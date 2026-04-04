import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/conversation/conversation_screen.dart';
import '../../features/onboarding/major_selection_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
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
