import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import 'audio_service.dart';
import 'voice_turn_service.dart';

/// High-level states for a voice turn. See `FE-Voice-Integration.md §7`:
///
///   listening ──VAD stop──▶ thinking ──reply ready──▶ speaking
///     ▲                                                   │
///     └───────────────playback done──────────────────────┘
///
/// [idle] is the pre-start / post-stop state and is never visited during a
/// running conversation.
enum VoiceTurnState { idle, listening, thinking, speaking }

/// Orchestrates the full voice-in turn loop:
///
/// 1. Records the user via [AudioService.startVoiceRecording].
/// 2. Runs a simple amplitude-based VAD on
///    [AudioService.voiceAmplitudeStream]; stops the turn after 700 ms of
///    silence (or the 30 s hard cap).
/// 3. Uploads the recording through [VoiceTurnService.turn].
/// 4. Plays the reply MP3 through an owned [AudioPlayer] as soon as it
///    lands, and loops back to listening when playback drains.
///
/// The UI reads [state] and the transcript streams; it does not touch the
/// recorder or the reply player directly.
class VoiceTurnController {
  VoiceTurnController({
    required VoiceTurnService service,
    required AudioService audio,
  })  : _service = service,
        _audio = audio;

  final VoiceTurnService _service;
  final AudioService _audio;

  /// Plays the reply MP3 once the backend has returned it.
  final AudioPlayer _replyPlayer = AudioPlayer();

  final ValueNotifier<VoiceTurnState> _state =
      ValueNotifier(VoiceTurnState.idle);

  final _userTranscriptController = StreamController<String>.broadcast();
  final _assistantTranscriptController = StreamController<String>.broadcast();
  final _errorController = StreamController<Object>.broadcast();
  final _amplitudeController = StreamController<double>.broadcast();

  // VAD tuning. The FE doc suggests 500–800 ms of trailing silence, amp
  // threshold tuned on top of the `record` package's dBFS scale
  // (-160 .. 0). We use stream mode on iOS, where `getAmplitude()`
  // reports peak-sample dBFS from the PCM16 tap — real speech peaks at
  // ~-20..-5 dBFS, quiet room noise peaks at ~-50..-40, so -35 is a
  // comfortable speech/noise cutoff. `_minSpeechMs` + hangover gate
  // catches the rest.
  static const _silenceHangoverMs = 700;
  static const _minSpeechMs = 500;
  static const _maxTurnMs = 30000;
  static const _speechThresholdDb = -35.0;

  StreamSubscription<Amplitude>? _ampSub;
  StreamSubscription<PlayerState>? _replySub;
  Timer? _silenceTimer;
  Timer? _maxTurnTimer;
  DateTime? _firstSpeechAt;
  DateTime? _lastSpeechAt;
  int _ampSampleCount = 0;
  String? _sessionId;
  Future<VoiceTurnResult>? _inflight;
  int _turnToken = 0;
  bool _running = false;

  ValueListenable<VoiceTurnState> get state => _state;
  Stream<String> get onUserTranscript => _userTranscriptController.stream;
  Stream<String> get onAssistantTranscript =>
      _assistantTranscriptController.stream;
  Stream<Object> get onError => _errorController.stream;

  /// Coarse user-speech amplitude in dBFS (roughly -160..0). Bridges the
  /// VAD amplitude to the UI so the orb can pulse while the user talks.
  Stream<double> get onAmplitude => _amplitudeController.stream;

  // ─── Lifecycle ────────────────────────────────────────────────────────

  /// Begins a conversation bound to [sessionId]. Kicks off the first
  /// listening turn immediately. Safe to call only once per controller
  /// instance.
  Future<void> start({required String sessionId}) async {
    if (_running) return;
    _running = true;
    _sessionId = sessionId;

    _replySub = _replyPlayer.playerStateStream.listen(_onReplyPlayerState);

    await _beginListeningTurn();
  }

  /// Tears the controller down: stops recording and reply playback;
  /// cancels any in-flight request (by orphaning it — the request itself
  /// can't be cancelled mid-flight but the response will be ignored once
  /// [_turnToken] has moved on).
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _turnToken++;

    _cancelTurnTimers();
    await _ampSub?.cancel();
    _ampSub = null;
    await _replySub?.cancel();
    _replySub = null;

    try {
      await _audio.stopVoiceRecording();
    } catch (_) {}
    try {
      await _replyPlayer.stop();
    } catch (_) {}

    _state.value = VoiceTurnState.idle;
  }

  /// Mid-reply interrupt: stop playback, drop any in-flight turn, return
  /// to listening. Safe to call in any state.
  Future<void> interrupt() async {
    if (!_running) return;
    _turnToken++; // orphan any pending turn

    _cancelTurnTimers();
    await _ampSub?.cancel();
    _ampSub = null;

    try {
      await _replyPlayer.stop();
    } catch (_) {}
    try {
      await _audio.stopVoiceRecording();
    } catch (_) {}

    await _beginListeningTurn();
  }

  void dispose() {
    _cancelTurnTimers();
    _ampSub?.cancel();
    _replySub?.cancel();
    _replyPlayer.dispose();
    _userTranscriptController.close();
    _assistantTranscriptController.close();
    _errorController.close();
    _amplitudeController.close();
    _state.dispose();
  }

  // ─── Listening turn ───────────────────────────────────────────────────

  Future<void> _beginListeningTurn() async {
    if (!_running) return;
    _state.value = VoiceTurnState.listening;
    _firstSpeechAt = null;
    _lastSpeechAt = null;
    _ampSampleCount = 0;

    try {
      await _audio.startVoiceRecording();
    } catch (e) {
      _errorController.add(e);
      _state.value = VoiceTurnState.idle;
      return;
    }

    _ampSub = _audio
        .voiceAmplitudeStream(interval: const Duration(milliseconds: 100))
        .listen(_onAmplitude, onError: (Object e) {
      debugPrint('[VoiceTurn] amplitude stream error: $e');
    });

    _maxTurnTimer = Timer(
      const Duration(milliseconds: _maxTurnMs),
      _endUserTurn,
    );
  }

  void _onAmplitude(Amplitude amp) {
    // `record` reports dBFS in [-160, 0]. Above threshold = speech.
    final db = amp.current;
    _amplitudeController.add(db);

    // Log every ~500 ms so we can see the meter on-device without
    // drowning the console. Drop this once VAD is dialed in.
    _ampSampleCount++;
    if (_ampSampleCount % 5 == 0) {
      debugPrint(
        '[VoiceTurn] amp=${db.toStringAsFixed(1)} dBFS '
        '(threshold=${_speechThresholdDb.toStringAsFixed(1)})',
      );
    }

    if (db > _speechThresholdDb) {
      final now = DateTime.now();
      _firstSpeechAt ??= now;
      _lastSpeechAt = now;
      _silenceTimer?.cancel();
      _silenceTimer = Timer(
        const Duration(milliseconds: _silenceHangoverMs),
        _maybeEndOnSilence,
      );
    }
  }

  void _maybeEndOnSilence() {
    if (_state.value != VoiceTurnState.listening) return;
    final firstSpeech = _firstSpeechAt;
    final lastSpeech = _lastSpeechAt;
    if (firstSpeech == null || lastSpeech == null) return;
    // Actual span of detected speech, not elapsed-since-recording-start.
    final speechSpanMs = lastSpeech.difference(firstSpeech).inMilliseconds;
    if (speechSpanMs < _minSpeechMs) {
      // The user barely spoke — don't send a meaningless turn. Rearm the
      // silence timer so we'll still auto-close on the next lull.
      _silenceTimer = Timer(
        const Duration(milliseconds: _silenceHangoverMs),
        _maybeEndOnSilence,
      );
      return;
    }
    debugPrint(
      '[VoiceTurn] VAD end: speechSpan=${speechSpanMs}ms → uploading turn',
    );
    _endUserTurn();
  }

  // ─── Thinking turn ────────────────────────────────────────────────────

  Future<void> _endUserTurn() async {
    if (_state.value != VoiceTurnState.listening) return;
    _cancelTurnTimers();
    await _ampSub?.cancel();
    _ampSub = null;

    final path = await _audio.stopVoiceRecording();
    if (path == null) {
      debugPrint('[VoiceTurn] no recording path on endUserTurn');
      await _beginListeningTurn();
      return;
    }

    _state.value = VoiceTurnState.thinking;
    final myToken = ++_turnToken;

    _inflight = _service.turn(sessionId: _sessionId!, audioPath: path);

    try {
      final result = await _inflight!;
      if (myToken != _turnToken || !_running) return;
      await _onTurnReady(result);
    } catch (e) {
      if (myToken != _turnToken || !_running) return;
      debugPrint('[VoiceTurn] turn failed: $e');
      _errorController.add(e);
      await _beginListeningTurn();
    } finally {
      _inflight = null;
    }
  }

  // ─── Speaking turn ────────────────────────────────────────────────────

  Future<void> _onTurnReady(VoiceTurnResult result) async {
    if (result.userText.trim().isNotEmpty) {
      _userTranscriptController.add(result.userText);
    }
    if (result.assistantText.trim().isNotEmpty) {
      _assistantTranscriptController.add(result.assistantText);
    }

    if (result.audio.isEmpty) {
      debugPrint('[VoiceTurn] empty reply audio — skipping playback');
      await _beginListeningTurn();
      return;
    }

    _state.value = VoiceTurnState.speaking;
    debugPrint(
      '[VoiceTurn] onTurnReady: audio=${result.audio.length}B, '
      'pipeline=${result.pipelineMs.total}ms — starting reply player',
    );

    try {
      // The record package leaves the AVAudioSession in .playAndRecord,
      // which hardware-caps speaker volume on iOS. Switch to .playback
      // for the reply so the speaker runs at full device volume. The
      // record package will set it back to .playAndRecord when the next
      // recording starts.
      if (Platform.isIOS) {
        await AVAudioSession().setCategory(
          AVAudioSessionCategory.playback,
          AVAudioSessionCategoryOptions.none,
        );
      }
      await _replyPlayer.setVolume(1.0);
      await _replyPlayer.setAudioSource(_ReplyBytesSource(result.audio));
      unawaited(_replyPlayer.play());
    } catch (e, st) {
      debugPrint('[VoiceTurn] reply playback failed: $e\n$st');
      _errorController.add(e);
      await _beginListeningTurn();
      return;
    }
  }

  void _onReplyPlayerState(PlayerState ps) {
    if (!_running) return;
    debugPrint(
      '[VoiceTurn] replyPlayer state: '
      'playing=${ps.playing} processing=${ps.processingState}',
    );
    if (ps.processingState == ProcessingState.completed) {
      if (_state.value == VoiceTurnState.speaking) {
        _replyPlayer.stop();
        _beginListeningTurn();
      }
    }
  }

  // ─── Housekeeping ─────────────────────────────────────────────────────

  void _cancelTurnTimers() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _maxTurnTimer?.cancel();
    _maxTurnTimer = null;
  }
}

/// In-memory MP3 buffer wrapper for the reply player. See the twin in
/// `filler_audio_service.dart` — kept private to each file so neither
/// leaks its audio pipeline onto the other.
// ignore: experimental_member_use
class _ReplyBytesSource extends StreamAudioSource {
  final Uint8List _bytes;
  _ReplyBytesSource(this._bytes);

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/mpeg',
    );
  }
}
