import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/personas/persona.dart';
import '../../core/providers/profile_providers.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/utils/error_utils.dart';

class PersonaSelectionScreen extends ConsumerStatefulWidget {
  const PersonaSelectionScreen({super.key});

  @override
  ConsumerState<PersonaSelectionScreen> createState() =>
      _PersonaSelectionScreenState();
}

class _PersonaSelectionScreenState
    extends ConsumerState<PersonaSelectionScreen> {
  String? _submittingId;

  Future<void> _selectPersona(Persona persona) async {
    if (_submittingId != null) return;
    HapticFeedback.mediumImpact();
    setState(() => _submittingId = persona.id);
    try {
      final auth = ref.read(authServiceProvider);
      final api = ref.read(apiServiceProvider);
      // POST /api/profile returns the enriched profile — no refetch needed.
      await api.createProfile(name: auth.userName, personaId: persona.id);
      if (mounted) {
        // Still invalidate so any widget listening to profileProvider sees
        // the new state. The next read hits the cache-bust and fetches
        // GET /api/profile once, which is cheap compared to the fix of
        // wiring a notifier-style provider through the whole tree.
        ref.invalidate(profileProvider);
        context.go('/conversation');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submittingId = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final personasAsync = ref.watch(personasProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 48),
              Text('Pick your tutor', style: AppTypography.sectionHeading),
              const SizedBox(height: 12),
              Text(
                'Choose the AI companion you want to practice English with',
                style: AppTypography.body.copyWith(color: AppColors.darkGray),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Expanded(child: _buildList(personasAsync)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(AsyncValue<List<Persona>> personasAsync) {
    return personasAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Failed to load tutors',
              style: AppTypography.body.copyWith(color: AppColors.warmGray),
            ),
            const SizedBox(height: 8),
            Text(
              friendlyError(error),
              style: AppTypography.caption.copyWith(color: AppColors.warmGray),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.invalidate(personasProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (personas) {
        if (personas.isEmpty) {
          return Center(
            child: Text(
              'No tutors available yet.',
              style: AppTypography.body.copyWith(color: AppColors.warmGray),
            ),
          );
        }
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: personas.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (context, i) {
            final p = personas[i];
            return _PersonaCard(
              persona: p,
              loading: _submittingId == p.id,
              enabled: _submittingId == null,
              onTap: () => _selectPersona(p),
            );
          },
        );
      },
    );
  }
}

class _PersonaCard extends StatelessWidget {
  final Persona persona;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  const _PersonaCard({
    required this.persona,
    required this.loading,
    required this.enabled,
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
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.large),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
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
                      style: AppTypography.sectionHeading,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
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
                SizedBox(
                  width: 20,
                  height: 20,
                  child: loading
                      ? const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.warmGray,
                        )
                      : const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: AppColors.warmGray,
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
