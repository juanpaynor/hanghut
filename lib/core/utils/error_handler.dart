import 'package:flutter/material.dart';

/// Centralized error handler that converts system exceptions into
/// user-friendly messages. Never expose raw exceptions to the UI.
class ErrorHandler {
  ErrorHandler._();

  /// Show a user-friendly error SnackBar. Logs the raw error in debug mode.
  static void showError(
    BuildContext context, {
    required dynamic error,
    String? fallbackMessage,
  }) {
    final message = getUserMessage(error, fallback: fallbackMessage);

    // Log the real error for debugging
    debugPrint('⚠️ Error: $error');

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFD32F2F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show a user-friendly success SnackBar.
  static void showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Convert a raw error/exception into a user-friendly string.
  /// Maps known Supabase, network, and platform errors to clean messages.
  static String getUserMessage(dynamic error, {String? fallback}) {
    final raw = error.toString().toLowerCase();

    // ── Network / Connectivity ───────────────────────────────────────────
    if (raw.contains('socketexception') ||
        raw.contains('connection refused') ||
        raw.contains('network is unreachable') ||
        raw.contains('failed host lookup')) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (raw.contains('timeout') || raw.contains('timed out')) {
      return 'The request timed out. Please try again.';
    }
    if (raw.contains('handshake') || raw.contains('certificate')) {
      return 'Secure connection failed. Please try again later.';
    }

    // ── Auth ─────────────────────────────────────────────────────────────
    if (raw.contains('invalid login credentials') ||
        raw.contains('invalid_credentials')) {
      return 'Invalid email or password. Please try again.';
    }
    if (raw.contains('email not confirmed')) {
      return 'Please verify your email before signing in.';
    }
    if (raw.contains('user already registered') ||
        raw.contains('already been registered')) {
      return 'An account with this email already exists.';
    }
    if (raw.contains('jwt expired') || raw.contains('token is expired')) {
      return 'Your session has expired. Please sign in again.';
    }
    if (raw.contains('not authorized') || raw.contains('permission denied')) {
      return 'You don\'t have permission to do that.';
    }
    if (raw.contains('refresh_token_not_found')) {
      return 'Your session has expired. Please sign in again.';
    }

    // ── Supabase / PostgreSQL ────────────────────────────────────────────
    if (raw.contains('row-level security') || raw.contains('rls')) {
      return 'You don\'t have permission to perform this action.';
    }
    if (raw.contains('duplicate key') || raw.contains('unique constraint')) {
      return 'This item already exists.';
    }
    if (raw.contains('foreign key') || raw.contains('violates foreign key')) {
      return 'This action can\'t be completed because it references other data.';
    }
    if (raw.contains('null value in column') ||
        raw.contains('not-null constraint')) {
      return 'Some required information is missing. Please fill in all fields.';
    }
    if (raw.contains('too many requests') || raw.contains('rate limit')) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    if (raw.contains('storage') && raw.contains('object not found')) {
      return 'The file could not be found.';
    }
    if (raw.contains('payload too large') || raw.contains('too large')) {
      return 'The file is too large. Please use a smaller file.';
    }

    // ── Platform / Device ────────────────────────────────────────────────
    if (raw.contains('photo_access_denied') ||
        raw.contains('permission') && raw.contains('denied')) {
      return 'Please allow access in your device settings to continue.';
    }
    if (raw.contains('camera')) {
      return 'Unable to access the camera. Please check your permissions.';
    }

    // ── Flutter / Misc ───────────────────────────────────────────────────
    if (raw.contains('formatexception') || raw.contains('format exception')) {
      return 'Something went wrong processing the data. Please try again.';
    }

    // ── Fallback ─────────────────────────────────────────────────────────
    return fallback ?? 'Something went wrong. Please try again.';
  }
}
