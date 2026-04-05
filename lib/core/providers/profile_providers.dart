import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../personas/persona.dart';
import 'providers.dart';

/// User profile data — fetched from backend. Keyed on the current user id
/// so the cached value is dropped whenever the user signs out or switches
/// accounts.
final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  final api = ref.read(apiServiceProvider);
  return api.getProfile();
});

/// Daily quota data. Keyed on the current user id.
final quotaProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  final api = ref.read(apiServiceProvider);
  return api.getQuota();
});

/// Conversation memory/history entries. Keyed on the current user id.
final memoriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];
  final api = ref.read(apiServiceProvider);
  return api.getMemories();
});

/// Catalog of personas the user can pick from. Rarely changes — Riverpod
/// keeps it cached in memory for the lifetime of the app session.
final personasProvider = FutureProvider<List<Persona>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.getPersonas();
});
