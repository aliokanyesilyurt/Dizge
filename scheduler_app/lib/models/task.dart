import 'package:flutter/material.dart';
import 'node.dart';

/// Elle çizilmiş açıklama (kalem/parmak ile). Strokes, [size] uzayında saklanır.
class Sketch {
  final List<List<Offset>> strokes;
  final Size size;
  final Color color;
  const Sketch(this.strokes, this.size, this.color);

  bool get isEmpty => strokes.every((s) => s.isEmpty);

  Map<String, dynamic> toJson() => {
        'strokes': strokes
            .map((s) => s.map((o) => [o.dx, o.dy]).toList())
            .toList(),
        'w': size.width,
        'h': size.height,
        'color': colorToHex(color),
      };

  factory Sketch.fromJson(Map<String, dynamic> j) => Sketch(
        (j['strokes'] as List)
            .map((s) => (s as List).map((p) {
                  // Nokta [x, y] çifti olarak saklanır; dinamik indeksleme
                  // yerine önce listeye daraltıp okuyoruz.
                  final xy = (p as List).cast<num>();
                  return Offset(xy[0].toDouble(), xy[1].toDouble());
                }).toList())
            .toList(),
        Size((j['w'] as num).toDouble(), (j['h'] as num).toDouble()),
        colorFromHex(j['color'] as String?),
      );
}

/// Görevin Kanban/pano durumu (TickTick tarzı). Rutinlerde günlük tamamlanma
/// hâlâ [Task.completedOn] üzerinden yürür; bu alan tek seferlik işlerin pano
/// sütununu belirler.
enum TaskStatus { todo, doing, done }

/// Bir işin ne sıklıkla tekrarlandığı.
enum RepeatType {
  once, // tek günlük iş
  daily, // her gün
  weekly, // haftanın seçili günleri
  monthly, // her ayın aynı günü
}

/// Tekrar kuralı. [once] dışındakiler "rutin" sayılır.
class Repeat {
  final RepeatType type;

  /// weekly için: 1 = Pazartesi ... 7 = Pazar.
  final Set<int> weekdays;

  /// Rutinin biteceği gün (dahil). null => süresiz.
  final DateTime? until;

  const Repeat.once()
      : type = RepeatType.once,
        weekdays = const {},
        until = null;

  const Repeat(this.type, {this.weekdays = const {}, this.until});

  bool get isRoutine => type != RepeatType.once;

  Repeat copyWith({RepeatType? type, Set<int>? weekdays, DateTime? until, bool clearUntil = false}) =>
      Repeat(
        type ?? this.type,
        weekdays: weekdays ?? this.weekdays,
        until: clearUntil ? null : (until ?? this.until),
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'weekdays': (weekdays.toList()..sort()),
        'until': until == null ? null : dateToKey(until!),
      };

  factory Repeat.fromJson(Map<String, dynamic> j) {
    final type = RepeatType.values.firstWhere(
      (t) => t.name == j['type'],
      orElse: () => RepeatType.once,
    );
    return Repeat(
      type,
      weekdays: (j['weekdays'] as List?)
              ?.map((e) => (e as num).toInt())
              .toSet() ??
          const {},
      until: dateFromKeyOrNull(j['until'] as String?),
    );
  }

  static const List<String> weekdayShort = [
    'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'
  ];

  /// "Her gün", "Sal, Per", "Her ayın 12'si" gibi okunur özet.
  String describe(DateTime anchor) {
    switch (type) {
      case RepeatType.once:
        return 'Tek günlük';
      case RepeatType.daily:
        return 'Her gün';
      case RepeatType.weekly:
        if (weekdays.isEmpty) return 'Haftalık';
        if (weekdays.length == 7) return 'Her gün';
        final sorted = weekdays.toList()..sort();
        return sorted.map((d) => weekdayShort[d - 1]).join(', ');
      case RepeatType.monthly:
        return 'Her ayın ${anchor.day}\'i';
    }
  }
}

class Task implements Node {
  @override
  final String id;
  @override
  String title;
  String note; // açıklama (yazılı) — [Node.body] olarak da erişilir
  String place; // yer (isteğe bağlı)
  Sketch? sketch; // açıklama (elle çizilmiş), isteğe bağlı
  double? startHour; // 0.0 - 24.0, null => saatsiz
  double durationHours; // süre (saat cinsinden)
  Color color;
  String categoryName;
  Repeat repeat;

  // --- İlişkisel / meta veri (mimari kararlar) ---
  @override
  final Set<String> tags; // TickTick etiketleri (# olmadan); analitik + filtre
  TaskStatus status; // Kanban sütunu
  int priority; // 0 = yok ... 3 = en yüksek
  int timeSpentMinutes; // Pomodoro'nun yazdığı harcanan süre
  @override
  final DateTime createdAt;
  @override
  DateTime updatedAt;

  /// Tek günlük işte işin günü; rutinde rutinin başladığı gün.
  DateTime date;

  /// Rutinlerde hangi günlerde tamamlandığı; tek günlük işte 0 veya 1 eleman.
  final Set<DateTime> completedOn;

  Task({
    String? id,
    required this.title,
    this.note = '',
    this.place = '',
    this.sketch,
    this.startHour,
    this.durationHours = 1.0,
    required this.color,
    this.categoryName = '',
    this.repeat = const Repeat.once(),
    required DateTime date,
    Set<DateTime>? completedOn,
    Set<String>? tags,
    this.status = TaskStatus.todo,
    this.priority = 0,
    this.timeSpentMinutes = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? newNodeId(),
        date = dayKey(date),
        completedOn = completedOn ?? <DateTime>{},
        tags = tags ?? <String>{},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  @override
  NodeKind get kind => NodeKind.task;

  /// [Node.body] — görevin yazılı açıklaması Markdown gövde olarak kullanılır;
  /// [[bağlantı]] ve etiketler buradan çözümlenir.
  @override
  String get body => note;

  static DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get isRoutine => repeat.isRoutine;

  /// Saati belirlenmiş mi (saat dilimi olarak çizilebilir mi)?
  bool get scheduled => startHour != null;

  double? get endHour =>
      startHour == null ? null : (startHour! + durationHours).clamp(0.0, 24.0);

  bool isDoneOn(DateTime day) => completedOn.contains(dayKey(day));

  void setDone(DateTime day, bool done) {
    final k = dayKey(day);
    done ? completedOn.add(k) : completedOn.remove(k);
  }

  /// Bu iş verilen günde görünür mü?
  bool occursOn(DateTime day) {
    final d = dayKey(day);
    if (repeat.type == RepeatType.once) return d == date;
    if (d.isBefore(date)) return false;
    final until = repeat.until;
    if (until != null && d.isAfter(dayKey(until))) return false;
    switch (repeat.type) {
      case RepeatType.once:
        return false;
      case RepeatType.daily:
        return true;
      case RepeatType.weekly:
        if (repeat.weekdays.isEmpty) return d.weekday == date.weekday;
        return repeat.weekdays.contains(d.weekday);
      case RepeatType.monthly:
        // Ayın son gününü aşan tekrarlar (ör. 31) o ayın son gününe düşer.
        final lastDay = DateUtils.getDaysInMonth(d.year, d.month);
        return d.day == (date.day > lastDay ? lastDay : date.day);
    }
  }

  static String formatTime(double time) {
    int hour = time.floor();
    int minute = ((time - hour) * 60).round();
    if (minute == 60) {
      hour += 1;
      minute = 0;
    }
    return '${(hour % 24).toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// "1 sa 30 dk" gibi süre metni.
  static String formatDuration(double hours) {
    final total = (hours * 60).round();
    final h = total ~/ 60;
    final m = total % 60;
    if (h == 0) return '$m dk';
    if (m == 0) return '$h sa';
    return '$h sa $m dk';
  }

  String get startString => startHour == null ? '' : formatTime(startHour!);
  String get endString => endHour == null ? '' : formatTime(endHour!);
  String get durationString => formatDuration(durationHours);
  String get timeString => scheduled ? '$startString – $endString' : 'Saatsiz';

  /// Sıralama anahtarı: saatliler önce (başlangıca göre), saatsizler sonda.
  static int compare(Task a, Task b) {
    if (a.scheduled && b.scheduled) return a.startHour!.compareTo(b.startHour!);
    if (a.scheduled) return -1;
    if (b.scheduled) return 1;
    return a.title.compareTo(b.title);
  }

  Task copy() => Task(
        id: id,
        title: title,
        note: note,
        place: place,
        sketch: sketch,
        startHour: startHour,
        durationHours: durationHours,
        color: color,
        categoryName: categoryName,
        repeat: repeat,
        date: date,
        completedOn: {...completedOn},
        tags: {...tags},
        status: status,
        priority: priority,
        timeSpentMinutes: timeSpentMinutes,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Kullanıcının "Kopyala" dediğinde ürettiği yeni iş.
  ///
  /// [copy]'den farkı bilinçli: yeni bir kimlik alır (aksi hâlde iki blok aynı
  /// görevi gösterirdi) ve tamamlanma geçmişini devralmaz — kopya henüz
  /// yapılmadı, kaynağın geçmişi ona ait değil.
  Task duplicateTo(DateTime day) => Task(
        title: title,
        note: note,
        place: place,
        sketch: sketch,
        startHour: startHour,
        durationHours: durationHours,
        color: color,
        categoryName: categoryName,
        repeat: repeat,
        date: day,
        tags: {...tags},
        status: status,
        priority: priority,
      );

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'task',
        'id': id,
        'title': title,
        'body': note, // Markdown açıklama
        'place': place,
        'sketch': sketch?.toJson(),
        'startHour': startHour,
        'durationHours': durationHours,
        'colorHex': colorToHex(color),
        'categoryName': categoryName,
        'repeat': repeat.toJson(),
        'date': dateToKey(date),
        'completedOn': completedOn.map(dateToKey).toList(),
        'tags': tags.toList(),
        'status': status.name,
        'priority': priority,
        'timeSpentMinutes': timeSpentMinutes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String?,
        title: (j['title'] as String?) ?? '',
        // Geriye dönük: eski kayıtlarda 'note', yenilerde 'body'.
        note: (j['body'] ?? j['note'] ?? '') as String,
        place: (j['place'] as String?) ?? '',
        sketch: j['sketch'] == null
            ? null
            : Sketch.fromJson((j['sketch'] as Map).cast<String, dynamic>()),
        startHour: (j['startHour'] as num?)?.toDouble(),
        durationHours: (j['durationHours'] as num?)?.toDouble() ?? 1.0,
        color: colorFromHex(j['colorHex'] as String?),
        categoryName: (j['categoryName'] as String?) ?? '',
        repeat: j['repeat'] == null
            ? const Repeat.once()
            : Repeat.fromJson((j['repeat'] as Map).cast<String, dynamic>()),
        date: dateFromKeyOrNull(j['date'] as String?) ?? DateTime.now(),
        completedOn: (j['completedOn'] as List?)
                ?.map((e) => dateFromKeyOrNull(e as String?))
                .whereType<DateTime>()
                .map(Task.dayKey)
                .toSet() ??
            <DateTime>{},
        tags: readTags(j['tags']),
        status: TaskStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => TaskStatus.todo,
        ),
        priority: (j['priority'] as num?)?.toInt() ?? 0,
        timeSpentMinutes: (j['timeSpentMinutes'] as num?)?.toInt() ?? 0,
        createdAt: readDate(j['createdAt']),
        updatedAt: readDate(j['updatedAt']),
      );
}

/// Görev eklerken/düzenlerken seçilebilecek renk paleti.
const List<Color> kTaskColors = [
  Color(0xFFFF6090), // pembe
  Color(0xFF4FC3F7), // mavi
  Color(0xFF81C784), // yeşil
  Color(0xFFFFB74D), // turuncu
  Color(0xFFBA68C8), // mor
  Color(0xFF4DD0E1), // turkuaz
  Color(0xFFFFF176), // sarı
  Color(0xFFE57373), // kırmızı
];

/// Bir iş kategorisi: ad + renk. Hazır olanlar + kullanıcının eklediği özel olanlar.
class TaskCategory {
  final String name;
  final Color color;
  const TaskCategory(this.name, this.color);
}

/// Uygulama genel ayarları + kategori listesi (sadece bellekte tutulur).
class AppData {
  /// Hazır + özel kategoriler. Renk = işin TÜRÜ/anlamı.
  static List<TaskCategory> categories = [
    const TaskCategory('Kalıcı iş', Color(0xFFE57373)),
    const TaskCategory('Günlük rutin', Color(0xFF4FC3F7)),
    const TaskCategory('Haftalık / ara sıra', Color(0xFFFF6090)),
    const TaskCategory('Önemli / acil', Color(0xFFFFB74D)),
    const TaskCategory('Hobi / keyfi', Color(0xFF81C784)),
    const TaskCategory('Sosyal', Color(0xFFBA68C8)),
    const TaskCategory('Diğer', Color(0xFFFFF176)),
  ];
}

class TaskRepository {
  /// Tüm işler (tek günlük + rutin). Sadece bellekte tutulur.
  static final List<Task> all = [];

  /// Verilen günde görünen işler, saate göre sıralı.
  static List<Task> forDate(DateTime date) {
    final list = all.where((t) => t.occursOn(date)).toList();
    list.sort(Task.compare);
    return list;
  }

  static bool hasTasksOn(DateTime date) => all.any((t) => t.occursOn(date));

  static void add(Task task) => all.add(task);

  /// Aynı id'li işi yenisiyle değiştirir; yoksa ekler.
  static void update(Task task) {
    final i = all.indexWhere((t) => t.id == task.id);
    i == -1 ? all.add(task) : all[i] = task;
  }

  static void remove(Task task) => all.removeWhere((t) => t.id == task.id);

  /// Rutinin sadece [day] günündeki tekrarını kaldırır: rutini o günden
  /// önce bitirir. (Tek günlük işte işin kendisini siler.)
  static void endRoutineBefore(Task task, DateTime day) {
    final d = Task.dayKey(day);
    if (!task.isRoutine || !d.isAfter(task.date)) {
      remove(task);
      return;
    }
    task.repeat = task.repeat.copyWith(
      until: d.subtract(const Duration(days: 1)),
    );
  }
}
