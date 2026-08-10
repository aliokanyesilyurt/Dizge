import 'package:flutter/material.dart';
import 'node.dart';

/// Alışkanlığın ritmi:
/// - [daily]: her gün yapılması beklenir (seri = ardışık gün).
/// - [weekly]: haftada [Habit.targetPerWeek] kez yeter (esnek rutin; seri =
///   hedefi tutturan ardışık haftalar).
enum HabitCadence { daily, weekly }

/// Alışkanlık: takvimdeki rutinden farklı olarak "zinciri kırma" (streak)
/// psikolojisi ve ısı haritası için ayrı bir veri modeli. Her tamamlanan gün
/// [doneDates]'e yazılır (yalnızca gün hassasiyetinde).
class Habit {
  final String id;
  String title;
  Color color;
  HabitCadence cadence;

  /// [HabitCadence.weekly] için haftalık hedef (ör. haftada 3).
  int targetPerWeek;

  final Set<DateTime> doneDates;
  final DateTime createdAt;

  /// Son değişiklik damgası — senkronda **son yazan kazanır** hakemi budur.
  ///
  /// Alan eksik geldiğinde varsayılan bilinçli olarak [createdAt]; `DateTime
  /// .now()` değil. "Şimdi" demek, hiç değişmemiş bir alışkanlığın her
  /// açılışta kendini en yeni ilan etmesi ve sunucudaki kopyayı ezmesi olurdu.
  DateTime updatedAt;

  Habit({
    String? id,
    required this.title,
    required this.color,
    this.cadence = HabitCadence.daily,
    this.targetPerWeek = 3,
    Set<DateTime>? doneDates,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? newNodeId(),
       doneDates = doneDates ?? <DateTime>{},
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  /// Değişiklik damgasını tazeler. Modeli değiştiren her yol bunu çağırmalı;
  /// aksi hâlde değişiklik sunucuya gider ama "eski" damgayla gider ve
  /// karşıdaki daha yeni kayıt tarafından sessizce reddedilir.
  void touch() => updatedAt = DateTime.now();

  bool isDoneOn(DateTime day) => doneDates.contains(dayOnly(day));

  void setDone(DateTime day, bool done) {
    final k = dayOnly(day);
    done ? doneDates.add(k) : doneDates.remove(k);
  }

  void toggle(DateTime day) => setDone(day, !isDoneOn(day));

  /// Haftanın Pazartesi'si (ISO). Haftalık gruplamada anahtar.
  static DateTime weekStart(DateTime d) {
    final day = dayOnly(d);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  /// [day]'in içinde bulunduğu haftada kaç kez yapıldı. Haftalık ritimde
  /// ilerlemeyi ("2/3") göstermek için; seri sayısı bu soruya cevap vermiyor.
  int doneInWeekOf(DateTime day) => _doneInWeek(weekStart(day));

  int _doneInWeek(DateTime weekStartDay) {
    var c = 0;
    for (var i = 0; i < 7; i++) {
      if (doneDates.contains(weekStartDay.add(Duration(days: i)))) c++;
    }
    return c;
  }

  /// Güncel seri. Bugün henüz yapılmadıysa seriyi kırmaz (dünden sayar).
  int get currentStreak =>
      cadence == HabitCadence.daily ? _dailyStreak() : _weeklyStreak();

  int _dailyStreak() {
    var day = dayOnly(DateTime.now());
    if (!doneDates.contains(day)) {
      day = day.subtract(const Duration(days: 1)); // bugün bekleyebilir
    }
    var n = 0;
    while (doneDates.contains(day)) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }

  int _weeklyStreak() {
    var week = weekStart(DateTime.now());
    // İçinde bulunulan hafta henüz dolmadıysa ve hedef tutmadıysa geçen haftadan başla.
    if (_doneInWeek(week) < targetPerWeek) {
      week = week.subtract(const Duration(days: 7));
    }
    var n = 0;
    while (_doneInWeek(week) >= targetPerWeek) {
      n++;
      week = week.subtract(const Duration(days: 7));
    }
    return n;
  }

  /// Son [days] gün içindeki tamamlanma oranı (0-1). Isı haritası özeti için.
  double completionRate(int days) {
    if (days <= 0) return 0;
    final today = dayOnly(DateTime.now());
    var done = 0;
    for (var i = 0; i < days; i++) {
      if (doneDates.contains(today.subtract(Duration(days: i)))) done++;
    }
    if (cadence == HabitCadence.weekly) {
      // Beklenen = hedef * (days/7); orantısal.
      final expected = targetPerWeek * (days / 7);
      return expected == 0 ? 0 : (done / expected).clamp(0.0, 1.0);
    }
    return done / days;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'colorHex': colorToHex(color),
    'cadence': cadence.name,
    'targetPerWeek': targetPerWeek,
    'doneDates': doneDates.map(dateToKey).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
    id: j['id'] as String?,
    title: (j['title'] as String?) ?? '',
    color: colorFromHex(j['colorHex'] as String?),
    cadence: HabitCadence.values.firstWhere(
      (c) => c.name == j['cadence'],
      orElse: () => HabitCadence.daily,
    ),
    targetPerWeek: (j['targetPerWeek'] as num?)?.toInt() ?? 3,
    doneDates:
        (j['doneDates'] as List?)
            ?.map((e) => dateFromKeyOrNull(e as String?))
            .whereType<DateTime>()
            .map(dayOnly)
            .toSet() ??
        <DateTime>{},
    createdAt: readDate(j['createdAt']),
    // Yokluğu `null` olarak geçiyor ki kurucu [createdAt]'e düşebilsin.
    // `readDate` burada yanlış olurdu: eksik alanı "şimdi" sayardı.
    updatedAt: readDateOrNull(j['updatedAt']),
  );
}
