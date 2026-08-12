import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/group_context.dart';
import 'package:scheduler_app/data/app_store.dart';
import 'package:scheduler_app/data/local_store.dart';
import 'package:scheduler_app/data/persistence_providers.dart';
import 'package:scheduler_app/data/sync/mutation.dart';
import 'package:scheduler_app/data/sync/remote_gateway.dart';
import 'package:scheduler_app/models/group.dart';
import 'package:scheduler_app/models/habit.dart';
import 'package:scheduler_app/models/node.dart';
import 'package:scheduler_app/models/task.dart';

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
}

const _mavi = Color(0xFF4FC3F7);

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
}
