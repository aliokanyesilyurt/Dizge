import 'package:flutter/services.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;

import 'handwriting_recognizer.dart';
import 'ink_lines.dart';

/// Android'in el yazısı tanıması (A7): ML Kit Digital Ink.
///
/// Bu dosya **paketin tanındığı tek yer** — `windows_ink_recognizer.dart`ın
/// `MethodChannel`ı kendi içinde tuttuğu gibi. Uygulamanın geri kalanı yalnız
/// [HandwritingRecognizer] görüyor ve hangi motorun konuştuğunu bilmiyor.
///
/// ## Model cihaza iniyor, yazı cihazdan çıkmıyor
///
/// ML Kit'in Türkçe modeli ilk kullanımda indiriliyor (~20 MB), sonrası
/// tamamen çevrimdışı. Yani ağ bir kez gerekiyor, mürekkep hiçbir zaman
/// sunucuya gitmiyor — planın çevrimdışı-öncelik ilkesi korunuyor.
class MlKitRecognizer implements HandwritingRecognizer {
  MlKitRecognizer({
    mlkit.DigitalInkRecognizer? recognizer,
    mlkit.DigitalInkRecognizerModelManager? models,
  }) : _recognizer =
           recognizer ?? mlkit.DigitalInkRecognizer(languageCode: _language),
       _models = models ?? mlkit.DigitalInkRecognizerModelManager();

  /// BCP-47 etiketi. ML Kit'in taban modelleri arasında Türkçe `tr` olarak
  /// geçiyor; `tr-TR` gönderilirse model bulunamıyor.
  static const _language = 'tr';

  final mlkit.DigitalInkRecognizer _recognizer;
  final mlkit.DigitalInkRecognizerModelManager _models;

  RecognizerState _state = RecognizerState.preparing;
  Future<void>? _warming;

  /// İlk hâl [RecognizerState.preparing]: model inmiş mi bilmiyoruz.
  ///
  /// Windows'un iyimserliği burada yanlış olurdu — orada beklenen bir şey yok,
  /// burada indirilecek bir model var. `ready` diye başlasaydık arayüz "okudum"
  /// diyip boş öneriler gösterirdi; `unavailable` diye başlasaydık kullanıcı
  /// tanımanın kapalı olduğunu sanırdı.
  @override
  RecognizerState get state => _state;

  /// Model yoksa indirir. İkinci çağrı aynı [Future]'a biner — bootstrap ve
  /// onay şeridi ikisi de çağırıyor, model iki kez inmemeli.
  @override
  Future<void> warmUp() => _warming ??= _prepare();

  Future<void> _prepare() async {
    try {
      if (await _models.isModelDownloaded(_language)) {
        _state = RecognizerState.ready;
        return;
      }

      // Wi-Fi şartı **bilinçli olarak kapalı**. Varsayılan `true`, kablosuz ağa
      // hiç bağlanmayan bir telefonda tanımayı kalıcı olarak "hazırlanıyor"
      // hâlinde bırakırdı. Kullanıcı ajanda modunu açarak zaten bu işi istedi;
      // indirme bir kereliğine ve tek seferlik.
      final ok = await _models.downloadModel(_language, isWifiRequired: false);
      _state = ok ? RecognizerState.ready : RecognizerState.unavailable;
    } on PlatformException {
      // Ağ yok, yer yok ya da Play Services eksik. Hepsinin karşılığı aynı:
      // tanıma bu turda yok, ajanda çalışmaya devam ediyor.
      _state = RecognizerState.unavailable;
    } on MissingPluginException {
      // Bu platformda eklenti kayıtlı değil (masaüstü derlemesi). Bootstrap
      // zaten Android dışında bu motoru seçmiyor; yine de kilit atmıyoruz.
      _state = RecognizerState.unavailable;
    }
  }

  @override
  Future<List<String>> recognizeLines(List<InkLine> lines) async {
    if (lines.isEmpty) return const [];

    // Şerit doğrudan da açılabilir; model hazır değilse burada bekleriz.
    await warmUp();
    if (_state != RecognizerState.ready) return List.filled(lines.length, '');

    final texts = <String>[];
    for (final line in lines) {
      texts.add(await _recognizeLine(line));
    }
    return texts;
  }

  /// Satırlar **tek tek** gönderiliyor.
  ///
  /// ML Kit tek satır yazı için eğitilmiş; bir sayfanın tamamı tek çağrıda
  /// gönderilseydi geriye tek bir uzun cümle dönerdi. Ayırmayı zaten
  /// `ink_lines.dart` yaptı (plan §Ae); burada o ayrımı bozmuyoruz.
  Future<String> _recognizeLine(InkLine line) async {
    try {
      final candidates = await _recognizer.recognize(
        _inkOf(line),
        context: mlkit.DigitalInkRecognitionContext(
          // Yazı alanının ölçüsü tanımanın doğruluğunu artırıyor: motor harf
          // boyunu buradan kestiriyor.
          writingArea: mlkit.WritingArea(
            width: line.bounds.width,
            height: line.bounds.height,
          ),
        ),
      );

      // Adaylar en olasıdan başlayarak geliyor. Kullanıcıya alternatif
      // listesi sunmuyoruz: plan §Ab'nin sözü "düzenlenebilir tek öneri" —
      // beş aday arasından seçtirmek, düzeltmekten daha yorucu.
      return candidates.isEmpty ? '' : candidates.first.text;
    } on PlatformException {
      // Tek satırın okunamaması turu bitirmez: kalan satırlar denenmeye devam
      // eder ve bu satır boş öneri olarak hizasında kalır.
      return '';
    } on MissingPluginException {
      _state = RecognizerState.unavailable;
      return '';
    }
  }

  /// [InkLine]'ı ML Kit'in beklediği biçime çevirir.
  mlkit.Ink _inkOf(InkLine line) {
    final ink = mlkit.Ink();

    // Satır kendi köşesine taşınıyor: sayfanın altına yazılmış bir satır,
    // yazı alanı (yukarıdaki `writingArea`) satır kadarken 900 piksel aşağıda
    // duruyor gibi görünürdü.
    final dx = line.bounds.left;
    final dy = line.bounds.top;

    // Zaman damgası **uydurma**. `InkStroke` nokta zamanı saklamıyor: tuval
    // yalnız konum topluyor ve depoya da öyle yazılıyor. ML Kit `t` alanını
    // yazma hızından ipucu almak için kullanıyor; eşit aralıklı damgalar bu
    // ipucunu susturuyor ama tanımayı bozmuyor. Alternatifi — depo biçimini
    // değiştirip her noktaya zaman eklemek — eski sayfaları taşımayı gerektirir
    // ve kazancı belirsiz.
    var t = 0;
    for (final stroke in line.strokes) {
      final s = mlkit.Stroke();
      for (final p in stroke) {
        s.points.add(mlkit.StrokePoint(x: p.dx - dx, y: p.dy - dy, t: t));
        t += _msPerPoint;
      }
      ink.strokes.add(s);
      t += _msBetweenStrokes;
    }

    return ink;
  }

  static const _msPerPoint = 10;
  static const _msBetweenStrokes = 100;

  /// Yerel kaynakları bırakır. Uygulama ömrü boyunca tek motor yaşıyor;
  /// bu yüzden yalnız testlerin ve ileride mod değişiminin işine yarar.
  Future<void> close() => _recognizer.close();
}
