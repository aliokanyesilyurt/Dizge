/// Biçim belirteçleri: boşluk, tipografi, yuvarlaklık, simge ölçeği ve süre.
///
/// Hiçbiri renk bilmiyor — bu yüzden paletten ayrı duruyorlar.
library;

import 'package:flutter/material.dart';
// --- Biçim belirteçleri ------------------------------------------------------

/// Yuvarlaklık ölçeği. Tek tek sayı yazmak yerine bunlar kullanılır ki
/// uygulamanın "köşe dili" tek yerden değişebilsin.
abstract final class R {
  /// Takvim bloğu, minik rozet.
  static const xs = 6.0;

  /// Girdi alanı, küçük kutu.
  static const sm = 10.0;

  /// Kart, panel.
  static const md = 16.0;

  /// Büyük panel, sheet gövdesi.
  static const lg = 22.0;

  /// Hap / tam yuvarlak.
  static const pill = 999.0;

  static BorderRadius get radiusXs => BorderRadius.circular(xs);
  static BorderRadius get radiusSm => BorderRadius.circular(sm);
  static BorderRadius get radiusMd => BorderRadius.circular(md);
  static BorderRadius get radiusLg => BorderRadius.circular(lg);
  static BorderRadius get radiusPill => BorderRadius.circular(pill);
}

/// Hareket süreleri. Tek bir "his" için hepsi buradan okunur.
abstract final class Motion {
  /// Dokunma geri bildirimi, renk geçişi.
  static const fast = Duration(milliseconds: 140);

  /// Açılıp kapanan panel, seçim animasyonu.
  static const base = Duration(milliseconds: 220);

  /// Sayfa/bölüm geçişi.
  static const slow = Duration(milliseconds: 320);

  static const curve = Curves.easeOutCubic;
}

/// Boşluk ölçeği. `R` yarıçapı, `Motion` süreyi neyse, bu da boşluğu.
///
/// Neden ölçek: bu değerler bir zamanlar her dosyada elle yazılıydı ve 1'den
/// 26'ya neredeyse her tam sayı kullanılıyordu. 11 ile 12 arasındaki fark
/// kimseye bir şey anlatmıyor, ama yan yana gelen iki kartı görünür biçimde
/// eşitsiz kılıyor. Dörtlü ritim bu eşitsizliği baştan imkânsız kılıyor.
///
/// Neden `ThemeExtension` değil: bu sayılar temaya göre değişmiyor. Bir kartın
/// iç boşluğu açık temada da koyuda da aynı. Değişmez bir değeri temaya
/// bağlamak, okuyana gereksiz bir soru sordurur.
abstract final class S {
  /// Çizgi/ayraç payı. Boşluk değil, kıl payı.
  static const hair = 2.0;

  /// İkon ile yazısı, çip içi dikey.
  static const xs = 4.0;

  /// Satır içi öğeler arası.
  static const sm = 8.0;

  /// Kart içi dikey ritim, liste satırları arası.
  static const md = 12.0;

  /// Kart iç boşluğu, bölümler arası.
  static const lg = 16.0;

  /// Bölüm blokları arası, sheet iç boşluğu.
  static const xl = 24.0;

  /// Büyük ayrım: başlık bloğu ile gövde arası.
  static const xxl = 32.0;

  /// Ekranın kenar boşluğu — başlık ve gövde **aynı** çizgide dursun diye tek
  /// sabitten okunur.
  ///
  /// Daha önce `SectionHeader` soldan 24, altındaki listeler 14–20 arası
  /// kendi seçtikleri bir değer kullanıyordu; sonuç, sekme değiştirince
  /// içeriğin yatayda zıplamasıydı.
  static const gutter = 20.0;

  /// Kayan listelerin altında FAB'a bırakılan pay.
  ///
  /// Ölçeğin bir kademesi değil, bir **ölçü**: FAB'ın kendi boyu + nefes payı.
  /// Üç ekranda elle `100` yazılıydı.
  static const fabGap = 100.0;
}

/// Tipografi ölçeği. Sekiz kademe, her birinin tek bir işi var.
///
/// Bu ölçekten önce depoda **22 ayrı yazı boyu** vardı (9'dan 26'ya, yarım
/// puntolar dahil) ve 182 satır içi `TextStyle`. Aynı rol iki ekranda iki ayrı
/// boyla çiziliyordu.
///
/// [TextTheme] bu kademelerden **türetilir** ([_buildTextTheme]); böylece
/// `textTheme.headlineSmall` ile [headline] aynı sayıyı verir ve iki ayrı
/// tipografi kaynağı oluşmaz.
abstract final class T {
  /// **Yalnız yoğun ızgara için**: takvim bloğu, ay hücresi, ısı haritası.
  ///
  /// Neden ayrı bir kademe: `GridDensity.compact` modunda bir saatlik blok 38
  /// piksele iner ve yazının oraya sığması gerekir. Bu boyları [micro]'ya
  /// çıkarmak blokları taşırırdı. Ama eski 9 ve 9.5 da fazla küçüktü — ikisi
  /// burada, 10'da buluşuyor.
  static const dense = 10.0;

  /// Rozet, sayaç, yardımcı etiket.
  static const micro = 11.0;

  /// Alt açıklama, ikincil satır.
  static const caption = 12.0;

  /// Gövde metni, liste satırı.
  static const body = 13.0;

  /// Kart başlığı, birincil satır.
  static const strong = 14.0;

  /// Panel başlığı, sheet başlığı.
  static const title = 16.0;

  /// Ekran başlığı (`SectionHeader`).
  static const headline = 20.0;

  /// Karşılama ekranı, boş durum rakamı.
  static const display = 26.0;

  /// Küçükten büyüğe tüm kademeler — testlerin ve göç denetimlerinin
  /// dayandığı tek liste.
  static const steps = <double>[
    dense,
    micro,
    caption,
    body,
    strong,
    title,
    headline,
    display,
  ];
}

/// Simge kutusu ölçeği: ikonlar, avatarlar, marka işareti.
///
/// Hepsi aynı şey — kenarı kenarına eşit, yazının yanında duran kare bir
/// kutu — ve hepsi aynı hastalığa yakalanmıştı: 11'den 60'a **on altı ayrı
/// boy**. En sık kullanılan üçü 18, 16 ve 14'tü ve aralarındaki fark hiçbir
/// yerde bir anlam taşımıyordu; yalnız iki ikonu yan yana koyunca eşitsiz
/// görünüyorlardı.
abstract final class I {
  /// Yoğun çip, satır içi küçük işaret.
  static const xs = 14.0;

  /// Gövde yazısının yanındaki ikon, küçük avatar.
  static const sm = 16.0;

  /// Varsayılan arayüz ikonu — düğmeler, liste satırları, gezinme.
  static const md = 18.0;

  /// Öne çıkan eylem: FAB, birincil düğme.
  static const lg = 24.0;

  /// Boş durum ikonu.
  static const xl = 32.0;

  /// Marka işareti, boş durum dairesi — sayfada tek başına duran simge.
  static const hero = 56.0;
}

/// Izgara yoğunluğu: bir saatin kaç piksel yer kapladığı. Kullanıcı başlıktaki
/// düğmeyle değiştirir; tercih oturum boyunca korunur.
enum GridDensity {
  compact(38.0, 'Sıkışık'),
  cozy(56.0, 'Normal'),
  spacious(88.0, 'Geniş');

  const GridDensity(this.hourHeight, this.label);
  final double hourHeight;
  final String label;

  GridDensity get next =>
      GridDensity.values[(index + 1) % GridDensity.values.length];
}

/// Saat sütununun genişliği. Başlık satırı ile ızgaranın hizalı kalması için
/// ikisi de bu sabiti kullanır.
const double kTimeGutterWidth = 58.0;

/// Gövde yazı tipi. Uygulamayla birlikte paketlenir (`assets/fonts/`), bu
/// yüzden görünüm her platformda ve çevrimdışıyken aynı.
///
/// Neden Inter: ekran için tasarlanmış, rakamları dar ve dikey hizalı — saat
/// etiketleri ile gün sayıları ızgarada kaymadan üst üste oturuyor. Önceki
/// tercih olan `Segoe UI` yalnızca Windows'ta doğru görünüyordu.
const String kFontFamily = 'Inter';

/// Paketlenmiş font yüklenemezse (bozuk kurulum, beklenmedik platform) yazı
/// kaybolmasın diye sistem yığını.
const List<String> kFontFallback = [
  'Segoe UI',
  'Roboto',
  'Helvetica Neue',
  'Arial',
  'sans-serif',
];
