import 'api_service.dart';

class MockApiService extends ApiService {
  MockApiService(super.authService);

  @override
  Future<Map<String, dynamic>?> getLatestMemory(String userId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return {
      'summary': 'Talked about preparing for a software engineering internship at FPT.',
      'facts': {'goal': 'internship at FPT', 'project': 'graduation thesis on microservices'},
      'pending_followup': 'How did the mock interview go?',
    };
  }

  @override
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return {
      'id': userId,
      'name': 'Minh Nguyen',
      'major': 'IT',
      'level': 'B1',
    };
  }

  @override
  Future<void> upsertUserProfile({
    required String userId,
    required String name,
    required String major,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
