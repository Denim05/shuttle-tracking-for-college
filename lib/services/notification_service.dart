import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const int liveTrackingNotificationId = 99991;
  static const int proximityAlertNotificationId = 99992;

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

    // Create the high-priority alert channel for Android
    const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
      'SISTecChalo_pulse_alerts',
      'Pulse Alerts',
      description: 'Geofencing and proximity alerts for SISTecChalo',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    // Create ongoing live tracking channel for Android lock screen & status bar
    const AndroidNotificationChannel liveTrackingChannel = AndroidNotificationChannel(
      'SISTecChalo_live_tracking',
      'Live Shuttle Tracking',
      description: 'Ongoing lockscreen status for live college bus tracking',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );

    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(alertChannel);
    await androidPlugin?.createNotificationChannel(liveTrackingChannel);

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

    final AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'SISTecChalo_pulse_alerts',
      'Pulse Alerts',
      channelDescription: 'Geofencing and proximity alerts for SISTecChalo',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      color: const Color(0xFF00F0FF),
      styleInformation: BigTextStyleInformation(body),
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
    );
  }

  /// Shows or updates an ongoing live tracking notification on Android lock screen & status bar
  Future<void> updateLiveTrackingNotification({
    required String busNumber,
    required String targetStop,
    required int etaMinutes,
    required String distanceStr,
    required double speedKmh,
    int? currentStopIndex,
    int? totalStops,
    int? walkingMinutes,
    String? leavePrompt,
  }) async {
    if (kIsWeb) return;

    final String etaStr = etaMinutes <= 1 ? 'ARRIVING NOW' : '~$etaMinutes min';
    final String speedStr = speedKmh > 1 ? '${speedKmh.toStringAsFixed(0)} km/h' : 'Stationary';
    final String title = 'Bus $busNumber • $etaStr to $targetStop';

    String body = 'Distance: $distanceStr • Speed: $speedStr';
    if (leavePrompt != null && leavePrompt.isNotEmpty) {
      body = '$leavePrompt • $body';
    } else if (walkingMinutes != null && walkingMinutes > 0) {
      body = 'Walk: ~$walkingMinutes min • $body';
    }

    final bool hasProgress = currentStopIndex != null && totalStops != null && totalStops > 0;

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'SISTecChalo_live_tracking',
      'Live Shuttle Tracking',
      channelDescription: 'Ongoing lockscreen status for live college bus tracking',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      showWhen: true,
      showProgress: hasProgress,
      maxProgress: totalStops ?? 1,
      progress: currentStopIndex ?? 0,
      color: const Color(0xFF00E5FF),
      category: AndroidNotificationCategory.transport,
      subText: 'Live Transit Telemetry',
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'SISTecChalo Fleet',
      ),
    );

    await flutterLocalNotificationsPlugin.show(
      liveTrackingNotificationId,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  /// Cancels the ongoing live tracking notification
  Future<void> cancelLiveTrackingNotification() async {
    if (kIsWeb) return;
    await flutterLocalNotificationsPlugin.cancel(liveTrackingNotificationId);
  }

  /// High-priority proximity arrival alert when bus is within 500m / 2 min of user stop
  Future<void> showProximityArrivalAlert({
    required String busNumber,
    required String stopName,
    required int etaMinutes,
    required String distanceStr,
  }) async {
    if (kIsWeb) return;

    final String title = 'Bus $busNumber Approaching Your Stop';
    final String body = 'Your bus is $distanceStr away (~$etaMinutes min) from $stopName. Please head to your pickup point now!';

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'SISTecChalo_pulse_alerts',
      'Pulse Alerts',
      channelDescription: 'Geofencing and proximity alerts for SISTecChalo',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Bus Approaching Stop',
      color: const Color(0xFF10B981),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'Proximity Geofence Alert',
      ),
    );

    await flutterLocalNotificationsPlugin.show(
      proximityAlertNotificationId,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }
}


