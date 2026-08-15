import 'package:dizge/core/handwriting_recognizer.dart';
import 'package:dizge/core/ink_lines.dart';
import 'package:dizge/data/app_store.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/screens/agenda_screen.dart';
import 'package:dizge/widgets/ink_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// A5 + A8 — tanıma arayüzü ve onay şeridi.
///
/// Buradaki testlerin çoğu tek bir sözü koruyor: **tanıma asla sessizce görev
/// oluşturmaz ve mürekkep her hâlükârda kalır.**
void main() {
  // Görevlerin tek gerçek kaynağı hâlâ statik `TaskRepository`; testler
  // arasında sızmasın diye deponun yerleşik kalıbı burada da uygulanıyor.
  setUp(TaskRepository.all.clear);

  /// Verilen metinleri sırayla döndüren sahte motor.
  ///
  /// A6/A7 gerçek motorları getirdiğinde bu sınıf değişmeyecek: arayüzün
  /// varlık sebebi tam olarak bu — uygulamanın geri kalanı hangi motorun
  /// konuştuğunu bilmiyor.
  final fake = _FakeRecognizer(['Süt al', 'Rapor yaz']);

  /// Tuvale üst üste iki satır çizer.
  Future<void> writeTwoLines(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(InkCanvas));

    for (final dy in [-40.0, 40.0]) {
      final gesture = await tester.startGesture(center + Offset(-60, dy));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.moveBy(const Offset(40, 2));
      await gesture.up();
      await tester.pumpAndSettle();
    }
  }

  group('UnavailableRecognizer', () {
    test('her satır için boş dize döndürür, satırı düşürmez', () async {
      // Uzunluk sözü: öneriler yazının hizasından kaymasın diye okunamayan
      // satır listeden düşmez.
      const recognizer = UnavailableRecognizer();
      final lines = [
        for (var i = 0; i < 3; i++)
          InkLine(const [], Rect.fromLTWH(0, i * 20, 10, 10)),
      ];

      expect(recognizer.isAvailable, isFalse);
      expect(await recognizer.recognizeLines(lines), ['', '', '']);
    });
  });

  group('onay şeridi', () {
    testWidgets('tanıma kapalıyken satırlar yine listelenir', (tester) async {
      await pumpApp(tester, const AgendaScreen());
      await writeTwoLines(tester);

      await tester.tap(find.text('Görevlere çevir'));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 satır bulundu'), findsOneWidget);
      expect(find.textContaining('Tanıma bu cihazda kapalı'), findsOneWidget);
      // Başlıklar boş geldiği için düğme pasif: boş başlıklı görev üretilmez.
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });

    testWidgets('tanınan metin öneri olarak gelir ve göreve çevrilir', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        const AgendaScreen(),
        overrides: [handwritingRecognizerProvider.overrideWithValue(fake)],
      );
      await writeTwoLines(tester);

      await tester.tap(find.text('Görevlere çevir'));
      await tester.pumpAndSettle();

      expect(find.text('Süt al'), findsOneWidget);
      expect(find.text('Rapor yaz'), findsOneWidget);

      await tester.tap(find.text('2 görev oluştur'));
      await tester.pumpAndSettle();

      final titles = container
          .read(appStoreProvider)
          .tasks
          .map((t) => t.title)
          .toList();
      expect(titles, containsAll(['Süt al', 'Rapor yaz']));
    });

    testWidgets('görevler oluştuktan sonra mürekkep sayfada kalır', (
      tester,
    ) async {
      // Planın §Ab sözü. Ajanda önce bir defterdir.
      final container = await pumpApp(
        tester,
        const AgendaScreen(),
        overrides: [handwritingRecognizerProvider.overrideWithValue(fake)],
      );
      await writeTwoLines(tester);

      final before = container
          .read(appStoreProvider)
          .agendaPage(DateTime.now())
          .strokes
          .length;

      await tester.tap(find.text('Görevlere çevir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 görev oluştur'));
      await tester.pumpAndSettle();

      expect(
        container.read(appStoreProvider).agendaPage(DateTime.now()).strokes,
        hasLength(before),
      );
    });

    testWidgets('kapatılan satır göreve çevrilmez', (tester) async {
      final container = await pumpApp(
        tester,
        const AgendaScreen(),
        overrides: [handwritingRecognizerProvider.overrideWithValue(fake)],
      );
      await writeTwoLines(tester);

      await tester.tap(find.text('Görevlere çevir'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('1 görev oluştur'));
      await tester.pumpAndSettle();

      final titles = container
          .read(appStoreProvider)
          .tasks
          .map((t) => t.title)
          .toList();
      expect(titles, ['Rapor yaz']);
    });

    testWidgets('vazgeçince hiçbir görev oluşmaz', (tester) async {
      final container = await pumpApp(
        tester,
        const AgendaScreen(),
        overrides: [handwritingRecognizerProvider.overrideWithValue(fake)],
      );
      await writeTwoLines(tester);

      await tester.tap(find.text('Görevlere çevir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      expect(container.read(appStoreProvider).tasks, isEmpty);
    });
  });
}

class _FakeRecognizer implements HandwritingRecognizer {
  _FakeRecognizer(this.texts);

  final List<String> texts;

  @override
  RecognizerState get state => RecognizerState.ready;

  @override
  Future<void> warmUp() async {}

  @override
  Future<List<String>> recognizeLines(List<InkLine> lines) async => [
    for (var i = 0; i < lines.length; i++) i < texts.length ? texts[i] : '',
  ];
}
