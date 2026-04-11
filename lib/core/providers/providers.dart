import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import '../services/base_auth_service.dart';
import '../services/realtime_service.dart';
import '../services/session_service.dart';
import '../services/tts_chat_service.dart';

/// Auth service — provided as override from main()
final authServiceProvider = Provider<BaseAuthService>((ref) {
  throw UnimplementedError('authServiceProvider must be overridden');
});

/// Bridges the [BaseAuthService] ChangeNotifier into the Riverpod graph so
/// providers can `ref.watch` it and rebuild on sign-in / sign-out.
final authListenableProvider = ChangeNotifierProvider<BaseAuthService>((ref) {
  return ref.watch(authServiceProvider);
});

/// Current signed-in user id, or `null` when signed out. User-scoped
/// providers (profile, quota, memories) depend on this so Riverpod
/// refetches automatically whenever the account changes — otherwise the
/// old user's data survives the sign-out/sign-in transition.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authListenableProvider).userId;
});

/// API service — provided as override from main()
final apiServiceProvider = Provider<ApiService>((ref) {
  throw UnimplementedError('apiServiceProvider must be overridden');
});

/// Session service — provided as override from main()
final sessionServiceProvider = Provider<SessionService>((ref) {
  throw UnimplementedError('sessionServiceProvider must be overridden');
});

/// Realtime service — provided as override from main()
final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  throw UnimplementedError('realtimeServiceProvider must be overridden');
});

/// TTS chat service — provided as override from main()
final ttsChatServiceProvider = Provider<TtsChatService>((ref) {
  throw UnimplementedError('ttsChatServiceProvider must be overridden');
});
