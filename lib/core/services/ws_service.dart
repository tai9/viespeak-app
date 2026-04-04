import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/env.dart';

class WsService {
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

  Future<void> connect({required String token}) async {
    final baseUrl = Env.wsBaseUrl.isNotEmpty ? Env.wsBaseUrl : Env.apiBaseUrl;
    final scheme = baseUrl.startsWith('https') ? 'wss' : 'ws';
    final host = baseUrl.replaceFirst(RegExp(r'https?://'), '');
    // Also strip ws:// or wss:// if wsBaseUrl already has the scheme
    final cleanHost = host.replaceFirst(RegExp(r'wss?://'), '');
    final wsUrl = '$scheme://$cleanHost/ws/voice?token=$token';

    debugPrint('[WS] Connecting to $wsUrl');
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _isActive = true;
    debugPrint('[WS] Channel created, listening for events');

    _channel!.stream.listen(
      _handleEvent,
      onError: (e) {
        debugPrint('[WS] Error: $e');
        errorController.add(e.toString());
      },
      onDone: () {
        debugPrint('[WS] Connection closed');
        _isActive = false;
        doneController.add(null);
      },
    );
  }

  void _handleEvent(dynamic message) {
    final event = jsonDecode(message as String) as Map<String, dynamic>;
    final type = event['type'] as String? ?? '';
    debugPrint('[WS] Event: $type');

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

  /// Send PCM16 audio chunk wrapped in input_audio_buffer.append event
  void sendAudio(Uint8List pcm16Bytes) {
    if (!_isActive) return;
    _channel?.sink.add(jsonEncode({
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcm16Bytes),
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
