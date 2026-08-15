import 'package:dizge/core/handwriting_recognizer.dart';
import 'package:dizge/core/ink_lines.dart';
import 'package:dizge/core/windows_ink_recognizer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A6 — Windows tanıma köprüsünün Dart yarısı.
///
/// Karşı taraf C++ ve gerçek bir kalem gerektiriyor; buradaki testler o yüzden
/// **sözleşmeyi** sınıyor: kanaldan ne gidiyor, ne dönüyor, hata hâlinde ne
/// oluyor. Tanımanın *doğruluğu* bu testlerin işi değil — o, elle bir tur
/// atmakla ölçülür.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dizge/ink');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Son çağrının argümanları — kanaldan ne gittiğini görmek için.
  MethodCall? lastCall;

  void mock(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      lastCall = call;
      return handler(call);
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    lastCall = null;
  });

  InkLine line(List<List<Offset>> strokes) =>
      InkLine(strokes, const Rect.fromLTWH(0, 0, 10, 10));

  test('vuruşlar düz sayı dizisi olarak gönderilir', () async {
    // Nokta başına liste açmak, uzun bir sayfada kanaldan geçen veriyi iki
    // katına çıkarıyordu; biçimin korunduğu buradan görülüyor.
    mock((_) => <String>['bir']);

    await WindowsInkRecognizer().recognizeLines([
      line([
        const [Offset(1, 2), Offset(3, 4)],
      ]),
    ]);

    expect(lastCall?.method, 'recognizeLines');
    final lines = (lastCall!.arguments as Map)['lines'] as List;
    expect(lines.single, [
      [1.0, 2.0, 3.0, 4.0],
    ]);
  });

  test('boş satır listesi kanala hiç gitmez', () async {
    var called = false;
    mock((_) {
      called = true;
      return <String>[];
    });

    expect(await WindowsInkRecognizer().recognizeLines(const []), isEmpty);
    expect(called, isFalse);
  });

  test('okunan metinler sırayla döner', () async {
    mock((_) => <String>['Süt al', 'Rapor yaz']);

    final texts = await WindowsInkRecognizer().recognizeLines([
      line([
        const [Offset.zero],
      ]),
      line([
        const [Offset.zero],
      ]),
    ]);

    expect(texts, ['Süt al', 'Rapor yaz']);
  });

  test('yerel taraf eksik döndürürse hiza bozulmaz', () async {
    // Arayüzün sözü: i'inci öneri i'inci satırın yanına gider. Yerel taraf
    // beklenmedik bir uzunluk verirse öneriler kaymaktansa tamamlanır.
    mock((_) => <String>['yalnız bir tane']);

    final texts = await WindowsInkRecognizer().recognizeLines([
      line([
        const [Offset.zero],
      ]),
      line([
        const [Offset.zero],
      ]),
      line([
        const [Offset.zero],
      ]),
    ]);

    expect(texts, ['yalnız bir tane', '', '']);
  });

  test('yerel taraf patlarsa boş metinler döner, hata sızmaz', () async {
    // Tanıma çökerse kullanıcının yazdığı sayfa da gitmemeli; başarısızlık
    // "okunamadı"ya iner ve başlık elle yazılır.
    mock((_) => throw PlatformException(code: 'boom'));

    final texts = await WindowsInkRecognizer().recognizeLines([
      line([
        const [Offset.zero],
      ]),
    ]);

    expect(texts, ['']);
  });

  test('kanal hiç yoksa motor kendini kapatır', () async {
    // Eski bir derlemede kanal kayıtlı olmayabilir. O zaman "tanıma yok"
    // durumuna düşmeli — her seferinde yeniden denemek yerine.
    messenger.setMockMethodCallHandler(channel, null);

    final recognizer = WindowsInkRecognizer();
    expect(
      recognizer.state,
      RecognizerState.ready,
      reason: 'ilk hâl iyimser: Windows tarafında beklenen bir indirme yok',
    );

    await recognizer.recognizeLines([
      line([
        const [Offset.zero],
      ]),
    ]);

    expect(recognizer.state, RecognizerState.unavailable);
  });

  test('warmUp yerel yanıtı saklar', () async {
    mock((call) => call.method == 'isAvailable' ? false : null);

    final recognizer = WindowsInkRecognizer();
    await recognizer.warmUp();

    expect(recognizer.state, RecognizerState.unavailable);
  });

  test('kurulu tanıyıcılar listelenir', () async {
    // A0'ın sorusunun yanıtı: bu makinede hangi diller kurulu.
    mock(
      (call) => call.method == 'recognizerNames'
          ? <String>['Microsoft Handwriting Recognizer - Turkish']
          : null,
    );

    expect(await WindowsInkRecognizer().recognizerNames(), [
      'Microsoft Handwriting Recognizer - Turkish',
    ]);
  });
}
