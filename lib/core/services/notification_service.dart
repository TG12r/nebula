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

    await _notifications.show(id, title, body, details);
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

    await _notifications.show(id, title, body, details);
  }

  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }
}
