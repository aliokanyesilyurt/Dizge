import 'package:dizge/core/pool_panel_controller.dart';
import 'package:dizge/core/time_grid.dart';
import 'package:dizge/data/app_store.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/data/persistence_providers.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/screens/week/pool_panel.dart';
import 'package:dizge/screens/week_view_screen.dart';
import 'package:dizge/widgets/week_time_grid.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Ö1b — "Kenarda Bekleyenler" paneli.
void main() {
  setUp(TaskRepository.all.clear);

  /// Izgaranın açılışta gösterdiği saat; blok görünür olsun diye.
  double visibleHour() => hourOfDay(DateTime.now()).floorToDouble();

  Task task(String title, {bool inPool = false}) => Task(
    title: title,
    color: const Color(0xFF38BDF8),
    date: DateTime.now(),
    startHour: visibleHour(),
    durationHours: 1,
    inPool: inPool,
  );

  /// Panel sütununun sığdığı bir masaüstü penceresi.
  void wide(WidgetTester tester) =>
      useScreenSize(tester, const Size(1400, 1000));

  group('tercih', () {
    ProviderContainer containerWith(LocalStore store) {
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('varsayılan kapalı', () {
      expect(
        containerWith(InMemoryStore()).read(poolPanelOpenProvider),
        isFalse,
      );
    });

    test('açma tercihi sonraki oturumda korunur', () async {
      final store = InMemoryStore();
      await containerWith(store).read(poolPanelOpenProvider.notifier).set(true);

      expect(containerWith(store).read(poolPanelOpenProvider), isTrue);
    });
  });

  group('panel', () {
    testWidgets('havuz boş ve panel kapalıyken ekranda iz bırakmaz', (
      tester,
    ) async {
      wide(tester);
      await pumpApp(tester, const WeekViewScreen());

      expect(find.byType(PoolRail), findsNothing);
      expect(find.byType(PoolPanel), findsNothing);
    });

    testWidgets('havuzda iş varken şerit sayacı gösterir', (tester) async {
      wide(tester);
      await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (s) {
          s.addTask(task('Kenardaki', inPool: true));
          s.addTask(task('Öteki', inPool: true));
        },
      );

      expect(find.byType(PoolRail), findsOneWidget);
      expect(find.byTooltip('Havuz (2)'), findsOneWidget);
    });

    testWidgets('şeride dokunmak paneli açar, tercih diske iner', (
      tester,
    ) async {
      wide(tester);
      final disk = InMemoryStore();

      await pumpApp(
        tester,
        const WeekViewScreen(),
        overrides: [localStoreProvider.overrideWithValue(disk)],
        seed: (s) => s.addTask(task('Kenardaki', inPool: true)),
      );

      await tester.tap(find.byType(PoolRail));
      await tester.pumpAndSettle();

      expect(find.byType(PoolPanel), findsOneWidget);
      expect(find.text('Kenardaki'), findsOneWidget);
      expect(disk.readString(kPoolPanelKey), 'open');

      // Daraltmak şeride geri döner.
      await tester.tap(find.byTooltip('Paneli daralt'));
      await tester.pumpAndSettle();
      expect(find.byType(PoolPanel), findsNothing);
      expect(find.byType(PoolRail), findsOneWidget);
    });

    testWidgets('panelde bekleme süresi yazıyor', (tester) async {
      wide(tester);
      final old = task('Eski', inPool: true)
        ..updatedAt = DateTime.now().subtract(const Duration(days: 3));

      await pumpApp(
        tester,
        const WeekViewScreen(),
        overrides: [
          poolPanelOpenProvider.overrideWith(
            (ref) => PoolPanelController(InMemoryStore())..set(true),
          ),
        ],
        seed: (s) => s.addTask(old),
      );

      expect(find.text('3 gündür bekliyor'), findsOneWidget);
    });
  });

  group('takvimden havuza', () {
    testWidgets('önizlemedeki "Bugün iptal" işi takvimden çeker', (
      tester,
    ) async {
      wide(tester);
      final job = task('Tez');

      final container = await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (s) => s.addTask(job),
      );

      // Bloğa dokun → önizleme açılır.
      await tester.tap(find.text('Tez'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bugün iptal'));
      await tester.pumpAndSettle();

      expect(job.inPool, isTrue);
      expect(container.read(poolProvider), hasLength(1));
      // Takvimden çekildi ama silinmedi.
      expect(container.read(appStoreProvider).tasks, hasLength(1));
      expect(find.byType(PoolRail), findsOneWidget);
    });

    testWidgets('rutinde aynı etiket çıkar ama iş havuza girmez', (
      tester,
    ) async {
      // Plan K3: menüde tek satır. Rutin havuza giremez ("her gün tekrarlayan
      // ama hiçbir gün görünmeyen iş" tanımsız — K2), ama kullanıcı bu ayrımı
      // etiketten öğrenmiyor: aynı düğme, arkada başka mekanizma.
      wide(tester);
      late Task routine;
      final day = Task.dayKey(DateTime.now());

      final container = await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (s) {
          routine = Task(
            title: 'Koşu',
            color: const Color(0xFF34E39B),
            date: day,
            startHour: visibleHour(),
            repeat: const Repeat(RepeatType.daily),
          );
          s.addTask(routine);
        },
      );

      // Günlük rutin haftanın her gününde duruyor; herhangi biri yeter.
      await tester.tap(find.text('Koşu').first);
      await tester.pumpAndSettle();

      expect(find.text('Düzenle'), findsOneWidget, reason: 'önizleme açılmalı');
      expect(find.text('Bugün iptal'), findsOneWidget);

      await tester.tap(find.text('Bugün iptal'));
      await tester.pumpAndSettle();

      // Rutin bugün başlıyor, yani ızgaradaki ilk bloğu bugünün sütununda:
      // atlanan gün de bugün olmalı.
      expect(routine.isSkippedOn(day), isTrue);
      expect(routine.inPool, isFalse, reason: 'rutin havuza girmez');
      expect(container.read(poolProvider), isEmpty);
    });

    testWidgets('iptal geri alınabilir', (tester) async {
      wide(tester);
      final job = task('Tez');

      await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (s) => s.addTask(job),
      );

      await tester.tap(find.text('Tez'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bugün iptal'));
      await tester.pumpAndSettle();
      expect(job.inPool, isTrue);

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();

      expect(job.inPool, isFalse);
      expect(find.text('Tez'), findsWidgets, reason: 'blok ızgaraya dönmeli');
    });
  });

  group('havuzdan takvime', () {
    testWidgets('panelden sürükleyip ızgaraya bırakmak işi takvime koyar', (
      tester,
    ) async {
      wide(tester);
      final job = task('Kenardaki', inPool: true);

      final container = await pumpApp(
        tester,
        const WeekViewScreen(),
        overrides: [
          poolPanelOpenProvider.overrideWith(
            (ref) => PoolPanelController(InMemoryStore())..set(true),
          ),
        ],
        seed: (s) => s.addTask(job),
      );

      final card = find.text('Kenardaki');
      expect(card, findsOneWidget);

      // Panelden ızgaranın ortasına sürükle. Tek sıçramada değil adım adım:
      // sürükleme tanıyıcısı hareketi ancak birkaç olayda ayırt ediyor.
      final from = tester.getCenter(card);
      const to = Offset(300, 750);
      final gesture = await tester.startGesture(from);
      // Kart uzun basmayla kalkıyor (bkz. PoolPanel).
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 6)!);
        await tester.pump(const Duration(milliseconds: 30));
      }
      // Sürükleme gerçekten başladıysa parmağın altında bir kopya var.
      expect(
        find.text('Kenardaki'),
        findsNWidgets(2),
        reason: 'sürükleme başlamalı (kart + geri bildirim)',
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(job.inPool, isFalse, reason: 'iş takvime inmeli');
      expect(container.read(poolProvider), isEmpty);
    });

    testWidgets('boş haftada ızgaranın tam ortasına bırakmak çalışır', (
      tester,
    ) async {
      // Bu test bir yaranın izi. Eskiden boş haftada ızgaranın üstünde yüzen
      // bir "Bu hafta boş" kartı vardı; `RenderStack` vuruşu ön çocukta
      // durdurduğu için tam oraya bırakılan iş alttaki `DragTarget`'a hiç
      // ulaşmıyordu — boş bir haftaya havuzdan ilk işi koymanın en doğal yolu,
      // ekranın tam ortasındaki tek ölü nokta demekti. Kart bir bayrakla
      // yamanmıştı; T2'de kart kalkınca yama da kalktı.
      //
      // Kart gitti ama soru duruyor: ızgaranın ortasına bırakılan iş iniyor
      // mu? İleride oraya başka bir katman konursa bu test haber verir.
      wide(tester);
      final job = task('Kenardaki', inPool: true);

      final container = await pumpApp(
        tester,
        const WeekViewScreen(),
        overrides: [
          poolPanelOpenProvider.overrideWith(
            (ref) => PoolPanelController(InMemoryStore())..set(true),
          ),
        ],
        seed: (s) => s.addTask(job),
      );

      // Hafta gerçekten boş: ızgarada tek blok yok, bilgi başlıkta.
      expect(
        find.textContaining('hiç iş yok', findRichText: true),
        findsOneWidget,
      );

      final from = tester.getCenter(find.text('Kenardaki'));
      final to = tester.getCenter(find.byType(WeekTimeGrid));

      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 6)!);
        await tester.pump(const Duration(milliseconds: 30));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(job.inPool, isFalse, reason: 'kartın üstüne bırakmak da inmeli');
      expect(container.read(poolProvider), isEmpty);
    });

    testWidgets('sağ tık menüsünden geri koymak eski güne döndürür', (
      tester,
    ) async {
      wide(tester);
      final job = task('Kenardaki', inPool: true);
      final originalDay = job.date;

      final container = await pumpApp(
        tester,
        const WeekViewScreen(),
        overrides: [
          poolPanelOpenProvider.overrideWith(
            (ref) => PoolPanelController(InMemoryStore())..set(true),
          ),
        ],
        seed: (s) => s.addTask(job),
      );

      await tester.tap(find.text('Kenardaki'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Takvime geri koy'));
      await tester.pumpAndSettle();

      expect(job.inPool, isFalse);
      expect(job.date, originalDay);
      expect(container.read(poolProvider), isEmpty);
    });
  });
}
