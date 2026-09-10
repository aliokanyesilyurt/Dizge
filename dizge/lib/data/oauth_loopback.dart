import 'dart:async';
import 'dart:convert' show HtmlEscape;
import 'dart:io';

/// Masaüstünde Google girişinin dönüş noktası (G1).
///
/// Neden özel şema (`dizge://`) değil: tarayıcı o adrese yönlenince
/// uygulamayı açıyor ama **kendisi gösterecek bir sayfa bulamıyor**; sekme
/// Google'ın son sayfasında "yükleniyor" diye dönüp duruyordu. Giriş
/// başarılı oluyor, yalnız tarayıcı tarafı yarım kalıyordu. Bir sekmeyi
/// betikle kapatmak da mümkün değil — tarayıcılar yalnız betiğin kendi
/// açtığı pencereyi kapattırıyor.
///
/// Burada uygulama giriş başlarken `127.0.0.1` üzerinde küçük bir HTTP
/// dinleyici açıyor. Tarayıcı oraya dönünce gelen kod oturuma çevriliyor ve
/// tarayıcıya **bizim sayfamız** gidiyor: "Giriş tamamlandı, bu sekmeyi
/// kapatabilirsin". Dinleyici tek kullanımlık; iş bitince ya da [timeout]
/// dolunca kapanıyor.
class OAuthLoopback {
  OAuthLoopback({this.port = defaultPort});

  /// Sabit port: Supabase panosundaki izinli dönüş adresleri listesinde
  /// birebir bu adres duruyor. Değişirse pano da güncellenmeli.
  static const int defaultPort = 53682;
  static const String path = '/auth-callback';

  final int port;
  HttpServer? _server;
  Timer? _timer;

  String get redirectUrl => 'http://127.0.0.1:$port$path';

  bool get isListening => _server != null;

  /// Dinlemeye başlar. Port doluysa `false` döner ve çağıran eski yola
  /// (özel şema) düşer — giriş yine çalışır, yalnız sekme açık kalır.
  ///
  /// [onCallback] dönüş adresini alır; hata varsa kullanıcıya gösterilecek
  /// cümleyi, yoksa `null` döner. Sayfa ona göre yazılır.
  Future<bool> start({
    required Future<String?> Function(Uri uri) onCallback,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    await stop();
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      return false;
    }
    _timer = Timer(timeout, stop);

    _server!.listen((request) async {
      // Tarayıcılar sayfanın yanında `favicon.ico` da istiyor; ona boş cevap.
      if (request.uri.path != path) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      String? error;
      try {
        error = await onCallback(request.uri);
      } catch (_) {
        error = 'Giriş tamamlanamadı. Uygulamaya dönüp tekrar dene.';
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html;
      request.response.write(resultPage(error: error));
      await request.response.close();
      await stop();
    });
    return true;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  /// Tarayıcıda gösterilen sayfa. Tek dosya, dış kaynak yok (dinleyici
  /// kapanınca hiçbir şey yüklenemezdi); iki temada da okunur.
  static String resultPage({String? error}) {
    final ok = error == null;
    final title = ok ? 'Giriş tamamlandı' : 'Giriş tamamlanmadı';
    final text = ok
        ? 'Dizge’ye dönebilirsin. Bu sekmeyi kapatabilirsin.'
        : const HtmlEscape().convert(error);
    final mark = ok ? '✓' : '!';
    final accent = ok ? '#22c55e' : '#ef4444';

    return '''<!doctype html>
<html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$title · Dizge</title>
<style>
:root{color-scheme:light dark;--bg:#f7f7f5;--card:#fff;--ink:#1c1c1a;--dim:#6b6b66}
@media (prefers-color-scheme:dark){:root{--bg:#111113;--card:#1b1b1e;--ink:#ededea;--dim:#a1a19b}}
body{margin:0;min-height:100vh;display:grid;place-items:center;background:var(--bg);
font-family:system-ui,-apple-system,"Segoe UI",sans-serif;color:var(--ink)}
.card{background:var(--card);padding:40px 36px;border-radius:20px;max-width:360px;
text-align:center;box-shadow:0 10px 30px rgba(0,0,0,.08)}
.mark{width:56px;height:56px;border-radius:50%;margin:0 auto 18px;display:grid;
place-items:center;font-size:28px;font-weight:700;color:#fff;background:$accent}
h1{font-size:20px;margin:0 0 8px}p{margin:0;color:var(--dim);line-height:1.5}
</style></head>
<body><div class="card"><div class="mark">$mark</div>
<h1>$title</h1><p>$text</p></div></body></html>''';
  }
}

/// Dönüş adresindeki hata parametresini kullanıcı cümlesine çevirir.
///
/// Sağlayıcı "access_denied" gibi teknik bir kod gönderiyor; kullanıcı
/// tarayıcıda "izin verme" dediyse ya da akışı yarıda bıraktıysa gelen bu.
String? oauthErrorOf(Uri uri) {
  final code = uri.queryParameters['error'];
  if (code == null) return null;
  if (code == 'access_denied') return 'Google girişi tamamlanmadı.';
  final description = uri.queryParameters['error_description'];
  return description == null || description.isEmpty
      ? 'Giriş tamamlanamadı ($code).'
      : description;
}
