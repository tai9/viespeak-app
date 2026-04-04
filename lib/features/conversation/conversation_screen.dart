import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/profile_providers.dart';
import '../../core/providers/providers.dart';
import '../../core/services/audio_service.dart';
import '../../core/services/realtime_service.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/utils/error_utils.dart';
import '../../shared/widgets/quota_bar_widget.dart';
import 'transcript_widget.dart';

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
  final _scrollController = ScrollController();
  final _entries = <TranscriptEntry>[];
  final _subscriptions = <StreamSubscription>[];

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isSpeaking = false;
  bool _quotaExceeded = false;
  String _quotaResetAt = '';
  Timer? _sessionTimer;
  int _secondsRemaining = 0;
  int _totalSeconds = 0;
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
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _cancelSubscriptions();
    _realtimeService.disconnect();
    _audioService.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> _startConversation() async {
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

      _totalSeconds = sessionInit.remainingSeconds;
      _secondsRemaining = sessionInit.remainingSeconds;

      // 2. Fetch memories for context hint
      try {
        // apiService captured before async gap
        final memories = await apiService.getMemories();
        if (memories.isNotEmpty && mounted) {
          final summary = memories.first['summary'] as String?;
          if (summary != null && summary.isNotEmpty) {
            setState(() {
              _entries.add(TranscriptEntry(
                speaker: 'system',
                text: 'Last time: $summary',
                isFinalized: true,
              ));
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
              _entries.add(TranscriptEntry(
                speaker: 'assistant',
                text: _currentAITranscript.toString(),
              ));
            }
          });
          _scrollToBottom();
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
          _scrollToBottom();
        }),
        _realtimeService.onUserTranscript.listen((transcript) {
          if (transcript.trim().isEmpty) return;
          setState(() {
            _entries.add(TranscriptEntry(
              speaker: 'user',
              text: transcript,
              isFinalized: true,
            ));
          });
          _transcriptLog.add({'role': 'user', 'text': transcript});
          _scrollToBottom();
        }),
        _realtimeService.onAudioReceived.listen((audioBytes) {
          _audioService.playAudioChunk(audioBytes);
        }),
        _realtimeService.onSpeechStarted.listen((_) {
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
          setState(() => _isSpeaking = false);
        }),
        _realtimeService.onError.listen((error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error)),
            );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _startMic() async {
    try {
      await _audioService.startRecording();
      _audioService.micStream?.listen((pcm16Chunk) {
        _realtimeService.sendAudio(pcm16Chunk);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _endConversation() async {
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

  @override
  Widget build(BuildContext context) {
    if (_quotaExceeded) {
      return _buildQuotaExceededView();
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: _isConnected ? _buildAppBar() : _buildIdleAppBar(),
      body: SafeArea(
        child: _isConnected ? _buildConversationView() : _buildStartView(),
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
                style: AppTypography.bodyStandard.copyWith(color: AppColors.warmGray),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildIdleAppBar() {
    return AppBar(
      backgroundColor: AppColors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: GestureDetector(
          onTap: () => context.push('/profile'),
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.warmStoneSurface,
                borderRadius: BorderRadius.circular(AppRadius.comfortable),
                boxShadow: AppShadows.warmLift,
              ),
              child: Center(
                child: Text(
                  _userName.isNotEmpty ? _userName[0].toUpperCase() : '?',
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
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      title: Text(
        _personaName,
        style: AppTypography.nav.copyWith(color: AppColors.black),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(25),
        child: Column(
          children: [
            QuotaBarWidget(
              secondsRemaining: _secondsRemaining,
              totalSeconds: _totalSeconds,
            ),
            const Divider(height: 1, color: AppColors.borderSubtle),
          ],
        ),
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

  Widget _buildConversationView() {
    return Column(
      children: [
        Expanded(
          child: TranscriptWidget(
            entries: _entries,
            scrollController: _scrollController,
          ),
        ),
        // Speaking indicator
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: _SpeakingIndicator(isSpeaking: _isSpeaking),
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

class _SpeakingIndicator extends StatelessWidget {
  final bool isSpeaking;

  const _SpeakingIndicator({required this.isSpeaking});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isSpeaking ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mic_rounded,
            size: 18,
            color: isSpeaking ? AppColors.black : AppColors.warmGray,
          ),
          const SizedBox(width: 6),
          Text(
            isSpeaking ? 'Listening...' : 'Speak anytime',
            style: AppTypography.caption.copyWith(
              color: isSpeaking ? AppColors.black : AppColors.warmGray,
            ),
          ),
        ],
      ),
    );
  }
}
