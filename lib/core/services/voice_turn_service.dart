import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import 'api_service.dart';
import 'base_auth_service.dart';

/// Backend pipeline timing breakdown for a single `/tts/voice` turn.
class VoicePipelineMs {
  final int stt;
  final int llm;
  final int rewrite;
  final int tts;
  final int total;

  const VoicePipelineMs({
    required this.stt,
    required this.llm,
    required this.rewrite,
    required this.tts,
    required this.total,
  });
}

/// Result of a `/tts/voice` turn: the full MP3 reply plus the STT and LLM
/// transcripts and the backend-measured latency breakdown.
class VoiceTurnResult {
  final Uint8List audio;
  final String userText;
  final String assistantText;
  final VoicePipelineMs pipelineMs;

  const VoiceTurnResult({
    required this.audio,
    required this.userText,
    required this.assistantText,
    required this.pipelineMs,
  });
}

/// Thrown when `/tts/voice` returns 404 — the session expired on the
/// backend. Caller should re-run `/session/init`.
class VoiceSessionNotFoundException implements Exception {
  @override
  String toString() => 'Session not found — please restart the conversation.';
}

/// Thrown when `/tts/voice` returns 422 — STT produced no text. This is a
/// recoverable, turn-scoped error; the UI should nudge the user to try
/// again without appending a transcript entry.
class VoiceTranscriptionEmptyException implements Exception {
  @override
  String toString() => "Didn't catch that — try again.";
}

/// Sentinel bytes prepended to the JSON metadata trailer at the end of the
/// `/tts/voice` response body. ASCII: `\x00\x00VIESPEAK_META\x00`.
const _sentinel = [
  0x00, 0x00, 0x56, 0x49, 0x45, 0x53, 0x50, 0x45, //
  0x41, 0x4B, 0x5F, 0x4D, 0x45, 0x54, 0x41, 0x00,
];

/// HTTP client for `POST /tts/voice` — the canonical voice-in path described
/// in `viespeak-be/docs/FE-Voice-Integration.md`.
///
/// Unlike `TtsChatService`, input is a recorded audio file uploaded as
/// multipart/form-data. The response body is a binary chunked stream:
///
/// ```
/// [MP3 audio bytes] [sentinel] [JSON metadata]
/// ```
///
/// Metadata carries `user_text` (STT transcript), `assistant_text` (the
/// plain LLM reply — not the expressive rewrite) and `pipeline_ms` timings.
class VoiceTurnService {
  final BaseAuthService _authService;

  VoiceTurnService(this._authService);

  String get _baseUrl => Env.apiBaseUrl;

  /// POST `/tts/voice` — uploads the recording at [audioPath] under
  /// [sessionId] and returns the parsed [VoiceTurnResult].
  Future<VoiceTurnResult> turn({
    required String sessionId,
    required String audioPath,
  }) async {
    final uri = Uri.parse('$_baseUrl/tts/voice');
    debugPrint('[VoiceTurnService] POST $uri (session=$sessionId)');

    final request = http.MultipartRequest('POST', uri)
      ..fields['session_id'] = sessionId
      ..files.add(await http.MultipartFile.fromPath('audio', audioPath));

    if (_authService.token != null) {
      request.headers['Authorization'] = 'Bearer ${_authService.token}';
    }

    final streamed = await request.send();
    debugPrint(
      '[VoiceTurnService] response status: ${streamed.statusCode}',
    );

    if (streamed.statusCode == 401) {
      debugPrint('[VoiceTurnService] 401 — signing out');
      _authService.signOut();
      throw SessionExpiredException();
    }

    if (streamed.statusCode == 404) {
      await streamed.stream.drain<void>();
      throw VoiceSessionNotFoundException();
    }

    if (streamed.statusCode == 422) {
      await streamed.stream.drain<void>();
      throw VoiceTranscriptionEmptyException();
    }

    // Accept any 2xx. NestJS `@Post()` returns 201 by default, and the
    // body is binary `[MP3][sentinel][JSON]` — trying to `bytesToString()`
    // it here blows up in UTF-8 decode on the MP3 header, masking the
    // real (successful) response as a `FormatException`.
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final body = await streamed.stream.bytesToString();
      throw HttpException(
        'voice turn failed (${streamed.statusCode}): $body',
      );
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream) {
      builder.add(chunk);
    }
    final rawBytes = builder.toBytes();
    debugPrint(
      '[VoiceTurnService] raw response: ${rawBytes.length} bytes',
    );

    return parseVoiceResponse(rawBytes);
  }
}

/// Splits a `/tts/voice` response body into MP3 audio and trailing metadata.
///
/// Throws [StateError] if the sentinel is missing — unlike `/tts/chat`,
/// `/tts/voice` always returns metadata, so the absence is a protocol bug
/// worth surfacing.
VoiceTurnResult parseVoiceResponse(Uint8List body) {
  final idx = _findSentinel(body);
  if (idx == -1) {
    throw StateError('No metadata sentinel in /tts/voice response');
  }

  final audio = Uint8List.sublistView(body, 0, idx);
  final metaBytes =
      Uint8List.sublistView(body, idx + _sentinel.length);
  final meta = jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
  final ms = (meta['pipeline_ms'] as Map).cast<String, dynamic>();

  return VoiceTurnResult(
    audio: audio,
    userText: meta['user_text'] as String? ?? '',
    assistantText: meta['assistant_text'] as String? ?? '',
    pipelineMs: VoicePipelineMs(
      stt: (ms['stt'] as num?)?.toInt() ?? 0,
      llm: (ms['llm'] as num?)?.toInt() ?? 0,
      rewrite: (ms['rewrite'] as num?)?.toInt() ?? 0,
      tts: (ms['tts'] as num?)?.toInt() ?? 0,
      total: (ms['total'] as num?)?.toInt() ?? 0,
    ),
  );
}

/// Scans for the sentinel from the tail of [data] — the sentinel is always
/// within a few hundred bytes of the end so tail-first scanning is O(1)
/// amortized on typical payloads.
int _findSentinel(Uint8List data) {
  if (data.length < _sentinel.length) return -1;
  outer:
  for (var i = data.length - _sentinel.length; i >= 0; i--) {
    for (var j = 0; j < _sentinel.length; j++) {
      if (data[i + j] != _sentinel[j]) continue outer;
    }
    return i;
  }
  return -1;
}
