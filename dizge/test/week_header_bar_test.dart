import 'package:dizge/core/grid_density_controller.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/data/persistence_providers.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/screens/week_view_screen.dart';
import 'package:dizge/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUp(TaskRepository.all.clear);

  group('yoğunluk tercihi', () {
    ProviderContainer containerWith(LocalStore store) {
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('kayıt yoksa ortadaki kademeyle başlar', () {
      final container = containerWith(InMemoryStore());
      expect(container.read(gridDensityProvider), GridDensity.cozy);
    });

    test('seçim depoya yazılır ve sonraki açılışta geri okunur', () async {
      final store = InMemoryStore();

      final first = containerWith(store);
      await first.read(gridDensityProvider.notifier).set(GridDensity.spacious);
      expect(store.readString(kGridDensityKey), 'spacious');

      // Yeni oturum: aynı depodan okuyan ikinci bir container.
      final second = containerWith(store);
      expect(second.read(gridDensityProvider), GridDensity.spacious);
    });

    test('bozuk kayıt ortadaki kademeye düşer, patlamaz', () async {
      final store = InMemoryStore();
      await store.writeString(kGridDensityKey, 'devasa');

      expect(containerWith(store).read(gridDensityProvider), GridDensity.cozy);
    });

    test('diske enum adı yazılır, index değil', () async {
      // Index yazılsaydı enum'a ileride yeni bir kademe eklendiğinde
      // kullanıcının tercihi sessizce başka bir yoğunluğa dönüşürdü.
      final store = InMemoryStore();
      await containerWith(
        store,
      ).read(gridDensityProvider.notifier).set(GridDensity.compact);

      expect(store.readString(kGridDensityKey), 'compact');
      expect(store.readString(kGridDensityKey), isNot('0'));
    });
  });

  group('başlık çubuğu', () {
    testWidgets('yoğunluk seçimi ızgarayı değiştirir ve diske iner', (
      tester,
    ) async {
      useScreenSize(tester, const Size(1400, 1000));
      final store = InMemoryStore();

      await pumpApp(
        tester,
        const WeekViewScreen(),
        overrides: [localStoreProvider.overrideWithValue(store)],
      );

      // Açılışta "Normal" görünür — seçicinin mevcut kademeyi göstermesi
      // döngüsel düğmeye göre asıl kazanç.
      expect(find.text('Normal'), findsOneWidget);

      await tester.tap(find.text('Normal'));
      await tester.pumpAndSettle();

      // Üç seçenek birden açılır; kullanıcı kaç tık kaldığını tahmin etmez.
      expect(find.text('Sıkışık'), findsOneWidget);
      expect(find.text('Geniş'), findsOneWidget);

      await tester.tap(find.text('Geniş'));
      await tester.pumpAndSettle();

      expect(store.readString(kGridDensityKey), 'spacious');
      expect(find.text('Geniş'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Bugün" yalnız başka bir haftadayken görünür', (tester) async {
      useScreenSize(tester, const Size(1400, 1000));

      await pumpApp(tester, const WeekViewScreen());
      expect(find.text('Bugün'), findsNothing);

      await tester.tap(find.byTooltip('Önceki hafta'));
      await tester.pumpAndSettle();
      expect(find.text('Bugün'), findsOneWidget);

      await tester.tap(find.text('Bugün'));
      await tester.pumpAndSettle();
      expect(find.text('Bugün'), findsNothing);
    });

    testWidgets('telefon genişliğinde yazılar düşer, eylemler kalır', (
      tester,
    ) async {
      useScreenSize(tester, const Size(390, 844));

      await pumpApp(tester, const WeekViewScreen());

      // 390px'te beş öğe yan yana sığmıyor; sığdırmaya çalışmak yerine
      // ikincil etiketler ikona iniyor. Eylemlerin kendisi kaybolmuyor.
      expect(find.text('Normal'), findsNothing);
      expect(find.text('Yeni'), findsNothing);
      expect(find.byTooltip('Izgara yoğunluğu'), findsOneWidget);
      expect(find.byTooltip('Önceki hafta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
