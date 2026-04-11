import '../personas/persona.dart';
import 'session_service.dart';

class MockSessionService extends SessionService {
  MockSessionService(super.authService);

  @override
  Future<SessionInitResult> getSessionInit() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return SessionInitResult(
      mode: SessionMode.s2s,
      remainingSeconds: 600,
      persona: const Persona(
        id: 'alex',
        name: 'Alex',
        description: 'Senior software engineer from Singapore.',
        voice: 'alloy',
      ),
      token: 'mock-ephemeral-token',
      model: 'gpt-4o-mini-realtime-preview',
    );
  }

  @override
  Future<void> endSession({
    required List<Map<String, String>> transcript,
    required int durationSeconds,
    String? sessionId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
