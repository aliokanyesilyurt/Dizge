import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/time_grid.dart';
import 'package:scheduler_app/data/app_store.dart';
import 'package:scheduler_app/models/task.dart';

/// Izgaradaki sürükle-bırak ve süre değiştirmenin **anlamı**.
///
/// Widget testi jestin doğru gün/saati bildirdiğini kanıtlıyor; burada ise o
/// bilginin modele nasıl uygulandığı kilitleniyor. Rutinlerde bu ayrım kritik:
/// bir rutini sürüklemek "bu haftaki tekrarı taşı" mı, "kuralı değiştir" mi?
void main() {
  setUp(TaskRepository.all.clear);

  // 2026-07-20 Pazartesi.
  final monday = DateTime(2026, 7, 20);
  final tuesday = monday.add(const Duration(days: 1));
  final wednesday = monday.add(const Duration(days: 2));
  final thursday = monday.add(const Duration(days: 3));

  Task seed(
    AppStore store, {
    Repeat repeat = const Repeat.once(),
    double start = 9.0,
    double duration = 1.0,
    DateTime? date,
  }) {
    final task = Task(
      title: 'İş',
      color: const Color(0xFF4FC3F7),
      date: date ?? monday,
      startHour: start,
      durationHours: duration,
      repeat: repeat,
    );
    store.addTask(task);
    return task;
  }

  group('moveTask — tek günlük iş', () {
    test('gün ve saat doğrudan uygulanır', () {
      final store = AppStore();
      final task = seed(store);

      store.moveTask(task, toDay: wednesday, newStartHour: 14.5);

      expect(task.date, wednesday);
      expect(task.startHour, 14.5);
      expect(task.occursOn(wednesday), isTrue);
      expect(task.occursOn(monday), isFalse);
    });

    test('gün sonunu taşan bırakma başlangıcı geri çeker', () {
      final store = AppStore();
      final task = seed(store, start: 9.0, duration: 3.0);

      // 23:00'a bırakılan 3 saatlik iş 21:00'de başlar (süre korunur).
      store.moveTask(task, toDay: monday, newStartHour: 23.0);

      expect(task.startHour, 21.0);
      expect(task.durationHours, 3.0);
    });

    test('taşıma updatedAt damgasını tazeler', () {
      final store = AppStore();
      final task = seed(store);
      final before = task.updatedAt;

      store.moveTask(task, toDay: tuesday, newStartHour: 10.0);

      expect(task.updatedAt.isAfter(before) || task.updatedAt == before, isTrue);
      expect(TaskRepository.all.single.id, task.id,
          reason: 'taşıma kopya üretmemeli');
    });
  });

  group('moveTask — rutinler', () {
    test('günlük rutinde saat değişir, başlangıç günü sabit kalır', () {
      final store = AppStore();
      final task = seed(store, repeat: const Repeat(RepeatType.daily));

      store.moveTask(task, toDay: thursday, newStartHour: 7.0);

      expect(task.startHour, 7.0);
      expect(task.date, monday,
          reason: 'günlük rutin zaten her gün; gün taşıması anlamsız');
      expect(task.occursOn(thursday), isTrue);
      expect(task.occursOn(tuesday), isTrue);
    });

    test('haftalık rutinde sürüklenen gün hedefe taşınır, diğeri kalır', () {
      final store = AppStore();
      final task = seed(
        store,
        repeat: const Repeat(RepeatType.weekly, weekdays: {1, 3}), // Pzt, Çar
      );

      // Pazartesi tekrarını Salı'ya sürükle.
      store.moveTask(task, toDay: tuesday, newStartHour: 9.0);

      expect(task.repeat.weekdays, {2, 3}, reason: 'Pzt → Sal, Çar korunur');
      expect(task.occursOn(tuesday), isTrue);
      expect(task.occursOn(wednesday), isTrue);
      expect(task.occursOn(monday), isFalse);
    });

    test('haftalık rutinde hedefe en yakın tekrar taşınır', () {
      final store = AppStore();
      final task = seed(
        store,
        repeat: const Repeat(RepeatType.weekly, weekdays: {1, 3}), // Pzt, Çar
      );

      // Perşembe'ye bırak: Çarşamba (en yakın) taşınmalı, Pazartesi durmalı.
      store.moveTask(task, toDay: thursday, newStartHour: 9.0);

      expect(task.repeat.weekdays, {1, 4});
    });

    test('aynı güne bırakmak tekrar kümesini bozmaz', () {
      final store = AppStore();
      final task = seed(
        store,
        repeat: const Repeat(RepeatType.weekly, weekdays: {1, 3}),
      );

      store.moveTask(task, toDay: wednesday, newStartHour: 15.0);

      expect(task.repeat.weekdays, {1, 3});
      expect(task.startHour, 15.0);
    });
  });

  group('resizeTask', () {
    test('süreyi günceller', () {
      final store = AppStore();
      final task = seed(store, start: 9.0, duration: 1.0);

      store.resizeTask(task, 2.5);

      expect(task.durationHours, 2.5);
    });

    test('en kısa süreden aşağı inmez', () {
      final store = AppStore();
      final task = seed(store, start: 9.0);

      store.resizeTask(task, 0.01);

      expect(task.durationHours, kMinDurationHours);
    });

    test('gün sonunu taşmaz', () {
      final store = AppStore();
      final task = seed(store, start: 23.0, duration: 0.5);

      // 23:00'te başlayan iş en fazla 1 saat olabilir.
      store.resizeTask(task, 5.0);

      expect(task.durationHours, 1.0);
    });
  });

  group('setTaskDone', () {
    test('rutinin yalnızca ilgili gününü işaretler', () {
      final store = AppStore();
      final task = seed(store, repeat: const Repeat(RepeatType.daily));

      store.setTaskDone(task, tuesday, true);

      expect(task.isDoneOn(tuesday), isTrue);
      expect(task.isDoneOn(wednesday), isFalse);
    });

    test('işareti geri almak mümkün', () {
      final store = AppStore();
      final task = seed(store);

      store.setTaskDone(task, monday, true);
      store.setTaskDone(task, monday, false);

      expect(task.isDoneOn(monday), isFalse);
    });
  });

  group('tasksForWeek', () {
    test('7 günlük matris döner ve rutinleri her güne yayar', () {
      final store = AppStore();
      seed(store, repeat: const Repeat(RepeatType.daily));
      seed(store, date: wednesday, start: 11.0);

      final week = store.tasksForWeek(monday);

      expect(week, hasLength(7));
      // Günlük rutin her günde var.
      expect(week.every((day) => day.isNotEmpty), isTrue);
      // Çarşamba'da rutin + tek günlük iş = 2.
      expect(week[2], hasLength(2));
      expect(week[0], hasLength(1));
    });

    test('hafta başlangıcı saat taşısa da doğru güne oturur', () {
      final store = AppStore();
      seed(store, date: monday);

      final week = store.tasksForWeek(DateTime(2026, 7, 20, 23, 45));

      expect(week[0], hasLength(1));
    });
  });
}
