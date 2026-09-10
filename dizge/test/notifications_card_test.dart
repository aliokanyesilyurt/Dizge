import 'package:dizge/core/reminders.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/data/persistence_providers.dart';
import 'package:dizge/screens/account/notifications_section.dart';
import 'package:dizge/screens/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// N3 — Hesap ekranında bildirimler gerçek bir ayar.
void main() {
  testWidgets('eski "backend eklendiğinde" uyarısı yok, kart var', (
    tester,
  ) async {
    useScreenSize(tester, const Size(900, 2400));
    await pumpApp(tester, const AccountScreen());

    expect(find.textContaining('backend'), findsNothing);
    expect(find.byType(NotificationsCard), findsOneWidget);
  });

  testWidgets('önceden-süre seçimi diske yazılır', (tester) async {
    final disk = InMemoryStore();
    final container = await pumpApp(
      tester,
      const Scaffold(body: NotificationsCard()),
      overrides: [localStoreProvider.overrideWithValue(disk)],
    );

    await tester.tap(find.text('30 dk önce'));
    await tester.pumpAndSettle();

    expect(container.read(reminderSettingsProvider).leadMinutes, 30);
    expect(disk.readString(kReminderSettingsKey), contains('"leadMinutes":30'));
  });

  testWidgets('kapatılınca ayrıntılar gizlenir', (tester) async {
    final container = await pumpApp(
      tester,
      const Scaffold(body: NotificationsCard()),
    );

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(container.read(reminderSettingsProvider).enabled, isFalse);
    expect(find.text('Deneme bildirimi gönder'), findsNothing);
  });

  testWidgets('deneme düğmesi kapıdan hemen bir bildirim gönderir', (
    tester,
  ) async {
    final gateway = NoopReminderGateway();
    await pumpApp(
      tester,
      const Scaffold(body: NotificationsCard()),
      overrides: [reminderGatewayProvider.overrideWithValue(gateway)],
    );

    await tester.tap(find.text('Deneme bildirimi gönder'));
    await tester.pumpAndSettle();

    expect(gateway.shown, ['Dizge']);
  });

  testWidgets('izin kapalıysa sebebi ve düzeltme yolu görünür', (tester) async {
    final gateway = NoopReminderGateway()..current = ReminderPermission.denied;
    await pumpApp(
      tester,
      const Scaffold(body: NotificationsCard()),
      overrides: [reminderGatewayProvider.overrideWithValue(gateway)],
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('izni kapalı'), findsOneWidget);
    expect(find.text('İzin ver'), findsOneWidget);
  });
}
