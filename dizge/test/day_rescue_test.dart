import 'package:dizge/core/day_rescue.dart';
import 'package:dizge/data/app_store.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/screens/week_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Ö2 — "Günü kurtar".
///
/// Testlerin ağırlığı bilerek [planDayRescue] üzerinde: bu düğmenin asıl riski
/// görünmemesi değil, **yanlış işi süpürmesi**. Plan §6'nın sözleşmesindeki
/// her satırın burada bir karşılığı var.
void main() {
  setUp(TaskRepository.all.clear);

  final day = DateTime(2026, 8, 10);

  Task make(
    String title, {
    double? startHour,
    bool isFixed = false,
    Repeat repeat = const Repeat.once(),
  }) => Task(
    title: title,
    color: Colors.blue,
    date: day,
    startHour: startHour,
    isFixed: isFixed,
    repeat: repeat,
  );

  // --- Sözleşme (§6) --------------------------------------------------------

  group('sözleşme', () {
    test(
      'esnek tek günlük işler havuza, esnek rutinler atlananlara ayrılır',
      () {
        final once = make('Rapor', startHour: 15);
        final routine = make(
          'Spor',
          startHour: 16,
          repeat: const Repeat(RepeatType.daily),
        );

        final plan = planDayRescue([once, routine], day: day, afterHour: 12);

        expect(plan.toPool, [once]);
        expect(plan.toSkip, [routine]);
        expect(plan.total, 2);
      },
    );

    test('sabit iş dokunulmaz', () {
      final fixed = make('Doktor', startHour: 15, isFixed: true);
      final plan = planDayRescue([fixed], day: day, afterHour: 12);
      expect(plan.isEmpty, isTrue);
    });

    test('tamamlanmış iş dokunulmaz', () {
      final done = make('Fatura', startHour: 15)..setDone(day, true);
      final plan = planDayRescue([done], day: day, afterHour: 12);
      expect(plan.isEmpty, isTrue);
    });

    test('zaten atlanmış rutin ikinci kez atlanmaz', () {
      final routine = make(
        'Spor',
        startHour: 16,
        repeat: const Repeat(RepeatType.daily),
      )..setSkipped(day, true);

      final plan = planDayRescue([routine], day: day, afterHour: 12);
      expect(plan.isEmpty, isTrue);
    });

    test('şu andan önce başlayan iş süpürülmez, başlamamış olan süpürülür', () {
      final past = make('Sabah toplantısı', startHour: 9);
      final running = make('Süren iş', startHour: 13.5);
      final future = make('Akşam işi', startHour: 18);

      final plan = planDayRescue(
        [past, running, future],
        day: day,
        // 14:00 — "Süren iş" 13:30'da başladı, elde duruyor.
        afterHour: 14,
      );

      expect(plan.toPool, [future]);
    });

    test('saatsiz iş, saat kaç olursa olsun kapsamda', () {
      final untimed = make('Bir ara hallet');
      final plan = planDayRescue([untimed], day: day, afterHour: 23.9);
      expect(plan.toPool, [untimed]);
    });

    test('hiç uygun iş yoksa plan boş', () {
      final plan = planDayRescue(
        [make('Doktor', startHour: 15, isFixed: true)],
        day: day,
        afterHour: 12,
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.total, 0);
    });

    test('özet iki türü ayrı sayar', () {
      final plan = DayRescuePlan(
        day: day,
        toPool: [make('a'), make('b')],
        toSkip: [make('c', repeat: const Repeat(RepeatType.daily))],
      );
      expect(plan.describe(), '2 iş kenara alındı · 1 rutin atlandı');
    });
  });

  // --- Uygulama ve geri alma ------------------------------------------------

  group('uygulama', () {
    test('kurtarma takvimi boşaltır, geri alma eski hâli döndürür', () {
      final store = AppStore();
      final once = make('Rapor', startHour: 15);
      final routine = make(
        'Spor',
        startHour: 16,
        repeat: const Repeat(RepeatType.daily),
      );
      store.addTask(once);
      store.addTask(routine);

      final plan = planDayRescue(
        store.tasksForDate(day),
        day: day,
        afterHour: 12,
      );
      store.applyDayRescue(plan);

      // Tek günlük iş takvimden çekildi; rutin yerinde ama atlanmış.
      expect(once.inPool, isTrue);
      expect(once.occursOn(day), isFalse);
      expect(routine.inPool, isFalse);
      expect(routine.occursOn(day), isTrue);
      expect(routine.isSkippedOn(day), isTrue);

      store.undoDayRescue(plan);

      expect(once.inPool, isFalse);
      expect(once.occursOn(day), isTrue);
      expect(routine.isSkippedOn(day), isFalse);
    });

    test('havuza giden işin günü ve saati korunur', () {
      final store = AppStore();
      final task = make('Rapor', startHour: 15.5);
      store.addTask(task);

      store.applyDayRescue(planDayRescue([task], day: day, afterHour: 12));

      expect(task.date, day);
      expect(task.startHour, 15.5);
    });

    test('atlamak tamamlanma geçmişine dokunmaz', () {
      final store = AppStore();
      final routine = make(
        'Spor',
        startHour: 16,
        repeat: const Repeat(RepeatType.daily),
      )..setDone(day.subtract(const Duration(days: 1)), true);
      store.addTask(routine);

      store.skipRoutineOn(routine, day, true);

      expect(routine.isSkippedOn(day), isTrue);
      expect(routine.isDoneOn(day), isFalse);
      // Dünkü tik yerinde: "bugün geçiyorum" geçmişi silmez.
      expect(routine.isDoneOn(day.subtract(const Duration(days: 1))), isTrue);
    });
  });

  // --- Model / kayıt --------------------------------------------------------

  group('model', () {
    test('isFixed ve skippedOn kayıttan tam döner', () {
      final task = make('Doktor', startHour: 15, isFixed: true)
        ..setSkipped(day, true);

      final back = Task.fromJson(task.toJson());

      expect(back.isFixed, isTrue);
      expect(back.isSkippedOn(day), isTrue);
    });

    test('eski kayıtta alanlar yoksa iş esnek ve atlanmamış', () {
      final back = Task.fromJson({
        'id': 'x',
        'title': 'Eski iş',
        'date': '2026-08-10',
      });

      expect(back.isFixed, isFalse);
      expect(back.skippedOn, isEmpty);
    });

    test('kopyalama sabitliği devralır, atlamayı devralmaz', () {
      final source = make('Ders', startHour: 10, isFixed: true)
        ..setSkipped(day, true);

      final copy = source.duplicateTo(day.add(const Duration(days: 1)));

      expect(copy.isFixed, isTrue);
      expect(copy.skippedOn, isEmpty);
    });
  });

  // --- Arayüz ---------------------------------------------------------------

  group('arayüz', () {
    testWidgets('kurtarılacak iş yokken düğme pasif', (tester) async {
      useScreenSize(tester, const Size(1200, 900));

      await pumpApp(tester, const WeekViewScreen());

      final button = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text('Günü kurtar'),
          matching: find.byType(Tooltip),
        ),
      );
      expect(button.message, 'Kurtarılacak iş yok');
    });

    testWidgets('bugün esnek iş varken düğme aktif ve sayıyı söyler', (
      tester,
    ) async {
      useScreenSize(tester, const Size(1200, 900));
      final today = Task.dayKey(DateTime.now());

      await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (store) {
          // Saatsiz: günün saati ne olursa olsun kapsamda kalır, böylece test
          // sabahleyin de akşamleyin de aynı sonucu verir.
          store.addTask(
            Task(title: 'Bir ara hallet', color: Colors.blue, date: today),
          );
        },
      );

      final button = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text('Günü kurtar'),
          matching: find.byType(Tooltip),
        ),
      );
      expect(button.message, contains('1 esnek'));
    });

    testWidgets('düğme dört işi onaysız süpürür ve geri alınabilir', (
      tester,
    ) async {
      useScreenSize(tester, const Size(1200, 900));
      final today = Task.dayKey(DateTime.now());

      final container = await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (store) {
          for (var i = 0; i < 4; i++) {
            store.addTask(
              Task(title: 'İş $i', color: Colors.blue, date: today),
            );
          }
        },
      );

      await tester.tap(find.text('Günü kurtar'));
      await tester.pumpAndSettle();

      // Beşin altında onay sorulmaz.
      expect(find.text('Günü kurtaralım mı?'), findsNothing);
      expect(container.read(poolProvider), hasLength(4));

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();

      expect(container.read(poolProvider), isEmpty);
    });

    testWidgets(
      'beş ve üzeri iş önce onay ister; vazgeçmek hiçbir şeyi taşımaz',
      (tester) async {
        useScreenSize(tester, const Size(1200, 900));
        final today = Task.dayKey(DateTime.now());

        final container = await pumpApp(
          tester,
          const WeekViewScreen(),
          seed: (store) {
            for (var i = 0; i < 5; i++) {
              store.addTask(
                Task(title: 'İş $i', color: Colors.blue, date: today),
              );
            }
          },
        );

        await tester.tap(find.text('Günü kurtar'));
        await tester.pumpAndSettle();

        expect(find.text('Günü kurtaralım mı?'), findsOneWidget);
        expect(container.read(poolProvider), isEmpty);

        await tester.tap(find.text('Vazgeç'));
        await tester.pumpAndSettle();

        expect(container.read(poolProvider), isEmpty);

        // Onaylayınca uygulanır.
        await tester.tap(find.text('Günü kurtar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kurtar'));
        await tester.pumpAndSettle();

        expect(container.read(poolProvider), hasLength(5));
      },
    );

    testWidgets('390px başlıkta kurtarma düğmesi taşma yapmıyor', (
      tester,
    ) async {
      useScreenSize(tester, const Size(390, 844));
      final today = Task.dayKey(DateTime.now());

      await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (store) => store.addTask(
          Task(title: 'Bir ara hallet', color: Colors.blue, date: today),
        ),
      );

      // Başlık zaten doluydu (plan §5.3): enerji seçici eklenince 1.7px
      // taşmıştı. Altıncı denetim "Bugün"ün yuvasını devraldığı için genişlik
      // artmıyor — bu testin bekçilediği şey tam olarak o karar.
      expect(tester.takeException(), isNull);
      // Dar ekranda yazı düşer, ipucu kalır.
      expect(find.text('Günü kurtar'), findsNothing);
      expect(find.byTooltip('Kurtarılacak iş yok'), findsNothing);
    });

    testWidgets('"Bugün" ile "Günü kurtar" aynı yuvayı paylaşır', (
      tester,
    ) async {
      useScreenSize(tester, const Size(1200, 900));

      await pumpApp(tester, const WeekViewScreen());

      // Bu haftadayken kurtarma düğmesi var, "Bugün" yok.
      expect(find.text('Günü kurtar'), findsOneWidget);
      expect(find.text('Bugün'), findsNothing);

      await tester.tap(find.byTooltip('Sonraki hafta'));
      await tester.pumpAndSettle();

      // Başka haftada tam tersi: geçen haftayı kurtarmak diye bir şey yok.
      expect(find.text('Günü kurtar'), findsNothing);
      expect(find.text('Bugün'), findsOneWidget);
    });
  });

  group('Z5 — saat penceresi', () {
    Task windowed({required double from, required double to}) => Task(
      title: 'Rapor',
      color: const Color(0xFF38BDF8),
      date: DateTime(2026, 8, 17),
      startHour: null,
      windowStart: from,
      windowEnd: to,
    );

    test('açık pencere korunuyor', () {
      // Pencere açıkken iş şu an yapılıyor olabilir: başlamış saatli işle
      // aynı gerekçeyle masadan alınmıyor.
      final task = windowed(from: 9, to: 12);
      final plan = planDayRescue(
        [task],
        day: DateTime(2026, 8, 17),
        afterHour: 10,
      );
      expect(plan.isEmpty, isTrue);
    });

    test('kapanmış pencere korunmuyor', () {
      // Bugün artık olamaz; kenara alınacakların tam da kendisi.
      final task = windowed(from: 9, to: 12);
      final plan = planDayRescue(
        [task],
        day: DateTime(2026, 8, 17),
        afterHour: 15,
      );
      expect(plan.toPool, [task]);
    });

    test('ileride duran pencere bugünkü davranışta', () {
      final task = windowed(from: 18, to: 22);
      final plan = planDayRescue(
        [task],
        day: DateTime(2026, 8, 17),
        afterHour: 15,
      );
      expect(plan.toPool, [task]);
    });

    test('penceresiz saatsiz iş bugünkü gibi süpürülüyor', () {
      final task = Task(
        title: 'Saatsiz',
        color: const Color(0xFF38BDF8),
        date: DateTime(2026, 8, 17),
      );
      final plan = planDayRescue(
        [task],
        day: DateTime(2026, 8, 17),
        afterHour: 10,
      );
      expect(plan.toPool, [task]);
    });
  });
}
