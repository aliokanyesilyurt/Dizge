import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_config.dart';
import 'core/connectivity.dart';
import 'core/secure_key_store.dart';
import 'core/telemetry.dart';
import 'data/app_store.dart';
import 'data/local_store.dart';
import 'data/persistence_providers.dart';
import 'data/sync/outbox.dart';
import 'data/sync/remote_gateway.dart';
import 'data/sync/sync_engine.dart';

/// Uygulamanın çalışmaya hazır hâle geldiği tek nokta.
///
/// Sıra önemlidir:
///  1. Flutter bağlanır ve hata yakalayıcılar kurulur — bundan sonrasında
///     oluşan her çökme telemetriye düşer.
///  2. Telemetri kurulur (anahtar yoksa no-op).
///  3. Şifreli depo açılır; açılamazsa bellek deposuna düşülür (uygulama
///     çalışmaya devam eder, kullanıcı uyarılır).
///  4. Kayıtlı durum store'a yüklenir — ilk kare zaten dolu gelir, "boş takvim
///     bir anlığına görünüp sonra doluyor" titremesi olmaz.
///  5. Senkron motoru başlatılır (uzak sunucu tanımlıysa).
///
/// [gateway] üretimde `bootstrap()` çağrısından geçirilir; şimdilik
/// [NoopRemoteGateway] ile tamamen yerel çalışır.
Future<ProviderContainer> bootstrap({RemoteGateway? gateway}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final telemetry = await _initTelemetry();
  _installErrorHandlers(telemetry);

  final (store, storageDegraded) = await _openStore();

  final outbox = Outbox(store);
  final remote = gateway ?? const NoopRemoteGateway();

  // Senkron motoru yalnızca gerçek bir sunucu tanımlıysa kurulur; aksi hâlde
  // provider null kalır ve hiçbir zamanlayıcı dönmez.
  final engine = remote.isConfigured
      ? SyncEngine(
          outbox: outbox,
          gateway: remote,
          connectivity: ConnectivityService(),
          telemetry: telemetry,
        )
      : null;

  final container = ProviderContainer(
    overrides: [
      telemetryProvider.overrideWithValue(telemetry),
      localStoreProvider.overrideWithValue(store),
      outboxProvider.overrideWithValue(outbox),
      remoteGatewayProvider.overrideWithValue(remote),
      syncEngineProvider.overrideWithValue(engine),
    ],
  );

  // Store'u depoya bağla ve kayıtlı durumu yükle. Bu satırdan sonra ilk kare
  // zaten dolu çizilir.
  final appStore = container.read(appStoreProvider);
  await appStore.attachPersistence(store, outbox: outbox);

  if (engine != null) {
    engine
      ..snapshotProvider = appStore.toJson
      ..start();
  }

  telemetry.capture(
    Ev.appOpened,
    props: {
      'storage': storageDegraded ? 'memory_fallback' : 'encrypted',
      'pending_sync': outbox.length,
    },
  );

  return container;
}

Future<Telemetry> _initTelemetry() async {
  if (!AppConfig.telemetryAvailable) {
    // Anahtar yok: geliştirmede konsola bas, üretimde tamamen sus.
    return kDebugMode ? const DebugTelemetry() : const NoopTelemetry();
  }
  final posthog = await PostHogTelemetry.init();
  final inner = posthog ?? const NoopTelemetry();

  // Rıza kapısı: kullanıcı Hesap ekranından açana kadar tek olay gitmez.
  // (Rıza tercihi backend/ayar deposuna bağlandığında başlangıç değeri
  // oradan okunacak.)
  return ConsentGate(inner, enabled: false);
}

/// Şifreli depoyu açar. Başarısızsa bellek deposuna düşer ve `true` (bozulmuş)
/// bayrağı döner.
Future<(LocalStore, bool)> _openStore() async {
  final encrypted = HiveLocalStore();
  try {
    await encrypted.init();
    return (encrypted, false);
  } on SecureStorageUnavailable catch (e) {
    debugPrint('Güvenli depo açılamadı: $e');
  } catch (e, s) {
    debugPrint('Yerel depo açılamadı: $e\n$s');
  }

  final memory = InMemoryStore();
  await memory.init();
  return (memory, true);
}

/// Yakalanmayan hataları hem konsola hem telemetriye yönlendirir.
///
/// Not: hata **metni** gönderilmez — istisna mesajları kullanıcı verisi
/// içerebilir (ör. "Task 'Doktor randevusu' bulunamadı"). Yalnızca tipi ve
/// nerede olduğu ölçülür.
void _installErrorHandlers(Telemetry telemetry) {
  final previousOnError = FlutterError.onError;

  FlutterError.onError = (details) {
    previousOnError?.call(details);
    telemetry.capture(
      Ev.appError,
      props: {
        'type': details.exception.runtimeType.toString(),
        'library': details.library ?? 'unknown',
        'fatal': false,
      },
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Yakalanmayan hata: $error\n$stack');
    telemetry.capture(
      Ev.appError,
      props: {'type': error.runtimeType.toString(), 'fatal': true},
    );
    return true; // uygulamayı düşürme
  };
}

/// Uygulama arka plana giderken bekleyen yazmaları diske indirir.
///
/// Debounce penceresi (400 ms) içinde uygulama öldürülürse son değişiklik
/// kaybolurdu; bu gözlemci onu kapatıyor.
class AppLifecycleFlusher extends StatefulWidget {
  const AppLifecycleFlusher({super.key, required this.child});

  final Widget child;

  @override
  State<AppLifecycleFlusher> createState() => _AppLifecycleFlusherState();
}

class _AppLifecycleFlusherState extends State<AppLifecycleFlusher>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      final container = ProviderScope.containerOf(context, listen: false);
      unawaited(container.read(appStoreProvider).flush());
      unawaited(container.read(telemetryProvider).flush());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
