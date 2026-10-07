import 'package:flutter/foundation.dart' show kIsWeb, PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/auth_service.dart';
import 'services/socket_service.dart';
import 'services/bus_store.dart';
import 'services/notification_service.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/user_dashboard.dart';
import 'screens/admin_dashboard.dart';
import 'screens/manager_dashboard.dart';
import 'screens/driver_dashboard.dart';
import 'screens/force_password_change_screen.dart';
import 'screens/commute_setup_screen.dart';
import 'screens/guest_dashboard.dart';


// ─── Global Navigator Key (for SnackBars from outside Widget tree) ───────────

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ─── Background FCM Handler ──────────────────────────────────────────────────

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('⚠️ Error initializing Firebase in background: $e');
  }
  debugPrint('📩 Background message received: ${message.notification?.title}');
}

// ─── Entry Point ─────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ⚡ Non-blocking eager Render cloud server pre-warm
  ApiService.warmUpBackend();
  // No dart:io override needed — Render uses valid HTTPS certificates.

  // Lock portrait orientation (only on mobile, not web)
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    
    // Initialize Firebase
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Automated Production Failure Crashlytics Error Capture
      FlutterError.onError = (errorDetails) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      // Log app launch event
      FirebaseAnalytics.instance.logAppOpen();
    } catch (e) {
      debugPrint('⚠️ Error initializing Firebase/Crashlytics: $e');
    }
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor           : Colors.transparent,
    statusBarIconBrightness  : Brightness.light,
    statusBarBrightness      : Brightness.dark,
    systemNavigationBarColor : AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('⚠️ Error initializing NotificationService: $e');
  }

  runApp(const SISTecChaloApp());
}

// ─── Root Widget ─────────────────────────────────────────────────────────────

class SISTecChaloApp extends StatelessWidget {
  const SISTecChaloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // AuthService — drives authentication state (login / logout / role)
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService(),
        ),

        // SocketService — real-time socket with ChangeNotifier
        //   Must be ChangeNotifierProvider so widgets can react via Consumer
        ChangeNotifierProvider<SocketService>(
          create: (_) {
            final svc = SocketService();
            svc.initSocket();
            return svc;
          },
        ),

        // BusStore — depends on SocketService, created after it
        ChangeNotifierProxyProvider<SocketService, BusStore>(
          create: (ctx) => BusStore(
            ctx.read<SocketService>(),
          ),
          update: (ctx, socketSvc, prev) =>
              prev ?? BusStore(socketSvc),
        ),
      ],
      child: MaterialApp(
        title              : 'SISTecChalo',
        debugShowCheckedModeBanner: false,
        navigatorKey       : navigatorKey,
        theme              : AppTheme.dark,
        scrollBehavior     : const _SmoothScrollBehavior(),
        home               : const AuthWrapper(),
      ),
    );
  }
}

// ─── Smooth Scroll Behavior ───────────────────────────────────────────────────

class _SmoothScrollBehavior extends ScrollBehavior {
  const _SmoothScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();
}

// ─── Auth Wrapper ─────────────────────────────────────────────────────────────

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late Future<void> _initAppFuture;
  bool _hasCompletedOnboarding = true;

  @override
  void initState() {
    super.initState();
    _initAppFuture = _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hasCompletedOnboarding = prefs.getBool('has_completed_onboarding') ?? false;
    } catch (_) {}

    if (!mounted) return;
    // Concurrently auto-login auth check and play the full starting screen animation
    await Future.wait([
      Provider.of<AuthService>(context, listen: false).tryAutoLogin(),
      Future.delayed(const Duration(milliseconds: 2300)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initAppFuture,
      builder: (context, snapshot) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          child: (snapshot.connectionState == ConnectionState.waiting)
              ? const _SplashScreen(key: ValueKey('splash_screen'))
              : Consumer<AuthService>(
                  key: const ValueKey('authenticated_content'),
                  builder: (context, auth, _) {
                    // Show 3-screen progressive onboarding on first launch
                    if (!_hasCompletedOnboarding && !auth.isAuthenticated) {
                      return OnboardingScreen(
                        onCompleted: () => setState(() => _hasCompletedOnboarding = true),
                      );
                    }

                    if (!auth.isAuthenticated) return const LoginScreen();

                    // Mandatory First-Time Password Reset Enforcement (Students with temporary passwords)
                    if (auth.currentUser?.role == 'user' && auth.currentUser?.mustChangePassword == true && !auth.isGuest) {
                      return const ForcePasswordChangeScreen();
                    }

                    // Mandatory Local Commute & Nearest Stop Setup (for student commuters)
                    if (auth.currentUser?.role == 'user' && !auth.isGuest && auth.currentUser?.isCommuteConfigured != true) {
                      return const CommuteSetupScreen(isInitialSetup: true);
                    }

                    switch (auth.currentUser?.role) {
                      case 'admin':
                        return const AdminDashboard();
                      case 'manager':
                        return const ManagerDashboard();
                      case 'driver':
                        return const DriverDashboard();
                      case 'guest':
                        return const GuestDashboard();
                      case 'user':
                      default:
                        return const UserDashboard();
                    }
                  },
                ),
        );
      },
    );
  }
}

// ─── Splash Screen (Branded Opening Animation) ───────────────────────────────

class _SplashScreen extends StatefulWidget {
  const _SplashScreen({super.key});

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/splash-animated.gif'), context);
    precacheImage(const AssetImage('assets/splash-1080x2400.png'), context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F11),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFF0F0F11),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              // High-resolution static starting screen background
              Image.asset(
                'assets/splash-1080x2400.png',
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),

              // Animated liquid reveal starting screen GIF
              Image.asset(
                'assets/splash-animated.gif',
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


