import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConstants {
  // --- CONFIGURATION ---
  // Set to true to connect directly to the 24/7 Render Cloud Server
  static const bool isProduction = true; // ← Connected to Render Cloud Server

  // Dynamic local machine URL for Android emulator (10.0.2.2) and local desktop (127.0.0.1)
  static String get _localUrl {
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:5000';
    }
    return 'http://127.0.0.1:5000';
  }

  // Production Cloud Server URL (Render)
  static const String _productionUrl = 'https://smart-shuttle-backend-2h13.onrender.com';

  static String get baseUrl => isProduction ? _productionUrl : _localUrl;
  static String get apiUrl => '$baseUrl/api';

  static String get socketUrl => baseUrl;

  static const String modelApiKey = 'al-rqfpNNmS9Ny2xW4gjZURmYgnUDZJET089BXf3dga8wk';

  // --- APP VERSION & PLAY STORE ---
  static const String currentAppVersion = '1.0.4';
  static const int currentBuildNumber = 18;
  static const String playStoreUrl = 'https://play.google.com/store/apps/details?id=com.smartcampus.shuttle';

  // Helper to confirm connection type
  static String get currentConfigInfo => isProduction
      ? 'Connected to Production Server'
      : 'Connected to Local Server: $_localUrl';
}
