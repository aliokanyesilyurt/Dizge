import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../data/persistence_providers.dart';
import '../data/sync/remote_gateway.dart';
import '../models/profile.dart';
import '../screens/auth_gate.dart';

/// Görülebilen profillerin yerel önbelleği.
const String kProfilesCacheKey = 'profiles.cache';

/// uuid → [Profile]. Grup bağlamında "bu işi kim yazdı" sorusunun sözlüğü.
///
/// Neden ayrı bir sözlük ve satırın içinde bir ad değil (Y4.4d): adı payload'a
/// yazmak veriyi çoğaltırdı ve biri adını değiştirdiğinde eski satırlar
/// sonsuza dek eski adı gösterirdi. Ad kişinin niteliği, işin değil.
@immutable
class ProfileDirectory {
  const ProfileDirectory({this.byId = const {}});

  final Map<String, Profile> byId;

  /// Bilinmeyen kimlik için **null**: çağıran yer `?` rozetine düşer.
  /// Burada uydurma bir profil üretmek, adı gerçekten "Adsız" olan biriyle
  /// henüz tanınmayan birini ekranda aynı gösterirdi.
  Profile? operator [](String? userId) =>
      (userId == null || userId.isEmpty) ? null : byId[userId];

  bool get isEmpty => byId.isEmpty;
}

/// Profilleri tutar, tazeler ve diske yazar.
///
/// Tazeleme grup listesiyle **aynı anda** olur ([GroupContextController.refresh]
/// çağrılan yerlerde): profiller yalnız grup bağlamında görünüyor, onlara ayrı
/// bir takvim icat etmeye değmez.
class ProfileDirectoryController extends StateNotifier<ProfileDirectory> {
  ProfileDirectoryController(this._store, this._gateway)
    : super(ProfileDirectory(byId: _readCache(_store)));

  final LocalStore _store;
  final RemoteGateway _gateway;

  /// Çevrimdışı açılışta bloklarda `?` rozeti bir kare bile görünmesin diye.
  static Map<String, Profile> _readCache(LocalStore store) {
    try {
      final raw = store.readString(kProfilesCacheKey);
      if (raw == null || raw.isEmpty) return const {};
      return {
        for (final e in jsonDecode(raw) as List)
          if (Profile.fromJson((e as Map).cast<String, dynamic>()) case final p
              when p.userId.isNotEmpty)
            p.userId: p,
      };
    } catch (_) {
      // Bozuk önbellek yüzünden açılışı düşürmeye değmez.
      return const {};
    }
  }

  /// Sunucudan tazeler.
  ///
  /// Hata **yutuluyor** ([GroupContextController.refresh] ile aynı gerekçe):
  /// çevrimdışıyken doğru davranış son bilinen adları göstermek, kullanıcıya
  /// hata kutusu açmak değil. Ad, kullanıcının yazdığı ve kaybolabilecek bir
  /// şey değil — kaybolursa yerine `?` geçer, o kadar.
  Future<void> refresh() async {
    try {
      final fetched = await _gateway.fetchProfiles();
      // Boş liste **yazılmıyor**: RLS bir an için hiçbir satır döndürürse
      // (oturum tazelenirken) bütün adları silmek, ekranı sebepsiz `?`'e
      // çevirirdi. Gerçekten profilsiz bir hesapta zaten önbellek de boş.
      if (fetched.isEmpty) return;
      await _apply({for (final p in fetched) p.userId: p});
    } catch (_) {
      // Sessiz: son bilinen adlar ekranda kalır.
    }
  }

  /// Kendi görünen adını yazar (Y4.4g).
  ///
  /// Sıra önemli: önce sunucu. Yerelden yazıp sunucu çağrısı düşseydi kullanıcı
  /// adının değiştiğini sanır, karşı taraf eski adı görmeye devam ederdi.
  ///
  /// Yerel harita **hemen** güncelleniyor: sunucudan tazelemeyi beklemek,
  /// kullanıcıya kendi yazdığı adın bir tur sonra görünmesi demekti.
  Future<void> updateDisplayName(String userId, String displayName) async {
    final trimmed = displayName.trim();
    await _gateway.updateDisplayName(trimmed);

    final mine = state.byId[userId] ?? Profile(userId: userId);
    await _apply({...state.byId, userId: mine.copyWith(displayName: trimmed)});
  }

  /// Kendi rozet rengini yazar (Karar C).
  ///
  /// [updateDisplayName] ile aynı sıra ve aynı gerekçe: önce sunucu, sonra
  /// yerel harita.
  Future<void> updateAvatarColor(String userId, int color) async {
    await _gateway.updateAvatarColor(color);

    final mine = state.byId[userId] ?? Profile(userId: userId);
    await _apply({...state.byId, userId: mine.copyWith(avatarColor: color)});
  }

  Future<void> _apply(Map<String, Profile> byId) async {
    state = ProfileDirectory(byId: byId);
    await _store.writeString(
      kProfilesCacheKey,
      jsonEncode([for (final p in byId.values) p.toJson()]),
    );
  }
}

final profileDirectoryProvider =
    StateNotifierProvider<ProfileDirectoryController, ProfileDirectory>(
      (ref) => ProfileDirectoryController(
        ref.watch(localStoreProvider),
        ref.watch(remoteGatewayProvider),
      ),
    );

/// Hesapsız kullanıcının kendi seçtiği yüzü.
///
/// Sunucuda karşılığı yok ve olmayacak: misafirin adı bu cihazdan dışarı
/// çıkmıyor, kimsenin görmediği bir rozeti sunucuya yazmanın anlamı yok.
///
/// Kimliği sabit `kGuestUserId`. Eskiden rengi taşımak için
/// `'guest_color_3'` gibi uydurma kimlikler üretiliyor ve rozet bunu ön
/// ekinden tanımaya çalışıyordu; renk artık [Profile.avatarColor] alanında,
/// kimlik yine sadece kimlik.
final guestProfileProvider = Provider<Profile?>((ref) {
  if (!ref.watch(guestModeProvider)) return null;

  final store = ref.watch(localStoreProvider);
  final name = store.readString(kGuestNameKey) ?? 'Misafir';
  return Profile(
    userId: kGuestUserId,
    displayName: name.trim().isEmpty ? 'Misafir' : name.trim(),
    avatarColor: int.tryParse(store.readString(kGuestColorKey) ?? ''),
  );
});

/// Misafirin kimliği. Sunucudaki hiçbir uuid'ye benzemiyor — bilerek: bu dize
/// bir gün `owner_id` diye bir satıra yazılırsa hemen göze batmalı.
const String kGuestUserId = 'guest';

/// Tek bir kişinin profili.
///
/// `family` + `select`: bir kişinin adı değiştiğinde yalnız onun blokları
/// yeniden çizilir. Bütün haritayı izlemek, her tazelemede ekrandaki her
/// avatarı uyandırırdı.
final profileProvider = Provider.family<Profile?, String?>((ref, userId) {
  // Kimliksiz "ben": ya misafiriz, ya da hiç kimseyiz. `guestProfileProvider`
  // misafir değilken zaten null döndürüyor, yani bu dal eski davranışı
  // (bilinmeyen kimlik → null → `?` rozeti) bozmuyor.
  if (userId == null || userId == kGuestUserId) {
    return ref.watch(guestProfileProvider);
  }
  return ref.watch(profileDirectoryProvider.select((d) => d[userId]));
});
