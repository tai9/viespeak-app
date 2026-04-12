import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'core/services/filler_audio_service.dart';
import 'core/services/mock_realtime_service.dart';
import 'core/services/mock_voice_turn_service.dart';
import 'core/services/realtime_service.dart';
import 'core/services/session_service.dart';
import 'core/services/tts_chat_service.dart';
import 'core/services/voice_turn_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final isDev = Env.devMode;
  debugPrint('[VieSpeak] API_BASE_URL=${Env.apiBaseUrl}');

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  final BaseAuthService authService = AuthService();
  final apiService = ApiService(authService);
  final sessionService = SessionService(authService);
  final realtimeService = isDev ? MockRealtimeService() : RealtimeService();
  final ttsChatService = TtsChatService(authService);
  final VoiceTurnService voiceTurnService =
      isDev ? MockVoiceTurnService() : VoiceTurnService(authService);
  final fillerAudioService = FillerAudioService();
  // Warm the filler cache so "hmm..." / "let me think..." clips are in
  // memory by the time the user starts their first turn. Best-effort:
  // errors are swallowed inside the service.
  unawaited(fillerAudioService.preloadAll());

  runApp(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        apiServiceProvider.overrideWithValue(apiService),
        sessionServiceProvider.overrideWithValue(sessionService),
        realtimeServiceProvider.overrideWithValue(realtimeService),
        ttsChatServiceProvider.overrideWithValue(ttsChatService),
        voiceTurnServiceProvider.overrideWithValue(voiceTurnService),
        fillerAudioServiceProvider.overrideWithValue(fillerAudioService),
      ],
      child: const ViespeakApp(),
    ),
  );
}
