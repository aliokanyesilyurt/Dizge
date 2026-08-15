import 'package:dizge/models/profile.dart';
import 'package:dizge/theme.dart';
import 'package:dizge/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Y4.4c — rozet tek başına.
///
/// Yüzeylere dağıtmadan önce burada doğrulanıyor: avatarı dört ekrana yayıp
/// sonra düzeltmek, dört ekranı birden düzeltmek olurdu.

Widget _wrap(Widget child, {double textScale = 1.0}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('renk', () {
    test('aynı kimlik her zaman aynı rengi verir', () {
      // `hashCode` kullanılsaydı aynı kişi bir gün mavi, ertesi gün mor
      // olabilirdi — Dart dize hash'i çalışma zamanları arasında değişir.
      final a = avatarColorFor('u-ali');
      final b = avatarColorFor('u-ali');
      expect(a, b);
    });

    test('farklı kimlikler paletin içinde kalır', () {
      for (final id in ['u-ali', 'u-veli', 'u-ayse', '', 'x']) {
        expect(kAvatarColors, contains(avatarColorFor(id)));
      }
    });

    test('renk addan bağımsız — ad değişince renk değişmez', () {
      // Y4.4c'nin asıl sözü. Ada bağlasaydık, adını düzelten biri geçmiş
      // haftalardaki bütün bloklarını renk değiştirmiş bulurdu.
      const once = Profile(userId: 'u-ali', displayName: 'Ali');
      const sonra = Profile(userId: 'u-ali', displayName: 'Ali Okan');
      expect(avatarColorFor(once.userId), avatarColorFor(sonra.userId));
      expect(once.initials, isNot(sonra.initials));
    });

    test('her palet rengi mürekkebiyle AA eşiğini geçer', () {
      // Kontrast bir test temennisi değil: rozet opak bir daire olduğu için
      // ölçüm tam olarak burada yapılabiliyor — zemin temadan bağımsız.
      for (final color in kAvatarColors) {
        final ratio = contrastRatio(color, inkOn(color));
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              'Renk $color mürekkebiyle yalnız ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });
  });

  group('içerik', () {
    testWidgets('profil varsa baş harfler görünür', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const UserAvatar(
            profile: Profile(userId: 'u-ali', displayName: 'Ali Okan'),
            userId: 'u-ali',
          ),
        ),
      );

      expect(find.text('AO'), findsOneWidget);
    });

    testWidgets('profil bilinmiyorsa soru işareti çizilir', (tester) async {
      // Boş bir daire "bu iş kimsenin" derdi; `?` "henüz bilmiyorum" diyor.
      await tester.pumpWidget(
        _wrap(const UserAvatar(profile: null, userId: 'u-yabanci')),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('fotoğraf varken de baş harf yedekte durur', (tester) async {
      // `Image.network` testte ağa çıkamaz ve hata verir; aranan davranış tam
      // olarak bu — kullanıcıya kırık resim ikonu değil, baş harf gösterilir.
      await tester.pumpWidget(
        _wrap(
          const UserAvatar(
            profile: Profile(
              userId: 'u-ali',
              displayName: 'Ali Okan',
              avatarUrl: 'https://ornek/foto.jpg',
            ),
            userId: 'u-ali',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('AO'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ölçü ve erişilebilirlik', () {
    testWidgets('istenen çapta çizilir', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const UserAvatar(
            profile: Profile(userId: 'u', displayName: 'A'),
            userId: 'u',
            size: 14,
          ),
        ),
      );

      final box = tester.getSize(
        find.descendant(
          of: find.byType(UserAvatar),
          matching: find.byType(Container),
        ),
      );
      expect(box, const Size(14, 14));
    });

    testWidgets('metin ölçeği rozeti büyütmez', (tester) async {
      // %200'de 14px'lik bir daire bloğun yarısını kaplardı. Tam ad zaten
      // ipucunda ve ekran okuyucuda; bilgi kaybı yok.
      await tester.pumpWidget(
        _wrap(
          const UserAvatar(
            profile: Profile(userId: 'u', displayName: 'Ali Okan'),
            userId: 'u',
            size: 14,
          ),
          textScale: 2.0,
        ),
      );

      final box = tester.getSize(
        find.descendant(
          of: find.byType(UserAvatar),
          matching: find.byType(Container),
        ),
      );
      expect(box, const Size(14, 14));
    });

    testWidgets('ekran okuyucu adı duyar, bilinmeyeni de söyler', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          const Column(
            children: [
              UserAvatar(
                profile: Profile(userId: 'u-ali', displayName: 'Ali Okan'),
                userId: 'u-ali',
              ),
              UserAvatar(profile: null, userId: 'u-yok'),
            ],
          ),
        ),
      );

      expect(find.bySemanticsLabel('Ali Okan'), findsOneWidget);
      expect(find.bySemanticsLabel('Bilinmeyen kişi'), findsOneWidget);
      handle.dispose();
    });
  });
}
