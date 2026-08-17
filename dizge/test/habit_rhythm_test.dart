import 'package:dizge/models/habit.dart';
import 'package:dizge/models/node.dart';
import 'package:dizge/screens/habits_screen.dart';
import 'package:dizge/screens/routines_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Z9 — alışkanlık süreksiz, rutin sürekli (§Zc).
///
/// `HabitCadence` ekseni kalktı: ritmin tamamı `targetPerWeek` (1–7) ve 7
/// "her gün" demek. Bu dosyanın asıl yükü **göç**: eski günlük alışkanlık
/// taşınmalı ve gördüğü sayı değişmemeli.
void main() {
  Habit habit({int target = 3, Set<DateTime>? done}) => Habit(
    title: 'Yürüyüş',
    color: const Color(0xFF38BDF8),
    targetPerWeek: target,
    doneDates: done,
  );

  group('Z9 — ritim tek eksen', () {
    test('7 her gün demek', () {
      expect(habit(target: 7).isEveryDay, isTrue);
      expect(habit(target: 3).isEveryDay, isFalse);
    });

    test('hedef 1–7 arasına sıkışıyor', () {
      // Kayıttan gelen bozuk değer ritmi tanımsız hâle getirmesin.
      final ondan = Habit.fromJson({
        'id': 'h1',
        'title': 'Bozuk',
        'targetPerWeek': 99,
      });
      expect(ondan.targetPerWeek, 7);
    });
  });

  group('Z9 — göç: günlük alışkanlık', () {
    test('eski daily kaydı haftada 7 oluyor', () {
      final migrated = Habit.fromJson({
        'id': 'h1',
        'title': 'Su iç',
        'cadence': 'daily',
        'targetPerWeek': 3, // daily kayıtta bu alan anlamsızdı
      });

      expect(migrated.targetPerWeek, 7);
      expect(migrated.isEveryDay, isTrue);
    });

    test('serisi gün cinsinden kalıyor', () {
      // "Serisi bozulmamış" ölçütü bu: günlük alışkanlık taşındıktan sonra da
      // ardışık **gün** sayıyor, ardışık hafta değil.
      final today = dayOnly(DateTime.now());
      final migrated = Habit.fromJson({
        'id': 'h1',
        'title': 'Su iç',
        'cadence': 'daily',
        'doneDates': [
          dateToKey(today),
          dateToKey(today.subtract(const Duration(days: 1))),
          dateToKey(today.subtract(const Duration(days: 2))),
        ],
      });

      expect(migrated.currentStreak, 3);
    });

    test('haftalık kayıt olduğu gibi kalıyor', () {
      final weekly = Habit.fromJson({
        'id': 'h2',
        'title': 'Koşu',
        'cadence': 'weekly',
        'targetPerWeek': 3,
      });
      expect(weekly.targetPerWeek, 3);
      expect(weekly.isEveryDay, isFalse);
    });
  });

  group('Z9 — ekranlar ayrımı söylüyor', () {
    Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
      useScreenSize(tester, const Size(900, 1400));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(home: screen),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('alışkanlık ekranı süreksizliği ve saatsizliği anlatıyor', (
      tester,
    ) async {
      await pumpScreen(tester, const HabitsScreen());

      expect(find.textContaining('haftada birkaç kez'), findsOneWidget);
      expect(find.textContaining('Rutinler'), findsOneWidget);
    });

    testWidgets('rutin ekranı sürekliliği ve saati anlatıyor', (tester) async {
      await pumpScreen(tester, const RoutinesScreen());

      expect(find.textContaining('Saati belli'), findsOneWidget);
      expect(find.textContaining('Alışkanlıklar'), findsOneWidget);
    });

    testWidgets('alışkanlık düzenleyicisinde saat alanı yok', (tester) async {
      // §Zc'nin en somut ölçütü: alışkanlığın saati yok. Bir gün biri
      // "küçük bir hatırlatma saati" eklemek isterse önce bu test düşer.
      await pumpScreen(tester, const HabitsScreen());
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Yeni alışkanlık'), findsOneWidget);

      // Arama düzenleyicinin içiyle sınırlı: arkadaki boş durum yazısı zaten
      // "saatli iş rutindir" diyor, onu saat alanı sanmayalım.
      Finder inDialog(Finder f) =>
          find.descendant(of: find.byType(AlertDialog), matching: f);
      expect(inDialog(find.byType(TimePickerDialog)), findsNothing);
      expect(inDialog(find.byIcon(Icons.schedule_rounded)), findsNothing);
      expect(inDialog(find.byIcon(Icons.access_time)), findsNothing);
      expect(inDialog(find.textContaining('Saat seç')), findsNothing);
      expect(inDialog(find.textContaining(':00')), findsNothing);
    });

    testWidgets('hedef 7 sayı değil "Her gün" diye okunuyor', (tester) async {
      await pumpScreen(tester, const HabitsScreen());
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('3/hafta'), findsOneWidget);

      await tester.drag(find.byType(Slider), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(find.text('Her gün'), findsOneWidget);
      expect(find.text('7/hafta'), findsNothing);
    });
  });

  group('Z9 — eski istemciyle uyum', () {
    test('cadence yazılmaya devam ediyor', () {
      // Bu sürümü tanımayan bir cihaz alanı bulamazsa varsayılana (her gün)
      // düşer ve haftada 3'lük bir alışkanlık orada günlük görünürdü.
      expect(habit(target: 7).toJson()['cadence'], 'daily');
      expect(habit(target: 3).toJson()['cadence'], 'weekly');
    });

    test('tur kayıpsız', () {
      final back = Habit.fromJson(habit(target: 4).toJson());
      expect(back.targetPerWeek, 4);
    });
  });
}
