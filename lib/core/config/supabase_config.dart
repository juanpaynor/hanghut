import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseConfig {
  // IMPORTANT: Replace these with your actual values!
  // These are fallbacks for when .env file is missing (e.g., in release builds)
  // Custom domain for the same project — must match SUPABASE_URL in .env so the
  // endpoint is identical whether or not .env loads.
  static const String _fallbackUrl = 'https://api.hanghut.com';
  static const String _fallbackAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJhaGhlenF0a3B2a2lhbG5kdWZ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQzMzk2NDAsImV4cCI6MjA3OTkxNTY0MH0.6dKJKlaAU2tSiu0lcDatiXkf59yCz8eHMq04KBQer3I';

  static String get supabaseUrl {
    final envUrl = dotenv.env['SUPABASE_URL'] ?? '';
    if (envUrl.isNotEmpty) return envUrl;

    // Fallback to hardcoded values
    if (_fallbackUrl == 'YOUR_SUPABASE_URL_HERE') {
      throw Exception(
        'CRITICAL: Supabase URL not configured! '
        'Either add .env file or update supabase_config.dart with your actual URL.',
      );
    }
    return _fallbackUrl;
  }

  static String get supabaseAnonKey {
    final envKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    if (envKey.isNotEmpty) return envKey;

    // Fallback to hardcoded values
    if (_fallbackAnonKey == 'YOUR_SUPABASE_ANON_KEY_HERE') {
      throw Exception(
        'CRITICAL: Supabase Anon Key not configured! '
        'Either add .env file or update supabase_config.dart with your actual key.',
      );
    }
    return _fallbackAnonKey;
  }

  // Initialize Supabase (call this in main.dart before runApp)
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        // Pin the session storage key. supabase_flutter otherwise derives it as
        // "sb-<url-host-first-segment>-auth-token", so changing the Supabase URL
        // (api.hanghut.com vs the raw project URL used as .env-missing fallback)
        // changes the key and silently logs everyone out — and flip-flops on
        // every launch where .env fails to load. 'sb-api-auth-token' is the key
        // already in use with api.hanghut.com, so current sessions are kept.
        localStorage: SharedPreferencesLocalStorage(
          persistSessionKey: 'sb-api-auth-token',
        ),
      ),
    );
  }

  // Get Supabase client instance
  static SupabaseClient get client => Supabase.instance.client;

  // Convenience getters
  static GoTrueClient get auth => client.auth;
  static SupabaseStorageClient get storage => client.storage;
  static PostgrestClient get db => client.from('') as PostgrestClient;
}
