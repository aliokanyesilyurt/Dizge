import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/task.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> scheduleTaskNotification(Task task) async {
    if (!task.scheduled || task.startHour == null) return;

    // Yalnızca gelecekteki işler için bildirim planla
    final now = DateTime.now();
    int hour = task.startHour!.floor();
    int minute = ((task.startHour! - hour) * 60).round();
    if (minute == 60) {
      hour += 1;
      minute = 0;
    }

    final taskTime = DateTime(
      task.date.year,
      task.date.month,
      task.date.day,
      hour,
      minute,
    );

    if (taskTime.isBefore(now)) return;

    final id = task.id.hashCode;

    await _plugin.zonedSchedule(
      id,
      'Hatırlatıcı: ${task.title}',
      'Zamanı geldi!',
      tz.TZDateTime.from(taskTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'dizge_tasks',
          'Görev Bildirimleri',
          channelDescription: 'Planlanan görevler için hatırlatıcılar',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelTaskNotification(Task task) async {
    await _plugin.cancel(task.id.hashCode);
  }
}
