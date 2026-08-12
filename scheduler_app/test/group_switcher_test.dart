import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/group_context.dart';
import 'package:scheduler_app/data/local_store.dart';
import 'package:scheduler_app/data/persistence_providers.dart';
import 'package:scheduler_app/models/group.dart';
import 'package:scheduler_app/widgets/group_switcher.dart';

import 'helpers.dart';

/// Y4.2 — kenar çubuğundaki bağlam seçici.
///
/// Sorulan tek soru: **kullanıcı hangi bağlamda olduğunu ekrana bakarak
/// anlayabiliyor mu?** Seçici yanlış yerde susarsa, süzülen işler "kayboldu"
/// görünür.

/// Grup listesi önbellekte hazır bir depo — seçici ağa çıkmadan da dolu gelir.
LocalStore _storeWith(List<Group> groups, {String? active}) {
  final store = InMemoryStore();
  store.writeString(
    kGroupsCacheKey,
    jsonEncode([for (final g in groups) g.toJson()]),
  );
  if (active != null) store.writeString(kActiveGroupKey, active);
  return store;
}

const _ekip = Group(id: 'g1', name: 'Ekip');
const _ev = Group(id: 'g2', name: 'Ev');

void main() {
  testWidgets('grubu olmayan kullanıcıda seçici hiç görünmez', (tester) async {
    await pumpApp(
      tester,
      const Scaffold(body: GroupSwitcher(collapsed: false)),
      overrides: [localStoreProvider.overrideWithValue(InMemoryStore())],
    );

    expect(find.text('Kişisel'), findsNothing);
  });

  testWidgets('grup varken seçici bulunulan bağlamı yazar', (tester) async {
    await pumpApp(
      tester,
      const Scaffold(body: GroupSwitcher(collapsed: false)),
      overrides: [
        localStoreProvider.overrideWithValue(_storeWith([_ekip, _ev])),
      ],
    );

    expect(find.text('Kişisel'), findsOneWidget);
  });

  testWidgets('kayıtlı grup bağlamı açılışta adıyla görünür', (tester) async {
    await pumpApp(
      tester,
      const Scaffold(body: GroupSwitcher(collapsed: false)),
      overrides: [
        localStoreProvider.overrideWithValue(
          _storeWith([_ekip, _ev], active: 'g1'),
        ),
      ],
    );

    expect(find.text('Ekip'), findsOneWidget);
  });

  testWidgets('menüden seçmek bağlamı değiştirir', (tester) async {
    final container = await pumpApp(
      tester,
      const Scaffold(body: GroupSwitcher(collapsed: false)),
      overrides: [
        localStoreProvider.overrideWithValue(_storeWith([_ekip, _ev])),
      ],
    );

    await tester.tap(find.byType(GroupSwitcher));
    await tester.pumpAndSettle();

    // Menüde "Kişisel" iki kez görünür: düğmenin üstünde ve listede.
    expect(find.text('Ev'), findsOneWidget);
    await tester.tap(find.text('Ev'));
    await tester.pumpAndSettle();

    expect(container.read(activeGroupIdProvider), 'g2');
    expect(find.text('Ev'), findsOneWidget);
  });

  testWidgets('Kişisel e dönüş menüden yapılabilir', (tester) async {
    final container = await pumpApp(
      tester,
      const Scaffold(body: GroupSwitcher(collapsed: false)),
      overrides: [
        localStoreProvider.overrideWithValue(_storeWith([_ekip], active: 'g1')),
      ],
    );

    await tester.tap(find.byType(GroupSwitcher));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kişisel'));
    await tester.pumpAndSettle();

    expect(container.read(activeGroupIdProvider), isNull);
    expect(find.text('Kişisel'), findsOneWidget);
  });
}
