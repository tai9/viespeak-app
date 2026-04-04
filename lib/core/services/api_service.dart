import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/env.dart';
import 'base_auth_service.dart';

class ApiService {
  final BaseAuthService _authService;

  ApiService(this._authService);

  String get _baseUrl => Env.apiBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authService.token != null)
          'Authorization': 'Bearer ${_authService.token}',
      };

  /// GET /api/profile — returns list of profiles (empty if none exists)
  Future<Map<String, dynamic>?> getProfile() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/profile'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      if (list.isNotEmpty) {
        return list.first as Map<String, dynamic>;
      }
    }
    return null;
  }

  /// POST /api/profile — create or update profile with name and major
  Future<void> createProfile({
    required String name,
    required String major,
  }) async {
    await http.post(
      Uri.parse('$_baseUrl/api/profile'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'major': major,
      }),
    );
  }

  /// GET /session/quota — returns remaining quota for today
  Future<Map<String, dynamic>?> getQuota() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/session/quota'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  /// GET /api/memories — returns list of memory entries
  Future<List<Map<String, dynamic>>> getMemories() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/memories'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    }
    return [];
  }
}
