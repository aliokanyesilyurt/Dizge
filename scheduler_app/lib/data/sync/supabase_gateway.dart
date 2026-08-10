import '../../core/app_config.dart';
import 'mutation.dart';
import 'remote_gateway.dart';
import 'supabase_api.dart';

/// [RemoteGateway]'in Supabase uygulaması.
///
/// Sorumluluğu üç şey: mutasyonu tele koymak, sunucunun cevabını
/// [PushResult]'a çevirmek, çekilen satırları `AppStore.loadJson`'ın beklediği
/// şekle derlemek. Ağ, kimlik ve paket tipleri [SupabaseApi]'nin arkasında.
class SupabaseGateway implements RemoteGateway {
  const SupabaseGateway(this._api);

  final SupabaseApi _api;

  /// Yapılandırma denetimi (`AppConfig.backendAvailable`) burada **değil**,
  /// kurulum yerinde: bu nesne zaten yalnız anahtarlar varken kuruluyor.
  /// Buradaki soru yalnız şu: konuşabileceğimiz bir kullanıcı var mı?
  ///
  /// Oturum yoksa `false` — ve `SyncEngine` hiç uyanmaz. Oturumsuz kullanıcının
  /// kuyruğunun birikmemesi bilinçli: o veri henüz bir hesaba ait değil.
  @override
  bool get isConfigured => _api.currentUserId != null;

  // --- Gönderim --------------------------------------------------------------

  @override
  Future<PushResult> push(List<Mutation> mutations) async {
    if (mutations.isEmpty) return PushResult.empty;

    try {
      final raw = await _api.rpc('apply_mutations', {
        'muts': [for (final m in mutations) _wire(m)],
      });
      return _readResult(raw, sent: mutations);
    } on RemoteException catch (e) {
      if (e.fatal) return PushResult(fatal: true, message: e.message);

      // Geçici hata: sunucu bu mutasyonları hiç görmedi. Kabul edilmiş saymak
      // sessiz veri kaybı olurdu — hepsi kuyrukta kalır, motor geri çekilir.
      return PushResult(
        rejected: [for (final m in mutations) m.id],
        message: e.message,
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> pull({DateTime? since}) async {
    // [since] bilerek yok sayılıyor (plan B4). Artımlı çekim, gelen kayıtları
    // yerel duruma **birleştirmeyi** gerektirir; `AppStore.loadJson` ise yıkıp
    // yeniden kuruyor. Sözü tutamayacağımız bir parametreyi kısmen uygulamak
    // yerine tam çekim yapıyoruz — çağıran (oturum açılışı) zaten bunu istiyor.

    // Oturum yokken **boş görüntü dönmek yasak**. Çağıran onu "sunucu boş"
    // diye okur ve yerel takvimin üstüne yazabilir. Yokluğun boşluktan
    // ayrılması gerekiyor; bu yüzden hata.
    if (!isConfigured) {
      throw const RemoteException('oturum yok — çekim yapılamaz', fatal: true);
    }

    final nodes = await _api.fetchAll('nodes');
    final habits = await _api.fetchAll('habits');
    final categories = await _api.fetchAll('categories');

    return {
      'schemaVersion': AppConfig.kSchemaVersion,
      'savedAt': DateTime.now().toIso8601String(),
      'nodes': _livePayloads(nodes),
      'habits': _livePayloads(habits),
      'categories': _categories(categories),
    };
  }

  @override
  Future<PushResult> pushSnapshot(Map<String, dynamic> snapshot) async {
    final mutations = <Mutation>[];

    for (final raw in (snapshot['nodes'] as List? ?? const [])) {
      final node = (raw as Map).cast<String, dynamic>();
      final kind = node['kind'] == 'note' ? EntityKind.note : EntityKind.task;
      final m = _fromRecord(node, kind);
      if (m != null) mutations.add(m);
    }

    for (final raw in (snapshot['habits'] as List? ?? const [])) {
      final habit = (raw as Map).cast<String, dynamic>();
      final m = _fromRecord(habit, EntityKind.habit);
      if (m != null) mutations.add(m);
    }

    final result = await push(mutations);
    if (result.fatal) return result;

    // Kategoriler ayrı yoldan gider: sıralı bir **liste** ve kimlikleri adları.
    // Tek tek upsert, kullanıcının sildiği bir kategoriyi sunucuda bırakırdı.
    // Boş listede bile çağrılır — "hepsini sildim" de taşınması gereken bir
    // durum.
    try {
      await _api.rpc('replace_categories', {
        'cats': [
          for (final raw in (snapshot['categories'] as List? ?? const []))
            (raw as Map).cast<String, dynamic>(),
        ],
      });
    } on RemoteException catch (e) {
      if (e.fatal) return PushResult(fatal: true, message: e.message);
      // Kategoriler geçici olarak gitmediyse iş kaybı yok: bir sonraki tam
      // gönderim onları taşır. Kayıtların kabulünü buna bağlamıyoruz.
    }

    return result;
  }

  // --- Çeviriler -------------------------------------------------------------

  /// Mutasyonun tel gösterimi.
  ///
  /// Tek farkı damganın **UTC**'ye çevrilmesi ve bu fark önemli:
  /// `DateTime.toIso8601String()` yerel saati ofsetsiz yazıyor
  /// ("2026-08-10T12:00:00.000"). Postgres onu `timestamptz`e çevirirken UTC
  /// sanar. UTC+3'te her damga üç saat ileri okunur — ve şemadaki saat kayması
  /// koruması (`now() + 5 dakika`) yüzünden **her mutasyon reddedilirdi**.
  static Map<String, dynamic> _wire(Mutation m) => {
    ...m.toJson(),
    'at': m.at.toUtc().toIso8601String(),
  };

  /// Sunucunun `{accepted, rejected}` cevabını [PushResult]'a çevirir.
  ///
  /// Cevapta hiç adı geçmeyen mutasyon **kabul edilmiş sayılmaz**: sunucunun
  /// onu işlediğine dair kanıt yok, kuyrukta kalıp tekrar denenmeli.
  static PushResult _readResult(dynamic raw, {required List<Mutation> sent}) {
    if (raw is! Map) {
      return PushResult(
        fatal: true,
        message: 'apply_mutations beklenmedik cevap verdi: $raw',
      );
    }
    final map = raw.cast<String, dynamic>();
    return PushResult(
      accepted: _ids(map['accepted']),
      rejected: _ids(map['rejected']),
    );
  }

  static List<String> _ids(dynamic v) =>
      v is List ? [for (final e in v) e.toString()] : const [];

  /// Silinmemiş satırların `payload`'ları — `loadJson` bunları bekliyor.
  static List<Map<String, dynamic>> _livePayloads(
    List<Map<String, dynamic>> rows,
  ) => [
    for (final r in rows)
      if (r['deleted_at'] == null && r['payload'] is Map)
        (r['payload'] as Map).cast<String, dynamic>(),
  ];

  /// Sunucu satırından istemci şekline: `color_hex` → `colorHex`, sıra korunur.
  static List<Map<String, dynamic>> _categories(
    List<Map<String, dynamic>> rows,
  ) {
    final sorted = [...rows]
      ..sort(
        (a, b) => ((a['position'] as num?) ?? 0).compareTo(
          (b['position'] as num?) ?? 0,
        ),
      );
    return [
      for (final r in sorted)
        if (r['name'] != null)
          {
            'name': r['name'] as String,
            'colorHex': (r['color_hex'] as String?) ?? '',
          },
    ];
  }

  /// Anlık görüntüdeki bir kaydı yeniden gönderilebilir mutasyona çevirir.
  ///
  /// Damga kaydın kendi `updatedAt`'i — "şimdi" olsaydı tam gönderim,
  /// sunucudaki daha yeni kayıtları eski verilerle ezerdi.
  static Mutation? _fromRecord(Map<String, dynamic> record, EntityKind kind) {
    final id = record['id'] as String?;
    if (id == null || id.isEmpty) return null;

    return Mutation(
      kind: kind,
      entityId: id,
      op: MutationOp.upsert,
      payload: record,
      at:
          DateTime.tryParse((record['updatedAt'] as String?) ?? '') ??
          DateTime.tryParse((record['createdAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
