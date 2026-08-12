import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/app_config.dart';
import 'package:scheduler_app/core/connectivity.dart';
import 'package:scheduler_app/data/app_store.dart';
import 'package:scheduler_app/data/local_store.dart';
import 'package:scheduler_app/data/sync/mutation.dart';
import 'package:scheduler_app/data/sync/outbox.dart';
import 'package:scheduler_app/data/sync/remote_gateway.dart';
import 'package:scheduler_app/data/sync/sync_engine.dart';
import 'package:scheduler_app/models/habit.dart';
import 'package:scheduler_app/models/node.dart';
import 'package:scheduler_app/models/task.dart';

/// Y1 — artımlı çekim ve birleştirme.
///
/// Buradaki testlerin ortak sorusu tek: **karşı tarafın değişikliği geliyor mu,
/// benimkini ezmeden?**

Task _task(String title, {DateTime? updatedAt, String? id}) => Task(
  id: id,
  title: title,
  color: const Color(0xFF4FC3F7),
  date: DateTime(2026, 8, 10),
  startHour: 9,
  updatedAt: updatedAt,
);

/// Sunucudan gelmiş gibi görünen artımlı görüntü.
Map<String, dynamic> _incoming({
  List<Map<String, dynamic>> nodes = const [],
  List<Map<String, dynamic>> habits = const [],
  List<String> deletedIds = const [],
  String? cursor,
}) => {
  'schemaVersion': 3,
  'nodes': nodes,
  'habits': habits,
  'deletedIds': deletedIds,
  'cursor': ?cursor,
};

/// Testte platform eklentisi yok ve gerçek servis "çevrimdışı" diyor —
/// güvenli varsayım ama burada sınamak istediğimiz şeyin önünü kesiyor.
class _AlwaysOnline extends ConnectivityService {
  @override
  Future<NetworkStatus> current() async => NetworkStatus.online;

  @override
  Stream<NetworkStatus> watch() => const Stream.empty();
}

class _FakeGateway implements RemoteGateway {
  _FakeGateway({this.snapshot});

  Map<String, dynamic>? snapshot;
  final List<DateTime?> pulledSince = [];
  final List<List<Mutation>> pushed = [];
  bool throwOnPull = false;

  /// Sunucunun "bir şey değişti" dediği yer (Y2).
  // Kullanan testler addTearDown ile kapatıyor.
  // ignore: close_sinks
  final signals = StreamController<void>.broadcast();

  @override
  bool get isConfigured => true;

  @override
  Stream<void> get remoteChanges => signals.stream;

  @override
  Future<PushResult> push(List<Mutation> mutations) async {
    pushed.add(mutations);
    return PushResult(accepted: [for (final m in mutations) m.id]);
  }

  @override
  Future<Map<String, dynamic>?> pull({DateTime? since}) async {
    pulledSince.add(since);
    if (throwOnPull) throw Exception('ağ koptu');
    return snapshot;
  }

  @override
  Future<PushResult> pushSnapshot(Map<String, dynamic> s) async =>
      PushResult.empty;
}

void main() {
  setUp(TaskRepository.all.clear);

  group('birleştirme', () {
    test('sunucudan gelen yeni kayıt yerele eklenir', () {
      final store = AppStore();
      expect(store.tasks, isEmpty);

      store.mergeJson(_incoming(nodes: [_task('Karşı taraftan').toJson()]));

      expect(store.tasks.single.title, 'Karşı taraftan');
    });

    test('daha yeni damgalı kayıt yereldekini günceller', () {
      final store = AppStore();
      final mine = _task('Eski hâli', updatedAt: DateTime(2026, 8, 10, 9));
      store.addTask(mine);

      store.mergeJson(
        _incoming(
          nodes: [
            _task(
              'Yeni hâli',
              id: mine.id,
              updatedAt: DateTime(2026, 8, 10, 12),
            ).toJson(),
          ],
        ),
      );

      expect(store.tasks, hasLength(1));
      expect(store.tasks.single.title, 'Yeni hâli');
    });

    test('eski damgalı kayıt yerelde olanı EZMEZ', () {
      // Hakem sunucudaki `apply_mutations` ile birebir aynı olmalı: iki taraf
      // farklı kural kullansaydı iki cihaz farklı sonuca varırdı.
      final store = AppStore();
      final mine = _task('Benim yenim', updatedAt: DateTime(2026, 8, 10, 15));
      store.addTask(mine);

      store.mergeJson(
        _incoming(
          nodes: [
            _task(
              'Sunucunun eskisi',
              id: mine.id,
              updatedAt: DateTime(2026, 8, 10, 9),
            ).toJson(),
          ],
        ),
      );

      expect(store.tasks.single.title, 'Benim yenim');
    });

    test('mezar taşı yereldeki kaydı siler', () {
      // Bunlar olmadan silme taşınamaz: artımlı çekimde "gelmedi" ile
      // "silindi" ayırt edilemez.
      final store = AppStore();
      final job = _task('Silinecek');
      store.addTask(job);

      store.mergeJson(_incoming(deletedIds: [job.id]));

      expect(store.tasks, isEmpty);
    });

    test('notlar ve alışkanlıklar da birleşir', () {
      final store = AppStore();
      final note = Note(title: 'Uzaktan not', body: 'gövde');
      final habit = Habit(title: 'Su iç', color: const Color(0xFF81C784));

      store.mergeJson(
        _incoming(nodes: [note.toJson()], habits: [habit.toJson()]),
      );

      expect(store.notes.single.title, 'Uzaktan not');
      expect(store.habits.single.title, 'Su iç');
    });

    test(
      'birleştirme mutasyon üretmez — sunucudan geleni geri göndermeyiz',
      () async {
        // Üretseydi her çekilen kayıt kuyruğa girip geri gönderilirdi: sonsuz
        // bir eko.
        final disk = InMemoryStore();
        await disk.init();
        final outbox = Outbox(disk);
        final store = AppStore();
        await store.attachPersistence(disk, outbox: outbox);

        store.mergeJson(_incoming(nodes: [_task('Uzaktan').toJson()]));

        expect(outbox.isEmpty, isTrue);
      },
    );

    test('iki cihaz aynı sunucu görüntüsünde buluşur', () {
      // Planın "bitti sayılır" ölçütü: A'da yapılan değişiklik B'de belirir.
      final a = AppStore();
      final job = _task('A nın işi');
      a.addTask(job);

      final wire = _incoming(nodes: [for (final t in a.tasks) t.toJson()]);

      TaskRepository.all.clear();
      final b = AppStore();
      b.mergeJson(wire);

      expect(b.tasks.single.title, 'A nın işi');
      expect(b.tasks.single.id, job.id);
    });
  });

  group('senkron motoru — çekim', () {
    Future<(SyncEngine, _FakeGateway, InMemoryStore, AppStore)> engine({
      Map<String, dynamic>? snapshot,
    }) async {
      final disk = InMemoryStore();
      await disk.init();
      final gateway = _FakeGateway(snapshot: snapshot);
      final store = AppStore();
      final e = SyncEngine(
        outbox: Outbox(disk),
        gateway: gateway,
        connectivity: _AlwaysOnline(),
        store: disk,
      )..mergeHandler = store.mergeJson;
      addTearDown(e.dispose);
      return (e, gateway, disk, store);
    }

    test('kuyruk boşken de çeker', () async {
      // Artımlı çekimin bütün amacı bu: hiçbir yerel değişiklik olmadan
      // karşı taraftan geleni almak. Eski motor burada erken dönüyordu.
      final (e, gateway, _, store) = await engine(
        snapshot: _incoming(nodes: [_task('Uzaktan gelen').toJson()]),
      );

      await e.syncNow();

      expect(gateway.pulledSince, hasLength(1));
      expect(store.tasks.single.title, 'Uzaktan gelen');
    });

    test('imleç yokken epoch\'tan başlar', () async {
      // `since: null` tam çekim demek ve tam çekim yerel durumu **ezer** —
      // o karar oturum açılışına ait, motorun sessizce vereceği bir karar değil.
      final (e, gateway, _, _) = await engine(snapshot: _incoming());

      await e.syncNow();

      expect(gateway.pulledSince.single, isNotNull);
      expect(gateway.pulledSince.single!.millisecondsSinceEpoch, 0);
    });

    test('imleç başarılı birleştirmeden sonra ilerler', () async {
      final (e, _, disk, _) = await engine(
        snapshot: _incoming(cursor: '2026-08-11T10:00:00.000Z'),
      );

      await e.syncNow();

      expect(disk.readString(kSyncCursorKey), '2026-08-11T10:00:00.000Z');
    });

    test('sunucu boş dönerse imleç yerinde kalır', () async {
      // Yarıda kalan ya da boş bir tur, bir daha hiç gelmeyecek kayıtlar
      // bırakmamalı.
      final (e, _, disk, _) = await engine(snapshot: _incoming());
      await disk.writeString(kSyncCursorKey, '2026-08-01T00:00:00.000Z');

      await e.syncNow();

      expect(disk.readString(kSyncCursorKey), '2026-08-01T00:00:00.000Z');
    });

    test('çekim patlarsa imleç ilerlemez', () async {
      final (e, gateway, disk, _) = await engine(snapshot: _incoming());
      await disk.writeString(kSyncCursorKey, '2026-08-01T00:00:00.000Z');
      gateway.throwOnPull = true;

      await e.syncNow();

      expect(disk.readString(kSyncCursorKey), '2026-08-01T00:00:00.000Z');
    });

    test('kayıtlı imleç sunucuya aynen gider', () async {
      final (e, gateway, disk, _) = await engine(snapshot: _incoming());
      await disk.writeString(kSyncCursorKey, '2026-08-05T12:30:00.000Z');

      await e.syncNow();

      expect(
        gateway.pulledSince.single!.toUtc().toIso8601String(),
        '2026-08-05T12:30:00.000Z',
      );
    });

    test('imleç başa alınınca çekim epoch\'tan sorar', () async {
      // Y3e. Gruba bugün katılan biri için imleç bir tuzak: grubun geçen
      // hafta yazılmış satırları imlecin gerisinde kalır, `fetchSince` kesin
      // büyük filtrelediği için onları hiç sormaz ve kullanıcı grubu **boş**
      // görür — hata da almadan.
      final (e, gateway, disk, _) = await engine(snapshot: _incoming());
      await disk.writeString(kSyncCursorKey, '2026-08-05T12:30:00.000Z');

      await e.resetPullCursor();
      await e.syncNow();

      expect(gateway.pulledSince.last!.millisecondsSinceEpoch, 0);
    });

    test('imleç başa alınınca çekim kendiliğinden koşar', () async {
      // Üyelik değişimi bir sonraki turu beklememeli: katılan kişi grubu
      // hemen görmeli.
      final (e, gateway, _, store) = await engine(
        snapshot: _incoming(nodes: [_task('Grubun işi').toJson()]),
      );

      await e.resetPullCursor();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(gateway.pulledSince, hasLength(1));
      expect(store.tasks.single.title, 'Grubun işi');
    });

    test('realtime sinyali çekimi tetikler', () async {
      // Y2 olmadan Y1 boşta kalıyordu: uygulama dururken hiçbir şey çekimi
      // tetiklemiyor, yani karşı tarafın değişikliği yine gelmiyordu.
      final (e, gateway, _, store) = await engine(snapshot: _incoming());
      addTearDown(gateway.signals.close);

      e.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final afterStart = gateway.pulledSince.length;

      gateway.snapshot = _incoming(
        nodes: [_task('Karşı taraf ekledi').toJson()],
      );
      gateway.signals.add(null);
      await Future<void>.delayed(
        AppConfig.syncDebounce + const Duration(milliseconds: 400),
      );

      expect(gateway.pulledSince.length, afterStart + 1);
      expect(store.tasks.single.title, 'Karşı taraf ekledi');
    });

    test('art arda gelen sinyaller tek çekimde birleşir', () async {
      // Karşı taraftaki bir sürükleme oturumu onlarca satır değiştirebilir;
      // her olayda çekim yapmak gidiş-dönüş israfı olurdu.
      final (e, gateway, _, _) = await engine(snapshot: _incoming());
      addTearDown(gateway.signals.close);

      e.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final afterStart = gateway.pulledSince.length;

      for (var i = 0; i < 10; i++) {
        gateway.signals.add(null);
      }
      await Future<void>.delayed(
        AppConfig.syncDebounce + const Duration(milliseconds: 400),
      );

      expect(gateway.pulledSince.length, afterStart + 1);
    });

    test('birleştirici bağlı değilse motor yalnız gönderir', () async {
      // Eski davranış korunuyor: çekimi açmak tek satırlık bir bağlama işi.
      final disk = InMemoryStore();
      await disk.init();
      final gateway = _FakeGateway(snapshot: _incoming());
      final e = SyncEngine(
        outbox: Outbox(disk),
        gateway: gateway,
        connectivity: _AlwaysOnline(),
        store: disk,
      );
      addTearDown(e.dispose);

      await e.syncNow();

      expect(gateway.pulledSince, isEmpty);
    });
  });
}
