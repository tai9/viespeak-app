import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// 24 kHz, mono, PCM16 → 48000 bytes per second of playback.
const int _bytesPerSecond = 24000 * 2;

class RealtimeService {
  WebSocketChannel? _channel;
  bool _isActive = false;
  bool _hasActiveResponse = false;

  // Byte accounting used to estimate when the speaker has finished draining
  // AI audio, so the controller knows it's safe to un-pause the mic.
  int _pendingAudioBytes = 0;
  DateTime? _firstAudioAt;
  Timer? _drainTimer;

  // --- Event streams ---
  @protected
  final sessionReadyController = StreamController<void>.broadcast();
  @protected
  final audioController = StreamController<Uint8List>.broadcast();
  @protected
  final aiTranscriptDeltaController = StreamController<String>.broadcast();
  @protected
  final aiTranscriptDoneController = StreamController<String>.broadcast();
  @protected
  final userTranscriptController = StreamController<String>.broadcast();
  @protected
  final speechStartedController = StreamController<void>.broadcast();
  @protected
  final speechStoppedController = StreamController<void>.broadcast();
  @protected
  final errorController = StreamController<String>.broadcast();
  @protected
  final doneController = StreamController<void>.broadcast();
  @protected
  final aiPlaybackStartedController = StreamController<void>.broadcast();
  @protected
  final aiPlaybackFinishedController = StreamController<void>.broadcast();

  Stream<void> get onSessionReady => sessionReadyController.stream;
  Stream<Uint8List> get onAudioReceived => audioController.stream;
  Stream<String> get onAITranscriptDelta => aiTranscriptDeltaController.stream;
  Stream<String> get onAITranscriptDone => aiTranscriptDoneController.stream;
  Stream<String> get onUserTranscript => userTranscriptController.stream;
  Stream<void> get onSpeechStarted => speechStartedController.stream;
  Stream<void> get onSpeechStopped => speechStoppedController.stream;
  Stream<String> get onError => errorController.stream;
  Stream<void> get onDone => doneController.stream;

  /// Fires when the AI response starts (before the first audio chunk plays).
  /// The controller uses this to enter AI_SPEAKING and pause the mic.
  Stream<void> get onAIPlaybackStarted => aiPlaybackStartedController.stream;

  /// Fires when the estimated playback drain window has elapsed — i.e. the
  /// speaker should be done playing the queued PCM and it's safe to resume
  /// the mic without capturing the AI's own voice.
  Stream<void> get onAIPlaybackFinished => aiPlaybackFinishedController.stream;

  bool get isConnected => _isActive;

  /// Connect directly to OpenAI Realtime API using ephemeral token
  Future<void> connect({
    required String token,
    required String model,
  }) async {
    final wsUrl = 'wss://api.openai.com/v1/realtime?model=$model';
    debugPrint('[Realtime] Connecting to OpenAI Realtime API');

    _channel = WebSocketChannel.connect(
      Uri.parse(wsUrl),
      protocols: ['realtime', 'openai-insecure-api-key.$token', 'openai-beta.realtime-v1'],
    );
    _isActive = true;

    _channel!.stream.listen(
      _handleEvent,
      onError: (e) {
        debugPrint('[Realtime] Error: $e');
        errorController.add(e.toString());
      },
      onDone: () {
        debugPrint('[Realtime] Connection closed');
        _isActive = false;
        doneController.add(null);
      },
    );
  }

  void _handleEvent(dynamic message) {
    final event = jsonDecode(message as String) as Map<String, dynamic>;
    final type = event['type'] as String? ?? '';
    debugPrint('[Realtime] Event: $type');

    switch (type) {
      case 'session.created':
      case 'session.updated':
        sessionReadyController.add(null);

      case 'response.created':
        _hasActiveResponse = true;
        _pendingAudioBytes = 0;
        _firstAudioAt = null;
        _drainTimer?.cancel();
        aiPlaybackStartedController.add(null);

      case 'response.done':
      case 'response.cancelled':
        _hasActiveResponse = false;
        _scheduleDrain();

      case 'response.audio.delta':
        final delta = event['delta'] as String?;
        if (delta != null) {
          final bytes = base64Decode(delta);
          _pendingAudioBytes += bytes.length;
          _firstAudioAt ??= DateTime.now();
          audioController.add(bytes);
        }

      case 'response.audio_transcript.delta':
        final delta = event['delta'] as String?;
        if (delta != null) {
          aiTranscriptDeltaController.add(delta);
        }

      case 'response.audio_transcript.done':
        final transcript = event['transcript'] as String?;
        if (transcript != null) {
          aiTranscriptDoneController.add(transcript);
        }

      case 'conversation.item.input_audio_transcription.completed':
        final transcript = event['transcript'] as String?;
        if (transcript != null) {
          userTranscriptController.add(transcript);
        }

      case 'input_audio_buffer.speech_started':
        speechStartedController.add(null);

      case 'input_audio_buffer.speech_stopped':
        speechStoppedController.add(null);

      case 'error':
        final error = event['error'] as Map<String, dynamic>?;
        final message = error?['message'] as String? ?? 'Unknown error';
        errorController.add(message);
    }
  }

  /// Send session.update to configure audio format and VAD
  void sendSessionUpdate() {
    if (!_isActive) return;
    _channel?.sink.add(jsonEncode({
      'type': 'session.update',
      'session': {
        'modalities': ['audio', 'text'],
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'input_audio_transcription': {'model': 'whisper-1'},
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.5,
          'silence_duration_ms': 800,
        },
      },
    }));
  }

  /// Send PCM16 audio chunk to OpenAI. The caller (ConversationController)
  /// is responsible for ensuring we're not in AI_SPEAKING state — the mic
  /// is hardware-paused during AI playback so this method won't be invoked
  /// with echo samples.
  void sendAudio(Uint8List pcm16Bytes) {
    if (!_isActive) return;
    _channel?.sink.add(jsonEncode({
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcm16Bytes),
    }));
  }

  /// After OpenAI finishes generating a response, the speaker is still
  /// playing out the queued PCM. Estimate how long that will take and fire
  /// [onAIPlaybackFinished] once the buffer should be drained.
  void _scheduleDrain() {
    final start = _firstAudioAt;
    final totalMs = (_pendingAudioBytes * 1000) ~/ _bytesPerSecond;
    final elapsedMs = start == null
        ? 0
        : DateTime.now().difference(start).inMilliseconds;
    // + safety margin for flutter_sound's internal player buffer, which
    // keeps playing for a few hundred ms after the last byte is fed.
    final remainingMs = (totalMs - elapsedMs).clamp(0, 60000) + 700;
    _drainTimer?.cancel();
    _drainTimer = Timer(Duration(milliseconds: remainingMs), () {
      _pendingAudioBytes = 0;
      _firstAudioAt = null;
      aiPlaybackFinishedController.add(null);
      // Safety: clear any stale samples the server may still have buffered.
      if (_isActive) {
        _channel?.sink.add(jsonEncode({
          'type': 'input_audio_buffer.clear',
        }));
      }
    });
  }

  /// Cancel current AI response (on user interruption).
  /// No-op if there is no in-progress response — otherwise OpenAI returns
  /// "Cancellation failed: no active response".
  void cancelResponse() {
    if (!_isActive || !_hasActiveResponse) return;
    _hasActiveResponse = false;
    _channel?.sink.add(jsonEncode({
      'type': 'response.cancel',
    }));
  }

  bool get hasActiveResponse => _hasActiveResponse;

  void disconnect() {
    _isActive = false;
    _drainTimer?.cancel();
    _hasActiveResponse = false;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    sessionReadyController.close();
    audioController.close();
    aiTranscriptDeltaController.close();
    aiTranscriptDoneController.close();
    userTranscriptController.close();
    speechStartedController.close();
    speechStoppedController.close();
    errorController.close();
    doneController.close();
    aiPlaybackStartedController.close();
    aiPlaybackFinishedController.close();
  }
}
