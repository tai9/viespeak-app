import 'auth_service.dart';

class MockAuthService extends AuthService {
  @override
  Future<void> signInWithGoogle() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));
    setSession(
      token: 'mock-token-123',
      user: {
        'id': 'mock-user-id',
        'name': 'Minh Nguyen',
        'email': 'minh@example.com',
      },
    );
  }
}
