import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/data/app_store.dart';
import 'package:scheduler_app/data/local_store.dart';
import 'package:scheduler_app/models/task.dart';
import 'package:scheduler_app/screens/day_view_screen.dart';
import 'package:scheduler_app/widgets/task_editor_sheet.dart';

import 'helpers.dart';

/// Ö4a — enerji (efor) modeli.
void main() {
  setUp(TaskRepository.all.clear);

  Task sample({Energy? energy}) => Task(
    title: 'Refactor',
    color: const Color(0xFF4FC3F7),
    date: DateTime(2026, 8, 4),
    energy: energy,
  );

  group('model', () {
    test('varsayılan belirtilmemiş', () {
      expect(sample().energy, isNull);
    });

    test('JSON gidiş-dönüşü kademeyi korur', () {
      for (final level in Energy.values) {
        final clone = Task.fromJson(sample(energy: level).toJson());
        expect(clone.energy, level);
      }
    });

    test('efor alanı olmayan eski kayıt açılır ve boş kalır', () {
      // Ö4a öncesi yazılmış bir kayıt: 'energy' anahtarı hiç yok.
      final old = sample().toJson()..remove('energy');
      final task = Task.fromJson(old);

      expect(task.energy, isNull);
      expect(task.title, 'Refactor', reason: 'kalan alanlar bozulmamalı');
    });

    test('tanınmayan kademe veriyi düşürmez, boşa iner', () {
      // Başka bir sürümde eklenmiş bir kademe geri okunduğunda kayıt açılmalı.
      final j = sample().toJson()..['energy'] = 'kozmik';
      expect(Task.fromJson(j).energy, isNull);
    });

    test('kopyalar eforu taşır', () {
      final task = sample(energy: Energy.low);
      expect(task.copy().energy, Energy.low);
      expect(task.duplicateTo(DateTime(2026, 8, 9)).energy, Energy.low);
    });

    test('dört kademe var ve etiketleri Türkçe', () {
      // Kademe sayısı bir tasarım kararı (bkz. plan K5); sessizce değişmesin.
      expect(Energy.values, hasLength(4));
      expect(Energy.high.label, 'Yüksek efor');
      expect(Energy.discharge.label, 'Deşarj');
    });
  });

  group('düzenleyici', () {
    testWidgets('seçilen efor işe yazılır', (tester) async {
      final day = DateTime(2026, 7, 20);
      await pumpApp(tester, DayViewScreen(date: day));

      await tester.tap(find.text('Yeni iş'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Başlıksız'),
        'Tez yaz',
      );

      expect(find.text('Belirtilmemiş'), findsOneWidget);

      await tester.tap(find.text('Efor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yüksek efor'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ekle'));
      await tester.pumpAndSettle();

      expect(TaskRepository.all.single.energy, Energy.high);
    });

    testWidgets('seçili kademeye tekrar dokunmak seçimi kaldırır', (
      tester,
    ) async {
      final day = DateTime(2026, 7, 20);
      await pumpApp(tester, DayViewScreen(date: day));

      await tester.tap(find.text('Yeni iş'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Başlıksız'),
        'Bulaşık',
      );

      await tester.tap(find.text('Efor'));
      await tester.pumpAndSettle();
      // Seçildikten sonra aynı yazı hem satırın değerinde hem çipte duruyor;
      // `.last` her zaman çip (satır değeri ağaçta önce geliyor).
      await tester.tap(find.text('Düşük efor').last);
      await tester.pumpAndSettle();
      // Yanlışlıkla işaretlenen bir iş "belirtilmemiş"e dönebilmeli.
      await tester.tap(find.text('Düşük efor').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ekle'));
      await tester.pumpAndSettle();

      expect(TaskRepository.all.single.energy, isNull);
    });

    testWidgets('var olan işin eforu satırda görünür', (tester) async {
      final day = DateTime(2026, 7, 20);
      final task = Task(
        title: 'Sunum',
        color: const Color(0xFF4FC3F7),
        date: day,
        energy: Energy.medium,
      );

      // Düzenleyici doğrudan kuruluyor: burada sınanan şey kaydın efor
      // alanının satıra yansıması, oraya hangi ekrandan gelindiği değil.
      await pumpApp(
        tester,
        Scaffold(
          body: TaskEditorSheet(date: day, existing: task),
        ),
      );

      expect(find.text('Orta efor'), findsOneWidget);
    });
  });

  test('seçim diske iner ve yeni oturumda geri okunur', () async {
    final disk = InMemoryStore();
    await disk.init();

    final a = AppStore();
    await a.attachPersistence(disk);
    a.addTask(sample(energy: Energy.discharge));
    await a.flush();

    TaskRepository.all.clear();
    final b = AppStore();
    await b.attachPersistence(disk);

    expect(b.tasks.single.energy, Energy.discharge);
  });
}
