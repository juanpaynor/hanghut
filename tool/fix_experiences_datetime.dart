import 'package:supabase/supabase.dart';

Future<void> main() async {
  final supabaseUrl = 'https://rahhezqtkpvkialnduft.supabase.co';
  final supabaseKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJhaGhlenF0a3B2a2lhbG5kdWZ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQzMzk2NDAsImV4cCI6MjA3OTkxNTY0MH0.6dKJKlaAU2tSiu0lcDatiXkf59yCz8eHMq04KBQer3I';

  final client = SupabaseClient(supabaseUrl, supabaseKey);

  try {
    // We only update where is_experience = true and datetime is in the past or close to now.
    // To be safe, let's just update all experiences to 365 days from now.
    final futureDate = DateTime.now()
        .add(const Duration(days: 365))
        .toIso8601String();

    final response = await client
        .from('tables')
        .update({'datetime': futureDate})
        .eq('is_experience', true)
        .select('id, title, datetime');

    print('✅ Fixed ${response.length} experiences to expire in 365 days:');
    for (var t in response) {
      print(
        '- ${t['title']} (ID: ${t['id']}) -> new datetime: ${t['datetime']}',
      );
    }
  } catch (e) {
    print('❌ Error updating experiences: $e');
  }
}
