import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/memory_service.dart';
import '../../core/theme/app_theme.dart';

class MajorSelectionScreen extends StatefulWidget {
  const MajorSelectionScreen({super.key});

  @override
  State<MajorSelectionScreen> createState() => _MajorSelectionScreenState();
}

class _MajorSelectionScreenState extends State<MajorSelectionScreen> {
  final _memoryService = MemoryService();
  bool _loading = false;

  Future<void> _selectMajor(String major) async {
    setState(() => _loading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser!;
      await _memoryService.upsertUserProfile(
        userId: user.id,
        name: user.userMetadata?['full_name'] ?? '',
        major: major,
      );
      if (mounted) context.go('/conversation?major=$major');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'What do you study?',
                style: AppTypography.sectionHeading,
              ),
              const SizedBox(height: 12),
              Text(
                'Choose your major to get a personalized AI companion',
                style: AppTypography.body.copyWith(color: AppColors.darkGray),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 56),
              _MajorCard(
                title: 'IT',
                subtitle: 'Chat with Alex — Senior Software Engineer',
                icon: Icons.code_rounded,
                onTap: _loading ? null : () => _selectMajor('IT'),
              ),
              const SizedBox(height: 16),
              _MajorCard(
                title: 'Economics',
                subtitle: 'Chat with Sarah — Marketing Manager',
                icon: Icons.trending_up_rounded,
                onTap: _loading ? null : () => _selectMajor('Economics'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MajorCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const _MajorCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: AppShadows.outlineRing,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.large),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.warmStoneSurface,
                    borderRadius: BorderRadius.circular(AppRadius.comfortable),
                    boxShadow: AppShadows.warmLift,
                  ),
                  child: Icon(icon, size: 24, color: AppColors.black),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.bodyMedium),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: AppTypography.caption.copyWith(color: AppColors.darkGray),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: AppColors.warmGray,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
