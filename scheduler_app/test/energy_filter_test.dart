import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/energy_filter_controller.dart';
import 'package:scheduler_app/core/time_grid.dart';
import 'package:scheduler_app/data/local_store.dart';
import 'package:scheduler_app/data/persistence_providers.dart';
import 'package:scheduler_app/models/node.dart';
import 'package:scheduler_app/models/task.dart';
import 'package:scheduler_app/screens/week_view_screen.dart';
import 'package:scheduler_app/widgets/week_time_grid.dart';

import 'helpers.dart';

/// Ö4b — "Bugün enerjim" filtresi.
void main() {
  setUp(TaskRepository.all.clear);

  group('eleme kuralı', () {
    Task withEnergy(Energy? energy) => Task(
      title: 'iş',
      color: const Color(0xFF4FC3F7),
      date: DateTime(2026, 8, 4),
      energy: energy,
    );

    test('filtre kapalıyken hiçbir iş elenmez', () {
      for (final level in [null, ...Energy.values]) {
        expect(withEnergy(level).exceedsEnergy(null), isFalse);
      }
    });

    test('eforu belirtilmemiş iş hiçbir filtrede elenmez', () {
      for (final limit in Energy.values) {
        expect(
          withEnergy(null).exceedsEnergy(limit),
          isFalse,
          reason: 'filtre bir öneri, sansür değil',
        );
      }
    });

    test('enerjinin üstündeki efor elenir, altındaki ve eşiti kalır', () {
      expect(withEnergy(Energy.high).exceedsEnergy(Energy.low), isTrue);
      expect(withEnergy(Energy.medium).exceedsEnergy(Energy.low), isTrue);
      expect(withEnergy(Energy.low).exceedsEnergy(Energy.low), isFalse);
      expect(withEnergy(Energy.discharge).exceedsEnergy(Energy.low), isFalse);

      // En yüksek enerjide hiçbir şey elenmez.
      for (final level in Energy.values) {
        expect(withEnergy(level).exceedsEnergy(Energy.high), isFalse);
      }
    });

    test('kademe sırası azalan efor; karşılaştırma buna yaslanıyor', () {
      expect(Energy.values, [
        Energy.high,
        Energy.medium,
        Energy.low,
        Energy.discharge,
      ]);
    });
  });

  group('tercih', () {
    ProviderContainer containerWith(LocalStore store) {
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('kayıt yoksa filtre kapalı başlar', () {
      expect(containerWith(InMemoryStore()).read(energyFilterProvider), isNull);
    });

    test('seçim aynı gün içinde kalıcı', () async {
      final store = InMemoryStore();

      final first = containerWith(store);
      await first.read(energyFilterProvider.notifier).set(Energy.low);

      // Yeni oturum: aynı depodan okuyan ikinci bir container.
      expect(containerWith(store).read(energyFilterProvider), Energy.low);
    });

    test('dünden kalan seçim bugüne taşınmaz', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final raw = '${dateToKey(yesterday)}|discharge';

      // Aynı kayıt kendi gününde okunuyor…
      expect(
        EnergyFilterController.decodeForTest(raw, yesterday),
        Energy.discharge,
      );
      // …ertesi gün kendiliğinden düşüyor. Aksi hâlde dün akşam "deşarj"
      // diyen biri sabah yarısı solmuş bir takvimle karşılaşırdı.
      expect(EnergyFilterController.decodeForTest(raw, DateTime.now()), isNull);
    });

    test('bozuk kayıt filtreyi açık bırakmaz', () {
      final today = DateTime.now();
      for (final raw in [null, '', 'saçma', '${dateToKey(today)}|kozmik']) {
        expect(EnergyFilterController.decodeForTest(raw, today), isNull);
      }
    });

    test('temizlemek diskteki kaydı da düşürür', () async {
      final store = InMemoryStore();
      final container = containerWith(store);

      await container.read(energyFilterProvider.notifier).set(Energy.medium);
      await container.read(energyFilterProvider.notifier).set(null);

      expect(container.read(energyFilterProvider), isNull);
      expect(containerWith(store).read(energyFilterProvider), isNull);
    });
  });

  group('ızgara', () {
    /// Açılışta ekranda olan bir saat: ızgara "şimdi"nin bir saat öncesini
    /// ortalıyor, bu yüzden şu anki saate konan blok görünür oluyor.
    double visibleHour() => hourOfDay(DateTime.now()).floorToDouble();

    Task at(String title, Energy? energy) => Task(
      title: title,
      color: const Color(0xFF4FC3F7),
      date: DateTime.now(),
      startHour: visibleHour(),
      durationHours: 1,
      energy: energy,
    );

    double opacityOf(WidgetTester tester, String title) {
      final block = find.bySemanticsLabel(RegExp('^$title,'));
      expect(block, findsOneWidget, reason: '"$title" ızgarada görünmeli');
      return tester
          .widget<Opacity>(
            find.ancestor(of: block, matching: find.byType(Opacity)).first,
          )
          .opacity;
    }

    testWidgets('seçilen enerjinin üstündeki iş soluklaşır ama kaybolmaz', (
      tester,
    ) async {
      useScreenSize(tester, const Size(1400, 1000));
      final store = InMemoryStore();

      await pumpApp(
        tester,
        const WeekViewScreen(),
        overrides: [localStoreProvider.overrideWithValue(store)],
        seed: (s) {
          s.addTask(at('Tez', Energy.high));
          s.addTask(at('Bulasik', Energy.low));
          s.addTask(at('Serbest', null));
        },
      );

      // Filtre kapalıyken hepsi tam görünür.
      expect(opacityOf(tester, 'Tez'), 1);

      await tester.tap(find.text('Tüm işler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Düşük efor'));
      await tester.pumpAndSettle();

      // Soluklaşan blok hâlâ ağaçta: gizlemek işi unutturur, soluklaştırmak
      // "bugün olmasa da olur" der.
      expect(opacityOf(tester, 'Tez'), lessThan(1));
      expect(opacityOf(tester, 'Bulasik'), 1);
      expect(
        opacityOf(tester, 'Serbest'),
        1,
        reason: 'efor belirtilmemiş iş elenmemeli',
      );

      // Tercih diske indi ve ızgaraya ulaştı.
      expect(store.readString(kEnergyFilterKey), contains('low'));
      expect(
        tester.widget<WeekTimeGrid>(find.byType(WeekTimeGrid)).energyLimit,
        Energy.low,
      );
    });

    testWidgets('ekran okuyucu solgunluğun sebebini duyar', (tester) async {
      useScreenSize(tester, const Size(1400, 1000));

      await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (s) => s.addTask(at('Tez', Energy.high)),
      );

      await tester.tap(find.text('Tüm işler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deşarj'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp('bugünkü enerjinin üstünde')),
        findsOneWidget,
      );
    });

    testWidgets('filtre kapatılınca solgunluk kalkar', (tester) async {
      useScreenSize(tester, const Size(1400, 1000));

      await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (s) => s.addTask(at('Tez', Energy.high)),
      );

      await tester.tap(find.text('Tüm işler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deşarj'));
      await tester.pumpAndSettle();
      expect(opacityOf(tester, 'Tez'), lessThan(1));

      await tester.tap(find.text('Deşarj'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tüm işler').last);
      await tester.pumpAndSettle();

      expect(opacityOf(tester, 'Tez'), 1);
    });
  });
}
