import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:window_manager/window_manager.dart';

import 'core/app_config.dart';
import 'core/auth_service.dart';
import 'core/connectivity.dart';
import 'core/handwriting_recognizer.dart';
import 'core/mlkit_recognizer.dart';
import 'core/reminders.dart';
import 'core/secure_key_store.dart';
import 'core/telemetry.dart';
import 'core/windows_ink_recognizer.dart';
import 'data/app_store.dart';
import 'data/local_notifications_gateway.dart';
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
          store: store,
          telemetry: telemetry,
        )
      : null;

  // El yazısı motorunun seçimi burada, çalışan uygulamada yapılıyor —
  // provider'ın kendi varsayılanında değil.
  //
  // Neden: `handwritingRecognizerProvider`ın varsayılanı `Unavailable` ve öyle
  // kalmalı. Seçimi provider'ın içine `Platform.isWindows` ile yazsaydık
  // testler de Windows'ta koştuğu için gerçek kanalı çağırmaya kalkarlardı;
  // depo zaten aynı kararı telemetri, depolama ve senkron için de burada
  // veriyor.
  final recognizer = _recognizerForPlatform();
  final reminders = _remindersForPlatform();

  final container = ProviderContainer(
    overrides: [
      telemetryProvider.overrideWithValue(telemetry),
      localStoreProvider.overrideWithValue(store),
      outboxProvider.overrideWithValue(outbox),
      remoteGatewayProvider.overrideWithValue(remote),
      authServiceProvider.overrideWithValue(authService),
      syncEngineProvider.overrideWithValue(engine),
      handwritingRecognizerProvider.overrideWithValue(recognizer),
      reminderGatewayProvider.overrideWithValue(reminders),
    ],
  );

  // Motoru şimdiden hazırla: Windows'ta "dil paketi var mı" sorusu, Android'de
  // modelin indirilmesi. Beklemiyoruz — ikisi de uygulamanın açılışını
  // geciktirmemeli; onay şeridi açıldığında `warmUp` yeniden çağrılıyor ve
  // aynı işe biniyor.
  unawaited(recognizer.warmUp());

  // Store'u depoya bağla ve kayıtlı durumu yükle. Bu satırdan sonra ilk kare
  // zaten dolu çizilir.
  final appStore = container.read(appStoreProvider);
  await appStore.attachPersistence(store, outbox: outbox);

  if (engine != null) {
    engine
      ..snapshotProvider = appStore.toJson
      // Artımlı çekimin yerel duruma açılan kapısı (Y1). Bağlanmasaydı motor
      // yalnız gönderirdi ve ikinci cihazın değişikliği uygulama yeniden
      // başlatılana kadar gelmezdi.
      ..mergeHandler = appStore.mergeJson
      ..start();
  }

  // Hatırlatmalar depo dolduktan **sonra**: boş depoyla kurulan ilk plan
  // bekleyen bütün bildirimleri silerdi. Beklenmiyor — eklentinin açılışı
  // (saat dilimi veritabanı) ilk kareyi geciktirmemeli.
  unawaited(
    reminders.init().then(
      (_) => container.read(reminderSchedulerProvider).start(),
      onError: (Object _) {},
    ),
  );

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
/// Bu platformda hangi el yazısı motorunun konuşacağı.
///
/// Windows'ta işletim sisteminin kendi `InkAnalyzer`'ı, Android'de ML Kit;
/// başka her yerde "tanıma yok" hâli. Bu üç satır, planın §Aa'da kabul ettiği
/// bedelin tamamı: ayrışma burada başlıyor ve burada bitiyor.
///
/// `Platform` yerine [defaultTargetPlatform] kullanılmıyor: burası zaten
/// yalnız gerçek uygulamada koşuyor (testler provider'ı override ediyor) ve
/// soru "hangi işletim sistemi" — "hangi tasarım dili" değil.
HandwritingRecognizer _recognizerForPlatform() {
  if (kIsWeb) return const UnavailableRecognizer();
  if (Platform.isWindows) return WindowsInkRecognizer();
  if (Platform.isAndroid) return MlKitRecognizer();
  return const UnavailableRecognizer();
}

/// Bildirim kapısı: yalnız hatırlatmaların gerçekten kurulabildiği yerde
/// gerçek eklenti. Masaüstünde Linux/macOS dağıtım hedefi değil.
ReminderGateway _remindersForPlatform() {
  if (kIsWeb) return NoopReminderGateway();
  if (Platform.isWindows || Platform.isAndroid) {
    return LocalNotificationsGateway();
  }
  return NoopReminderGateway();
}

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
    SupabaseAuthService(client.auth, onBrowserReturn: _bringToFront),
  );
}

/// Google girişinden dönülünce pencereyi öne getirir (G1). Kullanıcı az
/// önce tarayıcıdaydı; takvim arkada kalırsa "giriş oldu mu" diye aramak
/// zorunda kalırdı.
void _bringToFront() {
  if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    return;
  }
  unawaited(() async {
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {
      // Pencere yöneticisi hazır değilse sessiz: giriş yine tamamlandı.
    }
  }());
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
