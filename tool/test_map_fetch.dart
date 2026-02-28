import 'dart:io';
import 'package:supabase/supabase.dart';

Future<void> main() async {
  final supabaseUrl = 'https://rahhezqtkpvkialnduft.supabase.co';
  final supabaseKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJhaGhlenF0a3B2a2lhbG5kdWZ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQzMzk2NDAsImV4cCI6MjA3OTkxNTY0MH0.6dKJKlaAU2tSiu0lcDatiXkf59yCz8eHMq04KBQer3I';

  final client = SupabaseClient(supabaseUrl, supabaseKey);

  try {
    final response = await client
        .from('tables')
        .select(
          'id, title, is_experience, status, datetime, latitude, longitude, experience_type, images, video_url',
        )
        .eq('is_experience', true)
        .order('updated_at', ascending: false)
        .limit(2);

    final tables = List<Map<String, dynamic>>.from(response);
    print('Found ${tables.length} experiences recently updated:');
    for (var t in tables) {
      print('''
ID: ${t['id']}
Title: ${t['title']}
Status: ${t['status']}
Datetime: ${t['datetime']}
Lat, Lng: ${t['latitude']}, ${t['longitude']}
Images: ${t['images']}
Video: ${t['video_url']}
''');
    }
  } catch (e) {
    print('Error from tables: $e');
  }

  // Also check map_ready_tables
  try {
    final response2 = await client
        .from('map_ready_tables')
        .select('id, title, is_experience')
        .eq('is_experience', true)
        .order('scheduled_time', ascending: false)
        .limit(2);

    print('Experiences in map_ready_tables:');
    for (var t in response2) {
      print('ID: ${t['id']} -> ${t['title']}');
    }
  } catch (e) {
    print('Error from map_ready_tables: $e');
  }
}
