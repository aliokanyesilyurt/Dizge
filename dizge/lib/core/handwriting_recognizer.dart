import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ink_lines.dart';

/// Motorun o anki hâli.
///
/// A5'te bu bir `bool`du (`isAvailable`) ve iki hâl yetiyordu: ya tanıma var
/// ya yok. A7 üçüncü bir hâl getirdi — **hazırlanıyor**: ML Kit'in Türkçe
/// modeli ilk kullanımda iniyor. Bunu "yok"a katmak yalan olurdu; kullanıcı
/// tanımanın kapalı olduğunu sanıp bir daha denemezdi.
enum RecognizerState {
  /// Tanıma çalışıyor.
  ready,

  /// Henüz değil ama olacak — model iniyor ya da yerel taraf sorulmadı.
  /// Arayüz beklemeyi anlatır, "kapalı" demez.
  preparing,

  /// Bu cihazda tanıma yok. Bir hata değil, **normal bir hâl**.
  unavailable,
}

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
  /// Bu cihazda tanımanın hâli.
  ///
  /// Yalnız "paket kurulu mu" değil: Windows'ta el yazısı dil paketi eksikse
  /// [RecognizerState.unavailable], Android'de model henüz inmediyse
  /// [RecognizerState.preparing] döner.
  ///
  /// Eşzamanlı olması bilinçli — arayüz altyazısı her karede okunuyor.
  /// Değeri değiştiren iş [warmUp] içinde yapılır.
  RecognizerState get state;

  /// Motoru sorup/hazırlayıp [state]'i yerine oturtur.
  ///
  /// **Idempotent olmak zorunda:** hem açılışta (bootstrap) hem onay şeridi
  /// açılırken çağrılıyor. İkinci çağrı modeli ikinci kez indirmemeli.
  Future<void> warmUp();

  /// Her satır için bir metin döndürür — **girdiyle aynı uzunlukta**.
  ///
  /// Uzunluk sözü bilinçli: çağıran taraf satırları ekranda zaten çizmiş
  /// durumda ve i'inci öneriyi i'inci satırın yanına koyuyor. Motor bir satırı
  /// okuyamazsa o satır için boş dize döner, listeden düşmez — yoksa öneriler
  /// yazının hizasından kayar.
  Future<List<String>> recognizeLines(List<InkLine> lines);
}

/// [RecognizerState]'in çağıranların çoğuna yeten kısaltması.
///
/// Uzantı olması, üç motorun da bunu ayrı ayrı yazmasını engelliyor: hâl tek
/// yerde tanımlı, "hazır mı" sorusunun yanıtı tek yerden geliyor.
extension HandwritingRecognizerState on HandwritingRecognizer {
  bool get isAvailable => state == RecognizerState.ready;
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
  RecognizerState get state => RecognizerState.unavailable;

  @override
  Future<void> warmUp() async {}

  @override
  Future<List<String>> recognizeLines(List<InkLine> lines) async =>
      List.filled(lines.length, '');
}

/// O an kullanılacak motor.
///
/// Varsayılanı [UnavailableRecognizer] ve öyle kalıyor: platform seçimi
/// `bootstrap.dart`ta, yalnız çalışan uygulamada yapılıyor. Motor seçiminin
/// bir provider olması, testlerin sahte bir motoru araya sokabilmesi için de
/// gerekli.
final handwritingRecognizerProvider = Provider<HandwritingRecognizer>(
  (ref) => const UnavailableRecognizer(),
);
