# Modülerlik planı — şişmiş dosyaları sökmek

> Durum: **uygulanıyor**. M1 bitti; M2–M4 sırada.

## 1. İstenen

İki dosya bin beş yüz satırı geçti. Bir özelliği değiştirmek için o dosyanın
tamamında gezmek gerekiyor, çakışma riski yüksek ve yeni bir bölüm eklemek
her seferinde dosyayı biraz daha büyütüyor. Dosyalar davranış değişmeden
anlamlı parçalara ayrılsın.

## 2. Bugün ne var (ölçüldü)

| dosya | satır | ne var içinde |
|---|---|---|
| `lib/widgets/week_time_grid.dart` | 1581 | 7 sınıf: ızgara + sürükleme + blok + önizleme |
| `lib/widgets/task_editor_sheet.dart` | 1454 | 6 sınıf: sayfa + 15 özellik satırı + 5 ortak parça |
| `lib/theme.dart` | 1185 | jetonlar, palet, tema kurulumu |
| `lib/screens/account_screen.dart` | 1113 | hesap, oturum, grup, senkron bölümleri |
| `lib/screens/week_view_screen.dart` | 1055 | haftalık ekran kabuğu |

Repoda ayırma deseni **zaten var**: `lib/screens/week/` klasörü
(`daily_habit_strip.dart`, `pool_panel.dart`, `week_header_bar.dart`).
Bu plan o deseni sürdürüyor, yeni bir yapı icat etmiyor.

## 3. Karar M1 — Klasör + herkese açık ad, `part` değil

Dart'ta `_Ad` ile başlayan sınıf dosyayı terk edemez. İki çıkış var:

- `part` / `part of` — gizlilik korunur ama dosyalar tek kütüphane kalır;
  araçlar, `import` düzeni ve okunabilirlik bundan zarar görür.
- **İç klasör + alt çizgisiz ad** — `lib/widgets/week_grid/event_block.dart`
  içinde `EventBlock`. Teknik olarak herkese açık ama klasör "burası içeridir"
  diyor; repoda `lib/screens/week/` bunu zaten böyle yapıyor.

İkincisi seçiliyor. Yan faydası: parçalar tek başına test edilebilir hâle
geliyor — bugün `_EventBlock`'a doğrudan bir test yazmanın yolu yok.

## 4. Karar M2 — Giriş dosyalarının yolu değişmiyor

`week_time_grid.dart` ve `task_editor_sheet.dart` sekizer dosyadan
çağrılıyor. Yolları korunuyor; içleri boşalıyor, dışa açtıkları ad ve imza
aynı kalıyor. Böylece bu iş tek bir `import` satırını bile değiştirmiyor ve
gözden geçirirken "taşındı mı, değişti mi" sorusu sorulmuyor.

## 5. Karar M3 — Davranış değişmiyor, testler taşınmıyor

Bu bir **taşıma** işi: kod kesiliyor, yapıştırılıyor, `import` ekleniyor.
Mantık düzeltmesi, ad iyileştirmesi, "madem elimiz değmişken" eklemesi yok.
Ölçüt de bu: her dilim sonrası 567 testin tamamı, tek satırı değişmeden
geçmeli. Bir test dosyaya dokunmak gerekirse taşıma sınırı yanlış çizilmiş
demektir — sınır düzeltilir, test değil.

Refactor sırasında keşfedilen gerçek hatalar not edilir, **ayrı** commit'te
düzeltilir.

## 6. Dilimler

### M1 — `week_time_grid.dart` → `lib/widgets/week_grid/` — **bitti**

| yeni dosya | içerik | ~satır |
|---|---|---|
| `week_grid/event_block.dart` | `EventBlock` + state, `EagerVerticalDragRecognizer` | ~470 |
| `week_grid/block_preview.dart` | `Preview` (blok içi yerleşim), `DragPreview` | ~250 |
| `week_grid/grid_chrome.dart` | `HourGutter`, `GridPainter` | ~110 |
| `week_grid/interaction.dart` | `DragState`, `ResizeState` | ~40 |
| `week_time_grid.dart` (kalan) | `WeekTimeGrid` + state: yerleşim ve olaylar | ~700 |

**Bitti sayılır:** giriş dosyası 800 satırın altında, `flutter analyze` temiz,
567 test dosyalarına dokunulmadan geçiyor.

**Sonuç:** giriş dosyası 714 satır; `event_block.dart` 486, `block_preview.dart`
258, `grid_chrome.dart` 120, `interaction.dart` 43. Analiz temiz, 567 test
geçiyor. Tek istisna `test/layout_test.dart`: `T.dense` beyaz listesi **dosya
yolu** sayıyor, davranış değil — bölünen yüzeyin iki yeni yolu listeye eklendi.
Mantık testi değişmedi.

### M2 — `task_editor_sheet.dart` → `lib/widgets/editor/`

Önce ortak sunum parçaları (durum tutmuyorlar, en temiz kesik):

| yeni dosya | içerik | ~satır |
|---|---|---|
| `editor/property_row.dart` | `PropertyRow` | ~110 |
| `editor/editor_controls.dart` | `BigChoice`, `ChoiceChipTile`, `Tag`, `SegToggle` | ~200 |

Sonra kendi başına duran satırlar — her biri değer alıp geri çağırım döndüren
küçük bir widget'a dönüşüyor:

| yeni dosya | içerik | ~satır |
|---|---|---|
| `editor/repeat_row.dart` | tekrar kuralı seçimi | ~110 |
| `editor/time_rows.dart` | saat, süre, çoklu saat, pencere satırları | ~340 |

**Bitti sayılır:** giriş dosyası 800 satırın altında, testler dokunulmadan
geçiyor. Satırların durumu hâlâ sayfada; widget'lar `value` + `onChanged`
alıyor, kendi `setState`'ini tutmuyor.

### M3 — `lib/theme.dart` → `lib/theme/`

Jetonlar (`S`, `T`, `R`, `I`, `Motion`), palet (`AppPalette`, renkler) ve
`ThemeData` kurulumu üç dosyaya ayrılıyor; `theme.dart` üçünü dışa açan ince
bir dosya olarak kalıyor.

**Bitti sayılır:** `import '../theme.dart';` yazan hiçbir dosya değişmiyor.

### M4 — `account_screen.dart` ve `week_view_screen.dart`

M1–M3'ten sonra yeniden ölçülür. İkisi de bölüm bölüm yazılmış; bölümler
`lib/screens/account/` ve `lib/screens/week/` altına iniyor. Bu dilim
**şartlı**: ilk üçü bittiğinde hâlâ can sıkıyorlarsa yapılır.

## 7. Kapsam dışı

Durum yönetimini değiştirmek (Riverpod düzeni bugünkü gibi kalıyor), widget
ağacını yeniden tasarlamak, `app_store.dart`'ı bölmek (957 satır ama tek bir
sorumluluk: depo), test dosyalarını bölmek, adlandırma iyileştirmeleri.

## 8. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| Taşırken sessiz davranış değişikliği | Orta | M3: testler dokunulmadan geçmeli; geçmiyorsa taşıma yanlış |
| `_` kalkınca ad çakışması | Düşük | İç klasör + `import` ön eki gerekirse |
| Refactor ortada kalır, yarısı bölünmüş yarısı değil | Orta | Her dilim tek başına commit edilebilir ve tek başına iyileştirme |
| Dosya küçülür ama karmaşa aynı kalır | Orta | Kesikler sorumluluğa göre çiziliyor, satır sayısına göre değil |

## 9. Sıra

M1 → M2 → M3 → (M4 şartlı).

M1 önde: en büyük dosya, en net sınırlar (`EventBlock` kendi state'iyle zaten
ayrı bir dünya) ve az önce oradaki bir hatayı ararken dosyanın büyüklüğünün
maliyeti görüldü.
