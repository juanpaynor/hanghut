import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bitemates/providers/auth_provider.dart';
import 'package:bitemates/features/auth/screens/welcome_screen.dart';
import 'package:bitemates/features/profile/screens/profile_setup_screen.dart';
import 'package:bitemates/features/home/screens/main_navigation_screen.dart';
import 'package:bitemates/features/splash/screens/social_magnet_splash_screen.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/providers/theme_provider.dart';
import 'package:bitemates/core/services/account_status_service.dart';
import 'package:bitemates/features/auth/screens/account_suspended_screen.dart';
import 'package:bitemates/features/ticketing/screens/my_tickets_screen.dart';
import 'package:bitemates/core/services/analytics_service.dart';

// GEOFENCING DISABLED for Android review — uncomment to re-enable
// import 'package:workmanager/workmanager.dart';
// import 'package:bitemates/features/location/logic/geofence_engine.dart';
// import 'package:bitemates/core/services/location_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:bitemates/core/services/push_notification_service.dart';
import 'package:bitemates/core/services/notification_service.dart';
import 'package:bitemates/core/services/app_location_service.dart';
import 'package:bitemates/core/services/deep_link_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// GEOFENCING DISABLED for Android review — uncomment to re-enable
// @pragma('vm:entry-point')
// void callbackDispatcher() {
//   Workmanager().executeTask((task, inputData) async {
//     print("📍 BACKGROUND TASK: \$task started");
//     try {
//       WidgetsFlutterBinding.ensureInitialized();
//       try { await dotenv.load(); } catch (_) {}
//       await SupabaseConfig.initialize();
//       final engine = GeofenceEngine();
//       await engine.init();
//       final locationService = LocationService();
//       final pos = await locationService.getCurrentLocation();
//       if (pos != null) {
//         engine.checkProximity(pos.latitude, pos.longitude);
//         await engine.syncGeofences();
//       }
//     } catch (e) {
//       print("❌ BACKGROUND TASK ERROR: \$e");
//     }
//     return Future.value(true);
//   });
// }

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Keep this handler as light as possible — no Firebase.initializeApp()
  // unless you actually need to use Firebase services (Firestore, etc.) here.
  // Heavy initialization in the background isolate competes with the main
  // app's memory and can cause Android to OOM-kill the process.
  print("Handling a background message: ${message.messageId}");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure the app renders behind system bars and accounts for their insets.
  // On Android 15+ edge-to-edge is enforced; this makes the nav bar
  // transparent so Flutter's MediaQuery.padding reports the correct bottom
  // inset and SafeArea / BottomNavigationBar work out of the box.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  // GEOFENCING DISABLED for Android review — uncomment to re-enable
  // Workmanager().initialize(
  //   callbackDispatcher,
  //   isInDebugMode: false,
  // );
  // Workmanager().registerPeriodicTask(
  //   "geofence-check",
  //   "geofenceTask",
  //   frequency: const Duration(minutes: 15),
  //   existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
  //   constraints: Constraints(
  //     networkType: NetworkType.connected,
  //     requiresBatteryNotLow: false,
  //   ),
  // );

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
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize local notifications FIRST (required for foreground FCM)
    await NotificationService().initialize();
    await NotificationService().requestPermissions();

    await PushNotificationService().init();
  } catch (e) {
    print("❌ FIREBASE INIT ERROR: $e");
  }

  // Initialize Foreground Geofence Engine + location (deferred to after first frame)
  // This reduces startup jank — these are not needed before the UI renders
  runApp(const MyApp());

  // Defer non-critical work to after the first frame renders
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // GEOFENCING DISABLED for Android review — uncomment to re-enable
    // await GeofenceEngine().init();
    // GeofenceEngine().syncGeofences();

    // Universal Links / App Links. Init after first frame so navigatorKey is
    // mounted before any cold-start link tries to navigate.
    DeepLinkService.instance.init();

    AppLocationService().updateLocationIfNeeded().catchError((e) {
      print("⚠️ Location update failed (non-critical): $e");
    });
  });
}

// Global Navigator Key for Deep Linking
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
            navigatorKey: navigatorKey, // Add Global Key
            navigatorObservers: [AnalyticsService().observer],
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
  Session? _session;
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    // Seed from the persisted/recovered session. supabase_flutter restores and
    // (if needed) refreshes the session during init, so currentSession is the
    // reliable source of truth — NOT the first onAuthStateChange emission,
    // which can be null during a slow/failed refresh at cold start.
    _session = SupabaseConfig.client.auth.currentSession;
    _sub = SupabaseConfig.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      // Only an EXPLICIT sign-out logs the user out. Transient events
      // (tokenRefreshFailed, network hiccups) must never boot a user who still
      // has a valid persisted session — that was the "logged out on exit" bug.
      if (data.event == AuthChangeEvent.signedOut) {
        setState(() => _session = null);
      } else {
        final s = data.session ?? SupabaseConfig.client.auth.currentSession;
        if (s != null) setState(() => _session = s);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_session != null) {
      return SessionHandler(session: _session!);
    }
    return const WelcomeScreen();
  }
}

class SessionHandler extends StatefulWidget {
  final Session session;

  const SessionHandler({super.key, required this.session});

  @override
  State<SessionHandler> createState() => _SessionHandlerState();
}

class _SessionHandlerState extends State<SessionHandler> {
  late Future<Map<String, dynamic>> _statusFuture;
  late Future<bool> _profileFuture;

  @override
  void initState() {
    super.initState();
    // Set analytics user ID on login
    AnalyticsService().setUserId(widget.session.user.id);
    _statusFuture = AccountStatusService.checkStatus();
    _profileFuture = _checkProfileExists(widget.session.user.id);
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
      // Fail SAFE: a transient/network error must not kick an existing,
      // logged-in user into onboarding (that reads as "logged out"). Assume the
      // profile exists and let them in; a genuinely missing profile returns a
      // clean null above (→ false), not an exception.
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _statusFuture,
      builder: (context, statusSnapshot) {
        if (statusSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final statusData = statusSnapshot.data;
        final status = statusData?['status'] ?? 'active';

        if (status == 'suspended' ||
            status == 'banned' ||
            status == 'deleted') {
          return AccountSuspendedScreen(
            status: status,
            reason: statusData?['reason'],
          );
        }

        return FutureBuilder(
          future: _profileFuture,
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: Colors.black),
                ),
              );
            }

            // Only route to setup when the profile is DEFINITIVELY absent.
            // Errors/nulls fall through to the app (fail-safe) so a launch-time
            // hiccup never looks like a logout.
            if (profileSnapshot.data == false) {
              print('⚠️ AUTH_GATE: No profile found, redirecting to setup');
              return const ProfileSetupScreen();
            }

            return const MainNavigationScreen();
          },
        );
      },
    );
  }
}
