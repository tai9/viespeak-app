import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RealtimeService {
  WebSocketChannel? _channel;
  bool _isActive = false;

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

  Stream<void> get onSessionReady => sessionReadyController.stream;
  Stream<Uint8List> get onAudioReceived => audioController.stream;
  Stream<String> get onAITranscriptDelta => aiTranscriptDeltaController.stream;
  Stream<String> get onAITranscriptDone => aiTranscriptDoneController.stream;
  Stream<String> get onUserTranscript => userTranscriptController.stream;
  Stream<void> get onSpeechStarted => speechStartedController.stream;
  Stream<void> get onSpeechStopped => speechStoppedController.stream;
  Stream<String> get onError => errorController.stream;
  Stream<void> get onDone => doneController.stream;

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

      case 'response.audio.delta':
        final delta = event['delta'] as String?;
        if (delta != null) {
          audioController.add(base64Decode(delta));
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

  /// Send PCM16 audio chunk to OpenAI
  void sendAudio(Uint8List pcm16Bytes) {
    if (!_isActive) return;
    _channel?.sink.add(jsonEncode({
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcm16Bytes),
    }));
  }

  /// Cancel current AI response (on user interruption)
  void cancelResponse() {
    if (!_isActive) return;
    _channel?.sink.add(jsonEncode({
      'type': 'response.cancel',
    }));
  }

  void disconnect() {
    _isActive = false;
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
  }
}
