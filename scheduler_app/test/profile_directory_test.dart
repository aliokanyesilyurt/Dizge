import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/profile_directory.dart';
import 'package:scheduler_app/data/local_store.dart';
import 'package:scheduler_app/data/sync/mutation.dart';
import 'package:scheduler_app/data/sync/remote_gateway.dart';
import 'package:scheduler_app/data/sync/supabase_api.dart';
import 'package:scheduler_app/models/group.dart';
import 'package:scheduler_app/models/profile.dart';

/// Y4.4b — adların istemciye kadar taşınması.
///
/// Buradaki testlerin ortak sorusu: **ağ yokken kullanıcı kimin işine baktığını
/// hâlâ görebiliyor mu?** Bir uuid'yi ada çevirmek ağa bağlı olsaydı, uçaktaki
/// kullanıcı grup takvimini adsız yüzlerle görürdü.

class _FakeGateway implements RemoteGateway {
  _FakeGateway({this.profiles = const []});

  List<Profile> profiles;
  bool throwOnFetch = false;
  int fetchCount = 0;
  final List<String> renamed = [];
  Exception? nextWriteFailure;

  @override
  Future<List<Profile>> fetchProfiles() async {
    fetchCount++;
    if (throwOnFetch) throw Exception('ağ koptu');
    return profiles;
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final f = nextWriteFailure;
    if (f != null) {
      nextWriteFailure = null;
      throw f;
    }
    renamed.add(displayName);
  }

  // --- Bu testin ilgilenmediği yüzey ------------------------------------------
  @override
  bool get isConfigured => true;
  @override
  Stream<void> get remoteChanges => const Stream.empty();
  @override
  Future<PushResult> push(List<Mutation> m) async => PushResult.empty;
  @override
  Future<Map<String, dynamic>?> pull({DateTime? since}) async => null;
  @override
  Future<PushResult> pushSnapshot(Map<String, dynamic> s) async =>
      PushResult.empty;
  @override
  Future<List<Group>> fetchGroups() async => const [];
  @override
  Future<Group> createGroup(String name) async => throw UnimplementedError();
  @override
  Future<String> createInvite(String g, {String? email}) async =>
      throw UnimplementedError();
  @override
  Future<String> acceptInvite(String t) async => throw UnimplementedError();
  @override
  Future<void> leaveGroup(String g) async => throw UnimplementedError();
}

const _ali = Profile(
  userId: 'u-ali',
  displayName: 'Ali Okan',
  avatarUrl: 'https://ornek/foto.jpg',
);
const _veli = Profile(userId: 'u-veli', displayName: 'Veli');

void main() {
  group('baş harfler', () {
    test('iki sözcüklü ad iki harf verir', () {
      expect(_ali.initials, 'AO');
    });

    test('tek sözcüklü ad tek harf verir', () {
      expect(_veli.initials, 'V');
    });

    test('üçüncü sözcük rozete girmez', () {
      // Üç harf 14px'lik bir dairede okunmaz; sınır tasarımın kendisi.
      const p = Profile(userId: 'u', displayName: 'Ali Okan Yeşilyurt');
      expect(p.initials, 'AO');
    });

    test('Latin dışı harfler büyütülerek geçer', () {
      const p = Profile(userId: 'u', displayName: 'ömer çınar');
      expect(p.initials, 'ÖÇ');
    });

    test('harf içermeyen ad soru işaretine düşer', () {
      // Emojiyi büyütüp göstermektense bilinmezliği söylemek dürüst.
      const p = Profile(userId: 'u', displayName: '🎉 ✨');
      expect(p.initials, '?');
      expect(const Profile(userId: 'u').initials, '?');
    });

    test('boş ad "Adsız" etiketi verir ama uydurma harf üretmez', () {
      const p = Profile(userId: 'u', displayName: '   ');
      expect(p.label, 'Adsız');
      expect(p.initials, '?');
    });
  });

  group('fotoğraf', () {
    test('boş dize fotoğraf sayılmaz', () {
      // Yoksa boş bir ağ isteği atılır ve her açılışta bir hata yutulurdu.
      final p = Profile.fromRow(const {
        'user_id': 'u',
        'display_name': 'Ali',
        'avatar_url': '   ',
      });
      expect(p.avatarUrl, isNull);
      expect(p.hasPhoto, isFalse);
    });

    test('dolu adres kırpılarak taşınır', () {
      expect(_ali.hasPhoto, isTrue);
      expect(Profile.fromJson(_ali.toJson()), _ali);
    });
  });

  group('sözlük', () {
    test('bilinmeyen kimlik null verir — uydurma profil üretilmez', () {
      // "Adsız" diye gerçekten kaydolmuş biriyle henüz tanınmayan biri
      // ekranda aynı görünmemeli.
      const d = ProfileDirectory(byId: {'u-ali': _ali});
      expect(d['u-ali'], _ali);
      expect(d['u-yok'], isNull);
      expect(d[null], isNull);
    });

    test('tazeleme sunucudan gelen adları yazar ve diske işler', () async {
      final store = InMemoryStore();
      final gateway = _FakeGateway(profiles: [_ali, _veli]);
      final c = ProfileDirectoryController(store, gateway);

      await c.refresh();

      expect(c.state['u-ali']?.displayName, 'Ali Okan');
      expect(c.state['u-veli']?.displayName, 'Veli');
      expect(store.readString(kProfilesCacheKey), isNotNull);
    });

    test('önbellek açılışta okunur — ağ beklenmez', () async {
      // Y4.4'ün asıl sözü: çevrimdışı açılışta bloklar `?` göstermez.
      final store = InMemoryStore();
      await store.writeString(
        kProfilesCacheKey,
        jsonEncode([_ali.toJson(), _veli.toJson()]),
      );

      final gateway = _FakeGateway()..throwOnFetch = true;
      final c = ProfileDirectoryController(store, gateway);

      expect(c.state['u-ali']?.displayName, 'Ali Okan');
      await c.refresh();
      expect(
        c.state['u-ali']?.displayName,
        'Ali Okan',
        reason: 'ağ hatası yutulur',
      );
    });

    test('bozuk önbellek açılışı düşürmez', () {
      final store = InMemoryStore();
      store.writeString(kProfilesCacheKey, '{bozuk json');

      final c = ProfileDirectoryController(store, _FakeGateway());

      expect(c.state.isEmpty, isTrue);
    });

    test('boş cevap son bilinen adları silmez', () async {
      // Oturum tazelenirken RLS bir an hiçbir satır döndürebilir; bunu
      // yazmak bütün ekranı sebepsiz `?`'e çevirirdi.
      final store = InMemoryStore();
      final gateway = _FakeGateway(profiles: [_ali]);
      final c = ProfileDirectoryController(store, gateway);
      await c.refresh();

      gateway.profiles = const [];
      await c.refresh();

      expect(c.state['u-ali'], _ali);
    });
  });

  group('ad değiştirme', () {
    test('sunucuya kırpılmış gider, yerele hemen yazılır', () async {
      final store = InMemoryStore();
      final gateway = _FakeGateway(profiles: [_ali]);
      final c = ProfileDirectoryController(store, gateway);
      await c.refresh();

      await c.updateDisplayName('u-ali', '  Ali Okan Y.  ');

      expect(gateway.renamed, ['Ali Okan Y.']);
      // Sunucudan tazelemeyi beklemek, kullanıcıya kendi yazdığı adın bir tur
      // sonra görünmesi demekti.
      expect(c.state['u-ali']?.displayName, 'Ali Okan Y.');
      // Fotoğraf ada dokunmakla kaybolmamalı.
      expect(c.state['u-ali']?.avatarUrl, 'https://ornek/foto.jpg');
    });

    test('profili hiç olmayan kullanıcı için satır açılır', () async {
      final c = ProfileDirectoryController(InMemoryStore(), _FakeGateway());

      await c.updateDisplayName('u-yeni', 'Yeni Kişi');

      expect(c.state['u-yeni']?.displayName, 'Yeni Kişi');
    });

    test('sunucu reddederse yerel ad değişmez', () async {
      // Sıra bilinçli: önce sunucu. Tersi olsaydı kullanıcı adının
      // değiştiğini sanır, karşı taraf eskisini görmeye devam ederdi.
      final store = InMemoryStore();
      final gateway = _FakeGateway(profiles: [_ali]);
      final c = ProfileDirectoryController(store, gateway);
      await c.refresh();

      gateway.nextWriteFailure = const RemoteException('ağ yok');

      await expectLater(
        c.updateDisplayName('u-ali', 'Yeni Ad'),
        throwsA(isA<RemoteException>()),
      );
      expect(c.state['u-ali']?.displayName, 'Ali Okan');
    });
  });
}
