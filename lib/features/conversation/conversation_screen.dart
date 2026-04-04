import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/services/audio_service.dart';
import '../../core/services/base_auth_service.dart';
import '../../core/services/ws_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/utils/error_utils.dart';
import 'transcript_widget.dart';

class ConversationScreen extends StatefulWidget {
  final String major;

  const ConversationScreen({super.key, required this.major});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  WsService? _wsService;
  final _audioService = AudioService();
  final _scrollController = ScrollController();
  final _entries = <TranscriptEntry>[];
  final _subscriptions = <StreamSubscription>[];

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isSpeaking = false; // user is speaking
  Timer? _sessionTimer;
  int _secondsRemaining = 600; // 10 minutes

  // Accumulate streaming AI transcript
  StringBuffer _currentAITranscript = StringBuffer();

  String get _personaName => widget.major == 'IT' ? 'Alex' : 'Sarah';
  String get _userName => context.read<BaseAuthService>().userName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _wsService ??= context.read<WsService>();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _cancelSubscriptions();
    _wsService?.disconnect();
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
    try {
      final token = context.read<BaseAuthService>().token;
      if (token == null) {
        setState(() => _isConnecting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Not authenticated. Please sign in again.')),
          );
        }
        return;
      }

      // Connect WebSocket
      await _wsService!.connect(token: token);

      // Start mic immediately — don't wait for session.created
      await _startMic();

      // Listen to WS events
      _subscriptions.addAll([
        _wsService!.onAITranscriptDelta.listen((delta) {
          _currentAITranscript.write(delta);
          setState(() {
            // Update or add the current AI message
            if (_entries.isNotEmpty && _entries.last.speaker == 'assistant' && !_entries.last.isFinalized) {
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
        _wsService!.onAITranscriptDone.listen((transcript) {
          setState(() {
            // Finalize the current AI message
            if (_entries.isNotEmpty && _entries.last.speaker == 'assistant') {
              _entries.last = TranscriptEntry(
                speaker: 'assistant',
                text: transcript,
                isFinalized: true,
              );
            }
          });
          _currentAITranscript = StringBuffer();
          _scrollToBottom();
        }),
        _wsService!.onUserTranscript.listen((transcript) {
          if (transcript.trim().isEmpty) return;
          setState(() {
            _entries.add(TranscriptEntry(
              speaker: 'user',
              text: transcript,
              isFinalized: true,
            ));
          });
          _scrollToBottom();
        }),
        _wsService!.onAudioReceived.listen((audioBytes) {
          _audioService.playAudioChunk(audioBytes);
        }),
        _wsService!.onSpeechStarted.listen((_) {
          setState(() => _isSpeaking = true);
          // Interrupt AI audio when user starts speaking
          _audioService.stopPlayback();
        }),
        _wsService!.onSpeechStopped.listen((_) {
          setState(() => _isSpeaking = false);
        }),
        _wsService!.onError.listen((error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error)),
            );
          }
        }),
        _wsService!.onDone.listen((_) {
          if (mounted) _endConversation();
        }),
      ]);

      // Start session timer
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
        _wsService?.sendAudio(pcm16Chunk);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  void _endConversation() {
    _sessionTimer?.cancel();
    _cancelSubscriptions();
    _wsService?.disconnect();
    _audioService.stopRecording();
    _audioService.stopPlayback();
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
      appBar: _isConnected ? _buildAppBar() : _buildIdleAppBar(),
      body: SafeArea(
        child: _isConnected ? _buildConversationView() : _buildStartView(),
      ),
    );
  }

  PreferredSizeWidget _buildIdleAppBar() {
    return AppBar(
      backgroundColor: AppColors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: IconButton(
          icon: const Icon(Icons.person_outline_rounded, color: AppColors.black),
          onPressed: () => context.push('/profile'),
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
