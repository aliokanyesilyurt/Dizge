import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/models/task.dart';
import 'package:scheduler_app/screens/week_view_screen.dart';

import 'helpers.dart';

/// D7'nin erişilebilirlik kontrol listesi.
///
/// Ana ekran fare üzerine kuruluydu: bloklara klavyeyle hiç ulaşılamıyordu ve
/// ekran okuyucu blok içindeki parçaları bağlamsız okuyordu. Bu testler o iki
/// açığın kapalı kaldığını garanti ediyor.
void main() {
  setUp(TaskRepository.all.clear);

  DateTime thisMonday() {
    final today = Task.dayKey(DateTime.now());
    return today.subtract(Duration(days: today.weekday - 1));
  }

  /// Bloğun klavye odağı düğümü.
  ///
  /// `Focus.of(context)` yeterli değil: blok `ShadPopover` / `ShadTooltip`
  /// içinde duruyor ve bunların kendi odak düğümleri araya girebiliyor.
  /// Anahtarla aramak, testin gerçekten *bloğun* düğümünü tuttuğunu garanti eder.
  FocusNode blockFocus(WidgetTester tester, Task task) =>
      tester.widget<Focus>(find.byKey(ValueKey('focus-${task.id}'))).focusNode!;

  Future<Task> pumpWithTask(WidgetTester tester, {bool done = false}) async {
    final monday = thisMonday();
    late Task task;
    await pumpApp(
      tester,
      const WeekViewScreen(),
      seed: (store) {
        task = Task(
          title: 'Toplantı',
          color: Colors.blue,
          date: monday,
          startHour: 14,
          durationHours: 1.5,
        );
        if (done) task.setDone(monday, true);
        store.addTask(task);
      },
    );
    return task;
  }

  group('ekran okuyucu', () {
    testWidgets('blok tek bir cümle olarak duyulur', (tester) async {
      useScreenSize(tester, const Size(1400, 1000));
      await pumpWithTask(tester);

      // Parçalı okuma ("Toplantı" … "14:00 – 15:30" … ikon) bağlam vermiyordu.
      expect(
        find.bySemanticsLabel('Toplantı, Pazartesi 14:00 – 15:30'),
        findsOneWidget,
      );
    });

    testWidgets('tamamlanma durumu da cümleye giriyor', (tester) async {
      useScreenSize(tester, const Size(1400, 1000));
      await pumpWithTask(tester, done: true);

      // Üstü çizili yazı ve ✓ ikonu ekran okuyucuya hiçbir şey söylemez.
      expect(
        find.bySemanticsLabel('Toplantı, Pazartesi 14:00 – 15:30, tamamlandı'),
        findsOneWidget,
      );
    });
  });

  group('klavye', () {
    testWidgets('odaklı blokta Enter düzenleyiciyi açar', (tester) async {
      useScreenSize(tester, const Size(1400, 1000));
      final task = await pumpWithTask(tester);

      // Fare olmadan bloğa erişmenin hiçbir yolu yoktu.
      final node = blockFocus(tester, task);
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue);

      // Izgarada metin alanı yok; biri belirdiyse düzenleyici açılmıştır.
      expect(find.byType(TextField), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('odaklı blokta Delete işi siler ve geri alınabilir', (
      tester,
    ) async {
      useScreenSize(tester, const Size(1400, 1000));
      final task = await pumpWithTask(tester);

      blockFocus(tester, task).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(TaskRepository.all, isEmpty);
      // Klavyeyle silmek de fare ile silmekle aynı ağa düşer.
      expect(find.text('Geri al'), findsOneWidget);
    });

    testWidgets('sol/sağ ok haftayı değiştirir', (tester) async {
      useScreenSize(tester, const Size(1400, 1000));
      await pumpApp(tester, const WeekViewScreen());

      expect(
        find.textContaining('Bu hafta', findRichText: true),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Gelecek hafta', findRichText: true),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Bu hafta', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('boş hafta', () {
    testWidgets('bilgi başlıkta duruyor, ızgaranın ortasında değil', (
      tester,
    ) async {
      useScreenSize(tester, const Size(1400, 1000));

      await pumpApp(tester, const WeekViewScreen());

      // Boş ızgara tek başına "veri mi kayboldu, hafta mı boş" sorusunu
      // cevaplamıyor; cevap veriliyor ama bir uyarı gibi değil. Plan
      // yapılmamış bir hafta hata değil (T2), o yüzden ekranın ortasında
      // yüzen bir kart yerine bağlam satırının devamı.
      expect(
        find.textContaining('hiç iş yok', findRichText: true),
        findsOneWidget,
      );

      await pumpWithTask(tester);
      expect(
        find.textContaining('hiç iş yok', findRichText: true),
        findsNothing,
      );
    });
  });

  group('font paketi', () {
    test('kullanılmayan yazı tipleri paketlenmiyor', () {
      // Kaldırıldıklarını burada kilitliyoruz: `pubspec.yaml`'a geri sızarlarsa
      // kimse fark etmeden her kuruluma ~283 KB ölü yük döner.
      final pubspec = File('pubspec.yaml').readAsStringSync();

      for (final family in ['PatrickHand', 'PermanentMarker']) {
        expect(
          pubspec,
          isNot(contains('- family: $family')),
          reason: '$family yeniden paketlenmiş',
        );
        expect(
          File('assets/fonts/$family-Regular.ttf').existsSync(),
          isFalse,
          reason: '$family dosyası geri gelmiş',
        );
      }
    });
  });
}
