import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'core/app_config.dart';
import 'core/auth_service.dart';
import 'core/connectivity.dart';
import 'core/secure_key_store.dart';
import 'core/telemetry.dart';
import 'data/app_store.dart';
import 'data/local_store.dart';
import 'data/persistence_providers.dart';
import 'data/supabase_auth_service.dart';
import 'data/sync/outbox.dart';
import 'data/sync/remote_gateway.dart';
import 'data/sync/supabase_api.dart';
import 'data/sync/supabase_gateway.dart';
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
/// Supabase anahtarları `--dart-define` ile verilmişse gerçek kapılar kurulur;
/// verilmemişse [NoopRemoteGateway] + [NoopAuthService] ile uygulama tamamen
/// yerel çalışır. [gateway] ve [auth] yalnızca testler ve özel derlemeler için.
Future<ProviderContainer> bootstrap({
  RemoteGateway? gateway,
  AuthService? auth,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Depo telemetriden **önce** açılıyor (T4): rıza tercihi orada saklanıyor ve
  // geçit doğru başlangıç değeriyle kurulmalı. Hata yakalayıcıların bir adım
  // gecikmesi bilinçli bir bedel — `_openStore` kendi hatalarını zaten yakalayıp
  // bellek deposuna düşüyor, yani bu pencerede sessizce kaybolan bir çökme yok.
  final (store, storageDegraded) = await _openStore();

  final telemetry = await _initTelemetry(store);
  _installErrorHandlers(telemetry);

  final outbox = Outbox(store);
  final (remote, authService) = await _initBackend(gateway, auth);

  // Motorun varlığı **sunucunun yapılandırılmış olmasına** bağlı, oturumun
  // açık olmasına değil: kullanıcı uygulama açıldıktan sonra da giriş yapabilir
  // ve o an motorun kurulu olması gerekir. Oturum denetimi motorun içinde,
  // her gönderim turunda yapılıyor.
  final engine = remote.isConfigured || AppConfig.backendAvailable
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
      authServiceProvider.overrideWithValue(authService),
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

/// Supabase'i kurar ve kapıları döner.
///
/// Anahtarlar verilmemişse (`--dart-define` yok) **hiçbir şey kurulmaz**:
/// uygulama bugünkü gibi tamamen yerel çalışır. Bu, geliştirme makinesinde ve
/// testlerde varsayılan yol.
///
/// [gatewayOverride] / [authOverride] testler ve özel derlemeler için.
Future<(RemoteGateway, AuthService)> _initBackend(
  RemoteGateway? gatewayOverride,
  AuthService? authOverride,
) async {
  if (gatewayOverride != null || authOverride != null) {
    return (
      gatewayOverride ?? const NoopRemoteGateway(),
      authOverride ?? const NoopAuthService(),
    );
  }

  if (!AppConfig.backendAvailable) {
    return (const NoopRemoteGateway(), const NoopAuthService());
  }

  try {
    await sb.Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
      // Oturum jetonunu saklamak, yenilemek ve uygulama yeniden açıldığında
      // geri yüklemek paketin işi.
      authOptions: const sb.FlutterAuthClientOptions(autoRefreshToken: true),
    );
  } catch (e, s) {
    // Sunucu kurulamadıysa uygulama **yine de açılmalı**. Planlar cihazda ve
    // erişilebilir olmaya devam eder; yalnız eşitleme yoktur.
    debugPrint('Supabase kurulamadı, yerel kipte devam ediliyor: $e\n$s');
    return (const NoopRemoteGateway(), const NoopAuthService());
  }

  final client = sb.Supabase.instance.client;
  return (
    SupabaseGateway(LiveSupabaseApi(client)),
    SupabaseAuthService(client.auth),
  );
}

/// Telemetriyi kurar ve **her zaman** rıza geçidinin arkasına koyar.
///
/// "Her zaman" (T4) düzeltilmiş bir hata: eskiden anahtar verilmemişse geçit
/// hiç kurulmuyor, çıplak bir [NoopTelemetry] dönüyordu. Hesap ekranı da
/// geçidi göremeyince "Anonim kullanım istatistikleri" anahtarını pasif
/// bırakıyordu — düğme bozuk değildi, arkasında çevrilecek bir şey yoktu.
///
/// Şimdi geçit her koşulda var: tercih gerçek bir tercih, saklanıyor ve
/// açılışta geri okunuyor. İçeride gerçek bir sunucu olup olmaması ayrı bir
/// soru ve ekran bunu kullanıcıya dürüstçe söylüyor.
Future<Telemetry> _initTelemetry(LocalStore store) async {
  final Telemetry inner;
  if (!AppConfig.telemetryAvailable) {
    // Anahtar yok: geliştirmede konsola bas, üretimde tamamen sus.
    inner = kDebugMode ? const DebugTelemetry() : const NoopTelemetry();
  } else {
    inner = await PostHogTelemetry.init() ?? const NoopTelemetry();
  }

  // Varsayılan **kapalı**: kayıt yoksa rıza yok. Sessiz izleme, kullanıcının
  // henüz cevaplamadığı bir soruyu "evet" saymak olurdu.
  final remembered = store.readString(kTelemetryConsentKey) == 'on';

  return ConsentGate(
    inner,
    enabled: remembered,
    onPersist: (value) =>
        store.writeString(kTelemetryConsentKey, value ? 'on' : 'off'),
  );
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
