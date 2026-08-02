import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'bootstrap.dart';
import 'core/theme_mode_controller.dart';
import 'screens/app_shell.dart';
import 'theme.dart';
import 'theme/shad_bridge.dart';

Future<void> main() async {
  // Depo, telemetri ve senkron kurulur; hazır bir ProviderContainer döner.
  // Böylece uygulamanın ilk karesi kayıtlı verisiyle birlikte çizilir.
  final container = await bootstrap();

  runApp(
    // ProviderScope: tüm Riverpod state'inin kökü. Ekranlar buradan store'a
    // erişir. Container önceden kurulduğu için `UncontrolledProviderScope`.
    UncontrolledProviderScope(
      container: container,
      child: const AppLifecycleFlusher(child: SchedulerApp()),
    ),
  );
}

class SchedulerApp extends ConsumerWidget {
  const SchedulerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    // ShadApp.custom yalnızca `ShadTheme`'i ağaca koyar; yönlendirme,
    // yerelleştirme ve Material bileşenleri altındaki MaterialApp'e bırakır.
    // Uygulama tarih seçici / bottom sheet gibi Material widget'larına bağlı
    // olduğu için ShadApp'in kendi (shadcn-only) kipi kullanılmıyor.
    return ShadApp.custom(
      theme: shadThemeFrom(AppPalette.light),
      darkTheme: shadThemeFrom(AppPalette.dark),
      themeMode: mode,
      appBuilder: (context) => _materialApp(mode),
    );
  }

  Widget _materialApp(ThemeMode mode) {
    return MaterialApp(
      title: 'Program & Takvim',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(brightness: Brightness.light),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      themeMode: mode,
      // Uygulama tamamen Türkçe; sistem dili ne olursa olsun tarih/saat
      // seçicileri de Türkçe açılsın diye yerel sabitlenir.
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Sistem çubukları temayı izler. `builder` içinde okunuyor çünkü
        // MaterialApp'in teması ancak burada bağlamda hazır.
        final palette = context.colors;
        final barIcons =
            palette.isDark ? Brightness.light : Brightness.dark;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: barIcons,
            statusBarBrightness: palette.brightness,
            systemNavigationBarColor: palette.sidebar,
            systemNavigationBarIconBrightness: barIcons,
          ),
          // Aşırı büyük yazı tipi ölçeği takvim ızgarasını okunmaz hâle
          // getiriyor; erişilebilirlikten tamamen vazgeçmeden makul bir tavan.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const AppShell(),
    );
  }
}
