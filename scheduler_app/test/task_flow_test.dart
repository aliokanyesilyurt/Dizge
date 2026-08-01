import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/models/task.dart';
import 'package:scheduler_app/screens/day_view_screen.dart';
import 'package:scheduler_app/screens/monthly_view_screen.dart';

import 'helpers.dart';

void main() {
  setUp(TaskRepository.all.clear);

  Future<void> pumpDay(WidgetTester tester, DateTime date) =>
      pumpApp(tester, DayViewScreen(date: date));

  testWidgets('haftalık rutin ekleme akışı ve tekrar eden günler',
      (tester) async {
    // Sabit bir Pazartesi seç.
    final monday = DateTime(2026, 7, 20);
    expect(monday.weekday, DateTime.monday);

    await pumpDay(tester, monday);
    expect(find.text('Bu gün boş.'), findsOneWidget);

    // Editörü aç.
    await tester.tap(find.text('Yeni iş'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Başlıksız'), 'Koşu');

    // "Tür" satırına dokun -> açılır -> "Rutin" seç.
    await tester.tap(find.text('Tür'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rutin'));
    await tester.pumpAndSettle();

    // Rutin seçilince "Tekrar" satırı kendiliğinden açılır.
    await tester.tap(find.text('Haftanın günleri'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();

    // Pazartesi listesinde, "Rutinler" başlığı altında görünmeli.
    expect(find.text('Koşu'), findsOneWidget);
    expect(find.text('RUTİNLER'), findsOneWidget);
    expect(find.text('BUGÜNE ÖZEL'), findsNothing);

    final task = TaskRepository.all.single;
    expect(task.repeat.type, RepeatType.weekly);
    expect(task.repeat.weekdays, {DateTime.monday});

    // Sonraki Pazartesi'ye düşer, araya gelen Salı'ya düşmez.
    expect(task.occursOn(monday.add(const Duration(days: 7))), isTrue);
    expect(task.occursOn(monday.add(const Duration(days: 1))), isFalse);
    // Başlangıçtan önceki Pazartesi'ye de düşmez.
    expect(task.occursOn(monday.subtract(const Duration(days: 7))), isFalse);
  });

  testWidgets('tek günlük iş sadece kendi gününde görünür ve tamamlanabilir',
      (tester) async {
    final day = DateTime(2026, 7, 20);
    await pumpDay(tester, day);

    await tester.tap(find.text('Yeni iş'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Başlıksız'), 'Fatura öde');

    // Saat + süre: saat satırını aç, 12:00 seç.
    await tester.tap(find.text('Saat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12:00'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();

    expect(find.text('BUGÜNE ÖZEL'), findsOneWidget);
    expect(find.text('RUTİNLER'), findsNothing);
    expect(find.text('12:00'), findsOneWidget); // kartta başlangıç saati
    expect(find.text('1 sa'), findsOneWidget); // varsayılan süre

    final task = TaskRepository.all.single;
    expect(task.isRoutine, isFalse);
    expect(task.startHour, 12.0);
    expect(task.endHour, 13.0);
    expect(task.occursOn(day.add(const Duration(days: 1))), isFalse);

    // Tamamlama kutucuğu gün sayacını ve üstü çizili başlığı günceller.
    expect(find.textContaining('0/1 tamam'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('done-${task.id}')));
    await tester.pumpAndSettle();
    expect(task.isDoneOn(day), isTrue);
    expect(find.textContaining('1/1 tamam'), findsOneWidget);
  });

  testWidgets('telefon genişliğinde tüm özellik satırları taşmadan açılır',
      (tester) async {
    useScreenSize(tester, const Size(390, 844));

    await pumpDay(tester, DateTime(2026, 7, 20));
    await tester.tap(find.text('Yeni iş'));
    await tester.pumpAndSettle();

    // Rutin + haftalık: en kalabalık hâli aç.
    await tester.tap(find.text('Tür'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rutin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Haftanın günleri'));
    await tester.pumpAndSettle();

    // Sırayla her satırı aç; taşma olursa pump sırasında hata fırlar.
    // (Rutinde tarih satırının etiketi "Başlangıç" olur.)
    for (final label in ['Başlangıç', 'Saat', 'Kategori', 'Yer', 'Açıklama']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    // "Süre" satırı ancak saat seçilince görünür.
    await tester.tap(find.text('Saat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('09:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Süre'));
    await tester.pumpAndSettle();

    expect(find.text('1 sa'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aylık ızgarada kalabalık bir gün hücreyi taşırmaz',
      (tester) async {
    useScreenSize(tester, const Size(390, 844));

    final today = DateTime.now();
    await pumpApp(
      tester,
      const MonthlyViewScreen(),
      seed: (store) {
        for (var i = 0; i < 10; i++) {
          store.addTask(Task(
            title: 'Uzunca bir iş başlığı $i',
            color: Colors.blue,
            date: today,
            startHour: 8.0 + i * 0.5,
          ));
        }
      },
    );

    expect(tester.takeException(), isNull);
  });

  test('aylık rutin, kısa aylarda ayın son gününe düşer', () {
    final task = Task(
      title: 'Kira',
      color: Colors.blue,
      date: DateTime(2026, 1, 31),
      repeat: const Repeat(RepeatType.monthly),
    );
    expect(task.occursOn(DateTime(2026, 1, 31)), isTrue);
    expect(task.occursOn(DateTime(2026, 2, 28)), isTrue); // 31 yok -> son gün
    expect(task.occursOn(DateTime(2026, 2, 27)), isFalse);
    expect(task.occursOn(DateTime(2026, 3, 31)), isTrue);
  });

  test('rutini bu günden itibaren bitirmek geçmişi korur', () {
    final start = DateTime(2026, 7, 1);
    final task = Task(
      title: 'Su iç',
      color: Colors.blue,
      date: start,
      repeat: const Repeat(RepeatType.daily),
    );
    TaskRepository.add(task);

    TaskRepository.endRoutineBefore(task, DateTime(2026, 7, 10));
    expect(TaskRepository.all, hasLength(1));
    expect(task.occursOn(DateTime(2026, 7, 9)), isTrue);
    expect(task.occursOn(DateTime(2026, 7, 10)), isFalse);

    // Başlangıç gününde bitirmek işi tamamen kaldırır.
    TaskRepository.endRoutineBefore(task, start);
    expect(TaskRepository.all, isEmpty);
  });
}
