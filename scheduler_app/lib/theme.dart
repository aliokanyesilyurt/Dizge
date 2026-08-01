import 'package:flutter/material.dart';

/// Notion'ın koyu modundan esinlenen nötr palet.
class AppColors {
  static const bg = Color(0xFF191919); // sayfa zemini
  static const surface = Color(0xFF202020); // kart / girdi zemini
  static const surfaceAlt = Color(0xFF252525); // sheet / dialog
  static const hover = Color(0xFF2C2C2C); // dokunma / seçim zemini

  static const line = Color(0xFF373737); // belirgin kenarlık, ızgara
  static const lineSoft = Color(0xFF2A2A2A); // yumuşak ayraç

  static const ink = Color(0xFFECECEA); // ana yazı
  static const inkDim = Color(0xFFB4B3AF); // ikincil yazı
  static const inkFaint = Color(0xFF8A8A88); // ipucu / placeholder

  static const blue = Color(0xFF529CCA); // Notion mavisi (vurgu)
  static const pink = Color(0xFFC9769B); // hafta sonu / bugün
  static const amber = Color(0xFFC99C6B); // tarih rakamları

  // --- Kenar çubuğu ---
  static const sidebar = Color(0xFF141414); // çubuk zemini
  static const sidebarHover = Color(0xFF232323); // üzerine gelme
  static const sidebarActive = Color(0xFF2E2E2E); // seçili öğe hapı

  // --- Takvim: her gün zeminden ayrı, yumuşak köşeli bir kutu ---
  static const gridDay = Color(0xFF212121); // hafta içi gün kutusu
  static const gridWeekend = Color(0xFF1A1A1A); // hafta sonu (bir tık koyu)

  static const clockFace = Color(0xFF2A2A2A); // saat diski (zeminden önde)

  // --- Haftalık zaman ızgarası (Google Takvim tarzı) ---
  static const gridHourLine = Color(0xFF2E2E2E); // tam saat çizgisi
  static const gridHalfLine = Color(0xFF242424); // yarım saat (daha soluk)
  static const gridColumnLine = Color(0xFF2A2A2A); // günleri ayıran dikey çizgi
  static const gridTodayWash = Color(0x14529CCA); // bugünün sütununa hafif ton
  static const nowLine = Color(0xFFE5484D); // "şu an" çizgisi
  static const dropTarget = Color(0x3352A0CA); // sürüklerken bırakma hedefi
}

/// Izgara yoğunluğu: bir saatin kaç piksel yer kapladığı. Kullanıcı başlıktaki
/// düğmeyle değiştirir; tercih oturum boyunca korunur.
enum GridDensity {
  compact(36.0, 'Sıkışık'),
  cozy(56.0, 'Normal'),
  spacious(84.0, 'Geniş');

  const GridDensity(this.hourHeight, this.label);
  final double hourHeight;
  final String label;

  GridDensity get next => GridDensity.values[(index + 1) % GridDensity.values.length];
}

/// Saat sütununun genişliği. Başlık satırı ile ızgaranın hizalı kalması için
/// ikisi de bu sabiti kullanır.
const double kTimeGutterWidth = 54.0;

/// Web fontu indirmeye gerek kalmadan her platformda okunur duran yığın.
/// CanvasKit bilinmeyen aileleri gömülü Roboto'ya düşürür.
const String kFontFamily = 'Segoe UI';
const List<String> kFontFallback = [
  'Inter',
  'Roboto',
  'Helvetica Neue',
  'Arial',
  'sans-serif',
];

/// Seçili gezinme öğesinin arkasındaki yumuşak renk geçişi.
const kActiveGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFF2F3B47), Color(0xFF2A2A2A)],
);

/// Notion etiketleri gibi: yumuşak zemin + okunur yazı rengi.
class TagStyle {
  final Color fill;
  final Color text;
  const TagStyle(this.fill, this.text);
}

/// Bir kategori renginden Notion tarzı etiket zemini üretir.
TagStyle tagStyleFor(Color color, {bool selected = false}) => TagStyle(
      color.withValues(alpha: selected ? 0.28 : 0.16),
      color,
    );

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.blue,
    brightness: Brightness.dark,
  ).copyWith(
    surface: AppColors.surface,
    primary: AppColors.blue,
    secondary: AppColors.pink,
    onPrimary: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    splashFactory: InkSparkle.splashFactory,
    fontFamily: kFontFamily,
    fontFamilyFallback: kFontFallback,
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        color: AppColors.ink,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        color: AppColors.ink,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: TextStyle(
        color: AppColors.ink,
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
      bodySmall: TextStyle(
        color: AppColors.inkDim,
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w500,
      ),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.lineSoft,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: AppColors.inkDim, size: 20),
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceAlt,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfaceAlt,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: AppColors.inkFaint,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.inkDim),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.blue,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.inkDim,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.blue : AppColors.hover,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}
