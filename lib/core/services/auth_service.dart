import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'base_auth_service.dart';

class AuthService extends BaseAuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  StreamSubscription<AuthState>? _authSubscription;

  AuthService() {
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      notifyListeners();
    });
  }

  Session? get session => _supabase.auth.currentSession;
  User? get user => _supabase.auth.currentUser;

  @override
  String? get token => session?.accessToken;

  @override
  bool get isSignedIn => session != null;

  @override
  String get userName {
    final meta = user?.userMetadata;
    final fullName = meta?['full_name'] as String? ??
        meta?['name'] as String? ??
        user?.email?.split('@').first ??
        'there';
    return fullName.split(' ').first;
  }

  @override
  Future<void> signInWithGoogle() async {
    await _supabase.auth.signInWithOAuth(OAuthProvider.google);
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    await _supabase.auth.signUp(email: email, password: password);
  }

  @override
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
