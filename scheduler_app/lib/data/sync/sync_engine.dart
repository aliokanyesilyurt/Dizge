import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/app_config.dart';
import '../../core/connectivity.dart';
import '../../core/telemetry.dart';
import 'outbox.dart';
import 'remote_gateway.dart';

/// Senkronun kullanıcıya gösterilebilir durumu.
enum SyncState {
  /// Gönderilecek bir şey yok.
  idle,

  /// Bekleyen değişiklik var ama cihaz çevrimdışı.
  waitingForNetwork,

  /// Gönderim sürüyor.
  syncing,

  /// Kalıcı hata; kullanıcı müdahalesi gerekiyor (ör. yeniden oturum aç).
  failed,
}

/// Outbox'ı uzak sunucuya boşaltan motor.
///
/// Tetikleyiciler:
///   * kuyruğa yeni mutasyon düşmesi (debounce'lu),
///   * bağlantının geri gelmesi,
///   * uygulama öne geldiğinde elle [syncNow].
///
/// Başarısızlıkta **üstel geri çekilme** uygulanır (2s, 4s, 8s … en fazla 5dk)
/// ki sunucu düşükken cihaz pil yakmasın.
class SyncEngine {
  SyncEngine({
    required Outbox outbox,
    required RemoteGateway gateway,
    required ConnectivityService connectivity,
    Telemetry telemetry = const NoopTelemetry(),
  }) : _outbox = outbox,
       _gateway = gateway,
       _connectivity = connectivity,
       _telemetry = telemetry;

  final Outbox _outbox;
  final RemoteGateway _gateway;
  final ConnectivityService _connectivity;
  final Telemetry _telemetry;

  final _state = ValueNotifier<SyncState>(SyncState.idle);
  ValueListenable<SyncState> get state => _state;

  StreamSubscription<int>? _outboxSub;
  StreamSubscription<NetworkStatus>? _networkSub;
  Timer? _debounce;
  Timer? _retry;
  int _failureStreak = 0;
  bool _running = false;
  bool _stopped = false;

  /// Yerel durumun tamamını üretecek geri çağırım. Outbox taştığında tam
  /// gönderim için gerekir; [AppStore.toJson] bağlanır.
  Map<String, dynamic> Function()? snapshotProvider;

  void start() {
    if (!_gateway.isConfigured) {
      // Backend yok: motoru hiç uyandırma. Uygulama saf yerel çalışır.
      _state.value = SyncState.idle;
      return;
    }
    _outboxSub = _outbox.changes.listen((_) => _scheduleFlush());
    _networkSub = _connectivity.watch().listen((status) {
      if (status == NetworkStatus.online) _scheduleFlush(immediate: true);
    });
    _scheduleFlush(immediate: true);
  }

  void _scheduleFlush({bool immediate = false}) {
    if (_stopped || _outbox.isEmpty) {
      if (_outbox.isEmpty) _state.value = SyncState.idle;
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : AppConfig.syncDebounce,
      () => unawaited(syncNow()),
    );
  }

  /// Kuyruğu şimdi boşaltmayı dener. Eşzamanlı çağrılar tek turda birleşir.
  Future<void> syncNow() async {
    if (_running || _stopped || !_gateway.isConfigured) return;
    if (_outbox.isEmpty) {
      _state.value = SyncState.idle;
      return;
    }

    if (await _connectivity.current() == NetworkStatus.offline) {
      _state.value = SyncState.waitingForNetwork;
      return;
    }

    _running = true;
    _state.value = SyncState.syncing;
    try {
      // Kuyruk taştıysa artımlı gönderim tutarsız olur: önce tam görüntü.
      if (_outbox.needsFullPush && snapshotProvider != null) {
        final result = await _gateway.pushSnapshot(snapshotProvider!());
        if (result.fatal) {
          _onFatal(result);
          return;
        }
        _outbox.needsFullPush = false;
      }

      final batch = _outbox.pending;
      final result = await _gateway.push(batch);

      if (result.fatal) {
        _onFatal(result);
        return;
      }

      _outbox.ack(result.accepted);
      _outbox.markFailed(result.rejected);
      await _outbox.persist();

      if (result.rejected.isEmpty) {
        _failureStreak = 0;
        _state.value = _outbox.isEmpty ? SyncState.idle : SyncState.syncing;
        _telemetry.capture(
          Ev.syncFlushed,
          props: {'count': result.accepted.length},
        );
      } else {
        _scheduleRetry();
      }
    } catch (e, s) {
      debugPrint('Senkron hatası: $e\n$s');
      _scheduleRetry();
    } finally {
      _running = false;
      if (!_outbox.isEmpty && _state.value == SyncState.syncing) {
        _scheduleFlush();
      }
    }
  }

  void _onFatal(PushResult result) {
    _state.value = SyncState.failed;
    debugPrint('Senkron kalıcı hata: ${result.message}');
    _telemetry.capture(Ev.appError, props: {'area': 'sync', 'fatal': true});
  }

  /// 2s, 4s, 8s … en çok 5 dakika.
  void _scheduleRetry() {
    _failureStreak = math.min(_failureStreak + 1, 8);
    final delay = Duration(
      seconds: math.min(300, math.pow(2, _failureStreak).toInt()),
    );
    _state.value = SyncState.waitingForNetwork;
    _retry?.cancel();
    _retry = Timer(delay, () => unawaited(syncNow()));
  }

  Future<void> dispose() async {
    _stopped = true;
    _debounce?.cancel();
    _retry?.cancel();
    await _outboxSub?.cancel();
    await _networkSub?.cancel();
    _state.dispose();
  }
}
