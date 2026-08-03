import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/theme_mode_controller.dart';
import 'package:scheduler_app/data/local_store.dart';
import 'package:scheduler_app/data/persistence_providers.dart';
import 'package:scheduler_app/main.dart';
import 'package:scheduler_app/models/task.dart' show kTaskColors;
import 'package:scheduler_app/screens/app_shell.dart';
import 'package:scheduler_app/screens/week_view_screen.dart';
import 'package:scheduler_app/theme.dart';
import 'package:scheduler_app/theme/shad_bridge.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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

    for (final (themeName, p) in [
      ('açık tema', AppPalette.light),
      ('koyu tema', AppPalette.dark),
    ]) {
      test('$themeName: her kategori rengi blok içinde okunur kalır', () {
        // Tek tek renk seçmek yerine paletin tamamı taranıyor: kurala uymayan
        // bir renk ileride eklenirse test onu yakalar, gözden kaçmaz.
        for (final color in kTaskColors) {
          final style = p.event(color);
          expect(
            contrastRatio(style.ink, style.fill),
            greaterThanOrEqualTo(4.5),
            reason: '$themeName ${color.toARGB32().toRadixString(16)} okunmuyor',
          );
        }
      });

      test('$themeName: gövde sakin, renk kimliği şeritte', () {
        for (final color in kTaskColors) {
          final style = p.event(color);

          // Şerit ham kategori rengi — bloğu bir bakışta o tanıtıyor.
          expect(style.stripe, color);

          // Gövde ise yaprağa yakın durur. Dolu renk olsaydı yan yana altı
          // blok ızgarayı okunmaz bir renk cümbüşüne çevirirdi.
          expect(
            contrastRatio(style.fill, p.surface),
            lessThan(1.9),
            reason: '$themeName ${color.toARGB32().toRadixString(16)} '
                'gövdesi fazla doygun',
          );
        }
      });
    }

    test('tamamlanan blok soluklaşır ve ikincil yazıya döner', () {
      const color = Color(0xFF4FC3F7);
      final open = AppPalette.light.event(color);
      final done = AppPalette.light.event(color, done: true);

      expect(done.fill, isNot(open.fill));
      expect(done.ink, AppPalette.light.inkDim);

      // Tamamlanan blok geri çekilir: zemini de şeridi de açık hâlinden soluk.
      expect(
        contrastRatio(done.fill, AppPalette.light.surface),
        lessThan(contrastRatio(open.fill, AppPalette.light.surface)),
      );
      expect(
        contrastRatio(done.stripe, AppPalette.light.surface),
        lessThan(contrastRatio(open.stripe, AppPalette.light.surface)),
      );
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
          child: testApp(home: const AppShell(), brightness: Brightness.light),
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
          child: testApp(home: const AppShell(), brightness: Brightness.light),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Koyu'));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });

  group('shadcn köprüsü', () {
    test('şema paletten türer, ikinci bir renk listesi tutulmaz', () {
      final light = shadThemeFrom(AppPalette.light).colorScheme;
      final dark = shadThemeFrom(AppPalette.dark).colorScheme;

      expect(light.background, AppPalette.light.bg);
      expect(light.primary, AppPalette.light.accent);
      expect(light.primaryForeground, AppPalette.light.onAccent);
      expect(light.border, AppPalette.light.line);
      expect(dark.background, AppPalette.dark.bg);
      expect(dark.primary, AppPalette.dark.accent);
    });

    test('parlaklık palete bağlı kalır', () {
      expect(shadThemeFrom(AppPalette.light).brightness, Brightness.light);
      expect(shadThemeFrom(AppPalette.dark).brightness, Brightness.dark);
    });

    testWidgets('ShadTheme ekranların içinden okunabilir', (tester) async {
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

      // Asıl mesele bu: Shad bileşenleri ağacın derinliğinde, AppShell'in
      // altında da temayı bulabilmeli.
      final shad = ShadTheme.of(tester.element(find.byType(AppShell)));
      expect(shad.colorScheme.primary, AppPalette.light.accent);

      // Tema anahtarı her iki sistemi birden çevirir.
      await container.read(themeModeProvider.notifier).set(ThemeMode.dark);
      await tester.pumpAndSettle();

      final swapped = ShadTheme.of(tester.element(find.byType(AppShell)));
      expect(swapped.colorScheme.primary, AppPalette.dark.accent);
      expect(tester.element(find.byType(AppShell)).colors, AppPalette.dark);
    });
  });

  group('tipografi', () {
    test('gövde yazı tipi paketlenmiş aileden gelir', () {
      final theme = buildAppTheme(brightness: Brightness.light);

      expect(theme.textTheme.bodyMedium?.fontFamily, kFontFamily);
      // Paketlenmiş font kendisi zaten listede olduğu için yedeklerin başına
      // tekrar yazılması gereksiz olurdu; yedek yığını yalnız sistem aileleri.
      expect(kFontFallback, isNot(contains(kFontFamily)));
    });

    test('Shad bileşenleri ızgarayla aynı yazı tipini kullanır', () {
      // İki farklı yazı tipinin yan yana durması, D1'in engellemek için
      // var olduğu tek şey.
      final shad = shadThemeFrom(AppPalette.light).textTheme;

      expect(shad.family, kFontFamily);
      expect(shad.p.fontFamily, kFontFamily);
      expect(shad.small.fontFamilyFallback, kFontFallback);
    });

    test('pubspec her ağırlığı gerçek bir dosyayla bildirir', () {
      // Bu testin varlık sebebi: font dosyası silinse ya da bir ağırlık
      // bildirilmeden kalsa Flutter sessizce yedeğe düşer — ekran görüntüsü
      // bakılmadan fark edilmez.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final block = pubspec.split('- family: $kFontFamily')[1].split('- family:')[0];

      for (final weight in [400, 500, 600, 700]) {
        expect(block, contains('weight: $weight'),
            reason: '$weight ağırlığı pubspec\'te bildirilmemiş');
      }

      for (final file in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        final path = 'assets/fonts/$kFontFamily-$file.ttf';
        expect(block, contains(path));
        expect(File(path).existsSync(), isTrue, reason: '$path yok');
      }
    });
  });
}
