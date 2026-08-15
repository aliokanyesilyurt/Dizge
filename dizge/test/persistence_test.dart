import 'package:dizge/data/app_store.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/data/sync/mutation.dart';
import 'package:dizge/data/sync/outbox.dart';
import 'package:dizge/models/habit.dart';
import 'package:dizge/models/node.dart';
import 'package:dizge/models/task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(TaskRepository.all.clear);

  group('AppStore kalıcılık', () {
    test('değişiklikler diske yazılır ve yeniden yüklenir', () async {
      final store = InMemoryStore();
      await store.init();

      final a = AppStore();
      await a.attachPersistence(store);
      a.addTask(
        Task(
          title: 'Toplantı',
          color: const Color(0xFF5AA9FF),
          date: DateTime(2026, 8, 3),
          startHour: 14,
          durationHours: 1.5,
        ),
      );
      a.addNote(Note(title: 'Notlar', body: 'içerik'));
      a.addHabit(Habit(title: 'Su iç', color: const Color(0xFF34E39B)));
      // Debounce'u beklemeden zorla indir.
      await a.flush();

      // Yeni bir oturum: depo aynı, bellek sıfır.
      TaskRepository.all.clear();
      final b = AppStore();
      await b.attachPersistence(store);

      expect(b.tasks, hasLength(1));
      expect(b.tasks.single.title, 'Toplantı');
      expect(b.tasks.single.startHour, 14);
      expect(b.notes.single.title, 'Notlar');
      expect(b.habits.single.title, 'Su iç');
    });

    test('özel kategoriler de kalıcıdır', () async {
      final store = InMemoryStore();
      await store.init();

      final a = AppStore();
      await a.attachPersistence(store);
      a.addCategory(const TaskCategory('Tez', Color(0xFFA78BFA)));
      await a.flush();

      // Kategoriler statik olduğu için sıfırla, sonra yeniden yükle.
      AppData.categories = [const TaskCategory('Diğer', Color(0xFFF2E14C))];
      final b = AppStore();
      await b.attachPersistence(store);

      expect(AppData.categories.map((c) => c.name), contains('Tez'));
    });

    test('alışkanlığın damgası kaydedilir ve geri okunur', () async {
      final store = InMemoryStore();
      await store.init();

      final a = AppStore();
      await a.attachPersistence(store);
      a.addHabit(Habit(title: 'Koş', color: const Color(0xFF34E39B)));
      final stamped = a.habits.single.updatedAt;
      await a.flush();

      final b = AppStore();
      await b.attachPersistence(store);

      expect(b.habits.single.updatedAt, stamped);
    });

    test('alışkanlık değiştiğinde damga tazelenir', () async {
      final store = InMemoryStore();
      await store.init();

      final a = AppStore();
      await a.attachPersistence(store);
      final habit = Habit(
        title: 'Koş',
        color: const Color(0xFF34E39B),
        // Geçmişe damgala ki tazelenme ölçülebilsin.
        updatedAt: DateTime(2026, 1, 5),
      );
      a.addHabit(habit);

      a.toggleHabit(habit, DateTime(2026, 8, 10));

      expect(habit.updatedAt.isAfter(DateTime(2026, 1, 5)), isTrue);
    });

    test('sürüm 2 kaydındaki alışkanlık damgayı createdAt\'ten alır', () async {
      // LWW hakemi damga olduğu için bu göç önemli: alan eksikken `readDate`
      // her açılışta `DateTime.now()` üretirdi. O alışkanlık, sunucudaki
      // kopyasını her seferinde "daha yeniyim" diye ezerdi — üstelik hiç
      // değişmemişken.
      final store = InMemoryStore();
      await store.init();
      await store.writeSnapshot({
        'schemaVersion': 2,
        'nodes': const [],
        'habits': [
          {
            'id': 'h1',
            'title': 'Su iç',
            'colorHex': 'FF81C784',
            'cadence': 'daily',
            'targetPerWeek': 3,
            'doneDates': const [],
            'createdAt': DateTime(2026, 1, 5).toIso8601String(),
            // 'updatedAt' bilerek yok — sürüm 2 kaydı böyle görünüyordu.
          },
        ],
        'categories': const [],
      });

      final a = AppStore();
      await a.attachPersistence(store);

      expect(a.habits.single.updatedAt, DateTime(2026, 1, 5));

      // Aynı kayıt eski paletten de geliyor (`FF81C784` pastel yeşil): renk
      // okunurken neon karşılığına taşınıyor. Göçün birim testi
      // `category_colors_test.dart`'ta; buradaki iddia aynı çevrimin gerçek
      // yükleme yolunda — anlık görüntü → AppStore — da işlediğini gösteriyor.
      expect(a.habits.single.color, const Color(0xFF34E39B));
    });

    test('bozuk kayıt uygulamayı düşürmez, boş başlar', () async {
      final store = InMemoryStore();
      await store.init();
      // Şema dışı bir görüntü yaz.
      await store.writeSnapshot({'nodes': 'bu bir liste değil'});

      final a = AppStore();
      await a.attachPersistence(store); // fırlatmamalı
      expect(a.tasks, isEmpty);
    });

    test('hidrasyon sırasında senkron kuyruğu dolmaz', () async {
      final store = InMemoryStore();
      await store.init();
      final outbox = Outbox(store);

      final a = AppStore();
      await a.attachPersistence(store, outbox: outbox);
      a.addTask(
        Task(
          title: 'X',
          color: const Color(0xFF5AA9FF),
          date: DateTime(2026, 8, 3),
        ),
      );
      await a.flush();
      expect(outbox.length, 1);

      // İkinci oturum: diskten okunan veri sunucuya geri gönderilmemeli.
      TaskRepository.all.clear();
      final freshOutbox = Outbox(store);
      final b = AppStore();
      await b.attachPersistence(store, outbox: freshOutbox);
      expect(b.tasks, hasLength(1));
      expect(
        freshOutbox.length,
        1,
        reason: 'yalnızca diskten yüklenen eski kuyruk; yeni kayıt eklenmemeli',
      );
    });
  });

  group('grup alanları (Y4)', () {
    Task grupIsi() => Task(
      title: 'Grubun işi',
      color: const Color(0xFF5AA9FF),
      date: DateTime(2026, 8, 12),
      groupId: 'grup-1',
      ownerId: 'ali',
    );

    test('grup ve köken JSON turunda korunur', () {
      final geri = Task.fromJson(grupIsi().toJson());

      expect(geri.groupId, 'grup-1');
      expect(geri.ownerId, 'ali');
    });

    test('kişisel kayıt grup anahtarını null olarak yazar', () {
      // Anahtarın **yokluğu** sunucuda "grubuna dokunma" demek. Kişisel bir
      // kaydın susması, "işi gruptan çıkardım"ın hiç gitmemesi olurdu.
      final json = Task(
        title: 'Kişisel',
        color: const Color(0xFF5AA9FF),
        date: DateTime(2026, 8, 12),
      ).toJson();

      expect(json.containsKey('groupId'), isTrue);
      expect(json['groupId'], isNull);
      // Köken sunucunun yazdığı bir alan; boşken her kayda serpilmez.
      expect(json.containsKey('ownerId'), isFalse);
    });

    test('not ve alışkanlık da taşır', () {
      final not = Note.fromJson(
        Note(title: 'Not', groupId: 'grup-1', ownerId: 'ali').toJson(),
      );
      final aliskanlik = Habit.fromJson(
        Habit(
          title: 'Su iç',
          color: const Color(0xFF34E39B),
          groupId: 'grup-1',
        ).toJson(),
      );

      expect(not.groupId, 'grup-1');
      expect(not.ownerId, 'ali');
      expect(aliskanlik.groupId, 'grup-1');
    });

    test('copy() grubu ve kökeni korur', () {
      // Geri alma bu yoldan geçiyor: düşseydi undo, grup işini sessizce
      // kişiselleştirirdi.
      final kopya = grupIsi().copy();

      expect(kopya.groupId, 'grup-1');
      expect(kopya.ownerId, 'ali');
    });

    test('duplicateTo() grubu devralır, kökeni devralmaz', () {
      // Grup işini kopyalamak o grupta çalışmaktır. Kökeni devralmak ise
      // kopyayı yazmadığı bir kişiye mal etmek olurdu.
      final kopya = grupIsi().duplicateTo(DateTime(2026, 8, 13));

      expect(kopya.groupId, 'grup-1');
      expect(kopya.ownerId, isNull);
    });
  });

  group('Outbox', () {
    late InMemoryStore store;
    late Outbox outbox;

    setUp(() async {
      store = InMemoryStore();
      await store.init();
      outbox = Outbox(store);
    });

    Mutation upsert(String id, {String title = 'x'}) => Mutation(
      kind: EntityKind.task,
      op: MutationOp.upsert,
      entityId: id,
      payload: {'title': title},
    );

    test('aynı kaydın ardışık güncellemeleri tek kayda daraltılır', () {
      // Sürükle-bırak sırasında tipik: aynı işe onlarca kez dokunulur.
      for (var i = 0; i < 20; i++) {
        outbox.enqueue(upsert('task-1', title: 'v$i'));
      }
      expect(outbox.length, 1);
      expect(
        outbox.pending.single.payload['title'],
        'v19',
        reason: 'kuyruk kaydın son hâlini taşımalı',
      );
    });

    test('silme, o kayda ait bekleyen güncellemeleri düşürür', () {
      outbox.enqueue(upsert('task-1'));
      outbox.enqueue(upsert('task-2'));
      outbox.enqueue(
        Mutation(
          kind: EntityKind.task,
          op: MutationOp.delete,
          entityId: 'task-1',
          payload: const {},
        ),
      );

      expect(outbox.length, 2);
      expect(
        outbox.pending.where((m) => m.entityId == 'task-1').single.op,
        MutationOp.delete,
      );
    });

    test('ack gönderilenleri kuyruktan çıkarır', () {
      outbox.enqueue(upsert('a'));
      outbox.enqueue(upsert('b'));
      final ids = outbox.pending.map((m) => m.id).toList();

      outbox.ack([ids.first]);
      expect(outbox.length, 1);
      expect(outbox.pending.single.entityId, 'b');
    });

    test('sürekli başarısız olan kayıt kuyruğu tıkamaz', () {
      outbox.enqueue(upsert('zehirli'));
      final id = outbox.pending.single.id;

      for (var i = 0; i < 3; i++) {
        outbox.markFailed([id], maxAttempts: 3);
      }
      expect(outbox.length, 0);
      expect(
        outbox.needsFullPush,
        isTrue,
        reason: 'kayıp mutasyon sonrası tam senkron gerekir',
      );
    });

    test('kuyruk diske yazılıp geri okunur', () async {
      outbox.enqueue(upsert('a'));
      outbox.enqueue(upsert('b'));
      await outbox.persist();

      final reloaded = Outbox(store)..load();
      expect(reloaded.length, 2);
      expect(reloaded.pending.map((m) => m.entityId), containsAll(['a', 'b']));
    });
  });

  group('Mutation', () {
    test('JSON round-trip tüm alanları korur', () {
      final m = Mutation(
        kind: EntityKind.habit,
        op: MutationOp.delete,
        entityId: 'h1',
        payload: const {'k': 'v'},
        attempts: 2,
      );
      final clone = Mutation.fromJson(m.toJson());

      expect(clone.id, m.id);
      expect(clone.kind, EntityKind.habit);
      expect(clone.op, MutationOp.delete);
      expect(clone.entityId, 'h1');
      expect(clone.attempts, 2);
    });
  });
}
