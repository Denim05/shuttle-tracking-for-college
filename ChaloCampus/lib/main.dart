import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/socket_service.dart';
import 'services/bus_store.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/user_dashboard.dart';
import 'screens/admin_dashboard.dart';
import 'screens/manager_dashboard.dart';
import 'screens/driver_dashboard.dart';


// ─── Global Navigator Key (for SnackBars from outside Widget tree) ───────────

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor           : Colors.transparent,
    statusBarIconBrightness  : Brightness.light,
    statusBarBrightness      : Brightness.dark,
    systemNavigationBarColor : AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await NotificationService().init();

  runApp(const ChaloCampusApp());
}

// ─── Root Widget ─────────────────────────────────────────────────────────────

class ChaloCampusApp extends StatelessWidget {
  const ChaloCampusApp({super.key});

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
        title              : 'ChaloCampus',
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
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width : 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft,
                  end  : Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppShadows.primary,
              ),
              child: const Icon(
                Icons.directions_bus_rounded,
                color: Colors.white,
                size : 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'ChaloCampus',
              style: AppTextStyles.headlineMedium.copyWith(
                color    : AppColors.text,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width : 24,
              height: 24,
              child : CircularProgressIndicator(
                strokeWidth: 2,
                color      : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

