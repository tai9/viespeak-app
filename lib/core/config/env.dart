import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? '';
  static String get wsBaseUrl => dotenv.env['WS_BASE_URL'] ?? '';
  static bool get devMode => dotenv.env['DEV_MODE']?.toLowerCase() == 'true';
}
