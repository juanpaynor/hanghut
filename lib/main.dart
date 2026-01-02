import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/providers/auth_provider.dart';
import 'package:bitemates/features/auth/screens/login_screen.dart';
import 'package:bitemates/features/profile/screens/profile_setup_screen.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';
import 'package:bitemates/core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load();

  // Initialize Supabase
  await SupabaseConfig.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      child: MaterialApp(
        title: 'HangHut',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: SupabaseConfig.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Colors.black)),
          );
        }

        final session = snapshot.hasData ? snapshot.data!.session : null;

        if (session != null) {
          // Check if profile exists before showing main screen
          return FutureBuilder(
            future: _checkProfileExists(session.user.id),
            builder: (context, profileSnapshot) {
              if (profileSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  ),
                );
              }

              if (profileSnapshot.hasError || profileSnapshot.data != true) {
                // Profile doesn't exist - redirect to profile setup
                print('⚠️ AUTH_GATE: No profile found, redirecting to setup');
                return const ProfileSetupScreen();
              }

              return const MainNavigationScreen();
            },
          );
        } else {
          return const LoginScreen();
        }
      },
    );
  }

  Future<bool> _checkProfileExists(String userId) async {
    try {
      final response = await SupabaseConfig.client
          .from('users')
          .select('id, display_name, user_photos(photo_url, is_primary)')
          .eq('id', userId)
          .maybeSingle();

      if (response != null) {
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error checking profile: $e');
      return false;
    }
  }
}
