import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/data/app_store.dart';
import 'package:scheduler_app/models/task.dart';
import 'package:scheduler_app/widgets/quick_add_sheet.dart';

import 'helpers.dart';

/// Hızlı ekleme "tek nefeslik" olmalı: başlık yaz, Enter'a bas, iş eklendi.
/// Bu testler o akışın kısa kalmasını koruyor.
void main() {
  setUp(TaskRepository.all.clear);

  final day = DateTime(2026, 7, 20);

  /// Boş bir ekran çizip üzerine hızlı ekleme sayfasını açar.
  Future<ProviderContainer> openSheet(
    WidgetTester tester, {
    double? startHour,
  }) async {
    late BuildContext ctx;
    final container = await pumpApp(
      tester,
      Builder(
        builder: (context) {
          ctx = context;
          return const Scaffold(body: SizedBox.shrink());
        },
      ),
    );
    // Sayfanın kapanmasını beklemiyoruz; testler açıkken etkileşiyor.
    unawaited(showQuickAdd(ctx, date: day, startHour: startHour));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('başlık yazıp Enter demek işi ekler', (tester) async {
    final container = await openSheet(tester, startHour: 14.0);

    await tester.enterText(
      find.widgetWithText(TextField, 'Ne yapacaksın?'),
      'Diş hekimi',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final store = container.read(appStoreProvider);
    expect(store.tasks, hasLength(1));
    final task = store.tasks.single;
    expect(task.title, 'Diş hekimi');
    expect(task.date, day);
    expect(task.startHour, 14.0);
    expect(task.durationHours, 1.0);
    expect(task.isRoutine, isFalse);
  });

  testWidgets('ızgaradan gelen saat rozet olarak görünür', (tester) async {
    await openSheet(tester, startHour: 14.5);
    expect(find.text('14:30'), findsOneWidget);
  });

  testWidgets('saatsiz açılırsa süre rozeti gösterilmez', (tester) async {
    await openSheet(tester);

    expect(find.text('Saatsiz'), findsOneWidget);
    // Süre yalnızca saat seçiliyken anlamlı.
    expect(find.text('1 sa'), findsNothing);
  });

  testWidgets('boş başlıkla Ekle düğmesi pasiftir', (tester) async {
    final container = await openSheet(tester);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Ekle'),
    );
    expect(button.onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Ne yapacaksın?'),
      'Bir şey',
    );
    await tester.pumpAndSettle();

    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Ekle'),
    );
    expect(enabled.onPressed, isNotNull);
    expect(
      container.read(appStoreProvider).tasks,
      isEmpty,
      reason: 'yalnızca yazmak kayıt oluşturmamalı',
    );
  });

  testWidgets('sadece boşluk yazmak iş eklemez', (tester) async {
    final container = await openSheet(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Ne yapacaksın?'),
      '   ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(container.read(appStoreProvider).tasks, isEmpty);
  });

  testWidgets('süre rozetine dokunmak süreyi döngüsel değiştirir', (
    tester,
  ) async {
    await openSheet(tester, startHour: 9.0);

    expect(find.text('1 sa'), findsOneWidget);
    await tester.tap(find.text('1 sa'));
    await tester.pumpAndSettle();
    expect(find.text('1 sa 30 dk'), findsOneWidget);
  });

  testWidgets('Ayrıntılar tam editöre girilenlerle devreder', (tester) async {
    final container = await openSheet(tester, startHour: 9.0);

    await tester.enterText(
      find.widgetWithText(TextField, 'Ne yapacaksın?'),
      'Rapor yaz',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ayrıntılar'));
    await tester.pumpAndSettle();

    // Tam editör açıldı ve başlık taşındı.
    expect(find.text('Tür'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Rapor yaz'), findsOneWidget);
    // Henüz kaydedilmedi: vazgeçilirse ortada yarım iş kalmamalı.
    expect(container.read(appStoreProvider).tasks, isEmpty);
  });
}
