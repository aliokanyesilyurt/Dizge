import 'package:dizge/core/handwriting_recognizer.dart';
import 'package:dizge/core/ink_lines.dart';
import 'package:dizge/core/mlkit_recognizer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A7 — Android tanıma motorunun Dart yarısı.
///
/// Karşı taraf ML Kit ve gerçek bir telefon gerektiriyor; buradaki testler o
/// yüzden **sözleşmeyi** sınıyor: model inmemişse ne oluyor, kanaldan ne
/// gidiyor, hata hâlinde ajanda ayakta kalıyor mu. Tanımanın *doğruluğu* bu
/// testlerin işi değil — o, elle bir tur atmakla ölçülür.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Paketin kendi kanalı: hem tanıma hem model yönetimi buradan geçiyor, bu
  // yüzden testler paketin gerçek kodunu çalıştırıyor — taklidi değil.
  const channel = MethodChannel('google_mlkit_digital_ink_recognizer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <MethodCall>[];

  /// [downloaded] modelin cihazda olup olmadığını, [texts] sırayla dönecek
  /// okumaları belirler.
  void mock({
    bool downloaded = true,
    bool downloadSucceeds = true,
    List<String> texts = const [],
  }) {
    var read = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'vision#manageInkModels':
          final task = (call.arguments as Map)['task'];
          if (task == 'check') return downloaded;
          return downloadSucceeds ? 'success' : 'fail';
        case 'vision#startDigitalInkRecognizer':
          final text = read < texts.length ? texts[read] : '';
          read++;
          return [
            {'text': text, 'score': 0.0},
          ];
        default:
          return null;
      }
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    calls.clear();
  });

  InkLine line(List<List<Offset>> strokes, [Rect? bounds]) =>
      InkLine(strokes, bounds ?? const Rect.fromLTWH(0, 0, 10, 10));

  InkLine oneStroke() => line([
    const [Offset.zero],
  ]);

  test('model inmişse motor hazır olur ve indirme denenmez', () async {
    mock();

    final recognizer = MlKitRecognizer();
    expect(
      recognizer.state,
      RecognizerState.preparing,
      reason: 'sorulmadan önce "hazırlanıyor" — ne ready ne unavailable',
    );

    await recognizer.warmUp();

    expect(recognizer.state, RecognizerState.ready);
    expect(
      calls.where((c) => (c.arguments as Map)['task'] == 'download'),
      isEmpty,
    );
  });

  test('model yoksa indirilir ve motor hazır olur', () async {
    mock(downloaded: false);

    final recognizer = MlKitRecognizer();
    await recognizer.warmUp();

    final download = calls.firstWhere(
      (c) => (c.arguments as Map)['task'] == 'download',
    );
    expect((download.arguments as Map)['model'], 'tr');
    // Wi-Fi şartı bilinçli olarak kapalı: kablosuz ağa hiç bağlanmayan bir
    // telefonda tanıma kalıcı olarak "hazırlanıyor"da kalırdı.
    expect((download.arguments as Map)['wifi'], isFalse);
    expect(recognizer.state, RecognizerState.ready);
  });

  test(
    'indirme başarısızsa tanıma kapanır, ajanda çalışmaya devam eder',
    () async {
      mock(downloaded: false, downloadSucceeds: false);

      final recognizer = MlKitRecognizer();
      final texts = await recognizer.recognizeLines([oneStroke(), oneStroke()]);

      expect(recognizer.state, RecognizerState.unavailable);
      // Uzunluk sözü: öneriler yazının hizasından kaymasın diye satır düşmez.
      expect(texts, ['', '']);
    },
  );

  test('warmUp iki kez çağrılsa da model bir kez inmeye çalışır', () async {
    mock(downloaded: false);

    final recognizer = MlKitRecognizer();
    await Future.wait([recognizer.warmUp(), recognizer.warmUp()]);
    await recognizer.warmUp();

    expect(
      calls.where((c) => (c.arguments as Map)['task'] == 'download').length,
      1,
    );
  });

  test('okunan metinler sırayla döner', () async {
    mock(texts: ['Süt al', 'Rapor yaz']);

    final texts = await MlKitRecognizer().recognizeLines([
      oneStroke(),
      oneStroke(),
    ]);

    expect(texts, ['Süt al', 'Rapor yaz']);
  });

  test('her satır ayrı çağrı — sayfa tek cümleye dönüşmez', () async {
    // ML Kit tek satır için eğitilmiş; üç satır tek yığın gönderilseydi geriye
    // tek uzun cümle dönerdi (plan §Ae).
    mock(texts: ['bir', 'iki', 'üç']);

    await MlKitRecognizer().recognizeLines([
      oneStroke(),
      oneStroke(),
      oneStroke(),
    ]);

    expect(
      calls.where((c) => c.method == 'vision#startDigitalInkRecognizer').length,
      3,
    );
  });

  test('satır kendi köşesine taşınır, yazı alanı satır kadar olur', () async {
    mock(texts: ['bir']);

    await MlKitRecognizer().recognizeLines([
      line([
        const [Offset(120, 500), Offset(140, 510)],
      ], const Rect.fromLTWH(120, 500, 60, 30)),
    ]);

    final args =
        calls
                .firstWhere(
                  (c) => c.method == 'vision#startDigitalInkRecognizer',
                )
                .arguments
            as Map;

    final strokes = ((args['ink'] as Map)['strokes'] as List).cast<Map>();
    final points = (strokes.single['points'] as List).cast<Map>();
    // Sayfanın altına yazılmış bir satır, yazı alanı satır kadarken 500 piksel
    // aşağıda duruyor gibi görünürdü.
    expect(points.first['x'], 0.0);
    expect(points.first['y'], 0.0);
    expect(points.last['x'], 20.0);
    expect(points.last['y'], 10.0);

    final area = (args['context'] as Map)['writingArea'] as Map;
    expect(area['width'], 60.0);
    expect(area['height'], 30.0);
  });

  test('zaman damgaları artan üretilir', () async {
    // `InkStroke` nokta zamanı saklamıyor; damgalar uydurma ama ML Kit artan
    // bir dizi bekliyor — azalan damga tanımayı bozar.
    mock(texts: ['bir']);

    await MlKitRecognizer().recognizeLines([
      line([
        const [Offset.zero, Offset(1, 1)],
        const [Offset(2, 2), Offset(3, 3)],
      ]),
    ]);

    final args =
        calls
                .firstWhere(
                  (c) => c.method == 'vision#startDigitalInkRecognizer',
                )
                .arguments
            as Map;

    final times = [
      for (final stroke
          in ((args['ink'] as Map)['strokes'] as List).cast<Map>())
        for (final p in (stroke['points'] as List).cast<Map>()) p['t'] as int,
    ];

    expect(times, [0, 10, 120, 130]);
  });

  test('boş satır listesi kanala hiç gitmez', () async {
    mock();

    expect(await MlKitRecognizer().recognizeLines(const []), isEmpty);
    expect(calls, isEmpty);
  });

  test('tek satır okunamazsa tur devam eder', () async {
    var read = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'vision#manageInkModels') return true;
      read++;
      if (read == 1) throw PlatformException(code: 'error');
      return [
        {'text': 'Rapor yaz', 'score': 0.0},
      ];
    });

    final texts = await MlKitRecognizer().recognizeLines([
      oneStroke(),
      oneStroke(),
    ]);

    expect(texts, ['', 'Rapor yaz']);
  });
}
