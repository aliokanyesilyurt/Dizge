import 'dart:convert';

import 'package:dizge/core/group_context.dart';
import 'package:dizge/data/app_store.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/data/persistence_providers.dart';
import 'package:dizge/data/sync/mutation.dart';
import 'package:dizge/data/sync/outbox.dart';
import 'package:dizge/data/sync/remote_gateway.dart';
import 'package:dizge/data/sync/supabase_api.dart';
import 'package:dizge/models/group.dart';
import 'package:dizge/models/habit.dart';
import 'package:dizge/models/node.dart';
import 'package:dizge/models/profile.dart';
import 'package:dizge/models/task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Y4.2 — bağlam seçici ve süzgeç.
///
/// Buradaki testlerin ortak sorusu: **kullanıcı hangi bağlamda ne görüyor ve
/// ürettiği iş kimin oluyor?** Süzgecin yanlış tarafa düşmesi, kullanıcının
/// işini "kayboldu" sanmasıyla aynı şey.

class _FakeGateway implements RemoteGateway {
  _FakeGateway({this.groups = const []});

  List<Group> groups;
  bool throwOnFetch = false;
  int fetchCount = 0;

  @override
  bool get isConfigured => true;

  @override
  Stream<void> get remoteChanges => const Stream.empty();

  @override
  Future<PushResult> push(List<Mutation> mutations) async => PushResult.empty;

  @override
  Future<Map<String, dynamic>?> pull({DateTime? since}) async => null;

  @override
  Future<PushResult> pushSnapshot(Map<String, dynamic> snapshot) async =>
      PushResult.empty;

  @override
  Future<List<Group>> fetchGroups() async {
    fetchCount++;
    if (throwOnFetch) throw Exception('ağ koptu');
    return groups;
  }

  // --- Profiller (Y4.4) ------------------------------------------------------

  List<Profile> profiles = const [];
  bool throwOnProfiles = false;
  int profileFetchCount = 0;
  final List<String> renamed = [];

  @override
  Future<List<Profile>> fetchProfiles() async {
    profileFetchCount++;
    if (throwOnProfiles) throw Exception('ağ koptu');
    return profiles;
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    _maybeFail();
    renamed.add(displayName);
  }

  @override
  Future<void> updateAvatarColor(int color) async {}

  // --- Grup işlemleri --------------------------------------------------------

  /// Sunucunun reddi: sıradaki grup çağrısı bununla düşer.
  RemoteException? nextFailure;

  final List<String> created = [];
  final List<({String groupId, String? email})> invited = [];
  final List<String> accepted = [];
  final List<String> left = [];

  void _maybeFail() {
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
  }

  @override
  Future<Group> createGroup(String name) async {
    _maybeFail();
    created.add(name);
    final group = Group(id: 'yeni-${created.length}', name: name.trim());
    groups = [...groups, group];
    return group;
  }

  @override
  Future<String> createInvite(String groupId, {String? email}) async {
    _maybeFail();
    invited.add((groupId: groupId, email: email));
    return 'davet-token-${invited.length}';
  }

  @override
  Future<String> acceptInvite(String token) async {
    _maybeFail();
    accepted.add(token);
    // Sunucu daveti kabul edince kullanıcı artık üye: liste de öyle döner.
    groups = [...groups, _ev];
    return _ev.id;
  }

  @override
  Future<void> leaveGroup(String groupId) async {
    _maybeFail();
    left.add(groupId);
    groups = [
      for (final g in groups)
        if (g.id != groupId) g,
    ];
  }
}

const _mavi = Color(0xFF38BDF8);

const _ekip = Group(id: 'g1', name: 'Ekip');
const _ev = Group(id: 'g2', name: 'Ev');

Task _task(
  String title, {
  String? groupId,
  bool inPool = false,
  Repeat? repeat,
}) => Task(
  title: title,
  color: _mavi,
  date: DateTime(2026, 8, 10),
  startHour: inPool ? null : 9,
  inPool: inPool,
  repeat: repeat ?? const Repeat.once(),
  groupId: groupId,
);

/// Kapsayıcıyı testin istediği depo ve sahte sunucuyla kurar.
ProviderContainer _container({LocalStore? store, RemoteGateway? gateway}) {
  final container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store ?? InMemoryStore()),
      remoteGatewayProvider.overrideWithValue(gateway ?? _FakeGateway()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(TaskRepository.all.clear);

  group('bağlam hatırlanır', () {
    test('açılışta kayıtlı bağlam ve önbellekteki gruplar geri gelir', () {
      final store = InMemoryStore();
      store.writeString(kActiveGroupKey, 'g1');
      store.writeString(
        kGroupsCacheKey,
        jsonEncode([_ekip.toJson(), _ev.toJson()]),
      );

      final ctx = _container(store: store).read(groupContextProvider);

      expect(ctx.activeId, 'g1');
      expect(ctx.label, 'Ekip');
      expect(ctx.groups, [_ekip, _ev]);
    });

    test('boş kayıt Kişisel demektir', () {
      final store = InMemoryStore();
      store.writeString(kActiveGroupKey, '');

      final ctx = _container(store: store).read(groupContextProvider);

      expect(ctx.isPersonal, isTrue);
      expect(ctx.label, 'Kişisel');
    });

    test('bozuk önbellek açılışı düşürmez', () {
      final store = InMemoryStore();
      store.writeString(kGroupsCacheKey, 'bu JSON değil');

      expect(
        _container(store: store).read(groupContextProvider).groups,
        isEmpty,
      );
    });

    test('seçim anında diske yazılır', () async {
      final store = InMemoryStore();
      final container = _container(store: store);

      await container.read(groupContextProvider.notifier).select('g1');

      expect(store.readString(kActiveGroupKey), 'g1');
      expect(container.read(activeGroupIdProvider), 'g1');
    });

    test('Kişisel e dönüş de yazılır', () async {
      final store = InMemoryStore();
      store.writeString(kActiveGroupKey, 'g1');
      final container = _container(store: store);

      await container.read(groupContextProvider.notifier).select(null);

      expect(store.readString(kActiveGroupKey), '');
      expect(container.read(activeGroupIdProvider), isNull);
    });
  });

  group('liste tazeleme', () {
    test('sunucudan gelen liste önbelleğe yazılır', () async {
      final store = InMemoryStore();
      final gateway = _FakeGateway(groups: [_ekip, _ev]);
      final container = _container(store: store, gateway: gateway);

      await container.read(groupContextProvider.notifier).refresh();

      expect(container.read(groupContextProvider).groups, [_ekip, _ev]);
      expect(jsonDecode(store.readString(kGroupsCacheKey)!), [
        _ekip.toJson(),
        _ev.toJson(),
      ]);
    });

    test('hata yutulur, son bilinen liste ekranda kalır', () async {
      final store = InMemoryStore();
      store.writeString(kGroupsCacheKey, jsonEncode([_ekip.toJson()]));
      final gateway = _FakeGateway()..throwOnFetch = true;
      final container = _container(store: store, gateway: gateway);

      await container.read(groupContextProvider.notifier).refresh();

      expect(gateway.fetchCount, 1);
      expect(container.read(groupContextProvider).groups, [_ekip]);
    });

    test('üyelik düşerse bağlam Kişisel e döner (Y4d)', () async {
      final store = InMemoryStore();
      store.writeString(kActiveGroupKey, 'g1');
      store.writeString(kGroupsCacheKey, jsonEncode([_ekip.toJson()]));
      final container = _container(
        store: store,
        // Sunucu artık o grubu göndermiyor: kullanıcı gruptan çıkarıldı.
        gateway: _FakeGateway(groups: const []),
      );

      await container.read(groupContextProvider.notifier).refresh();

      expect(container.read(groupContextProvider).isPersonal, isTrue);
      expect(store.readString(kActiveGroupKey), '');
    });

    test('üyelik sürüyorsa bağlam korunur', () async {
      final store = InMemoryStore();
      store.writeString(kActiveGroupKey, 'g1');
      final container = _container(
        store: store,
        gateway: _FakeGateway(groups: [_ekip, _ev]),
      );

      await container.read(groupContextProvider.notifier).refresh();

      expect(container.read(groupContextProvider).activeId, 'g1');
    });
  });

  group('süzgeç (Y4b)', () {
    test('kişisel bağlam grup işlerini göstermez', () {
      final container = _container();
      final store = container.read(appStoreProvider);
      store.addTask(_task('Kendi işim'));
      store.addTask(_task('Grubun işi', groupId: 'g1'));

      final week = container.read(tasksForWeekProvider(DateTime(2026, 8, 10)));

      expect([for (final day in week) ...day].map((t) => t.title), [
        'Kendi işim',
      ]);
    });

    test('grup bağlamı yalnız o grubun işlerini gösterir', () async {
      final container = _container();
      final store = container.read(appStoreProvider);
      store.addTask(_task('Kendi işim'));
      store.addTask(_task('Ekibin işi', groupId: 'g1'));
      store.addTask(_task('Evin işi', groupId: 'g2'));

      await container.read(groupContextProvider.notifier).select('g1');

      final day = container.read(tasksForDateProvider(DateTime(2026, 8, 10)));
      expect(day.map((t) => t.title), ['Ekibin işi']);
    });

    test('havuz, yapılacaklar ve rutinler de süzülür', () async {
      final container = _container();
      final store = container.read(appStoreProvider);
      store.addTask(_task('Kenarda kişisel', inPool: true));
      store.addTask(_task('Kenarda grup', inPool: true, groupId: 'g1'));
      store.addTask(
        _task(
          'Grup rutini',
          groupId: 'g1',
          repeat: const Repeat(RepeatType.daily),
        ),
      );

      await container.read(groupContextProvider.notifier).select('g1');

      expect(container.read(poolProvider).map((t) => t.title), [
        'Kenarda grup',
      ]);
      expect(container.read(routinesProvider).map((t) => t.title), [
        'Grup rutini',
      ]);
      expect(container.read(todosProvider).map((t) => t.title), [
        'Kenarda grup',
      ]);
    });

    test('notlar ve alışkanlıklar da süzülür', () async {
      final container = _container();
      final store = container.read(appStoreProvider);
      store.addNote(Note(title: 'Kişisel not'));
      store.addNote(Note(title: 'Grup notu', groupId: 'g1'));
      store.addHabit(Habit(title: 'Kişisel alışkanlık', color: _mavi));
      store.addHabit(
        Habit(title: 'Grup alışkanlığı', color: _mavi, groupId: 'g1'),
      );

      await container.read(groupContextProvider.notifier).select('g1');

      expect(container.read(notesProvider).map((n) => n.title), ['Grup notu']);
      expect(container.read(habitsProvider).map((h) => h.title), [
        'Grup alışkanlığı',
      ]);
    });
  });

  group('bağlamda üretilen iş o bağlamın olur (Y4c)', () {
    test('grup bağlamında açılan görev grubun kimliğini taşır', () async {
      final container = _container();
      await container.read(groupContextProvider.notifier).select('g1');

      final store = container.read(appStoreProvider);
      final task = _task('Toplantı');
      store.addTask(task);

      expect(task.groupId, 'g1');
      // Damga mutasyona da girmeli, yoksa sunucuda kişisel olarak yazılırdı.
      expect(task.toJson()['groupId'], 'g1');
    });

    test('kişisel bağlamda üretilen iş kişisel kalır', () {
      final container = _container();
      final store = container.read(appStoreProvider);
      final task = _task('Alışveriş');
      store.addTask(task);

      expect(task.groupId, isNull);
    });

    test('açıkça verilmiş grup, bağlam damgasıyla ezilmez', () async {
      final container = _container();
      await container.read(groupContextProvider.notifier).select('g1');

      final store = container.read(appStoreProvider);
      final task = _task('Ev işi', groupId: 'g2');
      store.addTask(task);

      expect(task.groupId, 'g2');
    });

    test('not ve alışkanlık da bağlamı alır', () async {
      final container = _container();
      await container.read(groupContextProvider.notifier).select('g1');

      final store = container.read(appStoreProvider);
      final note = Note(title: 'Karar');
      final habit = Habit(title: 'Günlük yürüyüş', color: _mavi);
      store.addNote(note);
      store.addHabit(habit);

      expect(note.groupId, 'g1');
      expect(habit.groupId, 'g1');
    });

    test('bağlam değişince depo yeniden kurulmaz', () async {
      final container = _container();
      final before = container.read(appStoreProvider);
      before.addTask(_task('Duran iş'));

      await container.read(groupContextProvider.notifier).select('g1');

      // Aynı örnek: `watch` olsaydı bellekteki takvim gider, kullanıcı bağlam
      // değiştirdiği anda her şeyin yeniden yüklenmesini beklerdi.
      expect(identical(container.read(appStoreProvider), before), isTrue);
      expect(before.tasks, hasLength(1));
    });
  });

  group('grup işlemleri (Y4.3)', () {
    test('kurulan grup listeye girer ve bağlam ona taşınır', () async {
      final store = InMemoryStore();
      final gateway = _FakeGateway();
      final container = _container(store: store, gateway: gateway);

      final group = await container.read(groupActionsProvider).create('Ekip');

      expect(gateway.created, ['Ekip']);
      expect(container.read(groupContextProvider).groups, [group]);
      expect(container.read(activeGroupIdProvider), group.id);
      // Kalıcı: uygulama kapanıp açılınca da aynı grupta olunmalı.
      expect(store.readString(kActiveGroupKey), group.id);
      expect(store.readString(kGroupsCacheKey), contains('Ekip'));
    });

    test('kurma sunucudan tazelemeye bağlı değil', () async {
      final gateway = _FakeGateway();
      final container = _container(gateway: gateway);
      final before = gateway.fetchCount;

      await container.read(groupActionsProvider).create('Ekip');

      // Tazeleme hatayı yutuyor; ağ o anda düşseydi kullanıcı az önce
      // kurduğu grubu göremezdi.
      expect(gateway.fetchCount, before);
      expect(container.read(groupContextProvider).groups, hasLength(1));
    });

    test('grup adı listede sıralı durur', () async {
      final container = _container(gateway: _FakeGateway(groups: [_ev]));
      await container.read(groupContextProvider.notifier).refresh();

      await container.read(groupActionsProvider).create('Anahtar');

      expect(container.read(groupContextProvider).groups.map((g) => g.name), [
        'Anahtar',
        'Ev',
      ]);
    });

    test('davet token u üretilir ve e-posta iletilir', () async {
      final gateway = _FakeGateway();
      final container = _container(gateway: gateway);

      final token = await container
          .read(groupActionsProvider)
          .invite('g1', email: 'biri@posta.com');

      expect(token, 'davet-token-1');
      expect(gateway.invited.single.groupId, 'g1');
      expect(gateway.invited.single.email, 'biri@posta.com');
    });

    test('kabul edilen davet gruba sokar ve bağlamı oraya taşır', () async {
      final gateway = _FakeGateway();
      final container = _container(gateway: gateway);

      await container.read(groupActionsProvider).accept('  token  ');

      expect(gateway.accepted, ['  token  ']);
      expect(container.read(activeGroupIdProvider), _ev.id);
      expect(container.read(groupContextProvider).label, 'Ev');
    });

    test('sunucu reddi çağırana taşınır, bağlam değişmez', () async {
      final gateway = _FakeGateway()
        ..nextFailure = const RemoteException('davet zaten kullanılmış');
      final container = _container(gateway: gateway);

      await expectLater(
        container.read(groupActionsProvider).accept('token'),
        throwsA(isA<RemoteException>()),
      );
      expect(container.read(groupContextProvider).isPersonal, isTrue);
    });
  });

  group('gruptan çıkmak (Y4d)', () {
    test('o grubun yerel satırları silinir, kişisel olanlar durur', () async {
      final gateway = _FakeGateway(groups: [_ekip, _ev]);
      final container = _container(gateway: gateway);
      await container.read(groupContextProvider.notifier).refresh();

      final store = container.read(appStoreProvider);
      store.addTask(_task('Kişisel iş'));
      store.addTask(_task('Ekibin işi', groupId: 'g1'));
      store.addTask(_task('Evin işi', groupId: 'g2'));
      store.addNote(Note(title: 'Ekip notu', groupId: 'g1'));
      store.addHabit(
        Habit(title: 'Ekip alışkanlığı', color: _mavi, groupId: 'g1'),
      );

      await container.read(groupActionsProvider).leave('g1');

      expect(gateway.left, ['g1']);
      expect(store.tasks.map((t) => t.title), ['Kişisel iş', 'Evin işi']);
      expect(store.notes, isEmpty);
      expect(store.habits, isEmpty);
    });

    test('silme outbox a yazılmaz — karşı tarafta kalmalı', () async {
      final store = InMemoryStore();
      final outbox = Outbox(store)..load();
      final container = _container(gateway: _FakeGateway(groups: [_ekip]));
      await container.read(groupContextProvider.notifier).refresh();

      final appStore = container.read(appStoreProvider);
      await appStore.attachPersistence(store, outbox: outbox);
      appStore.addTask(_task('Ekibin işi', groupId: 'g1'));
      final beforeDeletes = outbox.pending
          .where((m) => m.op == MutationOp.delete)
          .length;

      await container.read(groupActionsProvider).leave('g1');

      expect(appStore.tasks, isEmpty);
      expect(
        outbox.pending.where((m) => m.op == MutationOp.delete).length,
        beforeDeletes,
        reason: 'gruptan çıkmak bir senkron değil, görüş alanının daralması',
      );
    });

    test('çıkılan grup listeden düşer ve bağlam Kişisel e döner', () async {
      final store = InMemoryStore();
      final container = _container(
        store: store,
        gateway: _FakeGateway(groups: [_ekip]),
      );
      await container.read(groupContextProvider.notifier).refresh();
      await container.read(groupContextProvider.notifier).select('g1');

      await container.read(groupActionsProvider).leave('g1');

      expect(container.read(groupContextProvider).groups, isEmpty);
      expect(container.read(groupContextProvider).isPersonal, isTrue);
      expect(store.readString(kActiveGroupKey), '');
    });

    test('sunucu reddederse yerel satırlar durur', () async {
      final gateway = _FakeGateway(groups: [_ekip])
        ..nextFailure = const RemoteException('ağ koptu');
      final container = _container(gateway: gateway);
      final store = container.read(appStoreProvider);
      store.addTask(_task('Ekibin işi', groupId: 'g1'));

      await expectLater(
        container.read(groupActionsProvider).leave('g1'),
        throwsA(isA<RemoteException>()),
      );
      // Sıra bu yüzden sabit: önce sunucu. Tersi olsaydı kullanıcı hâlâ üye
      // olduğu bir grubun işlerini kaybederdi.
      expect(store.tasks, hasLength(1));
    });
  });
}
