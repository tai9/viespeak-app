import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

const _sampleRate = 24000;
const _voiceSampleRate = 16000;

class AudioService {
  AudioRecorder? _recorder;
  // Separate recorder for the /tts/voice voice-in path. We stream PCM16
  // via AVAudioEngine (same path S2S uses — this is the one that actually
  // works on iOS) and wrap the bytes in a WAV container on stop. An
  // earlier iteration used file-mode AAC-LC via AVAudioRecorder, but that
  // returned dead air (-120 dBFS) on device — `RecorderFileDelegate` also
  // silently ignores the echoCancel/noiseSuppress/autoGain flags.
  AudioRecorder? _voiceRecorder;
  String? _voiceRecordingPath;
  StreamSubscription<Uint8List>? _voiceStreamSub;
  BytesBuilder? _voiceBuffer;
  FlutterSoundPlayer? _player;
  bool _playerInitialized = false;
  // Cached init future so concurrent callers all await the same
  // openPlayer()/startPlayerFromStream() instead of each kicking off a
  // fresh (racing) init and dropping chunks in the middle of playback.
  Future<void>? _initFuture;
  // Serializes feedUint8FromStream calls so chunks are delivered in order.
  Future<void> _playChain = Future.value();

  /// Stream of PCM16 audio chunks from the microphone
  Stream<Uint8List>? micStream;

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> startRecording() async {
    final granted = await requestPermission();
    if (!granted) {
      throw Exception('Microphone permission denied');
    }

    _recorder ??= AudioRecorder();
    final stream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        bitRate: _sampleRate * 16,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
    );

    micStream = stream.map((data) => Uint8List.fromList(data));
  }

  Future<void> stopRecording() async {
    await _recorder?.stop();
    micStream = null;
  }

  /// Start recording a single voice-in turn to a temporary wav file.
  ///
  /// Used by `VoiceTurnController` / `/tts/voice` — the client records a
  /// complete user utterance, ships the file to the backend, and waits for
  /// a single MP3 reply.
  ///
  /// Uses stream mode (PCM16 via `AVAudioEngine` on iOS / the Android
  /// equivalent) and wraps the raw bytes in a RIFF/WAVE header on stop.
  /// This is the same capture path the S2S mode uses successfully; the
  /// file-mode alternative (`AVAudioRecorder` + AAC-LC) returns silent
  /// audio on iOS and silently ignores voice-processing flags.
  ///
  /// Returns the absolute file path that will be written on
  /// [stopVoiceRecording].
  Future<String> startVoiceRecording() async {
    final granted = await requestPermission();
    if (!granted) {
      throw Exception('Microphone permission denied');
    }

    // Fresh recorder per turn keeps state simple and lets us reuse the
    // _voiceRecordingPath slot without worrying about leftover buffers
    // from a previous turn.
    await _voiceStreamSub?.cancel();
    _voiceStreamSub = null;
    await _voiceRecorder?.dispose();
    _voiceRecorder = AudioRecorder();
    _voiceBuffer = BytesBuilder(copy: false);

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    _voiceRecordingPath = path;

    final stream = await _voiceRecorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _voiceSampleRate,
        numChannels: 1,
        bitRate: _voiceSampleRate * 16,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
    );

    _voiceStreamSub = stream.listen(
      (chunk) => _voiceBuffer?.add(chunk),
      onError: (Object e) =>
          debugPrint('[AudioService] voice stream error: $e'),
    );

    debugPrint('[AudioService] voice recording (PCM16→WAV) → $path');
    return path;
  }

  /// Stops the in-progress voice recording, wraps the captured PCM16
  /// buffer in a WAV container, writes it to disk, and returns its path.
  /// Returns `null` if nothing was recording.
  Future<String?> stopVoiceRecording() async {
    if (_voiceRecorder == null) return null;
    await _voiceStreamSub?.cancel();
    _voiceStreamSub = null;
    try {
      await _voiceRecorder!.stop();
    } catch (e) {
      debugPrint('[AudioService] voice stop error: $e');
    }
    final pcm = _voiceBuffer?.takeBytes() ?? Uint8List(0);
    _voiceBuffer = null;
    final path = _voiceRecordingPath;
    _voiceRecordingPath = null;
    if (path == null) return null;
    try {
      final wav = _buildWavFile(
        pcm16: pcm,
        sampleRate: _voiceSampleRate,
        numChannels: 1,
      );
      await File(path).writeAsBytes(wav, flush: true);
      debugPrint(
        '[AudioService] voice recording stopped '
        '(pcm=${pcm.length}B wav=${wav.length}B) → $path',
      );
    } catch (e) {
      debugPrint('[AudioService] WAV write failed: $e');
    }
    return path;
  }

  /// Wraps a little-endian PCM16 buffer in a 44-byte RIFF/WAVE header.
  /// The `record` package gives us raw samples from stream mode; the
  /// backend expects a self-describing audio file, so we package it here
  /// before upload.
  static Uint8List _buildWavFile({
    required Uint8List pcm16,
    required int sampleRate,
    required int numChannels,
  }) {
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = pcm16.length;
    final fileSize = 36 + dataSize;

    final b = BytesBuilder(copy: false);
    b.add(const [0x52, 0x49, 0x46, 0x46]); // "RIFF"
    b.add(_u32le(fileSize));
    b.add(const [0x57, 0x41, 0x56, 0x45]); // "WAVE"
    b.add(const [0x66, 0x6d, 0x74, 0x20]); // "fmt "
    b.add(_u32le(16)); // PCM fmt chunk size
    b.add(_u16le(1)); // format = PCM
    b.add(_u16le(numChannels));
    b.add(_u32le(sampleRate));
    b.add(_u32le(byteRate));
    b.add(_u16le(blockAlign));
    b.add(_u16le(bitsPerSample));
    b.add(const [0x64, 0x61, 0x74, 0x61]); // "data"
    b.add(_u32le(dataSize));
    b.add(pcm16);
    return b.toBytes();
  }

  static List<int> _u32le(int v) => [
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ];

  static List<int> _u16le(int v) => [v & 0xff, (v >> 8) & 0xff];

  /// Amplitude updates for the in-progress voice recording, sampled at
  /// [interval]. Used by `VoiceTurnController` as a simple amplitude-based
  /// VAD. Returns an empty stream if no voice recording is active.
  Stream<Amplitude> voiceAmplitudeStream({
    Duration interval = const Duration(milliseconds: 100),
  }) {
    final r = _voiceRecorder;
    if (r == null) return const Stream.empty();
    return r.onAmplitudeChanged(interval);
  }

  /// Pause the hardware mic. The stream stays subscribed but stops emitting
  /// bytes, so nothing can be forwarded to OpenAI while the AI is speaking.
  Future<void> pauseRecording() async {
    if (_recorder == null) return;
    if (!await _recorder!.isRecording()) return;
    if (await _recorder!.isPaused()) return;
    await _recorder!.pause();
  }

  /// Resume the hardware mic. No-op if we're not actually paused.
  Future<void> resumeRecording() async {
    if (_recorder == null) return;
    if (!await _recorder!.isPaused()) return;
    await _recorder!.resume();
  }

  /// Idempotent, concurrent-safe player init. Call this eagerly (e.g. from
  /// ConversationController.start) so the first audio chunk doesn't race
  /// an async openPlayer().
  Future<void> initPlayer() {
    if (_playerInitialized) return Future.value();
    return _initFuture ??= _doInitPlayer();
  }

  Future<void> _doInitPlayer() async {
    _player ??= FlutterSoundPlayer(logLevel: Level.error);
    await _player!.openPlayer();
    await _player!.startPlayerFromStream(
      codec: Codec.pcm16,
      sampleRate: _sampleRate,
      numChannels: 1,
      interleaved: true,
      bufferSize: 8192,
    );
    _playerInitialized = true;
  }

  /// Feed PCM16 audio bytes to the speaker. Calls are serialized through
  /// a single future chain so chunks are fed to flutter_sound strictly in
  /// arrival order — feeding concurrently drops samples mid-sentence.
  Future<void> playAudioChunk(Uint8List pcm16Bytes) {
    final next = _playChain.then((_) async {
      if (!_playerInitialized) await initPlayer();
      await _player!.feedUint8FromStream(pcm16Bytes);
    });
    // Swallow errors on the chain itself so one bad chunk doesn't poison
    // every subsequent play — but still surface them to the caller.
    _playChain = next.catchError((_) {});
    return next;
  }

  /// Stop audio playback (e.g. when user interrupts)
  Future<void> stopPlayback() async {
    if (!_playerInitialized) return;
    await _player!.stopPlayer();
    _playerInitialized = false;
    _initFuture = null;
    _playChain = Future.value();
  }

  /// Play a complete MP3 buffer (e.g. from the /tts/chat endpoint).
  ///
  /// Unlike [playAudioChunk] (which feeds a PCM16 stream), this starts a
  /// one-shot playback of a fully-buffered MP3 and returns a future that
  /// completes when playback finishes or is stopped.
  Future<void> playMp3(Uint8List mp3Bytes) async {
    debugPrint('[AudioService] playMp3: ${mp3Bytes.length} bytes');
    // Stop any in-progress PCM stream playback first.
    if (_playerInitialized) {
      await stopPlayback();
    }
    // Stop any previous MP3 playback that might still be active.
    await stopMp3();

    _player = FlutterSoundPlayer(logLevel: Level.error);
    await _player!.openPlayer();
    debugPrint('[AudioService] playMp3: player opened');
    final completer = Completer<void>();
    await _player!.startPlayer(
      fromDataBuffer: mp3Bytes,
      codec: Codec.mp3,
      whenFinished: () {
        debugPrint('[AudioService] playMp3: whenFinished callback');
        if (!completer.isCompleted) completer.complete();
      },
    );
    debugPrint('[AudioService] playMp3: startPlayer called');
    _mp3Completer = completer;
    await completer.future;
    _mp3Completer = null;
    await _player!.closePlayer();
    _player = null;
    debugPrint('[AudioService] playMp3: done, player closed');
  }

  Completer<void>? _mp3Completer;

  /// Stop MP3 playback if active.
  Future<void> stopMp3() async {
    if (_mp3Completer != null && !_mp3Completer!.isCompleted) {
      await _player?.stopPlayer();
      _mp3Completer!.complete();
      _mp3Completer = null;
      await _player?.closePlayer();
      _player = null;
    }
  }

  Future<void> dispose() async {
    await stopRecording();
    await stopVoiceRecording();
    await stopMp3();
    if (_playerInitialized) {
      await _player!.stopPlayer();
    }
    if (_player != null) {
      await _player!.closePlayer();
    }
    _recorder?.dispose();
    _voiceRecorder?.dispose();
  }
}
