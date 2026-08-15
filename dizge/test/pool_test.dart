import 'package:dizge/data/app_store.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/data/sync/mutation.dart';
import 'package:dizge/data/sync/outbox.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/screens/day_view_screen.dart';
import 'package:dizge/screens/monthly_view_screen.dart';
import 'package:dizge/screens/todos_screen.dart';
import 'package:dizge/screens/week_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Ö1a — havuz modeli ("Kenarda Bekleyenler").
void main() {
  setUp(TaskRepository.all.clear);

  Task todo({DateTime? date, bool inPool = false}) => Task(
    title: 'Fatura öde',
    color: const Color(0xFF38BDF8),
    date: date ?? DateTime(2026, 8, 5),
    startHour: 10,
    inPool: inPool,
  );

  group('model', () {
    test('varsayılan havuz dışı', () {
      expect(todo().inPool, isFalse);
    });

    test('havuzdaki iş kendi gününde bile görünmez', () {
      final task = todo(inPool: true);
      expect(task.occursOn(DateTime(2026, 8, 5)), isFalse);
      expect(task.occursOn(DateTime(2026, 8, 6)), isFalse);
    });

    test('havuz bayrağı rutinin tekrarlarını da susturur', () {
      // Rutin havuza *atılmıyor* (bkz. K2) ama kapı yine de tek: bayrak bir
      // şekilde açılırsa tekrarlar da çıkmamalı.
      final routine = Task(
        title: 'Koşu',
        color: const Color(0xFF34E39B),
        date: DateTime(2026, 8, 3),
        repeat: const Repeat(RepeatType.daily),
        inPool: true,
      );
      expect(routine.occursOn(DateTime(2026, 8, 9)), isFalse);
    });

    test('havuzdayken tarih korunur — "geri koy" ona yaslanıyor', () {
      final task = todo(inPool: true);
      expect(task.date, DateTime(2026, 8, 5));
      expect(task.startHour, 10);
    });

    test('JSON gidiş-dönüşü bayrağı taşır', () {
      expect(Task.fromJson(todo(inPool: true).toJson()).inPool, isTrue);
      expect(Task.fromJson(todo().toJson()).inPool, isFalse);
    });

    test('havuz öncesi kayıt takvimde kalmaya devam eder', () {
      final old = todo().toJson()..remove('inPool');
      expect(Task.fromJson(old).inPool, isFalse);
    });

    test('kopya havuzda doğmaz, takvime iner', () {
      final copy = todo(inPool: true).duplicateTo(DateTime(2026, 8, 9));
      expect(copy.inPool, isFalse);
      expect(copy.occursOn(DateTime(2026, 8, 9)), isTrue);
    });

    test('copy() bayrağı olduğu gibi taşır', () {
      expect(todo(inPool: true).copy().inPool, isTrue);
    });
  });

  group('store', () {
    test('havuza atmak işi takvimden çeker, silmez', () {
      final store = AppStore();
      final task = todo();
      store.addTask(task);

      store.moveToPool(task);

      expect(task.inPool, isTrue);
      expect(store.tasks, hasLength(1), reason: 'iş silinmemeli');
      expect(store.tasksForDate(DateTime(2026, 8, 5)), isEmpty);
      expect(TaskRepository.hasTasksOn(DateTime(2026, 8, 5)), isFalse);
    });

    test('geri koymak işi eski gününe döndürür', () {
      final store = AppStore();
      final task = todo();
      store.addTask(task);
      store.moveToPool(task);

      store.pullFromPool(task);

      expect(task.inPool, isFalse);
      expect(task.date, DateTime(2026, 8, 5));
      expect(store.tasksForDate(DateTime(2026, 8, 5)), hasLength(1));
    });

    test('başka bir güne ve saate de geri konabilir', () {
      final store = AppStore();
      final task = todo();
      store.addTask(task);
      store.moveToPool(task);

      store.pullFromPool(task, toDay: DateTime(2026, 8, 12), startHour: 15);

      expect(task.date, DateTime(2026, 8, 12));
      expect(task.startHour, 15);
      expect(store.tasksForDate(DateTime(2026, 8, 12)), hasLength(1));
      expect(store.tasksForDate(DateTime(2026, 8, 5)), isEmpty);
    });

    test('rutin havuza atılmaz', () {
      final store = AppStore();
      final routine = Task(
        title: 'Koşu',
        color: const Color(0xFF34E39B),
        date: DateTime(2026, 8, 3),
        repeat: const Repeat(RepeatType.daily),
      );
      store.addTask(routine);

      // Debug'ta assert atar; asıl korunan şey veri: bayrak açılmamalı.
      expect(() => store.moveToPool(routine), throwsAssertionError);
      expect(routine.inPool, isFalse);
      expect(store.tasksForDate(DateTime(2026, 8, 9)), hasLength(1));
    });

    test('havuz hareketi senkron kuyruğuna düşer', () async {
      final disk = InMemoryStore();
      await disk.init();
      final outbox = Outbox(disk);

      final store = AppStore();
      await store.attachPersistence(disk, outbox: outbox);
      final task = todo();
      store.addTask(task);
      store.moveToPool(task);
      await store.flush();

      // Ekleme + havuza atma aynı kayda daraltılır; taşınan hâl son hâl olmalı.
      final pending = outbox.pending.where((m) => m.entityId == task.id);
      expect(pending, hasLength(1));
      expect(pending.single.op, MutationOp.upsert);
      expect(pending.single.payload['inPool'], isTrue);
    });

    test('havuzdaki iş diskten havuzda geri gelir', () async {
      final disk = InMemoryStore();
      await disk.init();

      final a = AppStore();
      await a.attachPersistence(disk);
      final task = todo();
      a.addTask(task);
      a.moveToPool(task);
      await a.flush();

      TaskRepository.all.clear();
      final b = AppStore();
      await b.attachPersistence(disk);

      expect(b.tasks.single.inPool, isTrue);
      expect(b.tasksForDate(DateTime(2026, 8, 5)), isEmpty);
    });

    test('havuz listesi en eski bekleyeni önce verir', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(appStoreProvider);

      final older = todo()..title = 'Eski';
      final newer = todo()..title = 'Yeni';
      store.addTask(older);
      store.addTask(newer);

      store.moveToPool(older);
      // `updatedAt` milisaniye hassasiyetinde; iki hareket aynı ana düşmesin.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      store.moveToPool(newer);

      expect(container.read(poolProvider).map((t) => t.title), [
        'Eski',
        'Yeni',
      ]);
    });
  });

  group('görünümler', () {
    // Planın §7'deki riski: bayrak bir yerde unutulur, iş hem havuzda hem
    // takvimde görünür. Bu grup takvim ekranlarını tek tek geziyor.
    testWidgets('havuzdaki iş hiçbir takvim görünümünde çıkmaz', (
      tester,
    ) async {
      useScreenSize(tester, const Size(1400, 1000));
      final day = DateTime.now();

      Task pooled() => Task(
        title: 'Kenardaki',
        color: const Color(0xFF38BDF8),
        date: day,
        startHour: 10,
        inPool: true,
      );

      for (final screen in <Widget>[
        const WeekViewScreen(),
        const MonthlyViewScreen(),
        DayViewScreen(date: day),
      ]) {
        TaskRepository.all.clear();
        await pumpApp(tester, screen, seed: (s) => s.addTask(pooled()));

        expect(
          find.text('Kenardaki'),
          findsNothing,
          reason: '${screen.runtimeType} havuzdaki işi göstermemeli',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Yapılacaklar listesi havuzdakini saklamaz', (tester) async {
      // Havuz "takvimden çekildi" demek, "yok oldu" değil. Panel (Ö1b) henüz
      // yokken bu liste, havuza atılan işin tek görünür izi.
      useScreenSize(tester, const Size(1400, 1000));

      await pumpApp(
        tester,
        const TodosScreen(),
        seed: (s) => s.addTask(todo(inPool: true)),
      );

      expect(find.text('Fatura öde'), findsOneWidget);
    });
  });
}
