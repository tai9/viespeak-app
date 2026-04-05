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

class QuotaExceededException implements Exception {
  final String resetAt;

  QuotaExceededException(this.resetAt);

  @override
  String toString() => 'Daily quota exceeded. Resets at $resetAt';
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
    final response = await http.get(
      Uri.parse('$_baseUrl/session/init'),
      headers: _headers,
    );

    if (response.statusCode == 403) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw QuotaExceededException(body['reset_at'] as String? ?? '');
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
