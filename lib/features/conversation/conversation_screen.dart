import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/ws_service.dart';
import '../../core/theme/app_theme.dart';
import 'transcript_widget.dart';

class ConversationScreen extends StatefulWidget {
  final String major;

  const ConversationScreen({super.key, required this.major});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late final WsService _wsService = context.read<WsService>();
  final _scrollController = ScrollController();
  final _entries = <TranscriptEntry>[];

  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _sessionTimer;
  int _secondsRemaining = 600; // 10 minutes

  String get _personaName => widget.major == 'IT' ? 'Alex' : 'Sarah';
  String get _userName => context.read<AuthService>().userName;

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _wsService.disconnect();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startConversation() async {
    setState(() => _isConnecting = true);
    try {
      final auth = context.read<AuthService>();
      final token = auth.token;
      if (token == null) return;

      await _wsService.connect(
        token: token,
        major: widget.major,
      );

      _wsService.transcriptStream.listen((data) {
        final speaker = data['speaker'] as String? ?? 'assistant';
        final text = data['text'] as String? ?? '';
        if (text.isNotEmpty) {
          setState(() {
            _entries.add(TranscriptEntry(speaker: speaker, text: text));
          });
          _scrollToBottom();
        }
      });

      _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _secondsRemaining--);
        if (_secondsRemaining <= 0) {
          _endConversation();
        }
      });

      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });
    } catch (e) {
      setState(() => _isConnecting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e')),
        );
      }
    }
  }

  void _endConversation() {
    _sessionTimer?.cancel();
    _wsService.disconnect();
    setState(() => _isConnected = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String get _timerDisplay {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: _isConnected ? _buildAppBar() : null,
      body: SafeArea(
        child: _isConnected
            ? TranscriptWidget(
                entries: _entries,
                scrollController: _scrollController,
              )
            : _buildStartView(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      title: Text(
        '$_personaName  ·  $_timerDisplay',
        style: AppTypography.nav.copyWith(color: AppColors.black),
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: AppColors.borderSubtle),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.warmStoneSurface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: AppShadows.warmLift,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _endConversation,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'End',
                    style: AppTypography.button.copyWith(color: AppColors.black),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStartView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Hey $_userName,\n$_personaName is ready to chat.',
              style: AppTypography.sectionHeading,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 64),
            GestureDetector(
              onTap: _isConnecting ? null : _startConversation,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: AppColors.warmStoneSurface,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.warmLift,
                ),
                child: _isConnecting
                    ? const Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.black,
                          ),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.mic_rounded,
                            size: 48,
                            color: AppColors.black,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start talking',
                            style: AppTypography.button.copyWith(
                              color: AppColors.black,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
