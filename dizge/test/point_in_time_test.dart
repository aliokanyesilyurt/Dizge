import 'package:dizge/models/task.dart';
import 'package:dizge/screens/day_view_screen.dart';
import 'package:dizge/screens/week_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Z1–Z2 — saat ile süre bağımsız; "saati var, süresi yok" yazılabiliyor.
void main() {
  setUp(TaskRepository.all.clear);

  final day = DateTime(2026, 7, 20);

  Task call({double duration = 0}) => Task(
    title: 'Annemi ara',
    color: Colors.teal,
    date: day,
    startHour: 15,
    durationHours: duration,
  );

  group('model', () {
    test('saatli ve süresiz iş bir andır', () {
      final t = call();
      expect(t.hasDuration, isFalse);
      expect(t.isPointInTime, isTrue);
      expect(t.timeString, '15:00', reason: '"15:00 – 15:00" değil');
      expect(t.durationString, 'Süresiz');
    });

    test('süreli iş aralık, saatsiz iş an değil', () {
      expect(call(duration: 1).isPointInTime, isFalse);
      expect(call(duration: 1).timeString, '15:00 – 16:00');
      final untimed = Task(
        title: 'Okuma',
        color: Colors.teal,
        date: day,
        durationHours: 2,
      );
      expect(untimed.isPointInTime, isFalse);
      expect(untimed.hasDuration, isTrue);
    });

    test('süresizlik kayıttan geri okunur', () {
      final back = Task.fromJson(call().toJson());
      expect(back.durationHours, 0);
      expect(back.isPointInTime, isTrue);
    });
  });

  testWidgets('düzenleyicide saat ve süre ayrı; "Süresiz" seçilebilir', (
    tester,
  ) async {
    useScreenSize(tester, const Size(900, 1400));
    await pumpApp(tester, DayViewScreen(date: day));

    await tester.tap(find.text('Yeni iş'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Başlıksız'),
      'Annemi ara',
    );

    await tester.tap(find.text('Saat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14:00'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Süre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Süresiz'));
    await tester.pumpAndSettle();

    expect(find.textContaining('bir an olarak görünür'), findsOneWidget);

    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();

    final saved = TaskRepository.all.single;
    expect(saved.startHour, 14);
    expect(saved.durationHours, 0);
  });

  testWidgets('haftalık ızgarada süresiz iş an işaretiyle çizilir', (
    tester,
  ) async {
    useScreenSize(tester, const Size(1400, 1000));
    final today = Task.dayKey(DateTime.now());

    await pumpApp(
      tester,
      const WeekViewScreen(),
      seed: (s) {
        s.addTask(
          Task(
            title: 'Annemi ara',
            color: Colors.teal,
            date: today,
            startHour: 15,
            durationHours: 0,
          ),
        );
        s.addTask(
          Task(
            title: 'Toplantı',
            color: Colors.blue,
            date: today,
            startHour: 10,
            durationHours: 1,
          ),
        );
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('Annemi ara'), findsOneWidget);
    // İşaret yalnız süresiz işte.
    expect(find.byIcon(Icons.adjust_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
