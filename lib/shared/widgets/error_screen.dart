import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A full-screen friendly error view with a retry action.
///
/// Use this anywhere the app needs to show a non-recoverable error state
/// (API failures, timeouts, unexpected crashes, etc.).
class ErrorScreen extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const ErrorScreen({
    super.key,
    this.title = 'Something went wrong!',
    this.message = 'Please check your connection and try again.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.warmStone,
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.warmLift,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 36,
                    color: AppColors.warmGray,
                  ),
                ),
                const SizedBox(height: 32),

                // Title
                Text(
                  title,
                  style: AppTypography.cardHeading,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Message
                Text(
                  message,
                  style: AppTypography.bodyStandard.copyWith(
                    color: AppColors.darkGray,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Retry button
                if (onRetry != null)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.black,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: MaterialButton(
                        onPressed: onRetry,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          'Try again',
                          style: AppTypography.button.copyWith(
                            color: AppColors.white,
                          ),
                        ),
                      ),
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
