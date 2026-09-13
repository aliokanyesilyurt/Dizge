import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_config.dart';
import '../core/day_rescue.dart';
import '../core/group_context.dart';
import '../core/pool_labels.dart';
import '../core/telemetry.dart';
import '../core/time_grid.dart';
import '../models/agenda_page.dart';
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

  /// Ajanda yaprakları, gün anahtarına göre (A3).
  ///
  /// Liste değil harita: bir güne bir sayfa düşüyor ve erişim hep "bugünün
  /// sayfası" biçiminde oluyor. Listede tutmak her açılışta doğrusal arama
  /// demekti.
  final Map<String, AgendaPage> _agendaPages = {};

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

  /// Yeni kayıtların doğduğu bağlam (Y4c): grup bağlamındayken açılan hızlı
  /// ekleme, doğan işi o grubun kimliğiyle yazar.
  ///
  /// Damga tek bir yerde, `add*` metotlarında vuruluyor — çağrı yerlerinde
  /// değil. Altı ayrı ekran kendi damgasını vursaydı yedincisi unutulur ve o
  /// ekranda üretilen iş, grup bağlamında yazılıp kişiselde kaybolurdu.
  ///
  /// Alanı provider katmanı yazıyor ([appStoreProvider]); depo bağlamı
  /// **izlemiyor**, yalnız son değeri tutuyor.
  String? _activeGroupId;
  String? get activeGroupId => _activeGroupId;
  set activeGroupId(String? value) {
    if (_activeGroupId == value) return;
    _activeGroupId = value;
    notifyListeners();
  }
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

  /// Verilen günün ajanda yaprağı. Hiç yazılmamışsa **boş bir sayfa** döner,
  /// `null` değil: çağıran her yerde "sayfa var mı" diye sormak zorunda
  /// kalmasın; boş defter de bir defterdir.
  AgendaPage agendaPage(DateTime day) =>
      _agendaPages[AgendaPage.keyOf(day)] ?? AgendaPage(day: day);

  /// Yazılmış (boş olmayan) sayfaların gün anahtarları — sayfa gezinmesinde
  /// "hangi günlerde yazı var" işaretini koymak için.
  Iterable<String> get writtenAgendaDays =>
      _agendaPages.entries.where((e) => !e.value.isEmpty).map((e) => e.key);

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

  /// Verilen başlangıç tarihinden itibaren n günün görevleri. Mobil için 3 veya 1 günlük
  /// görünümü desteklemek üzere eklendi.
  List<List<Task>> tasksForDays(DateTime startDay, int numDays) {
    final start = Task.dayKey(startDay);
    return List.generate(
      numDays,
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
    task.groupId ??= activeGroupId == '*all*' ? null : activeGroupId;
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
        // Giriş hunisinin son adımı (T3c): kaydolan kişi gerçekten kullanmaya
        // başladı mı? Ayrı bir olay yerine burada bir özellik, çünkü soru
        // "kaç iş oluşturuldu"nun bir alt kümesi — huni bunu süzerek kurulur.
        'first': tasks.length == 1,
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

  /// Gün içinde tekrarlayan işin **tek bir tekrarını** işaretler (Z6).
  ///
  /// Ayrı bir kapı: [setTaskDone] günün tamamını yazıyor. Aynı kapıdan
  /// geçselerdi sabah dozunu işaretlemek akşamkini de bitmiş sayardı.
  /// Günün tamamlanmışlığını `Task.setSlotDone` kendisi hesaplıyor —
  /// hepsi bitmeden gün bitmiş olmuyor.
  void setTaskSlotDone(Task task, DateTime day, double hour, bool done) {
    task.setSlotDone(day, hour, done);
    task.updatedAt = DateTime.now();
    _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());
    _telemetry.capture(
      done ? Ev.taskCompleted : Ev.taskUncompleted,
      props: {'routine': task.isRoutine, 'slot': true},
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
      if (task.durationHours == 0) task.durationHours = 1.0;
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

  // --- "Günü kurtar" (Kaos düğmesi) -----------------------------------------

  /// Rutinin tek bir gününü atlar / atlamayı geri alır.
  ///
  /// Silmekten farkı: rutin yerinde kalır, yarın yine gelir. [Task.completedOn]
  /// hiç dokunulmaz — atlanan gün tamamlanmış sayılmaz.
  void skipRoutineOn(
    Task task,
    DateTime day,
    bool skipped, {
    String source = 'block',
  }) {
    if (task.isSkippedOn(day) == skipped) return;

    task.setSkipped(day, skipped);
    task.updatedAt = DateTime.now();
    TaskRepository.update(task);
    _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());
    if (source != 'rescue') {
      _telemetry.capture(
        Ev.routineSkipped,
        props: {'skipped': skipped, 'source': source},
      );
    }
    _touched();
  }

  // --- "Bugün iptal" (tek kapı) ---------------------------------------------

  /// İş o gün için iptal edilmiş mi?
  ///
  /// Rutinde "iptal" = o günü atlamak, tek günlük işte = havuza almak. Çağıran
  /// tarafın hangisi olduğunu bilmesi gerekmiyor; menüde tek satır görünsün
  /// diye ayrım burada kalıyor (plan K3).
  bool isCancelledOn(Task task, DateTime day) =>
      task.isRoutine ? task.isSkippedOn(day) : task.inPool;

  /// İşi o gün için iptal eder ve **bildirimde yazılacak cümleyi** döner.
  ///
  /// Cümleyi burası üretiyor çünkü mekanizmayı yalnız burası biliyor: ekran
  /// "iptal ettim" der, ne olduğunu ("kenara alındı" / "bugünlük atlandı")
  /// buradan öğrenir. Mekanizma gizlenmiyor, yalnızca *seçtirilmiyor*.
  String cancelOn(Task task, DateTime day, {String source = 'block'}) {
    if (task.isRoutine) {
      skipRoutineOn(task, day, true, source: source);
      return 'Bugünlük atlandı';
    }
    moveToPool(task);
    return kMovedToPool;
  }

  /// İptali geri alır: atlanan rutin geri gelir, havuzdaki iş [day] gününe
  /// döner.
  void undoCancelOn(Task task, DateTime day, {String source = 'block'}) {
    if (task.isRoutine) {
      skipRoutineOn(task, day, false, source: source);
    } else {
      pullFromPool(task, toDay: day);
    }
  }

  /// Planı uygular: tek günlük işler havuza, rutinler o günün atlananlarına.
  ///
  /// Tek bir bildirim atıyor (`_touched` sonda): sekiz işi tek tek bildirmek
  /// haftalık ızgarayı sekiz kez yeniden kurardı. Telemetri de tek olay —
  /// ölçülmek istenen "kaç iş süpürüldü", "kaç kez `moveToPool` çağrıldı"
  /// değil.
  void applyDayRescue(DayRescuePlan plan) {
    if (plan.isEmpty) return;

    for (final task in plan.toPool) {
      task.inPool = true;
      task.updatedAt = DateTime.now();
      TaskRepository.update(task);
      _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());
    }
    for (final task in plan.toSkip) {
      task.setSkipped(plan.day, true);
      task.updatedAt = DateTime.now();
      TaskRepository.update(task);
      _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());
    }

    _telemetry.capture(
      Ev.dayRescued,
      props: {
        'pooled': plan.toPool.length,
        'skipped': plan.toSkip.length,
        'total': plan.total,
      },
    );
    _touched();
  }

  /// Kurtarmayı geri alır: havuza gidenler eski günlerine döner (saatleri
  /// zaten hiç değişmedi), atlanan rutinlerin atlaması silinir.
  void undoDayRescue(DayRescuePlan plan) {
    for (final task in plan.toPool) {
      task.inPool = false;
      task.updatedAt = DateTime.now();
      TaskRepository.update(task);
      _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());
    }
    for (final task in plan.toSkip) {
      task.setSkipped(plan.day, false);
      task.updatedAt = DateTime.now();
      TaskRepository.update(task);
      _record(EntityKind.task, MutationOp.upsert, task.id, task.toJson());
    }

    _telemetry.capture(Ev.dayRescueUndone, props: {'total': plan.total});
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
    note.groupId ??= activeGroupId == '*all*' ? null : activeGroupId;
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

  // --- Ajanda sayfası mutasyonları ------------------------------------------

  /// Bir günün yaprağını yazar.
  ///
  /// `_record` **çağrılmıyor** ve bu bilinçli: ajanda sayfalarının senkronu
  /// plan §9'da kapsam dışı. Mutasyon kuyruğuna girselerdi sunucuda karşılığı
  /// olmayan bir varlık için kuyruk şişer, senkron motoru da her denemede
  /// bilinmeyen bir tür görürdü.
  ///
  /// Boş sayfa **silinir**, boş kayıt olarak tutulmaz: dokunulup vazgeçilmiş
  /// her gün için anlık görüntüde bir satır bırakmanın kimseye faydası yok.
  void saveAgendaPage(AgendaPage page) {
    if (page.isEmpty) {
      _agendaPages.remove(page.key);
    } else {
      _agendaPages[page.key] = page;
    }
    _touched();
  }

  // --- Alışkanlık mutasyonları ----------------------------------------------

  void addHabit(Habit habit) {
    habit.groupId ??= activeGroupId == '*all*' ? null : activeGroupId;
    _habits.add(habit);
    _record(EntityKind.habit, MutationOp.upsert, habit.id, habit.toJson());
    _telemetry.capture(
      Ev.habitCreated,
      props: {'target_per_week': habit.targetPerWeek},
    );
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
    // Damga mutasyondan **önce** tazelenmeli: `toJson` onu da taşıyor ve
    // sunucudaki LWW karşılaştırması bu değere bakıyor. Sonra tazelesek
    // kuyruğa eski damgalı bir kayıt girerdi.
    habit.touch();
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
      if (category.customLabel != null) 'label': category.customLabel,
    });
    _touched();
  }

  void updateCategory(TaskCategory category) {
    final i = AppData.categories.indexWhere((c) => c.name == category.name);
    if (i != -1) {
      AppData.categories[i] = category;
      _record(EntityKind.category, MutationOp.upsert, category.name, {
        'name': category.name,
        'colorHex': colorToHex(category.color),
        if (category.customLabel != null) 'label': category.customLabel,
      });
      _touched();
    }
  }

  /// Dış dünyada (ör. eski ekranlarda TaskRepository doğrudan) bir değişiklik
  /// olduysa store'u tazelemek için çağrılır.
  /// Bir grubun yerel kopyalarını siler — **outbox'a hiçbir şey yazmadan**
  /// (Y4d).
  ///
  /// Gruptan çıkan kullanıcının cihazında o grubun işleri yoksa kalırdı:
  /// artımlı çekim yalnız ekler ve sunucu, ayrılan üyeye o satırları artık
  /// göndermiyor ama mezar taşı da yollamıyor — satır silinmedi, görünmez
  /// oldu.
  ///
  /// Silmenin mutasyon üretmemesi bu işin **can alıcı** yeri. Üretseydi
  /// hikâye şu olurdu: "gruptan çıktım, kendi kopyamı sildim, karşı tarafta da
  /// silindi." Sunucudaki satır grubun ve orada kalmalı; burada olan bir
  /// senkron değil, görüş alanının daralması.
  void purgeGroup(String groupId) {
    final before = TaskRepository.all.length + _notes.length + _habits.length;
    TaskRepository.all.removeWhere((t) => t.groupId == groupId);
    _notes.removeWhere((n) => n.groupId == groupId);
    _habits.removeWhere((h) => h.groupId == groupId);
    final after = TaskRepository.all.length + _notes.length + _habits.length;
    if (after != before) _touched();
  }

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
    'agendaPages': [for (final p in _agendaPages.values) p.toJson()],
    'categories': [
      for (final c in AppData.categories)
        {
          'name': c.name,
          'colorHex': colorToHex(c.color),
          if (c.customLabel != null) 'label': c.customLabel,
        },
    ],
  };

  /// Sunucudan gelen **artımlı** görüntüyü yerel duruma birleştirir (Y1).
  ///
  /// [loadJson]'dan farkı yıkmaması: burada gelen her kayıt için ayrı bir karar
  /// veriliyor. Hakem yine **son yazan kazanır** ve ölçü yine `updatedAt` —
  /// sunucudaki `apply_mutations`'ın kullandığının **birebir aynısı**. Aynı
  /// kuralı iki yerde yazmak tekrar değil zorunluluk: sunucu yazarken, istemci
  /// okurken karar veriyor. Farklı kurallar kullansalardı iki cihaz farklı
  /// sonuca varırdı.
  ///
  /// `deletedIds` mezar taşlarını taşır. Onlar olmadan silme aktarılamaz:
  /// artımlı çekimde "gelmedi" ile "silindi" ayırt edilemez (B3).
  ///
  /// Bu metot **mutasyon üretmez**. Ürettiği anda sunucudan gelen her kayıt
  /// kuyruğa girip geri gönderilirdi — sonsuz bir eko.
  void mergeJson(Map<String, dynamic> j) {
    var changed = false;

    for (final raw in (j['nodes'] as List? ?? const [])) {
      final m = (raw as Map).cast<String, dynamic>();
      if (m['kind'] == 'note') {
        final incoming = Note.fromJson(m);
        final i = _notes.indexWhere((n) => n.id == incoming.id);
        if (i == -1) {
          _notes.add(incoming);
          changed = true;
        } else if (incoming.updatedAt.isAfter(_notes[i].updatedAt)) {
          _notes[i] = incoming;
          changed = true;
        }
      } else {
        final incoming = Task.fromJson(m);
        final i = TaskRepository.all.indexWhere((t) => t.id == incoming.id);
        if (i == -1) {
          TaskRepository.all.add(incoming);
          changed = true;
        } else if (incoming.updatedAt.isAfter(
          TaskRepository.all[i].updatedAt,
        )) {
          TaskRepository.all[i] = incoming;
          changed = true;
        }
      }
    }

    for (final raw in (j['habits'] as List? ?? const [])) {
      final incoming = Habit.fromJson((raw as Map).cast<String, dynamic>());
      final i = _habits.indexWhere((h) => h.id == incoming.id);
      if (i == -1) {
        _habits.add(incoming);
        changed = true;
      } else if (incoming.updatedAt.isAfter(_habits[i].updatedAt)) {
        _habits[i] = incoming;
        changed = true;
      }
    }

    for (final raw in (j['deletedIds'] as List? ?? const [])) {
      final id = raw as String;
      final before = TaskRepository.all.length + _notes.length + _habits.length;
      TaskRepository.all.removeWhere((t) => t.id == id);
      _notes.removeWhere((n) => n.id == id);
      _habits.removeWhere((h) => h.id == id);
      if (TaskRepository.all.length + _notes.length + _habits.length !=
          before) {
        changed = true;
      }
    }

    // Kategoriler bütün olarak geliyor (Y1d) — kimlikleri adları olduğu için
    // tek tek birleştirilemez.
    final categories = j['categories'] as List?;
    if (categories != null && categories.isNotEmpty) {
      AppData.categories = [
        for (final raw in categories)
          TaskCategory(
            ((raw as Map)['name'] as String?) ?? 'Diğer',
            colorFromHex(raw['colorHex'] as String?),
            customLabel: raw['label'] as String?,
          ),
      ];
      changed = true;
    }

    // Hiçbir şey değişmediyse ekranı yeniden çizmenin ve diske yazmanın anlamı
    // yok: artımlı çekim sık koşuyor ve turların çoğu boş dönüyor.
    if (changed) _touched();
  }

  void loadJson(Map<String, dynamic> j) {
    TaskRepository.all.clear();
    _notes.clear();
    _habits.clear();
    _agendaPages.clear();
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
    // Eski anlık görüntülerde bu alan hiç yok; `?? const []` onları da
    // okunabilir kılıyor — ajanda öncesi bir kayıt açıldığında sayfalar
    // boş başlar, uygulama patlamaz.
    for (final raw in (j['agendaPages'] as List? ?? const [])) {
      final page = AgendaPage.fromJson((raw as Map).cast<String, dynamic>());
      _agendaPages[page.key] = page;
    }

    final categories = j['categories'] as List?;
    if (categories != null && categories.isNotEmpty) {
      AppData.categories = [
        for (final raw in categories)
          TaskCategory(
            ((raw as Map)['name'] as String?) ?? 'Diğer',
            colorFromHex(raw['colorHex'] as String?),
            customLabel: raw['label'] as String?,
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
final appStoreProvider = ChangeNotifierProvider<AppStore>((ref) {
  final store = AppStore(telemetry: ref.watch(telemetryProvider));
  // `listen`, `watch` değil: bağlam değişince deponun kendisi yeniden
  // kurulsaydı bellekteki bütün takvim gider ve diskten yeniden hidrasyon
  // gerekirdi. Değişen şey yalnız yeni kayıtların varsayılan bağlamı.
  ref.listen<String?>(
    activeGroupIdProvider,
    (_, next) => store.activeGroupId = next,
    fireImmediately: true,
  );
  return store;
});

/// Bağlam süzgeci (Y4b).
///
/// Kişisel bağlamda `groupId == null` olanlar, grup bağlamında yalnız o
/// grubunkiler. Süzgeç burada, provider katmanında duruyor: widget'ların
/// içinde olsaydı her ekran kendi kuralını yazar ve biri unutulduğunda o ekran
/// sessizce başka bir bağlamın işlerini gösterirdi.
List<T> _inContext<T>(
  List<T> items,
  String? activeGroupId,
  String? Function(T) groupOf,
) {
  if (activeGroupId == '*all*') return items;
  return [
    for (final item in items)
      if (groupOf(item) == activeGroupId) item,
  ];
}

/// Belirli bir günün görevleri (saat sırasına göre). Takvim/gün ekranları için.
final tasksForDateProvider = Provider.family<List<Task>, DateTime>((ref, day) {
  return _inContext(
    ref.watch(appStoreProvider).tasksForDate(day),
    ref.watch(activeGroupIdProvider),
    (t) => t.groupId,
  );
});

/// Bir haftanın 7 günlük görev matrisi (haftalık ızgara).
final tasksForWeekProvider = Provider.family<List<List<Task>>, DateTime>((
  ref,
  monday,
) {
  final active = ref.watch(activeGroupIdProvider);
  return [
    for (final day in ref.watch(appStoreProvider).tasksForWeek(monday))
      _inContext(day, active, (t) => t.groupId),
  ];
});

/// Havuzda bekleyen işler ("Kenarda Bekleyenler"), en eski önce.
///
/// Sıralama bilinçli: havuzun asıl riski çöp kutusuna dönmesi. En uzun
/// bekleyen üstte durursa unutulmuş iş göze çarpar; en yeni üstte olsaydı
/// eskiler listenin dibinde sessizce yaşlanırdı.
final poolProvider = Provider<List<Task>>((ref) {
  final active = ref.watch(activeGroupIdProvider);
  return ref
      .watch(appStoreProvider)
      .tasks
      .where((t) => t.inPool && (active == '*all*' || t.groupId == active))
      .toList()
    ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
});

/// Rutin olmayan tek günlük işler (Yapılacaklar ekranı).
///
/// Havuzdakiler **burada kalır.** Havuz "takvimden çekildi" demek, "yok oldu"
/// değil; Yapılacaklar bir takvim görünümü değil, işlerin düz listesi. Havuza
/// atılan bir iş buradan da düşseydi, paneli açmayan biri onu hiçbir yerde
/// bulamazdı — kaybolan iş, kaybolan güven demek.
final todosProvider = Provider<List<Task>>((ref) {
  final active = ref.watch(activeGroupIdProvider);
  final list =
      ref
          .watch(appStoreProvider)
          .tasks
          .where((t) => !t.isRoutine && (active == '*all*' || t.groupId == active))
          .toList()
        ..sort((a, b) {
          final byDate = a.date.compareTo(b.date);
          return byDate != 0 ? byDate : Task.compare(a, b);
        });
  return list;
});

/// Tekrar eden işler (Rutinler ekranı).
final routinesProvider = Provider<List<Task>>((ref) {
  final active = ref.watch(activeGroupIdProvider);
  return ref
      .watch(appStoreProvider)
      .tasks
      .where((t) => t.isRoutine && (active == '*all*' || t.groupId == active))
      .toList()
    ..sort(Task.compare);
});

/// Bir günün ajanda yaprağı (A3).
///
/// Yazılmamış gün için boş sayfa döner; ekran "sayfa var mı" diye sormaz.
/// Grup bağlamına göre süzülmüyor — ajanda şimdilik kişisel (plan §9).
final agendaPageProvider = Provider.family<AgendaPage, DateTime>((ref, day) {
  return ref.watch(appStoreProvider).agendaPage(day);
});

/// Bir node'a gelen bağlantılar (backlink paneli).
final backlinksProvider = Provider.family<List<Node>, String>((ref, id) {
  return ref.watch(appStoreProvider).backlinkNodes(id);
});

/// Tüm notlar (bilgi bankası listesi), güncelleme tarihine göre yeni → eski.
final notesProvider = Provider<List<Note>>((ref) {
  return _inContext(
    ref.watch(appStoreProvider).notes.toList(),
    ref.watch(activeGroupIdProvider),
    (n) => n.groupId,
  )..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
});

/// Tüm alışkanlıklar (Alışkanlıklar ekranı).
final habitsProvider = Provider<List<Habit>>((ref) {
  return _inContext(
    ref.watch(appStoreProvider).habits,
    ref.watch(activeGroupIdProvider),
    (h) => h.groupId,
  );
});
