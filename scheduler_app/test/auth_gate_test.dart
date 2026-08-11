import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/auth_service.dart';
import 'package:scheduler_app/screens/app_shell.dart';
import 'package:scheduler_app/screens/auth_gate.dart';
import 'package:scheduler_app/screens/welcome_screen.dart';

import 'helpers.dart';

void main() {
  group('giriş kapısı', () {
    /// Kenar çubuğunun açık olduğu genişlik; dar ekranda kabuk drawer'a
    /// düşüyor ve test "takvim göründü mü" sorusunu daha zor soruyor.
    void useWideScreen(WidgetTester tester) =>
        useScreenSize(tester, const Size(1200, 900));

    testWidgets('oturum yokken takvim değil karşılama ekranı görünür', (
      tester,
    ) async {
      useWideScreen(tester);
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const AuthGate(),
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('oturum açıkken takvim görünür', (tester) async {
      useWideScreen(tester);
      final auth = FakeAuthService(
        user: const AuthUser(id: 'k1', email: 'ali@example.com'),
      );
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const AuthGate(),
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('anahtarsız derlemede kapı açık kalır', (tester) async {
      // G2'nin kaçış valfi. Kimlik doğrulanamayan bir derlemede kapıyı kapalı
      // tutmak, uygulamayı hiç açılamaz hâle getirirdi — `--dart-define`
      // vermeyi unutan her koşum ve bütün test paketi dahil.
      useWideScreen(tester);
      final auth = FakeAuthService(canAuthenticate: false);
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const AuthGate(),
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('oturum okunurken ara kare görünür', (tester) async {
      // Jeton güvenli kasadan geri yüklenirken bir kare "Hoş geldin" gösterip
      // sonra takvime atlamak, her açılışta bir yanıp sönme olurdu.
      useWideScreen(tester);
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      // Hiç yayın yapmayan akış: kapı "yükleniyor" durumunda kilitli kalır.
      // `pumpAndSettle` burada kullanılamaz — ara karedeki dönen gösterge
      // sonsuz animasyon, hiç durulmaz.
      final container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          authUserProvider.overrideWith(
            (ref) =>
                Stream<AuthUser?>.fromFuture(Completer<AuthUser?>().future),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(home: const AuthGate()),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('giriş yapılınca kapı kendiliğinden açılır', (tester) async {
      useWideScreen(tester);
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const AuthGate(),
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );

      expect(find.byType(WelcomeScreen), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'E-posta'),
        'ali@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Parola'),
        'parola123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Giriş yap'));
      await tester.pumpAndSettle();

      // Karşılama ekranı kendini kapatmıyor; kapı oturumu görüp değiştiriyor.
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('çıkış yapılınca kapı kendiliğinden kapanır', (tester) async {
      useWideScreen(tester);
      final auth = FakeAuthService(
        user: const AuthUser(id: 'k1', email: 'ali@example.com'),
      );
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const AuthGate(),
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );
      expect(find.byType(AppShell), findsOneWidget);

      await auth.signOut();
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('hatalı parola karşılama ekranında söylenir', (tester) async {
      useWideScreen(tester);
      final auth = FakeAuthService()
        ..nextFailure = const AuthFailure('E-posta veya parola hatalı.');
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const AuthGate(),
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'E-posta'),
        'ali@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Parola'),
        'yanlisparola',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Giriş yap'));
      await tester.pumpAndSettle();

      expect(find.text('E-posta veya parola hatalı.'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });
  });

  group('parola kurtarma', () {
    void useWideScreen(WidgetTester tester) =>
        useScreenSize(tester, const Size(1200, 900));

    /// Karşılama ekranını kurtarma adımına kadar getirir.
    Future<void> requestCode(WidgetTester tester, FakeAuthService auth) async {
      await pumpApp(
        tester,
        const AuthGate(),
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );

      await tester.tap(find.text('Parolamı unuttum'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'E-posta'),
        'ali@example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Kod gönder'));
      await tester.pumpAndSettle();
    }

    testWidgets('kod istemek kullanıcıyı kod adımına getirir', (tester) async {
      useWideScreen(tester);
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await requestCode(tester, auth);

      expect(auth.recoveryCodesSentTo, ['ali@example.com']);
      expect(find.widgetWithText(TextField, '6 haneli kod'), findsOneWidget);
      // Kapı hâlâ kapalı: kod istemek girmek değil.
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('doğru kod kapıyı açar', (tester) async {
      // Sert kapıda kurtarma yolu olmasaydı unutulan parola, veriye kalıcı
      // olarak erişilememesi demekti.
      useWideScreen(tester);
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await requestCode(tester, auth);

      await tester.enterText(
        find.widgetWithText(TextField, '6 haneli kod'),
        '123456',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Doğrula ve gir'));
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('yanlış kod söylenir ve kapı kapalı kalır', (tester) async {
      useWideScreen(tester);
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await requestCode(tester, auth);

      await tester.enterText(
        find.widgetWithText(TextField, '6 haneli kod'),
        '000000',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Doğrula ve gir'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Kod geçersiz'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('girişe dönmek kurtarmayı iptal eder', (tester) async {
      useWideScreen(tester);
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await requestCode(tester, auth);
      await tester.tap(find.text('Girişe dön'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Giriş yap'), findsOneWidget);
      expect(find.widgetWithText(TextField, '6 haneli kod'), findsNothing);
    });
  });
}
