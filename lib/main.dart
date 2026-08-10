import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/auth_service.dart';
import 'services/socket_service.dart';
import 'services/bus_store.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'screens/login_screen.dart';
import 'screens/user_dashboard.dart';
import 'screens/admin_dashboard.dart';
import 'screens/manager_dashboard.dart';
import 'screens/driver_dashboard.dart';


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
    } catch (e) {
      debugPrint('⚠️ Error initializing Firebase: $e');
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

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Provider.of<AuthService>(context, listen: false).tryAutoLogin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }

        return Consumer<AuthService>(
          builder: (context, auth, _) {
            if (!auth.isAuthenticated) return const LoginScreen();
            switch (auth.currentUser?.role) {
              case 'admin':
                return const AdminDashboard();
              case 'manager':
                return const ManagerDashboard();
              case 'driver':
                return const DriverDashboard();
              case 'user':
              case 'guest':
              default:
                return const UserDashboard();
            }
          },
        );
      },
    );
  }
}

// ─── Splash Screen ─────────────────────────────────────────────────────────────

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Background ambient radial glow
          Positioned(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF2D5BFF).withOpacity(0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(duration: 2.seconds, begin: const Offset(0.8, 0.8), end: const Offset(1.2, 1.2)),
          ),
          
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Glowing Icon Badge
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2D5BFF), Color(0xFF00F0FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2D5BFF).withOpacity(0.5),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.directions_bus_filled_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1), curve: Curves.easeOutBack),
                
                const SizedBox(height: 28),
                
                Text(
                  'SISTecChalo',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ).animate().fadeIn(delay: 200.ms),
                
                const SizedBox(height: 6),
                
                Text(
                  'REAL-TIME BUS TELEMETRY',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF00F0FF),
                    letterSpacing: 3,
                  ),
                ).animate().fadeIn(delay: 400.ms),
                
                const SizedBox(height: 48),
                
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF00F0FF),
                  ),
                ).animate().fadeIn(delay: 600.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


