import 'dart:async';

import 'package:dizge/models/task.dart';
import 'package:dizge/widgets/editor/place_field.dart';
import 'package:dizge/widgets/task_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// D5 — "yazınca konum çıksın".
///
/// İki katman ayrı sınanıyor: sıralama/eşleme saf fonksiyonda, dokunuşun
/// alanı doldurması editörde.
void main() {
  group('placeSuggestions', () {
    test('sık kullanılan önce gelir', () {
      final picks = placeSuggestions([
        'Ofis',
        'Ev',
        'Ofis',
        'Spor salonu',
        'Ofis',
        'Ev',
      ], '');

      expect(picks, ['Ofis', 'Ev', 'Spor salonu']);
    });

    test('boş ve yalnız boşluktan ibaret yerler sayılmaz', () {
      expect(placeSuggestions(['', '   ', 'Ev'], ''), ['Ev']);
    });

    test('yazdıkça daralır, baştan eşleşen öne geçer', () {
      final picks = placeSuggestions(['Yeni ofis', 'Ofis', 'Ofis', 'Ev'], 'of');

      // İlk ölçüt ön ek: "of" yazan "Ofis"i arıyor, "Yeni ofis"i değil.
      // Sıklık ancak eşit ön ek durumunda konuşuyor.
      expect(picks, ['Ofis', 'Yeni ofis']);
    });

    test('Türkçe harf farkı eşlemeyi bozmaz', () {
      expect(placeSuggestions(['İstanbul'], 'istan'), ['İstanbul']);
      expect(placeSuggestions(['Şişli'], 'sisli'), ['Şişli']);
      // Yazım farklıysa öneri duruyor: dokunmak yazılanı düzeltiyor.
      expect(placeSuggestions(['ofis'], 'OFİS'), ['ofis']);
      expect(placeSuggestions(['ofis'], 'ofis'), isEmpty); // birebir aynı
    });

    test('aynı yerin iki yazımı tek öneri olur', () {
      // "ev" ve "Ev" iki ayrı çip olarak çıksaydı, liste kullanıcının kendi
      // tutarsızlığını yüzüne çarpardı.
      final picks = placeSuggestions(['Ev', 'ev', 'EV'], '');

      expect(picks, ['Ev']);
    });

    test('birebir yazılmış olan önerilmez', () {
      expect(placeSuggestions(['Ev', 'Evim'], 'Ev'), ['Evim']);
    });

    test('liste sınırı aşılmaz', () {
      final history = [for (var i = 0; i < 20; i++) 'Yer $i'];

      expect(placeSuggestions(history, '', limit: 4), hasLength(4));
    });

    test('geçmiş boşken öneri yok', () {
      expect(placeSuggestions(const [], ''), isEmpty);
      expect(placeSuggestions(const [], 'ev'), isEmpty);
    });
  });

  group('editörde', () {
    setUp(TaskRepository.all.clear);

    final day = DateTime(2026, 8, 21);

    Task seed(String place) => Task(
      title: 'İş $place',
      color: const Color(0xFF5AA9FF),
      date: day,
      place: place,
    );

    Future<void> openEditor(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late BuildContext ctx;
      await pumpApp(
        tester,
        Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      );
      unawaited(showTaskEditor(ctx, date: day));
      await tester.pumpAndSettle();
    }

    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('yer satırı açılınca geçmiş öneri olarak duruyor', (
      tester,
    ) async {
      TaskRepository.all.addAll([seed('Ofis'), seed('Ev'), seed('Ofis')]);

      await openEditor(tester);
      await tapVisible(tester, find.text('Yer'));

      expect(find.text('Daha önce yazdıkların'), findsOneWidget);
      expect(find.text('Ofis'), findsOneWidget);
      expect(find.text('Ev'), findsOneWidget);
    });

    testWidgets('yazınca liste daralıyor', (tester) async {
      TaskRepository.all.addAll([seed('Ofis'), seed('Ev')]);

      await openEditor(tester);
      await tapVisible(tester, find.text('Yer'));
      await tester.enterText(find.byType(TextField).last, 'of');
      await tester.pumpAndSettle();

      expect(find.text('Ofis'), findsOneWidget);
      expect(find.text('Ev'), findsNothing);
      // Kaynağı yazan etiket yalnız hiç yazılmamışken görünür.
      expect(find.text('Daha önce yazdıkların'), findsNothing);
    });

    testWidgets('çipe dokunmak alanı dolduruyor ve iş öyle kaydediliyor', (
      tester,
    ) async {
      TaskRepository.all.add(seed('Spor salonu'));

      await openEditor(tester);
      await tester.enterText(find.byType(TextField).first, 'Antrenman');
      await tapVisible(tester, find.text('Yer'));
      await tapVisible(tester, find.text('Spor salonu'));

      // Satır özeti de tazelenmeli: kapanınca "Boş" yazıyor olamaz.
      expect(find.text('Spor salonu'), findsWidgets);

      await tapVisible(tester, find.text('Ekle'));

      final saved = TaskRepository.all.firstWhere(
        (t) => t.title == 'Antrenman',
      );
      expect(saved.place, 'Spor salonu');
    });

    testWidgets('geçmiş boşken çip alanı hiç çizilmiyor', (tester) async {
      await openEditor(tester);
      await tapVisible(tester, find.text('Yer'));

      expect(find.text('Daha önce yazdıkların'), findsNothing);
    });
  });
}
