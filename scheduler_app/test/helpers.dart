import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/auth_service.dart';
import 'package:scheduler_app/data/app_store.dart';
import 'package:scheduler_app/theme.dart';
import 'package:scheduler_app/theme/shad_bridge.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Testlerin kök widget'ı — `SchedulerApp`'in ağaç yapısını birebir yansıtır.
///
/// Ayrı bir yardımcı olarak duruyor çünkü test doğrudan `MaterialApp` kurarsa
/// `ShadTheme` ağaca hiç girmez: Shad bileşeni kullanan her ekran testte
/// "No ShadTheme widget ancestor found" ile patlar, üstelik gerçek uygulamada
/// sorun yokken. Kökü tek yerde tanımlayıp buradan kullanmak bu ayrışmayı
/// baştan engelliyor.
Widget testApp({
  required Widget home,
  Brightness brightness = Brightness.dark,
}) {
  final palette = brightness == Brightness.light
      ? AppPalette.light
      : AppPalette.dark;

  return ShadApp.custom(
    theme: shadThemeFrom(AppPalette.light),
    darkTheme: shadThemeFrom(AppPalette.dark),
    themeMode: brightness == Brightness.light
        ? ThemeMode.light
        : ThemeMode.dark,
    appBuilder: (context) => MaterialApp(
      theme: buildAppTheme(brightness: palette.brightness),
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Uygulamadaki `builder` ile aynı: `ShadApp.custom` toaster'ı kendisi
      // sarmıyor, geri alma bildirimleri buraya iniyor. Testte de olmalı ki
      // "geri al" akışı gerçek ağaçtaki gibi koşsun.
      builder: (context, child) =>
          ShadSonner(child: child ?? const SizedBox.shrink()),
      home: home,
    ),
  );
}

/// Testlerin ortak kabuğu.
///
/// Ekranlar artık Riverpod'a bağlı olduğu için her widget testi bir
/// [ProviderScope] içinde koşmalı. Provider'lar override edilmediği için:
///   * telemetri no-op (test ağa çıkmaz),
///   * depolama bellekte (test diske yazmaz),
///   * senkron motoru yok (test zamanlayıcı bırakmaz).
///
/// [seed] verilirse ağaç çizilmeden önce store'a veri konur.
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  Widget home, {
  void Function(AppStore store)? seed,
  List<Override> overrides = const [],
  Brightness brightness = Brightness.dark,
}) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);

  seed?.call(container.read(appStoreProvider));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testApp(home: home, brightness: brightness),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Ekran boyutunu sabitler (duyarlı düzen testleri için).
void useScreenSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Bellekte çalışan oturum servisi. Ağ yok, gerçek Supabase yok.
class FakeAuthService implements AuthService {
  FakeAuthService({AuthUser? user, this.canAuthenticate = true}) : _user = user;

  /// Anahtarsız derlemeyi taklit etmek için `false` verilir: kapı o zaman
  /// açık kalmalı (G2).
  @override
  final bool canAuthenticate;

  AuthUser? _user;
  final _controller = StreamController<AuthUser?>.broadcast();

  /// Bir sonraki çağrının fırlatacağı hata (hata yollarını sınamak için).
  AuthFailure? nextFailure;

  int signOutCount = 0;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get changes => _controller.stream;

  void _emit(AuthUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    final failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      throw failure;
    }
    _emit(AuthUser(id: 'kullanici-1', email: email));
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    final failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      throw failure;
    }
    _emit(AuthUser(id: 'kullanici-1', email: email));
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    _emit(null);
  }

  void dispose() => _controller.close();
}
