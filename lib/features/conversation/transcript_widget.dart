import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class TranscriptEntry {
  final String speaker;
  final String text;
  final bool isFinalized;
  final DateTime timestamp;

  TranscriptEntry({
    required this.speaker,
    required this.text,
    this.isFinalized = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class TranscriptWidget extends StatelessWidget {
  final List<TranscriptEntry> entries;
  final ScrollController? scrollController;

  const TranscriptWidget({
    super.key,
    required this.entries,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];

        // System messages (e.g. memory context hints)
        if (entry.speaker == 'system') {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Text(
                entry.text,
                style: AppTypography.caption.copyWith(
                  color: AppColors.warmGray,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final isUser = entry.speaker == 'user';

        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isUser ? AppColors.warmStoneSurface : AppColors.nearWhite,
              borderRadius: BorderRadius.circular(AppRadius.card),
              boxShadow: isUser ? AppShadows.warmLift : AppShadows.insetEdge,
            ),
            child: Text(
              entry.text,
              style: AppTypography.bodyStandard.copyWith(
                color: entry.isFinalized ? AppColors.black : AppColors.darkGray,
              ),
            ),
          ),
        );
      },
    );
  }
}
