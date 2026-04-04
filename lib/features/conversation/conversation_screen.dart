import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/providers/profile_providers.dart';
import '../../core/providers/providers.dart';
import '../../core/services/audio_service.dart';
import '../../core/services/realtime_service.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/utils/error_utils.dart';
import 'audio_level_processor.dart';
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
  final _entries = <TranscriptEntry>[];
  final _floatingTranscripts = <_FloatingTranscript>[];
  final _subscriptions = <StreamSubscription>[];

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isSpeaking = false;
  bool _isAISpeaking = false;
  bool _quotaExceeded = false;
  String _quotaResetAt = '';
  Timer? _sessionTimer;
  Timer? _aiSpeakingTimer;
  int _secondsRemaining = 0;
  DateTime? _sessionStartTime;

  // Audio level tracking for orb animation
  final _micLevel = ValueNotifier<double>(0.0);
  final _aiLevel = ValueNotifier<double>(0.0);
  final _micLevelProcessor = AudioLevelProcessor(alpha: 0.4);
  final _aiLevelProcessor = AudioLevelProcessor(alpha: 0.25);

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
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _aiSpeakingTimer?.cancel();
    _cancelSubscriptions();
    _realtimeService.disconnect();
    _audioService.dispose();
    _micLevel.dispose();
    _aiLevel.dispose();
    super.dispose();
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

      // 3. Connect to OpenAI Realtime API
      await _realtimeService.connect(
        token: sessionInit.token,
        model: sessionInit.model,
      );

      // 4. Send session config (audio format + VAD)
      _realtimeService.sendSessionUpdate();

      // 5. Start mic
      await _startMic();

      // 6. Listen to realtime events
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
          _transcriptLog.add({'role': 'assistant', 'text': transcript});
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
          _transcriptLog.add({'role': 'user', 'text': transcript});
          _addFloatingTranscript(transcript, true);
          HapticFeedback.lightImpact();
        }),
        _realtimeService.onAudioReceived.listen((audioBytes) {
          _audioService.playAudioChunk(audioBytes);
          _aiLevel.value = _aiLevelProcessor.process(audioBytes);
          if (!_isAISpeaking && mounted) {
            setState(() => _isAISpeaking = true);
          }
          _aiSpeakingTimer?.cancel();
          _aiSpeakingTimer = Timer(const Duration(milliseconds: 600), () {
            if (mounted) {
              setState(() => _isAISpeaking = false);
              _aiLevelProcessor.reset();
            }
          });
        }),
        _realtimeService.onSpeechStarted.listen((_) {
          HapticFeedback.selectionClick();
          setState(() => _isSpeaking = true);
          _audioService.stopPlayback();
          _realtimeService.cancelResponse();
          // Finalize partial AI transcript on interruption
          if (_entries.isNotEmpty &&
              _entries.last.speaker == 'assistant' &&
              !_entries.last.isFinalized) {
            final partialText = _currentAITranscript.toString();
            if (partialText.isNotEmpty) {
              setState(() {
                _entries.last = TranscriptEntry(
                  speaker: 'assistant',
                  text: partialText,
                  isFinalized: true,
                );
              });
              _transcriptLog.add({'role': 'assistant', 'text': partialText});
            }
            _currentAITranscript = StringBuffer();
          }
        }),
        _realtimeService.onSpeechStopped.listen((_) {
          HapticFeedback.selectionClick();
          setState(() => _isSpeaking = false);
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

  Future<void> _startMic() async {
    try {
      await _audioService.startRecording();
      _audioService.micStream?.listen((pcm16Chunk) {
        _realtimeService.sendAudio(pcm16Chunk);
        _micLevel.value = _micLevelProcessor.process(pcm16Chunk);
      });
    } catch (e) {
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
    _realtimeService.disconnect();
    _audioService.stopRecording();
    _audioService.stopPlayback();
    setState(() => _isConnected = false);

    // Send transcript + duration to backend
    if (_sessionStartTime != null && _transcriptLog.isNotEmpty) {
      final duration = DateTime.now().difference(_sessionStartTime!).inSeconds;
      try {
        await _sessionService.endSession(
          transcript: _transcriptLog,
          durationSeconds: duration,
        );
      } catch (_) {
        // Non-critical — don't block UI
      }
    }

    // Refresh cached quota + memories so profile screen shows fresh data
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
    final orbState = _isAISpeaking
        ? OrbState.aiSpeaking
        : _isSpeaking
            ? OrbState.userSpeaking
            : OrbState.idle;

    return GestureDetector(
      onTap: (!_isConnected && !_isConnecting) ? _startConversation : null,
      child: SizedBox(
        width: 260,
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VoiceOrbWidget(
              state: orbState,
              micLevel: _micLevel,
              aiLevel: _aiLevel,
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
