import '../../core/app_config.dart';
import '../../models/group.dart';
import '../../models/profile.dart';
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

  @override
  Stream<void> get remoteChanges => _api.remoteChanges;

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

  /// Sunucudaki değişiklikleri çeker.
  ///
  /// [since] null ise **tam** çekim: dönen görüntü `AppStore.loadJson`'a
  /// verilir ve yerel durumun yerine geçer (oturum açılışı).
  ///
  /// [since] verilirse **artımlı** çekim (Y1): yalnız o damgadan sonra sunucuda
  /// değişmiş satırlar gelir ve görüntü iki şey daha taşır —
  ///   * `deletedIds`: mezar taşı almış kayıtların kimlikleri. Bunlar olmadan
  ///     silme taşınamaz: "gelmedi" ile "silindi" ayırt edilemez (B3).
  ///   * `cursor`: bir sonraki çekimin başlayacağı **sunucu** damgası.
  /// Bu görüntü `loadJson`'a değil, `AppStore.mergeJson`'a verilir.
  @override
  Future<Map<String, dynamic>?> pull({DateTime? since}) async {
    // Oturum yokken **boş görüntü dönmek yasak**. Çağıran onu "sunucu boş"
    // diye okur ve yerel takvimin üstüne yazabilir. Yokluğun boşluktan
    // ayrılması gerekiyor; bu yüzden hata.
    if (!isConfigured) {
      throw const RemoteException('oturum yok — çekim yapılamaz', fatal: true);
    }

    final nodes = since == null
        ? await _api.fetchAll('nodes')
        : await _api.fetchSince('nodes', since);
    final habits = since == null
        ? await _api.fetchAll('habits')
        : await _api.fetchSince('habits', since);

    // Kategoriler her iki kipte de bütün olarak geliyor (Y1d): sıralı bir
    // liste ve kimlikleri adları, yani "silinen kategori" diye bir satır yok.
    // Üç satırlık bir tablo için bu maliyet gürültü seviyesinde.
    final categories = await _api.fetchAll('categories');

    final snapshot = <String, dynamic>{
      'schemaVersion': AppConfig.kSchemaVersion,
      'savedAt': DateTime.now().toIso8601String(),
      'nodes': _livePayloads(nodes),
      'habits': _livePayloads(habits),
      'categories': _categories(categories),
    };

    if (since == null) return snapshot;

    return snapshot
      ..['deletedIds'] = [..._deletedIds(nodes), ..._deletedIds(habits)]
      // İmleç **gelen satırlardan** hesaplanıyor, "şimdi"den değil: aradaki
      // saat farkı ya da bir sonraki turda yazılan satır atlanırdı.
      ..['cursor'] = _latestServerAt([...nodes, ...habits])?.toIso8601String();
  }

  /// Üyesi olunan gruplar (Y4).
  ///
  /// Süzgeç yok ve olmamalı: RLS zaten yalnız üyesi olunan grupları
  /// gösteriyor. Buraya bir `where` yazmak, güvenliğin istemcide olduğu
  /// izlenimi verirdi — `fetchAll`'daki aynı sebep.
  @override
  Future<List<Group>> fetchGroups() async {
    if (!isConfigured) return const [];
    final rows = await _api.fetchAll('groups');
    return [for (final r in rows) Group.fromRow(r)]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Grup kurar (`create_group`) ve kurulan grubu döner.
  ///
  /// Sunucu yalnız kimliği döndürüyor; adı ve sahibi burada biliniyor, ikinci
  /// bir çekim turu için sebep yok.
  @override
  Future<Group> createGroup(
    String name, {
    String? description,
    int? colorIndex,
  }) async {
    final id = await _api.rpc('create_group', {'group_name': name});
    final group = Group(
      id: id as String,
      name: name.trim(),
      ownerId: _api.currentUserId,
    ).copyWith(description: description ?? '', colorIndex: colorIndex);

    if (group.description != null || group.colorIndex != null) {
      try {
        await updateGroup(group);
      } on RemoteException {
        // Göç 06 çalışmamış olabilir (sütun yok). Grup kuruldu; kurulumu bu
        // yüzden başarısız saymak, kullanıcıyı "kurulmadı" sanıp ikinci bir
        // grup kurmaya iterdi.
      }
    }
    return group;
  }

  @override
  Future<void> updateGroup(Group group) => _api.updateGroup(
    group.id,
    name: group.name.trim(),
    description: group.description,
    color: group.colorIndex,
  );

  @override
  Future<List<GroupMember>> fetchGroupMembers(String groupId) async {
    if (!isConfigured) return const [];
    final rows = await _api.fetchGroupMembers(groupId);
    return [
      for (final r in rows)
        if (r['user_id'] != null) GroupMember.fromRow(r),
    ]..sort((a, b) => (b.isOwner ? 1 : 0) - (a.isOwner ? 1 : 0));
  }

  @override
  Future<String> createInvite(String groupId, {String? email}) async {
    final token = await _api.rpc('create_invite', {
      'gid': groupId,
      // Boş dize `null` demek: adrese yazılmamış, herkese açık davet.
      'invite_email': (email == null || email.trim().isEmpty)
          ? null
          : email.trim(),
    });
    return token as String;
  }

  @override
  Future<String> acceptInvite(String token) async {
    final groupId = await _api.rpc('accept_invite', {
      'invite_token': token.trim(),
    });
    return groupId as String;
  }

  @override
  Future<void> leaveGroup(String groupId) => _api.leaveGroup(groupId);

  /// Görülebilen profiller (Y4.4).
  ///
  /// `fetchGroups`'un aynısı: süzgeç yok, RLS zaten yalnız kendi satırını ve
  /// ortak grubu olanların satırını gösteriyor. Kimliksiz satır atlanıyor —
  /// haritanın anahtarı o ve boş anahtar bir profili kaybettirirdi.
  @override
  Future<List<Profile>> fetchProfiles() async {
    if (!isConfigured) return const [];
    final rows = await _api.fetchAll('profiles');
    return [
      for (final r in rows)
        if (Profile.fromRow(r) case final p when p.userId.isNotEmpty) p,
    ];
  }

  @override
  Future<void> updateDisplayName(String displayName) =>
      _api.upsertProfile(displayName: displayName.trim());

  @override
  Future<void> updateAvatarColor(int color) =>
      _api.upsertProfile(avatarColor: color);

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
  ///
  /// İkinci fark grupla geldi (Y4a): `groupId` payload'ın **içinde** yaşıyor
  /// (bir kaydın niteliği olduğu için), sunucu ise onu mutasyonun **tepesinde**
  /// bekliyor — çünkü orada bir sütun. Anahtarın varlığı korunuyor: payload
  /// grubunu bilmiyorsa yukarı da çıkmıyor ve sunucu satırın grubuna dokunmuyor.
  static Map<String, dynamic> _wire(Mutation m) => {
    ...m.toJson(),
    'at': m.at.toUtc().toIso8601String(),
    if (m.payload.containsKey('groupId')) 'groupId': m.payload['groupId'],
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
  /// Mezar taşı almış satırların kimlikleri (Y1b).
  static List<String> _deletedIds(List<Map<String, dynamic>> rows) => [
    for (final r in rows)
      if (r['deleted_at'] != null && r['id'] is String) r['id'] as String,
  ];

  /// Gelen satırlar içindeki en yeni **sunucu** damgası.
  ///
  /// Bir sonraki çekimin başlangıcı bu. Hiç satır gelmediyse null döner ve
  /// çağıran imleci olduğu yerde bırakır — ilerletmek, o pencerede yazılan
  /// bir satırı sonsuza dek atlamak olurdu.
  static DateTime? _latestServerAt(List<Map<String, dynamic>> rows) {
    DateTime? latest;
    for (final r in rows) {
      final raw = r['server_at'];
      if (raw is! String) continue;
      final at = DateTime.tryParse(raw);
      if (at == null) continue;
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    return latest;
  }

  static List<Map<String, dynamic>> _livePayloads(
    List<Map<String, dynamic>> rows,
  ) => [
    for (final r in rows)
      if (r['deleted_at'] == null && r['payload'] is Map)
        {
          ...(r['payload'] as Map).cast<String, dynamic>(),
          // Grup ve köken payload'da değil, satırın **sütunlarında** (Y4a).
          // Sütun payload'ın içindekini bilerek eziyor: payload'a düşmüş eski
          // bir kopya olabilir, yetkinin dayandığı değer ise sütun.
          'groupId': r['group_id'] as String?,
          'ownerId': ?r['owner_id'] as String?,
        },
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
            if (r['label'] != null) 'label': r['label'] as String,
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
