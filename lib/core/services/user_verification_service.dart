import 'dart:io';
import 'package:bitemates/core/config/supabase_config.dart';

class UserVerificationService {
  final String _bucketName = 'verification-docs';
  final String _tableName = 'user_verifications';

  // Check verification status
  Future<Map<String, dynamic>?> getVerificationStatus() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await SupabaseConfig.client
          .from(_tableName)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .maybeSingle();

      return response;
    } catch (e) {
      print('❌ VERIFY SERVICE: Error checking status - $e');
      return null;
    }
  }

  // Submit new verification
  Future<Map<String, dynamic>> submitVerification({
    required File idFront,
    required File idBack,
    required File selfie,
  }) async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // 1. Upload Images
      final frontUrl = await _uploadImage(userId, idFront, 'id_front');
      final backUrl = await _uploadImage(userId, idBack, 'id_back');
      final selfieUrl = await _uploadImage(userId, selfie, 'selfie');

      if (frontUrl == null || backUrl == null || selfieUrl == null) {
        return {'success': false, 'message': 'Failed to upload images'};
      }

      // 2. Create Record
      await SupabaseConfig.client.from(_tableName).insert({
        'user_id': userId,
        'status': 'pending',
        'id_front_url': frontUrl,
        'id_back_url': backUrl,
        'selfie_url': selfieUrl,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      return {
        'success': true,
        'message': 'Verification submitted successfully!',
      };
    } catch (e) {
      print('❌ VERIFY SERVICE: Error submitting - $e');
      return {
        'success': false,
        'message': 'Submission failed: ${e.toString()}',
      };
    }
  }

  Future<String?> _uploadImage(String userId, File file, String type) async {
    try {
      final fileExt = file.path.split('.').last;
      final fileName =
          '${userId}/$type-${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await SupabaseConfig.client.storage
          .from(_bucketName)
          .upload(fileName, file);

      // Files in verification-docs should be PRIVATE, but we need the path for the Admin to sign URL later.
      // Or if we want to store the "path" as the URL.
      // `getPublicUrl` won't work if bucket is private.
      // We'll return the Path so Admin can create SignedURL.
      return fileName;
    } catch (e) {
      print('❌ VERIFY SERVICE: Upload failed for $type - $e');
      return null;
    }
  }
}
