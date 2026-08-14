import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/data/app_store.dart';
import 'package:scheduler_app/models/habit.dart';
import 'package:scheduler_app/models/node.dart';
import 'package:scheduler_app/models/task.dart';
import 'package:scheduler_app/screens/habits_screen.dart';
import 'package:scheduler_app/screens/notes_screen.dart';
import 'package:scheduler_app/screens/reports_screen.dart';

import 'helpers.dart';

/// Verili bir store ile ekranı gerçek widget ağacında çizer; layout/paint
/// hatalarını (heatmap, grafikler) yakalar.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen,
  void Function(AppStore) seed,
) async {
  final container = ProviderContainer();
  seed(container.read(appStoreProvider));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(container.dispose);
}

void main() {
  setUp(TaskRepository.all.clear);

  testWidgets('Alışkanlıklar ekranı seri + ısı haritasıyla çizilir', (
    tester,
  ) async {
    await pumpScreen(tester, const HabitsScreen(), (store) {
      final h = Habit(title: 'Sabah koşusu', color: const Color(0xFF34E39B));
      h.setDone(DateTime.now(), true);
      store.addHabit(h);
    });
    expect(find.text('Sabah koşusu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Raporlar ekranı grafiklerle çizilir', (tester) async {
    await pumpScreen(tester, const ReportsScreen(), (store) {
      store.addTask(
        Task(
          title: 'İş görevi',
          color: const Color(0xFF5AA9FF),
          date: DateTime.now(),
          categoryName: 'İş',
        )..setDone(DateTime.now(), true),
      );
    });
    expect(find.text('Raporlar'), findsOneWidget);
    expect(find.text('Tamamlanma'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Notlar: not açılır ve backlink paneli görünür', (tester) async {
    await pumpScreen(tester, const NotesScreen(), (store) {
      final note = Note(title: 'ESP32 Pinout', body: 'SDA=21');
      store.addNote(note);
      store.addTask(
        Task(
          title: 'Kod yaz',
          note: 'bkz [[ESP32 Pinout]]',
          color: const Color(0xFF5AA9FF),
          date: DateTime.now(),
        ),
      );
    });
    // Listede not görünür.
    expect(find.text('ESP32 Pinout'), findsOneWidget);
    await tester.tap(find.text('ESP32 Pinout'));
    await tester.pumpAndSettle();
    // Detayda backlink paneli ve görev backlink'i görünür.
    expect(find.text('Backlinks (buraya bağlananlar)'), findsOneWidget);
    expect(find.text('Kod yaz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
