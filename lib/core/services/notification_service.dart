import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // Skip initialization on Windows if it causes issues, or use proper settings
    if (Platform.isWindows) {
      // flutter_local_notifications support for Windows is limited or requires extra setup
      // For now, we avoid crashing the app
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();

    final linuxSettings = const LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      linux: linuxSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        // Handle tap
      },
    );

    if (Platform.isAndroid) {
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> showProgress(
    int id,
    String title,
    String body,
    int progress,
    int max,
  ) async {
    if (!Platform.isAndroid) return; // Progress notifications are Android-only for now

    final androidDetails = AndroidNotificationDetails(
      'downloads_channel',
      'Downloads',
      channelDescription: 'Download progress notifications',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: max,
      progress: progress,
    );

    final details = NotificationDetails(android: androidDetails);

    await _notifications.show(id, title, body, details);
  }

  Future<void> showCompletion(int id, String title, String body) async {
    NotificationDetails? details;

    if (Platform.isAndroid) {
      const androidDetails = AndroidNotificationDetails(
        'downloads_channel',
        'Downloads',
        channelDescription: 'Download progress notifications',
        importance: Importance.high,
        priority: Priority.high,
      );
      details = const NotificationDetails(android: androidDetails);
    } else if (Platform.isLinux) {
      const linuxDetails = LinuxNotificationDetails();
      details = const NotificationDetails(linux: linuxDetails);
    } else if (Platform.isIOS || Platform.isMacOS) {
      const darwinDetails = DarwinNotificationDetails();
      details = const NotificationDetails(iOS: darwinDetails, macOS: darwinDetails);
    }

    // Windows support is skipped for now to avoid crashes if plugin not configured
    if (details == null) return;

    await _notifications.show(id, title, body, details);
  }

  Future<void> cancel(int id) async {
    if (Platform.isWindows) return; // Not supported/initialized on Windows
    await _notifications.cancel(id);
  }
}
