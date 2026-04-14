class AppConstants {
  // Production URL from Render
  static const String _cloudUrl = 'https://smart-shuttle-backend-2h13.onrender.com';

  // We use the cloud URL directly as Render handles standard HTTPS (443)
  static String get baseUrl => _cloudUrl;
  static String get apiUrl => '$baseUrl/api';
  
  // Socket.io works directly on the HTTPS cloud URL
  static String get socketUrl => _cloudUrl;
  
  static const String modelApiKey = 'al-rqfpNNmS9Ny2xW4gjZURmYgnUDZJET089BXf3dga8wk';
  
  // Helper to confirm connection type
  static String get currentConfigInfo => 'Connected to Production Cloud: $_cloudUrl';
}

