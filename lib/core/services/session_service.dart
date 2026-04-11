import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../personas/persona.dart';
import 'api_service.dart';
import 'base_auth_service.dart';

/// The conversation mode returned by `/session/init`.
enum SessionMode { s2s, tts }

class SessionInitResult {
  final SessionMode mode;
  final int remainingSeconds;
  final Persona persona;

  /// Only present in S2S mode — ephemeral token for OpenAI Realtime API.
  final String? token;

  /// Only present in S2S mode — OpenAI model identifier.
  final String? model;

  /// Only present in TTS mode — identifies this session for `/tts/chat` and
  /// `/session/end` calls.
  final String? sessionId;

  SessionInitResult({
    required this.mode,
    required this.remainingSeconds,
    required this.persona,
    this.token,
    this.model,
    this.sessionId,
  });
}

/// Why the backend refused a `/session/init`. The API returns two distinct
/// 403 error codes and the FE shows different copy for each.
enum QuotaExceededReason {
  /// `daily_quota_exceeded` — user has burned through their daily seconds.
  minutesExhausted,

  /// `daily_session_limit_exceeded` — user hit `max_sessions` for today.
  sessionsExhausted,
}

class QuotaExceededException implements Exception {
  final String resetAt;
  final QuotaExceededReason reason;

  QuotaExceededException(this.resetAt, this.reason);

  @override
  String toString() =>
      'Quota exceeded (${reason.name}). Resets at $resetAt';
}

/// Thrown when `/session/init` returns 400 because the user has no profile
/// row yet. Callers should route to onboarding.
class ProfileNotFoundException implements Exception {
  @override
  String toString() => 'User profile not found — complete onboarding first.';
}

class SessionService {
  static const _timeout = Duration(seconds: 15);

  final BaseAuthService _authService;

  SessionService(this._authService);

  String get _baseUrl => Env.apiBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authService.token != null)
          'Authorization': 'Bearer ${_authService.token}',
      };

  /// GET /session/init — initializes a conversation session.
  ///
  /// The response contains a `mode` field (`"s2s"` or `"tts"`) that determines
  /// which conversation flow the client should use:
  /// - `s2s`: WebSocket to OpenAI Realtime API (response includes `token` + `model`)
  /// - `tts`: HTTP turn-based via `/tts/chat` (response includes `session_id`)
  Future<SessionInitResult> getSessionInit() async {
    debugPrint('[SessionService] GET /session/init');
    final response = await http.get(
      Uri.parse('$_baseUrl/session/init'),
      headers: _headers,
    ).timeout(_timeout);
    debugPrint('[SessionService] /session/init → ${response.statusCode}');

    if (response.statusCode == 401) {
      debugPrint('[SessionService] 401 Unauthorized — signing out');
      _authService.signOut();
      throw SessionExpiredException();
    }

    if (response.statusCode == 400) {
      throw ProfileNotFoundException();
    }

    if (response.statusCode == 403) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final code = body['error'] as String? ?? '';
      final reason = code == 'daily_session_limit_exceeded'
          ? QuotaExceededReason.sessionsExhausted
          : QuotaExceededReason.minutesExhausted;
      throw QuotaExceededException(
        body['reset_at'] as String? ?? '',
        reason,
      );
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to initialize session: ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final modeStr = body['mode'] as String? ?? 's2s';
    final mode = modeStr == 'tts' ? SessionMode.tts : SessionMode.s2s;

    return SessionInitResult(
      mode: mode,
      remainingSeconds: body['remaining_seconds'] as int,
      persona: Persona.fromJson(body['persona'] as Map<String, dynamic>),
      token: body['token'] as String?,
      model: body['model'] as String?,
      sessionId: body['session_id'] as String?,
    );
  }

  /// POST /session/end — send transcript and duration to backend.
  ///
  /// [sessionId] is required for TTS mode sessions so the backend can clean up
  /// the in-memory TTS session state.
  Future<void> endSession({
    required List<Map<String, String>> transcript,
    required int durationSeconds,
    String? sessionId,
  }) async {
    final url = '$_baseUrl/session/end';
    final payload = <String, dynamic>{
      'transcript': transcript,
      'duration_seconds': durationSeconds,
    };
    if (sessionId != null) {
      payload['session_id'] = sessionId;
    }
    final body = jsonEncode(payload);
    debugPrint(
      '[SessionService] POST $url '
      'transcript=${transcript.length} items, duration=${durationSeconds}s'
      '${sessionId != null ? ', session_id=$sessionId' : ''}',
    );
    debugPrint('[SessionService] request body: $body');
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: body,
      ).timeout(_timeout);
      debugPrint(
        '[SessionService] /session/end → ${response.statusCode} '
        'body=${response.body}',
      );
    } catch (e, st) {
      debugPrint('[SessionService] /session/end FAILED: $e');
      debugPrint('$st');
      rethrow;
    }
  }
}
