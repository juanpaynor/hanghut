import 'package:flutter_dotenv/flutter_dotenv.dart';

class AblyConfig {
  static String get apiKey => dotenv.env['ABLY_API_KEY'] ?? '';
}
