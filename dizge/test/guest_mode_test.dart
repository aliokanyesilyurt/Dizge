/// Misafir kipi ve kapının önceliği (Karar A).
///
/// Bu dosyanın varlık sebebi somut bir hata: `guest_mode` yerel depoda
/// kalıcıydı ve kapı onu oturumdan **önce** okuyordu. Bir kez "misafir olarak
/// devam et" diyen cihazda Google girişi sunucuda tamamlanıyor, uygulama
/// misafir kabuğunda kalıyordu — kullanıcı "giriş yapıyorum ama giremiyorum"
/// diyordu ve haklıydı.
///
/// Aynı kusur hesap ekranını da boşaltıyordu: misafir dalı yalnız "Oturum aç"
/// satırını çiziyor, çıkış ve parola satırları hiç görünmüyordu.
library;

import 'package:dizge/core/auth_service.dart';
import 'package:dizge/core/profile_directory.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/data/persistence_providers.dart';
import 'package:dizge/models/profile.dart';
import 'package:dizge/screens/app_shell.dart';
import 'package:dizge/screens/auth_gate.dart';
import 'package:dizge/screens/welcome_screen.dart';
import 'package:dizge/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  /// Misafir olarak devam etmiş bir cihaz.
  Future<(InMemoryStore, List<Override>)> guestDevice(
    FakeAuthService auth, {
    String? name,
    String? color,
  }) async {
    final disk = InMemoryStore();
    await disk.init();
    await disk.writeString(kGuestModeKey, 'yes');
    if (name != null) await disk.writeString(kGuestNameKey, name);
    if (color != null) await disk.writeString(kGuestColorKey, color);
    return (
      disk,
      [
        authServiceProvider.overrideWithValue(auth),
        localStoreProvider.overrideWithValue(disk),
      ],
    );
  }

  void useWideScreen(WidgetTester tester) =>
      useScreenSize(tester, const Size(1200, 900));

  group('misafir kipi', () {
    testWidgets('misafir bayrağı varken takvim açılır', (tester) async {
      useWideScreen(tester);
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final (_, overrides) = await guestDevice(auth);

      await pumpApp(tester, const AuthGate(), overrides: overrides);

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('gerçek oturum misafir bayrağını yener', (tester) async {
      // Kusurun ta kendisi. Bayrak diskte duruyor **ve** oturum açık:
      // kapı oturumu görmeli, misafir kabuğuna düşmemeli.
      useWideScreen(tester);
      final auth = FakeAuthService(
        user: const AuthUser(id: 'k1', email: 'ali@example.com'),
      );
      addTearDown(auth.dispose);
      final (_, overrides) = await guestDevice(auth);

      final container = await pumpApp(
        tester,
        const AuthGate(),
        overrides: overrides,
      );

      expect(find.byType(AppShell), findsOneWidget);

      // Ekranın doğru olması yetmez: bayrak diskte kaldığı sürece kullanıcı
      // çıkış yaptığında hiç istemediği hâlde yine misafir olarak uyanırdı.
      await tester.pumpAndSettle();
      expect(container.read(guestModeProvider), isFalse);
    });

    testWidgets('misafirken giriş yapmak bayrağı temizler', (tester) async {
      useWideScreen(tester);
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final (disk, overrides) = await guestDevice(auth);

      final container = await pumpApp(
        tester,
        const AuthGate(),
        overrides: overrides,
      );
      expect(container.read(guestModeProvider), isTrue);

      // Kullanıcı misafirken hesap ekranından "Oturum aç" diyor, sonra
      // gerçekten giriyor.
      await auth.signIn(email: 'ali@example.com', password: 'parola123');
      await tester.pumpAndSettle();

      expect(container.read(guestModeProvider), isFalse);
      expect(disk.readString(kGuestModeKey), 'no');
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('oturum akışı düşerse misafir dışarı atılmaz', (tester) async {
      // Kapı hata durumunda kapanıyor — ama misafir zaten oturuma dayanmıyor.
      useWideScreen(tester);
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final (_, overrides) = await guestDevice(auth);

      await pumpApp(tester, const AuthGate(), overrides: overrides);
      auth.emitError(Exception('akış düştü'));
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
    });
  });

  group('misafir profili', () {
    test('ad ve renk yerel depodan okunur', () async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final (_, overrides) = await guestDevice(auth, name: 'Ali', color: '3');

      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);

      final me = container.read(guestProfileProvider);
      expect(me?.displayName, 'Ali');
      expect(me?.avatarColor, 3);
      // Kimlik artık rengi taşımıyor: bir zamanlar `guest_color_3` gibi
      // uydurma kimlikler üretiliyordu ve rozet bunu ön ekinden tanıyordu.
      expect(me?.userId, kGuestUserId);
    });

    test('misafir değilken profil yok', () async {
      final disk = InMemoryStore();
      await disk.init();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(disk)],
      );
      addTearDown(container.dispose);

      expect(container.read(guestProfileProvider), isNull);
      expect(container.read(profileProvider(null)), isNull);
    });

    test('boş ad "Misafir"e düşer', () async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final (_, overrides) = await guestDevice(auth, name: '   ');

      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);

      expect(container.read(guestProfileProvider)?.displayName, 'Misafir');
    });
  });

  group('rozet rengi', () {
    test('seçim yoksa renk kimlikten türer', () {
      // Türetme iyi bir varsayılan ve kaybolmamalı: profili henüz inmemiş bir
      // grup arkadaşı da kararlı bir renk almalı.
      expect(
        avatarColorOf(const Profile(userId: 'u-ali'), 'u-ali'),
        avatarColorFor('u-ali'),
      );
      expect(avatarColorOf(null, 'u-ali'), avatarColorFor('u-ali'));
    });

    test('seçim varsa kimlik değil seçim kazanır', () {
      const me = Profile(userId: 'u-ali', avatarColor: 4);
      expect(avatarColorOf(me, 'u-ali'), kAvatarColors[4]);
    });

    test('aralık dışı sıra rozeti düşürmez', () {
      // Palete sonradan renk eklenip çıkarılabilir; sunucudan gelen sıra
      // listenin dışına taşarsa rozetin çizilmemesi kabul edilemez bir bedel.
      const me = Profile(userId: 'u-ali', avatarColor: 99);
      expect(
        avatarColorOf(me, 'u-ali'),
        kAvatarColors[99 % kAvatarColors.length],
      );
    });
  });

  group('profil modeli', () {
    test('renk sunucu satırından ve önbellekten okunur', () {
      final fromRow = Profile.fromRow({
        'user_id': 'u-ali',
        'display_name': 'Ali',
        'avatar_color': 5,
      });
      expect(fromRow.avatarColor, 5);

      // Gidiş dönüş: yerel önbellek rengi kaybetmemeli, yoksa çevrimdışı
      // açılışta rozet bir kare boyunca başka renkte yanardı.
      expect(Profile.fromJson(fromRow.toJson()).avatarColor, 5);
    });

    test('sütun yoksa renk null kalır ve eski davranışa düşülür', () {
      // Göç panoda çalıştırılmamışsa sunucu `avatar_color` göndermez.
      final p = Profile.fromRow({'user_id': 'u-ali', 'display_name': 'Ali'});
      expect(p.avatarColor, isNull);
      expect(avatarColorOf(p, 'u-ali'), avatarColorFor('u-ali'));
    });
  });
}
