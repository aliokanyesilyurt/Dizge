import 'package:flutter/material.dart';

/// Uygulamanın tasarım sistemi: renk, derinlik, yuvarlaklık, tipografi.
///
/// Mimari karar: renkler artık `static const` **değil**. Açık ve koyu tema aynı
/// anda var olabilmeli, tema değişince ağaç kendiliğinden yeniden çizilmeli.
/// Bu yüzden palet bir [ThemeExtension] olarak taşınır ve widget'lar onu
/// `context.colors` üzerinden okur:
///
/// ```dart
/// final c = context.colors;
/// Container(color: c.surface, ...)
/// ```
///
/// ## Tasarım yönü
///
/// Sakin, derinlikli ve minimal. Üç ilke:
///
/// 1. **Zemin geri çekilir, içerik öne çıkar.** Kartlar zeminden bir tık
///    *ileri* durur. Açık temada bunu yükseklik (gölge) söyler; koyu temada
///    zemin neredeyse saf siyah olduğu için gölge işe yaramaz ve görevi ince
///    bir kenar çizgisi devralır (bkz. [AppPalette.shadowSm]).
/// 2. **İki neon vurgu.** Camgöbeği birincil (bugün, seçim, bağlantı),
///    magenta ikincil (kaçan iş, "şu an"). Geri kalan her şey nötr gri
///    skalasında; renk yalnızca kullanıcının kendi kategorilerine ait.
/// 3. **Derinlik ışıktır.** Açıkta iki katmanlı gölge: dar/koyu (temas) +
///    geniş/soluk (ortam). Koyuda ise öne çıkan öğe kendi rengiyle çıkar —
///    [glow]. Parıltı üç yerle sınırlı; her yere serpilirse neon olmaz.
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
/// okunmaz, koyu morun üstünde siyah okunmaz. Karar rengin kendi parlaklığına
/// bakarak veriliyor ve **temadan bağımsız** — zemin o rengin kendisi, sayfanın
/// zemini değil. Bu yüzden `AppPalette`'in bir üyesi değil, serbest bir işlev.
///
/// Daha önce bu koşul dört ayrı dosyada elle yazılıydı; dördü de aynı `#14161C`
/// sabitini taşıyordu ve palet değişince hiçbiri haber almıyordu.
Color inkOn(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? const Color(0xFFFFFFFF)
    : AppPalette.light.ink;

/// Rengi bilinmeyen bir kategori grafikte hangi renkle çizilir.
///
/// Rapor hizmeti bir `BuildContext` görmüyor (ve görmemeli), o yüzden bu değer
/// paletten okunamıyor; adı olan bir sabit, gövdeye gömülmüş bir hex'ten iyi.
const Color kUnknownCategoryColor = Color(0xFF529CCA);

/// WCAG 2.1 kontrast oranı (1:1 – 21:1).
///
/// Palette'in kendi içinde duruyor çünkü [AppPalette.readableOn] buna dayanıyor:
/// blok yazısının okunurluğu bir test kuralı değil, rengi üreten kodun parçası.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la < lb ? la : lb) + 0.05);
}

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

/// Tipografi hiyerarşisi.
///
/// Dört kademe var ve her kademenin tek bir işi var:
///   * **display** — ekranın adı / tarih aralığı. Sıkı harf aralığı, ağır.
///   * **title**   — kart ve bölüm başlıkları.
///   * **body**    — okunacak metin.
///   * **meta**    — saat, sayaç, etiket. Küçük, açık renk, hafif geniş aralık.
TextTheme _buildTextTheme(AppPalette p) {
  return TextTheme(
    displaySmall: TextStyle(
      color: p.ink,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      height: 1.15,
    ),
    headlineSmall: TextStyle(
      color: p.ink,
      fontSize: 21,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      height: 1.2,
    ),
    titleLarge: TextStyle(
      color: p.ink,
      fontSize: 17,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleMedium: TextStyle(
      color: p.ink,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    ),
    titleSmall: TextStyle(
      color: p.ink,
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(
      color: p.ink,
      fontSize: 15,
      height: 1.45,
      fontWeight: FontWeight.w500,
    ),
    bodyMedium: TextStyle(
      color: p.ink,
      fontSize: 14,
      height: 1.45,
      fontWeight: FontWeight.w500,
    ),
    bodySmall: TextStyle(
      color: p.inkDim,
      fontSize: 12.5,
      height: 1.4,
      fontWeight: FontWeight.w500,
    ),
    labelLarge: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    labelMedium: TextStyle(
      color: p.inkFaint,
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    ),
    labelSmall: TextStyle(
      color: p.inkFaint,
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    ),
  );
}

/// Uygulama temasını verilen parlaklık için kurar.
///
/// Varsayılanın koyu olması bilinçli: testler ve eski çağrılar `buildAppTheme()`
/// diyor ve uygulamanın kimliği koyu temada tanımlandı.
ThemeData buildAppTheme({Brightness brightness = Brightness.dark}) {
  final p = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;

  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: brightness,
      ).copyWith(
        surface: p.surface,
        onSurface: p.ink,
        primary: p.accent,
        onPrimary: p.onAccent,
        secondary: p.secondary,
        outline: p.line,
        outlineVariant: p.lineSoft,
        error: p.danger,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [p],
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    splashFactory: InkSparkle.splashFactory,
    fontFamily: kFontFamily,
    fontFamilyFallback: kFontFallback,
    textTheme: _buildTextTheme(p),
    iconTheme: IconThemeData(color: p.inkDim, size: 20),
    dividerTheme: DividerThemeData(color: p.lineSoft, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      iconTheme: IconThemeData(color: p.inkDim, size: 20),
      titleTextStyle: TextStyle(
        color: p.ink,
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surfaceAlt,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: R.radiusLg),
      titleTextStyle: TextStyle(
        color: p.ink,
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      contentTextStyle: TextStyle(
        color: p.inkDim,
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
        fontSize: 14,
        height: 1.5,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surfaceAlt,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      dragHandleColor: p.line,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.lg)),
      ),
    ),
    // Bildirim ve ipucu her iki temada da **koyu** yüzeydir: sayfanın üstünde
    // duran geçici bir katman, sayfanın rengini değil kendi rengini taşır.
    // Değerler koyu paletten okunuyor; daha önce elle yazılmışlardı ve palet
    // değişince eski tonlarda kalıyorlardı.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppPalette.dark.surfaceAlt,
      contentTextStyle: TextStyle(
        color: AppPalette.dark.ink,
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: R.radiusSm),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        elevation: 0,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: R.radiusPill),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        shape: RoundedRectangleBorder(borderRadius: R.radiusPill),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: R.radiusPill),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(borderRadius: R.radiusPill),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: p.inkDim,
        highlightColor: p.hover,
        shape: const CircleBorder(),
      ),
    ),
    // FAB ekrandan kopar: tek yükseltilmiş, renkli nesne olduğu için gölgesi
    // korunuyor (diğer düğmeler düz).
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.accent,
      foregroundColor: p.onAccent,
      elevation: 4,
      focusElevation: 6,
      hoverElevation: 8,
      highlightElevation: 2,
      extendedTextStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
      ),
      shape: RoundedRectangleBorder(borderRadius: R.radiusMd),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.onAccent : p.inkFaint,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.hover,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: p.hover,
      thumbColor: p.accent,
      overlayColor: p.accent.withValues(alpha: 0.12),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: p.surface,
        foregroundColor: p.inkDim,
        selectedBackgroundColor: p.accentSoft,
        selectedForegroundColor: p.navActiveInk,
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(borderRadius: R.radiusPill),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.isDark ? p.hover : AppPalette.dark.surfaceAlt,
        borderRadius: R.radiusXs,
      ),
      textStyle: TextStyle(
        color: AppPalette.dark.ink,
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
        fontSize: 12,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.isDark ? p.surfaceAlt : p.hover,
      hintStyle: TextStyle(color: p.inkFaint, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: R.radiusSm,
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: R.radiusSm,
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: R.radiusSm,
        borderSide: BorderSide(color: p.accent, width: 1.5),
      ),
    ),
  );
}
