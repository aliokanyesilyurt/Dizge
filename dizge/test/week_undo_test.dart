import 'package:dizge/models/task.dart';
import 'package:dizge/screens/week_view_screen.dart';
import 'package:dizge/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// D6'nın sözleşmesi: ızgarada yapılan her yıkıcı hareket geri alınabilir.
///
/// Sürükleyerek taşımak tek bir kazayla bir işi haftanın öbür ucuna atabiliyor
/// ve eski yerini kullanıcı hatırlamak zorunda kalıyordu. Bu testler geri
/// almanın gerçekten eski *değeri* koyduğunu doğruluyor — bildirimin görünmesi
/// yetmez.
void main() {
  setUp(TaskRepository.all.clear);

  DateTime thisMonday() {
    final today = Task.dayKey(DateTime.now());
    return today.subtract(Duration(days: today.weekday - 1));
  }

  /// Ekranı bir işle kurar ve o işi döndürür.
  Future<Task> pumpWithTask(
    WidgetTester tester, {
    required DateTime day,
    double startHour = 9,
  }) async {
    late Task task;
    await pumpApp(
      tester,
      const WeekViewScreen(),
      seed: (store) {
        task = Task(
          title: 'Toplantı',
          color: Colors.blue,
          date: day,
          startHour: startHour,
        );
        store.addTask(task);
      },
    );
    return task;
  }

  /// Bloğa sağ tıklayıp menüyü açar.
  Future<void> openContextMenu(WidgetTester tester) async {
    await tester.tap(find.text('Toplantı'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  testWidgets('sağ tık menüsü üç eylemi de sunar', (tester) async {
    useScreenSize(tester, const Size(1400, 1000));
    await pumpWithTask(tester, day: thisMonday());

    // Menü sağ tıktan önce ağaçta olmamalı; olsaydı aşağıdaki üç beklenti
    // hiçbir şey kanıtlamazdı.
    expect(find.text('Sil'), findsNothing);

    await openContextMenu(tester);

    expect(find.text('Düzenle'), findsOneWidget);
    expect(find.text('Kopyala'), findsOneWidget);
    expect(find.text('Sil'), findsOneWidget);
  });

  testWidgets('silme geri alınır ve iş geri gelir', (tester) async {
    useScreenSize(tester, const Size(1400, 1000));
    final task = await pumpWithTask(tester, day: thisMonday());

    await openContextMenu(tester);
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();

    expect(TaskRepository.all, isEmpty);
    expect(find.text('İş silindi'), findsOneWidget);

    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();

    // Yeni bir kopya değil, aynı görev geri geliyor: kimliği korunmazsa
    // notlar/etiketler başka bir kayda bağlı kalırdı.
    expect(TaskRepository.all, hasLength(1));
    expect(TaskRepository.all.single.id, task.id);
    expect(find.text('Toplantı'), findsOneWidget);
  });

  testWidgets('taşımayı geri almak işi eski gün ve saatine koyar', (
    tester,
  ) async {
    useScreenSize(tester, const Size(1400, 1000));
    final monday = thisMonday();
    final task = await pumpWithTask(tester, day: monday, startHour: 9);

    // Bloğu basılı tutup bir sütun sağa, bir saat aşağı sürükle.
    const columnWidth = (1400 - kTimeGutterWidth) / 7;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Toplantı')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(columnWidth, 60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(task.date, isNot(monday), reason: 'taşıma gerçekleşmeli');

    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();

    expect(task.date, monday);
    expect(task.startHour, 9);
  });

  testWidgets('kopyalama yeni kimlikli bir iş üretir, geçmişini taşımaz', (
    tester,
  ) async {
    useScreenSize(tester, const Size(1400, 1000));
    final monday = thisMonday();
    final task = await pumpWithTask(tester, day: monday);
    task.setDone(monday, true);

    await openContextMenu(tester);
    await tester.tap(find.text('Kopyala'));
    await tester.pumpAndSettle();

    final copy = TaskRepository.all.firstWhere((t) => t.id != task.id);
    expect(copy.title, task.title);
    // Kopya henüz yapılmadı; kaynağın tamamlanma geçmişi ona ait değil.
    expect(copy.isDoneOn(monday), isFalse);
  });
}
