import 'package:dizge/core/auth_service.dart';
import 'package:dizge/core/password_policy.dart';
import 'package:dizge/screens/app_shell.dart';
import 'package:dizge/screens/auth_gate.dart';
import 'package:dizge/screens/password_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// P1–P4 — parola kuralı, kayıt doğrulaması, parola değiştirme.
/// Kural satırı işaretli mi — satırın `Semantics.checked` değeri.
bool? ruleChecked(WidgetTester tester, String label) => tester
    .widget<Semantics>(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      ),
    )
    .properties
    .checked;

void main() {
  group('kural', () {
    test('8 karakter, harf ve rakam', () {
      expect(passwordAcceptable('kisa1'), isFalse);
      expect(passwordAcceptable('sadeceharf'), isFalse);
      expect(passwordAcceptable('12345678'), isFalse);
      expect(passwordAcceptable('parola12'), isTrue);
      expect(passwordAcceptable('çağrı123'), isTrue, reason: 'Türkçe harf');
    });

    test('güç kuralı geçmeyen parolada en fazla zayıf', () {
      expect(strengthOf(''), PasswordStrength.empty);
      expect(strengthOf('abc'), PasswordStrength.weak);
      expect(strengthOf('parola12'), PasswordStrength.fair);
      expect(strengthOf('Parola12!uzun-bir-cumle'), PasswordStrength.strong);
    });
  });

  group('kayıt', () {
    Future<FakeAuthService> openSignUp(WidgetTester tester) async {
      useScreenSize(tester, const Size(1400, 1400));
      final auth = FakeAuthService()..requireConfirmation = true;
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
      return auth;
    }

    testWidgets('kural listesi yazılırken işaretlenir', (tester) async {
      await openSignUp(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Parola'), 'abc');
      await tester.pump();

      expect(ruleChecked(tester, 'En az 8 karakter'), isFalse);

      await tester.enterText(
        find.widgetWithText(TextField, 'Parola'),
        'abcdefgh1',
      );
      await tester.pump();
      expect(ruleChecked(tester, 'En az 8 karakter'), isTrue);
    });

    testWidgets('tekrar eşleşmezse gönderilmez', (tester) async {
      await openSignUp(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Parola'),
        'parola123',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Parola (tekrar)'),
        'parola124',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Hesap oluştur'));
      await tester.pumpAndSettle();

      expect(find.text('Parolalar aynı değil.'), findsOneWidget);
      expect(find.text('E-postanı doğrula'), findsNothing);
    });

    testWidgets('onay isteniyorsa kod adımı gelir, kodla hesap açılır', (
      tester,
    ) async {
      final auth = await openSignUp(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Parola'),
        'parola123',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Parola (tekrar)'),
        'parola123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Hesap oluştur'));
      await tester.pumpAndSettle();

      expect(find.text('E-postanı doğrula'), findsOneWidget);
      expect(find.textContaining('ali@example.com'), findsOneWidget);
      // Yeniden gönder ilk 60 sn kapalı.
      expect(find.textContaining('Yeniden gönder ('), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, '6 haneli kod'),
        '000000',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Doğrula ve başla'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Kod geçersiz'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, '6 haneli kod'),
        '123456',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Doğrula ve başla'));
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(auth.currentUser?.email, 'ali@example.com');
    });

    testWidgets('bekleme bitince kod yeniden istenebilir', (tester) async {
      final auth = await openSignUp(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Parola'),
        'parola123',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Parola (tekrar)'),
        'parola123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Hesap oluştur'));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 61));
      await tester.tap(find.text('Kodu yeniden gönder'));
      await tester.pumpAndSettle();

      expect(auth.signupCodesResentTo, ['ali@example.com']);
      expect(find.text('Yeni bir kod gönderdik.'), findsOneWidget);
      // Sayaç yeniden başladı; testin bekleyen zamanlayıcı bırakmaması için.
      await tester.pump(const Duration(seconds: 61));
    });
  });

  group('parola değiştir', () {
    Future<FakeAuthService> open(
      WidgetTester tester, {
      bool hasPassword = true,
    }) async {
      useScreenSize(tester, const Size(900, 1600));
      final auth = FakeAuthService(
        user: AuthUser(
          id: 'k1',
          email: 'ali@example.com',
          hasPassword: hasPassword,
        ),
      );
      addTearDown(auth.dispose);
      await pumpApp(
        tester,
        const ChangePasswordScreen(),
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );
      await tester.pumpAndSettle();
      return auth;
    }

    Future<void> fillNew(WidgetTester tester, String p) async {
      await tester.enterText(find.widgetWithText(TextField, 'Yeni parola'), p);
      await tester.enterText(
        find.widgetWithText(TextField, 'Parola (tekrar)'),
        p,
      );
    }

    testWidgets('mevcut parola yanlışsa hiçbir şey değişmez', (tester) async {
      final auth = await open(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Mevcut parola'),
        'yanlis-parola1',
      );
      await fillNew(tester, 'yeniParola9');
      await tester.tap(find.widgetWithText(FilledButton, 'Parolayı değiştir'));
      await tester.pumpAndSettle();

      expect(find.text('Mevcut parola hatalı.'), findsOneWidget);
      expect(auth.lastPasswordUpdate, isNull);
    });

    testWidgets('doğru mevcut parolayla değişir, diğer oturumlar kapanabilir', (
      tester,
    ) async {
      final auth = await open(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Mevcut parola'),
        'eski-parola1',
      );
      await fillNew(tester, 'yeniParola9');
      await tester.tap(find.text('Diğer cihazlardaki oturumları kapat'));
      await tester.tap(find.widgetWithText(FilledButton, 'Parolayı değiştir'));
      await tester.pumpAndSettle();

      expect(auth.lastPasswordUpdate, 'yeniParola9');
      expect(auth.otherSessionsClosed, 1);
    });

    testWidgets('yeni parola eskisiyle aynı olamaz', (tester) async {
      final auth = await open(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Mevcut parola'),
        'eski-parola1',
      );
      await fillNew(tester, 'eski-parola1');
      await tester.tap(find.widgetWithText(FilledButton, 'Parolayı değiştir'));
      await tester.pumpAndSettle();

      expect(find.text('Yeni parola eskisiyle aynı olamaz.'), findsOneWidget);
      expect(auth.lastPasswordUpdate, isNull);
    });

    testWidgets('mevcut parolayı hatırlamayan kodla değiştirir', (
      tester,
    ) async {
      final auth = await open(tester);

      await tester.tap(find.text('Mevcut parolanı hatırlamıyor musun?'));
      await tester.pumpAndSettle();

      expect(auth.reauthCodesSent, 1);
      expect(find.widgetWithText(TextField, 'Mevcut parola'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, '6 haneli kod'),
        '123456',
      );
      await fillNew(tester, 'yeniParola9');
      await tester.tap(find.widgetWithText(FilledButton, 'Parolayı değiştir'));
      await tester.pumpAndSettle();

      expect(auth.lastPasswordUpdate, 'yeniParola9');
      expect(auth.lastPasswordCode, '123456');
    });

    testWidgets('Google hesabında "Parola belirle" ve kod yolu', (
      tester,
    ) async {
      final auth = await open(tester, hasPassword: false);

      expect(find.text('Parola belirle'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Mevcut parola'), findsNothing);

      await tester.tap(find.text('E-postama doğrulama kodu gönder'));
      await tester.pumpAndSettle();
      expect(auth.reauthCodesSent, 1);

      await tester.enterText(
        find.widgetWithText(TextField, '6 haneli kod'),
        '123456',
      );
      await fillNew(tester, 'yeniParola9');
      await tester.tap(find.widgetWithText(FilledButton, 'Parolayı belirle'));
      await tester.pumpAndSettle();

      expect(auth.lastPasswordUpdate, 'yeniParola9');
      await tester.pump(const Duration(seconds: 61));
    });
  });
}
