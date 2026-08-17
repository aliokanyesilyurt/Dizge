import 'package:flutter/material.dart';
import 'node.dart';

/// Alışkanlık: **süreksiz** olan iş.
///
/// Rutinle ayrımı bilinçli ve modelde (plan §Zc):
///
/// | | Alışkanlık | Rutin (`Task` + `Repeat`) |
/// |---|---|---|
/// | Ritim | Süreksiz — haftada [targetPerWeek] kez yeter | Sürekli, düzenli |
/// | Saat | Yok; gün içinde istediğin an | Var; takvimde blok |
/// | Ölçü | Seri (streak) + ısı haritası | Tamamlama / atlama |
///
/// Eskiden ayrıca bir `HabitCadence` ekseni vardı (`daily` / `weekly`) ve
/// `daily` bu ayrımı çürütüyordu: her gün belli bir şeyi yapmak alışkanlık
/// değil rutindir. Eksen kaldırıldı; ritmin tamamı [targetPerWeek] (1–7).
/// Haftada 7 "her gün" demek — anlam kayboldu değil, tek yere indi.
///
/// Her tamamlanan gün [doneDates]'e yazılır (yalnızca gün hassasiyetinde).
class Habit {
  final String id;
  String title;
  Color color;
  /// Haftada kaç kez yapılması bekleniyor (1–7).
  ///
  /// 7 = her gün. Ritmin tek ekseni bu; ayrı bir "günlük mü haftalık mı"
  /// sorusu yok.
  int targetPerWeek;

  /// Her gün beklenen bir alışkanlık mı? Ölçünün birimini bu belirliyor.
  bool get isEveryDay => targetPerWeek >= 7;

  final Set<DateTime> doneDates;
  final DateTime createdAt;

  /// Son değişiklik damgası — senkronda **son yazan kazanır** hakemi budur.
  ///
  /// Alan eksik geldiğinde varsayılan bilinçli olarak [createdAt]; `DateTime
  /// .now()` değil. "Şimdi" demek, hiç değişmemiş bir alışkanlığın her
  /// açılışta kendini en yeni ilan etmesi ve sunucudaki kopyayı ezmesi olurdu.
  DateTime updatedAt;

  /// Hangi gruba ait; null ise kişisel (Y4). Bkz. [Node.groupId].
  String? groupId;

  /// Kaydı oluşturan kişi; sunucu yazar (Y4). Bkz. [Node.ownerId].
  final String? ownerId;

  Habit({
    String? id,
    required this.title,
    required this.color,
    this.targetPerWeek = 3,
    Set<DateTime>? doneDates,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.groupId,
    this.ownerId,
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
  ///
  /// Birimi hedeften çıkıyor: her gün beklenen alışkanlıkta **ardışık gün**,
  /// haftada N'de **hedefi tutturan ardışık hafta**. Eskiden bunu ayrı bir
  /// ritim ekseni söylüyordu; eksen kalkınca ölçü hedefin kendisinden
  /// türetiliyor — ve günlük alışkanlıkların gördüğü sayı değişmiyor.
  int get currentStreak => isEveryDay ? _dailyStreak() : _weeklyStreak();

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
    if (!isEveryDay) {
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
    // `cadence` artık modelde yok ama **yazılmaya devam ediyor**: bu sürümü
    // tanımayan bir cihaz alanı bulamazsa varsayılana (her gün) düşer ve
    // haftada 3'lük bir alışkanlık orada günlük görünürdü. Türetilen değer
    // yazmak, o cihazın doğru okumasını sürdürüyor.
    'cadence': isEveryDay ? 'daily' : 'weekly',
    'targetPerWeek': targetPerWeek,
    'doneDates': doneDates.map(dateToKey).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    ...groupFields(groupId, ownerId),
  };

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
    id: j['id'] as String?,
    title: (j['title'] as String?) ?? '',
    color: colorFromHex(j['colorHex'] as String?),
    // Göç (§Zc): eski `daily` kaydı "haftada 7" olarak okunuyor. Silinmiyor,
    // susturulmuyor — anlamı korunuyor ve serisi aynı gün sayısını göstermeye
    // devam ediyor. Kullanıcı isterse hedefi düşürür.
    targetPerWeek: j['cadence'] == 'daily'
        ? 7
        : ((j['targetPerWeek'] as num?)?.toInt() ?? 3).clamp(1, 7),
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
    groupId: j['groupId'] as String?,
    ownerId: j['ownerId'] as String?,
  );
}
