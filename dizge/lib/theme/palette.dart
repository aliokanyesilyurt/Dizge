/// Renk paleti: [AppPalette] tema uzantısı, `context.colors` kısayolu ve
/// renkten okunur mürekkep hesaplayan yardımcılar.
library;

import 'package:flutter/material.dart';
import '../models/profile.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    // Zeminler
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.hover,
    required this.sidebar,
    required this.sidebarHover,
    required this.navActiveFill,
    required this.navActiveInk,
    // Çizgiler
    required this.line,
    required this.lineSoft,
    // Yazı
    required this.ink,
    required this.inkDim,
    required this.inkFaint,
    // Vurgu
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.secondary,
    required this.warning,
    required this.danger,
    // Takvim
    required this.gridDay,
    required this.gridWeekend,
    required this.clockFace,
    required this.gridHourLine,
    required this.gridHalfLine,
    required this.gridColumnLine,
    required this.gridTodayWash,
    required this.nowLine,
    required this.dropTarget,
    // Derinlik
    required this.shadowContact,
    required this.shadowAmbient,
    required this.glowAccent,
  });

  final Brightness brightness;

  /// Sayfa zemini — hiçbir zaman saf beyaz/siyah değil.
  final Color bg;

  /// Kart / girdi zemini. Zeminden **bir kat ileri**.
  final Color surface;

  /// Sheet / dialog zemini — en öndeki katman.
  final Color surfaceAlt;

  /// Dokunma / üzerine gelme zemini.
  final Color hover;

  final Color sidebar;
  final Color sidebarHover;

  /// Seçili gezinme öğesinin hapı ve üzerindeki yazı.
  final Color navActiveFill;
  final Color navActiveInk;

  /// Belirgin kenarlık, ızgara.
  final Color line;

  /// Yumuşak ayraç.
  final Color lineSoft;

  /// Birincil yazı — başlıklar, gövde.
  final Color ink;

  /// İkincil yazı — alt satırlar, ikonlar.
  final Color inkDim;

  /// Üçüncül yazı — meta bilgi, ipucu, saat etiketleri.
  final Color inkFaint;

  /// Tek vurgu rengi (bugün, seçim, bağlantı).
  final Color accent;

  /// Vurgunun yumuşak zemini (seçili hap, bilgi kutusu).
  final Color accentSoft;

  /// Vurgu zemininin üzerindeki yazı/ikon.
  final Color onAccent;

  /// İkincil vurgu — "açık/kaçan", en kötü gün, görev bağlantıları.
  final Color secondary;

  /// Dikkat (seri sayacı, kırık bağlantı).
  final Color warning;

  /// Geri alınamaz işlem.
  final Color danger;

  final Color gridDay;
  final Color gridWeekend;

  /// Saat diskinin zemini (gün görünümü).
  final Color clockFace;

  final Color gridHourLine;
  final Color gridHalfLine;
  final Color gridColumnLine;

  /// Bugünün sütununa binen çok hafif ton.
  final Color gridTodayWash;

  /// "Şu an" çizgisi.
  final Color nowLine;

  /// Sürüklerken bırakma hedefi.
  final Color dropTarget;

  /// Temas gölgesi: dar, yakın, biraz daha koyu.
  final Color shadowContact;

  /// Ortam gölgesi: geniş, uzak, çok soluk.
  final Color shadowAmbient;

  /// Neon parıltının rengi — vurgunun zemine sızması.
  ///
  /// Koyu temada derinliğin bir parçası: siyah zeminde gölge kaybolduğu için
  /// "öne çıkan" öğe, kendi rengiyle öne çıkar. Açık temada **tamamen saydam**;
  /// böylece aynı widget kodu iki temada da doğru davranır ve çağrı yerlerinde
  /// `isDark` koşulu yazmak gerekmez.
  final Color glowAccent;

  bool get isDark => brightness == Brightness.dark;

  // --- Hazır paletler --------------------------------------------------------

  /// Gece: mürekkep siyahı zemin + neon camgöbeği/magenta.
  ///
  /// Zemin neredeyse saf siyah. Bunun bir bedeli var ve tasarımın tamamını
  /// etkiliyor: **siyah zeminde siyah gölge hiçbir şeydir.** Kartları zeminden
  /// ayıran şey artık gölge değil, ince kenarlık ([line]) ve seçili öğelerde
  /// renk halesi ([glowAccent]). Gölgeler yalnız ekrandan gerçekten kopan
  /// katmanlarda (sheet, sürüklenen blok) anlamını koruyor.
  static const dark = AppPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF050507),
    surface: Color(0xFF0C0D11),
    surfaceAlt: Color(0xFF131419),
    hover: Color(0xFF1A1C23),
    sidebar: Color(0xFF000000),
    sidebarHover: Color(0xFF121318),
    navActiveFill: Color(0xFF07303A),
    navActiveInk: Color(0xFF67E8F9),
    line: Color(0xFF1E2028),
    lineSoft: Color(0xFF14161B),
    ink: Color(0xFFE8ECF2),
    inkDim: Color(0xFF99A1B3),
    inkFaint: Color(0xFF69707F),
    accent: Color(0xFF22D3EE),
    accentSoft: Color(0xFF08303A),
    onAccent: Color(0xFF041016),
    secondary: Color(0xFFF0ABFC),
    warning: Color(0xFFFDE047),
    danger: Color(0xFFFF4D6D),
    gridDay: Color(0xFF0C0D11),
    gridWeekend: Color(0xFF08090C),
    clockFace: Color(0xFF0E0F14),
    gridHourLine: Color(0xFF1C1F27),
    gridHalfLine: Color(0xFF121419),
    gridColumnLine: Color(0xFF171A21),
    gridTodayWash: Color(0x1422D3EE),
    // Doygun magenta. `danger`ın kırmızısından **renk tonuyla** ayrılıyor
    // (~38°), parlaklıkla değil: ikisi de aynı aydınlıkta ve "şu an" bir uyarı
    // değil, bir konum.
    nowLine: Color(0xFFFF2BD6),
    dropTarget: Color(0x3322D3EE),
    shadowContact: Color(0xB3000000),
    shadowAmbient: Color(0x80000000),
    glowAccent: Color(0x5922D3EE),
  );

  /// Gündüz: kâğıt beyazı kartlar, hafif soğuk gri zemin, **aynı camgöbeği**.
  ///
  /// T1 — bu palet uzun süre eski indigo/gül renklerinde kaldı; koyu tema
  /// N1–N4'te neon camgöbeği/magentaya geçerken buraya kimse dokunmadı ve iki
  /// tema farklı **marka** gibi görünmeye başladı. Tema değiştirmek bir tercih
  /// olmalı, başka bir uygulamaya geçmek değil.
  ///
  /// Koyu temanın rengi **kopyalanmadı**: `#22D3EE` beyaz kâğıtta 1.81:1 —
  /// WCAG AA metin eşiği 4.5:1. Onun yerine **ton açısı korunup parlaklık
  /// düşürüldü**; kimlik tonda taşınır, okunabilirlik parlaklıkta. Üç rolde de
  /// koyu ile açık arasındaki ton farkı 5°'nin altında.
  static const light = AppPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF7F8FC),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFFFFFF),
    hover: Color(0xFFF1F2F8),
    sidebar: Color(0xFFFFFFFF),
    sidebarHover: Color(0xFFF3F4FA),
    navActiveFill: Color(0xFFE6F6FA),
    navActiveInk: Color(0xFF0E7490),
    line: Color(0xFFE3E5EF),
    lineSoft: Color(0xFFEDEFF5),
    ink: Color(0xFF14161C),
    inkDim: Color(0xFF5A5F6E),
    inkFaint: Color(0xFF8B90A0),
    // Beyaz üstünde 5.36:1. Bir tık açığı (#0891B2) 3.68 ile eşiğin altında
    // kalıyor, bir tık koyusu (#155E75) geçiyor ama camgöbeği olmaktan çıkıp
    // laciverde dönüyor — kimliği taşımıyor.
    accent: Color(0xFF0E7490),
    accentSoft: Color(0xFFE6F6FA),
    onAccent: Color(0xFFFFFFFF),
    // Beyaz üstünde 6.32:1.
    secondary: Color(0xFFA21CAF),
    // `warning` ve `danger` markaya bağlanmaz: bunlar marka rengi değil,
    // evrensel işaret. Tema değişince anlamları değişmemeli.
    warning: Color(0xFFB45309),
    danger: Color(0xFFDC2626),
    gridDay: Color(0xFFFFFFFF),
    gridWeekend: Color(0xFFFAFBFE),
    clockFace: Color(0xFFFFFFFF),
    gridHourLine: Color(0xFFE7E9F1),
    gridHalfLine: Color(0xFFF2F3F8),
    gridColumnLine: Color(0xFFEDEFF6),
    gridTodayWash: Color(0x0F0E7490),
    // Metin değil konum çizgisi; eşik 3:1 ve bu 4.82:1. Koyu temadaki
    // magentanın (#FF2BD6) gündüz hâli — tondan 4° uzakta.
    nowLine: Color(0xFFD6009E),
    dropTarget: Color(0x330E7490),
    shadowContact: Color(0x14161C1F),
    shadowAmbient: Color(0x0D161C24),
    // Açıkta parıltı yok: beyaz kâğıt üstünde neon hale kir gibi durur ve
    // zaten gerek yok — gölge burada hâlâ çalışıyor.
    glowAccent: Color(0x00000000),
  );

  static AppPalette of(BuildContext context) {
    final theme = Theme.of(context);
    // Uzantı yoksa (ör. varsayılan MaterialApp teması) parlaklığa göre düş.
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  // --- Derinlik --------------------------------------------------------------

  /// Koyu temada yüzeyin kenarını çizen saç teli.
  ///
  /// Zemin siyaha inince gölge görünmez oldu — siyah üstüne siyah gölge hiçbir
  /// şeydir — ve kartlar zeminde yüzmeye başladı. Kenarı geri getirmenin iki
  /// yolu vardı: `border`'ı kart çizen on sekiz çağrı yerine tek tek eklemek,
  /// ya da onu derinliğin kendi tanımına koymak.
  ///
  /// İkincisi seçildi. Bulanıklığı sıfır, ofseti sıfır, yayılması küçük bir
  /// gölge tam olarak bir kenarlık gibi çizilir — üstelik kutunun köşe
  /// yarıçapını kendiliğinden takip ederek. Böylece kural tek yerde yaşıyor:
  /// "koyu temada yükseklik, kenarla anlatılır."
  ///
  /// Açık temada boş: orada gölge hâlâ işini yapıyor.
  List<BoxShadow> get _rim =>
      isDark ? [BoxShadow(color: line, spreadRadius: 0.6)] : const [];

  /// Zeminden hafifçe kalkan yüzey: kart, satır, hap.
  List<BoxShadow> get shadowSm => [
    ..._rim,
    BoxShadow(color: shadowContact, blurRadius: 2, offset: const Offset(0, 1)),
    BoxShadow(color: shadowAmbient, blurRadius: 8, offset: const Offset(0, 2)),
  ];

  /// Belirgin şekilde önde duran yüzey: seçili kart, açılır panel, FAB.
  List<BoxShadow> get shadowMd => [
    ..._rim,
    BoxShadow(color: shadowContact, blurRadius: 4, offset: const Offset(0, 2)),
    BoxShadow(color: shadowAmbient, blurRadius: 20, offset: const Offset(0, 8)),
  ];

  /// Ekrandan kopan katman: sürüklenen blok, sheet, dialog.
  ///
  /// Kenarlık **almıyor**: bu katman zaten ekrandan koptuğunu geniş gölgesiyle
  /// söylüyor ve koyu üstünde koyu ayrımı burada hâlâ okunuyor. Kenar eklemek
  /// onu kartlarla aynı dile indirirdi.
  List<BoxShadow> get shadowLg => [
    BoxShadow(color: shadowContact, blurRadius: 8, offset: const Offset(0, 4)),
    BoxShadow(
      color: shadowAmbient,
      blurRadius: 40,
      offset: const Offset(0, 18),
    ),
  ];

  /// Seçili / etkin öğenin altına düşen renk halesi (vurgu rengiyle).
  ///
  /// Üç yerde kullanılıyor, fazlasında değil: seçili gezinme öğesi, "şu an"
  /// çizgisi, sürüklenen blok. Parıltı her yere serpilirse neon olmaz,
  /// bulanıklık olur.
  List<BoxShadow> get glow => glowOf(accent);

  /// [tint] renginin halesi — "şu an" çizgisi magenta, sürüklenen blok kendi
  /// kategori rengiyle parlasın diye.
  ///
  /// Açık temada [glowAccent] tamamen saydam olduğundan buradan çıkan gölge de
  /// görünmez. Koşul yazmak yerine opaklığı paletten okumak bilinçli: çağrı
  /// yerleri `isDark` sormak zorunda kalmıyor.
  ///
  /// `spreadRadius` negatif: hale nesnenin kenarından **dışarı** taşsın ama
  /// altında kalan zemini boğmasın.
  List<BoxShadow> glowOf(Color tint) => [
    BoxShadow(
      color: tint.withValues(alpha: glowAccent.a),
      blurRadius: 24,
      spreadRadius: -4,
    ),
  ];

  // --- Türetilmiş stiller ----------------------------------------------------

  /// Yumuşak etiket: kategori rozetleri, saatsiz iş çipleri.
  ///
  /// Koyuda rengin kendisi yazı olarak okunur; açıkta aynı renk zemin üstünde
  /// yeterince koyulaştırılır (pastel kategori renkleri beyaz üstünde soluk
  /// kalıyordu).
  TagStyle tag(Color color, {bool selected = false}) {
    if (isDark) {
      return TagStyle(color.withValues(alpha: selected ? 0.26 : 0.15), color);
    }
    return TagStyle(
      Color.alphaBlend(
        color.withValues(alpha: selected ? 0.26 : 0.15),
        surface,
      ),
      Color.lerp(color, Colors.black, 0.55)!,
    );
  }

  /// Takvim ızgarasındaki etkinlik bloğu — sakin **renkli kart**.
  ///
  /// Dolu renk bloklar yerine: sol kenarda doygun bir şerit ([EventStyle.stripe])
  /// + gövdede aynı rengin çok düşük opaklıkta zemini. Yan yana duran altı dolu
  /// blok ekranı renk cümbüşüne çeviriyor, ızgaranın kendisi okunmuyordu. Renk
  /// kimliği şeritte yaşar; gövde sakin kalır.
  EventStyle event(Color color, {bool done = false}) {
    // Bloklar ızgara yaprağının (surface) üstünde durur; harmanlama o zemine
    // göre yapılır. Koyu tema daha çok opaklık ister — aynı oran orada
    // zeminden ayrışmıyor.
    final tintAlpha = isDark ? 0.20 : 0.13;
    final fill = Color.alphaBlend(color.withValues(alpha: tintAlpha), surface);

    if (done) {
      // Tamamlanan iş geri çekilir: zemin neredeyse yaprağa döner, şerit
      // solar, yazı ikincil olur. Üstü çizili başlık ve ✓ ikonu blokta.
      return EventStyle(
        fill: Color.lerp(fill, surface, 0.6)!,
        ink: inkDim,
        stripe: Color.lerp(color, surface, 0.55)!,
        edge: Color.lerp(fill, surface, 0.35)!,
      );
    }

    return EventStyle(
      fill: fill,
      ink: readableOn(color, fill),
      stripe: color,
      // Aynı renkli komşu bloklar birbirine akmasın diye ince ayrım: aynı
      // tonun bir kademe koyusu.
      edge: Color.alphaBlend(color.withValues(alpha: tintAlpha * 2), surface),
    );
  }

  /// [color]'ı [background] üzerinde okunur olana dek gövde mürekkebine doğru
  /// çeker ve AA eşiğini (4.5:1) geçen ilk tonu verir.
  ///
  /// Kategori rengini yazıda da kullanmak istiyoruz — bloğun rengini yalnız
  /// şeritten değil yazıdan da tanıyabilmek için. Ama pastel bir sarı, kendi
  /// soluk zemininde okunmaz. Sabit bir koyulaştırma oranı seçmek yerine eşiği
  /// hedefliyoruz: koyu bir mor zaten ilk adımda geçer, açık sarı birkaç adım
  /// daha iner. Böylece palete yeni bir renk eklendiğinde kural kendiliğinden
  /// tutar.
  ///
  /// Sonuç önbelleğe alınır: her etkinlik bloğu bunu her yeniden çiziminde
  /// çağırıyor ve sürükleme sırasında bu saniyede 60 kez oluyor. Girdiler
  /// (kategori paleti + tema) sonlu olduğundan önbellek birkaç girdide doyar.
  Color readableOn(Color color, Color background) {
    final key = Object.hash(color, background, ink);
    final cached = _readableCache[key];
    if (cached != null) return cached;

    // Zeminin parlaklığı döngü boyunca sabit — bir kez hesaplanır.
    final bgLuminance = background.computeLuminance();

    var result = ink;
    for (var step = 0; step <= 20; step++) {
      final candidate = Color.lerp(color, ink, step / 20)!;
      final l = candidate.computeLuminance();
      final ratio =
          ((l > bgLuminance ? l : bgLuminance) + 0.05) /
          ((l < bgLuminance ? l : bgLuminance) + 0.05);
      if (ratio >= 4.5) {
        result = candidate;
        break;
      }
    }
    return _readableCache[key] = result;
  }

  static final Map<int, Color> _readableCache = {};

  // --- ThemeExtension --------------------------------------------------------

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? hover,
    Color? sidebar,
    Color? sidebarHover,
    Color? navActiveFill,
    Color? navActiveInk,
    Color? line,
    Color? lineSoft,
    Color? ink,
    Color? inkDim,
    Color? inkFaint,
    Color? accent,
    Color? accentSoft,
    Color? onAccent,
    Color? secondary,
    Color? warning,
    Color? danger,
    Color? gridDay,
    Color? gridWeekend,
    Color? clockFace,
    Color? gridHourLine,
    Color? gridHalfLine,
    Color? gridColumnLine,
    Color? gridTodayWash,
    Color? nowLine,
    Color? dropTarget,
    Color? shadowContact,
    Color? shadowAmbient,
    Color? glowAccent,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      hover: hover ?? this.hover,
      sidebar: sidebar ?? this.sidebar,
      sidebarHover: sidebarHover ?? this.sidebarHover,
      navActiveFill: navActiveFill ?? this.navActiveFill,
      navActiveInk: navActiveInk ?? this.navActiveInk,
      line: line ?? this.line,
      lineSoft: lineSoft ?? this.lineSoft,
      ink: ink ?? this.ink,
      inkDim: inkDim ?? this.inkDim,
      inkFaint: inkFaint ?? this.inkFaint,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccent: onAccent ?? this.onAccent,
      secondary: secondary ?? this.secondary,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      gridDay: gridDay ?? this.gridDay,
      gridWeekend: gridWeekend ?? this.gridWeekend,
      clockFace: clockFace ?? this.clockFace,
      gridHourLine: gridHourLine ?? this.gridHourLine,
      gridHalfLine: gridHalfLine ?? this.gridHalfLine,
      gridColumnLine: gridColumnLine ?? this.gridColumnLine,
      gridTodayWash: gridTodayWash ?? this.gridTodayWash,
      nowLine: nowLine ?? this.nowLine,
      dropTarget: dropTarget ?? this.dropTarget,
      shadowContact: shadowContact ?? this.shadowContact,
      shadowAmbient: shadowAmbient ?? this.shadowAmbient,
      glowAccent: glowAccent ?? this.glowAccent,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      // Parlaklık ara değer almaz; yarıyı geçince karşıya döner.
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      hover: c(hover, other.hover),
      sidebar: c(sidebar, other.sidebar),
      sidebarHover: c(sidebarHover, other.sidebarHover),
      navActiveFill: c(navActiveFill, other.navActiveFill),
      navActiveInk: c(navActiveInk, other.navActiveInk),
      line: c(line, other.line),
      lineSoft: c(lineSoft, other.lineSoft),
      ink: c(ink, other.ink),
      inkDim: c(inkDim, other.inkDim),
      inkFaint: c(inkFaint, other.inkFaint),
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      onAccent: c(onAccent, other.onAccent),
      secondary: c(secondary, other.secondary),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      gridDay: c(gridDay, other.gridDay),
      gridWeekend: c(gridWeekend, other.gridWeekend),
      clockFace: c(clockFace, other.clockFace),
      gridHourLine: c(gridHourLine, other.gridHourLine),
      gridHalfLine: c(gridHalfLine, other.gridHalfLine),
      gridColumnLine: c(gridColumnLine, other.gridColumnLine),
      gridTodayWash: c(gridTodayWash, other.gridTodayWash),
      nowLine: c(nowLine, other.nowLine),
      dropTarget: c(dropTarget, other.dropTarget),
      shadowContact: c(shadowContact, other.shadowContact),
      shadowAmbient: c(shadowAmbient, other.shadowAmbient),
      glowAccent: c(glowAccent, other.glowAccent),
    );
  }
}

/// `context.colors` kısayolu.
extension AppPaletteContext on BuildContext {
  AppPalette get colors => AppPalette.of(this);
}

/// Yumuşak etiket zemini + okunur yazı rengi.
class TagStyle {
  const TagStyle(this.fill, this.text);
  final Color fill;
  final Color text;
}

/// Takvim bloğunun dolgusu, yazı rengi ve kenar tonu.
class EventStyle {
  const EventStyle({
    required this.fill,
    required this.ink,
    required this.stripe,
    required this.edge,
  });

  /// Gövde zemini — kategori renginin çok düşük opaklıkta izi.
  final Color fill;

  /// Blok içi yazı. [fill] üzerinde AA'yı geçmesi garanti.
  final Color ink;

  /// Sol kenardaki 3px doygun şerit — bloğun renk kimliği burada.
  final Color stripe;

  /// Kenarlık; yan yana duran aynı renkli iki bloğu ayırır.
  final Color edge;
}

/// Doygun bir renk zemininin üstüne konacak mürekkep.
///
/// Kategori renkleri kullanıcıdan geliyor: açık sarının üstünde beyaz yazı
/// okunmaz, koyu morun üstünde siyah okunmaz. Karar **temadan bağımsız** —
/// zemin o rengin kendisi, sayfanın zemini değil. Bu yüzden `AppPalette`'in
/// bir üyesi değil, serbest bir işlev.
///
/// Daha önce bu koşul dört ayrı dosyada elle yazılıydı; dördü de aynı `#14161C`
/// sabitini taşıyordu ve palet değişince hiçbiri haber almıyordu.
///
/// Seçim `ThemeData.estimateBrightnessForColor` ile yapılıyordu; N5b'de iki
/// adayın **ölçülen** kontrastına bakmaya geçti. Sezgi bir vekildi ve orta
/// parlaklıkta yanılıyordu: eşiği `(L+0.05)² > 0.15`, yani L≈0.337. Bunun
/// hemen altındaki doygun renklerde (eski pembe `#FF6090` L=0.32, mor
/// `#BA68C8` L=0.25, kırmızı `#E57373` L=0.30) beyaz mürekkep seçiliyor ve
/// oran 2.9–3.6'ya düşüyordu — hâlbuki aynı renklerde koyu mürekkep 5:1'i
/// geçiyor. Alışkanlık ekranındaki "bugün" düğmesi ve pasta dilimi etiketi
/// bu renklerde okunmuyordu.
///
/// Kalan boşluk: L≈0.18–0.21 aralığında iki aday da 4.5'in altında kalır
/// (en kötüsü 4.23). O bant paletin dışında; `category_colors_test.dart`
/// sekizini de her koşuda ölçüyor.
Color inkOn(Color background) {
  const white = Color(0xFFFFFFFF);
  final dark = AppPalette.light.ink;
  return contrastRatio(white, background) >= contrastRatio(dark, background)
      ? white
      : dark;
}

/// Rengi bilinmeyen bir kategori grafikte hangi renkle çizilir.
///
/// Rapor hizmeti bir `BuildContext` görmüyor (ve görmemeli), o yüzden bu değer
/// paletten okunamıyor; adı olan bir sabit, gövdeye gömülmüş bir hex'ten iyi.
///
/// N5a'da tonu neonlaştı (`#529CCA` → `#5AA9FF`) ama sabit kalmasının gerekçesi
/// değişmedi. Mavi kategoriden (`#38BDF8`) bir tık mora çekik: "rengi
/// bilinmeyen" dilim, mavi bir kategoriyle karışmasın.
const Color kUnknownCategoryColor = Color(0xFF5AA9FF);

/// Avatar rozetlerinin renk merdiveni (Y4.4c).
///
/// Renk **kimlikten** türer, addan değil: biri adını "Ali"den "Ali Okan"a
/// çevirdiğinde geçmiş haftalardaki bütün blokları renk değiştirseydi, kullanıcı
/// için sebepsiz bir kayma olurdu. Baş harf değişir (ad değişti), renk kalır
/// (kişi değişmedi).
///
/// Renkler **temadan bağımsız**: rozet opak bir daire, yani kontrast yalnız
/// dolgu ile mürekkep arasında — sayfanın zeminiyle ilgisi yok. Aynı kişi açık
/// ve koyu temada aynı renkte görünür, ki iki temayı yan yana açan biri aynı
/// kişiyi iki farklı insan sanmasın.
///
/// Orta tonlar seçildi: [inkOn] hepsinde koyu mürekkebi seçiyor ve dokuzunun
/// dokuzu da AA eşiğini (4.5:1) geçiyor — `avatar_test.dart` bunu her koşuda
/// yeniden ölçüyor.
const List<Color> kAvatarColors = [
  Color(0xFF7FB2E5), // mavi
  Color(0xFF74C7A8), // deniz yeşili
  Color(0xFFE0A379), // kiremit
  Color(0xFFB49BDE), // mor
  Color(0xFFE895A6), // gül
  Color(0xFF6FC3D2), // camgöbeği
  Color(0xFFCBBE72), // hardal
  Color(0xFFA8B3C4), // kurşun
];

/// Kimlikten sabit bir renk seçer.
///
/// `hashCode` **kullanılmıyor**: Dart'ta dize hash'i çalışma zamanları arasında
/// değişebilir ve aynı kişi bir gün mavi, ertesi gün mor olurdu. Basit ve
/// kararlı bir toplam yeterli — burada aranan dağılım kalitesi değil, aynı
/// girdinin her zaman aynı çıktıyı vermesi.
Color avatarColorFor(String userId) {
  if (userId.isEmpty) return kAvatarColors.last;
  var sum = 0;
  for (final unit in userId.codeUnits) {
    sum = (sum + unit) % 1000003;
  }
  return kAvatarColors[sum % kAvatarColors.length];
}

/// Rozetin gerçek rengi: **seçim varsa seçim, yoksa kimlik** (Karar C).
///
/// İki kaynağı tek yerde birleştiriyor ki "kullanıcı rengini seçti mi"
/// sorusunu rozet çizen her yer ayrı ayrı sormasın. `avatarColorFor` tek
/// başına da duruyor: kimliği olan ama profili hiç bilinmeyen biri (henüz
/// inmemiş bir grup arkadaşı) yine de kararlı bir renk almalı.
///
/// Modül alınıyor: sunucudan gelen sıra, listeye sonradan renk eklenip
/// çıkarılırsa aralık dışına düşebilir. Aralık dışı bir sayı yüzünden rozetin
/// çizilmemesi (ve o satırın çökmesi) kabul edilemez bir bedel.
Color avatarColorOf(Profile? profile, String? userId) {
  final chosen = profile?.avatarColor;
  if (chosen != null) return kAvatarColors[chosen.abs() % kAvatarColors.length];
  return avatarColorFor(userId ?? '');
}

/// WCAG 2.1 kontrast oranı (1:1 – 21:1).
///
/// Palette'in kendi içinde duruyor çünkü [AppPalette.readableOn] buna dayanıyor:
/// blok yazısının okunurluğu bir test kuralı değil, rengi üreten kodun parçası.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la < lb ? la : lb) + 0.05);
}
