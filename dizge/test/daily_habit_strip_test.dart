import 'package:dizge/data/app_store.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/models/habit.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/screens/week/daily_habit_strip.dart';
import 'package:dizge/screens/week_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Ö3 — ana ekranın günlük tik şeridi.
void main() {
  setUp(TaskRepository.all.clear);

  DateTime today() => Task.dayKey(DateTime.now());

  /// Her gün beklenen alışkanlık. Ritim tek eksen olduğundan (§Zc) bu artık
  /// varsayılan değil, açıkça istenen bir hedef: haftada 7.
  Habit daily(String title) =>
      Habit(title: title, color: const Color(0xFF34E39B), targetPerWeek: 7);

  /// Şeridin *içindeki* yazıyı arar. Çıplak `find.text('1')` gün başlığındaki
  /// ayın 1'ine de takılırdı; test hangi gün koştuğuna göre renk değiştirmemeli.
  Finder inStrip(String text) => find.descendant(
    of: find.byType(DailyHabitStrip),
    matching: find.text(text),
  );

  testWidgets('alışkanlık yokken şerit hiç çizilmez', (tester) async {
    useScreenSize(tester, const Size(1400, 1000));
    await pumpApp(tester, const WeekViewScreen());

    expect(find.text('BUGÜN'), findsNothing);
    expect(find.byType(DailyHabitStrip), findsOneWidget);
    expect(
      tester.getSize(find.byType(DailyHabitStrip)).height,
      0,
      reason: 'boş şerit ana ekranda tek piksel yer kaplamamalı',
    );
  });

  testWidgets('tik atınca gün işaretlenir ve seri rozeti belirir', (
    tester,
  ) async {
    useScreenSize(tester, const Size(1400, 1000));
    final habit = daily('Su iç');

    await pumpApp(
      tester,
      const WeekViewScreen(),
      seed: (store) => store.addHabit(habit),
    );

    expect(find.text('BUGÜN'), findsOneWidget);
    expect(habit.isDoneOn(today()), isFalse);
    expect(inStrip('1'), findsNothing, reason: 'seri yokken rozet de yok');

    await tester.tap(inStrip('Su iç'));
    await tester.pumpAndSettle();

    expect(habit.isDoneOn(today()), isTrue);
    expect(habit.currentStreak, 1);
    expect(inStrip('1'), findsOneWidget);
  });

  testWidgets('ikinci tık tiki geri alır', (tester) async {
    useScreenSize(tester, const Size(1400, 1000));
    final habit = daily('Gitar');

    await pumpApp(
      tester,
      const WeekViewScreen(),
      seed: (store) => store.addHabit(habit),
    );

    await tester.tap(inStrip('Gitar'));
    await tester.pumpAndSettle();
    await tester.tap(inStrip('Gitar'));
    await tester.pumpAndSettle();

    expect(habit.isDoneOn(today()), isFalse);
    expect(inStrip('1'), findsNothing);
  });

  testWidgets('başka bir haftaya geçilse de tik bugüne yazılır', (
    tester,
  ) async {
    // Şerit `PageView`'in dışında duruyor; bu testin kırılması o kararın
    // sessizce bozulduğu anlamına gelir.
    useScreenSize(tester, const Size(1400, 1000));
    final habit = daily('Koşu');

    await pumpApp(
      tester,
      const WeekViewScreen(),
      seed: (store) => store.addHabit(habit),
    );

    await tester.tap(find.byTooltip('Önceki hafta'));
    await tester.pumpAndSettle();
    expect(find.text('BUGÜN'), findsOneWidget, reason: 'şerit yerinde kalmalı');

    await tester.tap(inStrip('Koşu'));
    await tester.pumpAndSettle();

    expect(habit.isDoneOn(today()), isTrue);
    expect(
      habit.isDoneOn(today().subtract(const Duration(days: 7))),
      isFalse,
      reason: 'görünen hafta değil, bugün işaretlenir',
    );
  });

  testWidgets('haftalık ritim seri yerine hedef ilerlemesi gösterir', (
    tester,
  ) async {
    useScreenSize(tester, const Size(1400, 1000));
    final habit = Habit(
      title: 'Spor',
      color: const Color(0xFFA78BFA),
      targetPerWeek: 3,
    );

    await pumpApp(
      tester,
      const WeekViewScreen(),
      seed: (store) => store.addHabit(habit),
    );

    expect(inStrip('0/3'), findsOneWidget);

    await tester.tap(inStrip('Spor'));
    await tester.pumpAndSettle();

    expect(inStrip('1/3'), findsOneWidget);
  });

  testWidgets('ekran okuyucu durumu ve seriyi duyar', (tester) async {
    useScreenSize(tester, const Size(1400, 1000));
    final habit = daily('Kitap');

    await pumpApp(
      tester,
      const WeekViewScreen(),
      seed: (store) => store.addHabit(habit),
    );

    expect(find.bySemanticsLabel('Kitap, bugün yapılmadı'), findsOneWidget);

    await tester.tap(inStrip('Kitap'));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Kitap, bugün yapıldı, 1 günlük seri'),
      findsOneWidget,
    );
  });

  test('şeritten atılan tik diske iner', () async {
    final disk = InMemoryStore();
    await disk.init();

    final a = AppStore();
    await a.attachPersistence(disk);
    final habit = daily('Meditasyon');
    a.addHabit(habit);
    a.toggleHabit(habit, DateTime.now(), source: 'week_strip');
    await a.flush();

    // Yeni oturum: aynı depo, sıfır bellek.
    final b = AppStore();
    await b.attachPersistence(disk);

    expect(b.habits.single.isDoneOn(DateTime.now()), isTrue);
    expect(b.habits.single.currentStreak, 1);
  });
}
