import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme.dart';

/// `AppPalette` ile `shadcn_ui` arasındaki tek köprü.
///
/// ## Neden var
///
/// İki paralel renk sistemi tutmak kaçınılmaz olarak tutarsızlık üretir: biri
/// güncellenir, diğeri unutulur. Bu yüzden **kaynak tek**: [AppPalette]. Shadcn
/// bileşenlerinin okuduğu [ShadColorScheme] buradan *türetilir*, elle ikinci bir
/// palet yazılmaz.
///
/// Pratik sonucu: kenar çubuğundaki tema anahtarı bir kez çevrildiğinde hem
/// uygulamanın kendi widget'ları hem de Shad bileşenleri aynı anda döner.
///
/// ## Eşleme mantığı
///
/// Shadcn'in jeton adları web kökenli (`card`, `popover`, `muted`); bizimkiler
/// katman kökenli (`surface`, `surfaceAlt`, `hover`). Eşleme *anlama* göre
/// yapılır, isme göre değil:
///
///   * `card`    → `surface`    — zeminden bir kat ileri duran içerik yüzeyi
///   * `popover` → `surfaceAlt` — en öndeki katman (sheet, açılır menü)
///   * `muted`   → `hover`      — vurgusuz, geri çekilmiş zemin
ShadThemeData shadThemeFrom(AppPalette p) {
  return ShadThemeData(
    brightness: p.brightness,
    colorScheme: _schemeFrom(p),
    // Yuvarlaklık tek ölçekten okunur; shadcn'in kendi varsayılanı (8px)
    // devreye girerse kart ile blok arasındaki hiyerarşi bozulur.
    radius: R.radiusSm,
    // Renkte olduğu gibi tipografide de kaynak tek. Bu satır olmasaydı Shad
    // bileşenleri kendi varsayılan ailesinde kalır, ızgaranın hemen yanında
    // farklı bir yazı tipiyle görünürlerdi.
    textTheme: ShadTextTheme(family: kFontFamily)
        .apply(fontFamilyFallback: kFontFallback),
  );
}

ShadColorScheme _schemeFrom(AppPalette p) => ShadColorScheme(
      background: p.bg,
      foreground: p.ink,

      card: p.surface,
      cardForeground: p.ink,

      popover: p.surfaceAlt,
      popoverForeground: p.ink,

      // Birincil eylem = uygulamanın tek vurgu rengi (indigo).
      primary: p.accent,
      primaryForeground: p.onAccent,

      // İkincil eylem: dolu ama sessiz — zemin bir kat ileri, yazı ikincil.
      secondary: p.surfaceAlt,
      secondaryForeground: p.inkDim,

      muted: p.hover,
      mutedForeground: p.inkFaint,

      // Shadcn'de `accent` "üzerine gelinen / seçili öğe zemini" demek,
      // bizim `accent`imiz gibi doygun bir vurgu değil. Bu yüzden çapraz
      // eşleniyor: zemin `accentSoft`, üzerindeki yazı `accent`.
      accent: p.accentSoft,
      accentForeground: p.accent,

      destructive: p.danger,
      destructiveForeground: p.onAccent,

      border: p.line,
      input: p.lineSoft,
      ring: p.accent,

      selection: p.accentSoft,
    );
