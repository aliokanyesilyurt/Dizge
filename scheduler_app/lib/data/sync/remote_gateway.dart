import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/group.dart';
import 'mutation.dart';
import 'supabase_api.dart';

/// Bir gönderim denemesinin sonucu.
class PushResult {
  const PushResult({
    this.accepted = const [],
    this.rejected = const [],
    this.fatal = false,
    this.message,
  });

  /// Sunucunun kabul ettiği mutasyon id'leri — kuyruktan düşer.
  final List<String> accepted;

  /// Geçici olarak başarısız olanlar — kuyrukta kalır, tekrar denenir.
  final List<String> rejected;

  /// Kalıcı hata (ör. yetkisiz, şema uyumsuz). Tekrar denemek anlamsız;
  /// senkron durur ve kullanıcıya bildirilir.
  final bool fatal;

  final String? message;

  static const PushResult empty = PushResult();
}

/// Uzak sunucu ile konuşan **tek** nokta.
///
/// Mimari karar: Supabase/Firebase kararı bu arayüzün arkasında kalır. Uygulama
/// kodunun hiçbir yeri `supabase` ya da `firebase` paketini tanımaz; sen
/// backend'i kurduğunda yalnızca bu sınıftan bir uygulama yazıp
/// [remoteGatewayProvider]'ı override etmen yeterli:
///
/// ```dart
/// class SupabaseGateway implements RemoteGateway { ... }
///
/// runApp(ProviderScope(
///   overrides: [remoteGatewayProvider.overrideWithValue(SupabaseGateway(client))],
///   child: const SchedulerApp(),
/// ));
/// ```
///
/// Şu anda [NoopRemoteGateway] bağlı: uygulama tamamen yerel çalışır, outbox
/// birikmez (mutasyonlar anında "kabul edilmiş" sayılır).
abstract class RemoteGateway {
  /// Sunucu yapılandırılmış mı? False ise senkron motoru hiç çalışmaz.
  bool get isConfigured;

  /// "Sunucuda bir şey değişti" sinyali (Y2).
  ///
  /// Akış **veri taşımaz** ve bu bilinçli. Supabase Realtime satırın yeni
  /// hâlini de gönderebiliyor; kullanmıyoruz çünkü gelen payload'ı doğrudan
  /// uygulamak, birleştirme mantığının ikinci bir kopyasını yazmak demek.
  /// Üstelik güvenilmez: bağlantının koptuğu sürede olan olaylar hiç gelmez
  /// ve o boşluğu zaten artımlı çekim kapatıyor.
  ///
  /// Yani gerçek zamanlılık, doğruluğun üstüne eklenen bir **hız katmanı**;
  /// doğruluğun kendisi buna bağlı değil.
  Stream<void> get remoteChanges;

  /// Bekleyen mutasyonları gönderir. Kısmi başarı desteklenir.
  Future<PushResult> push(List<Mutation> mutations);

  /// Sunucudaki değişiklikleri çeker. [since] null ise tam çekim.
  /// Dönen harita `AppStore.loadJson` ile aynı şemadadır.
  Future<Map<String, dynamic>?> pull({DateTime? since});

  /// Yerel durumu bütünüyle sunucuya yazar (outbox taştığında kurtarma yolu).
  Future<PushResult> pushSnapshot(Map<String, dynamic> snapshot);

  /// Kullanıcının üyesi olduğu gruplar (Y4).
  ///
  /// Outbox'tan geçmiyor ve geçmemeli: grup listesi kullanıcının **yazdığı**
  /// bir şey değil, üyeliğinin sonucu. Çevrimdışıyken son bilinen liste yerel
  /// önbellekten okunur — burası yalnız tazeleme yolu.
  Future<List<Group>> fetchGroups();

  // --- Grup işlemleri (Y4.3) -------------------------------------------------
  //
  // Dördü de **çevrimiçi ister** ve hiçbiri outbox'a girmez (Y4f). Outbox
  // `Mutation` taşıyor ve hakemi "son yazan kazanır"; grup kurmakla "aynı anda
  // başkasının kurduğu grup" arasında böyle bir hakem yok. Bağlantı yoksa
  // doğru davranış sessizce kuyruğa almak değil, düğmeyi kapatıp söylemek.

  /// Yeni grup kurar ve kuranı sahip olarak içine alır. Kurulan grubu döner.
  Future<Group> createGroup(String name);

  /// Tek kullanımlık davet üretir ve token'ını döner.
  ///
  /// [email] verilirse davet **o adrese yazılır** (Y3f/Y4g): token sızsa bile
  /// başka bir hesapta çalışmaz. Yalnız grup sahibi çağırabilir.
  Future<String> createInvite(String groupId, {String? email});

  /// Daveti kabul eder; girilen grubun kimliğini döner.
  Future<String> acceptInvite(String token);

  /// Kullanıcının kendi üyeliğini bırakır.
  ///
  /// Sunucudaki satırlara dokunmaz: onlar grubun ve orada kalır. Yereldeki
  /// kopyaların temizliği ayrı bir iş (Y4d, [AppStore.purgeGroup]).
  Future<void> leaveGroup(String groupId);
}

/// Backend bağlanana kadarki varsayılan. Uygulamayı %100 offline çalıştırır.
class NoopRemoteGateway implements RemoteGateway {
  const NoopRemoteGateway();

  @override
  bool get isConfigured => false;

  @override
  Stream<void> get remoteChanges => const Stream.empty();

  @override
  Future<PushResult> push(List<Mutation> mutations) async =>
      // Kabul edilmiş say: backend yokken kuyruk sonsuza dek şişmesin.
      PushResult(accepted: [for (final m in mutations) m.id]);

  @override
  Future<Map<String, dynamic>?> pull({DateTime? since}) async => null;

  @override
  Future<PushResult> pushSnapshot(Map<String, dynamic> snapshot) async =>
      PushResult.empty;

  @override
  Future<List<Group>> fetchGroups() async => const [];

  // Grup işlemleri sunucusuz **yapılamaz** ve sessizce başarılı numarası
  // yapmak en kötüsü olurdu: kullanıcı grubu kurulmuş sanır, kimseyi davet
  // edemediğinde nedenini bulamazdı.
  @override
  Future<Group> createGroup(String name) async => throw _yokSunucu;

  @override
  Future<String> createInvite(String groupId, {String? email}) async =>
      throw _yokSunucu;

  @override
  Future<String> acceptInvite(String token) async => throw _yokSunucu;

  @override
  Future<void> leaveGroup(String groupId) async => throw _yokSunucu;

  static const _yokSunucu = RemoteException(
    'Gruplar için hesap bağlantısı gerekiyor.',
    fatal: true,
  );
}

final remoteGatewayProvider = Provider<RemoteGateway>(
  (ref) => const NoopRemoteGateway(),
);
