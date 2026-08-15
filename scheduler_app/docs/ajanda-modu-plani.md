# Ajanda Modu Planı — Kalem, Kâğıt ve Yazının Tanınması

**Durum:** onay bekliyor
**Tarih:** 15 Ağustos 2026
**Önceki:** `gorunum-cilasi-plani.md` (ölçekler oturdu), `ana-ekran-plani.md`
**Önkoşul:** A0'ın sonucu. Bu planın gövdesi, el yazısı tanımanın iki hedef
platformda gerçekten çalıştığının kanıtlanmasına bağlı (§4).

---

## 1. İstenen

Uygulamada bir **kullanım modu** seçilebilsin. Ajanda modunda görev yazma
yerleri kalem-kâğıt gibi çalışsın: kullanıcı elle yazsın, uygulama **yazılan
görevleri algılasın**. Samsung Notes'a benzeyen bu ajanda hâli dursun,
uygulamanın kalan kısmı da dursun — biri diğerinin yerine geçmesin.

---

## 2. Bugün ne var (doğrulandı)

Bu iş sıfırdan başlamıyor; parçaların üçte biri zaten yerinde.

| Ne | Nerede | Durum |
|---|---|---|
| Çizim tuvali | `widgets/drawing_canvas.dart` | Parmak/kalem ile yazma çalışıyor, geri al + temizle var |
| Çizim verisi | `models/task.dart` → `Sketch` | Vuruşlar, boyut ve renk; JSON'a yazılıp okunuyor |
| Çizimin bugünkü yeri | `task_editor_sheet.dart:791` | Görevin **eki** olarak; başlık hâlâ klavyeyle yazılıyor |
| Tercih saklama idiomu | `core/theme_mode_controller.dart` | `StateNotifier` + `LocalStore`, ilk karede hazır |
| Görev yazma kapıları | `showQuickAdd` ve `showTaskEditor` | **Yalnız iki tane** — on çağrı yeri bu ikisine iniyor |

**Kritik bulgu — mod, uygulamanın çatalı değil, iki kapının davranışı.**
Görev oluşturmanın tüm yolları `showQuickAdd` ve `showTaskEditor`'dan geçiyor.
Ajanda modunun ekranları tek tek değiştirmesi gerekmiyor; bu iki kapıyı
değiştirmesi yetiyor. "Ajanda hâli de dursun, kalanı da dursun" isteği bu
yüzden mimari olarak ucuz.

**Eksik olan tek şey tanıma.** Yazıyı yakalıyoruz, saklıyoruz, çiziyoruz —
ama okumuyoruz.

---

## 3. Karar Aa — Tanıma, bu planın **riski**; gerisi işçilik

Dürüst olmak gerekirse bu planın zorluğu ajanda arayüzünde değil. Ajanda
sayfası, mod anahtarı, çizgili kâğıt görünümü — hepsi bilinen iş. Tek gerçek
soru şu: **el yazısı Türkçe metne, iki hedef platformda, çevrimdışı olarak
çevrilebiliyor mu?**

Bilinenler:

| Yol | Windows | Android | Çevrimdışı | Not |
|---|---|---|---|---|
| **ML Kit Digital Ink** (`google_mlkit_digital_ink_recognition`) | ❌ **yok** | ✅ | ✅ (model indirildikten sonra) | Google'ın tüm ML Kit Flutter eklentileri yalnız Android/iOS |
| **Windows Ink Analysis** (WinRT `InkAnalyzer`) | ✅ | ❌ | ✅ | Flutter eklentisi **yok**; `windows/runner` içine C++ kanal yazılmalı |
| Bulut OCR | ✅ | ✅ | ❌ | Çevrimdışı-öncelik ilkesini kırar, anahtar ve para ister |
| Saf Dart model (ONNX/TFLite) | ✅ | ✅ | ✅ | Türkçe el yazısı için model eğitmek bir araştırma işi, bir dilim değil |

Birincil hedef **Windows** ve ML Kit orada yok. Bulut, uygulamanın çevrimdışı
kimliğini bozar. Geriye tek gerçekçi bileşim kalıyor:

> **Windows'ta `InkAnalyzer`, Android'de ML Kit — tek arayüzün arkasında.**

`google-giris-plani.md` §G8a'da "iki platform iki akış" bilinçli olarak
reddedilmişti. Burada aynı kaçış yolu **yok**: Windows'u kapsayan tek bir yol
mevcut değil. Bedeli kabul ediyoruz ama sınırlıyoruz — ayrışma tek bir
arayüzün altında kalır (§Ac) ve uygulamanın geri kalanı hangi motorun
konuştuğunu bilmez.

### A0 bir **kanıt dilimi**, özellik değil

Yukarıdaki tablonun iki satırı doğrulanmadan gerisi yazılmamalı:

1. Windows `InkAnalyzer` **Türkçe** el yazısını tanıyor mu? (Tanıma dil
   paketleri kuruluma bağlı — sende kurulu mu, kurulu değilse kullanıcıdan
   ne isteyeceğiz?)
2. ML Kit Digital Ink'in Türkçe modeli sideload edilen APK'da iniyor mu?

A0 bunları tek bir atma-kodu ile ölçer ve sonucu buraya yazar. **A0 olumsuz
çıkarsa bu planın gövdesi değişir** — o hâlde ajanda modu tanımasız da
anlamlıdır (§Ad'nin geri çekilme hâli), ama bunu bilerek seçmiş oluruz.

---

## 4. Karar Ab — Tanıma asla sessizce görev oluşturmaz

El yazısı tanıma, en iyi hâlinde bile yanılır. "Salı toplantı" yerine "Sali
toplant" üreten bir motor, sessizce görev yaratırsa kullanıcı ajandasına
güvenmeyi bırakır.

Karar: tanıma sonucu **düzenlenebilir bir öneri**dir. Akış şöyle:

```
yazı → satırlara ayır → her satır bir aday → onay şeridi → görev
```

Onay şeridinde tanınan metin bir girdi alanında durur; kullanıcı düzeltir,
kabul eder ya da yok sayar. **Mürekkep her hâlükârda saklanır** — görev
oluşsun ya da oluşmasın, yazdığı şey kaybolmaz. Ajanda önce bir defterdir,
sonra bir girdi yöntemi.

## 5. Karar Ac — Tek arayüz, iki motor, üçüncü bir "yok" hâli

```dart
abstract interface class HandwritingRecognizer {
  bool get isAvailable;
  Future<List<RecognizedLine>> recognize(List<List<Offset>> strokes, Size size);
}
```

Üç uygulaması olur: `WindowsInkRecognizer`, `MlKitRecognizer` ve
`UnavailableRecognizer`. Sonuncusu bir yedek değil, **birinci sınıf bir
durum**: tanıma yoksa ajanda modu çalışmaya devam eder, yalnız onay şeridi
"tanıma bu cihazda kapalı — başlığı yazarak ekle" der. Böylece masaüstü
derlemesi dil paketi olmayan bir makinede de açılır.

Uygulamanın geri kalanı `Sketch`'i ve `RecognizedLine`'ı görür; hangi motorun
konuştuğunu bilmez. `supabase_flutter`'ın üç dosyayla sınırlanması gibi, motor
paketleri de yalnız kendi dosyalarında tanınır.

## 6. Karar Ad — Ajanda bir **sayfa**, görev alanı değil

İki tasarım mümkündü:

* **(i)** Var olan görev sheet'lerinin başlık alanını tuvale çevirmek.
* **(ii)** Güne ait, kenardan kenara bir **ajanda sayfası** açmak; görevler o
  sayfadan çıkmak.

(i) küçük bir iş ama istenen şey değil: "kalem kâğıt kullanılan bir ajanda"
bir metin kutusunun yerine geçen tuval değil, üstüne serbestçe yazılan bir
yaprak. Ayrıca (i), Samsung Notes benzerliğini hiç vermez.

Karar: **(ii)**. Yeni bir varlık gelir — `AgendaPage`: bir güne (veya haftaya)
bağlı, kendi vuruşlarını taşıyan sayfa. `Sketch` yapısı yeniden kullanılır;
depolama `Task`/`Habit` ile aynı yoldan (`LocalStore` → Hive kutusu) gider,
böylece ileride senkron aynı kapıdan geçebilir.

Mod seçimi üç değerdir:

| Mod | Ne yapar |
|---|---|
| `klasik` | Bugünkü davranış. Ajanda sekmesi görünmez. |
| `ajanda` | Görev yazma kapıları önce ajanda sayfasını açar; klavye bir tık uzakta. |
| `karma` | İkisi de erişilebilir; kullanıcı her seferinde seçer. **Varsayılan.** |

Varsayılanın `karma` olması bilinçli: mevcut kullanıcının alışkanlığı bozulmaz,
yeni yol keşfedilebilir kalır.

## 7. Karar Ae — Satırlara ayırma bizim işimiz, tanıma motorunun değil

Bir ajanda sayfasında beş görev yazılıysa motora tek bir yığın vuruş
gönderilirse tek bir uzun cümle döner. Vuruşları satırlara ayırmak (dikey
kümeleme) bize düşer ve **motordan bağımsızdır** — yani saf Dart, test
edilebilir ve iki platformda da aynı.

Bu, planın en kolay test edilen parçası: girdi vuruş listesi, çıktı satır
listesi, arada ne ML Kit ne WinRT var.

---

## 8. Dilimler

### A0 — Kanıt: tanıma iki platformda Türkçe okuyor mu

Atma kodu. Windows'ta küçük bir C++ kanalı + `InkAnalyzer` çağrısı; Android'de
ML Kit paketiyle tek ekranlık deneme. Sonuç bu belgeye yazılır.

**Bitti sayılır:** iki platformda da elle yazılmış "Salı toplantı" cümlesi için
dönen metin buraya kaydedilmiş; Türkçe karakterlerin (ı, ş, ğ, ü, ö, ç)
durumu not edilmiş. Kod **atılır**, yalnız bulgu kalır.

### A1 — Satır ayırma (motorsuz, saf Dart)

`core/ink_lines.dart`: vuruş listesini satırlara kümeleyen işlev.

**Bitti sayılır:** birim testleri — üst üste üç satır yazı üç satıra ayrılır;
bir satırdaki noktalı harfler (i, ı, j) kendi satırında kalır; boş sayfa boş
liste döner.

### A2 — Mod tercihi

`core/usage_mode_controller.dart`, `ThemeModeController` ile birebir aynı
kalıpta. Hesap ekranına üç seçenekli bir alan.

**Bitti sayılır:** seçim yeniden başlatmaya dayanıyor; widget testi üç modda
da kapıların doğru davrandığını gösteriyor.

### A3 — `AgendaPage` modeli ve deposu

Güne bağlı sayfa; `Sketch`'in yeniden kullanımı; `LocalStore` üzerinden
kalıcılık; migration numarası sıradaki değeri alır.

**Bitti sayılır:** sayfa yazılıp okunuyor, uygulama kapanıp açıldığında
mürekkep yerinde; kalıcılık testi yeşil.

### A4 — Ajanda yüzeyi

Çizgili kâğıt görünümü, kalem/silgi, geri al, sayfa gezinme (gün ileri/geri).
`DrawingCanvas` genişletilir; ölçekler (`S`, `T`, `I`) ve palet olduğu gibi
kullanılır.

**Bitti sayılır:** Windows derlemesinde elle bir sayfa yazılıp kapatılıyor,
tekrar açıldığında aynı görünüyor.

### A5 — Tanıma arayüzü ve `UnavailableRecognizer`

Arayüz, veri tipleri ve "tanıma yok" hâli. **Hiçbir motor bağlanmadan.**

**Bitti sayılır:** ajanda modu uçtan uca çalışıyor; onay şeridi "tanıma bu
cihazda kapalı" diyor ve kullanıcı başlığı yazarak görev oluşturabiliyor.

### A6 — Windows motoru

`InkAnalyzer` kanalı, `windows/runner` içinde.

**Bitti sayılır:** derlenmiş exe'de elle yazılan üç satır, üç aday olarak onay
şeridine düşüyor.

### A7 — Android motoru

ML Kit paketi, model indirme akışı (ilk kullanımda indirilir, sonrası
çevrimdışı).

**Bitti sayılır:** sideload edilen APK'da aynı tur; model yokken uygulama
çökmüyor, "model indiriliyor" diyor.

### A8 — Onay şeridi ve görev oluşturma

Adaylar → düzenlenebilir öneriler → `Task`. Mürekkebin sayfada kalması.

**Bitti sayılır:** bir sayfadan üç görev oluşturuluyor, sayfa hâlâ yazıldığı
gibi duruyor, oluşan görevler haftalık ızgarada görünüyor.

---

## 9. Kapsam Dışı

Ajanda sayfalarının senkronu (önce yerelde otursun), el yazısı arama, yazının
düzleştirilmesi/güzelleştirilmesi, şekil tanıma, PDF dışa aktarma, iOS/macOS/
web (bu depoda zaten hedef değil), basınç ve eğim duyarlı fırça, sayfa
şablonları (kareli/noktalı).

---

## 10. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| Windows'ta Türkçe el yazısı tanıma dil paketi yok/zayıf | **Yüksek** | A0 tam bu risk için önde duruyor; olumsuzsa A6 düşer ve `UnavailableRecognizer` Windows'un kalıcı hâli olur |
| Tanıma doğruluğu düşük, kullanıcı güveni kırılır | **Yüksek** | Ab: sonuç asla sessizce görev olmaz, hep düzenlenebilir öneri; mürekkep her zaman saklanır |
| C++ kanalı Windows derlemesini kırılgan yapar | Orta | A6 en sona yakın; ondan önce her şey çalışıyor olacak, kanal düşerse yalnız tanıma düşer |
| İki motor iki hata yüzeyi (G8a'nın reddettiği durum) | **Kesin** | Kabul edilen bedel — Windows'u kapsayan tek yol yok. Ayrışma tek arayüzün altında tutuluyor |
| Ajanda sayfaları depoyu şişirir | Orta | Vuruşlar nokta listesi olarak saklanıyor; A3'te sayfa başına boyut ölçülecek |
| Kapsam büyük, tek oturumda bitmez | **Kesin** | Dokuz dilim; A0–A5 tanımasız da işe yarar bir ajanda verir |

---

## 11. Sıra

A0 → A1 → A2 → A3 → A4 → A5 → A8 → A6 → A7.

A0 kapıda duruyor: sonucu planın gövdesini değiştirebilir. A8'in motorlardan
**önce** gelmesi bilinçli — onay şeridi `UnavailableRecognizer` ile de
çalışabilmeli, yoksa motorlar olmadan hiçbir şey denenemez. A6 ve A7 en sonda:
ikisi de düşse elde çalışan bir ajanda kalır.
