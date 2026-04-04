import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/env.dart';
import 'base_auth_service.dart';

class SessionInitResult {
  final String token;
  final int remainingSeconds;
  final String model;

  SessionInitResult({
    required this.token,
    required this.remainingSeconds,
    required this.model,
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
    );
  }

  /// POST /session/end — send transcript and duration to backend
  Future<void> endSession({
    required List<Map<String, String>> transcript,
    required int durationSeconds,
  }) async {
    await http.post(
      Uri.parse('$_baseUrl/session/end'),
      headers: _headers,
      body: jsonEncode({
        'transcript': transcript,
        'duration_seconds': durationSeconds,
      }),
    );
  }
}
