import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bitemates/core/config/supabase_config.dart';

class AuthService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  // Get auth client
  GoTrueClient get auth => _supabase.auth;

  // Check if user is authenticated
  bool get isAuthenticated => _supabase.auth.currentUser != null;

  // Get current user
  User? get currentUser => _supabase.auth.currentUser;

  // Get user ID
  String? get userId => _supabase.auth.currentUser?.id;

  // Sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: displayName != null ? {'display_name': displayName} : null,
        emailRedirectTo: null, // Disable email confirmation redirect
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      rethrow;
    }
  }

  // Sign in with Google (for future implementation)
  Future<bool> signInWithGoogle() async {
    // TODO: Implement Google OAuth flow
    throw UnimplementedError('Google sign-in not yet implemented');
  }

  // Sign in with Apple (for future implementation)
  Future<bool> signInWithApple() async {
    // TODO: Implement Apple OAuth flow
    throw UnimplementedError('Apple sign-in not yet implemented');
  }

  // Get auth state stream
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
}
