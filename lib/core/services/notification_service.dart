import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
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

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> showProgress(
    int id,
    String title,
    String body,
    int progress,
    int max,
  ) async {
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

    try {
      await _notifications.show(id, title, body, details);
    } catch (e) {
      // Ignore notification errors (especially on Windows where plugin might fail)
      // debugPrint("Notification error: $e");
    }
  }

  Future<void> showCompletion(int id, String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'downloads_channel',
      'Downloads',
      channelDescription: 'Download progress notifications',
      importance: Importance.high,
      priority: Priority.high,
      // No progress bar
    );

    final details = const NotificationDetails(android: androidDetails);

    try {
      await _notifications.show(id, title, body, details);
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> showError(int id, String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'downloads_error_channel',
      'Download Errors',
      channelDescription: 'Notifications for failed downloads',
      importance: Importance.high,
      priority: Priority.high,
    );

    final details = const NotificationDetails(android: androidDetails);

    try {
      await _notifications.show(id, title, body, details);
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> cancel(int id) async {
    try {
      await _notifications.cancel(id);
    } catch (e) {
      // Ignore errors
    }
  }
}
