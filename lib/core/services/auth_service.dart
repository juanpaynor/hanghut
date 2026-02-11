import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  // Sign in with Google - using native SDK + Supabase signInWithIdToken
  Future<bool> signInWithGoogle() async {
    try {
      // Initialize Google Sign-In
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId:
            '558582827268-h51orqbvau38tb39ld303lcals5f2bqp.apps.googleusercontent.com',
        clientId:
            '558582827268-renm42f0ecl1tmfrhou1tuk2pergpghg.apps.googleusercontent.com',
      );

      // Trigger Google Sign-In flow
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        return false; // User canceled
      }

      // Get authentication details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        throw 'No ID Token found';
      }

      // Sign in to Supabase using the ID token
      final AuthResponse response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );

      return response.user != null;
    } catch (e) {
      print('Google Sign-In Error: $e');
      rethrow;
    }
  }

  // Sign in with Apple (for future implementation)
  Future<bool> signInWithApple() async {
    // TODO: Implement Apple OAuth flow
    throw UnimplementedError('Apple sign-in not yet implemented');
  }

  // Reset password via email (Web Flow)
  Future<void> resetPasswordForEmail(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'https://hanghut.com/auth/reset', // Points to Web App
      );
    } catch (e) {
      rethrow;
    }
  }

  // Get auth state stream
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
}
