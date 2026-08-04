import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mutation.dart';

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

  /// Bekleyen mutasyonları gönderir. Kısmi başarı desteklenir.
  Future<PushResult> push(List<Mutation> mutations);

  /// Sunucudaki değişiklikleri çeker. [since] null ise tam çekim.
  /// Dönen harita `AppStore.loadJson` ile aynı şemadadır.
  Future<Map<String, dynamic>?> pull({DateTime? since});

  /// Yerel durumu bütünüyle sunucuya yazar (outbox taştığında kurtarma yolu).
  Future<PushResult> pushSnapshot(Map<String, dynamic> snapshot);
}

/// Backend bağlanana kadarki varsayılan. Uygulamayı %100 offline çalıştırır.
class NoopRemoteGateway implements RemoteGateway {
  const NoopRemoteGateway();

  @override
  bool get isConfigured => false;

  @override
  Future<PushResult> push(List<Mutation> mutations) async =>
      // Kabul edilmiş say: backend yokken kuyruk sonsuza dek şişmesin.
      PushResult(accepted: [for (final m in mutations) m.id]);

  @override
  Future<Map<String, dynamic>?> pull({DateTime? since}) async => null;

  @override
  Future<PushResult> pushSnapshot(Map<String, dynamic> snapshot) async =>
      PushResult.empty;
}

final remoteGatewayProvider = Provider<RemoteGateway>(
  (ref) => const NoopRemoteGateway(),
);
