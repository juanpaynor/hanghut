import 'package:supabase/supabase.dart';

Future<void> main() async {
  final supabaseUrl = 'https://rahhezqtkpvkialnduft.supabase.co';
  final supabaseKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJhaGhlenF0a3B2a2lhbG5kdWZ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQzMzk2NDAsImV4cCI6MjA3OTkxNTY0MH0.6dKJKlaAU2tSiu0lcDatiXkf59yCz8eHMq04KBQer3I';

  final client = SupabaseClient(supabaseUrl, supabaseKey);

  try {
    final response = await client
        .from('experience_purchase_intents')
        .select()
        .order('created_at', ascending: false)
        .limit(5);

    print('Recent Experience Intents: \${(response as List).length}');
    for (var intent in response) {
      print(
        "- ID: \${intent['id']}, table: \${intent['table_id']}, status: \${intent['status']}",
      );
    }
  } catch (e) {
    print('Error reading experience intents: $e');
  }

  try {
    final response2 = await client
        .from('purchase_intents')
        .select()
        .order('created_at', ascending: false)
        .limit(5);

    print('\\nRecent Event Intents: \${(response2 as List).length}');
    for (var intent in response2) {
      print(
        "- ID: \${intent['id']}, event: \${intent['event_id']}, status: \${intent['status']}",
      );
    }
  } catch (e) {
    print('Error reading event intents: $e');
  }
}
