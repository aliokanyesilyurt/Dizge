import 'package:dizge/core/auth_service.dart';
import 'package:dizge/core/connectivity.dart';
import 'package:dizge/core/telemetry.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/data/persistence_providers.dart';
import 'package:dizge/screens/app_shell.dart';
import 'package:dizge/screens/auth_gate.dart';
import 'package:dizge/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Karşılama ekranındaki Google düğmesi.
final _googleButton = find.widgetWithText(
  OutlinedButton,
  'Google ile devam et',
);

void main() {
  /// Bağlantıyı sabitler. Testte gerçek eklenti konuşmuyor ve durum `null`
  /// kalıyor — "çevrimdışı mı" sorusunu açıkça sormayan bir test, düğmenin
  /// pasifleşmesini yanlışlıkla doğru sanabilirdi.
  Override network(NetworkStatus status) =>
      networkStatusProvider.overrideWith((ref) => Stream.value(status));

  group('AuthService sözleşmesi', () {
    test('backend yokken Google girişi de açıkça başarısız olur', () async {
      // Sessiz `return` olsaydı düğme çalışıyormuş gibi görünür, hiçbir şey
      // olmazdı.
      await expectLater(
        const NoopAuthService().signInWithGoogle(),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('karşılama ekranı — Google düğmesi', () {
    testWidgets('düğme görünür ve basınca akışı başlatır', (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final telemetry = RecordingTelemetry();

      await pumpApp(
        tester,
        const WelcomeScreen(),
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          telemetryProvider.overrideWithValue(telemetry),
          network(NetworkStatus.online),
        ],
      );

      expect(_googleButton, findsOneWidget);

      await tester.tap(_googleButton);
      await tester.pumpAndSettle();

      expect(auth.googleSignInCount, 1);
      expect(telemetry.events, contains(Ev.googleSignInStarted));
    });

    testWidgets('tarayıcı açıldıktan sonra ekran ne olduğunu söyler', (
      tester,
    ) async {
      // Bu yolun en kolay kaybedilen yeri: düğmeye basılır, pencere değişmez
      // ve kullanıcı tarayıcıya geçtiğini fark etmezse "bozuk" der.
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const WelcomeScreen(),
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          network(NetworkStatus.online),
        ],
      );

      await tester.tap(_googleButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Tarayıcıda girişi tamamla'), findsOneWidget);
    });

    testWidgets('sağlayıcı kapalıysa hata metni görünür', (tester) async {
      final auth = FakeAuthService()
        ..nextFailure = const AuthFailure(
          'Google girişi bu sunucuda açık değil.',
        );
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const WelcomeScreen(),
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          network(NetworkStatus.online),
        ],
      );

      await tester.tap(_googleButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Google girişi bu sunucuda açık değil.'),
        findsOneWidget,
      );
    });

    testWidgets('dönüş yolundaki hata da ekrana düşer', (tester) async {
      // G8d'nin asıl sınavı: hata çağrıya değil oturum akışına gelir. Ekran
      // yalnız çağrıyı dinleseydi kullanıcı tarayıcıdan boş döner ve karşısında
      // hiçbir şey olmamış gibi duran bir form bulurdu.
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const WelcomeScreen(),
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          network(NetworkStatus.online),
        ],
      );

      await tester.tap(_googleButton);
      await tester.pumpAndSettle();

      auth.emitGoogleFailure(const AuthFailure('Google girişi tamamlanmadı.'));
      await tester.pumpAndSettle();

      expect(find.text('Google girişi tamamlanmadı.'), findsOneWidget);
      // Yanıltıcı olurdu: "tarayıcıya git" yazısı hata gelince kalkmalı.
      expect(find.textContaining('Tarayıcıda girişi tamamla'), findsNothing);
    });

    testWidgets('çevrimdışıyken düğme pasif ve sebebi yazıyor', (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const WelcomeScreen(),
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          network(NetworkStatus.offline),
        ],
      );

      expect(tester.widget<OutlinedButton>(_googleButton).onPressed, isNull);
      expect(find.textContaining('çevrimdışıyken'), findsOneWidget);
    });

    testWidgets('parola kurtarma adımlarında düğme yok', (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      final disk = InMemoryStore();
      await disk.init();
      await disk.writeString(kHasSignedInKey, 'yes');

      await pumpApp(
        tester,
        const WelcomeScreen(),
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          localStoreProvider.overrideWithValue(disk),
          network(NetworkStatus.online),
        ],
      );

      expect(_googleButton, findsOneWidget);

      // Google düğmesi formu uzattı: 800×600'lük test penceresinde kurtarma
      // bağlantısı kaydırma alanının dışında kalıyor.
      await tester.ensureVisible(find.text('Parolamı unuttum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parolamı unuttum'));
      await tester.pumpAndSettle();

      // Kod bekleyen bir kullanıcıya üçüncü bir yol göstermek, kurtarmayı
      // yarıda bıraktırırdı.
      expect(_googleButton, findsNothing);
    });
  });

  group('kapı — Google dönüşü', () {
    testWidgets('tarayıcıdan dönünce takvim açılır', (tester) async {
      useScreenSize(tester, const Size(1200, 900));
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const AuthGate(),
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          network(NetworkStatus.online),
        ],
      );

      expect(find.byType(WelcomeScreen), findsOneWidget);

      await tester.tap(_googleButton);
      await tester.pumpAndSettle();

      // Dönüş: oturum akıştan gelir, ekranı kapı değiştirir — karşılama
      // ekranının kendi yönlendirmesi yok.
      auth.emitGoogleReturn();
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
    });
  });
}
