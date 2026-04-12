import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'voice_turn_service.dart';

/// Offline stand-in for [VoiceTurnService] used when `DEV_MODE=true`. Returns
/// a bundled MP3 (`assets/audio/mock_reply.mp3`) with canned transcripts and
/// fake `pipeline_ms` around 1200 ms so the filler-tier logic in
/// [VoiceTurnController] is still exercised in dev.
class MockVoiceTurnService implements VoiceTurnService {
  Uint8List? _cachedAudio;
  int _turnIndex = 0;

  static const List<_MockTurn> _canned = [
    _MockTurn(
      userText: "how's the weather today?",
      assistantText: 'Sunny and warm... pretty perfect for a walk.',
    ),
    _MockTurn(
      userText: 'tell me something interesting',
      assistantText: 'Octopuses have three hearts... wild, right?',
    ),
    _MockTurn(
      userText: 'what should I do this weekend?',
      assistantText: 'Honestly? Go find a good coffee and just wander.',
    ),
  ];

  @override
  Future<VoiceTurnResult> turn({
    required String sessionId,
    required String audioPath,
  }) async {
    _cachedAudio ??=
        (await rootBundle.load('assets/audio/mock_reply.mp3'))
            .buffer
            .asUint8List();
    // Simulate a realistic backend round-trip so the filler + adaptive
    // delay paths are meaningfully exercised.
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    final turn = _canned[_turnIndex % _canned.length];
    _turnIndex++;

    return VoiceTurnResult(
      audio: _cachedAudio!,
      userText: turn.userText,
      assistantText: turn.assistantText,
      pipelineMs: const VoicePipelineMs(
        stt: 350,
        llm: 450,
        rewrite: 150,
        tts: 250,
        total: 1200,
      ),
    );
  }
}

class _MockTurn {
  final String userText;
  final String assistantText;

  const _MockTurn({required this.userText, required this.assistantText});
}
