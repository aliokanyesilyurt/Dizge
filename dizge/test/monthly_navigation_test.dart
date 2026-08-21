import 'package:dizge/core/navigation_controller.dart';
import 'package:dizge/models/task.dart';
import 'package:dizge/screens/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Takvim yıl sınırında durmamalı.
///
/// Bildirilen kusur: "aylık geçiş yapmak için üstte buton falan yok, yıllık
/// görünüme dönüp geçiliyor". Kodda iki ayrı sebep vardı:
///
///   1. Ay başlığında ileri/geri düğmesi yoktu — tek yol yatay kaydırmaktı.
///   2. Aylık ekran yılı `DateTime.now().year` diye sabitliyor ve `PageView`
///      12 sayfada bitiyordu. Yani Aralık'tan Ocak'a geçmek **mümkün
///      değildi**; düğme eklemek tek başına yetmezdi.
///
/// Bu testler ikisini birden tutuyor: düğmeler var ve yıl sınırını aşıyorlar.
void main() {
  setUp(TaskRepository.all.clear);

  /// Kenar çubuğunun kalıcı olduğu genişlik; başlık çubuğu da burada tam.
  const wide = Size(1400, 1000);

  final thisYear = DateTime.now().year;

  group('gezinme durumu', () {
    test('openMonth mutlak ayı taşır — yıl artık durumda', () {
      final nav = NavigationController();
      nav.openMonth(DateTime(2027, 1));

      expect(nav.state.section, AppSection.month);
      expect(
        nav.state.anchor,
        DateTime(2027, 1),
        reason: 'ay damgası yılıyla birlikte taşınmalı',
      );
    });

    test('openYear yılı taşır', () {
      final nav = NavigationController();
      nav.openYear(2024);

      expect(nav.state.section, AppSection.year);
      expect(nav.state.anchor, DateTime(2024, 1));
    });
  });

  testWidgets('Aralık → sonraki ay, gelecek yılın Ocak ayını açar', (
    tester,
  ) async {
    useScreenSize(tester, wide);
    final container = await pumpApp(tester, const AppShell());

    container.read(navigationProvider.notifier).openMonth(DateTime(2026, 12));
    await tester.pumpAndSettle();
    expect(find.text('Aralık 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Sonraki ay'));
    await tester.pumpAndSettle();

    // Asıl kusur buydu: 12 sayfalık ızgara burada duvara toslardı.
    expect(find.text('Ocak 2027'), findsOneWidget);
  });

  testWidgets('Ocak → önceki ay, geçen yılın Aralık ayını açar', (
    tester,
  ) async {
    useScreenSize(tester, wide);
    final container = await pumpApp(tester, const AppShell());

    container.read(navigationProvider.notifier).openMonth(DateTime(2026, 1));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Önceki ay'));
    await tester.pumpAndSettle();

    expect(find.text('Aralık 2025'), findsOneWidget);
  });

  testWidgets('bugünün ayı dışındayken "Bugün" geri getirir', (tester) async {
    useScreenSize(tester, wide);
    final container = await pumpApp(tester, const AppShell());
    final notifier = container.read(navigationProvider.notifier);

    // Bulunduğun aydayken dönecek yer yok: düğme de olmamalı.
    notifier.openMonth(DateTime.now());
    await tester.pumpAndSettle();
    expect(find.text('Bugün'), findsNothing);

    notifier.openMonth(DateTime(thisYear + 1, 5));
    await tester.pumpAndSettle();
    expect(find.text('Bugün'), findsOneWidget);

    await tester.tap(find.text('Bugün'));
    await tester.pumpAndSettle();

    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    final now = DateTime.now();
    expect(find.text('${months[now.month - 1]} ${now.year}'), findsOneWidget);
  });

  testWidgets('yıl görünümü önceki/sonraki yıla gidiyor', (tester) async {
    useScreenSize(tester, wide);
    final container = await pumpApp(tester, const AppShell());

    container.read(navigationProvider.notifier).go(AppSection.year);
    await tester.pumpAndSettle();
    expect(find.text('$thisYear'), findsOneWidget);

    await tester.tap(find.byTooltip('Önceki yıl'));
    await tester.pumpAndSettle();
    expect(find.text('${thisYear - 1}'), findsOneWidget);

    await tester.tap(find.byTooltip('Sonraki yıl'));
    await tester.tap(find.byTooltip('Sonraki yıl'));
    await tester.pumpAndSettle();
    expect(find.text('${thisYear + 1}'), findsOneWidget);
  });

  testWidgets('yıl görünümünden aya girmek o yılı taşır', (tester) async {
    useScreenSize(tester, wide);
    final container = await pumpApp(tester, const AppShell());

    container.read(navigationProvider.notifier).go(AppSection.year);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Önceki yıl'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mart'));
    await tester.pumpAndSettle();

    // Eskiden buradan hep içinde bulunulan yılın Mart'ı açılırdı.
    expect(find.text('Mart ${thisYear - 1}'), findsOneWidget);
  });

  testWidgets('aydan 12 aya dönmek bakılan yılı koruyor', (tester) async {
    useScreenSize(tester, wide);
    final container = await pumpApp(tester, const AppShell());

    container
        .read(navigationProvider.notifier)
        .openMonth(DateTime(thisYear + 2, 6));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('12 ay'));
    await tester.pumpAndSettle();

    // Yılı unutmak, kullanıcıyı iki tıkla geri geldiği yere sürükler.
    expect(find.text('${thisYear + 2}'), findsOneWidget);
  });

  testWidgets('kaydırma hâlâ ay değiştiriyor', (tester) async {
    useScreenSize(tester, wide);
    final container = await pumpApp(tester, const AppShell());

    container.read(navigationProvider.notifier).openMonth(DateTime(2026, 3));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.text('Nisan 2026'), findsOneWidget);
  });
}
