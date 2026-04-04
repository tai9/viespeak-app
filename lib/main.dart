import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/providers/providers.dart';
import 'core/services/api_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/base_auth_service.dart';
import 'core/services/mock_realtime_service.dart';
import 'core/services/realtime_service.dart';
import 'core/services/session_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final isDev = Env.devMode;

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  final BaseAuthService authService = AuthService();
  final apiService = ApiService(authService);
  final sessionService = SessionService(authService);
  final realtimeService = isDev ? MockRealtimeService() : RealtimeService();

  runApp(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        apiServiceProvider.overrideWithValue(apiService),
        sessionServiceProvider.overrideWithValue(sessionService),
        realtimeServiceProvider.overrideWithValue(realtimeService),
      ],
      child: const ViespeakApp(),
    ),
  );
}
