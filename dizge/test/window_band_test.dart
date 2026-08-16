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

  Future<void> pumpGrid(WidgetTester tester, Task t) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      testApp(
        home: Scaffold(
          body: WeekTimeGrid(
            monday: monday,
            tasksByDay: List.generate(7, (i) => i == 0 ? [t] : const []),
            metrics: metrics,
            today: monday,
            onTapTask: (_, _) {},
            onTapEmpty: (_, _) {},
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

  /// Şerit, işin kimliğiyle işaretli.
  Finder bandFinder(Task t) => find.byKey(ValueKey('window-band-${t.id}'));

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

  testWidgets('şerit dokunuş almıyor', (tester) async {
    // Kısıtın resmi tıklanacak bir nesne değil: altındaki boş alan dokunuşu
    // şeridin arkasından geçip ızgaraya ulaşmalı.
    final t = task(windowStart: 9, windowEnd: 12);
    await pumpGrid(tester, t);

    expect(
      find.descendant(
        of: bandFinder(t),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
  });
}
