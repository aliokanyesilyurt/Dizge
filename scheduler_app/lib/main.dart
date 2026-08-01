import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bootstrap.dart';
import 'screens/app_shell.dart';
import 'theme.dart';

Future<void> main() async {
  // Depo, telemetri ve senkron kurulur; hazır bir ProviderContainer döner.
  // Böylece uygulamanın ilk karesi kayıtlı verisiyle birlikte çizilir.
  final container = await bootstrap();

  // Koyu arayüzle uyumlu sistem çubukları (Android'de şeffaf durum çubuğu).
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.sidebar,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(
    // ProviderScope: tüm Riverpod state'inin kökü. Ekranlar buradan store'a
    // erişir. Container önceden kurulduğu için `UncontrolledProviderScope`.
    UncontrolledProviderScope(
      container: container,
      child: const AppLifecycleFlusher(child: SchedulerApp()),
    ),
  );
}

class SchedulerApp extends StatelessWidget {
  const SchedulerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Program & Takvim',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Uygulama tamamen Türkçe; sistem dili ne olursa olsun tarih/saat
      // seçicileri de Türkçe açılsın diye yerel sabitlenir.
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Aşırı büyük yazı tipi ölçeği takvim ızgarasını okunmaz hâle getiriyor;
      // erişilebilirlikten tamamen vazgeçmeden makul bir tavan koyuyoruz.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AppShell(),
    );
  }
}
