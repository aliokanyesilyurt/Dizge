import 'package:dizge/core/time_grid.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/widgets/week_time_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Z7 — çoklu saatin ızgaradaki hâli.
///
/// Üç saat girilen iş üç blok çiziyor; tik her tekrarın kendi durumu.
void main() {
  final monday = DateTime(2026, 7, 20);
  const metrics = GridMetrics(hourHeight: 60.0);

  Task ilac({List<double>? times}) => Task(
    title: 'İlaç',
    color: const Color(0xFF38BDF8),
    date: monday,
    startHour: 8,
    durationHours: 0.5,
    timesOfDay: times,
  );

  Future<void> pumpGrid(WidgetTester tester, Task t) async {
    tester.view.physicalSize = const Size(1000, 700);
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

  testWidgets('tek seferlik iş tek blok', (tester) async {
    await pumpGrid(tester, ilac());
    expect(find.text('İlaç'), findsOneWidget);
  });

  testWidgets('üç saatli iş üç blok çiziyor', (tester) async {
    await pumpGrid(tester, ilac(times: [8, 14, 20]));
    expect(find.text('İlaç'), findsNWidgets(3));
  });

  testWidgets('bloklar kendi saatlerinde duruyor', (tester) async {
    await pumpGrid(tester, ilac(times: [8, 14, 20]));

    final tops =
        tester
            .widgetList<Text>(find.text('İlaç'))
            .map((w) => tester.getTopLeft(find.byWidget(w)).dy)
            .toList()
          ..sort();

    // Saat başına 60 piksel: 08:00 ile 14:00 arası altı saat.
    expect(tops[1] - tops[0], closeTo(6 * 60.0, 2.0));
    expect(tops[2] - tops[1], closeTo(6 * 60.0, 2.0));
  });

  testWidgets('sabah dozu işaretliyken akşamki boş görünüyor', (tester) async {
    final t = ilac(times: [8, 20]);
    t.setSlotDone(monday, 8, true);

    await pumpGrid(tester, t);

    // Tamamlanma yalnız renge değil ✓ ikonuna da yaslanıyor (WCAG 1.4.1);
    // iki bloktan yalnız biri tikli olmalı.
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(t.isDoneOn(monday), isFalse);
  });
}
