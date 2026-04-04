import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/auth/login_screen.dart';
import '../../features/conversation/conversation_screen.dart';
import '../../features/onboarding/major_selection_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../services/api_service.dart';
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
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
  );
}

/// Checks if user has a profile, routes to major selection or conversation
class _ProfileGate extends StatefulWidget {
  const _ProfileGate();

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    final api = context.read<ApiService>();
    final profile = await api.getProfile();

    if (!mounted) return;

    if (profile != null) {
      final major = profile['major'] as String? ?? 'IT';
      context.go('/conversation?major=$major');
    } else {
      context.go('/select-major');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}
