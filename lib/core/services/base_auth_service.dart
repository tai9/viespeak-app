import 'package:flutter/foundation.dart';

abstract class BaseAuthService extends ChangeNotifier {
  String? get token;
  bool get isSignedIn;
  String get userName;

  /// Stable identifier for the currently signed-in user, or `null` when
  /// signed out. Used as a cache key for user-scoped Riverpod providers so
  /// they refetch automatically when the account changes.
  String? get userId;

  Future<void> signInWithGoogle();
  Future<void> signInWithPassword({required String email, required String password});
  Future<void> signUp({required String email, required String password});
  Future<void> signOut();
}
