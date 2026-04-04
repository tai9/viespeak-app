import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/services/api_service.dart';
import '../../core/services/base_auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/utils/error_utils.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _memories = [];
  bool _loading = true;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final api = context.read<ApiService>();
    final results = await Future.wait([
      api.getProfile(),
      api.getMemories(),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as Map<String, dynamic>?;
      _memories = results[1] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  Future<void> _handleSignOut() async {
    setState(() => _signingOut = true);
    try {
      await context.read<BaseAuthService>().signOut();
    } catch (e) {
      if (mounted) {
        setState(() => _signingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: _buildProfileCard(),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildSectionTitle('Conversation history'),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _memories.isEmpty
                      ? Center(
                          child: Text(
                            'No conversations yet. Start talking!',
                            style: AppTypography.body.copyWith(color: AppColors.warmGray),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _memories.length,
                          itemBuilder: (context, index) =>
                              _buildMemoryCard(_memories[index]),
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
            ),
    );
  }

  Widget _buildProfileCard() {
    final name = _profile?['name'] as String? ?? 'Unknown';
    final major = _profile?['major'] as String? ?? 'Not set';
    final level = _profile?['level'] as String? ?? '—';
    final persona = major == 'IT' ? 'Alex' : 'Sarah';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: AppShadows.outlineRing,
      ),
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
                    '$major · Level $level · Companion: $persona',
                    style: AppTypography.caption.copyWith(color: AppColors.darkGray),
                  ),
                ],
              ),
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
    final date = createdAt.isNotEmpty ? createdAt.substring(0, 10) : '';

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
                    style: AppTypography.micro.copyWith(color: AppColors.warmGray),
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
                      style: AppTypography.button.copyWith(color: AppColors.black),
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
