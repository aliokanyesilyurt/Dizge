#include "ink_recognizer.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <vector>

#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.Input.Inking.Analysis.h>
#include <winrt/Windows.UI.Input.Inking.h>
#include <winrt/base.h>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr char kChannelName[] = "dizge/ink";

using MethodResultPtr =
    std::unique_ptr<flutter::MethodResult<EncodableValue>>;

// Tamamlanmış bir iş: yanıtlanacak çağrı ve üretilen metinler.
struct CompletedJob {
  MethodResultPtr result;
  std::vector<std::string> texts;
  bool failed = false;
};

std::mutex g_mutex;
std::queue<CompletedJob> g_done;
HWND g_window = nullptr;

// --- WinRT yardımcıları ----------------------------------------------------

std::string ToUtf8(const winrt::hstring& value) {
  if (value.empty()) return {};

  const int size = ::WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};

  std::string out(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                        static_cast<int>(value.size()), out.data(), size,
                        nullptr, nullptr);
  return out;
}

// Tek bir satırın vuruşlarını çözümleyip okunan metni döndürür.
//
// Her satır **kendi çözümleyicisinde** analiz ediliyor. Tek bir çözümleyiciye
// bütün sayfayı vermek daha ucuz olurdu ama satır eşleşmesi kaybolurdu: Dart
// tarafı i'inci öneriyi i'inci satırın yanına koyuyor ve bu hizanın bozulmaması
// arayüzün sözü (bkz. `HandwritingRecognizer.recognizeLines`).
std::string RecognizeOneLine(
    const std::vector<std::vector<winrt::Windows::Foundation::Numerics::float2>>&
        strokes) {
  using namespace winrt::Windows::UI::Input::Inking;
  using namespace winrt::Windows::UI::Input::Inking::Analysis;

  if (strokes.empty()) return {};

  InkStrokeBuilder builder;
  InkAnalyzer analyzer;
  bool added = false;

  for (const auto& points : strokes) {
    if (points.size() < 1) continue;

    std::vector<InkPoint> ink_points;
    ink_points.reserve(points.size());
    for (const auto& p : points) {
      ink_points.push_back(InkPoint(p, 0.5f));
    }

    auto stroke = builder.CreateStrokeFromInkPoints(
        winrt::single_threaded_vector(std::move(ink_points)).GetView(),
        winrt::Windows::Foundation::Numerics::float3x2::identity());
    analyzer.AddDataForStroke(stroke);
    added = true;
  }

  if (!added) return {};

  // Yalnız yazıyla ilgileniyoruz; çizim/şekil çözümlemesi bu ekranın işi değil.
  analyzer.SetStrokeDataKind(analyzer.AnalysisRoot().Id(),
                             InkAnalysisStrokeKind::Writing);

  auto status = analyzer.AnalyzeAsync().get();
  if (status.Status() != InkAnalysisStatus::Updated) return {};

  // Satır düğümlerinin okunan metni. Birden çok satır düğümü çıkarsa (kullanıcı
  // eğik yazmış olabilir) boşlukla birleştiriliyor — bölmüyoruz, çünkü satır
  // sayısı Dart tarafında zaten belirlenmiş durumda.
  // `FindNodes` ara arayüzü (`IInkAnalysisNode`) döndürüyor ve okunan metin
  // orada yok — somut `InkAnalysisLine` üzerinde. Dönüşüm başarısız olursa
  // (beklenmedik bir düğüm türü) o düğüm atlanıyor.
  std::string text;
  auto lines = analyzer.AnalysisRoot().FindNodes(InkAnalysisNodeKind::Line);
  for (uint32_t i = 0; i < lines.Size(); i++) {
    auto line = lines.GetAt(i).try_as<InkAnalysisLine>();
    if (!line) continue;

    auto part = ToUtf8(line.RecognizedText());
    if (part.empty()) continue;
    if (!text.empty()) text += " ";
    text += part;
  }

  return text;
}

// Kurulu el yazısı tanıyıcılarının adları.
//
// A0'ın sorusu buydu: "bu makinede Türkçe el yazısı tanınıyor mu?" Atma kodla
// bir kez ölçüp not etmek yerine, yanıtı uygulamanın kendisi söylüyor —
// böylece başka bir makinede de doğru yanıtı veriyor.
std::vector<std::string> RecognizerNames() {
  std::vector<std::string> names;
  try {
    winrt::Windows::UI::Input::Inking::InkRecognizerContainer container;
    auto recognizers = container.GetRecognizers();
    for (uint32_t i = 0; i < recognizers.Size(); i++) {
      names.push_back(ToUtf8(recognizers.GetAt(i).Name()));
    }
  } catch (...) {
    // Kurulu tanıyıcı listesi alınamadıysa liste boş kalır; bu bir hata değil,
    // "bilmiyoruz" demek.
  }
  return names;
}

bool InkAnalysisAvailable() {
  try {
    winrt::Windows::UI::Input::Inking::Analysis::InkAnalyzer probe;
    (void)probe;
    return true;
  } catch (...) {
    return false;
  }
}

// --- Çağrı gövdesinin çözülmesi --------------------------------------------

// Beklenen biçim: satırların listesi; her satır vuruşların listesi; her vuruş
// düz bir `[x1, y1, x2, y2, ...]` dizisi.
bool ParseLines(
    const EncodableValue* args,
    std::vector<
        std::vector<std::vector<winrt::Windows::Foundation::Numerics::float2>>>*
        out) {
  const auto* map = std::get_if<EncodableMap>(args);
  if (!map) return false;

  auto it = map->find(EncodableValue("lines"));
  if (it == map->end()) return false;

  const auto* lines = std::get_if<EncodableList>(&it->second);
  if (!lines) return false;

  for (const auto& raw_line : *lines) {
    const auto* strokes = std::get_if<EncodableList>(&raw_line);
    if (!strokes) return false;

    std::vector<std::vector<winrt::Windows::Foundation::Numerics::float2>> line;
    for (const auto& raw_stroke : *strokes) {
      const auto* flat = std::get_if<std::vector<double>>(&raw_stroke);
      if (!flat) return false;

      std::vector<winrt::Windows::Foundation::Numerics::float2> points;
      points.reserve(flat->size() / 2);
      for (size_t i = 0; i + 1 < flat->size(); i += 2) {
        points.push_back({static_cast<float>((*flat)[i]),
                          static_cast<float>((*flat)[i + 1])});
      }
      line.push_back(std::move(points));
    }
    out->push_back(std::move(line));
  }
  return true;
}

void PushDone(CompletedJob job) {
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_done.push(std::move(job));
  }
  if (g_window) {
    ::PostMessage(g_window, kInkRecognitionDoneMessage, 0, 0);
  }
}

void HandleCall(const flutter::MethodCall<EncodableValue>& call,
                MethodResultPtr result) {
  if (call.method_name() == "isAvailable") {
    result->Success(EncodableValue(InkAnalysisAvailable()));
    return;
  }

  if (call.method_name() == "recognizerNames") {
    EncodableList names;
    for (const auto& name : RecognizerNames()) {
      names.push_back(EncodableValue(name));
    }
    result->Success(EncodableValue(names));
    return;
  }

  if (call.method_name() != "recognizeLines") {
    result->NotImplemented();
    return;
  }

  std::vector<
      std::vector<std::vector<winrt::Windows::Foundation::Numerics::float2>>>
      lines;
  if (!ParseLines(call.arguments(), &lines)) {
    result->Error("bad_args", "Satır listesi çözülemedi");
    return;
  }

  // Asıl iş ayrı bir iş parçacığında: `AnalyzeAsync().get()` burada
  // beklenirse STA mesaj pompası kilitlenir ve pencere donar.
  //
  // Yanıt nesnesi doğrudan taşınıyor (kopyalanamaz); iş bitince kuyruğa
  // konuluyor ve yanıt **yalnız** platform iş parçacığında veriliyor.
  std::thread(
      [lines = std::move(lines), result = std::move(result)]() mutable {
        std::vector<std::string> texts;

        try {
          winrt::init_apartment(winrt::apartment_type::multi_threaded);
          for (const auto& line : lines) {
            texts.push_back(RecognizeOneLine(line));
          }
        } catch (...) {
          // Tanıma bu makinede yoksa ya da API patlarsa: boş metinler. Dart
          // tarafı bunu "okunamadı" olarak gösterir ve kullanıcı başlığı
          // kendisi yazar. Çökmek, yazdığı sayfayı da götürürdü.
          texts.assign(lines.size(), std::string());
        }

        CompletedJob done;
        done.result = std::move(result);
        done.texts = std::move(texts);
        PushDone(std::move(done));
      })
      .detach();
}

}  // namespace

void RegisterInkRecognizer(flutter::FlutterEngine* engine, HWND window) {
  g_window = window;

  auto channel = std::make_shared<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         MethodResultPtr result) { HandleCall(call, std::move(result)); });

  // Kanal, motor yaşadığı sürece yaşamalı; kaydı yapan kapsam bitince
  // yok olmasın diye burada tutuluyor.
  static std::shared_ptr<flutter::MethodChannel<EncodableValue>> kept;
  kept = channel;
}

void DrainInkRecognitionResults() {
  for (;;) {
    CompletedJob job;
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      if (g_done.empty()) return;
      job = std::move(g_done.front());
      g_done.pop();
    }

    if (!job.result) continue;

    EncodableList texts;
    for (const auto& text : job.texts) {
      texts.push_back(EncodableValue(text));
    }
    job.result->Success(EncodableValue(texts));
  }
}
