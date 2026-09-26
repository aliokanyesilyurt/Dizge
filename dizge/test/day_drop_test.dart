import 'package:dizge/core/pool_panel_controller.dart';
import 'package:dizge/core/time_grid.dart';
import 'package:dizge/data/app_store.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/screens/week/day_drop_target.dart';
import 'package:dizge/screens/week_view_screen.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// D4 — güne bırakmak ≠ saate bırakmak (plan H5).
void main() {
  setUp(TaskRepository.all.clear);

  final monday = mondayOf(DateTime.now());

  Task task(
    String title, {
    DateTime? date,
    double? start,
    bool inPool = false,
    Repeat repeat = const Repeat.once(),
  }) => Task(
    title: title,
    color: const Color(0xFF38BDF8),
    date: date ?? monday,
    startHour: start,
    inPool: inPool,
    repeat: repeat,
  );

  group('kabul kuralı', () {
    final wed = monday.add(const Duration(days: 2));

    test('havuzdaki iş her güne iner', () {
      expect(DayDropTarget.accepts(task('a', inPool: true), wed), isTrue);
    });

    test('rutin reddedilir', () {
      final r = task('r', repeat: const Repeat(RepeatType.daily));
      expect(DayDropTarget.accepts(r, wed), isFalse);
    });

    test('saatsiz iş kendi gününe bırakılamaz', () {
      expect(DayDropTarget.accepts(task('a'), monday), isFalse);
      expect(DayDropTarget.accepts(task('a'), wed), isTrue);
    });
  });

  group('store', () {
    test('untimed: havuzdan eski saatini almadan iner', () {
      final store = AppStore();
      final t = task('a', start: 14, inPool: true);
      store.addTask(t);

      store.pullFromPool(t, toDay: monday, untimed: true);

      expect(t.inPool, isFalse);
      expect(t.startHour, isNull);
    });
  });

  group('haftalık ekran', () {
    Future<void> dragTo(
      WidgetTester tester,
      Finder from,
      Finder to, {
      bool longPress = true,
    }) async {
      final start = tester.getCenter(from);
      final end = tester.getCenter(to);
      final g = await tester.startGesture(start);
      // Havuz kartı uzun bas + sürükle istiyor; saatsiz çip düz sürükleniyor
      // (onun uzun basması "yaptım").
      if (longPress) {
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      }
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(start, end, i / 10)!);
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    testWidgets('havuz kartını gün başlığına bırakmak işi saatsiz koyar', (
      tester,
    ) async {
      useScreenSize(tester, const Size(1400, 1000));
      final pooled = task('Vergi', start: 14, inPool: true);
      await pumpApp(
        tester,
        const WeekViewScreen(),
        overrides: [
          poolPanelOpenProvider.overrideWith(
            (ref) => PoolPanelController(InMemoryStore())..set(true),
          ),
        ],
        seed: (s) => s.addTask(pooled),
      );

      // İlk yedi hedef gün başlıkları (saatsiz şerit boşken çizilmiyor).
      await dragTo(
        tester,
        find.text('Vergi'),
        find.byType(DayDropTarget).at(3),
      );

      expect(pooled.inPool, isFalse);
      expect(pooled.date, monday.add(const Duration(days: 3)));
      expect(pooled.startHour, isNull, reason: 'güne bırakmak saat vermez');
      expect(find.text('Geri al'), findsOneWidget);
    });

    testWidgets('saatsiz iş başka günün başlığına taşınır', (tester) async {
      useScreenSize(tester, const Size(1400, 1000));
      final untimed = task('Market');
      await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (s) => s.addTask(untimed),
      );

      await dragTo(
        tester,
        find.text('Market'),
        find.byType(DayDropTarget).at(4),
        longPress: false,
      );

      expect(untimed.date, monday.add(const Duration(days: 4)));
      expect(untimed.startHour, isNull);
    });
  });
}
