import 'dart:math' as math;
import 'dart:typed_data';

class AudioLevelProcessor {
  double _smoothed = 0.0;
  final double alpha;

  AudioLevelProcessor({this.alpha = 0.3});

  /// Process PCM16 audio bytes and return a normalized 0.0-1.0 level
  /// with exponential moving average smoothing.
  double process(Uint8List pcm16Bytes) {
    final raw = _computeNormalizedRms(pcm16Bytes);
    _smoothed = alpha * raw + (1 - alpha) * _smoothed;
    return _smoothed.clamp(0.0, 1.0);
  }

  void reset() => _smoothed = 0.0;

  double _computeNormalizedRms(Uint8List pcm16Bytes) {
    if (pcm16Bytes.length < 2) return 0;

    final samples = pcm16Bytes.buffer.asInt16List(
      pcm16Bytes.offsetInBytes,
      pcm16Bytes.lengthInBytes ~/ 2,
    );

    double sumSquares = 0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / samples.length);
    // Normalize by max PCM16 amplitude and apply a scaling curve
    // to make typical speech volumes map to ~0.3-0.7 range
    return (rms / 32768.0 * 4.0).clamp(0.0, 1.0);
  }
}
