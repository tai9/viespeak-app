import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// User profile data — fetched from backend
final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getProfile();
});

/// Daily quota data
final quotaProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getQuota();
});

/// Conversation memory/history entries
final memoriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getMemories();
});
