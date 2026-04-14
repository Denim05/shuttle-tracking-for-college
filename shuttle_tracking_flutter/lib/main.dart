import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/socket_service.dart';
import 'screens/login_screen.dart';
import 'screens/user_dashboard.dart';
import 'screens/admin_dashboard.dart';
import 'screens/manager_dashboard.dart';
import 'screens/driver_dashboard.dart';
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  runApp(const MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) {
          final service = SocketService();
          service.initSocket(); // Initialize immediately
          return service;
        }),
      ],
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent, // Transparent status bar
          statusBarIconBrightness: Brightness.light, // Light icons for dark background
          statusBarBrightness: Brightness.dark, // iOS dark background
        ),
        child: MaterialApp(
          title: 'Sistec Chalo',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          home: const AuthWrapper(),
        ),
      ),
    );
  }
}
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Provider.of<AuthService>(context, listen: false).tryAutoLogin(),
      builder: (context, snapshot) {
        // While checking for a token, show a loading screen
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        return Consumer<AuthService>(
          builder: (context, auth, child) {
            // After checking, if the user is not authenticated, show the login screen
            if (!auth.isAuthenticated) {
              return const LoginScreen();
            }
            // Otherwise, show the correct dashboard based on the user's role
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
