import 'package:bitemates/core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReportService {
  final SupabaseClient _client = SupabaseConfig.client;

  Future<void> submitReport({
    required String targetType, // 'user', 'table', 'message'
    required String targetId,
    required String reasonCategory,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Must be logged in to report.');
    }

    try {
      await _client.from('reports').insert({
        'reporter_id': user.id,
        'target_type': targetType,
        'target_id': targetId,
        'reason_category': reasonCategory,
        'description': description,
        'metadata': metadata ?? {},
        'status': 'pending',
      });
    } catch (e) {
      print('❌ Error submitting report: $e');
      throw Exception('Failed to submit report. Please try again.');
    }
  }
}
