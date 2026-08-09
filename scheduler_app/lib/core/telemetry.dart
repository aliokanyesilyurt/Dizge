import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import 'app_config.dart';

/// Uygulamada gönderilen tüm olayların **tek** listesi.
///
/// Mimari karar: olay adları serbest string olarak dağılmaz. Panoda "task_added"
/// ile "task_created" gibi ikizler oluşmasın diye hepsi burada sabit. Yeni olay
/// eklerken buraya yaz, çağrı yerinde string yazma.
class Ev {
  const Ev._();

  // Yaşam döngüsü
  static const appOpened = 'app_opened';

  // Görev
  static const taskCreated = 'task_created';
  static const taskUpdated = 'task_updated';
  static const taskDeleted = 'task_deleted';
  static const taskCompleted = 'task_completed';
  static const taskUncompleted = 'task_uncompleted';

  /// Izgarada sürükleyip bırakma — ürünün kilit etkileşimi, ayrı ölçülür.
  static const taskMoved = 'task_moved';
  static const taskResized = 'task_resized';

  /// Havuz: takvimden çekme ve geri koyma. İkisi ayrı olay, çünkü asıl soru
  /// "havuza atılan iş geri geliyor mu, yoksa orası bir çöp kutusu mu".
  static const taskPooled = 'task_pooled';
  static const taskUnpooled = 'task_unpooled';

  /// "Günü kurtar". Geri alma **ayrı bir olay**, çünkü asıl soru düğmeye kaç
  /// kez basıldığı değil: bastıktan sonra pişman olunuyor mu. Yüksek bir geri
  /// alma oranı sözleşmenin (§6) yanlış işleri süpürdüğünü söyler — özelliğin
  /// tek erken uyarısı bu.
  static const dayRescued = 'day_rescued';
  static const dayRescueUndone = 'day_rescue_undone';

  /// Rutinin tek bir günü elle atlandı (kurtarma dışında, bloğun kendi
  /// menüsünden).
  static const routineSkipped = 'routine_skipped';

  // Gezinme / görünüm
  static const screenViewed = 'screen_viewed';
  static const weekChanged = 'week_changed';
  static const quickAddOpened = 'quick_add_opened';
  static const editorOpened = 'editor_opened';

  // Diğer varlıklar
  static const noteCreated = 'note_created';
  static const habitCreated = 'habit_created';
  static const habitToggled = 'habit_toggled';

  // Sağlık
  static const syncFlushed = 'sync_flushed';
  static const persistFailed = 'persist_failed';
  static const appError = 'app_error';
}

/// Telemetri sözleşmesi. UI ve servisler yalnızca bunu tanır; PostHog'a bağımlı
/// değildir. Sağlayıcı değişirse (Amplitude, kendi backend'in) tek bir sınıf
/// yazman yeter.
abstract class Telemetry {
  /// Bir olay gönderir. [props] **kişisel veri içermemelidir** — bkz.
  /// [SafeProps] ve sınıf başındaki gizlilik notu.
  void capture(String event, {Map<String, Object>? props});

  /// Ekran görüntüleme (PostHog'da ayrı bir olay tipi).
  void screen(String name, {Map<String, Object>? props});

  /// Oturum açan kullanıcıyı bağlar (backend eklendiğinde).
  Future<void> identify(String distinctId, {Map<String, Object>? props});

  /// Çıkışta kimliği ayırır — bir sonraki kullanıcı öncekinin profiline yazmasın.
  Future<void> reset();

  /// Kuyruğu hemen gönderir (uygulama arka plana giderken).
  Future<void> flush();
}

/// **Gizlilik sözleşmesi.** Bu uygulama kişinin günlük planını tutuyor; görev
/// başlıkları, notlar, yer adları son derece hassas. Bu yüzden telemetriye
/// yalnızca *şekil* verisi gider: sayılar, süreler, enum adları, boolean'lar.
///
/// [SafeProps] serbest metni yakalayıp reddeder; kaza ile başlık göndermeyi
/// derleme sonrası değil, ilk çalıştırmada (debug'ta assert) yakalarız.
class SafeProps {
  const SafeProps._();

  /// İzin verilen değer tipleri. String'ler yalnızca sabit sözlükten gelebilir.
  static Map<String, Object> sanitize(Map<String, Object>? props) {
    if (props == null || props.isEmpty) return const {};
    final out = <String, Object>{};
    props.forEach((k, v) {
      if (v is num || v is bool) {
        out[k] = v;
      } else if (v is String) {
        // Serbest metin sızıntısını engelle: uzun ya da boşluklu string'ler
        // büyük ihtimalle kullanıcı içeriğidir; enum/slug değildir.
        final looksLikeUserContent = v.length > 32 || v.contains(' ');
        assert(
          !looksLikeUserContent,
          'Telemetriye serbest metin gönderilmeye çalışıldı ("$k"). '
          'Kullanıcı içeriği asla telemetriye girmez; sayı/enum gönder.',
        );
        if (!looksLikeUserContent) out[k] = v;
      } else if (v is Iterable) {
        out[k] = v.length; // liste yerine yalnızca uzunluğu
      }
    });
    return out;
  }
}

/// Hiçbir şey göndermeyen uygulama. Testlerde, anahtar yokken ve kullanıcı
/// rıza vermediğinde kullanılır. **Varsayılan budur.**
class NoopTelemetry implements Telemetry {
  const NoopTelemetry();

  @override
  void capture(String event, {Map<String, Object>? props}) {}

  @override
  void screen(String name, {Map<String, Object>? props}) {}

  @override
  Future<void> identify(
    String distinctId, {
    Map<String, Object>? props,
  }) async {}

  @override
  Future<void> reset() async {}

  @override
  Future<void> flush() async {}
}

/// Olayları konsola basar. Geliştirirken "acaba gidiyor mu?" sorusunu ağ
/// trafiği olmadan cevaplar.
class DebugTelemetry implements Telemetry {
  const DebugTelemetry();

  void _log(String kind, String name, Map<String, Object>? props) {
    final safe = SafeProps.sanitize(props);
    debugPrint('📊 $kind: $name${safe.isEmpty ? '' : ' $safe'}');
  }

  @override
  void capture(String event, {Map<String, Object>? props}) =>
      _log('event', event, props);

  @override
  void screen(String name, {Map<String, Object>? props}) =>
      _log('screen', name, props);

  @override
  Future<void> identify(
    String distinctId, {
    Map<String, Object>? props,
  }) async => _log('identify', distinctId, props);

  @override
  Future<void> reset() async => _log('reset', '-', null);

  @override
  Future<void> flush() async {}
}

/// Gerçek PostHog uygulaması.
///
/// Not: `Posthog()` singleton'ı [PostHogTelemetry.init] çağrılmadan
/// kullanılmamalı; bu yüzden fabrika yalnızca başarılı kurulumda örnek döner.
class PostHogTelemetry implements Telemetry {
  PostHogTelemetry._(this._posthog);

  final Posthog _posthog;

  /// Ortak özellikler: her olaya eklenir, panoda ortam/sürüm kırılımı sağlar.
  static final Map<String, Object> _superProps = {
    'app_env': AppConfig.environment,
  };

  /// Anahtar yoksa ya da kurulum patlarsa `null` döner — çağıran tarafta
  /// [NoopTelemetry]'ye düşülür. Telemetri **asla** uygulamayı düşürmez.
  static Future<PostHogTelemetry?> init() async {
    if (!AppConfig.telemetryAvailable) return null;
    try {
      final config = PostHogConfig(AppConfig.posthogApiKey)
        ..host = AppConfig.posthogHost
        // Ekran/dokunma otomatik yakalama kapalı: hangi olayın gittiğini
        // biz belirleriz, aksi hâlde metin içerikleri sızabilir.
        ..captureApplicationLifecycleEvents = true
        ..debug = !AppConfig.isProd
        ..sessionReplay = false;

      final posthog = Posthog();
      await posthog.setup(config);
      return PostHogTelemetry._(posthog);
    } catch (e, s) {
      debugPrint('PostHog başlatılamadı, telemetri kapalı: $e\n$s');
      return null;
    }
  }

  Map<String, Object> _props(Map<String, Object>? props) => {
    ..._superProps,
    ...SafeProps.sanitize(props),
  };

  @override
  void capture(String event, {Map<String, Object>? props}) {
    // Ateşle-unut: ağ hatası kullanıcı akışını kesmemeli.
    _posthog
        .capture(eventName: event, properties: _props(props))
        .catchError((Object e) => debugPrint('telemetri capture hatası: $e'));
  }

  @override
  void screen(String name, {Map<String, Object>? props}) {
    _posthog
        .screen(screenName: name, properties: _props(props))
        .catchError((Object e) => debugPrint('telemetri screen hatası: $e'));
  }

  @override
  Future<void> identify(String distinctId, {Map<String, Object>? props}) async {
    try {
      await _posthog.identify(
        userId: distinctId,
        userProperties: _props(props),
      );
    } catch (e) {
      debugPrint('telemetri identify hatası: $e');
    }
  }

  @override
  Future<void> reset() async {
    try {
      await _posthog.reset();
    } catch (e) {
      debugPrint('telemetri reset hatası: $e');
    }
  }

  @override
  Future<void> flush() async {
    try {
      await _posthog.flush();
    } catch (e) {
      debugPrint('telemetri flush hatası: $e');
    }
  }
}

/// Rızaya bağlı telemetri geçidi.
///
/// KVKK/GDPR açısından kritik: kullanıcı açıkça kabul edene kadar tek bir olay
/// bile gitmez. [enabled] false iken tüm çağrılar yutulur; sonradan açılırsa
/// **geçmiş olaylar geri gönderilmez** (biriktirilmez de) — sessiz izleme yok.
class ConsentGate implements Telemetry {
  ConsentGate(this._inner, {bool enabled = false}) : _enabled = enabled;

  final Telemetry _inner;
  bool _enabled;

  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) await _inner.reset();
  }

  @override
  void capture(String event, {Map<String, Object>? props}) {
    if (_enabled) _inner.capture(event, props: props);
  }

  @override
  void screen(String name, {Map<String, Object>? props}) {
    if (_enabled) _inner.screen(name, props: props);
  }

  @override
  Future<void> identify(String distinctId, {Map<String, Object>? props}) async {
    if (_enabled) await _inner.identify(distinctId, props: props);
  }

  @override
  Future<void> reset() => _inner.reset();

  @override
  Future<void> flush() => _enabled ? _inner.flush() : Future.value();
}

/// Telemetri sağlayıcısı. `bootstrap()` gerçek uygulamayı override eder;
/// testler ve widget testleri bunu override etmezse [NoopTelemetry] alır —
/// yani test koşusu asla ağa çıkmaz.
final telemetryProvider = Provider<Telemetry>((ref) => const NoopTelemetry());
