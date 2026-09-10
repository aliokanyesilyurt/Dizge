/// Hatırlatmalar: ayarlar, plan ve bildirim kapısı (N1–N3).
///
/// Eski servis her `addTask`/`updateTask` çağrısında tek bir bildirim kurup
/// siliyordu. O yol üç şeyi kaçırıyordu: rutinler ve çoklu saatler hiç
/// kurulmuyordu, başka cihazdan senkronla gelen iş hiçbir zaman
/// `addTask`'tan geçmediği için hatırlatılmıyordu, tamamlanan/iptal edilen
/// işin bildirimi de düşmeye devam ediyordu.
///
/// Şimdiki model tek kaynaklı: depo değiştikçe önümüzdeki günlerin bütün
/// hatırlatmaları **baştan hesaplanıyor** ([planReminders]) ve platforma
/// topluca yazılıyor ([ReminderGateway.replaceAll]). Hangi yoldan gelirse
/// gelsin iş, depoya girdiği anda plana da girer.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../data/local_store.dart';
import '../data/persistence_providers.dart';
import '../models/task.dart';
import 'auth_service.dart';

// --- Ayarlar -----------------------------------------------------------------

/// "Ne kadar önce" seçenekleri, dakika. 0 = tam saatinde.
const List<int> kReminderLeadChoices = [0, 5, 10, 15, 30];

/// Ayarların yerel depodaki anahtarı. Cihaza özgü: bildirim izni de, "bu
/// cihazda beni rahatsız etme" isteği de cihazın kendisine ait.
const String kReminderSettingsKey = 'reminder_settings';

/// Bildirim izni bu cihazda bir kez soruldu mu?
const String kReminderAskedKey = 'reminder_permission_asked';

class ReminderSettings {
  const ReminderSettings({
    this.enabled = true,
    this.leadMinutes = 10,
    this.includeRoutines = true,
  });

  final bool enabled;
  final int leadMinutes;

  /// Günlük rutinler her gün aynı saatte düşer; bazısı için bu gürültü.
  final bool includeRoutines;

  ReminderSettings copyWith({
    bool? enabled,
    int? leadMinutes,
    bool? includeRoutines,
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    leadMinutes: leadMinutes ?? this.leadMinutes,
    includeRoutines: includeRoutines ?? this.includeRoutines,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'leadMinutes': leadMinutes,
    'includeRoutines': includeRoutines,
  };

  /// Bozuk ya da eski kayıt varsayılana düşer: ayar ekranı açılamaz hâle
  /// gelmesin.
  factory ReminderSettings.fromJson(Map<String, dynamic> j) {
    final lead = (j['leadMinutes'] as num?)?.toInt() ?? 10;
    return ReminderSettings(
      enabled: j['enabled'] as bool? ?? true,
      leadMinutes: kReminderLeadChoices.contains(lead) ? lead : 10,
      includeRoutines: j['includeRoutines'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.enabled == enabled &&
      other.leadMinutes == leadMinutes &&
      other.includeRoutines == includeRoutines;

  @override
  int get hashCode => Object.hash(enabled, leadMinutes, includeRoutines);
}

class ReminderSettingsController extends StateNotifier<ReminderSettings> {
  ReminderSettingsController(this._store) : super(_read(_store));

  final LocalStore _store;

  static ReminderSettings _read(LocalStore store) {
    final raw = store.readString(kReminderSettingsKey);
    if (raw == null || raw.isEmpty) return const ReminderSettings();
    try {
      return ReminderSettings.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return const ReminderSettings();
    }
  }

  Future<void> update(ReminderSettings next) async {
    if (next == state) return;
    state = next;
    await _store.writeString(kReminderSettingsKey, jsonEncode(next.toJson()));
  }
}

final reminderSettingsProvider =
    StateNotifierProvider<ReminderSettingsController, ReminderSettings>(
      (ref) => ReminderSettingsController(ref.watch(localStoreProvider)),
    );

// --- Plan --------------------------------------------------------------------

/// Kurulacak tek bir hatırlatma.
class Reminder {
  const Reminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });

  /// Platformun bildirim kimliği. Kararlı: aynı işin aynı tekrarı her
  /// hesaplamada aynı kimliği alır.
  final int id;
  final DateTime at;
  final String title;
  final String body;

  @override
  String toString() => 'Reminder($id, $at, $title)';
}

/// Metinden kararlı, pozitif, 31 bitlik bir kimlik (FNV-1a).
///
/// `String.hashCode` kullanılmıyor: Dart onun çalıştırmalar arasında aynı
/// kalacağını garanti etmiyor. Android kimliği 32 bitlik işaretli tamsayı
/// istiyor; üst bit atılıyor ki negatif çıkmasın.
int stableReminderId(String key) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(key)) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// Önümüzdeki [days] günün hatırlatmaları, en yakından uzağa, en çok [cap].
///
/// Kapsam dışında kalanlar ve sebepleri:
///   * saatsiz iş — hatırlatacak bir an yok;
///   * o gün tamamlanmış ya da iptal edilmiş iş — hatırlatmak alay etmek olur;
///   * havuzdaki iş — `occursOn` onu zaten hiçbir güne koymuyor;
///   * başkasının grup işi — grubun takvimini paylaşmak, arkadaşının
///     randevusunda senin telefonunun çalması demek olmamalı.
///
/// Üst sınırın sebebi platform: iOS 64 bekleyen bildirimden fazlasını
/// sessizce atıyor, Android'de alarm sayısının da bir tavanı var. Pencere
/// kaydıkça plan yeniden hesaplandığı için sınır bir kayıp değil.
List<Reminder> planReminders(
  Iterable<Task> tasks, {
  required DateTime now,
  required ReminderSettings settings,
  String? myId,
  int days = 7,
  int cap = 60,
}) {
  if (!settings.enabled) return const [];

  final lead = Duration(minutes: settings.leadMinutes);
  final today = Task.dayKey(now);
  final out = <Reminder>[];

  for (final task in tasks) {
    if (task.isRoutine && !settings.includeRoutines) continue;
    if (task.groupId != null &&
        task.ownerId != null &&
        myId != null &&
        task.ownerId != myId) {
      continue;
    }
    final hours = task.occurrenceHours;
    if (hours.isEmpty) continue;

    for (var i = 0; i < days; i++) {
      final day = today.add(Duration(days: i));
      if (!task.occursOn(day) || task.isDoneOn(day) || task.isSkippedOn(day)) {
        continue;
      }
      for (final hour in hours) {
        if (task.hasManyTimes && task.isSlotDone(day, hour)) continue;
        final start = day.add(Duration(minutes: (hour * 60).round()));
        final at = start.subtract(lead);
        if (!at.isAfter(now)) continue;

        out.add(
          Reminder(
            id: stableReminderId('${task.id}|${Task.slotKey(day, hour)}'),
            at: at,
            title: task.title,
            body: _body(task, hour, settings.leadMinutes),
          ),
        );
      }
    }
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > cap ? out.sublist(0, cap) : out;
}

String _body(Task task, double hour, int lead) {
  final when = lead == 0
      ? 'Şimdi · ${Task.formatTime(hour)}'
      : '$lead dk sonra · ${Task.formatTime(hour)}';
  final place = task.place.trim();
  return place.isEmpty ? when : '$when · $place';
}

// --- Platform kapısı ---------------------------------------------------------

/// Bildirim izninin durumu. `unknown`: platform söylemiyor (masaüstü) — orada
/// izin ayrı bir adım değil, sistem ayarı.
enum ReminderPermission { granted, denied, unknown }

/// Platform bildirimlerine açılan kapı. Uygulamanın geri kalanı eklentiyi
/// tanımıyor (`AuthService` ile aynı desen); testler [NoopReminderGateway]
/// ile koşuyor ve hiçbir yerel kanala dokunmuyor.
abstract class ReminderGateway {
  Future<void> init();
  Future<ReminderPermission> permission();

  /// İzni ister. Açılışta değil, kullanıcı bir sebep gördüğünde çağrılır.
  Future<ReminderPermission> requestPermission();

  /// Bekleyen bütün hatırlatmaları siler ve [reminders]'ı kurar.
  Future<void> replaceAll(List<Reminder> reminders);

  /// "Deneme bildirimi" — hemen.
  Future<void> showNow({required String title, required String body});

  /// Sistemin bu uygulamaya ait bildirim ayarlarını açar.
  Future<void> openSystemSettings();
}

class NoopReminderGateway implements ReminderGateway {
  NoopReminderGateway();

  /// Son kurulan plan — testler bunu okuyor.
  List<Reminder> scheduled = const [];
  int replaceCalls = 0;
  final List<String> shown = [];
  ReminderPermission current = ReminderPermission.unknown;

  @override
  Future<void> init() async {}

  @override
  Future<ReminderPermission> permission() async => current;

  @override
  Future<ReminderPermission> requestPermission() async => current;

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    replaceCalls++;
    scheduled = List.unmodifiable(reminders);
  }

  @override
  Future<void> showNow({required String title, required String body}) async =>
      shown.add(title);

  @override
  Future<void> openSystemSettings() async {}
}

/// Üretimde `bootstrap()` gerçek kapıyı geçirir.
final reminderGatewayProvider = Provider<ReminderGateway>(
  (ref) => NoopReminderGateway(),
);

// --- Zamanlayıcı -------------------------------------------------------------

/// Depoyu ve ayarları izleyip planı platforma yazar.
///
/// Değişiklikler birkaç saniye biriktiriliyor: sürükleyip bırakmak ya da
/// senkronun elli satırı birden getirmesi, elli ayrı "hepsini sil, yeniden
/// kur" turu olmamalı. Saatlik tur, yedi günlük pencerenin kaymasını
/// karşılıyor — uygulama günlerce açık kalırsa sekizinci günün hatırlatması
/// da zamanında kurulur.
class ReminderScheduler {
  ReminderScheduler(
    this._ref, {
    this.debounce = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Ref _ref;
  final Duration debounce;
  final DateTime Function() _clock;

  Timer? _pending;
  Timer? _hourly;
  AppStore? _store;

  void start() {
    final store = _ref.read(appStoreProvider);
    store.addListener(_schedule);
    _store = store;
    _ref.listen(reminderSettingsProvider, (_, _) => _schedule());
    _ref.listen(authUserProvider, (_, _) => _schedule());
    _hourly = Timer.periodic(const Duration(hours: 1), (_) => _schedule());
    _schedule();
  }

  void _schedule() {
    _pending?.cancel();
    _pending = Timer(debounce, () => unawaited(runNow()));
  }

  /// Planı şimdi hesaplar ve yazar. Hata yutuluyor: bildirim kurulamadı diye
  /// takvimin kendisi hiçbir zaman düşmemeli.
  Future<void> runNow() async {
    final AppStore store = _store ?? _ref.read(appStoreProvider);
    final plan = planReminders(
      store.tasks,
      now: _clock(),
      settings: _ref.read(reminderSettingsProvider),
      myId: _ref.read(authUserProvider).valueOrNull?.id,
    );
    try {
      final gateway = _ref.read(reminderGatewayProvider);
      if (plan.isNotEmpty) await _askOnce(gateway);
      await gateway.replaceAll(plan);
    } catch (_) {
      // Sessiz: bir sonraki değişiklik yeniden deneyecek.
    }
  }

  /// İzin açılışta değil, **ilk hatırlatma kurulacakken** bir kez soruluyor.
  ///
  /// Eski servis uygulamanın ilk saniyesinde, kullanıcı daha tek bir iş
  /// yazmadan soruyordu; bağlamsız bir izin penceresi çoğu zaman "hayır" alır
  /// ve Android ikinci kez sormaya izin vermez. Cevap ne olursa olsun bir daha
  /// burada sorulmaz — sonrası Bildirimler sayfasının işi.
  Future<void> _askOnce(ReminderGateway gateway) async {
    final store = _ref.read(localStoreProvider);
    if (store.readString(kReminderAskedKey) == 'yes') return;
    await store.writeString(kReminderAskedKey, 'yes');
    await gateway.requestPermission();
  }

  void dispose() {
    _pending?.cancel();
    _hourly?.cancel();
    _store?.removeListener(_schedule);
  }
}

/// Yalnız `bootstrap()` okuyor; testlerde kendiliğinden kurulmaz (zamanlayıcı
/// widget testlerinin "bekleyen Timer" denetimine takılırdı).
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  final scheduler = ReminderScheduler(ref);
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
