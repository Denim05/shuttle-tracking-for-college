import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // flutter_local_notifications does not support web — skip init on web.
    if (kIsWeb) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
      },
    );

    // Create the high-priority channel for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'SISTecChalo_pulse_alerts',
      'Pulse Alerts',
      description: 'Geofencing and proximity alerts for SISTecChalo',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Set up foreground message handler for FCM
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📩 Foreground FCM message: ${message.notification?.title}');
      if (message.notification != null) {
        showNotification(
          id: message.hashCode,
          title: message.notification!.title ?? 'SISTecChalo Alert',
          body: message.notification!.body ?? '',
        );
      }
    });
  }

  /// Request permissions and retrieve FCM token
  Future<String?> getDeviceToken() async {
    if (kIsWeb) return null;
    try {
      final NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        final String? token = await FirebaseMessaging.instance.getToken();
        debugPrint('🔑 FCM Token retrieved: $token');
        return token;
      } else {
        debugPrint('⚠️ FCM Notification permission denied or not granted.');
      }
    } catch (e) {
      debugPrint('⚠️ Error retrieving FCM Token: $e');
    }
    return null;
  }

  Future<void> showNotification({
    int id = 0,
    required String title,
    required String body,
  }) async {
    // On web, notifications are handled by the browser natively.
    // This service is a no-op on web.
    if (kIsWeb) {
      debugPrint('[Web Notification] $title: $body');
      return;
    }

    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'SISTecChalo_pulse_alerts',
      'Pulse Alerts',
      channelDescription: 'Geofencing and proximity alerts for SISTecChalo',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      color: Color(0xFF00F0FF),
      styleInformation: BigTextStyleInformation(''),
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
    );
  }
}


