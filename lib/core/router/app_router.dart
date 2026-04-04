import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/login_screen.dart';
import '../../features/conversation/conversation_screen.dart';
import '../../features/onboarding/major_selection_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final isLoggedIn = session != null;
    final isOnLogin = state.matchedLocation == '/';

    if (!isLoggedIn && !isOnLogin) return '/';
    if (isLoggedIn && isOnLogin) return '/select-major';
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/select-major',
      builder: (context, state) => const MajorSelectionScreen(),
    ),
    GoRoute(
      path: '/conversation',
      builder: (context, state) {
        final major = state.uri.queryParameters['major'] ?? 'IT';
        return ConversationScreen(major: major);
      },
    ),
  ],
);
