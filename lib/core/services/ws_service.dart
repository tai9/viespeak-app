import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/env.dart';

class WsService {
  WebSocketChannel? _channel;
  final _transcriptController = StreamController<Map<String, dynamic>>.broadcast();
  final _audioController = StreamController<Uint8List>.broadcast();

  Stream<Map<String, dynamic>> get transcriptStream => _transcriptController.stream;
  Stream<Uint8List> get audioStream => _audioController.stream;

  bool get isConnected => _channel != null;

  Future<void> connect({required String token, required String major}) async {
    final uri = Uri.parse('${Env.wsBaseUrl}/ws?major=$major');
    _channel = WebSocketChannel.connect(
      uri,
      protocols: [token],
    );

    await _channel!.ready;

    _channel!.stream.listen(
      (message) {
        if (message is String) {
          final data = jsonDecode(message) as Map<String, dynamic>;
          _transcriptController.add(data);
        } else if (message is List<int>) {
          _audioController.add(Uint8List.fromList(message));
        }
      },
      onError: (error) {
        _transcriptController.addError(error);
      },
      onDone: () {
        disconnect();
      },
    );
  }

  void sendAudio(Uint8List audioData) {
    _channel?.sink.add(audioData);
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _transcriptController.close();
    _audioController.close();
  }
}
