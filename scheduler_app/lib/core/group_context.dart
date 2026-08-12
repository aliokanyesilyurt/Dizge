import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../data/local_store.dart';
import '../data/persistence_providers.dart';
import '../data/sync/remote_gateway.dart';
import '../models/group.dart';

/// O an bakılan bağlamın anahtarı. Boş dize = **Kişisel**.
///
/// Neden boş dize ve null değil: [LocalStore] silme sunmuyor, yalnız yazma.
/// "Kişisel"i kaydedememek, kullanıcının gruptan kişisele dönüşünü uygulama
/// kapanınca unutmak olurdu.
const String kActiveGroupKey = 'settings.activeGroup';

/// Grup listesinin yerel önbelleği.
const String kGroupsCacheKey = 'groups.cache';

/// Kenar çubuğundaki bağlam seçicinin bütün durumu.
@immutable
class GroupContext {
  const GroupContext({this.groups = const [], this.activeId});

  /// Kullanıcının üyesi olduğu gruplar, ada göre sıralı.
  final List<Group> groups;

  /// Bakılan grup; **null ise Kişisel**.
  final String? activeId;

  Group? get active {
    for (final g in groups) {
      if (g.id == activeId) return g;
    }
    return null;
  }

  bool get isPersonal => activeId == null;

  /// Seçicide ve boş ekranlarda görünen ad.
  String get label => active?.name ?? 'Kişisel';
}

/// Hangi bağlamda çalışıldığını tutar ve **anında** diske yazar.
///
/// Bağlam bir süzgeç, ikinci bir depo değil (Y4b): yerel depo tek, kişisel
/// işler `groupId == null`, grup işleri o grubun kimliğini taşıyor. İkiye
/// bölmek senkron motorunu, outbox'ı, geri alma yığınını ve arama indeksini
/// birden bölmek olurdu.
class GroupContextController extends StateNotifier<GroupContext> {
  GroupContextController(this._store, this._gateway)
    : super(
        GroupContext(groups: _readCache(_store), activeId: _readActive(_store)),
      );

  final LocalStore _store;
  final RemoteGateway _gateway;

  static String? _readActive(LocalStore store) {
    try {
      final raw = store.readString(kActiveGroupKey);
      return (raw == null || raw.isEmpty) ? null : raw;
    } catch (_) {
      return null;
    }
  }

  /// Çevrimdışı açılışta grup **adları** görünsün diye.
  ///
  /// Liste sunucudan gelene kadar boş kalsaydı, seçici bir kare için yalnız
  /// "Kişisel" gösterir ve kullanıcı grubunun kaybolduğunu sanırdı.
  static List<Group> _readCache(LocalStore store) {
    try {
      final raw = store.readString(kGroupsCacheKey);
      if (raw == null || raw.isEmpty) return const [];
      return [
        for (final e in jsonDecode(raw) as List)
          Group.fromJson((e as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      // Bozuk önbellek yüzünden açılışı düşürmeye değmez: tazeleme zaten
      // birazdan doğrusunu getirecek.
      return const [];
    }
  }

  /// Bağlamı değiştirir.
  Future<void> select(String? groupId) async {
    if (groupId == state.activeId) return;
    state = GroupContext(groups: state.groups, activeId: groupId);
    await _store.writeString(kActiveGroupKey, groupId ?? '');
  }

  /// Yeni katılınan grubu listeye katar ve bağlamı ona taşır.
  ///
  /// Sunucudan tazelemek yerine buradan eklemenin sebebi bir gidiş-dönüş
  /// tasarrufu değil: [refresh] hatayı yutuyor: ağ o anda düşerse grup
  /// listeye hiç girmez ve kullanıcı az önce kurduğu grubu göremezdi.
  Future<void> adopt(Group group) async {
    final groups = [
      for (final g in state.groups)
        if (g.id != group.id) g,
      group,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    state = GroupContext(groups: groups, activeId: group.id);
    await _writeCache(groups);
    await _store.writeString(kActiveGroupKey, group.id);
  }

  /// Grup listesini sunucudan tazeler.
  ///
  /// Hata **yutuluyor**: çevrimdışı açılışta liste tazelenemiyorsa doğru
  /// davranış son bilinen listeyi göstermek, kullanıcıya bir hata kutusu
  /// açmak değil. Grup listesi kullanıcının yazdığı bir şey değil ki
  /// kaybolma riski olsun.
  Future<void> refresh() async {
    try {
      final fetched = await _gateway.fetchGroups();
      await _apply(fetched);
    } catch (_) {
      // Sessiz: son bilinen liste ekranda kalır.
    }
  }

  Future<void> _apply(List<Group> groups) async {
    // Üyeliği kalmayan bir gruba kilitlenmemek için (Y4d'nin arayüz yarısı):
    // aktif grup listeden düştüyse bağlam Kişisel'e döner. Dönmeseydi
    // kullanıcı boş bir ekrana bakar ve nedenini göremezdi.
    final stillMember = groups.any((g) => g.id == state.activeId);
    final nextActive = stillMember ? state.activeId : null;

    state = GroupContext(groups: groups, activeId: nextActive);

    await _writeCache(groups);
    if (!stillMember) await _store.writeString(kActiveGroupKey, '');
  }

  Future<void> _writeCache(List<Group> groups) => _store.writeString(
    kGroupsCacheKey,
    jsonEncode([for (final g in groups) g.toJson()]),
  );
}

/// Grup kurma, davet etme, daveti kabul etme ve gruptan çıkma (Y4.3).
///
/// Neden [GroupContextController]'ın içinde değil: gruptan çıkmak yerel
/// satırların temizlenmesini de gerektiriyor (Y4d) ve o iş [AppStore]'da.
/// Controller'a depoyu enjekte etmek döngü kurardı — `appStoreProvider` zaten
/// [activeGroupIdProvider]'ı dinliyor, o da bu controller'dan geliyor.
///
/// Dördü de **çevrimiçi ister** (Y4f). Kuyruk yok: bağlantı yoksa çağrı
/// [RemoteException] ile düşer ve arayüz bunu söyler.
class GroupActions {
  const GroupActions(this._ref);

  final Ref _ref;

  RemoteGateway get _gateway => _ref.read(remoteGatewayProvider);
  GroupContextController get _context =>
      _ref.read(groupContextProvider.notifier);

  /// Grup kurar ve bağlamı **hemen** yeni gruba taşır.
  ///
  /// Kurduğu grubun içine düşmek, kullanıcının bir sonraki hamlesinin
  /// (birini davet etmek, ilk işi yazmak) zaten orada olması demek.
  Future<Group> create(String name) async {
    final group = await _gateway.createGroup(name);
    await _context.adopt(group);
    return group;
  }

  /// Davet üretir; token'ı çağıran panoya kopyalar (Y4g).
  Future<String> invite(String groupId, {String? email}) =>
      _gateway.createInvite(groupId, email: email);

  /// Daveti kabul eder ve girilen grubu açar.
  ///
  /// Sunucu yalnız grubun kimliğini dönüyor — adı bilinmiyor, o yüzden
  /// [adopt] değil tam tazeleme gerekiyor.
  Future<void> accept(String token) async {
    final groupId = await _gateway.acceptInvite(token);
    await _context.refresh();
    await _context.select(groupId);
  }

  /// Gruptan çıkar: sunucudaki üyelik satırı silinir, **yereldeki kopyalar
  /// da** (Y4d) — ama o silme outbox'a yazılmaz.
  ///
  /// Sıra önemli: önce sunucu. Yerelden silip sunucu çağrısı düşseydi
  /// kullanıcı hâlâ üye olduğu bir grubun işlerini kaybederdi.
  Future<void> leave(String groupId) async {
    await _gateway.leaveGroup(groupId);
    _ref.read(appStoreProvider).purgeGroup(groupId);
    await _context.refresh();
  }
}

final groupActionsProvider = Provider<GroupActions>(GroupActions.new);

final groupContextProvider =
    StateNotifierProvider<GroupContextController, GroupContext>(
      (ref) => GroupContextController(
        ref.watch(localStoreProvider),
        ref.watch(remoteGatewayProvider),
      ),
    );

/// Yalnız aktif grup kimliği — süzgeçlerin izlediği en dar parça.
///
/// Ayrı bir provider çünkü liste her tazelendiğinde bütün takvimin yeniden
/// çizilmesi gerekmiyor; değişen şey bağlam değilse kimse uyanmamalı.
final activeGroupIdProvider = Provider<String?>(
  (ref) => ref.watch(groupContextProvider.select((c) => c.activeId)),
);
