import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/providers/profile_providers.dart';
import '../../core/providers/providers.dart';
import '../../core/services/audio_service.dart';
import '../../core/services/conversation_controller.dart';
import '../../core/services/realtime_service.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/utils/error_utils.dart';
import 'transcript_widget.dart';
import 'voice_orb_widget.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  final String major;

  const ConversationScreen({super.key, required this.major});

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  late final RealtimeService _realtimeService;
  late final SessionService _sessionService;
  final _audioService = AudioService();
  late final ConversationController _controller;
  final _entries = <TranscriptEntry>[];
  final _floatingTranscripts = <_FloatingTranscript>[];
  final _subscriptions = <StreamSubscription>[];

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _quotaExceeded = false;
  String _quotaResetAt = '';
  Timer? _sessionTimer;
  int _secondsRemaining = 0;
  DateTime? _sessionStartTime;

  // Accumulate streaming AI transcript
  StringBuffer _currentAITranscript = StringBuffer();

  // Collect transcript for endSession call
  final _transcriptLog = <Map<String, String>>[];

  String get _personaName => widget.major == 'IT' ? 'Alex' : 'Sarah';
  String get _userName => ref.read(authServiceProvider).userName;

  @override
  void initState() {
    super.initState();
    _realtimeService = ref.read(realtimeServiceProvider);
    _sessionService = ref.read(sessionServiceProvider);
    _controller = ConversationController(
      realtime: _realtimeService,
      audio: _audioService,
    );
    _controller.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _cancelSubscriptions();
    _controller.state.removeListener(_onStateChanged);
    // If the user navigates away mid-session (back button, route pop) the
    // Stop button's _endConversation never runs. Fire the session end here
    // so the backend can still persist the transcript as a memory and
    // deduct quota. Fire-and-forget since dispose can't await.
    if (_sessionStartTime != null) {
      final duration = DateTime.now().difference(_sessionStartTime!).inSeconds;
      debugPrint(
        '[Conversation] dispose: fire-and-forget endSession '
        'duration=${duration}s, transcriptLines=${_transcriptLog.length}',
      );
      _sessionService
          .endSession(
            transcript: _transcriptLog,
            durationSeconds: duration,
          )
          .then(
            (_) => debugPrint('[Conversation] dispose endSession OK'),
            onError: (e) =>
                debugPrint('[Conversation] dispose endSession failed: $e'),
          );
      _sessionStartTime = null;
    }
    _controller.stop();
    _controller.dispose();
    _audioService.dispose();
    super.dispose();
  }

  ConversationState _prevState = ConversationState.idle;
  void _onStateChanged() {
    final next = _controller.state.value;
    if (next == _prevState) return;
    // Haptic feedback on voice turn changes.
    if (next == ConversationState.userSpeaking ||
        next == ConversationState.aiSpeaking) {
      HapticFeedback.selectionClick();
    }
    _prevState = next;
    if (mounted) setState(() {});
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> _startConversation() async {
    HapticFeedback.mediumImpact();

    // Check mic permission before anything else
    final micGranted = await _audioService.requestPermission();
    if (!micGranted) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Microphone Access'),
            content: const Text(
              'VieSpeak needs microphone access to have a conversation. Please enable it in Settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
      return;
    }

    setState(() => _isConnecting = true);
    final apiService = ref.read(apiServiceProvider);
    try {
      // 1. Initialize session — get ephemeral token from backend
      final SessionInitResult sessionInit;
      try {
        sessionInit = await _sessionService.getSessionInit();
      } on QuotaExceededException catch (e) {
        setState(() {
          _isConnecting = false;
          _quotaExceeded = true;
          _quotaResetAt = e.resetAt;
        });
        return;
      }

      _secondsRemaining = sessionInit.remainingSeconds;

      // 2. Fetch memories for context hint
      try {
        // apiService captured before async gap
        final memories = await apiService.getMemories();
        if (memories.isNotEmpty && mounted) {
          final summary = memories.first['summary'] as String?;
          if (summary != null && summary.isNotEmpty) {
            setState(() {
              _entries.add(
                TranscriptEntry(
                  speaker: 'system',
                  text: 'Last time: $summary',
                  isFinalized: true,
                ),
              );
            });
          }
        }
      } catch (_) {
        // Memory fetch is non-critical, continue without it
      }

      // 3. Hand off connection + mic + playback + state machine to the
      //    controller. It owns the idle/userSpeaking/aiSpeaking FSM and
      //    hardware-pauses the mic whenever the AI is speaking.
      await _controller.start(
        token: sessionInit.token,
        model: sessionInit.model,
      );

      // 4. Listen to realtime transcript events (UI-only concerns)
      _subscriptions.addAll([
        _realtimeService.onAITranscriptDelta.listen((delta) {
          _currentAITranscript.write(delta);
          setState(() {
            if (_entries.isNotEmpty &&
                _entries.last.speaker == 'assistant' &&
                !_entries.last.isFinalized) {
              _entries.last = TranscriptEntry(
                speaker: 'assistant',
                text: _currentAITranscript.toString(),
              );
            } else {
              _entries.add(
                TranscriptEntry(
                  speaker: 'assistant',
                  text: _currentAITranscript.toString(),
                ),
              );
            }
          });
        }),
        _realtimeService.onAITranscriptDone.listen((transcript) {
          setState(() {
            if (_entries.isNotEmpty && _entries.last.speaker == 'assistant') {
              _entries.last = TranscriptEntry(
                speaker: 'assistant',
                text: transcript,
                isFinalized: true,
              );
            }
          });
          _currentAITranscript = StringBuffer();
          _transcriptLog.add({'role': 'assistant', 'content': transcript});
          _addFloatingTranscript(transcript, false);
          HapticFeedback.lightImpact();
        }),
        _realtimeService.onUserTranscript.listen((transcript) {
          if (transcript.trim().isEmpty) return;
          setState(() {
            _entries.add(
              TranscriptEntry(
                speaker: 'user',
                text: transcript,
                isFinalized: true,
              ),
            );
          });
          _transcriptLog.add({'role': 'user', 'content': transcript});
          _addFloatingTranscript(transcript, true);
          HapticFeedback.lightImpact();
        }),
        _realtimeService.onError.listen((error) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error)));
          }
        }),
        _realtimeService.onDone.listen((_) {
          if (mounted) _endConversation();
        }),
      ]);

      // 7. Start countdown timer
      _sessionStartTime = DateTime.now();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _endConversation() async {
    HapticFeedback.lightImpact();
    _sessionTimer?.cancel();
    _cancelSubscriptions();
    await _controller.stop();
    setState(() => _isConnected = false);

    // Send duration to backend so quota is deducted — always call this once
    // the session started, even if no transcript was captured. The transcript
    // guard used to skip the call when the user ended before speaking, which
    // left the backend quota untouched.
    if (_sessionStartTime != null) {
      final duration = DateTime.now().difference(_sessionStartTime!).inSeconds;
      debugPrint(
        '[Conversation] _endConversation: flushing session '
        'duration=${duration}s, transcriptLines=${_transcriptLog.length}',
      );
      try {
        await _sessionService.endSession(
          transcript: _transcriptLog,
          durationSeconds: duration,
        );
        debugPrint('[Conversation] endSession completed OK');
      } catch (e) {
        debugPrint('[Conversation] endSession threw: $e');
      }
      _sessionStartTime = null;
    } else {
      debugPrint(
        '[Conversation] _endConversation: no _sessionStartTime, skipping',
      );
    }

    // Refresh cached quota + memories so profile screen shows fresh data
    debugPrint('[Conversation] invalidating quotaProvider + memoriesProvider');
    ref.invalidate(quotaProvider);
    ref.invalidate(memoriesProvider);
  }

  void _addFloatingTranscript(String text, bool isUser) {
    setState(() {
      _floatingTranscripts.add(
        _FloatingTranscript(
          text: text,
          isUser: isUser,
          createdAt: DateTime.now(),
        ),
      );
      // Keep max 3
      if (_floatingTranscripts.length > 3) {
        _floatingTranscripts.removeAt(0);
      }
    });
    // Auto-remove after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _floatingTranscripts.removeWhere(
            (t) => DateTime.now().difference(t.createdAt).inSeconds >= 3,
          );
        });
      }
    });
  }

  bool get _active => _isConnected || _isConnecting;

  @override
  Widget build(BuildContext context) {
    if (_quotaExceeded) return _buildQuotaExceededView();

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            Column(
              children: [
                // Top header area
                SizedBox(
                  height: 60,
                  child: Stack(
                    children: [
                      // Profile avatar — top left, fades out when active
                      Positioned(
                        top: 12,
                        left: 16,
                        child: AnimatedOpacity(
                          opacity: _active ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 400),
                          child: GestureDetector(
                            onTap: _active
                                ? null
                                : () {
                                    HapticFeedback.lightImpact();
                                    context.push('/profile');
                                  },
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppColors.warmStoneSurface,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.comfortable,
                                ),
                                boxShadow: AppShadows.warmLift,
                              ),
                              child: Center(
                                child: Text(
                                  _userName.isNotEmpty
                                      ? _userName[0].toUpperCase()
                                      : '?',
                                  style: AppTypography.caption.copyWith(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    color: AppColors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Logo — center top, fades in when active
                      Center(
                        child: AnimatedOpacity(
                          opacity: _active ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 400),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Image.asset(
                              'assets/icon/app_icon.png',
                              width: 48,
                              height: 48,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Center area — orb + stop button
                Expanded(
                  child: SingleChildScrollView(
                    // Welcome text, orb, and stop button are all laid out
                    // together (AnimatedOpacity keeps them in the tree), so
                    // on short viewports the column can exceed available
                    // height. Allow scrolling as a safety net.
                    physics: const ClampingScrollPhysics(),
                    child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo + welcome text — fades out when active
                        AnimatedOpacity(
                          opacity: _active ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 400),
                          child: AnimatedSlide(
                            offset: _active
                                ? const Offset(0, -0.3)
                                : Offset.zero,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOutCubic,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/icon/app_icon.png',
                                  width: 80,
                                  height: 80,
                                ),
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 40,
                                  ),
                                  child: Text(
                                    'Hey $_userName,\n$_personaName is ready to chat.',
                                    style: AppTypography.bodyStandard.copyWith(
                                      color: AppColors.warmGray,
                                      fontSize: 18,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeInOutCubic,
                          height: _active ? 0 : 40,
                        ),

                        // The orb / start circle
                        _buildOrb(),

                        // Stop button — fades in when connected
                        AnimatedOpacity(
                          opacity: _isConnected ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 400),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: GestureDetector(
                              onTap: _isConnected ? _endConversation : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.warmStoneSurface,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.pill,
                                  ),
                                  boxShadow: AppShadows.warmLift,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.stop_rounded,
                                      size: 18,
                                      color: AppColors.black,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Stop',
                                      style: AppTypography.button.copyWith(
                                        color: AppColors.black,
                                      ),
                                    ),
                                  ],
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
              ],
            ),

            // Floating transcripts — positioned overlay above orb, no layout change
            if (_isConnected && _floatingTranscripts.isNotEmpty)
              Positioned(
                left: 24,
                right: 24,
                top: MediaQuery.of(context).size.height * 0.18,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _floatingTranscripts.map((t) {
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: t.isUser
                            ? AppColors.warmStoneSurface
                            : AppColors.nearWhite,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Text(
                        t.text,
                        style: AppTypography.bodyStandard.copyWith(
                          color: AppColors.warmGray,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrb() {
    final convState = _controller.state.value;
    final orbState = switch (convState) {
      ConversationState.aiSpeaking => OrbState.aiSpeaking,
      ConversationState.userSpeaking => OrbState.userSpeaking,
      ConversationState.idle => OrbState.idle,
    };

    return GestureDetector(
      onTap: () {
        if (!_isConnected && !_isConnecting) {
          _startConversation();
        } else if (convState == ConversationState.aiSpeaking) {
          // Tap-to-interrupt: stop AI and hand the turn back to the user.
          HapticFeedback.mediumImpact();
          _controller.interrupt();
        }
      },
      child: SizedBox(
        width: 260,
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VoiceOrbWidget(
              state: orbState,
              micLevel: _controller.micLevel,
              aiLevel: _controller.aiLevel,
            ),
            // "Start talking" overlay — only when idle
            if (!_isConnected)
              AnimatedOpacity(
                opacity: _isConnecting ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.mic_rounded,
                      size: 48,
                      color: AppColors.warmGray,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start talking',
                      style: AppTypography.button.copyWith(
                        color: AppColors.warmGray,
                      ),
                    ),
                  ],
                ),
              ),
            // Loading spinner when connecting
            if (_isConnecting)
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.warmGray,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotaExceededView() {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.black),
            onPressed: () => context.pop(),
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.timer_off_rounded,
                size: 64,
                color: AppColors.warmGray,
              ),
              const SizedBox(height: 24),
              Text(
                'You\'ve used all your time for today.',
                style: AppTypography.sectionHeading,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _quotaResetAt.isNotEmpty
                    ? 'Come back after ${_quotaResetAt.substring(0, 16).replaceAll('T', ' ')} to chat with $_personaName again!'
                    : 'Come back tomorrow to chat with $_personaName again!',
                style: AppTypography.bodyStandard.copyWith(
                  color: AppColors.warmGray,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingTranscript {
  final String text;
  final bool isUser;
  final DateTime createdAt;

  _FloatingTranscript({
    required this.text,
    required this.isUser,
    required this.createdAt,
  });
}
