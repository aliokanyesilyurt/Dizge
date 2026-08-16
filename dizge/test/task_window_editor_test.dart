import 'dart:async';

import 'package:dizge/models/task.dart';
import 'package:dizge/widgets/task_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Z3 — saat aralığının düzenleyicideki hâli.
///
/// İki iddia: aralık gerçekten kaydediliyor mu, ve kımıldatılamaz işte
/// **görünmüyor** mu (§Zb — orada aralık sormak anlamsız).
void main() {
  setUp(TaskRepository.all.clear);

  final day = DateTime(2026, 8, 17);

  Future<void> openEditor(WidgetTester tester, {Task? existing}) async {
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
    unawaited(showTaskEditor(ctx, date: day, existing: existing));
    await tester.pumpAndSettle();
  }

  /// Sayfa uzun; satır ekran dışındaysa tıklama ıskalıyor. Her dokunuştan
  /// önce hedefi görünür kılıyoruz.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('esnek işte aralık satırı var', (tester) async {
    await openEditor(tester);
    expect(find.text('Saat aralığı'), findsOneWidget);
  });

  testWidgets('kımıldatılamaz işte aralık satırı yok', (tester) async {
    final fixed = Task(
      title: 'Uçuş',
      color: const Color(0xFF5AA9FF),
      date: day,
      startHour: 14,
      isFixed: true,
    );
    await openEditor(tester, existing: fixed);

    expect(find.text('Sabit'), findsOneWidget);
    expect(find.text('Saat aralığı'), findsNothing);
  });

  testWidgets('hazır aralık seçilip kaydediliyor', (tester) async {
    final task = Task(
      title: 'Rapor',
      color: const Color(0xFF5AA9FF),
      date: day,
      startHour: 10,
    );
    TaskRepository.all.add(task);

    await openEditor(tester, existing: task);

    await tapVisible(tester, find.text('Saat aralığı'));
    await tapVisible(tester, find.text('09:00 – 12:00'));
    await tapVisible(tester, find.text('Kaydet'));

    expect(task.windowStart, 9);
    expect(task.windowEnd, 12);
  });

  testWidgets('kımıldatılamaz yapılan iş penceresini bırakıyor', (
    tester,
  ) async {
    // Satır gizliyken arkada duran bir aralık, kullanıcının göremediği bir
    // kısıt olurdu: "Günü kurtar" işi taşımaz ve sebebi ekranda hiç yazmaz.
    final task = Task(
      title: 'Rapor',
      color: const Color(0xFF5AA9FF),
      date: day,
      startHour: 10,
      windowStart: 9,
      windowEnd: 12,
    );
    TaskRepository.all.add(task);

    await openEditor(tester, existing: task);

    await tapVisible(tester, find.text('Sabit'));
    await tapVisible(tester, find.byType(Switch));
    await tapVisible(tester, find.text('Kaydet'));

    expect(task.isFixed, isTrue);
    expect(task.windowStart, isNull);
    expect(task.windowEnd, isNull);
  });
}
