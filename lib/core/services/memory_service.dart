import 'package:supabase_flutter/supabase_flutter.dart';

class MemoryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> getLatestMemory(String userId) async {
    final response = await _supabase
        .from('memories')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    return response;
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final response = await _supabase
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();

    return response;
  }

  Future<void> upsertUserProfile({
    required String userId,
    required String name,
    required String major,
  }) async {
    await _supabase.from('users').upsert({
      'id': userId,
      'name': name,
      'major': major,
    });
  }
}
