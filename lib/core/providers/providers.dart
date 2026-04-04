import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import '../services/base_auth_service.dart';
import '../services/realtime_service.dart';
import '../services/session_service.dart';

/// Auth service — provided as override from main()
final authServiceProvider = Provider<BaseAuthService>((ref) {
  throw UnimplementedError('authServiceProvider must be overridden');
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
