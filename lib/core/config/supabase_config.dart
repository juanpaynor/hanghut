import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://rahhezqtkpvkialnduft.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJhaGhlenF0a3B2a2lhbG5kdWZ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQzMzk2NDAsImV4cCI6MjA3OTkxNTY0MH0.6dKJKlaAU2tSiu0lcDatiXkf59yCz8eHMq04KBQer3I';

  // Initialize Supabase (call this in main.dart before runApp)
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
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
