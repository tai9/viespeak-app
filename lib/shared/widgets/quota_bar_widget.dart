import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class QuotaBarWidget extends StatelessWidget {
  final int secondsRemaining;
  final int totalSeconds;

  const QuotaBarWidget({
    super.key,
    required this.secondsRemaining,
    required this.totalSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalSeconds > 0 ? secondsRemaining / totalSeconds : 0.0;
    final isLow = secondsRemaining < 60;
    final minutes = secondsRemaining ~/ 60;
    final seconds = secondsRemaining % 60;
    final timeText = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: AppColors.borderSubtle,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isLow ? Colors.red.shade400 : AppColors.warmGray,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$timeText remaining',
            style: AppTypography.caption.copyWith(
              color: isLow ? Colors.red.shade400 : AppColors.warmGray,
            ),
          ),
        ],
      ),
    );
  }
}
