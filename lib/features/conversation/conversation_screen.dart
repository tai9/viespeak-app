import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/personas/persona.dart';
import '../../core/providers/profile_providers.dart';
import '../../core/providers/providers.dart';
import '../../core/services/audio_service.dart';
import '../../core/services/conversation_controller.dart';
import '../../core/services/realtime_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/voice_turn_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/utils/date_utils.dart';
import '../../shared/utils/error_utils.dart';
import '../../shared/utils/quota_utils.dart';
import 'transcript_widget.dart';
import 'voice_orb_widget.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key});

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

  // Populated once /session/init returns — the backend owns persona selection,
  // and /session/init returns the authoritative persona (which may differ
  // from the profile's stored id if the server fell back to a default).
  // Before the session starts we surface the profile's persona so the user
  // sees who they're about to talk to on the idle welcome screen.
  Persona? _persona;
  String? get _personaName {
    if (_persona != null) return _persona!.name;
    final profile = ref.watch(profileProvider).valueOrNull;
    final persona = profile?['persona'] as Map<String, dynamic>?;
    return persona?['name'] as String?;
  }

  String get _userName => ref.read(authServiceProvider).userName;

  // ─── TTS mode state ───────────────────────────────────────────────────
  SessionMode? _mode;
  String? _sessionId;
  VoiceTurnController? _voiceController;
  VoiceTurnState _voiceState = VoiceTurnState.idle;
  // Orb input in TTS mode — populated from VoiceTurnController.onAmplitude
  // (raw dBFS ~ -160..0) by mapping into the 0..1 range the orb expects.
  // Stays at 0 when no turn is listening so the orb settles to its idle pose.
  final _voiceMicLevel = ValueNotifier<double>(0.0);
  final _voiceAiLevel = ValueNotifier<double>(0.0);

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
    _voiceController?.state.removeListener(_onVoiceStateChanged);
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
            sessionId: _sessionId,
          )
          .then(
            (_) => debugPrint('[Conversation] dispose endSession OK'),
            onError: (e) =>
                debugPrint('[Conversation] dispose endSession failed: $e'),
          );
      _sessionStartTime = null;
    }
    if (_mode == SessionMode.tts) {
      _voiceController?.stop();
      _voiceController?.dispose();
      _voiceController = null;
    }
    _voiceMicLevel.dispose();
    _voiceAiLevel.dispose();
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
      // 1. Initialize session
      final SessionInitResult sessionInit;
      try {
        sessionInit = await _sessionService.getSessionInit();
      } on QuotaExceededException catch (e) {
        setState(() {
          _isConnecting = false;
          _quotaExceeded = true;
          _quotaResetAt = e.resetAt;
        });
        ref.invalidate(quotaProvider);
        return;
      } on ProfileNotFoundException {
        setState(() => _isConnecting = false);
        if (mounted) context.go('/select-persona');
        return;
      }

      _secondsRemaining = sessionInit.remainingSeconds;
      _mode = sessionInit.mode;
      _sessionId = sessionInit.sessionId;
      if (mounted) {
        setState(() => _persona = sessionInit.persona);
      }

      // 2. Fetch memories for context hint
      try {
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

      // 3. Branch on mode
      if (sessionInit.mode == SessionMode.tts) {
        await _startVoiceTurnMode();
      } else {
        await _startS2sMode(sessionInit);
      }

      // 4. Start countdown timer
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

  // ─── S2S mode (existing WebSocket flow) ─────────────────────────────

  Future<void> _startS2sMode(SessionInitResult sessionInit) async {
    await _controller.start(
      token: sessionInit.token!,
      model: sessionInit.model!,
      userName: _userName,
    );

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
  }

  // ─── TTS mode (record → /tts/voice → crossfaded MP3 playback) ───────

  Future<void> _startVoiceTurnMode() async {
    final controller = VoiceTurnController(
      service: ref.read(voiceTurnServiceProvider),
      audio: _audioService,
    );
    _voiceController = controller;
    controller.state.addListener(_onVoiceStateChanged);

    _subscriptions.addAll([
      controller.onUserTranscript.listen(_appendUserEntry),
      controller.onAssistantTranscript.listen(_appendAssistantEntry),
      controller.onError.listen(_onVoiceError),
      // Feed the amplitude meter into the orb. Map dBFS to 0..1 with a
      // usable speech window: room noise (~-55 dBFS) → 0, loud speech
      // (~-5 dBFS) → 1. The orb's own smoothing handles the rest.
      controller.onAmplitude.listen((db) {
        final level = ((db + 55) / 50).clamp(0.0, 1.0);
        _voiceMicLevel.value = level;
      }),
    ]);

    await controller.start(sessionId: _sessionId!);
  }

  void _onVoiceStateChanged() {
    final next = _voiceController?.state.value;
    if (next == null || next == _voiceState) return;
    if (next == VoiceTurnState.listening ||
        next == VoiceTurnState.speaking) {
      HapticFeedback.selectionClick();
    }
    // Drop the orb back to its resting pose when we leave the listening
    // phase — the amplitude stream stops emitting at that point, so the
    // notifier would otherwise stay pinned at the last observed value.
    if (next != VoiceTurnState.listening) {
      _voiceMicLevel.value = 0.0;
    }
    setState(() => _voiceState = next);
  }

  void _appendUserEntry(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _entries.add(
        TranscriptEntry(speaker: 'user', text: text, isFinalized: true),
      );
    });
    _transcriptLog.add({'role': 'user', 'content': text});
    _addFloatingTranscript(text, true);
    HapticFeedback.lightImpact();
  }

  void _appendAssistantEntry(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _entries.add(
        TranscriptEntry(
          speaker: 'assistant',
          text: text,
          isFinalized: true,
        ),
      );
    });
    _transcriptLog.add({'role': 'assistant', 'content': text});
    _addFloatingTranscript(text, false);
    HapticFeedback.lightImpact();
  }

  void _onVoiceError(Object error) {
    debugPrint('[VoiceTurn] error surfaced to UI: $error');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyError(error))),
    );
  }

  Future<void> _endConversation() async {
    HapticFeedback.lightImpact();
    _sessionTimer?.cancel();
    _cancelSubscriptions();

    if (_mode == SessionMode.tts) {
      final vc = _voiceController;
      if (vc != null) {
        vc.state.removeListener(_onVoiceStateChanged);
        await vc.stop();
        vc.dispose();
        _voiceController = null;
      }
      _voiceState = VoiceTurnState.idle;
    } else {
      await _controller.stop();
    }

    setState(() {
      _isConnected = false;
    });

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
          sessionId: _sessionId,
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

    final quotaAsync = ref.watch(quotaProvider);
    final quota = quotaAsync.valueOrNull;

    // Only allow start once the backend has confirmed both fields AND the
    // cached quota still has headroom. Exhaustion is decided locally from
    // the pre-fetched quota — no API round-trip just to get a 429.
    final canStart =
        quota != null &&
        quota['remaining_seconds'] is int &&
        !isQuotaExhausted(quota);

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
                              'assets/images/viespeak_logo.png',
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
                                    'assets/images/viespeak_logo.png',
                                    width: 80,
                                    height: 80,
                                  ),
                                  const SizedBox(height: 16),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 40,
                                    ),
                                    child: Text(
                                      _personaName != null
                                          ? 'Hey $_userName,\n$_personaName is ready to chat.'
                                          : 'Hey $_userName,\nready when you are.',
                                      style: AppTypography.bodyStandard
                                          .copyWith(
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
                          _buildOrb(canStart: canStart),

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

  Widget _buildOrb({required bool canStart}) {
    // TTS mode drives the orb from VoiceTurnController's state machine;
    // S2S mode keeps the existing ConversationController wiring.
    final OrbState orbState;
    if (_mode == SessionMode.tts && _isConnected) {
      orbState = switch (_voiceState) {
        VoiceTurnState.speaking => OrbState.aiSpeaking,
        VoiceTurnState.listening => OrbState.userSpeaking,
        VoiceTurnState.thinking => OrbState.idle,
        VoiceTurnState.idle => OrbState.idle,
      };
    } else {
      final convState = _controller.state.value;
      orbState = switch (convState) {
        ConversationState.aiSpeaking => OrbState.aiSpeaking,
        ConversationState.userSpeaking => OrbState.userSpeaking,
        ConversationState.idle => OrbState.idle,
      };
    }

    // Disabled only during the tiny cold-start window before quotaProvider
    // resolves. Exhausted quota already short-circuits to the exhausted
    // view in build(), so we don't need to handle it here.
    final startBlocked = !canStart && !_isConnected && !_isConnecting;

    return GestureDetector(
      onTap: () {
        if (!_isConnected && !_isConnecting) {
          // Cached quota already exhausted — flip straight to the exhausted
          // view without hitting the backend.
          final cachedQuota = ref.read(quotaProvider).valueOrNull;
          if (isQuotaExhausted(cachedQuota)) {
            HapticFeedback.lightImpact();
            setState(() {
              _quotaExceeded = true;
              _quotaResetAt = '';
            });
            return;
          }
          if (!canStart) return;
          _startConversation();
        } else if (_mode == SessionMode.tts &&
            _voiceState == VoiceTurnState.speaking) {
          // Tap-to-interrupt in TTS mode: stop reply playback and go back
          // to listening. VoiceTurnController handles the state transition.
          HapticFeedback.mediumImpact();
          _voiceController?.interrupt();
        } else if (_mode != SessionMode.tts &&
            _controller.state.value == ConversationState.aiSpeaking) {
          // Tap-to-interrupt in S2S mode
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
              micLevel: _mode == SessionMode.tts
                  ? _voiceMicLevel
                  : _controller.micLevel,
              aiLevel: _mode == SessionMode.tts
                  ? _voiceAiLevel
                  : _controller.aiLevel,
            ),
            // "Start talking" overlay — only when idle
            if (!_isConnected)
              AnimatedOpacity(
                opacity: _isConnecting ? 0.0 : (startBlocked ? 0.4 : 1.0),
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

  /// Formats the quota reset instant in the device's local time.
  ///
  /// When the backend supplies a reset timestamp (on a 429 from
  /// `/session/init`) it arrives as UTC — `formatTimestamp` handles the
  /// conversion. Otherwise (local exhaustion from cached `/quota`, which
  /// has no `reset_at` field) we fall back to midnight of the next local
  /// day, matching the backend's daily reset semantics.
  String _formatQuotaResetMessage(String rawResetAt) {
    final fromBackend = formatTimestamp(rawResetAt);
    if (fromBackend.isNotEmpty) {
      return 'Come back after $fromBackend to chat again!';
    }
    final now = DateTime.now();
    final nextMidnight = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    final formatted = DateFormat('yyyy-MM-dd, HH:mm').format(nextMidnight);
    return 'Come back after $formatted to chat again!';
  }

  String _quotaHeadline() {
    return "You've used all your time for today.";
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
            // Dismiss the quota-exceeded overlay and return to the orb
            // screen. /conversation is the root of the current nav stack,
            // so context.pop() is a no-op here — just clear the flag.
            onPressed: () => setState(() => _quotaExceeded = false),
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
                _quotaHeadline(),
                style: AppTypography.sectionHeading,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _formatQuotaResetMessage(_quotaResetAt),
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
