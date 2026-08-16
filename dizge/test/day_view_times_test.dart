import 'package:dizge/models/task.dart';
import 'package:dizge/screens/day_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Z7 — gün görünümünde tekrar başına kart.
///
/// Üç dozluk ilaç üç satır; her satır kendi tikiyle. Tek kart olsaydı
/// "sabahkini içtim" diyecek bir yer kalmazdı.
void main() {
  setUp(TaskRepository.all.clear);

  final day = DateTime(2026, 7, 20);

  /// Uzun yüzey: kart listesi kaydırılırsa alttaki kart hiç kurulmuyor ve
  /// bulucu "yok" diyor. Ölçülen şey yerleşim değil, kart sayısı.
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Task ilac({List<double>? times}) => Task(
    title: 'İlaç',
    color: const Color(0xFF38BDF8),
    date: day,
    startHour: 8,
    durationHours: 0.25,
    timesOfDay: times,
  );

  testWidgets('tek seferlik iş tek kart', (tester) async {
    TaskRepository.all.add(ilac());
    await pumpApp(tester, DayViewScreen(date: day));
    await tester.pumpAndSettle();

    expect(find.text('İlaç'), findsOneWidget);
  });

  testWidgets('üç saatli iş üç kart, saatleri yazılı', (tester) async {
    tallSurface(tester);
    TaskRepository.all.add(ilac(times: [8, 14, 20]));
    await pumpApp(tester, DayViewScreen(date: day));
    await tester.pumpAndSettle();

    expect(find.text('İlaç'), findsNWidgets(3));
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('14:00'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
  });

  testWidgets('bir tekrarı işaretlemek gündeki ötekini bitirmiyor', (
    tester,
  ) async {
    final task = ilac(times: [8, 20]);
    TaskRepository.all.add(task);
    await pumpApp(tester, DayViewScreen(date: day));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('done-${task.id}@8.0')));
    await tester.pumpAndSettle();

    expect(task.isSlotDone(day, 8), isTrue);
    expect(task.isSlotDone(day, 20), isFalse);
    // Gün ancak hepsi bitince tamamlanmış sayılır.
    expect(task.isDoneOn(day), isFalse);

    await tester.tap(find.byKey(ValueKey('done-${task.id}@20.0')));
    await tester.pumpAndSettle();
    expect(task.isDoneOn(day), isTrue);
  });
}
