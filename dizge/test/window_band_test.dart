import 'package:dizge/core/time_grid.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/widgets/week_time_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Z4 — saat penceresinin ızgaradaki şeridi.
///
/// Şerit bir kısıtın resmi: bloğun **arkasında** durur, dokunuş almaz ve
/// yüksekliği aralığın kendisidir. Penceresiz iş bugünkü gibi çizilir.
void main() {
  final monday = DateTime(2026, 7, 20);
  const hourHeight = 60.0;
  const metrics = GridMetrics(hourHeight: hourHeight);

  Task task({double? windowStart, double? windowEnd}) => Task(
    title: 'Rapor',
    color: const Color(0xFF38BDF8),
    date: monday,
    startHour: 10,
    durationHours: 1,
    windowStart: windowStart,
    windowEnd: windowEnd,
  );

  /// İşi verilen günlere koyarak ızgarayı çizer.
  ///
  /// Rutin, deponun aynı `Task` nesnesini birden çok güne döndürmesiyle
  /// görünür; bu yardımcı o durumu birebir taklit ediyor.
  Future<void> pumpGridOnDays(
    WidgetTester tester,
    Task t,
    Set<int> days,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      testApp(
        home: Scaffold(
          body: WeekTimeGrid(
            monday: monday,
            tasksByDay: List.generate(
              7,
              (i) => days.contains(i) ? [t] : const <Task>[],
            ),
            metrics: metrics,
            today: monday,
            onTapTask: (_, _) {},
            onTapEmpty: (_, _) {},
            onToggleDone: (_, _, _) {},
            onMove: (_, _, _) {},
            onResize: (_, _) {},
            onDuplicate: (_, _) {},
            onDelete: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpGrid(WidgetTester tester, Task t) =>
      pumpGridOnDays(tester, t, {0});

  /// Şerit, işin kimliği **ve günüyle** işaretli: aynı rutin haftada birkaç
  /// gün göründüğünde her günün kendi şeridi var.
  Finder bandFinder(Task t, {int day = 0}) =>
      find.byKey(ValueKey('window-band-${t.id}@$day'));

  testWidgets('penceresiz işte şerit çizilmiyor', (tester) async {
    final t = task();
    await pumpGrid(tester, t);
    expect(bandFinder(t), findsNothing);
  });

  testWidgets('pencereli işte şerit çiziliyor', (tester) async {
    final t = task(windowStart: 9, windowEnd: 12);
    await pumpGrid(tester, t);
    expect(bandFinder(t), findsOneWidget);
  });

  testWidgets('şeridin yüksekliği aralığın kendisi', (tester) async {
    // 09:00–12:00 üç saat; ızgarada saat başına 60 piksel.
    final t = task(windowStart: 9, windowEnd: 12);
    await pumpGrid(tester, t);

    final size = tester.getSize(bandFinder(t));
    expect(size.height, closeTo(3 * hourHeight, 0.5));
  });

  testWidgets('haftaya yayılan rutinde her günün kendi şeridi var', (
    tester,
  ) async {
    // Rutin, deponun **aynı** Task nesnesini birden çok güne döndürmesiyle
    // görünüyor. Şeridin anahtarı yalnız `task.id` olsaydı bütün günlerin
    // şeridi tek bir Stack'e aynı kimlikle girer, Flutter "Duplicate keys
    // found" diye ağacı düşürürdü.
    final t = task(windowStart: 9, windowEnd: 12);
    await pumpGridOnDays(tester, t, {0, 2, 4});

    expect(tester.takeException(), isNull);
    for (final day in [0, 2, 4]) {
      expect(bandFinder(t, day: day), findsOneWidget);
    }
    expect(bandFinder(t, day: 1), findsNothing);
  });

  testWidgets('şerit dokunuş almıyor', (tester) async {
    // Kısıtın resmi tıklanacak bir nesne değil: altındaki boş alan dokunuşu
    // şeridin arkasından geçip ızgaraya ulaşmalı.
    final t = task(windowStart: 9, windowEnd: 12);
    await pumpGrid(tester, t);

    expect(
      find.descendant(of: bandFinder(t), matching: find.byType(IgnorePointer)),
      findsOneWidget,
    );
  });
}
