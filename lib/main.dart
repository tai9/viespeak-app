import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/services/api_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/mock_api_service.dart';
import 'core/services/mock_auth_service.dart';
import 'core/services/mock_ws_service.dart';
import 'core/services/ws_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final isDev = Env.devMode;
  final authService = isDev ? MockAuthService() : AuthService();
  final apiService = isDev ? MockApiService(authService) : ApiService(authService);
  final wsService = isDev ? MockWsService() : WsService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        Provider<ApiService>.value(value: apiService),
        Provider<WsService>.value(value: wsService),
      ],
      child: const ViespeakApp(),
    ),
  );
}
