import 'base_auth_service.dart';

class MockAuthService extends BaseAuthService {
  bool _isSignedIn = false;

  @override
  String? get token => _isSignedIn ? 'mock-token-123' : null;

  @override
  bool get isSignedIn => _isSignedIn;

  @override
  String get userName => _isSignedIn ? 'Minh' : 'there';

  @override
  Future<void> signInWithGoogle() async {
    await Future.delayed(const Duration(milliseconds: 800));
    _isSignedIn = true;
    notifyListeners();
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));
    _isSignedIn = true;
    notifyListeners();
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));
    _isSignedIn = true;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    _isSignedIn = false;
    notifyListeners();
  }
}
