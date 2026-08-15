import 'package:dizge/models/task.dart';
import 'package:dizge/screens/week_view_screen.dart';
import 'package:dizge/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'helpers.dart';

void main() {
  setUp(TaskRepository.all.clear);

  /// Bu haftanın Pazartesi'si — ekran her zaman içinde bulunulan haftayı açar,
  /// bu yüzden tohum verisi sabit bir tarihe değil "şimdi"ye bağlanmalı.
  DateTime thisMonday() {
    final today = Task.dayKey(DateTime.now());
    return today.subtract(Duration(days: today.weekday - 1));
  }

  group('gün başlığı', () {
    testWidgets('iş sayısı rozetle görünür, boş gün sessiz kalır', (
      tester,
    ) async {
      useScreenSize(tester, const Size(1400, 1000));
      final monday = thisMonday();

      await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (store) {
          for (var i = 0; i < 3; i++) {
            store.addTask(
              Task(
                title: 'Pazartesi işi $i',
                color: Colors.blue,
                date: monday,
                startHour: 9.0 + i,
              ),
            );
          }
          store.addTask(
            Task(
              title: 'Salı işi',
              color: Colors.blue,
              date: monday.add(const Duration(days: 1)),
              startHour: 10,
            ),
          );
        },
      );

      // Rozetler tipiyle aranıyor: sayaç metni ayın gün sayısıyla aynı
      // rakam olabilir (ayın 3'ü + 3 iş), düz `find.text` ikisini ayıramaz.
      Finder badgeText(String text) => find.descendant(
        of: find.byType(ShadBadge),
        matching: find.text(text),
      );

      // Pazartesi 3, Salı 1. Kalan beş gün boş: rozet hiç çizilmiyor, yani
      // "0" yazan altı rozet ekranı kirletmiyor.
      expect(find.byType(ShadBadge), findsNWidgets(2));
      expect(badgeText('3'), findsOneWidget);
      expect(badgeText('1'), findsOneWidget);
    });

    testWidgets('ekran okuyucu gün, bugün ve iş sayısını tek etikette duyar', (
      tester,
    ) async {
      useScreenSize(tester, const Size(1400, 1000));
      final today = Task.dayKey(DateTime.now());

      await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (store) => store.addTask(
          Task(
            title: 'Bugünün işi',
            color: Colors.blue,
            date: today,
            startHour: 9,
          ),
        ),
      );

      // Sayının kendisi Semantics'ten dışlanıyor; okunması gereken cümle bu.
      const labels = ['PZT', 'SAL', 'ÇAR', 'PER', 'CUM', 'CMT', 'PAZ'];
      final expected = '${labels[today.weekday - 1]} ${today.day}, bugün, 1 iş';
      expect(find.bySemanticsLabel(expected), findsOneWidget);
    });

    testWidgets('390px: rozet düşer, gün sayıları taşmadan durur', (
      tester,
    ) async {
      useScreenSize(tester, const Size(390, 844));
      final monday = thisMonday();

      await pumpApp(
        tester,
        const WeekViewScreen(),
        seed: (store) {
          for (var i = 0; i < 3; i++) {
            store.addTask(
              Task(
                title: 'Pazartesi işi $i',
                color: Colors.blue,
                date: monday,
                startHour: 9.0 + i,
              ),
            );
          }
        },
      );

      // Telefonda bir gün sütunu ~47px. Rozet oraya sığmıyor; sığdırmaya
      // çalışmak gün sayısını kırpardı, o yüzden rozet tamamen düşüyor.
      expect(find.byType(ShadBadge), findsNothing);

      // Yedi günün sayısı da eksiksiz duruyor ve hiçbiri taşmıyor.
      for (var i = 0; i < 7; i++) {
        expect(find.text('${monday.add(Duration(days: i)).day}'), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('gün adı okunabilirliği', () {
    for (final (name, palette, brightness) in [
      ('açık tema', AppPalette.light, Brightness.light),
      ('koyu tema', AppPalette.dark, Brightness.dark),
    ]) {
      testWidgets('$name: PZT etiketi 4.5:1 kontrastı geçer', (tester) async {
        useScreenSize(tester, const Size(1400, 1000));

        await pumpApp(tester, const WeekViewScreen(), brightness: brightness);

        // Bugün vurgulu renk kullanır; ölçmek istediğimiz sessiz hâli. Bu
        // yüzden hedef gün "bugün olmayan" olarak hesaplanıyor — sabit bir
        // etiket seçilseydi test haftada bir gün kendiliğinden düşerdi.
        const weekdays = ['PZT', 'SAL', 'ÇAR', 'PER', 'CUM'];
        final todayIndex = Task.dayKey(DateTime.now()).weekday - 1;
        final label = tester.widget<Text>(
          find.text(weekdays[(todayIndex + 1) % weekdays.length]),
        );
        final color = label.style!.color!;

        // 11px etiket "büyük yazı" değil. Gün adı, hangi sütunun hangi güne
        // ait olduğunu söyleyen tek yazı — dekorasyon sayılamaz. İki zemin de
        // ölçülüyor: açık temada hafta sonu tonu, koyuda düz yüzey daha zorlu.
        for (final bg in [palette.surface, palette.gridWeekend]) {
          expect(
            contrastRatio(color, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$name gün adı okunmuyor',
          );
        }
      });
    }
  });

  group('hafta sonu ayrımı', () {
    // Ayrım yalnız zeminde ve bilinçli olarak hafif (plan §7). Test iki yönü
    // birden kilitliyor: fark görünür kalmalı ama yazıyı okunmaz yapmamalı.
    for (final (name, p) in [
      ('açık tema', AppPalette.light),
      ('koyu tema', AppPalette.dark),
    ]) {
      test('$name: zemin farkı var ama renkle bağırmıyor', () {
        expect(p.gridWeekend, isNot(p.surface));
        expect(contrastRatio(p.gridWeekend, p.surface), lessThan(1.3));
      });

      test('$name: gün sayısı hafta sonu zemininde de 4.5:1 üstünde', () {
        // Gün sayısı hafta sonunda da `ink` ile çiziliyor; soluklaştırma
        // yapılsaydı cumartesi okunmaz olurdu. Kural burada kilitli.
        expect(contrastRatio(p.ink, p.gridWeekend), greaterThan(4.5));
      });
    }
  });
}
