import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/app_config.dart';
import '../../core/connectivity.dart';
import '../../core/telemetry.dart';
import '../local_store.dart';
import 'outbox.dart';
import 'remote_gateway.dart';

/// Artımlı çekimin nereden devam edeceği — **sunucu** damgası (Y1c).
const String kSyncCursorKey = 'sync_cursor';

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
    required LocalStore store,
    Telemetry telemetry = const NoopTelemetry(),
  }) : _outbox = outbox,
       _gateway = gateway,
       _connectivity = connectivity,
       _store = store,
       _telemetry = telemetry;

  final Outbox _outbox;
  final RemoteGateway _gateway;
  final ConnectivityService _connectivity;

  /// Yalnız senkron imleci için. Verinin kendisi [Outbox] ve `AppStore`
  /// üzerinden yazılıyor; motorun depoyla başka bir işi yok.
  final LocalStore _store;

  final Telemetry _telemetry;

  final _state = ValueNotifier<SyncState>(SyncState.idle);
  ValueListenable<SyncState> get state => _state;

  StreamSubscription<int>? _outboxSub;
  StreamSubscription<NetworkStatus>? _networkSub;
  StreamSubscription<void>? _remoteSub;
  Timer? _debounce;
  Timer? _retry;
  int _failureStreak = 0;
  bool _running = false;
  bool _stopped = false;

  /// Yerel durumun tamamını üretecek geri çağırım. Outbox taştığında tam
  /// gönderim için gerekir; [AppStore.toJson] bağlanır.
  Map<String, dynamic> Function()? snapshotProvider;

  /// Sunucudan gelen artımlı görüntüyü yerel duruma katan geri çağırım;
  /// `AppStore.mergeJson` bağlanır (Y1).
  ///
  /// Bağlanmazsa motor yalnız gönderir — eski davranış. Böylece çekimi
  /// açmak tek satırlık bir bağlama işi, motorun içine gömülü bir varsayım
  /// değil.
  void Function(Map<String, dynamic> snapshot)? mergeHandler;

  /// Abonelikleri kurar. Birden çok kez çağrılabilir (tekrarında yeniden
  /// abone olmaz).
  ///
  /// **`isConfigured`'a burada bakılmıyor** ve bu bilinçli bir düzeltme:
  /// yapılandırma sabit değil, oturuma bağlı. Açılışta oturum kapalıyken
  /// erken dönseydik, kullanıcı sonradan giriş yaptığında motor hiç uyanmaz
  /// ve senkron ancak uygulama yeniden başlatılınca çalışırdı. Denetim, asıl
  /// yeri olan [_scheduleFlush] ve [syncNow]'da.
  void start() {
    if (_stopped) return;
    _outboxSub ??= _outbox.changes.listen((_) => _scheduleFlush());
    _networkSub ??= _connectivity.watch().listen((status) {
      if (status == NetworkStatus.online) _scheduleFlush(immediate: true);
    });

    // Sunucu tarafındaki değişikliğin haberi (Y2). Sinyal **debounce ediliyor**:
    // karşı taraftaki bir sürükleme oturumu onlarca satır değiştirebilir ve her
    // olayda çekim yapmak gidiş-dönüş israfı olurdu.
    _remoteSub ??= _gateway.remoteChanges.listen(
      (_) => _scheduleFlush(),
      onError: (Object e) => debugPrint('Realtime akışı hatası: $e'),
    );

    _scheduleFlush(immediate: true);
  }

  void _scheduleFlush({bool immediate = false}) {
    if (_stopped) return;

    // Gönderecek de çekecek de bir şey yoksa tur boş. Kuyruğun boş olması
    // tek başına yeterli değil (Y1): artımlı çekimin amacı zaten hiçbir yerel
    // değişiklik olmadan karşı taraftan geleni almak.
    if (_outbox.isEmpty && mergeHandler == null) {
      _state.value = SyncState.idle;
      return;
    }

    // Oturum yokken kuyruk birikir ama gönderilmez — o veri henüz bir hesaba
    // ait değil. Giriş yapıldığında `syncNow()` elle çağrılır (bkz. bootstrap).
    if (!_gateway.isConfigured) return;
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : AppConfig.syncDebounce,
      () => unawaited(syncNow()),
    );
  }

  /// Bir senkron turu: önce gönder, sonra çek.
  ///
  /// Sıra sabit (Y1e). Kuyrukta bekleyen mutasyon varken çekmek, kullanıcının
  /// henüz gönderilmemiş değişikliğini sunucunun eski hâliyle ezebilirdi.
  ///
  /// Kuyruk boşken de koşar: artımlı çekimin bütün amacı, **hiçbir yerel
  /// değişiklik olmadan** karşı taraftan geleni almak.
  Future<void> syncNow() async {
    if (_running || _stopped || !_gateway.isConfigured) return;

    final hasPending = !_outbox.isEmpty;
    // Çekecek bir şey de yoksa tur tamamen boş.
    if (!hasPending && mergeHandler == null) {
      _state.value = SyncState.idle;
      return;
    }

    if (await _connectivity.current() == NetworkStatus.offline) {
      _state.value = hasPending ? SyncState.waitingForNetwork : SyncState.idle;
      return;
    }

    _running = true;
    _state.value = SyncState.syncing;
    try {
      if (hasPending) {
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

        if (result.rejected.isNotEmpty) {
          _scheduleRetry();
          return;
        }

        _failureStreak = 0;
        _telemetry.capture(
          Ev.syncFlushed,
          props: {'count': result.accepted.length},
        );
      }

      await _pullChanges();

      _failureStreak = 0;
      _state.value = _outbox.isEmpty ? SyncState.idle : SyncState.syncing;
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

  /// Sunucudaki değişiklikleri çeker ve yerel duruma katar (Y1).
  ///
  /// İmleç yoksa **epoch**'tan başlanıyor: bu, "her şeyi çek" demek ve kurulum
  /// başına bir kez oluyor. `since: null` ile tam çekim yapmak cazip ama
  /// yanlış olurdu — tam çekim `loadJson`'a gider ve yerel durumu **ezer**;
  /// o karar oturum açılışına ait (A4), motorun sessizce vereceği bir karar
  /// değil. Artımlı yol ise birleştiriyor, yani en kötü ihtimalle bir kez
  /// fazladan veri indirmiş oluyoruz.
  Future<void> _pullChanges() async {
    final merge = mergeHandler;
    if (merge == null) return;

    final saved = _store.readString(kSyncCursorKey);
    final since =
        (saved == null ? null : DateTime.tryParse(saved)) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    final snapshot = await _gateway.pull(since: since);
    if (snapshot == null) return;

    merge(snapshot);

    // İmleç **yalnız başarılı birleştirmeden sonra** ilerliyor: yarıda kalan
    // bir çekim, bir daha hiç gelmeyecek kayıtlar bırakmamalı. Sunucu hiç
    // satır döndürmediyse `cursor` null gelir ve imleç olduğu yerde kalır.
    final cursor = snapshot['cursor'];
    if (cursor is String) {
      await _store.writeString(kSyncCursorKey, cursor);
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
    await _remoteSub?.cancel();
    _state.dispose();
  }
}
