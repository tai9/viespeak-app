import 'package:flutter/foundation.dart';

abstract class BaseAuthService extends ChangeNotifier {
  String? get token;
  bool get isSignedIn;
  String get userName;

  Future<void> signInWithGoogle();
  Future<void> signInWithPassword({required String email, required String password});
  Future<void> signUp({required String email, required String password});
  Future<void> signOut();
}
