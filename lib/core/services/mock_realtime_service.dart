import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'realtime_service.dart';

/// Mock realtime service that enables real mic input with simple
/// voice activity detection (VAD) — no OpenAI connection needed.
class MockRealtimeService extends RealtimeService {
  Timer? _silenceTimer;
  bool _speaking = false;

  // Simple energy-based VAD threshold (RMS of PCM16 samples)
  static const _vadThreshold = 500;
  static const _silenceTimeout = Duration(milliseconds: 800);

  @override
  Future<void> connect({
    required String token,
    required String model,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    debugPrint('[MockRealtime] Connected (dev mode — mic only, no AI)');
  }

  @override
  void sendSessionUpdate() {
    Future.delayed(const Duration(milliseconds: 100), () {
      sessionReadyController.add(null);
    });
  }

  @override
  void sendAudio(Uint8List pcm16Bytes) {
    // Simple energy-based voice activity detection
    final rms = _computeRms(pcm16Bytes);

    if (rms > _vadThreshold) {
      _silenceTimer?.cancel();

      if (!_speaking) {
        _speaking = true;
        speechStartedController.add(null);
        debugPrint('[MockRealtime] Speech started (RMS: ${rms.toStringAsFixed(0)})');
      }

      // Reset silence timer
      _silenceTimer = Timer(_silenceTimeout, () {
        if (_speaking) {
          _speaking = false;
          speechStoppedController.add(null);
          userTranscriptController.add('[dev mode] speech detected');
          debugPrint('[MockRealtime] Speech stopped');
        }
      });
    }
  }

  /// Compute RMS (root mean square) energy of PCM16 audio buffer
  double _computeRms(Uint8List pcm16Bytes) {
    if (pcm16Bytes.length < 2) return 0;

    final samples = pcm16Bytes.buffer.asInt16List(
      pcm16Bytes.offsetInBytes,
      pcm16Bytes.lengthInBytes ~/ 2,
    );

    double sumSquares = 0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / samples.length);
  }

  @override
  void cancelResponse() {
    // no-op — no AI responses in dev mode
  }

  @override
  void disconnect() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _speaking = false;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
