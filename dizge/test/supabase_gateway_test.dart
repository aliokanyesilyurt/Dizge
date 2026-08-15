import 'package:dizge/data/sync/mutation.dart';
import 'package:dizge/data/sync/supabase_api.dart';
import 'package:dizge/data/sync/supabase_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

/// Üç metotluk sahte sunucu. Gerçek `SupabaseClient` bir HTTP yığını olmadan
/// kurulamıyor; [SupabaseApi] dikişi tam bunun için var.
class _FakeApi implements SupabaseApi {
  _FakeApi({this.userId = 'kullanici-1'});

  String? userId;

  /// Yapılan çağrılar, sırasıyla — testler tele **ne konduğunu** doğruluyor.
  final List<({String fn, Map<String, dynamic> params})> calls = [];

  /// Belirli bir çağrıya verilecek cevap ya da fırlatılacak hata.
  Object? Function(String fn, Map<String, dynamic> params)? onRpc;

  Map<String, List<Map<String, dynamic>>> tables = {};

  @override
  String? get currentUserId => userId;

  @override
  Future<dynamic> rpc(String function, Map<String, dynamic> params) async {
    calls.add((fn: function, params: params));
    final handler = onRpc;
    if (handler == null) {
      return {'accepted': const <String>[], 'rejected': const <String>[]};
    }
    final result = handler(function, params);
    if (result is Exception) throw result;
    return result;
  }

  @override
  Stream<void> get remoteChanges => const Stream.empty();

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String table) async =>
      tables[table] ?? const [];

  /// Sunucunun `server_at > since` süzmesini taklit eder. Silinmiş satırlar
  /// **süzülmez**: mezar taşının gelmesi artımlı çekimin şartı.
  @override
  Future<List<Map<String, dynamic>>> fetchSince(
    String table,
    DateTime since,
  ) async => [
    for (final r in tables[table] ?? const <Map<String, dynamic>>[])
      if (DateTime.parse(r['server_at'] as String).isAfter(since)) r,
  ];

  /// Bırakılan üyelikler, sırasıyla.
  final List<String> left = [];

  @override
  Future<void> leaveGroup(String groupId) async => left.add(groupId);

  /// Yazılan görünen adlar, sırasıyla.
  final List<String> profileWrites = [];

  @override
  Future<void> upsertProfile({required String displayName}) async =>
      profileWrites.add(displayName);

  List<Map<String, dynamic>> mutationsSentTo(String fn) => [
    for (final c in calls)
      if (c.fn == fn)
        ...(c.params['muts'] as List).cast<Map<String, dynamic>>(),
  ];
}

/// Görüntüdeki bir bölümü tipli okur — `dynamic` üzerinden erişim testleri
/// sessizce yanlış alana bakmaya açık bırakıyor.
List<Map<String, dynamic>> _rows(Map<String, dynamic> snapshot, String key) => [
  for (final r in snapshot[key] as List) (r as Map).cast<String, dynamic>(),
];

Mutation _task(String id, {DateTime? at, MutationOp op = MutationOp.upsert}) =>
    Mutation(
      id: id,
      kind: EntityKind.task,
      entityId: 'is-$id',
      op: op,
      payload: {'id': 'is-$id', 'title': 'Deneme'},
      at: at ?? DateTime(2026, 8, 10, 12),
    );

void main() {
  group('isConfigured', () {
    test('oturum varsa yapılandırılmış sayılır', () {
      expect(SupabaseGateway(_FakeApi()).isConfigured, isTrue);
    });

    test('oturum yoksa senkron hiç uyanmaz', () {
      // SyncEngine buna bakıp motoru hiç başlatmıyor. Oturumsuz kullanıcının
      // kuyruğu birikmemeli — o veri henüz kimseye ait değil.
      expect(SupabaseGateway(_FakeApi(userId: null)).isConfigured, isFalse);
    });
  });

  group('push', () {
    test('boş kuyruk sunucuya hiç dokunmaz', () async {
      final api = _FakeApi();
      final result = await SupabaseGateway(api).push([]);

      expect(api.calls, isEmpty);
      expect(result.accepted, isEmpty);
      expect(result.rejected, isEmpty);
    });

    test('bütün kuyruk tek turda gider', () async {
      final api = _FakeApi();
      await SupabaseGateway(api).push([_task('a'), _task('b'), _task('c')]);

      // Üç mutasyon, tek çağrı. Sürükleme oturumunda bu fark onlarca
      // gidiş-dönüş demek.
      expect(api.calls, hasLength(1));
      expect(api.calls.single.fn, 'apply_mutations');
      expect(api.mutationsSentTo('apply_mutations'), hasLength(3));
    });

    test('sunucunun kabul/ret ayrımı olduğu gibi taşınır', () async {
      final api = _FakeApi()
        ..onRpc = (_, _) => {
          'accepted': ['a', 'c'],
          'rejected': ['b'],
        };

      final result = await SupabaseGateway(
        api,
      ).push([_task('a'), _task('b'), _task('c')]);

      expect(result.accepted, ['a', 'c']);
      expect(result.rejected, ['b']);
      expect(result.fatal, isFalse);
    });

    test('damga UTC olarak gider', () async {
      // Bu testin varlık sebebi somut bir hata: `DateTime.toIso8601String()`
      // yerel saati **ofsetsiz** yazıyor ("2026-08-10T12:00:00.000").
      // Postgres onu `timestamptz`e çevirirken UTC sanar. UTC+3'te bu, her
      // damganın üç saat ileri okunması demekti — ve şemadaki saat kayması
      // koruması (now() + 5 dakika) yüzünden **her mutasyon reddedilirdi**.
      final api = _FakeApi();
      final at = DateTime(2026, 8, 10, 12);

      await SupabaseGateway(api).push([_task('a', at: at)]);

      final sent = api.mutationsSentTo('apply_mutations').single;
      expect(sent['at'], endsWith('Z'));
      expect(DateTime.parse(sent['at'] as String).isAtSameMomentAs(at), isTrue);
    });

    test('kalıcı hata senkronu durdurur', () async {
      final api = _FakeApi()
        ..onRpc = (_, _) => const RemoteException('yetkisiz', fatal: true);

      final result = await SupabaseGateway(api).push([_task('a')]);

      expect(result.fatal, isTrue);
      expect(result.message, contains('yetkisiz'));
    });

    test('geçici hatada hiçbir şey kuyruktan düşmez', () async {
      // Kabul edilmiş saymak veri kaybı olurdu: sunucu o mutasyonu hiç
      // görmedi.
      final api = _FakeApi()..onRpc = (_, _) => const RemoteException('ağ yok');

      final result = await SupabaseGateway(api).push([_task('a'), _task('b')]);

      expect(result.fatal, isFalse);
      expect(result.accepted, isEmpty);
      expect(result.rejected, ['a', 'b']);
    });

    test('cevapta adı geçmeyen mutasyon kuyrukta kalır', () async {
      // Sunucu 'b'yi hiç anmadı. Kabul varsaymak onu sessizce kaybetmek olurdu.
      final api = _FakeApi()
        ..onRpc = (_, _) => {
          'accepted': ['a'],
          'rejected': const <String>[],
        };

      final result = await SupabaseGateway(api).push([_task('a'), _task('b')]);

      expect(result.accepted, ['a']);
      expect(result.rejected, isNot(contains('a')));
    });
  });

  group('gruplar (Y4)', () {
    test('grup ve köken sütunları payload\'a katılır', () async {
      // Y4a. `group_id` ve `owner_id` payload'ın içinde değil, satırın
      // sütunlarında. Gateway onları katmasaydı Y3'ün taşıdığı bütün grup
      // bilgisi tam burada, sessizce yere düşerdi.
      final api = _FakeApi()
        ..tables = {
          'nodes': [
            {
              'id': 'g1',
              'kind': 'task',
              'payload': {'id': 'g1', 'kind': 'task', 'title': 'Grubun işi'},
              'group_id': 'grup-1',
              'owner_id': 'ali',
              'deleted_at': null,
            },
          ],
          'habits': <Map<String, dynamic>>[],
          'categories': <Map<String, dynamic>>[],
        };

      final snapshot = (await SupabaseGateway(api).pull())!;

      final node = _rows(snapshot, 'nodes').single;
      expect(node['groupId'], 'grup-1');
      expect(node['ownerId'], 'ali');
    });

    test('sütun, payload\'daki eski kopyayı ezer', () async {
      // Payload'a düşmüş bir `groupId` olabilir (başka bir cihaz yazmış).
      // Yetkinin dayandığı değer sütun; ikisi çeliştiğinde sütun kazanmalı,
      // yoksa istemci satırı ait olmadığı grupta gösterir.
      final api = _FakeApi()
        ..tables = {
          'nodes': [
            {
              'id': 'g1',
              'kind': 'task',
              'payload': {'id': 'g1', 'title': 'İş', 'groupId': 'eski-grup'},
              'group_id': null,
              'deleted_at': null,
            },
          ],
          'habits': <Map<String, dynamic>>[],
          'categories': <Map<String, dynamic>>[],
        };

      final snapshot = (await SupabaseGateway(api).pull())!;

      expect(_rows(snapshot, 'nodes').single['groupId'], isNull);
    });

    test('payload\'daki grup, mutasyonun tepesine çıkar', () async {
      // Sunucu `groupId`'yi mutasyonun tepesinde bekliyor, çünkü orada bir
      // sütun; istemcide ise kaydın bir niteliği ve payload'ın içinde.
      final api = _FakeApi();
      final m = Mutation(
        id: 'm1',
        kind: EntityKind.task,
        entityId: 'is-1',
        op: MutationOp.upsert,
        payload: {'id': 'is-1', 'title': 'İş', 'groupId': 'grup-1'},
      );

      await SupabaseGateway(api).push([m]);

      expect(
        api.mutationsSentTo('apply_mutations').single['groupId'],
        'grup-1',
      );
    });

    test('grubu bilmeyen mutasyon anahtarı hiç yollamaz', () async {
      // Sunucu anahtarın **yokluğu** ile null değerini ayırıyor: yokluk
      // "grubuna dokunma", null "gruptan çıkar". Grup kavramından habersiz bir
      // kayıt (ör. eski sürümde kuyruğa girmiş) susmalı; null yollasaydı grup
      // işini sessizce kişiselleştirirdi.
      final api = _FakeApi();

      await SupabaseGateway(api).push([_task('a')]);

      expect(
        api.mutationsSentTo('apply_mutations').single.containsKey('groupId'),
        isFalse,
      );
    });
  });

  group('pull', () {
    test('çekilen satırlar loadJson şemasına derlenir', () async {
      final api = _FakeApi()
        ..tables = {
          'nodes': [
            {
              'id': 'g1',
              'kind': 'task',
              'payload': {'id': 'g1', 'kind': 'task', 'title': 'Toplantı'},
              'deleted_at': null,
            },
            {
              'id': 'n1',
              'kind': 'note',
              'payload': {'id': 'n1', 'kind': 'note', 'title': 'Not'},
              'deleted_at': null,
            },
          ],
          'habits': [
            {
              'id': 'h1',
              'payload': {'id': 'h1', 'title': 'Su iç'},
              'deleted_at': null,
            },
          ],
          'categories': [
            {'name': 'Tez', 'color_hex': 'FFBA68C8', 'position': 0},
          ],
        };

      final snapshot = await SupabaseGateway(api).pull();

      expect(snapshot, isNotNull);
      expect(_rows(snapshot!, 'nodes'), hasLength(2));
      expect(_rows(snapshot, 'habits'), hasLength(1));
      expect(_rows(snapshot, 'categories').single, {
        'name': 'Tez',
        'colorHex': 'FFBA68C8',
      });
    });

    test('mezar taşları çekilmez', () async {
      final api = _FakeApi()
        ..tables = {
          'nodes': [
            {
              'id': 'g1',
              'kind': 'task',
              'payload': {'id': 'g1', 'title': 'Yaşayan'},
              'deleted_at': null,
            },
            {
              'id': 'g2',
              'kind': 'task',
              'payload': const <String, dynamic>{},
              'deleted_at': '2026-08-01T00:00:00Z',
            },
          ],
        };

      final snapshot = await SupabaseGateway(api).pull();

      expect(_rows(snapshot!, 'nodes'), hasLength(1));
      expect(_rows(snapshot, 'nodes').single['title'], 'Yaşayan');
    });

    test('kategoriler sunucudaki sıraya göre gelir', () async {
      final api = _FakeApi()
        ..tables = {
          'categories': [
            {'name': 'Ikinci', 'color_hex': 'FF000002', 'position': 1},
            {'name': 'Birinci', 'color_hex': 'FF000001', 'position': 0},
          ],
        };

      final snapshot = await SupabaseGateway(api).pull();

      expect(_rows(snapshot!, 'categories').map((c) => c['name']), [
        'Birinci',
        'Ikinci',
      ]);
    });

    test('oturum yokken boş görüntü uydurmaz, hata fırlatır', () async {
      // "Sunucu boş" ile "sunucuya soramadım" aynı şey değil. Boş görüntü
      // dönseydi çağıran (oturum açılış akışı) onu birincisi sanıp yerel
      // takvimin üstüne yazabilirdi.
      final api = _FakeApi()..userId = null;

      await expectLater(
        SupabaseGateway(api).pull(),
        throwsA(isA<RemoteException>()),
      );
    });
  });

  group('pushSnapshot', () {
    test('görüntüdeki her kayıt mutasyona çevrilir', () async {
      final api = _FakeApi();
      await SupabaseGateway(api).pushSnapshot({
        'nodes': [
          {
            'id': 'g1',
            'kind': 'task',
            'title': 'İş',
            'updatedAt': '2026-08-01T09:00:00.000',
          },
          {
            'id': 'n1',
            'kind': 'note',
            'title': 'Not',
            'updatedAt': '2026-08-02T09:00:00.000',
          },
        ],
        'habits': [
          {'id': 'h1', 'title': 'Su', 'updatedAt': '2026-08-03T09:00:00.000'},
        ],
        'categories': [
          {'name': 'Tez', 'colorHex': 'FFBA68C8'},
        ],
      });

      final sent = api.mutationsSentTo('apply_mutations');
      expect(sent, hasLength(3));
      expect(
        sent.map((m) => m['kind']),
        containsAll(['task', 'note', 'habit']),
      );
      expect(sent.every((m) => m['op'] == 'upsert'), isTrue);
    });

    test('kategoriler bütün olarak değiştirilir', () async {
      // Tek tek upsert, silinmiş bir kategoriyi sunucuda bırakırdı.
      final api = _FakeApi();
      await SupabaseGateway(api).pushSnapshot({
        'nodes': const [],
        'habits': const [],
        'categories': [
          {'name': 'Tez', 'colorHex': 'FFBA68C8'},
        ],
      });

      final call = api.calls.firstWhere((c) => c.fn == 'replace_categories');
      final cats = [
        for (final c in call.params['cats'] as List)
          (c as Map).cast<String, dynamic>(),
      ];
      expect(cats.single['name'], 'Tez');
    });

    test('boş görüntü bile kategorileri sıfırlar', () async {
      // Kullanıcı bütün özel kategorileri sildiyse sunucu da boşalmalı.
      final api = _FakeApi();
      await SupabaseGateway(api).pushSnapshot({
        'nodes': const [],
        'habits': const [],
        'categories': const [],
      });

      expect(api.calls.map((c) => c.fn), contains('replace_categories'));
    });
  });

  group('grup işlemleri (Y4.3)', () {
    test('grup kurulur ve kuran sahip sayılır', () async {
      final api = _FakeApi(userId: 'ali')
        ..onRpc = (fn, _) => fn == 'create_group' ? 'grup-1' : null;

      final group = await SupabaseGateway(api).createGroup('  Ekip  ');

      expect(group.id, 'grup-1');
      // Ad kırpılıyor: sunucu da `btrim` uyguluyor, ikisi ayrışmamalı.
      expect(group.name, 'Ekip');
      expect(group.isOwnedBy('ali'), isTrue);
      expect(api.calls.single.params['group_name'], '  Ekip  ');
    });

    test('adressiz davet null e-postayla gider', () async {
      final api = _FakeApi()..onRpc = (_, _) => 'token-abc';

      final token = await SupabaseGateway(api).createInvite('grup-1');

      expect(token, 'token-abc');
      final params = api.calls.single.params;
      expect(params['gid'], 'grup-1');
      // Boş dize değil **null**: sunucu ikisini ayırıyor ve boş dize
      // "kimsenin adresi" diye kaydedilirdi.
      expect(params['invite_email'], isNull);
    });

    test('boş e-posta da adressiz sayılır', () async {
      final api = _FakeApi()..onRpc = (_, _) => 'token-abc';

      await SupabaseGateway(api).createInvite('grup-1', email: '   ');

      expect(api.calls.single.params['invite_email'], isNull);
    });

    test('adrese yazılı davet adresi taşır', () async {
      final api = _FakeApi()..onRpc = (_, _) => 'token-abc';

      await SupabaseGateway(
        api,
      ).createInvite('grup-1', email: '  biri@posta.com ');

      expect(api.calls.single.params['invite_email'], 'biri@posta.com');
    });

    test('daveti kabul etmek girilen grubu döner', () async {
      final api = _FakeApi()..onRpc = (_, _) => 'grup-7';

      final gid = await SupabaseGateway(api).acceptInvite('  token-abc  ');

      expect(gid, 'grup-7');
      // Kopyala-yapıştır boşluk taşır; sunucuya temizi gitmeli.
      expect(api.calls.single.params['invite_token'], 'token-abc');
    });

    test('gruptan çıkmak üyelik satırını siler', () async {
      final api = _FakeApi();

      await SupabaseGateway(api).leaveGroup('grup-1');

      expect(api.left, ['grup-1']);
      // Bir RPC değil: politika zaten "kendi üyeliğini bırakabilir" diyor.
      expect(api.calls, isEmpty);
    });
  });
}
