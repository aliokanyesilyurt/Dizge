# Ana Ekran Planı — Haftalık Zaman Izgarası

**Durum:** uygulanıyor — D0 · D1 · D2 · D3 · D4 · D5 bitti, sıradaki **D6** ·
**Tarih:** 2 Ağustos 2026 (son güncelleme 3 Ağustos 2026)
**Yöntem:** `frontend-ui-engineering` + `incremental-implementation`
**Dal:** `ana-ekran-shadcn`

---

## 1. Amaç

Haftalık planlama uygulamasının ana ekranını (dikeyde saat, yatayda gün) modern,
minimalist ve premium bir zaman ızgarasına dönüştürmek. Görsel dil `shadcn_ui`
(0.56.0) estetiğine oturacak; sadelik, ölçülü boşluk ve sakin tipografi esas.

**Bu plan koda dalmıyor.** Önce widget ağacını, bileşen haritasını ve dilimleri
onaylıyoruz.

---

## 2. Mevcut Durum (doğrulanmış)

Sıfırdan başlamıyoruz. Çalışan bir taban var:

| Bileşen | Satır | Durum |
|---|---|---|
| `lib/widgets/week_time_grid.dart` | 862 | Izgara, sürükle-taşı, kenardan uzat, "şimdi" çizgisi, 15 dk kılavuzu — **çalışıyor** |
| `lib/screens/week_view_screen.dart` | 690 | Başlık, gün başlıkları, saatsiz işler satırı |
| `lib/theme.dart` | 784 | `AppPalette` (40+ jeton), `R` (radius), `Motion`, `GridDensity` |
| `lib/screens/app_shell.dart` | 710 | Kenar çubuğu, tema anahtarı |

**Doğrulama:** `flutter analyze` temiz · 98/98 test geçiyor · `flutter build windows` exit 0.

**Açık uçlar:**
- `shadcn_ui: ^0.56.0` pubspec'te var ama **hiçbir yerde import edilmiyor**. Bu planın başlangıç noktası.
- Yazı tipi `Segoe UI` (yalnız Windows'ta doğru görünür).
- `assets/fonts/PatrickHand`, `PermanentMarker` paketleniyor ama `lib/` içinde kullanılmıyor.

---

## 3. Mimari Kararlar

### K1 — `ShadApp.custom` ile köprü, `MaterialApp` korunur

Uygulama Material widget'larına (tarih seçici, `showModalBottomSheet`, Türkçe
yerelleştirme) bağımlı. `ShadApp` tek başına bunları vermez.

```
ShadApp.custom(
  theme:     shadThemeFrom(AppPalette.light),
  darkTheme: shadThemeFrom(AppPalette.dark),
  themeMode: ref.watch(themeModeProvider),      // mevcut controller
  appBuilder: (context) => MaterialApp(...),    // bugünkü ağaç aynen
)
```

**Neden:** `ShadApp.custom`, `ShadTheme`'i ağaca koyar ama yönlendirme/yerelleştirmeyi
`appBuilder`'a bırakır. Mevcut `main.dart` gövdesi neredeyse hiç değişmez, tema
kipi denetleyicisi ve 98 test olduğu gibi kalır.

### K2 — Tek renk kaynağı: `AppPalette` → `ShadColorScheme`

İki paralel renk sistemi = kaçınılmaz tutarsızlık. `AppPalette` **kaynak** kalır;
shadcn şeması ondan türetilir (`lib/theme/shad_bridge.dart`):

| ShadColorScheme | ← AppPalette |
|---|---|
| `background` / `foreground` | `bg` / `ink` |
| `card` / `cardForeground` | `surface` / `ink` |
| `popover` / `popoverForeground` | `surfaceAlt` / `ink` |
| `primary` / `primaryForeground` | `accent` / `onAccent` |
| `secondary` / `secondaryForeground` | `surfaceAlt` / `inkDim` |
| `muted` / `mutedForeground` | `hover` / `inkFaint` |
| `accent` / `accentForeground` | `accentSoft` / `accent` |
| `destructive` / `destructiveForeground` | `danger` / `onAccent` |
| `border` / `input` / `ring` | `line` / `lineSoft` / `accent` |

Böylece açık/koyu tema, tema anahtarı ve mevcut palet testleri bedelsiz devam eder.

### K3 — Tipografi: gövde yazı tipi paketlenir

`Segoe UI` yerine değişken ağırlıklı, cross-platform bir gövde yazı tipi
(Inter veya Geist) `assets/fonts/` altına paketlenir. shadcn estetiğinin
temeli sakin, dar aralıklı bir sans-serif.

Kullanılmayan `PatrickHand` / `PermanentMarker` **kaldırılmaz** — ileride el yazısı
notlar için düşünülmüş olabilir; kararı D7'de sana bırakıyorum.

### K4 — Izgaranın kendisi shadcn bileşeni **olmaz**

`WeekTimeGrid` özel `CustomPainter` + jest tanıyıcılarla çalışıyor; shadcn'de
karşılığı yok ve olması da gerekmiyor. Shadcn bileşenleri **ızgaranın çevresinde**
(başlık, denetimler, açılır katmanlar) kullanılır. Izgaranın içi yalnız `ShadTheme`
jetonlarını okur.

> Bu, "shadcn'i aktif kullan" isteğinin en dürüst okuması: takvim tuvalini
> hazır bileşene sığdırmaya çalışmak kaliteyi düşürürdü.

---

## 4. Tasarım Dili Sözleşmesi

| Eksen | Karar |
|---|---|
| **Boşluk** | 4'ün katları: 4 · 8 · 12 · 16 · 24 · 32. Ara değer icat edilmez. |
| **Radius** | Mevcut `R` ölçeği korunur, shadcn'e bağlanır: blok `xs`(6), girdi `sm`(10), kart `md`(16). Her şeyi yuvarlamak yok. |
| **Gölge** | Yalnız yükselen katmanlarda (popover, sheet, sürüklenen blok). Izgarada gölge yok — çizgi ve zemin farkı yeter. |
| **Kenarlık** | shadcn ruhu: 1px `border`, düşük kontrast. Ayrım gölgeyle değil çizgiyle. |
| **Renk** | Etkinlik rengi dışında doygun renk yok. Zeminler nötr. Mor/gradyan yok. |
| **Hareket** | Mevcut `Motion` (140/220/320ms, `easeOutCubic`). Yeni süre eklenmez. |
| **Negatif alan** | Başlık ve gün başlıkları hafifler; ekranın ağırlık merkezi ızgaranın kendisi olur. |
| **Marka** | Uygulama adı tek bir yerde — `AppShell` içindeki wordmark. Öztürkçe ad seçilince tek satır değişir. |

---

## 5. Widget Ağacı

### Bugün

```
MaterialApp
└─ AppShell
   └─ WeekViewScreen
      ├─ _header()          ← _Chrome, _IconAction, _GhostButton (elde yazılmış)
      ├─ _DayHeaderRow      ← _DayHeaderCell ×7
      ├─ _UntimedRow        ← _UntimedChip
      └─ WeekTimeGrid
         ├─ _HourGutter
         ├─ _GridPainter (CustomPainter)
         ├─ _EventBlock ×N
         └─ _nowIndicator
```

### Hedef

```
ShadApp.custom
└─ MaterialApp                          (yerelleştirme, Material bileşenler)
   └─ AppShell
      └─ WeekViewScreen
         ├─ WeekHeaderBar               ← YENİ, ayrı dosya
         │  ├─ ShadButton.ghost         (◀ ▶ gezinme)
         │  ├─ ShadButton.outline       ("Bugün")
         │  ├─ Text                     (ay + yıl, tek vurgulu satır)
         │  ├─ ShadSelect<GridDensity>  (Sıkışık / Normal / Geniş)
         │  └─ ShadButton               (+ Yeni)
         ├─ ShadSeparator.horizontal
         ├─ DayHeaderRow                (mevcut, jetonlara bağlanır)
         │  └─ DayHeaderCell ×7         + ShadBadge (gün başına iş sayısı)
         ├─ UntimedRow                  (mevcut)
         │  └─ ShadBadge.secondary      (saatsiz iş çipleri)
         └─ WeekTimeGrid                (iç mantık değişmez)
            ├─ _HourGutter              → inkDim (muted değil: 10.5px'te AA)
            ├─ _GridPainter             → colorScheme.border
            ├─ _EventBlock              → + ShadContextMenu (sağ tık)
            │                             + ShadTooltip (kısa bloklarda tam ad)
            └─ _nowIndicator
```

Yeni dosyalar: `lib/theme/shad_bridge.dart`, `lib/screens/week/week_header_bar.dart`.

---

## 6. Shadcn Bileşen Haritası

| Bileşen | Nerede | Neyin yerine | Neden |
|---|---|---|---|
| `ShadButton.ghost` | Hafta gezinme okları | `_IconAction` | Odak halkası ve durum katmanları hazır |
| `ShadButton.outline` | "Bugün" | `_GhostButton` | İkincil eylem hiyerarşisi |
| `ShadButton` | "+ Yeni" | — | Tek birincil eylem |
| `ShadSelect` | Izgara yoğunluğu | Döngüsel düğme | Üç seçenek görünür olur, tahmin gerekmez |
| `ShadBadge` | Gün başına iş sayısı, saatsiz çipler | `_UntimedChip` | Tutarlı küçük etiket dili |
| `ShadSeparator` | Başlık / ızgara ayrımı | Elle `Divider` | Tek kalınlık kaynağı |
| `ShadTooltip` | Kısa bloklarda tam başlık | `Tooltip` | Tema ile uyumlu |
| `ShadContextMenu` | Blokta sağ tık: Düzenle / Kopyala / Sil | *(yok)* | Masaüstünde beklenen davranış |
| `ShadPopover` | Bloğa tıklayınca hızlı önizleme | Doğrudan sheet açmak | Tam düzenleyiciden önce hafif katman |
| `ShadCard` | Boş hafta durumu | *(yok)* | Bugün boş hafta hiçbir şey söylemiyor |
| `ShadSonner` | "Geri al" bildirimi | `SnackBar` | Taşıma/silme sonrası geri alma |

**Bilinçli olarak kullanılmayanlar:** `ShadCalendar` (kendi ızgaramız var),
`ShadTable` (zaman ızgarası tablo değil), `ShadSheet` (mevcut Material sheet'ler
çalışıyor, D kapsamında değil).

---

## 7. Ana Ekran Anatomisi

**Katman 1 — Başlık (yükseklik 56)**
Sol: `‹ ›` + "Bugün" · Orta: **Ağustos 2026** (tek vurgulu satır, sonrası hafif) ·
Sağ: yoğunluk seçici + "+ Yeni". Bugünün ağır başlık kutusu hafifler.

**Katman 2 — Gün başlıkları (yükseklik 64, yapışkan)**
Üstte üç harfli gün (`PZT`, muted, 11px, +0.5 letter-spacing), altında gün sayısı
(20px). Bugün: sayı dolu daire içinde `primary`. Hafta sonu: yalnız zeminde
çok hafif fark — renkle bağırmak yok. Sağ üstte iş sayısı `ShadBadge`.

**Katman 3 — Saatsiz işler (içeriğe göre, boşsa gizli)**
Tam gün / saati belirsiz işler yatay çip şeridi.

**Katman 4 — Izgara (kalan yükseklik, kaydırılabilir)**
Sol oluk 56px, saatler sağa hizalı ve ikincil ağırlıkta. "Şimdi" çizgisi
`primary`, solda 6px nokta.

Çizgi hiyerarşisi (D4'te ölçülüp düzeltildi): **tam saat > dikey gün ayracı >
yarım saat**. Planın ilk hâli gün ayracını en soluk diyordu; yanlıştı — gün
sınırı, yarım saat tikinden daha güçlü bir bölme. Tersi olsaydı alt bölme ana
bölmeden baskın çıkardı. Üç ağırlık da tema başına elle ayarlı kalıyor: koyu
temada okunur bir aralık için açık temadakinden belirgin biçimde geniş bir
yayılım gerekiyor, tek bir opaklık merdiveni ikisine birden hizmet etmiyor.

**Katman 5 — Etkinlik bloğu**
Radius `xs`(6). Sol kenarda 3px renk şeridi; gövde o rengin çok düşük opaklıkta
zemini — dolu renk bloklar yerine sakin bir kart. 1 satır başlık + (blok ≥ 40px ise)
saat aralığı. Tamamlanan: soluk zemin + üstü çizili başlık **ve** ✓ ikonu
(yalnız renge dayanmaz).

---

## 8. Etkileşim ve Durum

| Eylem | Davranış |
|---|---|
| Boş alana tık | Hızlı ekleme (mevcut) |
| Bloğa tık | `ShadPopover` önizleme → "Düzenle" tam sheet açar |
| Blokta sağ tık | `ShadContextMenu`: Düzenle / Kopyala / Sil |
| Basılı tut + sürükle | Taşı (15 dk'ya oturur) — mevcut mantık korunur |
| Alt kenardan çek | Süreyi değiştir — mevcut |
| Taşıma/silme sonrası | `ShadSonner` + "Geri al" |

**Durum yönetimi:** değişiklik yok. Riverpod + mevcut `scrollOffset` `ValueNotifier`
paylaşımı olduğu gibi kalır. Yoğunluk tercihi `ThemeModeController` desenini izleyerek
`LocalStore`'a yazılır (`readString`/`writeString` zaten var).

---

## 9. Erişilebilirlik (WCAG 2.1 AA)

- Her etkinlik bloğu `Semantics` ile: *"Toplantı, Salı 14:00–15:30, tamamlandı"*.
- Klavye: `Tab` ile bloklar arası, `Enter` düzenle, `Delete` sil, `←/→` hafta değiştir.
- Odak halkası `colorScheme.ring` — tüm etkileşimli öğelerde görünür.
- Kontrast: gövde 4.5:1, blok içi yazı `AppPalette.readableOn()` ile üretiliyor —
  kategori rengi AA eşiğini geçene dek gövde mürekkebine çekiliyor. Kural bir test
  temennisi değil, rengi üreten kodun kendisi; palete yeni renk eklendiğinde
  kendiliğinden tutar.
- Durum asla yalnız renkle anlatılmaz (tamamlandı → ✓ + üstü çizili).
- `MediaQuery.withClampedTextScaling(1.3)` korunur.

---

## 10. Duyarlılık

| Genişlik | Davranış |
|---|---|
| < 600 (telefon) | Tek gün sütunu + kaydırmalı gün seçici; başlık ikonlara iner |
| 600–1024 (tablet) | 7 gün, oluk 48px, yoğunluk otomatik `compact` |
| > 1024 (masaüstü) | Tam 7 gün + kenar çubuğu |

Test noktaları: 390 · 768 · 1024 · 1440. (390px hafta başlığı taşma testi zaten var.)

---

## 11. Artımlı Dilimler

Her dilim sonunda: `flutter analyze` temiz, testler yeşil, build ayakta, commit atılır.

| # | Dilim | Kapsam | Kabul ölçütü |
|---|---|---|---|
| **D0** | Köprü | `shad_bridge.dart`, `ShadApp.custom` sarmalama. Görsel değişiklik **yok**. | 98 test aynen geçer; `ShadTheme.of(context)` her yerden okunur |
| **D1** | Tipografi | Gövde yazı tipi paketlenir, `kFontFamily` güncellenir | Ekran görüntüsü karşılaştırması; taşma testleri geçer |
| **D2** | Başlık | `WeekHeaderBar` + ShadButton/ShadSelect | Yoğunluk seçimi çalışır ve diske yazılır; yeni test |
| **D3** | Gün başlıkları | Tipografi, bugün dairesi, `ShadBadge` sayaç | 390px'te taşma yok; hafta sonu ayrımı ≥3:1 |
| **D4** | Izgara jetonları | `_GridPainter` + `_HourGutter` okunabilirliği ve çizgi hiyerarşisi teste bağlanır | Çizim testleri geçer; iki temada da okunur |
| **D5** | Etkinlik bloğu | Şerit + soluk zemin, ✓ ikonu, `ShadTooltip` | Kontrast testi; tamamlanan blok testi genişletilir |
| **D6** | Katmanlar | `ShadPopover`, `ShadContextMenu`, `ShadSonner` geri al | Geri alma testi (yeni) |
| **D7** | Cila | Boş hafta `ShadCard`, klavye gezinme, Semantics, font temizliği | Erişilebilirlik kontrol listesi tam |

**Sıralama gerekçesi:** D0 en riskli parça (iki tema sisteminin bir arada yaşaması).
Orada patlarsa hiçbir görsel işe yatırım yapmadan öğreniriz.

---

## 12. Riskler

| Risk | Etki | Karşılık |
|---|---|---|
| `ShadApp.custom` + `MaterialApp` iç içe, tema kipi çakışması | Yüksek | D0 tek başına, görsel değişiklik olmadan doğrulanır |
| shadcn'in kendi radius/gölge varsayılanları mevcut dili bozar | Orta | `shadThemeFrom` içinde `radius` ve `decoration` açıkça `R`'ye bağlanır |
| Yazı tipi değişimi ızgara ölçülerini kaydırır | Orta | D1 ayrı dilim; taşma testleri kapıda |
| `ShadPopover`'ın sürükleme jestiyle çakışması | Orta | D6'da; çakışırsa popover'dan vazgeçip doğrudan sheet'e döneriz |
| Paket 0.x — kırıcı sürüm riski | Düşük | `pubspec.lock` sabit; sürüm yükseltmesi bu planın dışında |

---

## 13. Senin Kararına Bırakılanlar

1. **Yazı tipi:** Inter mi, Geist mi? (D1'den önce)
2. **`PatrickHand` / `PermanentMarker`:** kalsın mı, kaldırılsın mı? (D7)
3. **Telefon düzeni:** tek gün sütunu mu, 3 günlük kaydırmalı pencere mi? (D3'ten önce)
4. **Uygulama adı:** Öztürkçe ad seçilince tek satır değişir — acelesi yok.

---

## 14. Kapsam Dışı

Bu plan **yalnız ana ekran**. Dokunulmayacaklar: gün/ay/yıl görünümleri,
notlar, alışkanlıklar, raporlar, hesap ekranı, senkron/telemetri, veri modeli,
`shadcn_ui` sürüm yükseltmesi.

Sonraki adımlarda görülüp **düzeltilmeyecek** olanlar (ayrı iş):
- `bootstrap.dart:113` — boş satır kaybı (kozmetik regresyon)
- `day_view_screen.dart:384`, `habits_screen.dart:199`, `day_pie_chart.dart:151` —
  kontrast mantığı `AppPalette.event().ink` varken elle tekrarlanmış

