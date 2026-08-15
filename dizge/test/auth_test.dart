import 'package:dizge/core/auth_service.dart';
import 'package:dizge/data/app_store.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/data/persistence_providers.dart';
import 'package:dizge/data/sync/mutation.dart';
import 'package:dizge/data/sync/outbox.dart';
import 'package:dizge/models/node.dart';
import 'package:dizge/screens/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Note _note() => Note(title: 'Yerel not', body: 'çıkıştan sonra da durmalı');

void main() {
  group('NoopAuthService', () {
    test('backend yokken oturum kavramı yoktur', () {
      expect(const NoopAuthService().currentUser, isNull);
    });

    test('giriş denemesi sessizce başarısız olmaz, açıkça söyler', () async {
      // Sessiz `return` felaket olurdu: kullanıcı düğmeye basar, hiçbir şey
      // olmaz ve nedenini asla öğrenemez.
      await expectLater(
        const NoopAuthService().signIn(email: 'a@b.c', password: '123456'),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('çıkış yapmak hata vermez', () async {
      // Oturum yokken çıkmak zaten istenen durumda olmak demek.
      await expectLater(const NoopAuthService().signOut(), completes);
    });
  });

  group('hesap ekranı', () {
    /// Ayarlar listesi uzun ve `ListView` tembel çiziyor: varsayılan 800×600
    /// test penceresinde "Hesap" bölümü hiç kurulmuyor. Gerçek kullanıcı
    /// kaydırıyor; test ise bölümü görünür kılmak için pencereyi uzatıyor.
    void useTallScreen(WidgetTester tester) =>
        useScreenSize(tester, const Size(900, 1800));

    testWidgets('oturum yokken hesap bölümü hiç görünmez', (tester) async {
      useTallScreen(tester);
      // Kapıdan (AuthGate) sonra bu ekrana yalnız oturum açmış biri
      // ulaşabiliyor; "Oturum aç" satırı artık ulaşılamayan bir durumun
      // düğmesi olurdu. Anahtarsız yerel derlemede ise oturum kavramı hiç yok.
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const AccountScreen(),
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );

      expect(find.text('Oturum aç'), findsNothing);
      expect(find.text('Çıkış yap'), findsNothing);
      expect(find.text('Misafir'), findsOneWidget);
    });

    testWidgets('oturum açıkken e-posta ve çıkış görünür', (tester) async {
      useTallScreen(tester);
      final auth = FakeAuthService(
        user: const AuthUser(id: 'k1', email: 'ali@example.com'),
      );
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const AccountScreen(),
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );

      expect(find.text('ali@example.com'), findsOneWidget);
      expect(find.text('Çıkış yap'), findsOneWidget);
      expect(find.text('Oturum aç'), findsNothing);
    });

    testWidgets('oturum açılınca ekran kendiliğinden güncellenir', (
      tester,
    ) async {
      useTallScreen(tester);
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const AccountScreen(),
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );
      expect(find.text('Misafir'), findsOneWidget);

      // Oturum başka bir yerden açıldı (ör. jeton yenilendi). Ekran akışı
      // dinlediği için elle tazelemeye gerek kalmamalı.
      await auth.signIn(email: 'ali@example.com', password: '123456');
      await tester.pumpAndSettle();

      expect(find.text('ali@example.com'), findsOneWidget);
      expect(find.text('Misafir'), findsNothing);
    });

    testWidgets('çıkış cihazdaki planları da siler', (tester) async {
      useTallScreen(tester);
      // Kapıdan önce çıkış yerel veriye dokunmuyordu ve o doğru karardı.
      // Artık dokunuyor (G3): aynı cihazda ikinci bir kişi giriş yapsaydı
      // öncekinin bütün takvimini görürdü — Hive kutusu tek ve kullanıcıdan
      // bağımsız. Açığı kapı yarattı, kapatmak da onun borcu.
      final auth = FakeAuthService(
        user: const AuthUser(id: 'k1', email: 'ali@example.com'),
      );
      addTearDown(auth.dispose);

      final container = await pumpApp(
        tester,
        const AccountScreen(),
        overrides: [authServiceProvider.overrideWithValue(auth)],
        seed: (store) => store.addNote(_note()),
      );

      await tester.tap(find.text('Çıkış yap'));
      await tester.pumpAndSettle();

      expect(auth.signOutCount, 1);
      expect(container.read(appStoreProvider).notes, isEmpty);
    });

    testWidgets('gönderilmemiş değişiklik varken çıkış önce sorar', (
      tester,
    ) async {
      useTallScreen(tester);
      // Kuyruktaki mutasyon henüz hiçbir yerde yok: ne sunucuda, ne başka bir
      // cihazda. Sessizce silinseydi kullanıcı onu geri getiremezdi.
      final auth = FakeAuthService(
        user: const AuthUser(id: 'k1', email: 'ali@example.com'),
      );
      addTearDown(auth.dispose);

      final store = InMemoryStore();
      await store.init();
      final outbox = Outbox(store)
        ..enqueue(
          Mutation(
            kind: EntityKind.note,
            entityId: 'not-1',
            op: MutationOp.upsert,
            payload: const {},
          ),
        );

      final container = await pumpApp(
        tester,
        const AccountScreen(),
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          localStoreProvider.overrideWithValue(store),
          outboxProvider.overrideWithValue(outbox),
        ],
        seed: (s) => s.addNote(_note()),
      );

      await tester.tap(find.text('Çıkış yap'));
      await tester.pumpAndSettle();

      expect(find.text('Yüklenmemiş değişiklikler var'), findsOneWidget);

      // Vazgeçmek gerçekten vazgeçmek: ne oturum kapanır ne veri silinir.
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      expect(auth.signOutCount, 0);
      expect(container.read(appStoreProvider).notes, hasLength(1));
    });
  });
}
