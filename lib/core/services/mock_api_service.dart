import '../personas/persona.dart';
import 'api_service.dart';

class MockApiService extends ApiService {
  MockApiService(super.authService);

  @override
  Future<Map<String, dynamic>?> getProfile() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return {
      'id': 'mock-profile-id',
      'name': 'Minh Nguyen',
      'current_focus': 'preparing for internship interviews',
      'persona': {
        'id': 'alex',
        'name': 'Alex',
        'description': 'Senior software engineer from Singapore.',
        'voice': 'alloy',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> createProfile({
    required String name,
    required String personaId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final personas = await getPersonas();
    final persona = personas.firstWhere(
      (p) => p.id == personaId,
      orElse: () => throw Exception('unknown persona_id'),
    );
    return {
      'id': 'mock-profile-id',
      'name': name,
      'current_focus': '',
      'persona': {
        'id': persona.id,
        'name': persona.name,
        'description': persona.description,
        'voice': persona.voice,
      },
    };
  }

  @override
  Future<Persona> updatePersona(String personaId) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final personas = await getPersonas();
    return personas.firstWhere(
      (p) => p.id == personaId,
      orElse: () => throw Exception('Unknown persona'),
    );
  }

  @override
  Future<List<Persona>> getPersonas() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return const [
      Persona(
        id: 'alex',
        name: 'Alex',
        description: 'Senior software engineer from Singapore. Warm, '
            'practical, and loves walking through tech problems step by step.',
        voice: 'alloy',
      ),
      Persona(
        id: 'sarah',
        name: 'Sarah',
        description: 'Marketing manager at an FMCG company. Upbeat and '
            'full of real-world business examples.',
        voice: 'shimmer',
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>?> getQuota() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return {
      'remaining_seconds': 420,
      'total_seconds': 600,
      'membership_tier': 'free',
    };
  }

  @override
  Future<Map<String, dynamic>> redeemPromoCode(String code) async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (code.toUpperCase() == 'GOLD2024') {
      return {'membership_tier': 'gold', 'message': 'Upgraded to Gold'};
    }
    throw PromoRedeemException('invalid_code');
  }

  @override
  Future<List<Map<String, dynamic>>> getMemories() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return [
      {
        'id': 'mock-memory-id',
        'user_id': 'mock-user-id',
        'persona_id': 'alex',
        'session_id': 'mock-session-id',
        'summary': 'Talked about preparing for a software engineering internship at FPT.',
        'pending_followup': 'How did the mock interview go?',
        'created_at': '2026-04-04T00:00:00Z',
      },
    ];
  }
}
