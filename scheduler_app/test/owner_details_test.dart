import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduler_app/core/group_context.dart';
import 'package:scheduler_app/core/profile_directory.dart';
import 'package:scheduler_app/data/local_store.dart';
import 'package:scheduler_app/data/persistence_providers.dart';
import 'package:scheduler_app/data/sync/mutation.dart';
import 'package:scheduler_app/data/sync/remote_gateway.dart';
import 'package:scheduler_app/models/group.dart';
import 'package:scheduler_app/models/profile.dart';
import 'package:scheduler_app/widgets/owner_avatar.dart';

/// Y4.4f — **tam ad** detayda.
///
/// Rozet yüzeyde 14 piksellik bir daire; orada "Ali Okan" yazamayız. Önizleme,
/// düzenleyici ve ekran okuyucu ise kısaltmaya mecbur değil.

class _FakeGateway implements RemoteGateway {
  @override
  bool get isConfigured => true;
  @override
  Stream<void> get remoteChanges => const Stream.empty();
  @override
  Future<PushResult> push(List<Mutation> m) async => PushResult.empty;
  @override
  Future<Map<String, dynamic>?> pull({DateTime? since}) async => null;
  @override
  Future<PushResult> pushSnapshot(Map<String, dynamic> s) async =>
      PushResult.empty;
  @override
  Future<List<Group>> fetchGroups() async => const [];
  @override
  Future<List<Profile>> fetchProfiles() async => const [];
  @override
  Future<void> updateDisplayName(String d) async {}
  @override
  Future<Group> createGroup(String name) async => throw UnimplementedError();
  @override
  Future<String> createInvite(String g, {String? email}) async =>
      throw UnimplementedError();
  @override
  Future<String> acceptInvite(String t) async => throw UnimplementedError();
  @override
  Future<void> leaveGroup(String g) async => throw UnimplementedError();
}

const _ali = Profile(userId: 'u-ali', displayName: 'Ali Okan');
const _ekip = Group(id: 'g1', name: 'Ekip');

LocalStore _store({String? groupId}) {
  final store = InMemoryStore();
  store.writeString(kActiveGroupKey, groupId ?? '');
  store.writeString(kGroupsCacheKey, jsonEncode([_ekip.toJson()]));
  store.writeString(kProfilesCacheKey, jsonEncode([_ali.toJson()]));
  return store;
}

Future<void> _pump(WidgetTester tester, Widget child, {String? groupId}) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(_store(groupId: groupId)),
          remoteGatewayProvider.overrideWithValue(_FakeGateway()),
        ],
        child: MaterialApp(home: Scaffold(body: Center(child: child))),
      ),
    );

void main() {
  group('OwnerLine', () {
    testWidgets('grup bağlamında rozet ve tam ad yan yana', (tester) async {
      await _pump(tester, const OwnerLine(ownerId: 'u-ali'), groupId: 'g1');

      expect(find.text('Ali Okan'), findsOneWidget);
      expect(find.text('AO'), findsOneWidget);
    });

    testWidgets('kişisel bağlamda hiç çizilmez', (tester) async {
      await _pump(tester, const OwnerLine(ownerId: 'u-ali'));

      expect(find.text('Ali Okan'), findsNothing);
    });

    testWidgets('tanınmayan sahip için "Bilinmeyen kişi"', (tester) async {
      await _pump(tester, const OwnerLine(ownerId: 'u-yeni'), groupId: 'g1');

      expect(find.text('Bilinmeyen kişi'), findsOneWidget);
    });
  });

  group('ownerNameFor', () {
    testWidgets('kişiselde null, grupta ad verir', (tester) async {
      // Ekran okuyucu cümlesi buradan besleniyor: rozet göze görünüyorsa
      // kulağa da görünmeli, görünmüyorsa cümleye de girmemeli.
      late String? kisisel;
      late String? grupta;

      await _pump(
        tester,
        Consumer(
          builder: (context, ref, _) {
            kisisel = ownerNameFor(ref, 'u-ali');
            return const SizedBox.shrink();
          },
        ),
      );
      await _pump(
        tester,
        Consumer(
          builder: (context, ref, _) {
            grupta = ownerNameFor(ref, 'u-ali');
            return const SizedBox.shrink();
          },
        ),
        groupId: 'g1',
      );

      expect(kisisel, isNull);
      expect(grupta, 'Ali Okan');
    });

    testWidgets('sahibi olmayan satır cümleye ad katmaz', (tester) async {
      late String? ad;
      await _pump(
        tester,
        Consumer(
          builder: (context, ref, _) {
            ad = ownerNameFor(ref, null);
            return const SizedBox.shrink();
          },
        ),
        groupId: 'g1',
      );

      expect(ad, isNull);
    });
  });
}
