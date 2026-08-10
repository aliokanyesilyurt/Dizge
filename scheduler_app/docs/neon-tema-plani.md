# Neon Tema Planı — Mürekkep Siyahı · Cyan/Magenta

**Durum:** onay bekliyor
**Tarih:** 10 Ağustos 2026
**Kararlar (10 Ağustos):** neon palet **cyan + magenta**; zemin **neredeyse saf
siyah** (#050507).

---

## 1. Amaç

Koyu temayı "koyu gri"den çıkarıp gerçek siyaha indirmek ve tek soğuk indigo
yerine iki neon tonla renk kimliği vermek. Açık tema **hiç değişmiyor**.

---

## 2. Mevcut Durum (doğrulanmış)

| Ne | Nerede | Durum |
|---|---|---|
| Palet | `lib/theme.dart` `AppPalette.dark` | 31 renk alanı, `ThemeExtension` — tek nokta |
| Shadcn köprüsü | `lib/theme/shad_bridge.dart` | Şemayı **paletten türetiyor**, ikinci renk listesi yok |
| Tema dışı sabit renk | `lib/` içinde **5 yer** | 4'ü `#14161C` (açık temada koyu mürekkep), 1'i grafik yedek rengi |
| Testler | `test/theme_test.dart` | Renk **değeri** değil, **kural** doğruluyor (kontrast, kimlik) |

**Kritik bulgu — bu iş çoğunlukla bir değer değişimi.** 31 alan tek sınıfta,
köprü paletten türüyor, testler somut hex beklemiyor. Ekranlara dokunmadan
tema baştan aşağı değişebilir.

---

## 3. Mimari Kararlar

### T1 — Siyah zeminde gölge çalışmaz. Derinlik dile gelmeli.

Bugünkü tasarım yönü (`theme.dart` başlığı, ilke 3) şunu diyor: *"Gölge bir
efekt değil, ışık."* Kartlar zeminden gölgeyle ayrılıyor — `shadowContact`
(#8C000000) + `shadowAmbient` (#59000000).

Zemin #0E0F13 iken bu çalışıyor. Zemin #050507'ye inince **çalışmayı bırakıyor**:
siyah zemine düşen siyah gölge hiçbir şey değil. Kartlar zeminde yüzmeye başlar,
katman hiyerarşisi çöker.

Bu yüzden koyu temada derinliğin taşıyıcısı değişiyor:

| Katman | Bugün | Neon temada |
|---|---|---|
| Kart, satır (`shadowSm`) | iki katlı siyah gölge | **1px `line` kenarlık** + çok hafif iç aydınlık |
| Panel, seçili kart (`shadowMd`) | daha geniş gölge | kenarlık + zemin bir kademe ileri (`surfaceAlt`) |
| Sheet, sürüklenen blok (`shadowLg`) | en geniş gölge | siyah gölge **kalır** (koyu üstünde koyu ayrımı hâlâ işe yarar) + **neon parıltı** |

Gölge alanları silinmiyor — açık tema onları kullanmaya devam ediyor ve koyuda
`shadowLg` hâlâ anlamlı. Değişen şey, `shadowSm`/`shadowMd`'nin koyuda kenarlığa
devretmesi.

### T2 — Yeni palet alanı: `glow`

Neon bir arayüzde vurgu, kendi rengini zemine sızdırır. Bunu her çağrı yerinde
elle `BoxShadow(color: accent.withValues(alpha: .3), blurRadius: 20)` yazarak
yapmak, paletin tek-nokta olma iddiasını bozar.

`AppPalette`'e tek alan ekleniyor:

```dart
/// Neon parıltının rengi. Açık temada saydam — parıltı yalnız koyuda var.
final Color glowAccent;

/// Seçili / etkin öğenin altına düşen renk halesi.
List<BoxShadow> get glow => [
  BoxShadow(color: glowAccent, blurRadius: 24, spreadRadius: -4),
];
```

`copyWith` ve `lerp`'e birer satır. Açık temada `glowAccent` tamamen saydam
(`0x00000000`) — böylece aynı widget kodu iki temada da doğru davranır, koşul
yazmaya gerek kalmaz.

**Nerede kullanılır (üç yer, fazlası değil):** seçili gezinme öğesi, "şu an"
çizgisi, sürüklenen blok. Parıltı her yere serpilirse neon olmaz, bulanıklık olur.

### T3 — Kontrast kuralları: değişmiyor, test zaten bekçi

`test/theme_test.dart` iki kural doğruluyor ve ikisi de yeni palette geçmeli:

1. Her kategori rengi blok içinde **AA (4.5:1)** okunur.
2. Blok gövdesi yaprağa yakın kalır: `contrast(fill, surface) < 1.9`.

İkincisi zemin siyahlaştıkça zorlaşır — yaprak koyulaştıkça aynı renk daha çok
ayrışır. Hesapladım: en parlak kategori rengiyle (#FFF176 sarı) yeni yaprakta
(#0C0D11) oran **≈1.60**, eşiğin altında. Saf siyah yaprakta bile ≈1.73 çıkıyor,
yani seçtiğimiz #0C0D11'de rahat pay var.

Test gevşetilmiyor. Değer değişimi kuralın altından geçiyor.

### T4 — Kategori renkleri (`kTaskColors`) bu planda değişmiyor

Sekiz kategori rengi Material'ın pastel tonları (#FF6090, #4FC3F7, #81C784…).
Neon cyan/magenta'nın yanında bunlar sönük duracak — bu gerçek bir gözlem.

Yine de **bugün dokunmuyorum**, çünkü: `kTaskColors` yalnız *seçicinin*
listesidir; işler kendi rengini `colorHex` olarak saklıyor. Listeyi
neonlaştırmak mevcut işlerin rengini değiştirmez — kullanıcının takvimi eski
pastellerde kalır, seçiciden gelen yeniler neon olur. Yarım renkli bir takvim,
tutarlı-sönük bir takvimden kötüdür.

Doğru çözüm ayrı bir dilim: yeni palet + eski renkleri en yakın neon karşılığına
eşleyen tek seferlik göç. Bugünün işi değil, ama bugünden sonra sırada.

### T5 — 5 sabit renk paletle değiştirilir

`#14161C`, dört ayrı dosyada "açık temada koyu mürekkep" olarak elle yazılmış —
tam olarak `AppPalette.light.ink`. Bu iş sırasında token'a çevriliyor. Beşincisi
(`#529CCA`, grafik yedek rengi) `p.accent`e bağlanıyor.

Küçük bir temizlik ama bu planın tam ortasında: "tema tek noktadan değişir"
iddiası bu beş yer durdukça tam doğru değil.

---

## 4. Palet — Yeni `AppPalette.dark`

| Alan | Bugün | Yeni | Gerekçe |
|---|---|---|---|
| `bg` | #0E0F13 | **#050507** | Sayfa zemini; saf siyahın bir tık üstü |
| `surface` | #16181F | **#0C0D11** | Kart, ızgara yaprağı |
| `surfaceAlt` | #1B1E26 | **#131419** | Sheet, dialog — en öndeki katman |
| `hover` | #232733 | **#1A1C23** | Üzerine gelme |
| `sidebar` | #0A0B0E | **#000000** | En dip katman; gerçekten siyah |
| `sidebarHover` | #1A1D25 | **#121318** | |
| `navActiveFill` | #23283B | **#07303A** | Cyan'ın derin yıkaması |
| `navActiveInk` | #C7D2FE | **#67E8F9** | Cyan'ın açık tonu |
| `line` | #2A2E3A | **#1E2028** | Kenarlık — T1'de gölgenin işini devralıyor |
| `lineSoft` | #1F232C | **#14161B** | Yumuşak ayraç |
| `ink` | #ECEEF3 | **#E8ECF2** | Gövde yazısı (neredeyse aynı) |
| `inkDim` | #A8AEBF | **#99A1B3** | |
| `inkFaint` | #767D91 | **#69707F** | Siyah zeminde bir tık daha geri çekilebilir |
| `accent` | #818CF8 | **#22D3EE** | **Neon cyan** — bugün, seçim, bağlantı |
| `accentSoft` | #23283B | **#08303A** | Vurgunun derin zemini |
| `onAccent` | #0E0F13 | **#041016** | Cyan üstündeki yazı; siyaha yakın |
| `secondary` | #FDA4AF | **#F0ABFC** | **Neon magenta** — kaçan iş, en kötü gün |
| `warning` | #FCD34D | **#FDE047** | |
| `danger` | #FCA5A5 | **#FF4D6D** | |
| `gridDay` | #16181F | **#0C0D11** | |
| `gridWeekend` | #121419 | **#08090C** | Hafta sonu zeminden aşağı |
| `clockFace` | #191C24 | **#0E0F14** | |
| `gridHourLine` | #23262F | **#1C1F27** | |
| `gridHalfLine` | #191C23 | **#121419** | |
| `gridColumnLine` | #1E212A | **#171A21** | |
| `gridTodayWash` | 0x14818CF8 | **0x1422D3EE** | Bugünün sütununa cyan izi |
| `nowLine` | #FB7185 | **#FF2FB8** | Doygun magenta — `danger`'ın kırmızısıyla karışmaz |
| `dropTarget` | 0x33818CF8 | **0x3322D3EE** | |
| `shadowContact` | #8C000000 | **#B3000000** | Siyah üstünde daha derin olmalı |
| `shadowAmbient` | #59000000 | **#80000000** | |
| `glowAccent` | *(yok)* | **0x5922D3EE** | **Yeni** (T2) |

---

## 5. Dilimler

### N1 — Palet değişimi

`AppPalette.dark`'ın 31 değeri §4 tablosundan yazılır. Başka hiçbir dosyaya
dokunulmaz.

**Bitti sayılır:** `flutter test` tamamen yeşil (özellikle `theme_test.dart`'ın
iki kontrast kuralı), `flutter analyze` temiz.

### N2 — `glow` token'ı

`AppPalette`'e `glowAccent` alanı + `glow` getter'ı; `copyWith` ve `lerp`'e
birer satır; açık temada saydam.

**Bitti sayılır:** `theme_test.dart`'a "açık temada parıltı görünmez" testi
eklenir ve geçer.

### N3 — Derinlik: gölgeden kenarlığa (T1)

`shadowSm` / `shadowMd`'nin koyu temadaki karşılığı kenarlığa devreder. Kart
çizen yerler (`week_time_grid`, `pool_panel`, `daily_habit_strip`, kart
saran ortak widget'lar) taranır.

**Bitti sayılır:** Windows derlemesi açılır, ana ekran ve havuz paneli elle
görülür — kart/zemin ayrımı okunuyor.

### N4 — Parıltının üç yeri (T2)

Seçili gezinme öğesi, "şu an" çizgisi, sürüklenen blok.

**Bitti sayılır:** elle görsel doğrulama; parıltı bu üçünün dışında hiçbir yerde
yok.

### N5 — 5 sabit rengin temizliği (T5)

**Bitti sayılır:** `grep -rn "Color(0x" lib/ --include=*.dart` yalnız
`lib/theme/` ve `lib/models/` altında sonuç verir.

---

## 6. Kapsam Dışı

Açık tema (hiç dokunulmuyor), `kTaskColors` neonlaştırması ve göçü (T4),
tipografi, yuvarlaklık ölçeği (`R`), hareket süreleri (`Motion`), üçüncü bir
tema kipi ("neon" ayrı bir seçenek olarak değil, koyu temanın **kendisi** olarak
geliyor).

---

## 7. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| Kart/zemin ayrımı siyahta kaybolur | **Yüksek** | T1'in tamamı bu risk için; N3 elle görsel doğrulamayla kapanıyor |
| Kontrast testi yeni palette düşer | Düşük | §T3'te hesaplandı, pay var; N1 ölçütü testin kendisi |
| Neon cyan uzun oturumda yorar | Orta | Cyan yalnız *vurgu*; gövde nötr gri kalıyor. Doygunluk gerekirse tek satırda iner |
| Pastel kategori renkleri neonun yanında sönük durur | **Kesin** | Kabul edilen bilinçli borç (T4); sonraki dilim |
| Ekran görüntüsü testleri (varsa) kırılır | Yok | Depoda golden test yok — doğrulandı |

---

## 8. Sıra

N1 → N2 → N3 → N4 → N5. N1 tek başına da gönderilebilir: uygulama o commit'te
zaten siyah ve neon olur, N3 onu okunur kılar.
