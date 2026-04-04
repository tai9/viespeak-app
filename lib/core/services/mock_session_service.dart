import 'session_service.dart';

class MockSessionService extends SessionService {
  MockSessionService(super.authService);

  @override
  Future<SessionInitResult> getSessionInit() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return SessionInitResult(
      token: 'mock-ephemeral-token',
      remainingSeconds: 600,
      model: 'gpt-4o-mini-realtime-preview',
    );
  }

  @override
  Future<void> endSession({
    required List<Map<String, String>> transcript,
    required int durationSeconds,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
