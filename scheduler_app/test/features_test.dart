import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/models/habit.dart';
import 'package:scheduler_app/models/task.dart';
import 'package:scheduler_app/services/productivity_report.dart';

DateTime dayAgo(int n) {
  final t = DateTime.now();
  return DateTime(t.year, t.month, t.day).subtract(Duration(days: n));
}

void main() {
  group('Habit streak', () {
    test('günlük: ardışık günler seriyi büyütür, bugün beklerse kırılmaz', () {
      final h = Habit(title: 'Koşu', color: const Color(0xFF81C784));
      // Bugün hariç son 3 gün yapılmış (dün, önceki, ondan önceki).
      h.setDone(dayAgo(1), true);
      h.setDone(dayAgo(2), true);
      h.setDone(dayAgo(3), true);
      expect(h.currentStreak, 3); // bugün henüz yapılmadı ama seri korunur

      h.setDone(dayAgo(0), true);
      expect(h.currentStreak, 4);
    });

    test('günlük: boşluk seriyi keser', () {
      final h = Habit(title: 'Gitar', color: const Color(0xFF4FC3F7));
      h.setDone(dayAgo(0), true);
      h.setDone(dayAgo(1), true);
      h.setDone(dayAgo(3), true); // 2 gün önce atlanmış
      expect(h.currentStreak, 2);
    });

    test('haftalık: hedefi tutan ardışık haftalar seri sayılır', () {
      final h = Habit(
        title: 'Spor',
        color: const Color(0xFFFFB74D),
        cadence: HabitCadence.weekly,
        targetPerWeek: 3,
      );
      // Bu hafta 3 gün.
      final monThis = Habit.weekStart(DateTime.now());
      for (var i = 0; i < 3; i++) {
        h.setDone(monThis.add(Duration(days: i)), true);
      }
      // Geçen hafta 3 gün.
      final monLast = monThis.subtract(const Duration(days: 7));
      for (var i = 0; i < 3; i++) {
        h.setDone(monLast.add(Duration(days: i)), true);
      }
      expect(h.currentStreak, 2);
    });

    test('JSON round-trip alışkanlığı korur', () {
      final h = Habit(
        title: 'Kod',
        color: const Color(0xFFBA68C8),
        cadence: HabitCadence.weekly,
        targetPerWeek: 5,
      );
      h.setDone(dayAgo(1), true);
      final clone = Habit.fromJson(h.toJson());
      expect(clone.id, h.id);
      expect(clone.title, 'Kod');
      expect(clone.cadence, HabitCadence.weekly);
      expect(clone.targetPerWeek, 5);
      expect(clone.isDoneOn(dayAgo(1)), true);
    });
  });

  group('ProductivityReport', () {
    test('tamamlanma oranı ve kategori süresi doğru hesaplanır', () {
      final tasks = [
        Task(
          title: 'A',
          color: const Color(0xFF529CCA),
          date: dayAgo(1),
          durationHours: 2,
          categoryName: 'İş',
          tags: {'yazılım'},
        )..setDone(dayAgo(1), true),
        Task(
          title: 'B',
          color: const Color(0xFFC9769B),
          date: dayAgo(1),
          durationHours: 1,
          categoryName: 'İş',
        ), // tamamlanmadı
      ];

      final r = ProductivityReport.build(tasks, days: 7);
      expect(r.planned, 2);
      expect(r.completed, 1);
      expect(r.completionRate, closeTo(0.5, 1e-9));
      // İş kategorisinde 3 saat planlandı.
      final isBucket = r.byCategory.firstWhere((b) => b.label == 'İş');
      expect(isBucket.hours, 3);
      // Etiket dağılımı yazılım = 2 saat.
      expect(r.byTag.single.label, 'yazılım');
      expect(r.byTag.single.hours, 2);
    });

    test('veri yoksa oran 0 ve listeler boş', () {
      final r = ProductivityReport.build([], days: 30);
      expect(r.planned, 0);
      expect(r.completionRate, 0);
      expect(r.byCategory, isEmpty);
    });
  });
}
