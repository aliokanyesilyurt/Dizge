import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/models/node.dart';
import 'package:scheduler_app/models/task.dart' show kTaskColors;
import 'package:scheduler_app/theme.dart';

/// N5a/N5b — neon kategori paleti ve eski renklerin göçü.
///
/// İki ayrı iddia var ve ikisi de kendi başına kırılabilir: paletin kendisi
/// okunur mu, ve diskte duran eski renk bugünkü karşılığına taşınıyor mu.
void main() {
  group('N5a — neon paletin okunurluğu', () {
    test('şerit koyu zeminden 3:1 ile ayrışıyor', () {
      // WCAG 1.4.11 (metin dışı içerik). Şerit bloğun kimliğini taşıyan tek
      // doygun yüzey; zeminden ayrışmazsa blok renksiz görünür.
      for (final color in kTaskColors) {
        expect(
          contrastRatio(color, AppPalette.dark.surface),
          greaterThanOrEqualTo(3.0),
          reason: '${colorToHex(color)} koyu zeminde kayboluyor',
        );
      }
    });

    test('inkOn seçtiği mürekkeple AA eşiğini geçiyor', () {
      // Doygun rengin üstüne konan tik ikonu ve pasta dilimi etiketi bunu
      // kullanıyor: renk zemin, inkOn mürekkep.
      for (final color in kTaskColors) {
        expect(
          contrastRatio(inkOn(color), color),
          greaterThanOrEqualTo(4.5),
          reason: '${colorToHex(color)} üstünde yazı okunmuyor',
        );
      }
    });

    test('koyu temada blok yazısı kategori renginin ta kendisi', () {
      // readableOn okunurluk için rengi gövde mürekkebine doğru çeker. Koyu
      // temada hiç çekmemeli: atılan her adım, kategori renginin yazıda biraz
      // daha az tanınması demek. Palete okunmayan bir renk eklenirse bu test
      // düşer — kontrast testinden önce.
      for (final color in kTaskColors) {
        expect(
          AppPalette.dark.event(color).ink,
          color,
          reason: '${colorToHex(color)} yazıda soluklaştırılıyor',
        );
      }
    });

    test('kategori renkleri durum jetonlarıyla çakışmıyor', () {
      // Kırmızı bir kategori ile "tehlike", ya da bir blok ile "şu an" çizgisi
      // aynı sinyali taşımamalı.
      const jetonlar = {
        'accent': Color(0xFF22D3EE),
        'warning': Color(0xFFFDE047),
        'danger': Color(0xFFFF4D6D),
        'nowLine': Color(0xFFFF2BD6),
      };
      for (final MapEntry(key: ad, value: jeton) in jetonlar.entries) {
        expect(
          kTaskColors,
          isNot(contains(jeton)),
          reason: '$ad jetonu kategori rengiyle aynı',
        );
      }
    });

    test('kUnknownCategoryColor sekizliden ayırt edilebilir', () {
      expect(kTaskColors, isNot(contains(kUnknownCategoryColor)));
      expect(
        contrastRatio(kUnknownCategoryColor, AppPalette.dark.surface),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        contrastRatio(inkOn(kUnknownCategoryColor), kUnknownCategoryColor),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('N5b — eski renklerin göçü', () {
    test('eşleme tablosu güncel paletle birebir', () {
      // Palet değişip eşleme unutulursa kullanıcının takvimi yarı pastel
      // kalır. Tablonun ilk sekiz değeri kTaskColors'ın kendisi olmalı,
      // sırasıyla; dokuzuncusu bilinmeyen kategori rengi.
      final hedefler = kLegacyTaskColors.values.map(Color.new).toList();
      expect(hedefler.take(8), orderedEquals(kTaskColors));
      expect(hedefler.last, kUnknownCategoryColor);
      expect(kLegacyTaskColors, hasLength(9));
    });

    test('eski hex okunduğunda neon karşılığı dönüyor', () {
      for (final MapEntry(key: eski, value: yeni)
          in kLegacyTaskColors.entries) {
        expect(
          colorFromHex(colorToHex(Color(eski))),
          Color(yeni),
          reason: '${Color(eski)} göçmedi',
        );
      }
    });

    test('küçük harfli hex de göçüyor', () {
      // Kayıtlar colorToHex ile büyük harfli yazılıyor ama sunucudan ya da elle
      // düzenlenmiş bir dosyadan küçük harfli gelebilir.
      expect(colorFromHex('ffff6090'), const Color(0xFFFF3D8B));
    });

    test('yeni hex kendisi olarak dönüyor — eşleme etkisiz eleman', () {
      // Çevrim iki kez uygulanırsa (yerelden okunup sunucudan tekrar çekilen
      // satır) sonuç kaymamalı.
      for (final color in kTaskColors) {
        final bir = colorFromHex(colorToHex(color));
        final iki = colorFromHex(colorToHex(bir));
        expect(bir, color);
        expect(iki, color);
      }
    });

    test('tabloda olmayan renge dokunulmuyor', () {
      // Elle düzenlenmiş bir kayıt ya da ileride gelecek bir renk sessizce
      // değişmesin.
      expect(colorFromHex('FF123456'), const Color(0xFF123456));
    });

    test('yokluk ve bozuk değer yedeğe düşüyor, yedek de neon', () {
      const yedek = Color(0xFF38BDF8);
      expect(colorFromHex(null), yedek);
      expect(colorFromHex('mavi olsun'), yedek);
      expect(kTaskColors, contains(yedek));
    });
  });
}
