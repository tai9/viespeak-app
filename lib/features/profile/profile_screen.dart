import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/personas/persona.dart';
import '../../core/providers/profile_providers.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/utils/date_utils.dart';
import '../../shared/utils/error_utils.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _signingOut = false;

  Future<void> _handleRefresh() async {
    HapticFeedback.selectionClick();
    ref.invalidate(profileProvider);
    ref.invalidate(quotaProvider);
    ref.invalidate(memoriesProvider);
    // Wait for all three to finish so the spinner stays visible until the
    // new data is actually on screen.
    await Future.wait([
      ref.read(profileProvider.future),
      ref.read(quotaProvider.future),
      ref.read(memoriesProvider.future),
    ]);
  }

  Future<void> _handleSignOut() async {
    HapticFeedback.lightImpact();
    setState(() => _signingOut = true);
    try {
      await ref.read(authServiceProvider).signOut();
      ref.invalidate(profileProvider);
      ref.invalidate(quotaProvider);
      ref.invalidate(memoriesProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _signingOut = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final quotaAsync = ref.watch(quotaProvider);
    final memoriesAsync = ref.watch(memoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Profile',
          style: AppTypography.nav.copyWith(color: AppColors.black),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.black),
          onPressed: () => context.pop(),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.borderSubtle),
        ),
      ),
      body: _buildBody(profileAsync, quotaAsync, memoriesAsync),
    );
  }

  Widget _buildBody(
    AsyncValue<Map<String, dynamic>?> profileAsync,
    AsyncValue<Map<String, dynamic>?> quotaAsync,
    AsyncValue<List<Map<String, dynamic>>> memoriesAsync,
  ) {
    // Error state still blocks the whole screen — nothing useful to show.
    if (profileAsync.hasError && !profileAsync.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Failed to load profile',
              style: AppTypography.body.copyWith(color: AppColors.warmGray),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.invalidate(profileProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Use cached values while loading so we render the real layout with
    // skeleton placeholders instead of a jarring full-screen spinner.
    final profile = profileAsync.valueOrNull;
    final quota = quotaAsync.valueOrNull;
    final profileLoading = profile == null && profileAsync.isLoading;
    final quotaLoading = quota == null && quotaAsync.isLoading;
    final personaName =
        (profile?['persona'] as Map<String, dynamic>?)?['name'] as String?;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _handleRefresh,
            color: AppColors.black,
            backgroundColor: AppColors.white,
            child: ListView(
              // AlwaysScrollable so the pull gesture works even when the
              // content fits the viewport (e.g. empty history).
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: profileLoading
                      ? const _SkeletonCard(height: 96)
                      : _buildProfileCard(profile),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: quotaLoading
                      ? const _SkeletonCard(height: 110)
                      : _buildQuotaCard(quota),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildSectionTitle('Conversation history'),
                ),
                const SizedBox(height: 12),
                _buildMemoriesSection(memoriesAsync, personaName),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: _buildSignOutButton(),
        ),
        const SizedBox(height: 12),
        _buildAppVersion(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildMemoriesSection(
    AsyncValue<List<Map<String, dynamic>>> memoriesAsync,
    String? personaName,
  ) {
    return memoriesAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: const [
            _SkeletonCard(height: 80),
            SizedBox(height: 12),
            _SkeletonCard(height: 80),
            SizedBox(height: 12),
            _SkeletonCard(height: 80),
          ],
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'Failed to load history',
            style: AppTypography.body.copyWith(color: AppColors.warmGray),
          ),
        ),
      ),
      data: (memories) {
        if (memories.isEmpty) {
          final emptyText = personaName != null
              ? 'Start your first conversation with $personaName!'
              : 'No conversations yet. Start talking!';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                emptyText,
                style: AppTypography.body.copyWith(color: AppColors.warmGray),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [for (final memory in memories) _buildMemoryCard(memory)],
          ),
        );
      },
    );
  }

  Widget _buildProfileCard(Map<String, dynamic>? profile) {
    final name = profile?['name'] as String? ?? 'Unknown';
    final persona = profile?['persona'] as Map<String, dynamic>?;
    final currentFocus = profile?['current_focus'] as String?;
    final personaId = persona?['id'] as String?;
    final companion = persona?['name'] as String? ?? 'Not set';
    final subtitle = (currentFocus != null && currentFocus.isNotEmpty)
        ? 'Companion: $companion · $currentFocus'
        : 'Companion: $companion';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: AppShadows.outlineRing,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openPersonaPicker(currentId: personaId),
          borderRadius: BorderRadius.circular(AppRadius.large),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.warmStoneSurface,
                    borderRadius: BorderRadius.circular(AppRadius.comfortable),
                    boxShadow: AppShadows.warmLift,
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: AppTypography.sectionHeading,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: AppTypography.bodyMedium),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.darkGray,
                        ),
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

  Future<void> _openPersonaPicker({required String? currentId}) async {
    // Block mid-call switches. The backend re-reads the persona at
    // SessionEnd, so a switch mid-session would attribute the resulting
    // memory to the new persona — not what the user expects. The call
    // screen also caches `sessionInit.persona` for its UI copy, which
    // would go stale. Safer to make them finish the current conversation.
    if (ref.read(realtimeServiceProvider).isConnected) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Finish your current conversation before switching.'),
        ),
      );
      return;
    }

    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<Persona>(
      context: context,
      backgroundColor: AppColors.white,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PersonaPickerSheet(currentId: currentId),
    );
    if (picked == null || picked.id == currentId) return;
    try {
      final api = ref.read(apiServiceProvider);
      await api.updatePersona(picked.id);
      // Memories are now persona-scoped server-side. Drop the cached list
      // so the history section reflects the new persona (usually empty on
      // first switch, which the empty state copy calls out).
      ref.invalidate(profileProvider);
      ref.invalidate(memoriesProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Switched to ${picked.name}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Widget _buildQuotaCard(Map<String, dynamic>? quota) {
    if (quota == null) {
      return const SizedBox.shrink();
    }

    final remainingSeconds = quota['remaining_seconds'] as int? ?? 0;
    final totalSeconds = quota['total_seconds'] as int? ?? 600;
    final sessionsToday = quota['sessions_today'] as int? ?? 0;
    final maxSessions = quota['max_sessions'] as int? ?? 1;
    final progress = totalSeconds > 0 ? remainingSeconds / totalSeconds : 0.0;
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    final timeText =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    final isLow = remainingSeconds < 60;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: AppShadows.outlineRing,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's quota", style: AppTypography.bodyMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: AppColors.borderSubtle,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isLow ? Colors.red.shade400 : AppColors.warmGray,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$timeText left',
                  style: AppTypography.caption.copyWith(
                    color: isLow ? Colors.red.shade400 : AppColors.darkGray,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$sessionsToday / $maxSessions sessions used today',
              style: AppTypography.caption.copyWith(color: AppColors.warmGray),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: AppTypography.bodyMedium);
  }

  Widget _buildMemoryCard(Map<String, dynamic> memory) {
    final summary = memory['summary'] as String? ?? '';
    final followup = memory['pending_followup'] as String?;
    final createdAt = memory['created_at'] as String? ?? '';
    final date = formatTimestamp(createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.outlineRing,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (date.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    date,
                    style: AppTypography.micro.copyWith(
                      color: AppColors.warmGray,
                    ),
                  ),
                ),
              Text(summary, style: AppTypography.bodyStandard),
              if (followup != null && followup.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Follow-up: $followup',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.darkGray,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignOutButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppShadows.outlineRing,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _signingOut ? null : _handleSignOut,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Center(
              child: _signingOut
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.black,
                      ),
                    )
                  : Text(
                      'Sign out',
                      style: AppTypography.button.copyWith(
                        color: AppColors.black,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppVersion() {
    return Center(
      child: Text(
        'VieSpeak v1.0.0',
        style: AppTypography.micro.copyWith(color: AppColors.warmGray),
      ),
    );
  }
}

/// Subtle pulsing placeholder that matches the real card dimensions so the
/// layout doesn't shift when data arrives.
class _SkeletonCard extends StatefulWidget {
  final double height;

  const _SkeletonCard({required this.height});

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        final t = _controller.value;
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              AppColors.warmStoneSurface,
              AppColors.nearWhite,
              t,
            ),
            borderRadius: BorderRadius.circular(AppRadius.large),
            boxShadow: AppShadows.outlineRing,
          ),
        );
      },
    );
  }
}

/// Bottom-sheet list of personas. Pops with the selected [Persona] on tap,
/// or `null` if the user dismisses the sheet.
class _PersonaPickerSheet extends ConsumerWidget {
  final String? currentId;

  const _PersonaPickerSheet({required this.currentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personasAsync = ref.watch(personasProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Switch companion', style: AppTypography.sectionHeading),
            const SizedBox(height: 16),
            personasAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Text(
                      friendlyError(error),
                      style: AppTypography.body.copyWith(
                        color: AppColors.warmGray,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => ref.invalidate(personasProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (personas) => Column(
                children: [
                  for (final p in personas) ...[
                    _PersonaPickerRow(
                      persona: p,
                      selected: p.id == currentId,
                      onTap: () => Navigator.of(context).pop(p),
                    ),
                    if (p != personas.last) const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonaPickerRow extends StatelessWidget {
  final Persona persona;
  final bool selected;
  final VoidCallback onTap;

  const _PersonaPickerRow({
    required this.persona,
    required this.selected,
    required this.onTap,
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
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.warmStoneSurface,
                    borderRadius: BorderRadius.circular(AppRadius.comfortable),
                    boxShadow: AppShadows.warmLift,
                  ),
                  child: Center(
                    child: Text(
                      persona.name.isNotEmpty
                          ? persona.name[0].toUpperCase()
                          : '?',
                      style: AppTypography.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(persona.name, style: AppTypography.bodyMedium),
                      const SizedBox(height: 4),
                      Text(
                        persona.description,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.darkGray,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 22,
                  color: selected ? AppColors.black : AppColors.warmGray,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
