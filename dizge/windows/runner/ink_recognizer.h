#ifndef RUNNER_INK_RECOGNIZER_H_
#define RUNNER_INK_RECOGNIZER_H_

#include <flutter/flutter_engine.h>
#include <windows.h>

// El yazısı tanıma köprüsü (A6).
//
// Dart tarafı `HandwritingRecognizer` arayüzünü görür; burası o arayüzün
// Windows'taki tek uygulaması. Windows'un kendi `InkAnalyzer`'ı (WinRT,
// Windows.UI.Input.Inking.Analysis) kullanılıyor: cihazda çalışır, ağ
// istemez, ek paket indirmez.
//
// Neden C++ tarafında: bu API'nin Flutter eklentisi yok. ML Kit Android'de
// var ama Windows'u hiç kapsamıyor ve birincil hedef Windows.
//
// **Tanıma bu makinede yoksa hata değil, "yok" yanıtı döner.** Uygulamanın
// ajanda modu tanımasız da uçtan uca çalışıyor (bkz.
// `lib/core/handwriting_recognizer.dart` → `UnavailableRecognizer`), bu yüzden
// buradaki her hata yolu sessizce o hâle düşer; çökme yok.

// Kanalı motora bağlar. `window`, tanıma bittiğinde yanıtın platform
// iş parçacığına geri taşınması için gerekli (aşağıdaki nota bak).
void RegisterInkRecognizer(flutter::FlutterEngine* engine, HWND window);

// Arka plandaki tanıma işi bitince pencereye yollanan mesaj.
//
// Neden mesaj: `AnalyzeAsync` bloke edilerek beklenemez — runner iş parçacığı
// STA olarak başlatılıyor ve orada beklemek mesaj pompasını kilitler. İş ayrı
// bir iş parçacığında yapılıp sonuç kuyruğa konuyor, sonra bu mesajla platform
// iş parçacığına dönülüyor; kanal yanıtı yalnız orada veriliyor.
constexpr UINT kInkRecognitionDoneMessage = WM_APP + 0x1A;

// Kuyruktaki tamamlanmış işleri yanıtlar. Yalnız platform iş parçacığından,
// yani pencere mesaj işleyicisinden çağrılır.
void DrainInkRecognitionResults();

#endif  // RUNNER_INK_RECOGNIZER_H_
