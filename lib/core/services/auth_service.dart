import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';

class AuthService extends ChangeNotifier {
  String? _token;
  Map<String, dynamic>? _user;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isSignedIn => _token != null;
  String get userName => _user?['name']?.toString().split(' ').first ?? 'there';

  @protected
  void setSession({required String token, required Map<String, dynamic> user}) {
    _token = token;
    _user = user;
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn(
      serverClientId: '', // TODO: add web client ID
    );
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in cancelled');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw Exception('No ID token from Google');
    }

    // Exchange Google ID token for backend session token
    final response = await http.post(
      Uri.parse('${Env.apiBaseUrl}/api/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );

    if (response.statusCode != 200) {
      throw Exception('Auth failed: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _token = data['token'] as String;
    _user = data['user'] as Map<String, dynamic>?;
    notifyListeners();
  }

  Future<void> signOut() async {
    _token = null;
    _user = null;
    notifyListeners();
  }
}
