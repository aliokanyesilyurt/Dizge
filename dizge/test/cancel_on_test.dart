import 'package:dizge/core/navigation_controller.dart';
import 'package:dizge/data/app_store.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/screens/app_shell.dart';
import 'package:dizge/screens/monthly_view_screen.dart';
import 'package:dizge/screens/pool_screen.dart';
import 'package:dizge/screens/routines_screen.dart';
import 'package:dizge/screens/todos_screen.dart';
import 'package:dizge/widgets/cancel_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// D4 — "Bugün iptal" tek kapıdan geçer, havuzun ikinci bir kapısı var.
///
/// İki bildirilen kusur:
///   * "bir işi tek bir gün içinde iptal etmek istiyorum" — model bunu zaten
///     yapabiliyordu ama **iki ayrı adla**: rutinde "Bugün atla", tek günlük
///     işte "Kenara al". Hangisinin geçerli olduğunu kullanıcının bilmesi
///     bekleniyordu.
///   * "havuzun nerede olduğu belli değil" — havuz boş **ve** panel kapalıysa
///     ekranda sıfır iz bırakıyordu. Hiç kullanmamış biri için hiç yoktu.
///
/// Testlerin ağırlığı etikette ve keşfedilebilirlikte: mekanizmanın kendisi
/// (atlama ve havuz) `day_rescue_test` ile `pool_test` tarafından tutuluyor.
void main() {
  setUp(TaskRepository.all.clear);

  const wide = Size(1400, 1000);
  final today = Task.dayKey(DateTime.now());

  Task once(String title, {DateTime? date}) =>
      Task(title: title, color: Colors.blue, date: date ?? today);

  Task routine(String title, {DateTime? date}) => Task(
    title: title,
    color: Colors.green,
    date: date ?? today,
    startHour: 7,
    repeat: const Repeat(RepeatType.daily),
  );

  // --- Mağaza: tek kapı -----------------------------------------------------

  group('mağaza', () {
    test('tek günlük iş iptal edilince havuza girer', () {
      final store = AppStore();
      final job = once('Rapor');
      store.addTask(job);

      expect(store.isCancelledOn(job, today), isFalse);
      expect(store.cancelOn(job, today), 'Kenara alındı');

      expect(job.inPool, isTrue);
      expect(job.isSkippedOn(today), isFalse, reason: 'atlama rutinin işi');
      expect(store.isCancelledOn(job, today), isTrue);
    });

    test('rutin iptal edilince o günü atlar, havuza girmez', () {
      final store = AppStore();
      final job = routine('Koşu');
      store.addTask(job);

      expect(store.cancelOn(job, today), 'Bugünlük atlandı');

      expect(job.isSkippedOn(today), isTrue);
      expect(job.inPool, isFalse, reason: 'rutin havuza atılamaz (K2)');
      expect(store.isCancelledOn(job, today), isTrue);
    });

    test('iptal yalnız verilen günü kapsar', () {
      final store = AppStore();
      final job = routine(
        'Koşu',
        date: today.subtract(const Duration(days: 9)),
      );
      store.addTask(job);

      store.cancelOn(job, today);

      final yarin = today.add(const Duration(days: 1));
      expect(job.isSkippedOn(yarin), isFalse, reason: 'yarın yine gelmeli');
      expect(store.isCancelledOn(job, yarin), isFalse);
    });

    test('geri alma iki türü de eski hâline döndürür', () {
      final store = AppStore();
      final job = once('Rapor');
      final rut = routine('Koşu');
      store.addTask(job);
      store.addTask(rut);

      store.cancelOn(job, today);
      store.cancelOn(rut, today);
      store.undoCancelOn(job, today);
      store.undoCancelOn(rut, today);

      expect(job.inPool, isFalse);
      expect(rut.isSkippedOn(today), isFalse);
      expect(store.isCancelledOn(job, today), isFalse);
      expect(store.isCancelledOn(rut, today), isFalse);
    });

    test('havuzdan dönen iş iptal edildiği güne konar', () {
      final store = AppStore();
      // İş dünden kalma; iptal bugünden yapılıyor.
      final job = once('Rapor', date: today.subtract(const Duration(days: 1)));
      store.addTask(job);

      store.cancelOn(job, today);
      store.undoCancelOn(job, today);

      expect(job.date, today, reason: 'geri alma, iptal edilen güne döndürür');
    });
  });

  // --- Liste ekranları ------------------------------------------------------

  group('liste satırı', () {
    testWidgets('yapılacaklarda satır eylemi işi kenara alır', (tester) async {
      late Task job;

      final container = await pumpApp(
        tester,
        const TodosScreen(),
        seed: (store) {
          job = once('Rapor yaz');
          store.addTask(job);
        },
      );

      await tester.tap(find.byTooltip('Bugün iptal'));
      await tester.pumpAndSettle();

      expect(job.inPool, isTrue);
      expect(container.read(poolProvider), hasLength(1));
      // Havuza giren iş Yapılacaklar'dan düşmüyor (bkz. todosProvider), yani
      // satır yerinde kalıyor — yalnız eylemi tersine dönüyor.
      expect(find.byTooltip('İptali geri al'), findsOneWidget);
    });

    testWidgets('rutinlerde aynı etiket bugünü atlar', (tester) async {
      late Task job;

      await pumpApp(
        tester,
        const RoutinesScreen(),
        seed: (store) {
          job = routine('Sabah koşusu');
          store.addTask(job);
        },
      );

      // Etiket Yapılacaklar'dakiyle birebir aynı: kullanıcı rutin/tek-günlük
      // ayrımını bilmek zorunda değil (K3).
      await tester.tap(find.byTooltip('Bugün iptal'));
      await tester.pumpAndSettle();

      expect(job.isSkippedOn(today), isTrue);
      expect(job.inPool, isFalse);

      await tester.tap(find.byTooltip('İptali geri al'));
      await tester.pumpAndSettle();
      expect(job.isSkippedOn(today), isFalse);
    });
  });

  // --- Aylık hücre ----------------------------------------------------------

  group('aylık hücre', () {
    testWidgets('uzun basış menüsündeki "Bugün iptal" o günü iptal eder', (
      tester,
    ) async {
      useScreenSize(tester, wide);
      final day = DateTime(2026, 3, 12);
      late Task job;

      final container = await pumpApp(
        tester,
        MonthlyViewScreen(initialMonth: day),
        seed: (store) {
          job = once('Rapor yaz', date: day);
          store.addTask(job);
        },
      );

      // Uzun basış yalnız menüyü açar; kendi başına hiçbir şey değiştirmez.
      await tester.longPress(find.text('Rapor yaz'));
      await tester.pumpAndSettle();
      expect(job.inPool, isFalse);

      await tester.tap(find.text(cancelLabel(false)));
      await tester.pumpAndSettle();

      expect(job.inPool, isTrue);
      expect(container.read(poolProvider), hasLength(1));
      // Kısa dokunuş hâlâ tamamlama: iptal onun yerini almadı.
      expect(job.isDoneOn(day), isFalse);
    });

    testWidgets('atlanan rutin hücrede üstü çizili görünür', (tester) async {
      useScreenSize(tester, wide);
      final day = DateTime(2026, 3, 12);

      await pumpApp(
        tester,
        MonthlyViewScreen(initialMonth: day),
        seed: (store) => store.addTask(
          routine('Koşu', date: DateTime(2026, 3, 1))..setSkipped(day, true),
        ),
      );

      // Günlük rutin ayın her hücresinde duruyor; üstü çizili olan **yalnız**
      // atlanan gün olmalı.
      final rows = tester.widgetList<Text>(find.text('↻ Koşu'));
      expect(
        rows.where((t) => t.style?.decoration == TextDecoration.lineThrough),
        hasLength(1),
      );
    });
  });

  // --- Havuzun ikinci kapısı ------------------------------------------------

  group('kenar çubuğu', () {
    testWidgets('havuz boşken bile satırı duruyor', (tester) async {
      useScreenSize(tester, wide);
      await pumpApp(tester, const AppShell());

      // Haftalık görünüm de paneli içerdiği için birden fazla görünebilir.
      expect(find.text('Kenarda Bekleyenler'), findsWidgets);
    });

    testWidgets('rozet bekleyen iş sayısını söyler', (tester) async {
      useScreenSize(tester, wide);

      await pumpApp(
        tester,
        const AppShell(),
        seed: (store) {
          for (final title in ['Rapor', 'Fatura']) {
            final job = once(title);
            store.addTask(job);
            store.moveToPool(job);
          }
        },
      );

      // Çıplak `find.text('2')` haftalık ızgaradaki saate de takılırdı;
      // aranan sayı kenar çubuğu satırının içindeki.
      expect(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('Kenarda Bekleyenler'),
                matching: find.byType(Row),
              )
              .first,
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('satır havuz ekranını açar, oradan iş takvime döner', (
      tester,
    ) async {
      useScreenSize(tester, wide);
      late Task job;

      final container = await pumpApp(
        tester,
        const AppShell(),
        seed: (store) {
          job = once('Rapor');
          store.addTask(job);
          store.moveToPool(job);
        },
      );

      final poolTile = find.descendant(
        of: find.byType(ListView),
        matching: find.text('Kenarda Bekleyenler'),
      );
      await tester.tap(poolTile.first);
      await tester.pumpAndSettle();

      expect(container.read(navigationProvider).section, AppSection.pool);
      expect(find.byType(PoolScreen), findsOneWidget);
      expect(find.text('Rapor'), findsOneWidget);

      await tester.tap(find.byTooltip('Takvime geri koy'));
      await tester.pumpAndSettle();

      expect(job.inPool, isFalse);
      expect(container.read(poolProvider), isEmpty);
    });

    testWidgets('boş havuz ekranı işin oraya nasıl geldiğini anlatır', (
      tester,
    ) async {
      await pumpApp(tester, const PoolScreen());

      expect(find.textContaining('Bugün iptal'), findsOneWidget);
    });
  });
}
