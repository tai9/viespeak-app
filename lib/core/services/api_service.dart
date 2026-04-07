import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../personas/persona.dart';
import 'base_auth_service.dart';

/// Thrown when any API call receives a 401 Unauthorized response,
/// indicating the session has expired.
class SessionExpiredException implements Exception {
  @override
  String toString() => 'Session expired — please sign in again.';
}

class ApiService {
  final BaseAuthService _authService;

  ApiService(this._authService);

  String get _baseUrl => Env.apiBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authService.token != null)
          'Authorization': 'Bearer ${_authService.token}',
      };

  /// Check for 401 and sign the user out automatically.
  void _checkUnauthorized(http.Response response) {
    if (response.statusCode == 401) {
      debugPrint('[ApiService] 401 Unauthorized — signing out');
      _authService.signOut();
      throw SessionExpiredException();
    }
  }

  /// GET /api/profile — unified profile object, or null if the user has
  /// not created one yet (backend returns 404 → route to onboarding).
  /// `profile['persona']` may be null if the stored persona_id is unset
  /// or points to a removed persona — callers should also treat that as
  /// "onboarding incomplete" and route to the picker.
  ///
  /// Throws on 5xx / network errors so Riverpod can surface a retry UI
  /// instead of silently pretending onboarding is incomplete.
  Future<Map<String, dynamic>?> getProfile() async {
    debugPrint('[ApiService] GET /api/profile');
    final response = await http.get(
      Uri.parse('$_baseUrl/api/profile'),
      headers: _headers,
    );
    debugPrint('[ApiService] /api/profile → ${response.statusCode}');
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (response.statusCode == 404) {
      return null;
    }
    throw Exception('Failed to load profile: ${response.statusCode}');
  }

  /// POST /api/profile — create or update profile with name and persona.
  /// Returns the enriched profile (same shape as GET /api/profile), so
  /// callers don't need to refetch.
  Future<Map<String, dynamic>> createProfile({
    required String name,
    required String personaId,
  }) async {
    debugPrint('[ApiService] POST /api/profile personaId=$personaId');
    final response = await http.post(
      Uri.parse('$_baseUrl/api/profile'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'persona_id': personaId,
      }),
    );
    debugPrint('[ApiService] /api/profile → ${response.statusCode}');
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (response.statusCode == 400) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] as String? ?? 'Invalid request');
    }
    throw Exception('Failed to save profile: ${response.statusCode}');
  }

  /// PUT /api/profile/persona — swap the user's active persona.
  /// Returns the newly selected persona.
  Future<Persona> updatePersona(String personaId) async {
    debugPrint('[ApiService] PUT /api/profile/persona id=$personaId');
    final response = await http.put(
      Uri.parse('$_baseUrl/api/profile/persona'),
      headers: _headers,
      body: jsonEncode({'persona_id': personaId}),
    );
    debugPrint('[ApiService] /api/profile/persona → ${response.statusCode}');
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return Persona.fromJson(body['persona'] as Map<String, dynamic>);
    }
    if (response.statusCode == 400) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] as String? ?? 'Invalid persona');
    }
    throw Exception('Failed to update persona: ${response.statusCode}');
  }

  /// GET /api/personas — catalog of AI companions the user can pick from.
  /// Rarely changes; cache locally via a Riverpod FutureProvider.
  Future<List<Persona>> getPersonas() async {
    debugPrint('[ApiService] GET /api/personas');
    final response = await http.get(
      Uri.parse('$_baseUrl/api/personas'),
      headers: _headers,
    );
    debugPrint('[ApiService] /api/personas → ${response.statusCode}');
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = body['personas'] as List<dynamic>;
      return list
          .map((e) => Persona.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load personas: ${response.statusCode}');
  }

  /// GET /session/quota — returns remaining quota for today
  Future<Map<String, dynamic>?> getQuota() async {
    debugPrint('[ApiService] GET /session/quota');
    final response = await http.get(
      Uri.parse('$_baseUrl/session/quota'),
      headers: _headers,
    );
    debugPrint(
      '[ApiService] /session/quota → ${response.statusCode} '
      'body=${response.body}',
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  /// GET /api/memories — returns list of memory entries
  Future<List<Map<String, dynamic>>> getMemories() async {
    debugPrint('[ApiService] GET /api/memories');
    final response = await http.get(
      Uri.parse('$_baseUrl/api/memories'),
      headers: _headers,
    );
    debugPrint(
      '[ApiService] /api/memories → ${response.statusCode} '
      '(${response.body.length} bytes)',
    );
    _checkUnauthorized(response);
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      debugPrint('[ApiService] memories parsed: ${list.length} entries');
      return list.cast<Map<String, dynamic>>();
    }
    return [];
  }
}
