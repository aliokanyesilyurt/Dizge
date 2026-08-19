/// Belirteçlerle paleti [ThemeData]'ya bağlayan kurulum.
library;

import 'package:flutter/material.dart';

import 'palette.dart';
import 'tokens.dart';

/// Tipografi hiyerarşisi — boyları [T] ölçeğinden okur.
///
/// Material'ın rol adları korunuyor (`headlineSmall`, `bodyMedium`…) çünkü
/// Flutter'ın kendi bileşenleri onları arıyor. Ama **boy artık burada
/// seçilmiyor**: her rol [T]'nin bir kademesine bağlı. Ağırlık, harf aralığı
/// ve satır yüksekliği role özgü kalıyor — ölçeğin verdiği şey boy.
///
/// Roller kademelere şöyle oturuyor:
///   * **displaySmall** → [T.display] — ekranın adı / tarih aralığı.
///   * **headlineSmall** → [T.headline] — bölüm başlığı (`SectionHeader`).
///   * **titleLarge / titleMedium / titleSmall** → [T.title] · [T.strong] ·
///     [T.body] — panel, kart ve satır başlıkları.
///   * **body\*** → [T.strong] · [T.caption] — okunacak metin.
///   * **label\*** → [T.strong] · [T.micro] — saat, sayaç, etiket.
///
/// `bodyLarge` ile `bodyMedium`ın aynı kademeye düşmesi bilinçli: ikisinin
/// arasındaki eski 1 punto fark hiçbir yerde bir hiyerarşi anlatmıyordu.
TextTheme _buildTextTheme(AppPalette p) {
  return TextTheme(
    displaySmall: TextStyle(
      color: p.ink,
      fontSize: T.display,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      height: 1.15,
    ),
    headlineSmall: TextStyle(
      color: p.ink,
      fontSize: T.headline,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      height: 1.2,
    ),
    titleLarge: TextStyle(
      color: p.ink,
      fontSize: T.title,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleMedium: TextStyle(
      color: p.ink,
      fontSize: T.strong,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    ),
    titleSmall: TextStyle(
      color: p.ink,
      fontSize: T.body,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(
      color: p.ink,
      fontSize: T.strong,
      height: 1.45,
      fontWeight: FontWeight.w500,
    ),
    bodyMedium: TextStyle(
      color: p.ink,
      fontSize: T.strong,
      height: 1.45,
      fontWeight: FontWeight.w500,
    ),
    bodySmall: TextStyle(
      color: p.inkDim,
      fontSize: T.caption,
      height: 1.4,
      fontWeight: FontWeight.w500,
    ),
    labelLarge: const TextStyle(
      fontSize: T.strong,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    labelMedium: TextStyle(
      color: p.inkFaint,
      fontSize: T.micro,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    ),
    labelSmall: TextStyle(
      color: p.inkFaint,
      fontSize: T.micro,
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
    iconTheme: IconThemeData(color: p.inkDim, size: I.md),
    dividerTheme: DividerThemeData(color: p.lineSoft, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      iconTheme: IconThemeData(color: p.inkDim, size: I.md),
      titleTextStyle: TextStyle(
        color: p.ink,
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
        fontSize: T.strong,
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
        fontSize: T.title,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      contentTextStyle: TextStyle(
        color: p.inkDim,
        fontFamily: kFontFamily,
        fontFamilyFallback: kFontFallback,
        fontSize: T.strong,
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
        fontSize: T.body,
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
        textStyle: const TextStyle(
          fontSize: T.strong,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: R.radiusPill),
        padding: const EdgeInsets.symmetric(horizontal: S.xl, vertical: S.lg),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        shape: RoundedRectangleBorder(borderRadius: R.radiusPill),
        padding: const EdgeInsets.symmetric(horizontal: S.xl, vertical: S.lg),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        textStyle: const TextStyle(
          fontSize: T.strong,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: R.radiusPill),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(borderRadius: R.radiusPill),
        padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.md),
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
        fontSize: T.strong,
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
        fontSize: T.caption,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.isDark ? p.surfaceAlt : p.hover,
      hintStyle: TextStyle(color: p.inkFaint, fontSize: T.strong),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: S.md,
        vertical: S.md,
      ),
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
