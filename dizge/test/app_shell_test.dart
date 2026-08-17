import 'package:dizge/models/task.dart';
import 'package:dizge/screens/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUp(TaskRepository.all.clear);

  /// Kenar çubuğunun kalıcı durduğu genişlikte kabuk.
  Future<void> pumpWideShell(WidgetTester tester) async {
    useScreenSize(tester, const Size(1400, 900));
    await pumpApp(tester, const AppShell());
  }

  testWidgets('kenar çubuğu daralıp genişlerken ara karelerde taşma olmaz', (
    tester,
  ) async {
    await pumpWideShell(tester);

    // Daralt: genişlik 248 -> 68 animasyonu boyunca içerik taşmamalı.
    await tester.tap(find.byTooltip('Menüyü daralt'));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 55));
    }
    await tester.pumpAndSettle();

    // Daralmışken etiketler gizli, ikonlar durur.
    expect(find.text('Yıllık'), findsNothing);
    expect(find.text('Takvim'), findsNothing);

    // Genişlet: 68 -> 248 animasyonu boyunca da taşma olmamalı.
    await tester.tap(find.byTooltip('Menüyü genişlet'));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 55));
    }
    await tester.pumpAndSettle();

    expect(find.text('Yıllık'), findsOneWidget);
  });

  testWidgets('kenar çubuğundan bölüm değiştirilebilir', (tester) async {
    await pumpWideShell(tester);

    await tester.tap(find.text('Rutinler'));
    await tester.pumpAndSettle();
    // Metnin tamamı değil ayrımı taşıyan cümlesi aranıyor: boş durum
    // yazısı ayarlanabilir, ekranın hangisi olduğu değil.
    expect(find.textContaining('Henüz rutin yok.'), findsOneWidget);

    await tester.tap(find.text('Yapılacaklar'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Yapılacak iş yok.\nTek günlük bir iş ekleyince burada görünür.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('açılış bölümü haftalık ızgaradır', (tester) async {
    await pumpWideShell(tester);

    // Haftalık görünüm "Bu hafta" alt başlığı ve saat sütunuyla gelir.
    expect(find.textContaining('Bu hafta', findRichText: true), findsOneWidget);
    expect(find.text('09:00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
