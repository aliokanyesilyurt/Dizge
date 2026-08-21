import 'package:dizge/models/task.dart';
import 'package:dizge/screens/reports_screen.dart';
import 'package:dizge/services/productivity_report.dart';
import 'package:dizge/widgets/report_charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Rapor, seçilen gün aralığını gerçekten göstermeli.
///
/// Bildirilen kusur: "raporlar gün sayısına göre düzenlenmiyor, grafikler
/// hafif bozuk, sayılar değişmiyor". Üç ayrı sebep vardı:
///
///   1. `dailyCompletion` hesaplanıyor ama **hiçbir grafik onu çizmiyordu** —
///      aralığın tek gerçek görsel karşılığı olan trend eksikti.
///   2. Çubuklar mutlak toplam gösteriyordu. Toplam, aralık uzadıkça zaten
///      büyür; bilgi taşımaz. Günlük ortalama taşır.
///   3. Bilerek atlanan rutin günü "planlandı ama yapılmadı" sayılıyor,
///      tamamlanma oranını düşürüyordu.
void main() {
  setUp(TaskRepository.all.clear);

  final today = Task.dayKey(DateTime.now());

  Task dailyRoutine({DateTime? from}) => Task(
    title: 'Sabah koşusu',
    color: Colors.green,
    date: from ?? today.subtract(const Duration(days: 200)),
    startHour: 7,
    durationHours: 1,
    categoryName: 'spor',
    repeat: const Repeat(RepeatType.daily),
  );

  group('atlanan gün', () {
    test('planlanan sayılmaz — oranı düşürmez', () {
      final routine = dailyRoutine();
      final full = ProductivityReport.build([routine], days: 7);
      expect(full.planned, 7);

      routine.setSkipped(today, true);
      routine.setSkipped(today.subtract(const Duration(days: 1)), true);

      final skipped = ProductivityReport.build([routine], days: 7);
      expect(
        skipped.planned,
        5,
        reason: 'bilerek atlanan gün plana dahil değil',
      );
      expect(skipped.completionRate, full.completionRate);
    });

    test('atlanan gün kategoriye süre de yazmaz', () {
      final routine = dailyRoutine();
      routine.setSkipped(today, true);

      final report = ProductivityReport.build([routine], days: 7);
      final spor = report.byCategory.firstWhere((b) => b.label == 'spor');

      expect(spor.hours, 6, reason: 'yapılmayacak iş için saat ayrılmaz');
    });

    test('tamamlanmış gün atlanmış sayılmaz', () {
      final routine = dailyRoutine();
      routine.setDone(today, true);

      final report = ProductivityReport.build([routine], days: 7);
      expect(report.planned, 7);
      expect(report.completed, 1);
    });
  });

  group('aralık duyarlılığı', () {
    test('aynı veri, farklı aralık — farklı sayılar', () {
      final routine = dailyRoutine();

      final week = ProductivityReport.build([routine], days: 7);
      final quarter = ProductivityReport.build([routine], days: 90);

      expect(week.planned, 7);
      expect(quarter.planned, 90);
      expect(week.days, 7);
      expect(quarter.days, 90);
    });

    test('günlük trend, aralık kadar nokta taşır', () {
      final report = ProductivityReport.build([dailyRoutine()], days: 30);
      expect(report.dailyCompletion.length, 30);
    });

    test('işsiz gün trendde boşluk, sıfır değil', () {
      // Tek bir günde tek iş: kalan altı gün "%0 tamamlandı" değil, "veri
      // yok". İkisini aynı göstermek, hiç iş yazılmamış bir haftayı
      // başarısız bir hafta gibi çizerdi.
      final task = Task(title: 'Rapor', color: Colors.blue, date: today);
      final report = ProductivityReport.build([task], days: 7);

      expect(report.dailyCompletion.last, 0, reason: 'bugün planlı ama açık');
      expect(report.dailyCompletion.first, -1, reason: 'o gün hiç iş yoktu');
    });

    test('günlük ortalama iş sayısı aralığa bölünür', () {
      final report = ProductivityReport.build([dailyRoutine()], days: 30);
      expect(report.plannedPerDay, 1);
    });
  });

  group('rapor ekranı', () {
    testWidgets('aralık değişince ekrandaki sayılar değişiyor', (tester) async {
      useScreenSize(tester, const Size(1200, 1400));

      await pumpApp(
        tester,
        const ReportsScreen(),
        seed: (store) => store.addTask(dailyRoutine()),
      );

      // Varsayılan 30 gün.
      expect(find.text('Son 30 günün üretkenlik özeti'), findsOneWidget);
      expect(find.text('30'), findsWidgets, reason: 'planlanan toplam 30');

      await tester.tap(find.text('7g'));
      await tester.pumpAndSettle();

      expect(find.text('Son 7 günün üretkenlik özeti'), findsOneWidget);
      expect(find.text('7'), findsWidgets, reason: 'planlanan toplam 7');
    });

    testWidgets('trend grafiği çiziliyor', (tester) async {
      useScreenSize(tester, const Size(1200, 1400));

      await pumpApp(
        tester,
        const ReportsScreen(),
        seed: (store) => store.addTask(dailyRoutine()),
      );

      // Aralığın tek gerçek görsel karşılığı; hesaplanıp çizilmiyordu.
      expect(find.byType(TrendChart), findsOneWidget);
    });

    testWidgets('kategori çubuğu günlük ortalama gösteriyor', (tester) async {
      useScreenSize(tester, const Size(1200, 1400));

      await pumpApp(
        tester,
        const ReportsScreen(),
        seed: (store) => store.addTask(dailyRoutine()),
      );

      // Günde bir saatlik rutin: aralık ne olursa olsun "1 sa".
      // Mutlak toplam olsaydı 30g'de "30 sa", 90g'de "90 sa" yazardı —
      // aralık uzadıkça büyüyen bir sayı hiçbir şey söylemez.
      expect(find.text('Kategoriye göre günlük ortalama'), findsOneWidget);
      expect(find.text('1 sa'), findsWidgets);
    });

    testWidgets('hiç iş yokken boş durum görev eklemeyi söylüyor', (
      tester,
    ) async {
      useScreenSize(tester, const Size(1200, 1400));

      await pumpApp(tester, const ReportsScreen());

      expect(find.text('Rapor için yeterli veri yok.'), findsOneWidget);
    });

    testWidgets('iş aralığın dışındaysa boş durum aralığı söylüyor', (
      tester,
    ) async {
      useScreenSize(tester, const Size(1200, 1400));

      // Tek günlük, 200 gün önceki bir iş: hiçbir aralığa düşmüyor ama
      // kullanıcının verisi var. "Görev ekleyin" demek yanlış tavsiye olurdu.
      await pumpApp(
        tester,
        const ReportsScreen(),
        seed: (store) => store.addTask(
          Task(
            title: 'Eski iş',
            color: Colors.blue,
            date: today.subtract(const Duration(days: 200)),
          ),
        ),
      );

      expect(find.text('Son 30 günde iş yok.'), findsOneWidget);
      expect(
        find.text('Daha geniş bir aralık seçince eski işler görünebilir.'),
        findsOneWidget,
      );

      await tester.tap(find.text('7g'));
      await tester.pumpAndSettle();
      expect(find.text('Son 7 günde iş yok.'), findsOneWidget);

      // En geniş aralıkta genişletme tavsiyesi anlamsız: gidecek yer yok.
      await tester.tap(find.text('90g'));
      await tester.pumpAndSettle();
      expect(find.text('Son 90 günde iş yok.'), findsOneWidget);
      expect(
        find.text('Bu aralığa düşen planlanmış iş bulunmuyor.'),
        findsOneWidget,
      );
    });
  });
}
