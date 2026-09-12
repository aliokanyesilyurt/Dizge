import 'dart:convert';

import 'package:dizge/core/group_context.dart';
import 'package:dizge/core/profile_directory.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/data/persistence_providers.dart';
import 'package:dizge/data/sync/mutation.dart';
import 'package:dizge/data/sync/remote_gateway.dart';
import 'package:dizge/models/group.dart';
import 'package:dizge/models/profile.dart';
import 'package:dizge/widgets/owner_avatar.dart';
import 'package:dizge/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Y4.4d — rozetin **ne zaman** görüneceği.
///
/// Kararın tamamı [OwnerAvatar]'da duruyor; her yüzeyin ayrı ayrı "grupta
/// mıyım" diye sorması, dört ekranda dört kez unutulabilecek bir kural olurdu.
/// Bu dosya o tek kararı sınıyor.

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
  Future<void> updateAvatarColor(int color) async {}
  @override
  Future<Group> createGroup(
    String name, {
    String? description,
    int? colorIndex,
  }) async => throw UnimplementedError();

  @override
  Future<void> updateGroup(Group group) async => throw UnimplementedError();

  @override
  Future<List<GroupMember>> fetchGroupMembers(String groupId) async => const [];

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

/// Depoyu istenen bağlamla kurar: `groupId` null ise Kişisel.
LocalStore _store({String? groupId}) {
  final store = InMemoryStore();
  store.writeString(kActiveGroupKey, groupId ?? '');
  store.writeString(kGroupsCacheKey, jsonEncode([_ekip.toJson()]));
  store.writeString(kProfilesCacheKey, jsonEncode([_ali.toJson()]));
  return store;
}

Future<void> _pump(
  WidgetTester tester, {
  String? groupId,
  String? ownerId = 'u-ali',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(_store(groupId: groupId)),
        remoteGatewayProvider.overrideWithValue(_FakeGateway()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: OwnerAvatar(ownerId: ownerId)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('kişisel bağlamda rozet çizilmez', (tester) async {
    // Orada zaten her satır senin; avatar yalnız gürültü olurdu.
    await _pump(tester);

    expect(find.byType(UserAvatar), findsNothing);
  });

  testWidgets('grup bağlamında rozet görünür ve adı taşır', (tester) async {
    await _pump(tester, groupId: 'g1');

    expect(find.byType(UserAvatar), findsOneWidget);
    expect(find.text('AO'), findsOneWidget);
  });

  testWidgets('grupta kendi işin de rozet taşır', (tester) async {
    // Bilinçli: işaretin **yokluğunu** "benim" anlamına getirmek, boş bir
    // haftada öğrenilemeyecek sessiz bir kural olurdu.
    await _pump(tester, groupId: 'g1', ownerId: 'u-ali');

    expect(find.byType(UserAvatar), findsOneWidget);
  });

  testWidgets('sahibi bilinmeyen satır rozet almaz', (tester) async {
    // Yerelde üretilmiş, henüz gönderilmemiş iş: sahibi bir kare sonra
    // sunucudan dönecek. O ana kadar `?` göstermek yanlış soru sordururdu.
    await _pump(tester, groupId: 'g1', ownerId: null);

    expect(find.byType(UserAvatar), findsNothing);
  });

  testWidgets('tanınmayan sahip soru işaretiyle çizilir', (tester) async {
    // Gruba yeni katılmış birinin profili henüz önbellekte yok; iş yine de
    // birinin ve rozeti o boşluğu söylüyor.
    await _pump(tester, groupId: 'g1', ownerId: 'u-yabanci');

    expect(find.text('?'), findsOneWidget);
  });
}
