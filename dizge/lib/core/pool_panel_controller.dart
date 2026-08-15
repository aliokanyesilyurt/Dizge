import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../data/persistence_providers.dart';

/// Havuz panelinin açık mı daraltılmış mı olduğunu saklayan anahtar.
const String kPoolPanelKey = 'settings.poolPanelOpen';

/// "Kenarda Bekleyenler" paneli açık mı?
///
/// Yoğunluk ve tema gibi kalıcı bir yerleşim tercihi — enerji filtresinden
/// farklı olarak güne bağlı değil: paneli kapatan biri onu yarın da kapalı
/// ister.
///
/// Varsayılan **kapalı**. Havuzu hiç kullanmayan birinin ekranından 240 piksel
/// götürmek, kullanan birinin bir kez tıklamasından pahalı.
class PoolPanelController extends StateNotifier<bool> {
  PoolPanelController(this._store) : super(_read(_store));

  final LocalStore _store;

  static bool _read(LocalStore store) {
    try {
      return store.readString(kPoolPanelKey) == 'open';
    } catch (_) {
      return false;
    }
  }

  Future<void> set(bool open) async {
    if (open == state) return;
    state = open;
    await _store.writeString(kPoolPanelKey, open ? 'open' : 'closed');
  }

  Future<void> toggle() => set(!state);
}

final poolPanelOpenProvider = StateNotifierProvider<PoolPanelController, bool>(
  (ref) => PoolPanelController(ref.watch(localStoreProvider)),
);
