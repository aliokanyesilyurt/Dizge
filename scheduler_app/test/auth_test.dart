import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/auth_service.dart';
import 'package:scheduler_app/data/app_store.dart';
import 'package:scheduler_app/models/node.dart';
import 'package:scheduler_app/screens/account_screen.dart';

import 'helpers.dart';

Note _note() => Note(title: 'Yerel not', body: 'çıkıştan sonra da durmalı');

/// Bellekte çalışan oturum servisi. Ağ yok, gerçek Supabase yok.
class FakeAuthService implements AuthService {
  FakeAuthService({AuthUser? user}) : _user = user;

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

    testWidgets('oturum yokken giriş çağrısı görünür', (tester) async {
      useTallScreen(tester);
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await pumpApp(
        tester,
        const AccountScreen(),
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );

      expect(find.text('Oturum aç'), findsOneWidget);
      expect(find.text('Misafir'), findsOneWidget);
      expect(find.text('Çıkış yap'), findsNothing);
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

    testWidgets('çıkış yerel veriye dokunmaz', (tester) async {
      useTallScreen(tester);
      // Cihazdaki takvim kullanıcınındır. Çıkış yalnız jetonu siler; veriyi
      // silmek "Cihazdaki verileri sil" düğmesinin işi ve o ayrı bir karar.
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
      expect(container.read(appStoreProvider).notes, hasLength(1));
    });
  });
}
