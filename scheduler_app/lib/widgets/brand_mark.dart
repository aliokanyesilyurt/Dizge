import 'package:flutter/material.dart';

import '../theme.dart';

/// Uygulamanın işareti — kenar çubuğunun tepesinde, karşılama ekranında ve
/// açılış karesinde aynı şey.
///
/// Ayrı bir dosyaya çıkarıldı çünkü üç yerde görünüyor ve birbirinden
/// ayrılmaları sessiz bir tutarsızlık olurdu: marka, kullanıcının uygulamayı
/// tanıdığı ilk karedir.
///
/// İşaret artık çizilen bir ikon değil, **markanın kendi görseli**: koyu bir
/// disk üstünde camgöbeği "dizge" kelime-işareti, diskin dışı saydam. Saydam
/// olması iki temada da aynı dosyanın kullanılabilmesi demek; yuvarlak olması
/// da her boyutta aynı silueti vermesi — ikonun köşe yarıçapını boyuta göre
/// ayarlamak gerekmiyor.
///
/// Oranlar [size] üzerinden türetiliyor; 30 piksellik kenar çubuğu hâli
/// birebir korunur.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 30});

  final double size;

  /// Ham kelime-işareti (disk yok, saydam zemin). Yan yana metinle
  /// kullanılacak yerler için duruyor.
  static const wordmarkAsset = 'assets/brand/dizge_wordmark.png';

  static const markAsset = 'assets/brand/dizge_mark.png';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: c.shadowSm),
      child: Image.asset(
        markAsset,
        width: size,
        height: size,
        // Küçük boyutlarda (kenar çubuğunda 30 piksel) ince çizgiler kırılıyor;
        // `filterQuality` yükseltmek onları ayakta tutuyor.
        filterQuality: FilterQuality.high,
        // Görsel yüklenemezse marka yerine boşluk bırakmak, kenar çubuğunun
        // tepesinde açıklanamayan bir delik olurdu.
        errorBuilder: (context, _, _) => Icon(
          Icons.auto_awesome_rounded,
          size: size * 8 / 15,
          color: c.accent,
        ),
      ),
    );
  }
}
