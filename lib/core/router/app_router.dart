import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/conversation/conversation_screen.dart';
import '../../features/onboarding/persona_selection_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../providers/profile_providers.dart';
import '../services/base_auth_service.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

GoRouter appRouter(BaseAuthService authService) {
  return GoRouter(
    refreshListenable: authService,
    initialLocation: '/',
    redirect: (context, state) {
      final isSignedIn = authService.isSignedIn;
      final currentPath = state.matchedLocation;

      if (!isSignedIn) {
        return currentPath == '/login' ? null : '/login';
      }

      if (currentPath == '/login') {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const _ProfileGate(),
      ),
      GoRoute(
        path: '/select-persona',
        builder: (context, state) => const PersonaSelectionScreen(),
      ),
      GoRoute(
        path: '/conversation',
        builder: (context, state) => const ConversationScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
  );
}

/// Checks whether the user has picked a persona yet and routes accordingly.
/// A profile with a null `persona` object means onboarding isn't complete
/// (either never picked, or the stored id points to a removed persona).
class _ProfileGate extends ConsumerWidget {
  const _ProfileGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      loading: () => const SplashScreen(),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Error: $error')),
      ),
      data: (profile) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          // Onboarding is complete iff the profile exists AND carries a
          // resolved persona object. A null persona means the stored id is
          // missing or dangling — treat it as incomplete and re-pick.
          final persona = profile?['persona'] as Map<String, dynamic>?;
          if (profile != null && persona != null) {
            context.go('/conversation');
          } else {
            context.go('/select-persona');
          }
        });
        return const SplashScreen();
      },
    );
  }
}
