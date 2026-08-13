import 'package:flutter/foundation.dart';

/// Uygulamanın derleme zamanı yapılandırması.
///
/// Mimari karar — **sırlar kaynak koda gömülmez**. Tüm anahtarlar
/// `--dart-define` ile derleme sırasında verilir; verilmezse ilgili özellik
/// sessizce kapanır (uygulama yine çalışır). Böylece:
///   * repoya API anahtarı kaçmaz,
///   * geliştirici makinesinde telemetri kapalı çalışır,
///   * CI/CD aynı kodu farklı ortamlara (dev/staging/prod) derleyebilir.
///
/// Örnek üretim derlemesi:
/// ```
/// flutter build appbundle \
///   --dart-define=POSTHOG_API_KEY=phc_xxx \
///   --dart-define=POSTHOG_HOST=https://eu.i.posthog.com \
///   --dart-define=APP_ENV=prod
/// ```
class AppConfig {
  const AppConfig._();

  // --- Ortam ---------------------------------------------------------------

  /// `dev` | `staging` | `prod`. Telemetri olaylarına özellik olarak eklenir ki
  /// geliştirme trafiği üretim panosunu kirletmesin.
  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: kReleaseMode ? 'prod' : 'dev',
  );

  static bool get isProd => environment == 'prod';

  // --- PostHog -------------------------------------------------------------

  static const String posthogApiKey = String.fromEnvironment('POSTHOG_API_KEY');

  /// AB veri ikametgâhı için `https://eu.i.posthog.com` verilebilir.
  static const String posthogHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://eu.i.posthog.com',
  );

  /// Anahtar yoksa PostHog hiç başlatılmaz; [NoopTelemetry] devreye girer.
  static bool get telemetryAvailable => posthogApiKey.isNotEmpty;

  // --- Supabase ------------------------------------------------------------

  /// Proje URL'i, ör. `https://abcdefgh.supabase.co`.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Yayınlanabilir (public) anahtar. **Sır değildir** — istemciye zaten
  /// dağıtılır ve tek başına hiçbir veriye erişim vermez. Erişimi belirleyen
  /// şey satır düzeyi güvenlik (bkz. `supabase/schema.sql`). Yine de
  /// `--dart-define` ile veriliyor ki ortamlar (dev/staging/prod) aynı kodla
  /// derlensin.
  ///
  /// İki ad da okunuyor: Supabase panosu bu anahtarı önce "anon key", şimdi
  /// "publishable key" diye adlandırıyor. Eski derleme betikleri bozulmasın.
  static const String _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get supabaseKey =>
      _publishableKey.isNotEmpty ? _publishableKey : _anonKey;

  /// İkisi birden verilmemişse backend hiç kurulmaz: uygulama bugünkü gibi
  /// tamamen yerel çalışır, senkron motoru uyanmaz.
  static bool get backendAvailable =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  // --- Google ile giriş ----------------------------------------------------

  /// Tarayıcıdaki giriş bitince Supabase'in jetonu geri yollayacağı adres
  /// (G8b). Özel şema: `dizge` marka adı — `io.supabase.*` gibi bir ön ek,
  /// uygulamanın adını altyapı sağlayıcısına bağlardı.
  ///
  /// `--dart-define` ile verilmiyor: derlemeden derlemeye değişemez. Adres
  /// aynı zamanda platform kaydının içinde duruyor (Windows registry, Android
  /// manifest, iOS/macOS plist) ve Supabase panosundaki "Redirect URLs"
  /// listesine yazılı. Dördü birden değişmeden bunu değiştirmek, dönüşü
  /// sessizce koparırdı.
  ///
  /// Web'de kullanılmaz: orada dönüş, sayfanın kendi adresidir.
  static const String oauthCallbackUrl = 'dizge://login-callback';

  // --- Kalıcılık -----------------------------------------------------------

  /// Şifreli kutunun adı. Sürüm eki taşımaz; şema değişimi
  /// [kSchemaVersion] + migrasyon ile yönetilir.
  static const String boxName = 'scheduler_secure_box';

  /// Güvenli kasada AES anahtarının saklandığı isim.
  static const String encryptionKeyName = 'scheduler_hive_key_v1';

  /// Kalıcı anlık görüntünün şema sürümü. Model alanı ekleyip çıkardıkça artır
  /// ve [LocalStore] içindeki migrasyona bir adım yaz.
  ///
  /// v3: `Habit.updatedAt` — senkronun "son yazan kazanır" hakemi. Yazılan
  /// şekil değiştiği için sürüm artıyor; buna karşılık `migrateSnapshot`'ta
  /// v2 → v3 adımı **yok**, çünkü eksik damga okuma anında `createdAt`'ten
  /// türetiliyor (`Habit.fromJson`). Görüntüyü yeniden yazmak gereksiz iş
  /// olurdu.
  static const int kSchemaVersion = 3;

  // --- Senkronizasyon ------------------------------------------------------

  /// Bekleyen mutasyonların gönderilmeden önce biriktirileceği süre.
  static const Duration syncDebounce = Duration(seconds: 2);

  /// Diske yazmadan önceki bekleme. Sürükleme sırasında saniyede onlarca
  /// mutasyon olabilir; her birinde diske yazmak pil ve I/O israfı olur.
  static const Duration persistDebounce = Duration(milliseconds: 400);

  /// Outbox'ta tutulacak azami mutasyon. Aşılırsa en eskiler düşer ve tam
  /// anlık görüntü senkronu (full push) gerekir.
  static const int outboxLimit = 2000;
}
