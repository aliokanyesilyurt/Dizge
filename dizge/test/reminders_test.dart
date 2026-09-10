import 'package:dizge/core/reminders.dart';
import 'package:dizge/data/app_store.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/data/persistence_providers.dart';
import 'package:dizge/models/task.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// N2 — hatırlatma planı: depodan hesaplanır, platforma topluca yazılır.
void main() {
  setUp(TaskRepository.all.clear);

  // Pazartesi 09:00. Testlerin hepsi bu "şimdi"ye göre.
  final now = DateTime(2026, 9, 14, 9);
  final today = Task.dayKey(now);
  const on = ReminderSettings(leadMinutes: 0);

  Task at(
    double hour, {
    DateTime? date,
    Repeat repeat = const Repeat(RepeatType.once),
  }) => Task(
    title: 'İş $hour',
    color: Colors.blue,
    date: date ?? today,
    startHour: hour,
    repeat: repeat,
  );

  group('plan', () {
    test('saatli iş kendi saatinde, önceden-süre kadar erken düşer', () {
      final plan = planReminders(
        [at(14)],
        now: now,
        settings: const ReminderSettings(leadMinutes: 10),
      );

      expect(plan, hasLength(1));
      expect(plan.single.at, DateTime(2026, 9, 14, 13, 50));
      expect(plan.single.body, '10 dk sonra · 14:00');
    });

    test('geçmiş, saatsiz, tamamlanmış ve havuzdaki iş kurulmaz', () {
      final done = at(15)..setDone(today, true);
      final pooled = at(16)..inPool = true;
      final untimed = Task(title: 'Saatsiz', color: Colors.blue, date: today);

      final plan = planReminders(
        [at(8), done, pooled, untimed],
        now: now,
        settings: on,
      );

      expect(plan, isEmpty);
    });

    test('rutin her gün düşer; iptal edilen gün atlanır', () {
      final routine = at(7, repeat: const Repeat(RepeatType.daily))
        ..setSkipped(today.add(const Duration(days: 2)), true);

      final plan = planReminders([routine], now: now, settings: on);

      // Bugün 07:00 geçti; önümüzdeki 6 günden biri iptal → 5.
      expect(plan, hasLength(5));
      expect(
        plan.map((r) => r.at.day),
        isNot(contains(today.add(const Duration(days: 2)).day)),
      );
    });

    test('rutinler kapatılınca yalnız tek günlük işler kalır', () {
      final plan = planReminders(
        [at(20), at(10, repeat: const Repeat(RepeatType.daily))],
        now: now,
        settings: const ReminderSettings(
          leadMinutes: 0,
          includeRoutines: false,
        ),
      );

      expect(plan.map((r) => r.title), ['İş 20.0']);
    });

    test('çoklu saatte her tekrar ayrı; biten tekrar düşer', () {
      final pills = at(10)..setTimes([10, 14, 20]);
      pills.setSlotDone(today, 14, true);

      final plan = planReminders([pills], now: now, settings: on, days: 1);

      expect(plan.map((r) => r.at.hour), [10, 20]);
    });

    test('kapalıyken hiçbir şey kurulmaz', () {
      final plan = planReminders(
        [at(14)],
        now: now,
        settings: const ReminderSettings(enabled: false),
      );
      expect(plan, isEmpty);
    });

    test('başkasının grup işi hatırlatılmaz, kendininki hatırlatılır', () {
      final mine = Task(
        title: 'Benim',
        color: Colors.blue,
        date: today,
        startHour: 12,
        groupId: 'g1',
        ownerId: 'ben',
      );
      final theirs = Task(
        title: 'Onun',
        color: Colors.blue,
        date: today,
        startHour: 12,
        groupId: 'g1',
        ownerId: 'o',
      );

      final plan = planReminders(
        [mine, theirs],
        now: now,
        settings: on,
        myId: 'ben',
      );

      expect(plan.map((r) => r.title), ['Benim']);
    });

    test('en yakından uzağa sıralı ve üst sınırla kesilir', () {
      final tasks = [for (var h = 23.0; h >= 10; h--) at(h)];
      final plan = planReminders(tasks, now: now, settings: on, cap: 3);

      expect(plan.map((r) => r.at.hour), [10, 11, 12]);
    });

    test('kimlik kararlı, pozitif ve işe özgü', () {
      final task = at(14);
      final a = planReminders([task], now: now, settings: on).single;
      final b = planReminders([task], now: now, settings: on).single;
      final other = planReminders([at(14)], now: now, settings: on).single;

      expect(a.id, b.id, reason: 'aynı tekrar her hesapta aynı kimlik');
      expect(a.id, greaterThan(0));
      expect(other.id, isNot(a.id), reason: 'başka iş, başka kimlik');
    });
  });

  group('ayarlar', () {
    test('diske yazılır ve geri okunur', () async {
      final disk = InMemoryStore();
      final c1 = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(disk)],
      );
      await c1
          .read(reminderSettingsProvider.notifier)
          .update(
            const ReminderSettings(leadMinutes: 30, includeRoutines: false),
          );

      final c2 = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(disk)],
      );
      expect(
        c2.read(reminderSettingsProvider),
        const ReminderSettings(leadMinutes: 30, includeRoutines: false),
      );
    });

    test('bozuk kayıt varsayılana düşer', () {
      final disk = InMemoryStore()..writeString(kReminderSettingsKey, '{bozuk');
      final c = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(disk)],
      );
      expect(c.read(reminderSettingsProvider), const ReminderSettings());
    });
  });

  group('zamanlayıcı', () {
    test('depo değişince plan birikip bir kez yazılır', () {
      fakeAsync((async) {
        final gateway = NoopReminderGateway();
        final c = ProviderContainer(
          overrides: [
            localStoreProvider.overrideWithValue(InMemoryStore()),
            reminderGatewayProvider.overrideWithValue(gateway),
          ],
        );
        final scheduler = ReminderScheduler(_RefProbe.of(c), clock: () => now);
        scheduler.start();
        async.elapse(const Duration(seconds: 3));
        final baseline = gateway.replaceCalls;

        final store = c.read(appStoreProvider);
        store.addTask(at(14));
        store.addTask(at(15));
        store.addTask(at(16));
        async.elapse(const Duration(seconds: 3));

        expect(
          gateway.replaceCalls,
          baseline + 1,
          reason: 'üç değişiklik tek tur',
        );
        expect(gateway.scheduled, hasLength(3));

        scheduler.dispose();
        c.dispose();
      });
    });

    test('ilk hatırlatmada izin bir kez istenir', () {
      fakeAsync((async) {
        final gateway = _CountingGateway();
        final disk = InMemoryStore();
        final c = ProviderContainer(
          overrides: [
            localStoreProvider.overrideWithValue(disk),
            reminderGatewayProvider.overrideWithValue(gateway),
          ],
        );
        final scheduler = ReminderScheduler(_RefProbe.of(c), clock: () => now)
          ..start();

        c.read(appStoreProvider).addTask(at(14));
        async.elapse(const Duration(seconds: 3));
        c.read(appStoreProvider).addTask(at(15));
        async.elapse(const Duration(seconds: 3));

        expect(gateway.asks, 1);
        expect(disk.readString(kReminderAskedKey), 'yes');

        scheduler.dispose();
        c.dispose();
      });
    });
  });
}

class _CountingGateway extends NoopReminderGateway {
  int asks = 0;

  @override
  Future<ReminderPermission> requestPermission() async {
    asks++;
    return ReminderPermission.granted;
  }
}

/// Zamanlayıcı bir `Ref` istiyor; testte onu bir provider'ın içinden almanın
/// en kısa yolu.
class _RefProbe {
  static final _provider = Provider<Ref>((ref) => ref);
  static Ref of(ProviderContainer c) => c.read(_provider);
}
