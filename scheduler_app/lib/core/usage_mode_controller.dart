import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../data/persistence_providers.dart';

/// Kullanım modu tercihinin saklandığı anahtar. Tema tercihi gibi, kullanıcı
/// verisiyle aynı şifreli kutuda durur.
const String kUsageModeKey = 'settings.usageMode';

/// Görev yazmanın hangi yoldan gideceği.
///
/// Bu bir "tema" değil, bir **giriş yöntemi** tercihi: uygulamanın hangi
/// parçalarının görüneceğini değil, yeni bir iş eklerken önce neyin açılacağını
/// belirler. Ekranların hiçbiri kaybolmaz.
enum UsageMode {
  /// Bugünkü davranış: klavye. Ajanda sekmesi görünmez.
  klasik('Klasik', 'Klavyeyle yaz — bugünkü davranış'),

  /// Kalem önde: yeni iş eklemek önce ajanda sayfasını açar, klavye bir tık
  /// uzakta kalır.
  ajanda('Ajanda', 'Kalemle yaz, uygulama okusun'),

  /// İkisi de erişilebilir; kullanıcı her seferinde seçer.
  karma('Karma', 'İkisi de elinin altında');

  const UsageMode(this.label, this.description);

  final String label;
  final String description;

  /// Ajanda yüzeyi bu modda erişilebilir mi.
  bool get showsAgenda => this != UsageMode.klasik;

  /// Yeni iş eklerken **önce** ajanda mı açılır.
  ///
  /// Karma modda hayır: orada kullanıcı her seferinde seçer, uygulama onun
  /// yerine karar vermez.
  bool get opensAgendaFirst => this == UsageMode.ajanda;
}

/// Kullanım modu tercihini tutar ve **anında** diske yazar.
///
/// Neden ayrı bir controller — [ThemeModeController] ile aynı gerekçe: bu
/// tercih uygulamanın ilk karesinde gerekli (kenar çubuğunda ajanda sekmesinin
/// olup olmadığını belirliyor). Store'un anlık görüntüsüne koysaydık tercih
/// yalnızca veriyle birlikte yüklenir, değişiklik de debounce penceresi
/// dolana kadar diske inmezdi.
class UsageModeController extends StateNotifier<UsageMode> {
  UsageModeController(this._store) : super(_read(_store));

  final LocalStore _store;

  static UsageMode _read(LocalStore store) {
    // Depo henüz açılmamışsa (ya da bozuksa) varsayılana düş.
    try {
      return decode(store.readString(kUsageModeKey));
    } catch (_) {
      return UsageMode.karma;
    }
  }

  /// Varsayılanın **karma** olması bilinçli: mevcut kullanıcının alışkanlığı
  /// bozulmaz (klavye hâlâ orada), yeni yol da keşfedilebilir kalır. Tanınmayan
  /// bir değer de buraya düşer — ileride bir mod kaldırılırsa kimse kilitli
  /// kalmaz.
  static UsageMode decode(String? raw) =>
      UsageMode.values.where((m) => m.name == raw).firstOrNull ??
      UsageMode.karma;

  static String encode(UsageMode mode) => mode.name;

  Future<void> set(UsageMode mode) async {
    if (mode == state) return;
    state = mode;
    await _store.writeString(kUsageModeKey, encode(mode));
  }
}

final usageModeProvider = StateNotifierProvider<UsageModeController, UsageMode>(
  (ref) => UsageModeController(ref.watch(localStoreProvider)),
);
