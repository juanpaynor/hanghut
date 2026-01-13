import 'package:flutter_dotenv/flutter_dotenv.dart';

class AblyConfig {
  // IMPORTANT: Replace with your actual Ably API key!
  static const String _fallbackKey =
      'teFpNA.pY6r_Q:Dos8YhqrxkVIOB8IqxKIrqWSPJl3meLuBpm3q776yj0';

  static String get apiKey {
    final envKey = dotenv.env['ABLY_API_KEY'] ?? '';
    if (envKey.isNotEmpty) return envKey;

    // Fallback to hardcoded value
    if (_fallbackKey == 'YOUR_ABLY_API_KEY_HERE') {
      throw Exception(
        'CRITICAL: Ably API Key not configured! '
        'Update ably_config.dart with your actual key.',
      );
    }
    return _fallbackKey;
  }
}
