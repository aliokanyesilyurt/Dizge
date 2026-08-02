import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../data/persistence_providers.dart';

/// Tema tercihinin saklandığı anahtar. Kullanıcı verisiyle aynı şifreli
/// kutuda durur; ayrı bir tercih dosyası açmaya değmez.
const String kThemeModeKey = 'settings.themeMode';

/// Açık / koyu / sistem tercihini tutar ve **anında** diske yazar.
///
/// Neden ayrı bir controller: tema, uygulamanın ilk karesinde gerekli. Store'un
/// anlık görüntüsüne (snapshot) koysaydık, tercih yalnızca veriyle birlikte
/// yüklenir ve "Hesap → Görünüm" ekranındaki değişiklik debounce penceresi
/// dolana kadar diske inmezdi.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._store) : super(_read(_store));

  final LocalStore _store;

  static ThemeMode _read(LocalStore store) {
    // Depo henüz açılmamışsa (ya da bozuksa) sistem tercihine düş.
    try {
      return _decode(store.readString(kThemeModeKey));
    } catch (_) {
      return ThemeMode.system;
    }
  }

  static ThemeMode _decode(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await _store.writeString(kThemeModeKey, _encode(mode));
  }

  /// Kenar çubuğundaki tek dokunuşluk anahtar: açık ↔ koyu.
  ///
  /// [platformBrightness] yalnızca tercih "sistem" iken kullanılır — o durumda
  /// kullanıcı görünenin *tersini* bekler.
  Future<void> toggle(Brightness platformBrightness) {
    final showingDark = switch (state) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformBrightness == Brightness.dark,
    };
    return set(showingDark ? ThemeMode.light : ThemeMode.dark);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(ref.watch(localStoreProvider)),
);
