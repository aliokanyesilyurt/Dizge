import 'package:dizge/core/navigation_controller.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/screens/monthly_view_screen.dart';
import 'package:dizge/screens/routines_screen.dart';
import 'package:dizge/screens/todos_screen.dart';
import 'package:dizge/screens/week_view_screen.dart';
import 'package:dizge/widgets/task_check.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// "Yaptım" her ekranda olmalı.
///
/// Bildirilen kusur: "görevi yaptığımı onaylamak için yapılacaklar rutinler
/// kısmında onay tuşu yok, takvimden de işaretleyemiyorsun — tek yer günlük
/// görünüm". Kodda gerçekten öyleydi: `setTaskDone` yalnız iki yerden
/// çağrılıyordu (gün görünümü ve haftalık saatsiz satırın uzun basışı).
///
/// Tamamlama uygulamanın en sık yapılan hareketi. Bu testler onun her
/// yüzeyde bulunabilir kaldığını tutuyor.
void main() {
  setUp(TaskRepository.all.clear);

  const wide = Size(1400, 1000);

  DateTime thisMonday() {
    final today = Task.dayKey(DateTime.now());
    return today.subtract(Duration(days: today.weekday - 1));
  }

  group('yapılacaklar', () {
    testWidgets('satırdaki kutu işi tamamlar ve geri alır', (tester) async {
      late Task task;
      final day = Task.dayKey(DateTime.now());

      await pumpApp(
        tester,
        const TodosScreen(),
        seed: (store) {
          task = Task(title: 'Rapor yaz', color: Colors.blue, date: day);
          store.addTask(task);
        },
      );

      expect(find.byType(TaskCheck), findsOneWidget);
      expect(task.isDoneOn(day), isFalse);

      await tester.tap(find.byType(TaskCheck));
      await tester.pumpAndSettle();
      expect(task.isDoneOn(day), isTrue, reason: 'kutu işi tamamlamalı');

      await tester.tap(find.byType(TaskCheck));
      await tester.pumpAndSettle();
      expect(task.isDoneOn(day), isFalse, reason: 'aynı kutu geri almalı');
    });

    testWidgets('başlık açık iş sayısını canlı sayıyor', (tester) async {
      late Task task;
      final day = Task.dayKey(DateTime.now());

      await pumpApp(
        tester,
        const TodosScreen(),
        seed: (store) {
          task = Task(title: 'Rapor yaz', color: Colors.blue, date: day);
          store.addTask(task);
        },
      );

      expect(find.text('1 açık · 1 toplam'), findsOneWidget);

      await tester.tap(find.byType(TaskCheck));
      await tester.pumpAndSettle();

      expect(find.text('0 açık · 1 toplam'), findsOneWidget);
    });
  });

  group('rutinler', () {
    testWidgets('kutu bugünü işaretler', (tester) async {
      late Task routine;
      final today = Task.dayKey(DateTime.now());

      await pumpApp(
        tester,
        const RoutinesScreen(),
        seed: (store) {
          routine = Task(
            title: 'Sabah koşusu',
            color: Colors.green,
            date: today.subtract(const Duration(days: 30)),
            startHour: 7,
            repeat: const Repeat(RepeatType.daily),
          );
          store.addTask(routine);
        },
      );

      await tester.tap(find.byType(TaskCheck));
      await tester.pumpAndSettle();

      expect(routine.isDoneOn(today), isTrue);
      // Dünü kimse işaretlemedi: tek kutu yalnız bugünü kastediyor.
      expect(
        routine.isDoneOn(today.subtract(const Duration(days: 1))),
        isFalse,
      );
    });

    testWidgets('kutunun hangi güne baktığı satırda yazıyor', (tester) async {
      final today = Task.dayKey(DateTime.now());

      await pumpApp(
        tester,
        const RoutinesScreen(),
        seed: (store) => store.addTask(
          Task(
            title: 'Sabah koşusu',
            color: Colors.green,
            date: today,
            startHour: 7,
            repeat: const Repeat(RepeatType.daily),
          ),
        ),
      );

      // Tekrar eden bir işte tek kutu, hangi günü kastettiğini söylemezse
      // "bu rutini tamamen bitirdim" diye okunur.
      expect(find.textContaining('bugün açık'), findsOneWidget);

      await tester.tap(find.byType(TaskCheck));
      await tester.pumpAndSettle();

      expect(find.textContaining('bugün tamam'), findsOneWidget);
    });
  });

  group('haftalık ızgara', () {
    testWidgets('blok önizlemesinden işaretlenir', (tester) async {
      useScreenSize(tester, wide);
      final monday = thisMonday();
      late Task task;

      await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (store) {
          task = Task(
            title: 'Toplantı',
            color: Colors.blue,
            date: monday,
            startHour: 14,
            durationHours: 1.5,
          );
          store.addTask(task);
        },
      );

      await tester.tap(find.text('Toplantı').first);
      await tester.pumpAndSettle();
      expect(find.text('Düzenle'), findsOneWidget, reason: 'önizleme açılmalı');

      await tester.tap(find.byType(TaskCheck));
      await tester.pumpAndSettle();

      expect(task.isDoneOn(monday), isTrue);
    });

    testWidgets('sağ tık menüsünde de tamamlama var', (tester) async {
      useScreenSize(tester, wide);
      final monday = thisMonday();
      late Task task;

      await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (store) {
          task = Task(
            title: 'Toplantı',
            color: Colors.blue,
            date: monday,
            startHour: 14,
            durationHours: 1.5,
          );
          store.addTask(task);
        },
      );

      await tester.tap(find.text('Toplantı').first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yaptım'));
      await tester.pumpAndSettle();

      expect(task.isDoneOn(monday), isTrue);
    });
  });

  group('aylık ızgara', () {
    testWidgets('hücredeki iş satırına dokunmak onu tamamlar', (tester) async {
      useScreenSize(tester, wide);
      final day = DateTime(2026, 3, 12);
      late Task task;

      final container = await pumpApp(
        tester,
        MonthlyViewScreen(initialMonth: day),
        seed: (store) {
          task = Task(title: 'Rapor yaz', color: Colors.blue, date: day);
          store.addTask(task);
        },
      );

      await tester.tap(find.text('Rapor yaz'));
      await tester.pumpAndSettle();

      expect(task.isDoneOn(day), isTrue);
      // İş satırı hücrenin dokunuşunu yutmalı: eskiden aylık takvimde tek
      // yapılabilen şey günü açmaktı, tek bir işe ulaşılamıyordu.
      expect(
        container.read(navigationProvider).section,
        isNot(AppSection.hour),
        reason: 'iş satırına dokunmak günü açmamalı',
      );

      await tester.tap(find.text('Rapor yaz'));
      await tester.pumpAndSettle();
      expect(task.isDoneOn(day), isFalse, reason: 'ikinci dokunuş geri almalı');
    });

    testWidgets('hücrenin boşluğu hâlâ günü seçip açıyor', (tester) async {
      useScreenSize(tester, wide);
      final day = DateTime(2026, 3, 12);

      final container = await pumpApp(
        tester,
        MonthlyViewScreen(initialMonth: day),
      );

      await tester.tap(find.text('12').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('12').first);
      await tester.pumpAndSettle();

      expect(container.read(navigationProvider).section, AppSection.hour);
    });
  });
}
