import 'dart:convert';

import 'package:dizge/core/auth_service.dart';
import 'package:dizge/core/connectivity.dart';
import 'package:dizge/core/profile_directory.dart';
import 'package:dizge/data/local_store.dart';
import 'package:dizge/data/persistence_providers.dart';
import 'package:dizge/data/sync/mutation.dart';
import 'package:dizge/data/sync/remote_gateway.dart';
import 'package:dizge/data/sync/supabase_api.dart';
import 'package:dizge/models/group.dart';
import 'package:dizge/models/profile.dart';
import 'package:dizge/screens/account_screen.dart';
import 'package:dizge/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Y4.4e/g — hesap ekranı: kendi avatarın ve görünen adı değiştirme.

class _FakeGateway implements RemoteGateway {
  final List<String> renamed = [];
  Exception? nextFailure;

  @override
  Future<void> updateDisplayName(String displayName) async {
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
    renamed.add(displayName);
  }

  @override
  Future<List<Profile>> fetchProfiles() async => const [];
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
  Future<Group> createGroup(String name) async => throw UnimplementedError();
  @override
  Future<String> createInvite(String g, {String? email}) async =>
      throw UnimplementedError();
  @override
  Future<String> acceptInvite(String t) async => throw UnimplementedError();
  @override
  Future<void> leaveGroup(String g) async => throw UnimplementedError();
}

const _me = Profile(userId: 'k1', displayName: 'Ali Okan');
const _user = AuthUser(id: 'k1', email: 'ali@example.com');

LocalStore _storeWithProfile() {
  final store = InMemoryStore();
  store.writeString(kProfilesCacheKey, jsonEncode([_me.toJson()]));
  return store;
}

Future<_FakeGateway> _pumpAccount(
  WidgetTester tester, {
  AuthUser? user = _user,
  LocalStore? store,
  NetworkStatus network = NetworkStatus.online,
}) async {
  // Hesap ekranı uzun; alan pencereye sığsın diye ekran yükseltiliyor.
  useScreenSize(tester, const Size(900, 1800));

  final auth = FakeAuthService(user: user);
  addTearDown(auth.dispose);
  final gateway = _FakeGateway();

  await pumpApp(
    tester,
    const AccountScreen(),
    overrides: [
      authServiceProvider.overrideWithValue(auth),
      localStoreProvider.overrideWithValue(store ?? _storeWithProfile()),
      remoteGatewayProvider.overrideWithValue(gateway),
      networkStatusProvider.overrideWith((ref) => Stream.value(network)),
    ],
  );
  return gateway;
}

void main() {
  testWidgets('başlıkta ad, altında e-posta durur', (tester) async {
    // Bu ekranın ilk satırı, kullanıcının **başkalarına nasıl göründüğü**
    // olmalı; e-posta kimliğin kendisi değil, giriş yolu.
    await _pumpAccount(tester);

    expect(find.text('Ali Okan'), findsWidgets);
    expect(find.text('ali@example.com'), findsWidgets);
  });

  testWidgets('kendi avatarın grup arkadaşlarının gördüğü rozetle aynı', (
    tester,
  ) async {
    await _pumpAccount(tester);

    expect(find.byType(UserAvatar), findsWidgets);
    expect(find.text('AO'), findsWidgets);
  });

  testWidgets('oturum yoksa ad alanı hiç kurulmaz', (tester) async {
    // Adı olmayan bir hesabın değiştirilecek adı da yok.
    await _pumpAccount(tester, user: null, store: InMemoryStore());

    expect(find.text('Görünen ad'), findsNothing);
    expect(find.text('Misafir'), findsOneWidget);
  });

  testWidgets('ad kaydedilir ve sunucuya kırpılmış gider', (tester) async {
    final gateway = await _pumpAccount(tester);

    await tester.enterText(find.byType(TextField).first, '  Ali Okan Y.  ');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(gateway.renamed, ['Ali Okan Y.']);
    expect(find.text('Adın kaydedildi.'), findsOneWidget);
  });

  testWidgets('boş ad reddedilir, sunucuya hiç gidilmez', (tester) async {
    final gateway = await _pumpAccount(tester);

    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(gateway.renamed, isEmpty);
    expect(find.text('Görünen ad boş olamaz.'), findsOneWidget);
  });

  testWidgets('çevrimdışıyken kaydet pasif ve sebebi yazıyor', (tester) async {
    // Y4f'nin aynı gerekçesi: bu bir Mutation değil, outbox'a giremez.
    // Sessizce kuyruğa almak, kullanıcıya adının değiştiğini söyleyip karşı
    // tarafta eskisini bırakmak olurdu.
    await _pumpAccount(tester, network: NetworkStatus.offline);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Ad değiştirmek bağlantı gerektiriyor.'), findsOneWidget);
  });

  testWidgets('sunucu reddederse mesajı görünür', (tester) async {
    final gateway = await _pumpAccount(tester);
    gateway.nextFailure = const RemoteException('Sunucuya ulaşılamadı.');

    await tester.enterText(find.byType(TextField).first, 'Yeni Ad');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('Sunucuya ulaşılamadı.'), findsOneWidget);
  });
}
