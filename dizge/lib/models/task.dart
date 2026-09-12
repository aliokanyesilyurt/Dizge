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
    'strokes': strokes.map((s) => s.map((o) => [o.dx, o.dy]).toList()).toList(),
    'w': size.width,
    'h': size.height,
    'color': colorToHex(color),
  };

  factory Sketch.fromJson(Map<String, dynamic> j) => Sketch(
    (j['strokes'] as List)
        .map(
          (s) => (s as List).map((p) {
            // Nokta [x, y] çifti olarak saklanır; dinamik indeksleme
            // yerine önce listeye daraltıp okuyoruz.
            final xy = (p as List).cast<num>();
            return Offset(xy[0].toDouble(), xy[1].toDouble());
          }).toList(),
        )
        .toList(),
    Size((j['w'] as num).toDouble(), (j['h'] as num).toDouble()),
    colorFromHex(j['color'] as String?),
  );
}

/// Görevin Kanban/pano durumu (TickTick tarzı). Rutinlerde günlük tamamlanma
/// hâlâ [Task.completedOn] üzerinden yürür; bu alan tek seferlik işlerin pano
/// sütununu belirler.
enum TaskStatus { todo, doing, done }

/// İşin istediği zihinsel efor.
///
/// Neden `tags` değil: etiketler serbest metin (`Set<String>`); "Yüksek Efor",
/// "yüksek efor" ve "YuksekEfor" üç ayrı etiket olurdu. Filtre ve renk kapalı
/// bir küme ister.
///
/// Neden `priority` değil: aciliyet ile efor aynı şey değil. Doktor randevusu
/// düşük öncelikli ama yorucu olabilir; iki eksen birbirine karışırsa ikisi de
/// anlamını yitirir.
///
/// Dört kademe, üç değil: asıl kullanım senaryosu — akşam yorgun dönüp
/// "beynimi yakmadan ne yapabilirim" diye bakmak — tam olarak [low] ile
/// [medium] arasından seçmek. Ayrımı silmek özelliğin sebebini silerdi.
///
/// **Sıra anlamlı:** baştan sona azalan efor. [Task.exceedsEnergy] karşılaştırmayı
/// `index` üzerinden yapıyor; araya yeni bir kademe eklenecekse doğru yere
/// eklenmeli. Bir test bu sırayı bekçiliyor.
enum Energy {
  high('Yüksek efor'),
  medium('Orta efor'),
  low('Düşük efor'),
  discharge('Deşarj');

  const Energy(this.label);

  /// Kullanıcıya görünen ad.
  final String label;

  /// Kayıttan okunan ad; tanınmayan ya da eksik değer "belirtilmemiş" demek.
  ///
  /// İleri uyum: bu sürümün tanımadığı bir kademe (başka bir cihazda eklenmiş
  /// olabilir) veriyi düşürmez, yalnız sessizce boş görünür.
  static Energy? byName(String? name) {
    for (final e in Energy.values) {
      if (e.name == name) return e;
    }
    return null;
  }
}

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

  Repeat copyWith({
    RepeatType? type,
    Set<int>? weekdays,
    DateTime? until,
    bool clearUntil = false,
  }) => Repeat(
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
      weekdays:
          (j['weekdays'] as List?)?.map((e) => (e as num).toInt()).toSet() ??
          const {},
      until: dateFromKeyOrNull(j['until'] as String?),
    );
  }

  static const List<String> weekdayShort = [
    'Pzt',
    'Sal',
    'Çar',
    'Per',
    'Cum',
    'Cmt',
    'Paz',
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

  /// İşin içinde kalması istenen saat aralığı; null => pencere yok.
  ///
  /// Pencere bir **kısıt**, bir süre değil: "09:00–12:00 arasında" demek "üç
  /// saat sürecek" demek değildir — ne kadar süreceğini [durationHours]
  /// söyler. İkisi tek alana yüklenseydi kullanıcı hangisini kastettiğini
  /// söyleyemezdi (bkz. plan §Za).
  ///
  /// Pencere yeni bir eksen açmıyor, [isFixed]'i **nicelendiriyor**:
  /// kımıldatılamaz işin zaten çivili bir saati vardır, pencere orada
  /// anlamsız. Esnek işte ise "istediğin yere taşı"yı "şu aralıkta taşı"ya
  /// çeviriyor — Günü Kurtar bu sınırı aşamaz (§Zb).
  double? windowStart;
  double? windowEnd;

  /// Aynı işin o gün tekrarlanacağı saatler; boş => tek sefer.
  ///
  /// Pencereden farkı: pencere bir **kısıt** (iş bir kez olur, yeri
  /// serbesttir), bu ise bir **çoğalma** (iş birkaç kez olur, her tekrar ayrı
  /// tamamlanır). İlaç, su içme, kontrol turu bu ikincisi (plan §Za).
  ///
  /// [startHour] kaldırılmadı, listenin ilk öğesinin **aynası** oldu:
  /// [date]'in nullable yapılmama gerekçesiyle aynı gerekçe — `startHour` kod
  /// tabanında çok yerde okunuyor (sıralama, ızgara yerleşimi, çakışma
  /// paylaşımı) ve kaldırmak her çağrı yerine bir hata fırsatı eklerdi. Liste
  /// [setTimes] üzerinden değişiyor ve aynayı o koruyor.
  List<double> timesOfDay;

  /// Çoklu saatte hangi tekrarın tamamlandığı: `2026-08-17#08.00`.
  ///
  /// [completedOn] gün hassasiyetinde kalıyor, bu onun yanına geliyor. Aynı
  /// kümede toplansalardı "sabah içtim" ile "üçünü de içtim" ayırt edilemezdi
  /// — [completedOn] ile [skippedOn] ayrımının aynı mantığı.
  ///
  /// Anahtar **saat değeri**, dizin değil: 14:00 silindiğinde 08:00'in
  /// tamamlanmışlığı yerinde kalsın diye. Dizinle anahtarlansaydı bir saati
  /// çıkarmak kalanların geçmişini kaydırırdı.
  final Set<String> completedSlots;

  Color color;
  String categoryName;
  Repeat repeat;

  // --- İlişkisel / meta veri (mimari kararlar) ---
  @override
  final Set<String> tags; // TickTick etiketleri (# olmadan); analitik + filtre
  TaskStatus status; // Kanban sütunu
  int priority; // 0 = yok ... 3 = en yüksek

  /// İşin istediği efor; null => belirtilmemiş.
  ///
  /// Zorunlu değil, olmamalı da: her iş eklemeye bir karar daha eklemek hızlı
  /// eklemenin tek nefesliğini bozardı. Belirtilmeyen iş hiçbir filtrede
  /// elenmez.
  Energy? energy;

  int timeSpentMinutes; // Pomodoro'nun yazdığı harcanan süre
  @override
  final DateTime createdAt;
  @override
  DateTime updatedAt;

  /// Tek günlük işte işin günü; rutinde rutinin başladığı gün.
  DateTime date;

  /// Havuzda bekleyen iş: **takvimde hiçbir günde görünmez.**
  ///
  /// Neden `date`'i nullable yapmak yerine bir bayrak: `date` kod tabanında
  /// 30'u aşkın yerde okunuyor ve `occursOn`, `dayKey`, `compare`, aylık/yıllık
  /// ızgaralar hepsi onun dolu olmasına yaslanıyor. Nullable yapmak her çağrı
  /// yerine bir null denetimi, yani bir hata fırsatı eklerdi. Tek kapı
  /// [occursOn] olduğu için tek bir bayrak hepsini kapsıyor.
  ///
  /// [date] bilerek silinmiyor: işin hangi günden çekildiği "geri koy" için
  /// lazım — havuzdan çıkarken "eskiden Salı'daydı" diyebilmek için.
  bool inPool;

  /// "Günü kurtar"ın (Kaos düğmesi) dokunamayacağı iş: randevu, ders, uçuş.
  ///
  /// Neden `priority` değil: aciliyet ile **kımıldatılamazlık** aynı şey değil.
  /// Doktor randevusu düşük öncelikli ama sabittir; refactor yüksek öncelikli
  /// ama esnektir. İki eksen tek alana yüklenirse ikisi de anlamını yitirir.
  ///
  /// Varsayılan `false` bilinçli: kullanıcı hiçbir şey işaretlemezse düğme
  /// **çalışır**. Tersi olsaydı özellik sessizce ölü doğardı — kimse önceden
  /// bütün işlerini "esnek" diye işaretlemez.
  bool isFixed;

  /// Rutinlerde hangi günlerde tamamlandığı; tek günlük işte 0 veya 1 eleman.
  final Set<DateTime> completedOn;

  /// Rutinin **bilerek** atlandığı günler.
  ///
  /// [completedOn]'dan ayrı tutuluyor: "yapmadım" ile "bugün geçiyorum" aynı
  /// şey değil. Tek kümede toplansalardı atlanan gün tamamlanmış sayılır,
  /// tamamlanma istatistiği yalan söylerdi.
  ///
  /// Atlanan gün [occursOn]'dan **düşmez** — iş o günde durmaya devam eder,
  /// yalnız üstü çizili ve soluk çizilir. Düşseydi atlamak silmekten ayırt
  /// edilemez, kullanıcı fikrini değiştirdiğinde dokunacağı bir şey kalmazdı.
  /// Havuzun aksine bu bir görünürlük kuralı değil, gün üstünde bir durum —
  /// tıpkı [completedOn] gibi.
  final Set<DateTime> skippedOn;

  @override
  String? groupId;

  @override
  final String? ownerId;

  Task({
    String? id,
    required this.title,
    this.note = '',
    this.place = '',
    this.sketch,
    this.startHour,
    this.durationHours = 1.0,
    this.windowStart,
    this.windowEnd,
    List<double>? timesOfDay,
    Set<String>? completedSlots,
    required this.color,
    this.categoryName = '',
    this.repeat = const Repeat.once(),
    required DateTime date,
    this.inPool = false,
    this.isFixed = false,
    Set<DateTime>? completedOn,
    Set<DateTime>? skippedOn,
    Set<String>? tags,
    this.status = TaskStatus.todo,
    this.priority = 0,
    this.energy,
    this.timeSpentMinutes = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.groupId,
    this.ownerId,
  }) : id = id ?? newNodeId(),
       date = dayKey(date),
       timesOfDay = _normalizeTimes(timesOfDay),
       completedSlots = completedSlots ?? <String>{},
       completedOn = completedOn ?? <DateTime>{},
       skippedOn = skippedOn ?? <DateTime>{},
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

  /// Süresi var mı? Saat ile süre birbirinden bağımsız (Z1): "15:00'te
  /// annemi ara" saatli ama süresiz, "bugün bir yerde 2 saat" süreli ama
  /// saatsiz. Süresiz iş depoda `durationHours = 0`.
  bool get hasDuration => durationHours > 0;

  /// Saatli ama süresiz: takvimde bir blok değil, bir **an**.
  bool get isPointInTime => scheduled && !hasDuration;

  double? get endHour =>
      startHour == null ? null : (startHour! + durationHours).clamp(0.0, 24.0);

  /// Bu iş o gün birden çok kez mi tekrarlanıyor?
  bool get hasManyTimes => timesOfDay.length > 1;

  /// O günün tekrar saatleri. Çoklu saat yoksa tek öğe: [startHour].
  ///
  /// Çağıran taraf "bir mi çok mu" diye ayrım yapmak zorunda kalmasın diye
  /// tek kapı: saatsiz işte boş liste döner.
  List<double> get occurrenceHours {
    if (timesOfDay.isNotEmpty) return timesOfDay;
    final s = startHour;
    return s == null ? const [] : [s];
  }

  /// Saat listesini yazar ve [startHour] aynasını korur.
  ///
  /// Sıralanıp yinelenenler atılıyor: ızgara sıralı bekliyor ve aynı saati
  /// iki kez eklemek görünmeyen bir çift blok üretirdi.
  void setTimes(List<double> hours) {
    timesOfDay = _normalizeTimes(hours);
    if (timesOfDay.isNotEmpty) startHour = timesOfDay.first;
  }

  /// [day] gününün [hour] tekrarının kimliği.
  static String slotKey(DateTime day, double hour) =>
      '${dateToKey(dayKey(day))}#${hour.toStringAsFixed(2)}';

  bool isSlotDone(DateTime day, double hour) =>
      completedSlots.contains(slotKey(day, hour));

  void setSlotDone(DateTime day, double hour, bool done) {
    final k = slotKey(day, hour);
    done ? completedSlots.add(k) : completedSlots.remove(k);

    // Gün, ancak o günün **bütün** tekrarları bittiğinde tamamlanmış sayılır.
    // Biri işaretliyken günü tamamlanmış saymak, üç kez içilecek ilacın ilk
    // dozunda "bitti" demek olurdu.
    final hours = occurrenceHours;
    setDone(day, hours.isNotEmpty && hours.every((h) => isSlotDone(day, h)));
  }

  bool isDoneOn(DateTime day) => completedOn.contains(dayKey(day));

  /// Bu iş, elde [limit] kadar enerji varken fazla mı geliyor?
  ///
  /// Eforu belirtilmemiş iş **asla** elenmez: filtre bir öneri, sansür değil.
  /// Aksi hâlde alanı hiç doldurmayan biri bir gün filtreyi açar ve takvimini
  /// tamamen solmuş bulurdu.
  bool exceedsEnergy(Energy? limit) =>
      limit != null && energy != null && energy!.index < limit.index;

  void setDone(DateTime day, bool done) {
    final k = dayKey(day);
    done ? completedOn.add(k) : completedOn.remove(k);
  }

  /// Bu gün bilerek atlandı mı? (Yalnız rutinlerde anlamlı.)
  bool isSkippedOn(DateTime day) => skippedOn.contains(dayKey(day));

  void setSkipped(DateTime day, bool skipped) {
    final k = dayKey(day);
    skipped ? skippedOn.add(k) : skippedOn.remove(k);
  }

  /// "Günü kurtar" bu işe [day] gününde dokunabilir mi?
  ///
  /// Üç kapı, üçü de plan §6'nın sözleşmesinden: sabit iş yerinde kalır,
  /// tamamlanmış iş dokunulmaz, zaten atlanmış rutin ikinci kez atlanmaz.
  /// Havuzdakiler zaten hiçbir günde görünmediği için ayrı bir denetim
  /// gerektirmiyor.
  bool isRescuableOn(DateTime day) =>
      !isFixed && !isDoneOn(day) && !isSkippedOn(day);

  /// Bu iş verilen günde görünür mü?
  bool occursOn(DateTime day) {
    // Havuzun tek kapısı. Takvimin her okuması buradan geçtiği için havuza
    // atılan iş tek satırla bütün görünümlerden çekiliyor.
    if (inPool) return false;

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

  /// "1 sa 30 dk" gibi süre metni; sıfır "Süresiz".
  static String formatDuration(double hours) {
    final total = (hours * 60).round();
    if (total <= 0) return 'Süresiz';
    final h = total ~/ 60;
    final m = total % 60;
    if (h == 0) return '$m dk';
    if (m == 0) return '$h sa';
    return '$h sa $m dk';
  }

  String get startString => startHour == null ? '' : formatTime(startHour!);
  String get endString => endHour == null ? '' : formatTime(endHour!);
  String get durationString => formatDuration(durationHours);
  String get timeString => !scheduled
      ? 'Saatsiz'
      // Süresiz işte "14:00 – 14:00" yazmak bir aralık varmış gibi okunurdu.
      : hasDuration
      ? '$startString – $endString'
      : startString;

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
    windowStart: windowStart,
    windowEnd: windowEnd,
    timesOfDay: [...timesOfDay],
    completedSlots: {...completedSlots},
    color: color,
    categoryName: categoryName,
    repeat: repeat,
    date: date,
    inPool: inPool,
    isFixed: isFixed,
    completedOn: {...completedOn},
    skippedOn: {...skippedOn},
    tags: {...tags},
    status: status,
    priority: priority,
    energy: energy,
    timeSpentMinutes: timeSpentMinutes,
    createdAt: createdAt,
    updatedAt: updatedAt,
    // Aynı işin aynısı: grubu da kökeni de aynı kalmalı. Düşseydi geri alma
    // (undo) sessizce grup işini kişiselleştirirdi.
    groupId: groupId,
    ownerId: ownerId,
  );

  /// Kullanıcının "Kopyala" dediğinde ürettiği yeni iş.
  ///
  /// [copy]'den farkı bilinçli: yeni bir kimlik alır (aksi hâlde iki blok aynı
  /// görevi gösterirdi) ve tamamlanma geçmişini devralmaz — kopya henüz
  /// yapılmadı, kaynağın geçmişi ona ait değil.
  ///
  /// Havuz bayrağı da devralınmaz: bir güne kopyalamak o işi takvime koymak
  /// demek. Havuzdaki bir işin kopyası yine havuzda doğsaydı, kullanıcı
  /// kopyaladığı şeyi hiçbir yerde göremezdi.
  ///
  /// [isFixed] ise **devralınır**: kımıldatılamazlık işin kendi doğası
  /// (randevu, ders, uçuş), kopyada kaybolursa kopya sessizce esnek doğar ve
  /// ilk "Günü kurtar"da süpürülür. [skippedOn] devralınmaz — geçmiş,
  /// [completedOn] gibi, kaynağa ait.
  Task duplicateTo(DateTime day) => Task(
    title: title,
    note: note,
    place: place,
    sketch: sketch,
    startHour: startHour,
    durationHours: durationHours,
    // Pencere de [isFixed] gibi işin kendi doğası: kopyada kaybolursa kopya
    // sessizce sınırsız doğar ve ilk Günü Kurtar'da pencerenin dışına düşer.
    windowStart: windowStart,
    windowEnd: windowEnd,
    // Saatler devralınır; hangi tekrarın yapıldığı **devralınmaz** —
    // [completedOn] gibi o da kaynağa ait.
    timesOfDay: [...timesOfDay],
    color: color,
    categoryName: categoryName,
    repeat: repeat,
    date: day,
    isFixed: isFixed,
    tags: {...tags},
    status: status,
    priority: priority,
    energy: energy,
    // Grup devralınır: bir grup işini kopyalamak o grupta çalışmaktır.
    // Köken **devralınmaz** — kopyayı kopyalayan yazdı, sunucu `owner_id`'yi
    // zaten çağırana yazacak.
    groupId: groupId,
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
    'windowStart': windowStart,
    'windowEnd': windowEnd,
    'timesOfDay': timesOfDay,
    'completedSlots': completedSlots.toList(),
    'colorHex': colorToHex(color),
    'categoryName': categoryName,
    'repeat': repeat.toJson(),
    'date': dateToKey(date),
    'inPool': inPool,
    'isFixed': isFixed,
    'completedOn': completedOn.map(dateToKey).toList(),
    'skippedOn': skippedOn.map(dateToKey).toList(),
    'tags': tags.toList(),
    'status': status.name,
    'priority': priority,
    // Belirtilmemiş efor anahtarı yazılır ama null kalır; eski kayıtlarda
    // anahtar hiç yok, ikisi de aynı kapıya çıkıyor.
    'energy': energy?.name,
    'timeSpentMinutes': timeSpentMinutes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    ...groupFields(groupId, ownerId),
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
    // Yarım ya da ters pencere okunmuyor: anahtar yoksa (eski kayıt) ya da
    // çift tutarsızsa pencere hiç yok sayılıyor. Yarısını kabul etmek,
    // ekranda ucu açık bir aralık göstermek olurdu.
    windowStart: _readWindow(j)?.$1,
    windowEnd: _readWindow(j)?.$2,
    timesOfDay: (j['timesOfDay'] as List?)
        ?.map((e) => (e as num).toDouble())
        .toList(),
    completedSlots: (j['completedSlots'] as List?)
        ?.map((e) => e as String)
        .toSet(),
    color: colorFromHex(j['colorHex'] as String?),
    categoryName: (j['categoryName'] as String?) ?? '',
    repeat: j['repeat'] == null
        ? const Repeat.once()
        : Repeat.fromJson((j['repeat'] as Map).cast<String, dynamic>()),
    date: dateFromKeyOrNull(j['date'] as String?) ?? DateTime.now(),
    // Anahtar yoksa havuz öncesi bir kayıt: takvimde durmaya devam eder.
    inPool: (j['inPool'] as bool?) ?? false,
    // Anahtar yoksa iş esnek sayılır. Eski kayıtları sabit kabul etmek
    // güvenli görünürdü ama düğmeyi ilk kullanışta hiçbir şey yapmayan bir
    // şeye çevirirdi — özellik ölü doğardı (bkz. K3).
    isFixed: (j['isFixed'] as bool?) ?? false,
    completedOn: _readDays(j['completedOn']),
    skippedOn: _readDays(j['skippedOn']),
    tags: readTags(j['tags']),
    status: TaskStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => TaskStatus.todo,
    ),
    priority: (j['priority'] as num?)?.toInt() ?? 0,
    energy: Energy.byName(j['energy'] as String?),
    timeSpentMinutes: (j['timeSpentMinutes'] as num?)?.toInt() ?? 0,
    createdAt: readDate(j['createdAt']),
    updatedAt: readDate(j['updatedAt']),
    groupId: j['groupId'] as String?,
    ownerId: j['ownerId'] as String?,
  );
}

/// `completedOn` / `skippedOn` gibi gün kümelerini kayıttan okur.
///
/// Okunamayan gün sessizce düşer: tek bozuk tarih yüzünden bütün kaydı
/// açılmaz kılmak, o güne ait tik'i kaybetmekten pahalı.
/// Saat listesini ızgaranın beklediği hâle getirir: sıralı, yinelemesiz ve
/// 0–24 aralığında. Tek öğe kalırsa liste **boşaltılıyor** — "tek sefer"in
/// gösterimi boş liste, çünkü tek saat zaten [Task.startHour]'da duruyor ve
/// iki yerde iki ayrı doğru olması er geç ayrışırdı.
List<double> _normalizeTimes(List<double>? raw) {
  if (raw == null || raw.isEmpty) return <double>[];
  final set = <double>{};
  for (final h in raw) {
    if (h >= 0 && h < 24) set.add(h);
  }
  if (set.length < 2) return <double>[];
  return set.toList()..sort();
}

/// Kayıttan pencere çifti; geçersizse **hiç yok**.
///
/// Yarım (yalnız bir uç) ya da ters (`start >= end`) bir çift okunmuyor.
/// Yarısını kabul etmek ekranda ucu açık bir aralık göstermek, tersini kabul
/// etmek ise Günü Kurtar'a hiçbir saatin sığmadığı bir kısıt vermek olurdu —
/// iş sessizce her seferinde havuza inerdi.
(double, double)? _readWindow(Map<String, dynamic> j) {
  final start = (j['windowStart'] as num?)?.toDouble();
  final end = (j['windowEnd'] as num?)?.toDouble();
  if (start == null || end == null || start >= end) return null;
  return (start, end);
}

Set<DateTime> _readDays(Object? raw) =>
    (raw as List?)
        ?.map((e) => dateFromKeyOrNull(e as String?))
        .whereType<DateTime>()
        .map(Task.dayKey)
        .toSet() ??
    <DateTime>{};

/// Görev eklerken/düzenlerken seçilebilecek renk paleti.
///
/// Neon (N5a). Önceki sekizli Material'ın pastelleriydi ve koyu temanın
/// camgöbeği/magenta jetonlarının yanında sönük duruyordu.
///
/// Seçim ölçütü üç madde, üçü de `category_colors_test.dart`'ta ölçülüyor:
/// şerit koyu zeminden 3:1 ile ayrışsın, [inkOn] ile üstüne konan mürekkep
/// AA'yı geçsin, `readableOn` yazıyı gövde mürekkebine çekerken koyu temada
/// **hiç** adım atmasın — attığı her adım kategori renginin yazıda biraz daha
/// az tanınması demek.
///
/// Tema jetonlarının birebir aynısı seçilmedi (`accent` `#22D3EE`, `warning`
/// `#FDE047`, `danger` `#FF4D6D`, `nowLine` `#FF2BD6`): kırmızı bir kategori
/// ile tehlike rengi ya da bir iş bloğu ile "şu an" çizgisi aynı sinyali
/// taşımasın. Komşu tonlar alındı, aynıları değil.
///
/// Bu liste değişirse `kLegacyTaskColors` (node.dart) da değişmeli — eskiden
/// yazılmış renkleri buraya taşıyan eşleme orada.
const List<Color> kTaskColors = [
  Color(0xFFFF3D8B), // pembe
  Color(0xFF38BDF8), // mavi
  Color(0xFF34E39B), // yeşil
  Color(0xFFFF9E3D), // turuncu
  Color(0xFFA78BFA), // mor
  Color(0xFF00E5C7), // turkuaz
  Color(0xFFF2E14C), // sarı
  Color(0xFFFF5C5C), // kırmızı
];

/// Bir iş kategorisi: ad + renk. Hazır olanlar + kullanıcının eklediği özel olanlar.
class TaskCategory {
  /// **Depolanan** ad. Kaydın kimliği; değişmez (bkz. [categoryLabel]).
  final String name;
  final Color color;
  
  /// Kullanıcının bu kategori için belirlediği özel ad (varsa).
  final String? customLabel;
  
  const TaskCategory(this.name, this.color, {this.customLabel});

  /// Ekranda görünecek hâli. Kullanıcı özel bir ad verdiyse o görünür, yoksa
  /// varsayılan ad gösterilir.
  String get label => customLabel ?? categoryLabel(name);
  
  TaskCategory copyWith({
    String? name,
    Color? color,
    String? customLabel,
  }) {
    return TaskCategory(
      name ?? this.name,
      color ?? this.color,
      customLabel: customLabel ?? this.customLabel,
    );
  }
}

/// Hazır kategorilerin görünen adları: depolanan ad → ekrandaki ad.
///
/// Depolanan ad bilerek değişmiyor. O metin hem yerel anlık görüntüde hem
/// sunucuda duruyor ve senkronda kaydın kimliği; yeniden adlandırmak üç yeri
/// birden kırardı: eski anlık görüntüler, kuyrukta bekleyen değişiklikler ve
/// **eski sürümdeki ikinci cihaz** — o cihaz eski adı geri yazar, kategori
/// ikiye bölünürdü. Bu yüzden Başlık Düzeni yalnız görünen tarafta yaşıyor
/// (bkz. `docs/zaman-araliklari-ve-adlandirma-plani.md` §Zd).
///
/// Adlar **elle** yazıldı; `toUpperCase()` kullanılmıyor. Dart varsayılan
/// yerelde `'iş'.toUpperCase()` için `IŞ` üretir, `İŞ` değil — büyük harfe
/// çevirmeyi koda bırakmak ekranda "Kalıcı Iş" yazdırırdı.
///
/// K1 (10 Eylül): her biri **tek kısa kelime**. "Hobi / keyfi" gibi eğik
/// çizgili adlar iki ekseni (tür ve sıklık) karıştırıyordu; sıklık zaten işin
/// kendi ayarı (Tek Günlük / Rutin). "Rutin" bilerek kullanılmadı — işin
/// türüyle çakışırdı. Kullanıcı her birini Kategoriler sayfasından yeniden
/// adlandırabiliyor.
const Map<String, String> kCategoryLabels = {
  'Kalıcı iş': 'Mesai',
  'Günlük rutin': 'Gündelik',
  'Haftalık / ara sıra': 'Seyrek',
  'Önemli / acil': 'Acil',
  'Hobi / keyfi': 'Hobi',
};

/// Depolanan kategori adının ekranda görüneceği hâli.
///
/// Tanınmayan ad **olduğu gibi** dönüyor: kullanıcının kendi yazdığı özel
/// kategorinin yazımına karışmak, onu kendi verisinde tanınmaz hâle getirirdi.
String categoryLabel(String storedName) =>
    kCategoryLabels[storedName] ?? storedName;

/// Uygulama genel ayarları + kategori listesi (sadece bellekte tutulur).
class AppData {
  /// Hazır + özel kategoriler. Renk = işin TÜRÜ/anlamı.
  static List<TaskCategory> categories = [
    const TaskCategory('Kalıcı iş', Color(0xFFFF5C5C)),
    const TaskCategory('Günlük rutin', Color(0xFF38BDF8)),
    const TaskCategory('Haftalık / ara sıra', Color(0xFFFF3D8B)),
    const TaskCategory('Önemli / acil', Color(0xFFFF9E3D)),
    const TaskCategory('Hobi / keyfi', Color(0xFF34E39B)),
    const TaskCategory('Sosyal', Color(0xFFA78BFA)),
    const TaskCategory('Diğer', Color(0xFFF2E14C)),
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
