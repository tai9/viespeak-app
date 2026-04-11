import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

const _sampleRate = 24000;

class AudioService {
  AudioRecorder? _recorder;
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
    await stopMp3();
    if (_playerInitialized) {
      await _player!.stopPlayer();
    }
    if (_player != null) {
      await _player!.closePlayer();
    }
    _recorder?.dispose();
  }
}
