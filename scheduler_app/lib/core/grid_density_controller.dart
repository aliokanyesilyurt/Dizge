import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../data/persistence_providers.dart';
import '../theme.dart';

/// Izgara yoğunluğu tercihinin saklandığı anahtar. Tema kipiyle aynı şifreli
/// kutuda durur; ayrı bir tercih dosyası açmaya değmez.
const String kGridDensityKey = 'settings.gridDensity';

/// Saat satırlarının yüksekliğini belirleyen tercihi tutar ve **anında** diske
/// yazar.
///
/// Neden [ThemeModeController] deseni: yoğunluk da ilk karede gerekli. Store'un
/// anlık görüntüsüne koysaydık, tercih yalnızca veriyle birlikte yüklenir ve
/// ekran önce yanlış yoğunlukla çizilip sonra zıplardı.
class GridDensityController extends StateNotifier<GridDensity> {
  GridDensityController(this._store) : super(_read(_store));

  final LocalStore _store;

  static GridDensity _read(LocalStore store) {
    // Depo henüz açılmamışsa (ya da bozuksa) ortadaki seçeneğe düş.
    try {
      return _decode(store.readString(kGridDensityKey));
    } catch (_) {
      return GridDensity.cozy;
    }
  }

  /// Enum adı diske yazılıyor, `index` değil: ileride enum'a yeni bir kademe
  /// eklenirse index'ler kayar ve kullanıcının tercihi sessizce başka bir
  /// yoğunluğa dönüşürdü.
  static GridDensity _decode(String? raw) {
    for (final density in GridDensity.values) {
      if (density.name == raw) return density;
    }
    return GridDensity.cozy;
  }

  Future<void> set(GridDensity density) async {
    if (density == state) return;
    state = density;
    await _store.writeString(kGridDensityKey, density.name);
  }
}

final gridDensityProvider =
    StateNotifierProvider<GridDensityController, GridDensity>(
      (ref) => GridDensityController(ref.watch(localStoreProvider)),
    );
