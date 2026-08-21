import 'package:dizge/core/navigation_controller.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/screens/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Takvim bölümleri arasında gezinirken **kabuk yerinde kalmalı**.
///
/// Bildirilen kusur: 12 aylık görünümden bir aya girince kenar çubuğu
/// kayboluyordu. Sebebi `Navigator.push` idi — açılan rota kabuğun üstüne
/// biniyordu. Bu testler kenar çubuğunun her geçişte ayakta kaldığını ve
/// üst üste rota yığılmadığını doğruluyor.
void main() {
  setUp(TaskRepository.all.clear);

  /// Kenar çubuğu yalnız geniş ekranda kalıcı; dar ekranda Drawer'a düşüyor.
  const wide = Size(1400, 1000);

  /// Kabuğun çerçevesi ekranda mı? Kenar çubuğundaki bölüm etiketleri
  /// yalnız kalıcı çubukta çizilir.
  Finder sidebar() => find.text('Takvim');

  testWidgets('yıl görünümünden bir aya girmek kenar çubuğunu korur', (
    tester,
  ) async {
    useScreenSize(tester, wide);
    final container = await pumpApp(tester, const AppShell());

    container.read(navigationProvider.notifier).go(AppSection.year);
    await tester.pumpAndSettle();
    expect(sidebar(), findsOneWidget);

    // Mart'a gir (yıl ızgarasındaki mini ay başlığı).
    await tester.tap(find.text('Mart'));
    await tester.pumpAndSettle();

    // Asıl kusur buydu: rota itilince çubuk kayboluyordu.
    expect(sidebar(), findsOneWidget, reason: 'kenar çubuğu kayboldu');

    final nav = container.read(navigationProvider);
    expect(nav.section, AppSection.month);
    expect(
      nav.anchor,
      DateTime(DateTime.now().year, 3),
      reason: 'ay damgası yılıyla birlikte taşınmalı',
    );
  });

  testWidgets('ay → yıl → ay gidip gelmek rota yığmıyor', (tester) async {
    useScreenSize(tester, wide);
    final container = await pumpApp(tester, const AppShell());
    final notifier = container.read(navigationProvider.notifier);

    notifier.go(AppSection.month);
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('12 ay'));
      await tester.pumpAndSettle();
      expect(container.read(navigationProvider).section, AppSection.year);

      await tester.tap(find.text('Mart'));
      await tester.pumpAndSettle();
      expect(container.read(navigationProvider).section, AppSection.month);
    }

    // Önceki hâlinde her gidiş gelişte yığına iki rota ekleniyordu; geri tuşu
    // kimsenin beklemediği bir geçmişte geziniyordu. Artık kök rota tek.
    expect(sidebar(), findsOneWidget);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    expect(navigator.canPop(), isFalse, reason: 'geçişler rota yığmamalı');
  });

  testWidgets('aydan bir güne girmek kenar çubuğunu korur', (tester) async {
    useScreenSize(tester, wide);
    final container = await pumpApp(tester, const AppShell());

    container
        .read(navigationProvider.notifier)
        .openMonth(DateTime(DateTime.now().year, 3));
    await tester.pumpAndSettle();

    // Gün açmak iki aşamalı: ilk dokunuş seçer, ikincisi açar.
    await tester.tap(find.text('15').first);
    await tester.pumpAndSettle();
    expect(
      container.read(navigationProvider).section,
      AppSection.month,
      reason: 'ilk dokunuş yalnız seçmeli',
    );

    await tester.tap(find.text('15').first);
    await tester.pumpAndSettle();

    expect(sidebar(), findsOneWidget);
    final nav = container.read(navigationProvider);
    expect(nav.section, AppSection.hour);
    expect(nav.day!.day, 15);
  });

  testWidgets('kenar çubuğu seçimi ile ekran içi geçiş aynı yere yazar', (
    tester,
  ) async {
    useScreenSize(tester, wide);
    final container = await pumpApp(tester, const AppShell());

    // İki yol da tek bir duruma yazmazsa çubuktaki vurgu ile ekrandaki içerik
    // ayrışır: kullanıcı "Yıllık"ta görünürken ay ekranına bakar.
    await tester.tap(find.text('Yıllık'));
    await tester.pumpAndSettle();
    expect(container.read(navigationProvider).section, AppSection.year);

    await tester.tap(find.text('Mart'));
    await tester.pumpAndSettle();
    expect(container.read(navigationProvider).section, AppSection.month);
  });
}
