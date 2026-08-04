import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_config.dart';
import '../core/telemetry.dart';
import '../core/time_grid.dart';
import '../models/habit.dart';
import '../models/node.dart';
import '../models/task.dart';
import '../services/link_index.dart';
import 'local_store.dart';
import 'sync/mutation.dart';
import 'sync/outbox.dart';

/// Uygulamanın merkezi, reaktif deposu (mimari karar: state management).
///
/// GEÇİŞ NOTU: Görevler için tek gerçek kaynak hâlâ [TaskRepository]'dir; bu
/// store onun üstüne reaktif bir katman koyar (değişince `notifyListeners`).
/// Böylece eski ekranlar (statik repo + setState) hiç bozulmadan çalışmaya
/// devam eder, yeni ekranlar ise `ref.watch(appStoreProvider)` ile otomatik
/// güncellenir. Yeni yazılan/taşınan kod mutasyonları BU store üzerinden
/// yapmalı ki dinleyiciler haberdar olsun.
///
/// ÜRETİM EKLERİ (bu sürümde):
///   * **Kalıcılık** — [attachPersistence] ile şifreli [LocalStore]'a bağlanır;
///     her mutasyon debounce'lu olarak diske yazılır.
///   * **Offline-first** — aynı mutasyon [Outbox]'a da düşer; bağlantı gelince
///     senkron motoru sunucuya boşaltır. Yerel her zaman önce yazılır, UI
///     ağı beklemez.
///   * **Telemetri** — mutasyonların *şekli* (sayı/enum) ölçülür, içeriği asla.
class AppStore extends ChangeNotifier {
  AppStore({Telemetry telemetry = const NoopTelemetry()})
    : _telemetry = telemetry;

  final Telemetry _telemetry;

  final List<Note> _notes = [];
  final List<Habit> _habits = [];

  // --- Kalıcılık bağlantısı --------------------------------------------------

  LocalStore? _store;
  Outbox? _outbox;
  Timer? _persistDebounce;

  /// Hidrasyon (diskten yükleme) sırasında true; bu esnada tetiklenen
  /// mutasyonlar tekrar diske yazılmaz ve outbox'a düşmez.
  bool _hydrating = false;

  /// Diske yazılmayı bekleyen değişiklik var mı? Uygulama arka plana giderken
  /// [flush] ile zorlanır.
  bool _dirty = false;

  bool get hasPendingWrites => _dirty;

  /// Depoyu bağlar ve varsa kayıtlı durumu yükler. Bootstrap'ta bir kez çağrılır.
  Future<void> attachPersistence(LocalStore store, {Outbox? outbox}) async {
    _store = store;
    _outbox = outbox;
    outbox?.load();

    final snapshot = store.readSnapshot();
    if (snapshot != null) {
      _hydrating = true;
      try {
        loadJson(snapshot);
      } catch (e, s) {
        debugPrint('Kayıtlı durum yüklenemedi: $e\n$s');
        _telemetry.capture(Ev.appError, props: {'area': 'hydrate'});
      } finally {
        _hydrating = false;
      }
    }
    notifyListeners();
  }

  /// Bekleyen yazmayı hemen diske indirir (uygulama kapanırken/arka plana
  /// giderken çağrılır — debounce penceresinde veri kaybı olmasın).
  Future<void> flush() async {
    _persistDebounce?.cancel();
    await _writeNow();
    await _outbox?.persist();
  }

  void _schedulePersist() {
    final store = _store;
    if (store == null || _hydrating) return;
    _dirty = true;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(AppConfig.persistDebounce, () {
      unawaited(_writeNow());
    });
  }

  Future<void> _writeNow() async {
    final store = _store;
    if (store == null || !_dirty) return;
    try {
      await store.writeSnapshot(toJson());
      _dirty = false;
    } catch (e, s) {
      // Diske yazamamak sessizce geçilmemeli ama kullanıcı akışını da kesmemeli.
      debugPrint('Yerel kayıt başarısız: $e\n$s');
      _telemetry.capture(Ev.persistFailed);
    }
  }

  /// Mutasyonu senkron kuyruğuna yazar. Hidrasyon sırasında atlanır (diskten
  /// okunan veriyi sunucuya geri göndermek anlamsız).
  void _record(
    EntityKind kind,
    MutationOp op,
    String entityId,
    Map<String, dynamic> payload,
  ) {
    if (_hydrating) return;
    _outbox?.enqueue(
      Mutation(kind: kind, op: op, entityId: entityId, payload: payload),
    );
  }

  // --- Okuma -----------------------------------------------------------------

  List<Task> get tasks => TaskRepository.all;
  List<Note> get notes => List.unmodifiable(_notes);
  List<Habit> get habits => List.unmodifiable(_habits);

  /// LinkIndex ve arama için tüm node'lar (görev + not).
  List<Node> get nodes => [...TaskRepository.all, ..._notes];

  List<Task> tasksForDate(DateTime day) => TaskRepository.forDate(day);

  /// Bir haftanın 7 gününün görevleri (pazartesiden itibaren). Haftalık ızgara
  /// tek geçişte tüm haftayı ister; gün gün `forDate` çağırmak listeyi 7 kez
  /// taramak olurdu.
  List<List<Task>> tasksForWeek(DateTime monday) {
    final start = Task.dayKey(monday);
    return List.generate(
      7,
      (i) => TaskRepository.forDate(start.add(Duration(days: i))),
    );
  }

  Node? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Task? taskById(String id) {
    for (final t in TaskRepository.all) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// `[[ ]]` bağlantı indeksi. Her erişimde güncel node'lardan kurulur; böylece
  /// görevler eski TaskRepository yolu üzerinden düzenlense de bayat kalmaz.
  /// (Veri seti büyürse burada önbellek + invalidasyon eklenebilir.)
  LinkIndex get linkIndex => LinkIndex.build(nodes);

  /// [id]'ye link veren node'lar (backlink paneli).
  List<Node> backlinkNodes(String id) =>
      linkIndex.linksTo(id).map(nodeById).whereType<Node>().toList();

  /// `[[title]]` tıklaması -> hedef node (yoksa null).
  Node? resolveLink(String title) {
    final id = linkIndex.resolveTitle(title);
    return id == null ? null : nodeById(id);
  }

  // --- Görev mutasyonları (TaskRepository'ye köprü + bildirim) ---------------

  void addTask(Task task) {
    TaskRepository.add(task);
    _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());
    _telemetry.capture(
      Ev.taskCreated,
      props: {
        'routine': task.isRoutine,
        'repeat': task.repeat.type.name,
        'scheduled': task.scheduled,
        'duration_min': (task.durationHours * 60).round(),
        'has_note': task.note.isNotEmpty,
        'has_sketch': task.sketch != null,
        // Efor isteğe bağlı; kaç kişinin gerçekten işaretlediği ölçülmeden
        // filtrenin (Ö4b) kime hitap ettiği bilinemez.
        'energy': task.energy?.name ?? 'none',
      },
    );
    _touched();
  }

  void updateTask(Task task) {
    task.updatedAt = DateTime.now();
    TaskRepository.update(task);
    _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());
    _telemetry.capture(
      Ev.taskUpdated,
      props: {
        'routine': task.isRoutine,
        'scheduled': task.scheduled,
        'energy': task.energy?.name ?? 'none',
      },
    );
    _touched();
  }

  void removeTask(Task task) {
    TaskRepository.remove(task);
    _record(EntityKind.task, MutationOp.delete, task.id, const {});
    _telemetry.capture(Ev.taskDeleted, props: {'routine': task.isRoutine});
    _touched();
  }

  /// Geri alma: silinen bir görevi eski hâliyle geri koyar.
  ///
  /// [addTask] değil çünkü bu bir *oluşturma* değil. Aynı yolu kullansaydık
  /// her "geri al" bir `taskCreated` olayı üretir, oluşturma sayıları geri
  /// alınan silmelerle şişerdi. Senkron kaydı yine düşüyor — diğer cihaz
  /// görevin geri geldiğini görmeli.
  void restoreTask(Task task) {
    TaskRepository.add(task);
    _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());
    _touched();
  }

  void endRoutineBefore(Task task, DateTime day) {
    TaskRepository.endRoutineBefore(task, day);
    // Rutin ya kısaldı ya tamamen silindi; hangisi olduğunu repodan doğrula.
    final stillThere = taskById(task.id) != null;
    _record(
      EntityKind.task,
      stillThere ? MutationOp.upsert : MutationOp.delete,
      task.id,
      stillThere ? task.toJson() : const {},
    );
    _touched();
  }

  void setTaskDone(Task task, DateTime day, bool done) {
    task.setDone(day, done);
    task.updatedAt = DateTime.now();
    _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());
    _telemetry.capture(
      done ? Ev.taskCompleted : Ev.taskUncompleted,
      props: {
        'routine': task.isRoutine,
        // Zamanında mı, gecikmeli mi tamamlandı — erteleme analizinin girdisi.
        'days_late': Task.dayKey(
          DateTime.now(),
        ).difference(Task.dayKey(day)).inDays,
      },
    );
    _touched();
  }

  // --- Havuz ("Kenarda Bekleyenler") ----------------------------------------

  /// İşi havuza alır: takvimden çekilir ama **silinmez**.
  ///
  /// [Task.date] korunuyor — havuzdan çıkarken hangi günden geldiğini
  /// bilebilmek için. Saat de duruyor: geri koyarken kullanıcıya aynı saati
  /// önermek, onu sıfırdan seçtirmekten iyi.
  ///
  /// **Rutinler havuza girmez.** "Her gün tekrarlayan ama hiçbir gün görünmeyen
  /// iş" tanımsız bir şey; rutinde doğru eylem o günü atlamak. Kural asıl olarak
  /// arayüzde uygulanıyor (rutinde bu eylem hiç gösterilmiyor); buradaki
  /// denetim, bir çağrı yerinin unutulması hâlinde veriyi tutarsız bırakmamak
  /// için.
  void moveToPool(Task task) {
    assert(!task.isRoutine, 'Rutin havuza atılamaz (bkz. plan K2)');
    if (task.isRoutine || task.inPool) return;

    task.inPool = true;
    task.updatedAt = DateTime.now();
    TaskRepository.update(task);
    _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());
    _telemetry.capture(
      Ev.taskPooled,
      props: {
        'scheduled': task.scheduled,
        'energy': task.energy?.name ?? 'none',
      },
    );
    _touched();
  }

  /// İşi havuzdan çıkarıp takvime koyar.
  ///
  /// [toDay] verilmezse iş **eski gününe** döner: havuza atılırken korunan
  /// tarih tam bu an için saklanıyordu.
  void pullFromPool(Task task, {DateTime? toDay, double? startHour}) {
    if (!task.inPool) return;

    // Ölçüm için: havuza atıldığından beri geçen gün. Ayrı bir `pooledAt`
    // alanı yok — havuzdaki bir işe başka türlü dokunulmadığı sürece son
    // güncelleme zamanı bunun yeterince iyi bir yaklaşığı. `updatedAt`
    // aşağıda ezileceği için şimdi okunuyor.
    final waited = Task.dayKey(
      DateTime.now(),
    ).difference(Task.dayKey(task.updatedAt)).inDays;

    final target = Task.dayKey(toDay ?? task.date);
    task.inPool = false;
    task.date = target;
    if (startHour != null) {
      task.startHour = clampStartWithin(startHour, task.durationHours);
    }
    task.updatedAt = DateTime.now();
    TaskRepository.update(task);
    _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());
    _telemetry.capture(
      Ev.taskUnpooled,
      props: {
        'scheduled': task.scheduled,
        // Havuzda kaç gün beklediği: havuzun çöp kutusuna dönüp dönmediğini
        // söyleyen tek sayı.
        'days_waited': waited,
      },
    );
    _touched();
  }

  // --- Izgara etkileşimleri (sürükle-bırak) ---------------------------------

  /// Bir görevi ızgarada başka bir gün/saate taşır.
  ///
  /// Rutin semantiği — bilinçli tercih:
  ///   * **Saat** değişikliği rutinin tüm tekrarlarına uygulanır (kullanıcı
  ///     "sabah koşusunu 7'ye alayım" derken tek günü kastetmez).
  ///   * **Gün** değişikliği haftalık rutinde ilgili haftagününü değiştirir;
  ///     günlük/aylık rutinde gün taşıması yok sayılır (anlamsız olurdu).
  ///   * Tek günlük işte ikisi de doğrudan uygulanır.
  ///
  /// [newStartHour] 15 dakikalık ızgaraya oturtulmuş gelmelidir.
  void moveTask(
    Task task, {
    required DateTime toDay,
    required double newStartHour,
  }) {
    final fromDay = task.date;
    final start = clampStartWithin(newStartHour, task.durationHours);
    final targetDay = Task.dayKey(toDay);

    if (task.isRoutine) {
      if (task.repeat.type == RepeatType.weekly) {
        final oldWeekdays = task.repeat.weekdays.isEmpty
            ? {task.date.weekday}
            : task.repeat.weekdays;
        // Sürüklenen tekrar hangi haftagünündeyse onu hedefe taşı, diğerleri kalsın.
        final sourceWeekday = _weekdayBeingDragged(
          task,
          targetDay,
          oldWeekdays,
        );
        final next = {...oldWeekdays}
          ..remove(sourceWeekday)
          ..add(targetDay.weekday);
        task.repeat = task.repeat.copyWith(weekdays: next);
      }
    } else {
      task.date = targetDay;
    }

    task.startHour = start;
    task.updatedAt = DateTime.now();
    TaskRepository.update(task);
    _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());

    _telemetry.capture(
      Ev.taskMoved,
      props: {
        'routine': task.isRoutine,
        'day_delta': targetDay.difference(Task.dayKey(fromDay)).inDays,
        'hour': start.round(),
      },
    );
    _touched();
  }

  /// Haftalık rutinde sürüklenen tekrarın kaynak haftagünü. Hedef gün zaten
  /// kümede varsa (aynı güne bırakma) değişiklik gerekmez.
  int _weekdayBeingDragged(Task task, DateTime targetDay, Set<int> weekdays) {
    if (weekdays.contains(targetDay.weekday)) return targetDay.weekday;
    // Hedefe en yakın haftagünü taşınıyor kabul edilir.
    return weekdays.reduce((a, b) {
      final da = (a - targetDay.weekday).abs();
      final db = (b - targetDay.weekday).abs();
      return da <= db ? a : b;
    });
  }

  /// Blok kenarından çekerek süreyi değiştirir.
  void resizeTask(Task task, double newDurationHours) {
    final duration = newDurationHours.clamp(kMinDurationHours, 24.0);
    final start = task.startHour ?? 0.0;
    // Gün sonunu taşmasın: 23:00'te başlayan iş en fazla 1 saat olabilir.
    task.durationHours = duration.clamp(kMinDurationHours, 24.0 - start);
    task.updatedAt = DateTime.now();
    TaskRepository.update(task);
    _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());
    _telemetry.capture(
      Ev.taskResized,
      props: {'duration_min': (task.durationHours * 60).round()},
    );
    _touched();
  }

  // --- Not mutasyonları ------------------------------------------------------

  void addNote(Note note) {
    _notes.add(note);
    _record(EntityKind.note, MutationOp.upsert, note.id, note.toJson());
    _telemetry.capture(Ev.noteCreated);
    _touched();
  }

  void updateNote(Note note) {
    note.updatedAt = DateTime.now();
    final i = _notes.indexWhere((n) => n.id == note.id);
    i == -1 ? _notes.add(note) : _notes[i] = note;
    _record(EntityKind.note, MutationOp.upsert, note.id, note.toJson());
    _touched();
  }

  void removeNote(Note note) {
    _notes.removeWhere((n) => n.id == note.id);
    _record(EntityKind.note, MutationOp.delete, note.id, const {});
    _touched();
  }

  // --- Alışkanlık mutasyonları ----------------------------------------------

  void addHabit(Habit habit) {
    _habits.add(habit);
    _record(EntityKind.habit, MutationOp.upsert, habit.id, habit.toJson());
    _telemetry.capture(Ev.habitCreated, props: {'cadence': habit.cadence.name});
    _touched();
  }

  void removeHabit(Habit habit) {
    _habits.removeWhere((h) => h.id == habit.id);
    _record(EntityKind.habit, MutationOp.delete, habit.id, const {});
    _touched();
  }

  /// Alışkanlığı verilen günde işaretle/kaldır (ısı haritası hücresi tıklaması).
  ///
  /// [source] tikin nereden geldiğini ayırır: alışkanlık ekranından mı, ana
  /// ekrandaki günlük şeritten mi. Şeridin varlık sebebi tam olarak bu —
  /// ölçmeden bilinemez.
  void toggleHabit(Habit habit, DateTime day, {String source = 'habits'}) {
    habit.toggle(day);
    _record(EntityKind.habit, MutationOp.upsert, habit.id, habit.toJson());
    _telemetry.capture(
      Ev.habitToggled,
      props: {
        'done': habit.isDoneOn(day),
        'streak': habit.currentStreak,
        'source': source,
      },
    );
    _touched();
  }

  // --- Kategoriler -----------------------------------------------------------

  /// Kullanıcının eklediği özel kategori. Önceden yalnızca bellekteydi ve
  /// uygulama kapanınca kayboluyordu; artık anlık görüntüde taşınıyor.
  void addCategory(TaskCategory category) {
    if (AppData.categories.any((c) => c.name == category.name)) return;
    AppData.categories.add(category);
    _record(EntityKind.category, MutationOp.upsert, category.name, {
      'name': category.name,
      'colorHex': colorToHex(category.color),
    });
    _touched();
  }

  /// Dış dünyada (ör. eski ekranlarda TaskRepository doğrudan) bir değişiklik
  /// olduysa store'u tazelemek için çağrılır.
  void refresh() => _touched();

  void _touched() {
    _schedulePersist();
    notifyListeners();
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    super.dispose();
  }

  // --- Serileştirme ----------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'schemaVersion': AppConfig.kSchemaVersion,
    'savedAt': DateTime.now().toIso8601String(),
    'nodes': [
      for (final t in TaskRepository.all) t.toJson(),
      for (final n in _notes) n.toJson(),
    ],
    'habits': [for (final h in _habits) h.toJson()],
    'categories': [
      for (final c in AppData.categories)
        {'name': c.name, 'colorHex': colorToHex(c.color)},
    ],
  };

  void loadJson(Map<String, dynamic> j) {
    TaskRepository.all.clear();
    _notes.clear();
    _habits.clear();
    for (final raw in (j['nodes'] as List? ?? const [])) {
      final m = (raw as Map).cast<String, dynamic>();
      if (m['kind'] == 'note') {
        _notes.add(Note.fromJson(m));
      } else {
        TaskRepository.all.add(Task.fromJson(m));
      }
    }
    for (final raw in (j['habits'] as List? ?? const [])) {
      _habits.add(Habit.fromJson((raw as Map).cast<String, dynamic>()));
    }

    final categories = j['categories'] as List?;
    if (categories != null && categories.isNotEmpty) {
      AppData.categories = [
        for (final raw in categories)
          TaskCategory(
            ((raw as Map)['name'] as String?) ?? 'Diğer',
            colorFromHex(raw['colorHex'] as String?),
          ),
      ];
    }
    _touched();
  }
}

// --- Riverpod provider'ları --------------------------------------------------

/// Merkezi store. Ekranlar `ref.watch(appStoreProvider)` ile izler; her
/// `notifyListeners` bağımlı widget'ları yeniden çizer.
///
/// Telemetri buradan enjekte edilir: testlerde [telemetryProvider] override
/// edilmediği için store sessiz kalır.
final appStoreProvider = ChangeNotifierProvider<AppStore>(
  (ref) => AppStore(telemetry: ref.watch(telemetryProvider)),
);

/// Belirli bir günün görevleri (saat sırasına göre). Takvim/gün ekranları için.
final tasksForDateProvider = Provider.family<List<Task>, DateTime>((ref, day) {
  return ref.watch(appStoreProvider).tasksForDate(day);
});

/// Bir haftanın 7 günlük görev matrisi (haftalık ızgara).
final tasksForWeekProvider = Provider.family<List<List<Task>>, DateTime>((
  ref,
  monday,
) {
  return ref.watch(appStoreProvider).tasksForWeek(monday);
});

/// Havuzda bekleyen işler ("Kenarda Bekleyenler"), en eski önce.
///
/// Sıralama bilinçli: havuzun asıl riski çöp kutusuna dönmesi. En uzun
/// bekleyen üstte durursa unutulmuş iş göze çarpar; en yeni üstte olsaydı
/// eskiler listenin dibinde sessizce yaşlanırdı.
final poolProvider = Provider<List<Task>>((ref) {
  return ref.watch(appStoreProvider).tasks.where((t) => t.inPool).toList()
    ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
});

/// Rutin olmayan tek günlük işler (Yapılacaklar ekranı).
///
/// Havuzdakiler **burada kalır.** Havuz "takvimden çekildi" demek, "yok oldu"
/// değil; Yapılacaklar bir takvim görünümü değil, işlerin düz listesi. Havuza
/// atılan bir iş buradan da düşseydi, paneli açmayan biri onu hiçbir yerde
/// bulamazdı — kaybolan iş, kaybolan güven demek.
final todosProvider = Provider<List<Task>>((ref) {
  final list =
      ref.watch(appStoreProvider).tasks.where((t) => !t.isRoutine).toList()
        ..sort((a, b) {
          final byDate = a.date.compareTo(b.date);
          return byDate != 0 ? byDate : Task.compare(a, b);
        });
  return list;
});

/// Tekrar eden işler (Rutinler ekranı).
final routinesProvider = Provider<List<Task>>((ref) {
  return ref.watch(appStoreProvider).tasks.where((t) => t.isRoutine).toList()
    ..sort(Task.compare);
});

/// Bir node'a gelen bağlantılar (backlink paneli).
final backlinksProvider = Provider.family<List<Node>, String>((ref, id) {
  return ref.watch(appStoreProvider).backlinkNodes(id);
});

/// Tüm notlar (bilgi bankası listesi), güncelleme tarihine göre yeni → eski.
final notesProvider = Provider<List<Note>>((ref) {
  return ref.watch(appStoreProvider).notes.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
});

/// Tüm alışkanlıklar (Alışkanlıklar ekranı).
final habitsProvider = Provider<List<Habit>>((ref) {
  return ref.watch(appStoreProvider).habits;
});
