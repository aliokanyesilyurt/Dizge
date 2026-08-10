import '../app_store.dart';
import 'outbox.dart';
import 'remote_gateway.dart';

/// Oturum ilk açıldığında yerel takvim ile sunucunun karşılaşma biçimi.
enum FirstSyncPlan {
  /// İki taraf da boş — yapacak bir şey yok.
  nothing,

  /// Sunucu boş, cihazda veri var: cihaz kazanır, tam görüntü yüklenir.
  upload,

  /// Cihaz boş, sunucuda veri var: sunucu indirilir.
  download,

  /// **İkisinde de** veri var. Bu kararı kod veremez.
  ask,
}

/// [FirstSyncCoordinator.inspect]'in sonucu: ne yapılacağı ve (çekildiyse)
/// sunucudan gelen görüntü.
///
/// Görüntü karar nesnesinde taşınıyor çünkü ikinci kez çekmek hem gereksiz bir
/// ağ turu hem de bir yarış: aradan geçen sürede sunucu değişmiş olabilir ve
/// kullanıcı, kendisine gösterilenden başka bir şeyi onaylamış olurdu.
class FirstSyncDecision {
  const FirstSyncDecision(this.plan, {this.remote});

  final FirstSyncPlan plan;
  final Map<String, dynamic>? remote;
}

/// Oturum açıldığında iki tarafı buluşturur.
///
/// Karar ile uygulama bilinçli olarak ayrı: [FirstSyncPlan.ask] çıktığında
/// arada bir insan var. Tek bir `syncOnLogin()` metodu olsaydı, o metodun
/// içinden diyalog açmak gerekirdi ve mantık ekrana yapışırdı.
class FirstSyncCoordinator {
  const FirstSyncCoordinator({
    required this.gateway,
    required this.store,
    required this.outbox,
  });

  final RemoteGateway gateway;
  final AppStore store;
  final Outbox outbox;

  /// Sunucuyu çeker ve ne yapılması gerektiğini söyler. **Hiçbir şeyi
  /// uygulamaz.**
  Future<FirstSyncDecision> inspect() async {
    final remote = await gateway.pull();
    final remoteHasData = _hasData(remote);
    final localHasData =
        store.tasks.isNotEmpty ||
        store.notes.isNotEmpty ||
        store.habits.isNotEmpty;

    return FirstSyncDecision(
      plan(localHasData: localHasData, remoteHasData: remoteHasData),
      remote: remote,
    );
  }

  /// Kararın kendisi — saf işlev, testi ucuz.
  ///
  /// Sunucu boşken **sormuyoruz**: soracak bir şey yok, kullanıcının cihazdaki
  /// takvimi tek gerçek. Soru yalnız gerçekten iki gerçek varken anlamlı.
  static FirstSyncPlan plan({
    required bool localHasData,
    required bool remoteHasData,
  }) {
    if (!remoteHasData) {
      return localHasData ? FirstSyncPlan.upload : FirstSyncPlan.nothing;
    }
    if (!localHasData) return FirstSyncPlan.download;
    return FirstSyncPlan.ask;
  }

  /// Verilen kararı uygular.
  ///
  /// [FirstSyncPlan.ask] burada geçerli değil: çağıran onu önce kullanıcıya
  /// sorup [FirstSyncPlan.upload] ya da [FirstSyncPlan.download]'a çevirmeli.
  Future<void> apply(
    FirstSyncPlan chosen, {
    Map<String, dynamic>? remote,
  }) async {
    switch (chosen) {
      case FirstSyncPlan.nothing:
      case FirstSyncPlan.ask:
        return;

      case FirstSyncPlan.upload:
        await gateway.pushSnapshot(store.toJson());
        // Görüntü zaten yerel durumun tamamı; kuyrukta bekleyenler onun
        // içinde. Bırakmak aynı işi ikinci kez göndermek olurdu.
        await outbox.clear();

      case FirstSyncPlan.download:
        if (remote == null) return;
        store.loadJson(remote);
        // Kuyruğun temizlenmesi **şart**. Bekleyen mutasyonlar, kullanıcının
        // az önce terk etmeyi seçtiği yerel durumu anlatıyor: bırakılsalardı
        // gönderilir ve silinen işleri sunucuda diriltirdi. Yani "indir"
        // sessizce "birleştir"e dönerdi — kullanıcının onayladığı şey bu değil.
        await outbox.clear();
        await store.flush();
    }
  }

  static bool _hasData(Map<String, dynamic>? snapshot) {
    if (snapshot == null) return false;
    bool full(String key) => (snapshot[key] as List?)?.isNotEmpty ?? false;
    // Kategoriler sayılmıyor: varsayılan kategoriler her kurulumda var ve
    // onlara bakmak her sunucuyu "dolu" gösterirdi.
    return full('nodes') || full('habits');
  }
}
