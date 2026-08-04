import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../data/persistence_providers.dart';
import '../models/node.dart';
import '../models/task.dart';

/// "Bugün enerjim" tercihinin saklandığı anahtar. Değer `gün|kademe` biçiminde
/// yazılır — neden gün de yazıldığı için bkz. [EnergyFilterController].
const String kEnergyFilterKey = 'settings.energyToday';

/// Kullanıcının o günkü enerjisini tutar; ızgara bunun üstündeki eforları
/// soluklaştırır.
///
/// **Tercih güne bağlı.** [GridDensityController]'dan ayrılan tek yeri burası:
/// yoğunluk kalıcı bir zevk, enerji ise günün hâli. Süresiz saklansaydı dün
/// akşam "deşarj" işaretleyen biri ertesi sabah uygulamayı yarısı solmuş bir
/// takvimle açar ve nedenini bulamazdı. Bu yüzden değerin yanına yazıldığı gün
/// de kaydediliyor; gün değişince filtre kendiliğinden kalkıyor.
///
/// Gün içinde ise kalıcı: uygulama kapanıp açılsa da seçim yerinde durur.
class EnergyFilterController extends StateNotifier<Energy?> {
  EnergyFilterController(this._store) : super(_read(_store));

  final LocalStore _store;

  static Energy? _read(LocalStore store) {
    try {
      return _decode(store.readString(kEnergyFilterKey));
    } catch (_) {
      return null;
    }
  }

  /// `gün|kademe` çözümü. Eksik, bozuk ya da **başka bir güne ait** kayıt
  /// "filtre yok" demek.
  static Energy? _decode(String? raw, {DateTime? now}) {
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.length != 2) return null;
    if (parts.first != dateToKey(now ?? DateTime.now())) return null;
    return Energy.byName(parts.last);
  }

  Future<void> set(Energy? energy) async {
    if (energy == state) return;
    state = energy;
    await _store.writeString(
      kEnergyFilterKey,
      energy == null ? '' : '${dateToKey(DateTime.now())}|${energy.name}',
    );
  }

  /// Testlerin çözümlemeyi sabit bir "bugün" ile sınayabilmesi için.
  @visibleForTesting
  static Energy? decodeForTest(String? raw, DateTime now) =>
      _decode(raw, now: now);
}

final energyFilterProvider =
    StateNotifierProvider<EnergyFilterController, Energy?>(
      (ref) => EnergyFilterController(ref.watch(localStoreProvider)),
    );
