class AppConstants {
  // --- CONFIGURATION ---
  // Set to true when deploying the app, false for local testing
  static const bool isProduction = true; // ← switch to false for local dev

  // Local Machine IP for testing with physical devices
  // Run `ipconfig` and use the WiFi IPv4 address
  static const String _localUrl = 'http://192.168.1.4:5000';

  // Production Cloud Server URL (Render)
  static const String _productionUrl = 'https://smart-shuttle-backend-2h13.onrender.com';

  static String get baseUrl => isProduction ? _productionUrl : _localUrl;
  static String get apiUrl => '$baseUrl/api';

  static String get socketUrl => baseUrl;

  static const String modelApiKey = 'al-rqfpNNmS9Ny2xW4gjZURmYgnUDZJET089BXf3dga8wk';

  // Helper to confirm connection type
  static String get currentConfigInfo => isProduction
      ? 'Connected to Production Server'
      : 'Connected to Local Server: $_localUrl';
}
