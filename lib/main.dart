import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/providers/auth_provider.dart';
import 'package:bitemates/features/auth/screens/login_screen.dart';
import 'package:bitemates/features/profile/screens/profile_setup_screen.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';
import 'package:bitemates/features/splash/screens/social_magnet_splash_screen.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/providers/theme_provider.dart';
import 'package:bitemates/core/services/account_status_service.dart';
import 'package:bitemates/features/auth/screens/account_suspended_screen.dart';
import 'package:bitemates/features/ticketing/screens/my_tickets_screen.dart';

import 'package:workmanager/workmanager.dart';
import 'package:bitemates/features/location/logic/geofence_engine.dart';
import 'package:bitemates/core/services/location_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:bitemates/core/services/push_notification_service.dart';
import 'package:bitemates/core/services/app_location_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("📍 BACKGROUND TASK: $task started");

    try {
      // 1. Initialize Engine (Loads cache)
      final engine = GeofenceEngine();
      await engine.init();

      // 2. Get Location (One-shot)
      final locationService = LocationService();
      final pos = await locationService.getCurrentLocation();

      if (pos != null) {
        print(
          "📍 BACKGROUND TASK: Got location ${pos.latitude}, ${pos.longitude}",
        );
        // 3. Run Check
        engine.checkProximity(pos.latitude, pos.longitude);
      } else {
        print("⚠️ BACKGROUND TASK: Could not get location");
      }
    } catch (e) {
      print("❌ BACKGROUND TASK ERROR: $e");
    }

    return Future.value(true);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Workmanager
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true, // TODO: Set to false in production
  );

  // Register Periodic Task (15 min interval)
  Workmanager().registerPeriodicTask(
    "geofence-check",
    "geofenceTask",
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected, // Optional, but good for sync
    ),
  );

  // Load environment variables (optional for release builds)
  try {
    await dotenv.load();
    print('✅ .env file loaded successfully');
  } catch (e) {
    print('⚠️ .env file not found (using fallback config)');
    // This is expected for release builds where .env is gitignored
  }

  // Initialize Supabase
  await SupabaseConfig.initialize();

  // Initialize Firebase & Push Notifications
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await PushNotificationService().init();
  } catch (e) {
    print("❌ FIREBASE INIT ERROR: $e");
  }

  // Initialize Foreground Geofence Engine
  await GeofenceEngine().init();
  // Attempt sync (if network available)
  GeofenceEngine().syncGeofences(); // Fire and forget

  // Update user location once per 24h (non-blocking)
  AppLocationService().updateLocationIfNeeded().catchError((e) {
    print("⚠️ Location update failed (non-critical): $e");
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'HangHut',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const SocialMagnetSplashScreen(),
            routes: {
              '/my-tickets': (context) => const MyTicketsScreen(),
              '/map': (context) => const MainNavigationScreen(),
            },
          );
        },
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
          // Check account status FIRST before anything else
          return FutureBuilder(
            future: AccountStatusService.checkStatus(),
            builder: (context, statusSnapshot) {
              if (statusSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final statusData = statusSnapshot.data as Map<String, dynamic>?;
              final status = statusData?['status'] ?? 'active';

              // If suspended, banned, or deleted, show account suspended screen
              if (status == 'suspended' ||
                  status == 'banned' ||
                  status == 'deleted') {
                return AccountSuspendedScreen(
                  status: status,
                  reason: statusData?['reason'],
                );
              }

              // If active, check if profile exists before showing main screen
              return FutureBuilder(
                future: _checkProfileExists(session.user.id),
                builder: (context, profileSnapshot) {
                  if (profileSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(
                        child: CircularProgressIndicator(color: Colors.black),
                      ),
                    );
                  }

                  if (profileSnapshot.hasError ||
                      profileSnapshot.data != true) {
                    // Profile doesn't exist - redirect to profile setup
                    print(
                      '⚠️ AUTH_GATE: No profile found, redirecting to setup',
                    );
                    return const ProfileSetupScreen();
                  }

                  return const MainNavigationScreen();
                },
              );
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
