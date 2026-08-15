import 'package:flutter/material.dart';
import '../models/task.dart';
import '../theme.dart';

/// Bir grup (kategori/etiket) için toplanmış süre. Grafik satırı olarak çizilir.
class TimeBucket {
  final String label;
  final Color color;
  final double hours;
  const TimeBucket(this.label, this.color, this.hours);
}

/// Görev verisinden türetilen kullanıcı-yüzü üretkenlik raporu.
///
/// ADLANDIRMA NOTU: bu dosya eskiden `analytics.dart` idi. Uygulamaya gerçek
/// telemetri (`core/telemetry.dart`) eklenince ad çakışıyordu: burası
/// **kullanıcıya gösterilen** rapordur, dışarı hiçbir veri göndermez.
///
/// Tüm metrikler bir tarih aralığındaki **görev tekrarları** (occurrence)
/// üzerinden hesaplanır: rutinler her göründüğü günde bir kez sayılır.
class ProductivityReport {
  /// Aralıktaki planlanmış (bugüne kadar vadesi gelmiş) toplam tekrar.
  final int planned;

  /// Bunların kaçı tamamlandı.
  final int completed;

  /// Kategoriye göre planlanan toplam süre (saat), büyükten küçüğe.
  final List<TimeBucket> byCategory;

  /// Etikete göre planlanan toplam süre (saat), büyükten küçüğe.
  final List<TimeBucket> byTag;

  /// Haftanın her günü için tamamlanma oranı (Pzt=0 ... Paz=6). Erteleme analizi.
  final List<double> weekdayCompletion;

  /// Aralıktaki her gün için tamamlanma oranı (eski → yeni), trend çizgisi için.
  final List<double> dailyCompletion;

  const ProductivityReport({
    required this.planned,
    required this.completed,
    required this.byCategory,
    required this.byTag,
    required this.weekdayCompletion,
    required this.dailyCompletion,
  });

  double get completionRate => planned == 0 ? 0 : completed / planned;

  /// Erteleme eğiliminin en yüksek olduğu gün (en düşük tamamlanma). Veri yoksa null.
  int? get worstWeekday {
    int? worst;
    var min = 2.0;
    for (var i = 0; i < weekdayCompletion.length; i++) {
      if (weekdayCompletion[i] >= 0 && weekdayCompletion[i] < min) {
        min = weekdayCompletion[i];
        worst = i;
      }
    }
    return worst;
  }

  static const weekdayNames = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  /// [tasks] üzerinden son [days] günü kapsayan raporu üretir.
  factory ProductivityReport.build(List<Task> tasks, {int days = 30}) {
    final today = Task.dayKey(DateTime.now());
    final catHours = <String, double>{};
    final catColor = <String, Color>{};
    final tagHours = <String, double>{};

    var planned = 0;
    var completed = 0;

    // Haftanın günü ve günlük birikimler.
    final wdPlanned = List<int>.filled(7, 0);
    final wdDone = List<int>.filled(7, 0);
    final dailyRates = <double>[];

    for (var i = days - 1; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final occurrences = tasks.where((t) => t.occursOn(day)).toList();
      var dayPlanned = 0;
      var dayDone = 0;

      for (final t in occurrences) {
        planned++;
        dayPlanned++;
        wdPlanned[day.weekday - 1]++;

        final cat = t.categoryName.isEmpty ? 'Kategorisiz' : t.categoryName;
        catHours[cat] = (catHours[cat] ?? 0) + t.durationHours;
        catColor[cat] = t.color;
        for (final tag in t.tags) {
          tagHours[tag] = (tagHours[tag] ?? 0) + t.durationHours;
        }

        if (t.isDoneOn(day)) {
          completed++;
          dayDone++;
          wdDone[day.weekday - 1]++;
        }
      }
      dailyRates.add(dayPlanned == 0 ? 0 : dayDone / dayPlanned);
    }

    List<TimeBucket> buckets(
      Map<String, double> hours,
      Map<String, Color>? colors,
    ) {
      final list =
          hours.entries
              .map(
                (e) => TimeBucket(
                  e.key,
                  colors?[e.key] ?? kUnknownCategoryColor,
                  e.value,
                ),
              )
              .toList()
            ..sort((a, b) => b.hours.compareTo(a.hours));
      return list;
    }

    final weekday = List<double>.generate(
      7,
      (i) => wdPlanned[i] == 0 ? -1 : wdDone[i] / wdPlanned[i],
    );

    return ProductivityReport(
      planned: planned,
      completed: completed,
      byCategory: buckets(catHours, catColor),
      byTag: buckets(tagHours, null),
      weekdayCompletion: weekday,
      dailyCompletion: dailyRates,
    );
  }
}
