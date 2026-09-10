import 'dart:convert';
import 'dart:io';

import 'package:dizge/data/oauth_loopback.dart';
import 'package:flutter_test/flutter_test.dart';

/// G1 — masaüstünde Google dönüşü yerel bir adrese yapılır ve tarayıcıya
/// "giriş tamamlandı" sayfası gider.
void main() {
  // Testler gerçek portu (53682) meşgul etmesin; boş bir port bulunuyor.
  Future<int> freePort() async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    return port;
  }

  Future<(int, String)> get(Uri uri) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      return (res.statusCode, await res.transform(utf8.decoder).join());
    } finally {
      client.close(force: true);
    }
  }

  test(
    'dönüş kodu işleyiciye gider, tarayıcıya başarı sayfası döner',
    () async {
      final loopback = OAuthLoopback(port: await freePort());
      Uri? received;

      final started = await loopback.start(
        onCallback: (uri) async {
          received = uri;
          return null;
        },
      );
      expect(started, isTrue);

      final (status, body) = await get(
        Uri.parse('${loopback.redirectUrl}?code=abc123'),
      );

      expect(status, 200);
      expect(received?.queryParameters['code'], 'abc123');
      expect(body, contains('Giriş tamamlandı'));
      expect(body, contains('sekmeyi kapatabilirsin'));
    },
  );

  test('işleyici hata dönerse sayfa onu söyler (kaçışlı)', () async {
    final loopback = OAuthLoopback(port: await freePort());
    await loopback.start(onCallback: (_) async => 'Kod <geçersiz>');

    final (_, body) = await get(Uri.parse(loopback.redirectUrl));

    expect(body, contains('Giriş tamamlanmadı'));
    expect(body, contains('Kod &lt;geçersiz&gt;'));
  });

  test('tek kullanımlık: ilk dönüşten sonra kapanır', () async {
    final loopback = OAuthLoopback(port: await freePort());
    await loopback.start(onCallback: (_) async => null);

    await get(Uri.parse('${loopback.redirectUrl}?code=x'));
    // Kapanma cevaptan hemen sonra; bir tur beklemek yetiyor.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(loopback.isListening, isFalse);
  });

  test('başka yollar (favicon) işleyiciyi tetiklemez', () async {
    final loopback = OAuthLoopback(port: await freePort());
    var calls = 0;
    await loopback.start(
      onCallback: (_) async {
        calls++;
        return null;
      },
    );

    final (status, _) = await get(
      Uri.parse('http://127.0.0.1:${loopback.port}/favicon.ico'),
    );

    expect(status, 404);
    expect(calls, 0);
    expect(loopback.isListening, isTrue);
    await loopback.stop();
  });

  test('port doluysa false döner — çağıran özel şemaya düşer', () async {
    final busy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(busy.close);

    final loopback = OAuthLoopback(port: busy.port);
    final started = await loopback.start(onCallback: (_) async => null);

    expect(started, isFalse);
    expect(loopback.isListening, isFalse);
  });

  test('sağlayıcı hatası okunur cümleye çevrilir', () {
    expect(
      oauthErrorOf(Uri.parse('http://x/?error=access_denied')),
      'Google girişi tamamlanmadı.',
    );
    expect(oauthErrorOf(Uri.parse('http://x/?code=1')), isNull);
  });
}
