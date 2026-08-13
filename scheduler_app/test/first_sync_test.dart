import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/data/app_store.dart';
import 'package:scheduler_app/data/local_store.dart';
import 'package:scheduler_app/data/sync/first_sync.dart';
import 'package:scheduler_app/data/sync/mutation.dart';
import 'package:scheduler_app/data/sync/outbox.dart';
import 'package:scheduler_app/data/sync/remote_gateway.dart';
import 'package:scheduler_app/models/group.dart';
import 'package:scheduler_app/models/profile.dart';
import 'package:scheduler_app/models/task.dart';

/// Sunucu yerine geçen sahte. Ne çekildiğini ve ne basıldığını sayar.
class _FakeGateway implements RemoteGateway {
  _FakeGateway({this.remote});

  Map<String, dynamic>? remote;
  Map<String, dynamic>? pushedSnapshot;
  int pullCount = 0;

  @override
  bool get isConfigured => true;

  @override
  Stream<void> get remoteChanges => const Stream.empty();

  @override
  Future<PushResult> push(List<Mutation> mutations) async => PushResult.empty;

  @override
  Future<Map<String, dynamic>?> pull({DateTime? since}) async {
    pullCount++;
    return remote;
  }

  @override
  Future<PushResult> pushSnapshot(Map<String, dynamic> snapshot) async {
    pushedSnapshot = snapshot;
    return PushResult.empty;
  }

  @override
  Future<List<Group>> fetchGroups() async => const [];
  @override
  Future<List<Profile>> fetchProfiles() async => const [];
  @override
  Future<void> updateDisplayName(String displayName) async =>
      throw UnimplementedError('bu test ad değiştirmiyor');
  @override
  Future<Group> createGroup(String name) async =>
      throw UnimplementedError('bu test grup kurmuyor');

  @override
  Future<String> createInvite(String groupId, {String? email}) async =>
      throw UnimplementedError('bu test davet üretmiyor');

  @override
  Future<String> acceptInvite(String token) async =>
      throw UnimplementedError('bu test davet kabul etmiyor');

  @override
  Future<void> leaveGroup(String groupId) async =>
      throw UnimplementedError('bu test gruptan çıkmıyor');
}

Map<String, dynamic> _snapshotWithTask(String title) => {
  'schemaVersion': 3,
  'nodes': [
    Task(
      title: title,
      color: const Color(0xFF4FC3F7),
      date: DateTime(2026, 8, 10),
    ).toJson(),
  ],
  'habits': const [],
  'categories': const [],
};

/// Testlerin çoğu kuyrukla ilgilenmiyor; bu yardımcı gürültüyü alıyor.
FirstSyncCoordinator _coordinator(
  RemoteGateway gateway,
  AppStore store, {
  Outbox? outbox,
}) => FirstSyncCoordinator(
  gateway: gateway,
  store: store,
  outbox: outbox ?? Outbox(InMemoryStore()),
);

void main() {
  setUp(TaskRepository.all.clear);

  group('karar', () {
    test('iki taraf da boşsa yapacak bir şey yok', () {
      expect(
        FirstSyncCoordinator.plan(localHasData: false, remoteHasData: false),
        FirstSyncPlan.nothing,
      );
    });

    test('sunucu boşsa cihaz yüklenir — soru sorulmaz', () {
      // Soracak bir şey yok: kullanıcının cihazdaki takvimi tek gerçek.
      expect(
        FirstSyncCoordinator.plan(localHasData: true, remoteHasData: false),
        FirstSyncPlan.upload,
      );
    });

    test('cihaz boşsa sunucu indirilir', () {
      expect(
        FirstSyncCoordinator.plan(localHasData: false, remoteHasData: true),
        FirstSyncPlan.download,
      );
    });

    test('ikisinde de veri varsa karar kullanıcının', () {
      // Bu tek satır, planın A4 kararı. Otomatik seçim yapmak ya aylardır
      // cihazda duran takvimi ya da hesaptakini sessizce silerdi.
      expect(
        FirstSyncCoordinator.plan(localHasData: true, remoteHasData: true),
        FirstSyncPlan.ask,
      );
    });
  });

  group('inceleme', () {
    test('boş sunucu + dolu cihaz → yükle', () async {
      final store = AppStore();
      store.addTask(
        Task(
          title: 'Yerel iş',
          color: const Color(0xFF4FC3F7),
          date: DateTime(2026, 8, 10),
        ),
      );
      final gateway = _FakeGateway(remote: {'nodes': [], 'habits': []});

      final decision = await _coordinator(gateway, store).inspect();

      expect(decision.plan, FirstSyncPlan.upload);
    });

    test(
      'dolu sunucu + boş cihaz → indir, görüntü kararla birlikte gelir',
      () async {
        final gateway = _FakeGateway(remote: _snapshotWithTask('Uzak iş'));

        final decision = await _coordinator(gateway, AppStore()).inspect();

        expect(decision.plan, FirstSyncPlan.download);
        // Görüntü kararla taşınıyor: ikinci kez çekmek hem fazladan bir tur hem
        // de bir yarış olurdu — kullanıcı gördüğünden başkasını onaylardı.
        expect(decision.remote, isNotNull);
        expect(gateway.pullCount, 1);
      },
    );

    test('yalnız kategorisi olan sunucu boş sayılır', () async {
      // Varsayılan kategoriler her kurulumda var; onlara bakmak her sunucuyu
      // dolu gösterir ve gereksiz yere soru sordururdu.
      final store = AppStore();
      store.addTask(
        Task(
          title: 'Yerel',
          color: const Color(0xFF4FC3F7),
          date: DateTime(2026, 8, 10),
        ),
      );
      final gateway = _FakeGateway(
        remote: {
          'nodes': const [],
          'habits': const [],
          'categories': [
            {'name': 'İş', 'colorHex': 'FF4FC3F7'},
          ],
        },
      );

      final decision = await _coordinator(gateway, store).inspect();

      expect(decision.plan, FirstSyncPlan.upload);
    });
  });

  group('uygulama', () {
    test('yükleme tam görüntüyü basar', () async {
      final store = AppStore();
      store.addTask(
        Task(
          title: 'Yerel iş',
          color: const Color(0xFF4FC3F7),
          date: DateTime(2026, 8, 10),
        ),
      );
      final gateway = _FakeGateway();

      await _coordinator(gateway, store).apply(FirstSyncPlan.upload);

      expect(gateway.pushedSnapshot, isNotNull);
      expect(gateway.pushedSnapshot!['nodes'] as List, hasLength(1));
    });

    test('indirme yerel durumu sunucununkiyle değiştirir', () async {
      final store = AppStore();
      store.addTask(
        Task(
          title: 'Yerel iş',
          color: const Color(0xFF4FC3F7),
          date: DateTime(2026, 8, 10),
        ),
      );

      await _coordinator(
        _FakeGateway(),
        store,
      ).apply(FirstSyncPlan.download, remote: _snapshotWithTask('Uzak iş'));

      expect(store.tasks, hasLength(1));
      expect(store.tasks.single.title, 'Uzak iş');
    });

    test('"sor" kararı kendi başına hiçbir şey yapmaz', () async {
      // Çağıran onu önce kullanıcıya sorup upload/download'a çevirmeli.
      // Buraya sızarsa sessizce hiçbir şey yapmalı, tahminde bulunmamalı.
      final store = AppStore();
      store.addTask(
        Task(
          title: 'Yerel iş',
          color: const Color(0xFF4FC3F7),
          date: DateTime(2026, 8, 10),
        ),
      );
      final gateway = _FakeGateway();

      await _coordinator(gateway, store).apply(FirstSyncPlan.ask);

      expect(gateway.pushedSnapshot, isNull);
      expect(store.tasks, hasLength(1));
    });

    test('indirme bekleyen kuyruğu da temizler', () async {
      // Bu testin varlık sebebi somut bir hata: bekleyen mutasyonlar,
      // kullanıcının az önce terk etmeyi seçtiği yerel durumu anlatıyor.
      // Bırakılsalardı gönderilir ve silinen işleri sunucuda diriltirdi —
      // "indir" sessizce "birleştir"e dönerdi.
      final store = AppStore();
      final outbox = Outbox(InMemoryStore());
      await store.attachPersistence(InMemoryStore(), outbox: outbox);
      store.addTask(
        Task(
          title: 'Yerel iş',
          color: const Color(0xFF4FC3F7),
          date: DateTime(2026, 8, 10),
        ),
      );
      expect(outbox.isEmpty, isFalse);

      await _coordinator(
        _FakeGateway(),
        store,
        outbox: outbox,
      ).apply(FirstSyncPlan.download, remote: _snapshotWithTask('Uzak iş'));

      expect(outbox.isEmpty, isTrue);
      expect(store.tasks.single.title, 'Uzak iş');
    });

    test('görüntüsüz indirme yerel veriyi silmez', () async {
      // Savunma: çağıran görüntüyü unutursa `loadJson({})` bütün takvimi
      // silerdi.
      final store = AppStore();
      store.addTask(
        Task(
          title: 'Yerel iş',
          color: const Color(0xFF4FC3F7),
          date: DateTime(2026, 8, 10),
        ),
      );

      await _coordinator(_FakeGateway(), store).apply(FirstSyncPlan.download);

      expect(store.tasks, hasLength(1));
    });
  });
}
