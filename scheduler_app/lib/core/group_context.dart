import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    await _store.writeString(
      kGroupsCacheKey,
      jsonEncode([for (final g in groups) g.toJson()]),
    );
    if (!stillMember) await _store.writeString(kActiveGroupKey, '');
  }
}

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
