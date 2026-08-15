import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ink_lines.dart';

/// El yazısını metne çeviren motorun sözleşmesi (A5).
///
/// ## Neden arayüz
///
/// Windows'ta `InkAnalyzer`, Android'de ML Kit — tek bir yol iki platformu
/// birden kapsamıyor (plan §Aa). `google-giris-plani.md` §G8a'da "iki platform
/// iki akış" bilinçle reddedilmişti; burada aynı kaçış yolu yok. Bedeli
/// **tek bir arayüzün altına hapsediyoruz**: uygulamanın geri kalanı hangi
/// motorun konuştuğunu bilmez, yalnız satır girip metin alır.
///
/// ## Satırlara ayırmak motorun işi değil
///
/// Girdi [InkLine] listesi, ham vuruş yığını değil. Bir sayfaya beş görev
/// yazılmışsa motora tek yığın gönderilirse tek bir uzun cümle döner. Ayırma
/// `core/ink_lines.dart`'ta, saf Dart olarak ve motordan bağımsız yapılıyor.
abstract interface class HandwritingRecognizer {
  /// Bu cihazda tanıma yapılabiliyor mu.
  ///
  /// Yalnız "paket kurulu mu" değil: Windows'ta el yazısı dil paketi eksikse
  /// ya da Android'de model henüz inmediyse de `false` döner. Arayüz bu
  /// durumu bir hata olarak değil, **normal bir hâl** olarak taşır.
  bool get isAvailable;

  /// Her satır için bir metin döndürür — **girdiyle aynı uzunlukta**.
  ///
  /// Uzunluk sözü bilinçli: çağıran taraf satırları ekranda zaten çizmiş
  /// durumda ve i'inci öneriyi i'inci satırın yanına koyuyor. Motor bir satırı
  /// okuyamazsa o satır için boş dize döner, listeden düşmez — yoksa öneriler
  /// yazının hizasından kayar.
  Future<List<String>> recognizeLines(List<InkLine> lines);
}

/// Tanımanın olmadığı hâl — bir yedek değil, **birinci sınıf bir durum**.
///
/// Ajanda modu bu motorla da uçtan uca çalışır: kullanıcı yazar, satırlar
/// ayrılır, onay şeridi açılır ve başlıklar klavyeyle tamamlanır. Böylece
/// masaüstü derlemesi el yazısı dil paketi olmayan bir makinede de açılır ve
/// hiçbir ekran "yakında" demez.
class UnavailableRecognizer implements HandwritingRecognizer {
  const UnavailableRecognizer();

  @override
  bool get isAvailable => false;

  @override
  Future<List<String>> recognizeLines(List<InkLine> lines) async =>
      List.filled(lines.length, '');
}

/// O an kullanılacak motor.
///
/// Bugün her platformda [UnavailableRecognizer]; A6 (Windows) ve A7 (Android)
/// bu tek satırı değiştirecek. Motor seçiminin bir provider olması, testlerin
/// sahte bir motoru araya sokabilmesi için de gerekli.
final handwritingRecognizerProvider = Provider<HandwritingRecognizer>(
  (ref) => const UnavailableRecognizer(),
);
