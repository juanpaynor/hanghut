import 'dart:convert';
import 'dart:io';

import 'package:bitemates/core/config/supabase_config.dart';

/// Uploads an answer to a `file` registration question (team_comms #334).
///
/// Three steps, and the middle one deliberately does NOT go through the edge
/// function — a phone photo of an ID is bigger than a function body limit:
///  1. Ask `registration-file-upload` for a signed upload token. It is
///     anonymous-callable on purpose, because guests register too.
///  2. PUT the bytes straight to Supabase Storage with that token.
///  3. Store `answer_template` JSON-encoded as the answer, which is the exact
///     shape web writes, so one organizer Responses tab renders both platforms.
///
/// The `registration-uploads` bucket is private with zero storage policies, so
/// there is no direct-upload path and never was — the token is the only door.
class RegistrationFileService {
  static const String bucket = 'registration-uploads';

  /// Mirrors the server allowlist (#334). Checked here too so a 40 MB photo
  /// fails instantly instead of after a long upload on mobile data.
  static const int maxBytes = 10 * 1024 * 1024;
  static const List<String> allowedTypes = [
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'application/pdf',
  ];

  /// Human-readable cap for hints and error copy.
  static const String limitsLabel = 'JPG, PNG, WEBP, HEIC or PDF, up to 10 MB';

  /// Best-effort content type from a filename. The server re-checks, so a
  /// wrong guess is refused there rather than stored.
  static String? contentTypeFor(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      default:
        return null;
    }
  }

  /// Uploads [file] as the answer to [questionId].
  ///
  /// Returns the answer map to store (`{path, name, size, type}`). Throws
  /// [RegistrationFileException] with a message written for the buyer to read —
  /// the edge function's own `message` is surfaced directly when it sends one.
  Future<Map<String, dynamic>> upload({
    required String eventId,
    required String questionId,
    required File file,
    required String fileName,
  }) async {
    final size = await file.length();
    final type = contentTypeFor(fileName);

    // Local pre-checks: same rules, but no round trip and no wasted upload.
    if (type == null || !allowedTypes.contains(type)) {
      throw const RegistrationFileException(
        'That file type is not accepted. Use a JPG, PNG, WEBP, HEIC or PDF.',
      );
    }
    if (size <= 0) {
      throw const RegistrationFileException('That file appears to be empty.');
    }
    if (size > maxBytes) {
      throw const RegistrationFileException(
        'That file is too large. The limit is 10 MB.',
      );
    }

    final res = await SupabaseConfig.client.functions.invoke(
      'registration-file-upload',
      body: {
        'event_id': eventId,
        'question_id': questionId,
        'file_name': fileName,
        'content_type': type,
        'file_size': size,
      },
    );

    final data = res.data;
    final body = data is String ? jsonDecode(data) : data;
    if (body is! Map || body['success'] != true) {
      String? message;
      if (body is Map) {
        final error = body['error'];
        if (error is Map) message = error['message']?.toString().trim();
      }
      throw RegistrationFileException(
        (message == null || message.isEmpty)
            ? 'Could not start the upload. Please try again.'
            : message,
      );
    }

    final payload = Map<String, dynamic>.from(body['data'] as Map);
    final path = payload['path'].toString();
    final token = payload['token'].toString();

    try {
      await SupabaseConfig.client.storage.from(bucket).uploadToSignedUrl(
            path,
            token,
            file,
          );
    } catch (e) {
      throw RegistrationFileException(
        'The upload did not finish. Check your connection and try again.',
        cause: e,
      );
    }

    // Prefer the server's template so the stored shape is theirs, not ours.
    final template = payload['answer_template'];
    return template is Map
        ? Map<String, dynamic>.from(template)
        : {'path': path, 'name': fileName, 'size': size, 'type': type};
  }

  /// The stored answer, JSON-encoded for `registration_answers.answer` (text).
  static String encodeAnswer(Map<String, dynamic> answer) =>
      jsonEncode(answer);

  /// Reads back a stored answer, whether it arrives as JSON text or a map.
  /// Anything else (e.g. a sentence typed into the old text fallback) yields
  /// null rather than throwing.
  static Map<String, dynamic>? decodeAnswer(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    try {
      final decoded = jsonDecode(raw.toString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}

class RegistrationFileException implements Exception {
  final String message;
  final Object? cause;
  const RegistrationFileException(this.message, {this.cause});

  @override
  String toString() => message;
}
