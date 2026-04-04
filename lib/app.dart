import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/services/base_auth_service.dart';
import 'core/theme/app_theme.dart';

class ViespeakApp extends StatelessWidget {
  const ViespeakApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.read<BaseAuthService>();
    return MaterialApp.router(
      title: 'VieSpeak',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: appRouter(authService),
    );
  }
}
