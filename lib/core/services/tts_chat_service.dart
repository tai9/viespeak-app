import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../config/env.dart';
import 'api_service.dart';
import 'base_auth_service.dart';

/// Result of a `/tts/chat` call: MP3 audio bytes + the assistant's reply text.
class TtsChatResult {
  final Uint8List audioBytes;
  final String? assistantText;

  TtsChatResult({required this.audioBytes, this.assistantText});
}

/// Sentinel bytes appended before JSON metadata in the `/tts/chat` response.
/// ASCII: \x00\x00VIESPEAK_META\x00
const _sentinel = [
  0x00, 0x00, 0x56, 0x49, 0x45, 0x53, 0x50, 0x45, //
  0x41, 0x4B, 0x5F, 0x4D, 0x45, 0x54, 0x41, 0x00,
];

/// Calls the backend `/tts/chat` endpoint which streams LLM-generated TTS
/// audio (MP3) with trailing metadata containing the assistant's text.
///
/// The response body format:
/// ```
/// [MP3 audio bytes...] [sentinel] [JSON metadata]
/// ```
class TtsChatService {
  final BaseAuthService _authService;

  TtsChatService(this._authService);

  String get _baseUrl => Env.apiBaseUrl;

  /// POST `/tts/chat` — sends user text within a session, returns streamed
  /// MP3 audio + assistant text extracted from trailing metadata.
  ///
  /// [onAudioChunk] is called with each chunk as it arrives from the server,
  /// enabling real-time playback before the full response is received.
  Future<TtsChatResult> chat({
    required String sessionId,
    required String text,
    void Function(Uint8List chunk)? onAudioChunk,
  }) async {
    final uri = Uri.parse('$_baseUrl/tts/chat');
    debugPrint('[TtsChatService] POST $uri (session=$sessionId)');

    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      if (_authService.token != null) {
        request.headers.set('Authorization', 'Bearer ${_authService.token}');
      }
      request.write(jsonEncode({
        'session_id': sessionId,
        'text': text,
      }));

      final response = await request.close();
      debugPrint('[TtsChatService] response status: ${response.statusCode}');

      if (response.statusCode == 401) {
        debugPrint('[TtsChatService] 401 Unauthorized — signing out');
        _authService.signOut();
        throw SessionExpiredException();
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        final body = await response.transform(utf8.decoder).join();
        throw Exception('TTS chat failed (${response.statusCode}): $body');
      }

      final buffer = BytesBuilder(copy: false);
      await for (final chunk in response) {
        buffer.add(chunk);
        onAudioChunk?.call(Uint8List.fromList(chunk));
      }

      final rawBytes = buffer.toBytes();
      debugPrint(
        '[TtsChatService] raw response: ${rawBytes.length} bytes, '
        'first 32: ${rawBytes.take(32).toList()}',
      );

      final result = parseTtsResponse(rawBytes);
      debugPrint(
        '[TtsChatService] done — '
        'audio=${result.audioBytes.length} bytes, '
        'text=${result.assistantText?.length ?? 0} chars',
      );
      return result;
    } finally {
      client.close();
    }
  }
}

/// Splits a `/tts/chat` response body into MP3 audio and trailing JSON metadata.
///
/// If the sentinel is not found, the entire body is treated as audio (no metadata).
TtsChatResult parseTtsResponse(Uint8List body) {
  final sentinelIndex = _findSentinel(body);

  if (sentinelIndex == -1) {
    return TtsChatResult(audioBytes: body, assistantText: null);
  }

  final audio = Uint8List.sublistView(body, 0, sentinelIndex);
  final metaBytes = Uint8List.sublistView(
    body,
    sentinelIndex + _sentinel.length,
  );
  final meta = jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;

  return TtsChatResult(
    audioBytes: audio,
    assistantText: meta['assistant_text'] as String?,
  );
}

/// Searches for the sentinel from the end of [data] (most efficient since
/// the sentinel is always near the tail).
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
