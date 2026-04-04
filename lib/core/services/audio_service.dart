import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

const _sampleRate = 24000;

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  FlutterSoundPlayer? _player;
  bool _playerInitialized = false;

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

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        bitRate: _sampleRate * 16,
      ),
    );

    micStream = stream.map((data) => Uint8List.fromList(data));
  }

  Future<void> stopRecording() async {
    await _recorder.stop();
    micStream = null;
  }

  Future<void> initPlayer() async {
    if (_playerInitialized) return;
    _player ??= FlutterSoundPlayer();
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

  /// Feed PCM16 audio bytes to the speaker
  Future<void> playAudioChunk(Uint8List pcm16Bytes) async {
    if (!_playerInitialized) await initPlayer();
    await _player!.feedUint8FromStream(pcm16Bytes);
  }

  /// Stop audio playback (e.g. when user interrupts)
  Future<void> stopPlayback() async {
    if (!_playerInitialized) return;
    await _player!.stopPlayer();
    _playerInitialized = false;
  }

  Future<void> dispose() async {
    await stopRecording();
    if (_playerInitialized) {
      await _player!.stopPlayer();
    }
    if (_player != null) {
      await _player!.closePlayer();
    }
    _recorder.dispose();
  }
}
