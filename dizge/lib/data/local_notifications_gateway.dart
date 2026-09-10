import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../core/reminders.dart';

/// [ReminderGateway]'in `flutter_local_notifications` uygulaması.
///
/// Yalnız çeviri yapıyor: plan [planReminders]'ta, ne zaman yeniden
/// kurulacağı [ReminderScheduler]'da.
class LocalNotificationsGateway implements ReminderGateway {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'dizge_reminders',
      'Hatırlatmalar',
      channelDescription: 'Saati gelen işler için hatırlatmalar',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> init() async {
    if (_ready || kIsWeb) return;
    await _initTimeZone();

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        linux: LinuxInitializationSettings(defaultActionName: 'Aç'),
        // Kimlik ve GUID sabit kalmalı: Windows bildirim ayarlarındaki
        // "Dizge" satırı bunlara bağlı; değişirse kullanıcının kapattığı
        // bildirimler sessizce yeniden açılır (ya da tersi).
        windows: WindowsInitializationSettings(
          appName: 'Dizge',
          appUserModelId: 'Dizge.Takvim',
          guid: '5a356f07-9e17-4b2a-91d1-0ffc4c9f97d7',
        ),
      ),
    );
    _ready = true;
  }

  /// Yerel saat dilimi. Tek seferlik bir an için şart değil (an, dilimden
  /// bağımsız), ama eklenti tarihi o dilimin takvimiyle yorumluyor; UTC'de
  /// bırakmak her gün aynı saatte düşen işlerde yanlış güne taşardı.
  static Future<void> _initTimeZone() async {
    tz.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Tanınmayan ad (Windows bazen kendi adını verir): ofsetten bir
      // `Etc/GMT±N` bölgesi. İşaret ters — POSIX geleneği.
      final offset = DateTime.now().timeZoneOffset;
      if (offset.inMinutes % 60 == 0) {
        final h = -offset.inHours;
        final name = h == 0 ? 'Etc/UTC' : 'Etc/GMT${h > 0 ? '+' : ''}$h';
        try {
          tz.setLocalLocation(tz.getLocation(name));
        } catch (_) {}
      }
    }
  }

  @override
  Future<ReminderPermission> permission() async {
    if (!_ready) return ReminderPermission.unknown;
    if (!kIsWeb && Platform.isAndroid) {
      final enabled = await _android?.areNotificationsEnabled();
      return enabled == null
          ? ReminderPermission.unknown
          : enabled
          ? ReminderPermission.granted
          : ReminderPermission.denied;
    }
    return ReminderPermission.unknown;
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    if (!_ready) await init();
    if (!kIsWeb && Platform.isAndroid) {
      await _android?.requestNotificationsPermission();
    }
    return permission();
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    if (!_ready) return;
    // Windows'ta "bekleyenleri sil" yok; `cancelAll` zamanlanmışları da
    // kaldırıyor (bedeli: işlem merkezinde duran eski bildirimler de gider).
    if (!kIsWeb && Platform.isWindows) {
      await _plugin.cancelAll();
    } else {
      await _plugin.cancelAllPendingNotifications();
    }

    // Tam saatli alarm izni yoksa (Android 12+, izin geri alınmış) "yaklaşık"
    // moda düşülüyor: birkaç dakika gecikmeli bir hatırlatma, hiç
    // kurulamayan bir hatırlatmadan iyidir.
    var mode = AndroidScheduleMode.exactAllowWhileIdle;
    if (!kIsWeb && Platform.isAndroid) {
      final exact = await _android?.canScheduleExactNotifications() ?? true;
      if (!exact) mode = AndroidScheduleMode.inexactAllowWhileIdle;
    }

    for (final r in reminders) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime.from(r.at, tz.local),
        notificationDetails: _details,
        androidScheduleMode: mode,
      );
    }
  }

  @override
  Future<void> showNow({required String title, required String body}) async {
    if (!_ready) await init();
    await _plugin.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: _details,
    );
  }

  @override
  Future<void> openSystemSettings() async {
    if (kIsWeb) return;
    if (Platform.isWindows) {
      await launchUrl(Uri.parse('ms-settings:notifications'));
      return;
    }
    try {
      await _plugin.openAppNotificationSettings();
    } catch (_) {
      // Platform desteklemiyorsa sessiz: düğme zaten yalnız işe yaradığı
      // yerde gösteriliyor.
    }
  }
}
