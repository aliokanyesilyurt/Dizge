import 'package:dizge/core/app_config.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/models/task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Task _task({double? windowStart, double? windowEnd}) => Task(
  title: 'Rapor',
  color: const Color(0xFF5AA9FF),
  date: DateTime(2026, 8, 16),
  durationHours: 1.5,
  windowStart: windowStart,
  windowEnd: windowEnd,
);

void main() {
  group('Z2 — pencere yazılıp okunuyor', () {
    test('pencereli iş turu kayıpsız', () {
      final json = _task(windowStart: 9, windowEnd: 12).toJson();
      final back = Task.fromJson(json);

      expect(back.windowStart, 9);
      expect(back.windowEnd, 12);
      // Pencere süre değil: 09:00–12:00 arasında olan iş yine 1,5 saat.
      expect(back.durationHours, 1.5);
    });

    test('penceresiz iş penceresiz kalıyor', () {
      final back = Task.fromJson(_task().toJson());
      expect(back.windowStart, isNull);
      expect(back.windowEnd, isNull);
    });

    test('kopya ve gün kopyası pencereyi taşıyor', () {
      final t = _task(windowStart: 9, windowEnd: 12);

      expect(t.copy().windowStart, 9);
      expect(t.copy().windowEnd, 12);

      // duplicateTo: pencere de isFixed gibi işin kendi doğası. Kopyada
      // kaybolsaydı kopya sessizce sınırsız doğardı.
      final tomorrow = t.duplicateTo(DateTime(2026, 8, 17));
      expect(tomorrow.windowStart, 9);
      expect(tomorrow.windowEnd, 12);
    });
  });

  group('Z2 — geçersiz pencere hiç yok sayılıyor', () {
    test('ters çift (start >= end) düşüyor', () {
      // Ters pencere, Günü Kurtar'a hiçbir saatin sığmadığı bir kısıt
      // vermek olurdu: iş her seferinde sessizce havuza inerdi.
      final back = Task.fromJson({
        ..._task().toJson(),
        'windowStart': 15.0,
        'windowEnd': 9.0,
      });
      expect(back.windowStart, isNull);
      expect(back.windowEnd, isNull);
    });

    test('sıfır genişlikli pencere düşüyor', () {
      final back = Task.fromJson({
        ..._task().toJson(),
        'windowStart': 9.0,
        'windowEnd': 9.0,
      });
      expect(back.windowStart, isNull);
    });

    test('yarım çift düşüyor', () {
      // Yarısını kabul etmek ekranda ucu açık bir aralık göstermek olurdu.
      final onlyStart = Task.fromJson({
        ..._task().toJson(),
        'windowStart': 9.0,
        'windowEnd': null,
      });
      expect(onlyStart.windowStart, isNull);

      final onlyEnd = Task.fromJson({
        ..._task().toJson(),
        'windowStart': null,
        'windowEnd': 12.0,
      });
      expect(onlyEnd.windowEnd, isNull);
    });
  });

  group('Z2 — şema', () {
    test('sürüm 5', () {
      expect(AppConfig.kSchemaVersion, 5);
    });

    test('v3 anlık görüntüsü kayıpsız açılıyor', () {
      // v3 → v4 için göç adımı bilerek yok: pencere anahtarı bulunmayan eski
      // kayıt "pencere yok" diye okunuyor, ki doğru cevap zaten bu.
      final old = {
        'schemaVersion': 3,
        'categories': const [],
        'tasks': [
          {
            'id': 'a1',
            'title': 'Eski iş',
            'startHour': 14.0,
            'durationHours': 1.0,
            'date': '2026-08-03',
          },
        ],
      };

      final migrated = migrateSnapshot(Map<String, dynamic>.from(old));

      expect(migrated['schemaVersion'], 5);
      expect((migrated['tasks'] as List).length, 1);

      final task = Task.fromJson(
        ((migrated['tasks'] as List).first as Map).cast<String, dynamic>(),
      );
      expect(task.title, 'Eski iş');
      expect(task.startHour, 14.0);
      expect(task.windowStart, isNull);
    });
  });
}
