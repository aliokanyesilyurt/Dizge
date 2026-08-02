import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/theme_mode_controller.dart';
import 'package:scheduler_app/data/local_store.dart';
import 'package:scheduler_app/data/persistence_providers.dart';
import 'package:scheduler_app/main.dart';
import 'package:scheduler_app/screens/app_shell.dart';
import 'package:scheduler_app/screens/week_view_screen.dart';
import 'package:scheduler_app/theme.dart';

import 'helpers.dart';

void main() {
  group('palet', () {
    test('tema, parlaklığına uygun paleti uzantı olarak taşır', () {
      final light = buildAppTheme(brightness: Brightness.light);
      final dark = buildAppTheme(brightness: Brightness.dark);

      expect(light.extension<AppPalette>(), AppPalette.light);
      expect(dark.extension<AppPalette>(), AppPalette.dark);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
    });

    test('varsayılan koyu kalır (eski çağrılar ve testler bozulmasın)', () {
      expect(buildAppTheme().brightness, Brightness.dark);
    });

    testWidgets('context.colors çalışan temanın paletini verir',
        (tester) async {
      late AppPalette seen;

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: Builder(builder: (context) {
          seen = context.colors;
          return const SizedBox();
        }),
      ));

      expect(seen, AppPalette.light);
      expect(seen.isDark, isFalse);
    });

    testWidgets('palet uzantısı olmayan temada parlaklığa göre düşer',
        (tester) async {
      late AppPalette seen;

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(builder: (context) {
          seen = context.colors;
          return const SizedBox();
        }),
      ));

      expect(seen, AppPalette.dark);
    });

    test('etkinlik bloğunun yazısı zemine göre kontrast seçer', () {
      // Açık sarı üstünde beyaz yazı okunmaz; koyu mürekkep gelmeli.
      final onYellow = AppPalette.light.event(const Color(0xFFFFF176)).ink;
      final onIndigo = AppPalette.light.event(const Color(0xFF3F51B5)).ink;

      expect(onYellow.computeLuminance(), lessThan(0.2));
      expect(onIndigo.computeLuminance(), greaterThan(0.8));
    });

    test('tamamlanan blok soluklaşır ve ikincil yazıya döner', () {
      const color = Color(0xFF4FC3F7);
      final open = AppPalette.light.event(color);
      final done = AppPalette.light.event(color, done: true);

      expect(done.fill, isNot(open.fill));
      expect(done.ink, AppPalette.light.inkDim);
    });
  });

  group('tema kipi', () {
    ProviderContainer containerWith(LocalStore store) {
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('kayıt yoksa sistem tercihiyle başlar', () {
      final container = containerWith(InMemoryStore());
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('seçim depoya yazılır ve sonraki açılışta geri okunur', () async {
      final store = InMemoryStore();

      final first = containerWith(store);
      await first.read(themeModeProvider.notifier).set(ThemeMode.light);
      expect(store.readString(kThemeModeKey), 'light');

      // Yeni oturum: aynı depodan okuyan ikinci bir container.
      final second = containerWith(store);
      expect(second.read(themeModeProvider), ThemeMode.light);
    });

    test('anahtar, görünen temanın tersine geçer', () async {
      final container = containerWith(InMemoryStore());
      final controller = container.read(themeModeProvider.notifier);

      // "Sistem" iken kullanıcı ekranda ne görüyorsa onun tersini bekler.
      await controller.toggle(Brightness.dark);
      expect(container.read(themeModeProvider), ThemeMode.light);

      await controller.toggle(Brightness.dark);
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('bozuk kayıt sisteme düşer, patlamaz', () async {
      final store = InMemoryStore();
      await store.writeString(kThemeModeKey, 'mavi');

      final container = containerWith(store);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });
  });

  group('uygulama kabuğu', () {
    testWidgets('kök widget seçilen kipi gerçekten uygular', (tester) async {
      useScreenSize(tester, const Size(1400, 1000));

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(themeModeProvider.notifier).set(ThemeMode.light);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SchedulerApp(),
        ),
      );
      await tester.pumpAndSettle();

      // MaterialApp.builder içindeki bağlam gerçekten açık paleti görmeli.
      final context = tester.element(find.byType(AppShell));
      expect(context.colors, AppPalette.light);

      await container.read(themeModeProvider.notifier).set(ThemeMode.dark);
      await tester.pumpAndSettle();

      expect(tester.element(find.byType(AppShell)).colors, AppPalette.dark);
    });

    testWidgets('açık temada da hatasız çizilir', (tester) async {
      useScreenSize(tester, const Size(1400, 1000));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(brightness: Brightness.light),
            home: const AppShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Program'), findsOneWidget);
    });

    testWidgets('telefon genişliğinde hafta başlığı taşmaz', (tester) async {
      useScreenSize(tester, const Size(390, 844));

      await pumpApp(tester, const WeekViewScreen());

      // Geçmiş bir haftaya geçmek "Bugün" düğmesini de açar; başlık satırının
      // en kalabalık hâli budur.
      await tester.tap(find.byTooltip('Önceki hafta'));
      await tester.pumpAndSettle();

      expect(find.text('Bugün'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('kenar çubuğundaki seçim tema kipini değiştirir',
        (tester) async {
      useScreenSize(tester, const Size(1400, 1000));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(brightness: Brightness.light),
            darkTheme: buildAppTheme(brightness: Brightness.dark),
            themeMode: container.read(themeModeProvider),
            home: const AppShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Koyu'));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });
}
