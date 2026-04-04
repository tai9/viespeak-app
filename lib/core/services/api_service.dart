import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/env.dart';
import 'auth_service.dart';

class ApiService {
  final AuthService _authService;

  ApiService(this._authService);

  String get _baseUrl => Env.apiBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authService.token != null)
          'Authorization': 'Bearer ${_authService.token}',
      };

  Future<Map<String, dynamic>?> getLatestMemory(String userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/memory/$userId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/users/$userId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  Future<void> upsertUserProfile({
    required String userId,
    required String name,
    required String major,
  }) async {
    await http.put(
      Uri.parse('$_baseUrl/api/users/$userId'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'major': major,
      }),
    );
  }
}
