import 'dart:async';
import 'dart:typed_data';

import 'ws_service.dart';

class MockWsService extends WsService {
  Timer? _mockTimer;
  int _messageIndex = 0;

  static const _mockConversation = [
    {'speaker': 'assistant', 'text': 'Hey Minh! Good to see you again. How\'s it going?'},
    {'speaker': 'user', 'text': 'Hi Alex! I\'m doing good, just finished my midterm exams.'},
    {'speaker': 'assistant', 'text': 'Oh nice! How did they go? I remember you were pretty stressed about the database systems one...'},
    {'speaker': 'user', 'text': 'Actually it went better than I expected! I think the practice we did on normalization helped a lot.'},
    {'speaker': 'assistant', 'text': 'That\'s awesome to hear! You know, I had a similar experience back in uni... hmm, I think the thing that really clicked for me was when I started thinking about it in terms of real projects instead of just theory.'},
    {'speaker': 'user', 'text': 'Yeah that makes sense. By the way, I started working on my graduation thesis about microservices.'},
    {'speaker': 'assistant', 'text': 'Oh cool! Microservices is a great topic. What angle are you taking? Like... are you comparing it with monoliths, or more focused on a specific pattern?'},
    {'speaker': 'user', 'text': 'I want to build a small e-commerce system and compare the performance.'},
    {'speaker': 'assistant', 'text': 'I mean, that\'s actually a really practical approach. One thing I\'d suggest though — make sure you define clear metrics upfront. Like response time, throughput, deployment frequency... it\'ll make your comparison much more convincing.'},
  ];

  @override
  Future<void> connect({required String token, required String major}) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _messageIndex = 0;
    _startMockConversation();
  }

  void _startMockConversation() {
    _mockTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_messageIndex >= _mockConversation.length) {
        timer.cancel();
        return;
      }
      transcriptController.add(_mockConversation[_messageIndex]);
      _messageIndex++;
    });
  }

  @override
  void sendAudio(Uint8List audioData) {
    // no-op in mock
  }

  @override
  void disconnect() {
    _mockTimer?.cancel();
    _mockTimer = null;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
