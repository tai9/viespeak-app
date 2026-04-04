import 'api_service.dart';

class MockApiService extends ApiService {
  MockApiService(super.authService);

  @override
  Future<Map<String, dynamic>?> getProfile() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return {
      'id': 'mock-profile-id',
      'name': 'Minh Nguyen',
      'major': 'IT',
      'level': 'B1',
      'created_at': '2026-04-04T00:00:00Z',
    };
  }

  @override
  Future<void> createProfile({
    required String name,
    required String major,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<Map<String, dynamic>?> getQuota() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return {
      'remaining_seconds': 420,
      'total_seconds': 600,
      'sessions_today': 0,
      'max_sessions': 1,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getMemories() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return [
      {
        'id': 'mock-memory-id',
        'summary': 'Talked about preparing for a software engineering internship at FPT.',
        'facts': {'goal': 'internship at FPT', 'project': 'graduation thesis on microservices'},
        'pending_followup': 'How did the mock interview go?',
        'created_at': '2026-04-04T00:00:00Z',
      },
    ];
  }
}
