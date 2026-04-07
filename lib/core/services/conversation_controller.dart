import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/conversation/audio_level_processor.dart';
import 'audio_service.dart';
import 'realtime_service.dart';

/// High-level states for a voice conversation.
///
/// Strict invariant: whenever the machine is in [aiSpeaking], every PCM chunk
/// from the mic is dropped before it reaches the websocket. That blocks the
/// "mic picks up its own speaker → new response → infinite loop" failure
/// mode without touching the iOS/Android audio session (which would tear
/// down the player and truncate the AI's sentence).
enum ConversationState { idle, userSpeaking, aiSpeaking }

/// Orchestrates [RealtimeService] and [AudioService] through an explicit
/// state machine:
///
///   idle ──speech_started──▶ userSpeaking ──response.created──▶ aiSpeaking
///     ▲                                                              │
///     │                      playbackDrained +                       │
///     └──────300ms guard OR interrupt()──────────────────────────────┘
///
/// The screen reads [state], [micLevel], [aiLevel] and calls [start], [stop],
/// [interrupt]. It does not touch the mic or the websocket directly.
class ConversationController {
  ConversationController({
    required RealtimeService realtime,
    required AudioService audio,
  })  : _realtime = realtime,
        _audio = audio;

  final RealtimeService _realtime;
  final AudioService _audio;

  // How long to keep the mic gate closed after the drain timer fires. The
  // drain estimate is based on bytes received, which doesn't account for
  // flutter_sound's internal buffering — the speaker keeps playing for a
  // few hundred ms after the timer. Be generous: false-closed is harmless,
  // false-open costs us another echo loop.
  static const Duration _resumeGuard = Duration(milliseconds: 800);

  // Proactive conversation timings. If the user stays truly idle (no speech,
  // no AI playback) for [_checkInAfter], the AI sends a gentle check-in. If
  // still silent for [_reEngageAfter] after that, one final re-engage fires.
  // After stage 2, the controller stays silent until the user actually speaks.
  static const Duration _checkInAfter = Duration(seconds: 15);
  static const Duration _reEngageAfter = Duration(seconds: 20);

  final ValueNotifier<ConversationState> _state =
      ValueNotifier(ConversationState.idle);
  final ValueNotifier<double> _micLevel = ValueNotifier(0.0);
  final ValueNotifier<double> _aiLevel = ValueNotifier(0.0);

  final _micLevelProcessor = AudioLevelProcessor(alpha: 0.4);
  final _aiLevelProcessor = AudioLevelProcessor(alpha: 0.25);

  final List<StreamSubscription<dynamic>> _subs = [];
  StreamSubscription<Uint8List>? _micSub;
  Timer? _resumeTimer;
  Timer? _idleTimer;
  // 0 = fresh, 1 = check-in sent, 2 = re-engage sent (terminal until user speaks).
  int _idleStage = 0;
  String _userName = '';
  bool _started = false;

  ValueListenable<ConversationState> get state => _state;
  ValueListenable<double> get micLevel => _micLevel;
  ValueListenable<double> get aiLevel => _aiLevel;

  // ─── Lifecycle ────────────────────────────────────────────────────────

  Future<void> start({
    required String token,
    required String model,
    required String userName,
  }) async {
    if (_started) return;
    _started = true;
    _userName = userName;
    _idleStage = 0;

    await _realtime.connect(token: token, model: model);
    _realtime.sendSessionUpdate();
    // Open the player eagerly so the first response.audio.delta doesn't
    // race an async openPlayer() and drop mid-sentence chunks.
    await _audio.initPlayer();
    await _audio.startRecording();
    _micSub = _audio.micStream?.listen(_onMicChunk);

    _subs.addAll([
      _realtime.onSpeechStarted.listen((_) => _onUserSpeechStarted()),
      _realtime.onSpeechStopped.listen((_) => _onUserSpeechStopped()),
      _realtime.onAIPlaybackStarted.listen((_) => _enterAiSpeaking()),
      _realtime.onAIPlaybackFinished.listen((_) => _exitAiSpeaking()),
      _realtime.onAudioReceived.listen(_onAiAudioChunk),
    ]);

    // Kick off the greeting. The server processes websocket events in order,
    // so session.update (queued above) is guaranteed to take effect before
    // this response.create. The subscriptions are wired up, so the greeting
    // will flow through the normal aiSpeaking → idle path and arm the
    // check-in timer when playback drains.
    _realtime.sendProactiveResponse(_greetingInstructions());
  }

  Future<void> stop() async {
    _resumeTimer?.cancel();
    _idleTimer?.cancel();
    _idleStage = 0;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _micSub?.cancel();
    _micSub = null;
    await _audio.stopRecording();
    await _audio.stopPlayback();
    _realtime.disconnect();
    _state.value = ConversationState.idle;
    _micLevel.value = 0;
    _aiLevel.value = 0;
    _micLevelProcessor.reset();
    _aiLevelProcessor.reset();
    _started = false;
  }

  // ─── Mic path ─────────────────────────────────────────────────────────

  void _onMicChunk(Uint8List chunk) {
    // Belt-and-suspenders: even if the hardware pause hasn't taken effect
    // yet, never forward audio while the AI is speaking.
    if (_state.value == ConversationState.aiSpeaking) return;
    _realtime.sendAudio(chunk);
    _micLevel.value = _micLevelProcessor.process(chunk);
  }

  // ─── AI playback path ─────────────────────────────────────────────────

  void _onAiAudioChunk(Uint8List bytes) {
    _audio.playAudioChunk(bytes);
    _aiLevel.value = _aiLevelProcessor.process(bytes);
  }

  // ─── State transitions ────────────────────────────────────────────────

  void _onUserSpeechStarted() {
    // Ignore VAD blips while AI is speaking (shouldn't happen — mic is
    // paused — but be defensive).
    if (_state.value == ConversationState.aiSpeaking) return;
    _state.value = ConversationState.userSpeaking;
    // Any real user speech cancels a pending nudge and re-arms the full
    // check-in → re-engage sequence for the next idle window.
    _idleTimer?.cancel();
    _idleStage = 0;
  }

  void _onUserSpeechStopped() {
    if (_state.value == ConversationState.userSpeaking) {
      _state.value = ConversationState.idle;
    }
  }

  void _enterAiSpeaking() {
    _resumeTimer?.cancel();
    _idleTimer?.cancel();
    _state.value = ConversationState.aiSpeaking;
    _micLevel.value = 0;
    _micLevelProcessor.reset();
    // NOTE: intentionally not calling _audio.pauseRecording() here. On iOS
    // that toggles the shared AVAudioSession and cuts the player off
    // mid-sentence. The state gate in [_onMicChunk] already drops every
    // mic chunk while we're in aiSpeaking, which is enough to break the
    // echo loop as long as the state is held until playback fully drains.
  }

  void _exitAiSpeaking() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resumeGuard, () {
      _state.value = ConversationState.idle;
      _aiLevel.value = 0;
      _aiLevelProcessor.reset();
      // We're now truly idle (mic is live, speaker is drained). This is
      // the single scheduling point for the check-in / re-engage timers.
      _scheduleIdleTimer();
    });
  }

  // ─── Proactive conversation (greeting / check-in / re-engage) ─────────

  void _scheduleIdleTimer() {
    _idleTimer?.cancel();
    final delay = switch (_idleStage) {
      0 => _checkInAfter,
      1 => _reEngageAfter,
      _ => null, // stage 2 is terminal — stay silent until user speaks
    };
    if (delay == null) return;
    _idleTimer = Timer(delay, _onIdleTimerFired);
  }

  void _onIdleTimerFired() {
    if (_state.value != ConversationState.idle) return;
    if (_idleStage == 0) {
      _idleStage = 1;
      _realtime.sendProactiveResponse(_checkInInstructions());
    } else if (_idleStage == 1) {
      _idleStage = 2;
      _realtime.sendProactiveResponse(_reEngageInstructions());
    }
  }

  String _greetingInstructions() =>
      "Greet $_userName warmly in a single short sentence. "
      "Invite them to start talking about anything they like. "
      "Keep it under 15 words and sound natural.";

  String _checkInInstructions() =>
      "$_userName has been quiet for a little while. "
      "Gently check in with one short, friendly question to get them talking. "
      "Keep it under 15 words.";

  String _reEngageInstructions() =>
      "$_userName is still quiet. Offer one easy, concrete topic or question "
      "they can respond to (e.g. weekend, food, studies). "
      "Keep it warm, under 20 words, and don't pressure them.";

  // ─── Interrupt (tap-to-interrupt, ChatGPT-style) ──────────────────────

  /// Called by the UI when the user wants to cut the AI off mid-sentence.
  /// Stops playback, tells OpenAI to cancel, and hands the turn back.
  Future<void> interrupt() async {
    if (_state.value != ConversationState.aiSpeaking) return;
    _resumeTimer?.cancel();
    _realtime.cancelResponse();
    await _audio.stopPlayback();
    _state.value = ConversationState.idle;
    _aiLevel.value = 0;
    _aiLevelProcessor.reset();
    // Re-arm the idle sequence after a manual interrupt so a nudge still
    // fires if the user taps-to-interrupt then stays silent.
    _scheduleIdleTimer();
  }

  void dispose() {
    _resumeTimer?.cancel();
    _idleTimer?.cancel();
    _state.dispose();
    _micLevel.dispose();
    _aiLevel.dispose();
  }
}
