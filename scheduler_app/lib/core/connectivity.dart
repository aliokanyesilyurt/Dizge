import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ağ durumunun uygulama içindeki tek temsili.
///
/// Dikkat: `connectivity_plus` yalnızca **arayüz** durumunu söyler (wifi var mı),
/// internetin gerçekten çalıştığını değil. Bu yüzden [NetworkStatus.online]
/// "denemeye değer" anlamına gelir; gönderim yine de başarısız olabilir ve
/// outbox mutasyonu tutmaya devam eder.
enum NetworkStatus { online, offline }

/// Bağlantı durumunu izleyen servis. Test edilebilir olsun diye
/// [Connectivity] dışarıdan verilebilir.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static NetworkStatus _map(List<ConnectivityResult> results) {
    final hasLink = results.any((r) => r != ConnectivityResult.none);
    return hasLink ? NetworkStatus.online : NetworkStatus.offline;
  }

  /// Anlık durum. Platform eklentisi yoksa (test/masaüstü) çevrimdışı sayılır —
  /// güvenli taraf: veri yerelde kalır.
  Future<NetworkStatus> current() async {
    try {
      return _map(await _connectivity.checkConnectivity());
    } catch (e) {
      debugPrint('Bağlantı durumu okunamadı: $e');
      return NetworkStatus.offline;
    }
  }

  /// Durum değişimlerini yayınlar. Aynı durumun tekrarı bastırılır ki
  /// senkron motoru gereksiz tetiklenmesin.
  Stream<NetworkStatus> watch() {
    return _connectivity.onConnectivityChanged
        .map(_map)
        .distinct()
        .handleError((Object e) => debugPrint('Bağlantı akışı hatası: $e'));
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) => ConnectivityService(),
);

/// UI'nin izleyebileceği bağlantı durumu. İlk değeri gelene kadar `offline`
/// varsayılır (iyimser "online" gösterip sonra düzeltmek titremeye yol açar).
final networkStatusProvider = StreamProvider<NetworkStatus>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.watch();
});
