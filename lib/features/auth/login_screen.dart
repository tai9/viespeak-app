import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/utils/error_utils.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleEmailAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() => _loading = true);
    try {
      final auth = ref.read(authServiceProvider);
      if (_isSignUp) {
        await auth.signUp(email: email, password: password);
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/icon/app_icon.png',
                  width: 96,
                  height: 96,
                ),
                const SizedBox(height: 16),
                Text('VieSpeak', style: AppTypography.displayHero),
                const SizedBox(height: 12),
                Text(
                  'Practice English with AI companions',
                  style: AppTypography.body.copyWith(color: AppColors.darkGray),
                ),
                const SizedBox(height: 48),

                // Email field
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Email',
                    hintStyle: AppTypography.body.copyWith(color: AppColors.warmGray),
                    filled: true,
                    fillColor: AppColors.warmStoneSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.comfortable),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),

                // Password field
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: AppTypography.body.copyWith(color: AppColors.warmGray),
                    filled: true,
                    fillColor: AppColors.warmStoneSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.comfortable),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 20),

                // Sign in / Sign up button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: _PrimaryButton(
                    label: _isSignUp ? 'Sign up' : 'Sign in',
                    loading: _loading,
                    onPressed: _handleEmailAuth,
                  ),
                ),
                const SizedBox(height: 12),

                // Toggle sign in / sign up
                TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign in'
                        : "Don't have an account? Sign up",
                    style: AppTypography.caption.copyWith(color: AppColors.darkGray),
                  ),
                ),

                const SizedBox(height: 24),

                // Divider
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.borderSubtle)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'or',
                        style: AppTypography.caption.copyWith(color: AppColors.warmGray),
                      ),
                    ),
                    const Expanded(child: Divider(color: AppColors.borderSubtle)),
                  ],
                ),

                const SizedBox(height: 24),

                // Google sign-in button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: _GoogleSignInButton(
                    loading: _loading,
                    onPressed: _handleGoogleSignIn,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                : Text(
                    label,
                    style: AppTypography.button.copyWith(color: AppColors.white),
                  ),
          ),
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;

  const _GoogleSignInButton({
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppShadows.outlineRing,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Center(
            child: Text(
              'Continue with Google',
              style: AppTypography.button.copyWith(color: AppColors.black),
            ),
          ),
        ),
      ),
    );
  }
}
