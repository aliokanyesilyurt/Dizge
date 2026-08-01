import 'dart:math' as math;

/// Haftalık ızgaranın **saf** geometri ve yerleşim mantığı.
///
/// Mimari karar: burada `flutter` import'u yoktur. Çakışan etkinliklerin sütun
/// paylaşımı gibi asıl zor kısım widget ağacından bağımsız, milisaniyede
/// koşan birim testleriyle doğrulanabilir olsun diye ayrıldı.

/// Izgaranın piksel ↔ saat dönüşümü.
class GridMetrics {
  const GridMetrics({
    this.hourHeight = 64.0,
    this.dayStart = 0.0,
    this.dayEnd = 24.0,
  })  : assert(hourHeight > 0),
        assert(dayEnd > dayStart);

  /// Bir saatin piksel yüksekliği. Kullanıcı sıkıştırma (pinch) ile değiştirir.
  final double hourHeight;

  /// Izgaranın gösterdiği ilk/son saat. (İleride "çalışma saatleri" görünümü
  /// için 8–20 gibi daraltılabilir; tüm hesaplar bunu kullanır.)
  final double dayStart;
  final double dayEnd;

  static const double minHourHeight = 28.0;
  static const double maxHourHeight = 160.0;

  double get totalHeight => (dayEnd - dayStart) * hourHeight;

  /// Saat → ızgaranın tepesinden piksel.
  double yFor(double hour) => (hour - dayStart) * hourHeight;

  /// Piksel → saat (ızgara dışına taşarsa gün sınırına kırpılır).
  double hourAt(double dy) =>
      (dayStart + dy / hourHeight).clamp(dayStart, dayEnd);

  GridMetrics copyWith({double? hourHeight}) => GridMetrics(
        hourHeight: hourHeight ?? this.hourHeight,
        dayStart: dayStart,
        dayEnd: dayEnd,
      );

  /// Sıkıştırma jestinin ölçeğini uygulanabilir sınırlara oturtur.
  GridMetrics scaled(double factor) => copyWith(
        hourHeight:
            (hourHeight * factor).clamp(minHourHeight, maxHourHeight),
      );
}

/// Sürükleme sırasında saatin yuvarlanacağı adım (dakika).
const int kSnapMinutes = 15;

/// En kısa etkinlik: bundan kısası ızgarada okunamaz ve kazayla sıfırlanır.
const double kMinDurationHours = 0.25;

/// [hour]'u [minutes] dakikalık ızgaraya oturtur. Google Takvim'deki gibi
/// 15 dakikalık adımlarla hizalanır; ince ayar editörden yapılır.
double snapHour(double hour, {int minutes = kSnapMinutes}) {
  final step = minutes / 60.0;
  return (hour / step).round() * step;
}

/// Bir etkinliği gün içinde tutar: başlangıç + süre 24'ü aşarsa başlangıcı geri
/// çeker (süreyi kısaltmak yerine — kullanıcı süreyi bilerek seçmiştir).
double clampStartWithin(double start, double duration,
    {double dayStart = 0.0, double dayEnd = 24.0}) {
  final maxStart = math.max(dayStart, dayEnd - duration);
  return start.clamp(dayStart, maxStart);
}

/// Yerleşim sonrası bir etkinliğin ızgaradaki yeri.
///
/// [column]/[columns] yatay paylaşımı anlatır: 3 çakışan iş varsa her biri
/// genişliğin 1/3'ünü alır. [span] ise sağa doğru boş sütunlara taşabilmeyi
/// sağlar (tek başına kalan iş tüm genişliği kullansın diye).
class EventSlot<T> {
  EventSlot(this.item, this.start, this.end);

  final T item;
  final double start;
  final double end;

  int column = 0;
  int columns = 1;
  int span = 1;

  double get duration => end - start;

  /// Sütun düzenine göre 0–1 aralığında sol kenar.
  double get leftFraction => column / columns;

  /// Sütun düzenine göre 0–1 aralığında genişlik.
  double get widthFraction => span / columns;

  @override
  String toString() =>
      'EventSlot($item, $start-$end, col $column/$columns, span $span)';
}

/// Çakışan etkinlikleri Google Takvim'deki gibi sütunlara paylaştırır.
///
/// Algoritma:
///  1. Etkinlikler başlangıca, eşitlikte uzun olan öne gelecek şekilde sıralanır.
///  2. Zaman ekseninde **kesişmeyen** gruplara (cluster) ayrılır; bir grubun
///     sütun sayısı diğerini etkilemez — böylece sabah tek işi olan bir gün,
///     akşamki 4'lü çakışma yüzünden daralmaz.
///  3. Grup içinde her etkinlik, kendisinden önce biten ilk sütuna yerleşir.
///  4. Son adımda her etkinlik sağındaki boş sütunlara genişler.
///
/// Karmaşıklık O(n·k); k = eşzamanlı etkinlik sayısı (pratikte < 10).
List<EventSlot<T>> layoutEvents<T>(
  Iterable<T> items, {
  required double Function(T) startOf,
  required double Function(T) endOf,
}) {
  final slots = <EventSlot<T>>[];
  for (final item in items) {
    final start = startOf(item);
    // Sıfır/negatif süreli kayıt yerleşimi bozmasın: en az bir adım yer kaplar.
    final end = math.max(endOf(item), start + kMinDurationHours);
    slots.add(EventSlot<T>(item, start, end));
  }

  slots.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    return b.duration.compareTo(a.duration); // uzun olan solda
  });

  var index = 0;
  while (index < slots.length) {
    // --- 1. Grubu topla: birbirine zincirleme değen etkinlikler ---
    final group = <EventSlot<T>>[slots[index]];
    var groupEnd = slots[index].end;
    var j = index + 1;
    while (j < slots.length && slots[j].start < groupEnd) {
      group.add(slots[j]);
      groupEnd = math.max(groupEnd, slots[j].end);
      j++;
    }

    // --- 2. Sütunlara dağıt ---
    final columnEnds = <double>[]; // her sütunun son bitiş saati
    for (final slot in group) {
      var placed = false;
      for (var c = 0; c < columnEnds.length; c++) {
        // Kayan nokta gürültüsüne karşı küçük tolerans: 12:00'de biten ve
        // 12:00'de başlayan iki iş çakışmış sayılmamalı.
        if (columnEnds[c] <= slot.start + 1e-9) {
          slot.column = c;
          columnEnds[c] = slot.end;
          placed = true;
          break;
        }
      }
      if (!placed) {
        slot.column = columnEnds.length;
        columnEnds.add(slot.end);
      }
    }

    final total = columnEnds.length;
    for (final slot in group) {
      slot.columns = total;
    }

    // --- 3. Sağa genişle: boş kalan sütunları doldur ---
    for (final slot in group) {
      var span = 1;
      for (var c = slot.column + 1; c < total; c++) {
        final blocked = group.any((other) =>
            other != slot &&
            other.column == c &&
            other.start < slot.end - 1e-9 &&
            slot.start < other.end - 1e-9);
        if (blocked) break;
        span++;
      }
      slot.span = span;
    }

    index = j;
  }

  return slots;
}

/// Şu anki saatin ondalık gösterimi (14:30 → 14.5). "Şimdi" çizgisi için.
double hourOfDay(DateTime t) => t.hour + t.minute / 60.0 + t.second / 3600.0;

/// İki tarihin aynı güne düşüp düşmediği (saat kırpmadan).
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// [d]'nin içinde bulunduğu ISO haftasının pazartesisi (saat kırpılmış).
DateTime mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// İki pazartesi arasındaki hafta farkı. PageView sayfa indeksini tarihe
/// bağlamak için kullanılır (DST'ye dayanıklı olsun diye gün sayısı üzerinden).
int weeksBetween(DateTime fromMonday, DateTime toMonday) {
  final days = DateTime(toMonday.year, toMonday.month, toMonday.day)
      .difference(DateTime(fromMonday.year, fromMonday.month, fromMonday.day))
      .inDays;
  return (days / 7).round();
}
