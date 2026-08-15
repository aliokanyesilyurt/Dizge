import 'package:flutter/services.dart';

import 'handwriting_recognizer.dart';
import 'ink_lines.dart';

/// Windows'un kendi el yazısı tanıması (A6).
///
/// Karşı taraf `windows/runner/ink_recognizer.cpp`: WinRT `InkAnalyzer`.
/// Cihazda çalışır, ağ istemez, ek model indirmez.
///
/// Bu dosya **paketin tanındığı tek yer**. `supabase_flutter`'ın üç dosyayla
/// sınırlanması gibi, platform kanalı da burada kalıyor; uygulamanın geri
/// kalanı yalnız [HandwritingRecognizer] görüyor ve hangi motorun konuştuğunu
/// bilmiyor.
class WindowsInkRecognizer implements HandwritingRecognizer {
  WindowsInkRecognizer({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dizge/ink');

  final MethodChannel _channel;

  /// Yerel taraf bir kez soruluyor ve yanıt saklanıyor: bu, uygulamanın
  /// ömrü boyunca değişmeyen bir makine özelliği.
  bool? _available;

  /// Kurulu el yazısı tanıyıcılarının adları (örn. "Microsoft Handwriting
  /// Recognizer - Turkish").
  ///
  /// Planın A0 sorusunun yanıtı burada: "bu makinede Türkçe tanınıyor mu?"
  /// Atma kodla bir kez ölçüp not etmek yerine uygulamanın kendisi söylüyor —
  /// böylece başka bir makinede de doğru yanıtı veriyor.
  Future<List<String>> recognizerNames() async {
    try {
      final names = await _channel.invokeListMethod<String>('recognizerNames');
      return names ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Yerel tarafa sorup sonucu saklar. [isAvailable] eşzamanlı olmak zorunda
  /// (arayüzün sözü), bu yüzden ilk yanıt gelene kadar **iyimser** davranıyoruz:
  /// tanıma denenir, olmazsa boş metin döner ve kullanıcı başlığı yazar.
  /// Kötümser başlamak, çalışan bir makinede tanımayı ilk açılışta gereksiz
  /// yere kapatırdı.
  Future<void> warmUp() async {
    try {
      _available = await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      _available = false;
    } on MissingPluginException {
      _available = false;
    }
  }

  @override
  bool get isAvailable => _available ?? true;

  @override
  Future<List<String>> recognizeLines(List<InkLine> lines) async {
    if (lines.isEmpty) return const [];

    try {
      final texts = await _channel.invokeListMethod<String>('recognizeLines', {
        'lines': [
          for (final line in lines)
            [
              for (final stroke in line.strokes)
                <double>[
                  // Yerel taraf düz sayı dizisi bekliyor: [x1,y1,x2,y2,…].
                  // Nokta başına liste açmak, uzun bir sayfada kanaldan geçen
                  // veriyi iki katına çıkarıyordu.
                  for (final p in stroke) ...[p.dx, p.dy],
                ],
            ],
        ],
      });

      if (texts == null) return List.filled(lines.length, '');

      // Uzunluk sözü arayüzün sözü: i'inci öneri i'inci satırın yanına
      // gidiyor. Yerel taraf beklenmedik bir uzunluk döndürürse hizayı
      // bozmaktansa tamamlıyoruz.
      if (texts.length != lines.length) {
        return [
          for (var i = 0; i < lines.length; i++)
            i < texts.length ? texts[i] : '',
        ];
      }
      return texts;
    } on PlatformException {
      return List.filled(lines.length, '');
    } on MissingPluginException {
      // Kanal hiç kayıtlı değil (örneğin eski bir derleme). Tanıma yok
      // demektir; ajanda çalışmaya devam eder.
      _available = false;
      return List.filled(lines.length, '');
    }
  }
}
