import 'package:dizge/data/app_store.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/screens/monthly_view_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// D2 — aylık görünümde işi günler arasında sürüklemek (plan H2, H3).
void main() {
  setUp(TaskRepository.all.clear);

  final aug3 = DateTime(2026, 8, 3);
  final aug5 = DateTime(2026, 8, 5);

  Task todo({double? start = 14.0, Repeat repeat = const Repeat.once()}) =>
      Task(
        title: 'Fatura öde',
        color: const Color(0xFF38BDF8),
        date: aug3,
        startHour: start,
        repeat: repeat,
      );

  group('moveTaskToDay', () {
    test('gün değişir, saat olduğu gibi kalır', () {
      final store = AppStore();
      final task = todo();
      store.addTask(task);

      store.moveTaskToDay(task, aug5);

      expect(task.date, aug5);
      expect(task.startHour, 14.0);
    });

    test('saatsiz iş saatsiz kalır — 00:00a çakılmaz', () {
      final store = AppStore();
      final task = todo(start: null);
      store.addTask(task);

      store.moveTaskToDay(task, aug5);

      expect(task.date, aug5);
      expect(task.startHour, isNull);
    });

    test('clearTime saati siler', () {
      final store = AppStore();
      final task = todo();
      store.addTask(task);

      store.moveTaskToDay(task, aug5, clearTime: true);

      expect(task.startHour, isNull);
    });

    test('rutin taşınmaz', () {
      final store = AppStore();
      final task = todo(repeat: const Repeat(RepeatType.daily));
      store.addTask(task);

      store.moveTaskToDay(task, aug5);

      expect(task.date, aug3);
    });
  });

  group('ekran', () {
    Future<void> pumpMonth(WidgetTester tester, Task task) async {
      useScreenSize(tester, const Size(1400, 1000));
      await pumpApp(
        tester,
        MonthlyViewScreen(initialMonth: aug3),
        seed: (s) => s.addTask(task),
      );
    }

    Offset dayCell(WidgetTester tester, int day) =>
        tester.getCenter(find.text('$day'));

    testWidgets(
      'fare: satırı başka güne sürüklemek işi taşır',
      (tester) async {
        final task = todo();
        await pumpMonth(tester, task);

        final start = tester.getCenter(find.text('Fatura öde'));
        final g = await tester.startGesture(
          start,
          kind: PointerDeviceKind.mouse,
        );
        final target = dayCell(tester, 5) + const Offset(0, 30);
        for (var i = 1; i <= 10; i++) {
          await g.moveTo(Offset.lerp(start, target, i / 10)!);
          await tester.pump();
        }
        await g.up();
        await tester.pumpAndSettle();

        expect(task.date, aug5);
        expect(task.startHour, 14.0, reason: 'saat korunmalı');
        expect(find.text('Geri al'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'dokunmatik: uzun bas + sürükle taşır',
      (tester) async {
        final task = todo();
        await pumpMonth(tester, task);

        final start = tester.getCenter(find.text('Fatura öde'));
        final g = await tester.startGesture(start);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        final target = dayCell(tester, 5) + const Offset(0, 30);
        for (var i = 1; i <= 10; i++) {
          await g.moveTo(Offset.lerp(start, target, i / 10)!);
          await tester.pump();
        }
        await g.up();
        await tester.pumpAndSettle();

        expect(task.date, aug5);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'dokunmatik: uzun bas + kıpırdamadan bırak hızlı menüyü açar',
      (tester) async {
        final task = todo();
        await pumpMonth(tester, task);

        final g = await tester.startGesture(
          tester.getCenter(find.text('Fatura öde')),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await g.up();
        await tester.pumpAndSettle();

        expect(task.date, aug3, reason: 'iş yerinde kalmalı');
        expect(find.text('Düzenle'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets('rutin sürüklenmez, uzun basma menüyü açar', (tester) async {
      final routine = todo(repeat: const Repeat(RepeatType.weekly));
      await pumpMonth(tester, routine);

      await tester.longPress(find.text('↻ Fatura öde').first);
      await tester.pumpAndSettle();

      expect(find.byType(LongPressDraggable<Task>), findsNothing);
      expect(find.text('Düzenle'), findsOneWidget);
    });
  });
}
