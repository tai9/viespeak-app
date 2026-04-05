import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../personas/persona.dart';
import 'base_auth_service.dart';

class SessionInitResult {
  final String token;
  final int remainingSeconds;
  final String model;
  final Persona persona;

  SessionInitResult({
    required this.token,
    required this.remainingSeconds,
    required this.model,
    required this.persona,
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
  final BaseAuthService _authService;

  SessionService(this._authService);

  String get _baseUrl => Env.apiBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authService.token != null)
          'Authorization': 'Bearer ${_authService.token}',
      };

  /// GET /session/init — get ephemeral token for OpenAI Realtime API
  Future<SessionInitResult> getSessionInit() async {
    debugPrint('[SessionService] GET /session/init');
    final response = await http.get(
      Uri.parse('$_baseUrl/session/init'),
      headers: _headers,
    );
    debugPrint('[SessionService] /session/init → ${response.statusCode}');

    if (response.statusCode == 400) {
      // Backend returns this when the user has no profile row. Route to
      // onboarding instead of showing a generic error.
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
    return SessionInitResult(
      token: body['token'] as String,
      remainingSeconds: body['remaining_seconds'] as int,
      model: body['model'] as String,
      persona: Persona.fromJson(body['persona'] as Map<String, dynamic>),
    );
  }

  /// POST /session/end — send transcript and duration to backend
  Future<void> endSession({
    required List<Map<String, String>> transcript,
    required int durationSeconds,
  }) async {
    final url = '$_baseUrl/session/end';
    final body = jsonEncode({
      'transcript': transcript,
      'duration_seconds': durationSeconds,
    });
    debugPrint(
      '[SessionService] POST $url '
      'transcript=${transcript.length} items, duration=${durationSeconds}s',
    );
    debugPrint('[SessionService] request body: $body');
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: body,
      );
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
