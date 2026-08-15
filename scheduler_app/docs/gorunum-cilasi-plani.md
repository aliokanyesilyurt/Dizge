# Görünüm Cilası Planı — Ritim: Tipografi · Boşluk · Hizalama

**Durum:** ✅ **tamamlandı** — altı dilimin altısı indi (15 Ağustos)
**Tarih:** 15 Ağustos 2026
**Önceki:** `neon-tema-plani.md` (renk ve derinlik bitti),
`neon-kategori-renkleri-plani.md` (kategori paleti bitti),
`ana-ekran-plani.md` (shadcn köprüsü ve ızgara bitti)
**Önkoşul:** yok — bu iş tamamen istemci tarafında ve mevcut testlerle korunuyor.

---

## 1. Amaç

Renk işi bitti: tema siyah, vurgular neon, kontrast testlerle bekçilenmiş.
Geriye kalan rahatsızlık **renk değil, ritim**. Uygulama ekran ekran
bakıldığında iyi duruyor; ekranlar arasında gezinildiğinde tutmuyor — başlık
kayıyor, yazı boyu her kartta bir başka, kartlar geniş pencerede gerilip içi
boşalıyor.

Bu plan tek bir şey yapıyor: **aynı rolü her yerde aynı ölçüye bağlamak.**
Renklere, akışlara, özelliklere dokunulmuyor.

---

## 2. Mevcut Durum (ölçüldü, tahmin değil)

| Ne | Sayı | Nerede |
|---|---|---|
| Yarıçap ölçeği | ✅ var | `theme.dart` `R` (xs/sm/md/lg/pill) |
| Hareket ölçeği | ✅ var | `theme.dart` `Motion` (fast/base/slow + curve) |
| **Boşluk ölçeği** | ❌ **yok** | 1–26 arası neredeyse her tam sayı elle yazılı |
| **Tipografi ölçeği** | ❌ **yok** | **22 ayrı `fontSize`**, **182 satır içi `TextStyle`** |
| Genişlik sınırı | kısmen | Hesap 640, Notlar 720, Karşılama 400 — diğer altı ekranda yok |

**Kullanılan yazı boyları:** 9 · 9.5 · 10 · 10.5 · 11 · 11.5 · 12 · 12.5 · 13 ·
13.5 · 14 · 14.5 · 15 · 15.5 · 16 · 17 · 19 · 20 · 21 · 23 · 24 · 26.
Bu bir ölçek değil, birikmiş kalıntı. 11.5 ile 12 arasındaki fark hiç kimseye
bir şey anlatmıyor ama yan yana gelen iki kartı görünür biçimde eşitsiz kılıyor.

**Kenar boşlukları ekran başına ayrı:**

| Ekran | Başlık solu | Gövde solu | Fark |
|---|---|---|---|
| Alışkanlıklar | 24 | 20 | **4 px** |
| Rutinler / Yapılacaklar | 24 | 20 | **4 px** |
| Raporlar | 24 | 20 | **4 px** |
| Notlar | 24 | 20 | **4 px** |
| Gün\* | 24 (grafik) | 16 (liste) | **8 px** |
| Ay\* | 16 (gün adları) | 14 (ızgara) | **2 px** |
| Hesap | 24 | 24 | 0 ✅ |

\* Gün ve Ay `SectionHeader` kullanmıyor — kendi başlıkları var (Gün'de bir
`AppBar`, Ay'da bir gezinme satırı). Onlardaki kayma **kendi içlerinde**:
Gün'de saat grafiği ile altındaki liste ayraçta buluşurken iki farklı kenardan
başlıyor; Ay'da "Pzt Sal Çar" etiketleri altlarındaki sütunlarla iki piksel
kayık.

Kalan dört ekranda `SectionHeader` `fromLTRB(24, 22, 18, 18)` ile çiziliyor,
altındaki liste ise kendi boşluğunu seçiyor. Sonuç: **başlık ile kartlar
hiçbir ekranda aynı çizgide değil** ve sekme değiştirince içerik yatayda
zıplıyor.

**Kritik bulgu — bu iş de çoğunlukla bir değer değişimi.** `R` ve `Motion` bu
depoda zaten var ve çalışıyor; eksik olan iki kardeş ölçek. Ekran mimarisine,
widget ağacına, duruma dokunmadan ritim yerine oturabilir.

---

## 3. Mimari Kararlar

### C1a — Ölçekler `R` ve `Motion` ile aynı yerde, aynı dilde yaşar

Yeni bir tema uzantısı, yeni bir `context.*` girişi **yok**. `theme.dart`'ta
zaten kurulmuş idiom takip edilir: `abstract final class` + `static const`.

```dart
abstract final class S { static const md = 12.0; ... }
abstract final class T { static const body = 13.0; ... }
```

Neden `AppPalette`'e alan olarak değil: bunlar temaya göre **değişmiyor**. Açık
temada da koyu temada da bir kartın iç boşluğu aynı. `ThemeExtension` içine
konan değişmez değer, okunurken gereksiz bir soru sordurur ("bu temaya göre mi
farklı?"). `R` bu kararı zaten vermiş; ondan sapmıyoruz.

### C1b — Tipografi ölçeği yedi kademe, üstelik `textTheme` ile çakışmaz

`Theme.of(context).textTheme` bugün yalnız `headlineSmall` için (SectionHeader)
ve birkaç yerde kullanılıyor; kalan her şey satır içi. İki kaynağı birden
sürdürmek yeni bir ikilik olurdu.

Karar: **`T` tek kaynak, `textTheme` ondan türetilir.** `theme.dart`'ın
`ThemeData` üreten bölümü `T`'nin kademelerini `textTheme`'e yazar; böylece
`textTheme.headlineSmall` ile `T.headline` aynı sayıyı verir. Var olan
`textTheme` çağrıları kırılmaz, yeni yazılanlar `T`'yi kullanır.

| Kademe | Boy | Ağırlık | Rolü |
|---|---|---|---|
| `T.dense` | 10 | w600 | **Yalnız ızgara içi**: takvim bloğu, ay hücresi, ısı haritası |
| `T.micro` | 11 | w500 | Rozet, sayaç, yardımcı etiket |
| `T.caption` | 12 | w500 | Alt açıklama, ikincil satır |
| `T.body` | 13 | w500 | Gövde metni, liste satırı |
| `T.strong` | 14 | w600 | Kart başlığı, birincil satır |
| `T.title` | 16 | w600 | Panel başlığı, sheet başlığı |
| `T.headline` | 20 | w700 | Ekran başlığı (`SectionHeader`) |
| `T.display` | 26 | w700 | Karşılama, boş durum rakamı |

**`T.dense` neden ayrı bir kademe ve neden 10'da duruyor:** 9 ve 9.5 boyları
haftalık ızgarada ve ay hücresinde bilinçli — orada bir saatlik blok 38 piksel
yüksekliğe düşebiliyor (`GridDensity.compact`) ve yazının sığması gerekiyor.
Bunları körü körüne 11'e çıkarmak blokları taşırır. Ama 9 da fazla küçük;
tek kademede 10'da buluşuyorlar. Yoğun ızgara dışında `T.dense` kullanılmaz —
bu kural planın kapanış ölçütünde test ediliyor (C4).

### C1c — Boşluk ölçeği: dörtlü ritim, iki istisna

```
S.xs = 4 · S.sm = 8 · S.md = 12 · S.lg = 16 · S.xl = 24 · S.xxl = 32
S.hair = 2   (yalnız çizgi/ayraç payı)
S.gutter = 20  (ekran kenar boşluğu — C2)
```

Aradaki her sayı (3, 5, 6, 7, 9, 10, 11, 13, 14, 15, 18, 22, 26) en yakın
kademeye yuvarlanır. 6 ve 10 sık kullanılıyor ve ikisi de iki kademe arasında
tam ortada; bunlar **aşağı** yuvarlanır (6→4, 10→8), çünkü bu değerler hep
sıkışık bağlamlarda (çip içi, ikon yanı) geçiyor ve yukarı yuvarlamak orada
taşma üretir.

### C1d — Tek kenar boşluğu: `S.gutter`, başlık ve gövde ortak

`SectionHeader`'ın yatay boşluğu ile altındaki listenin yatay boşluğu **aynı
sabitten** okunur. Bu, C2'nin tamamı: dört piksellik kaymanın kaynağı iki ayrı
sayı olması, çözümü tek sayı olması.

Takvim ekranları (Hafta, Ay, Yıl) bu kuralın dışında: onların gövdesi bir
**ızgara** ve ızgara kenardan kenara uzanmalı. Onlarda yalnız `SectionHeader`
hizalanır, ızgara tam genişlikte kalır.

### C1e — Geniş pencerede okuma genişliği: liste ekranları sınırlı, takvim serbest

Birincil hedef Windows ve orada pencere 1920 piksel olabiliyor. Bir alışkanlık
kartı 1800 piksel geniş olduğunda solda 10 piksellik bir renk noktası, sağda
bir seri sayısı ve arada 1700 piksel boşluk kalıyor. Kart değil, cetvel.

Karar: liste ekranları paylaşılan bir `ContentColumn` ile **720 piksel**de
durur (Notlar'ın zaten kullandığı sayı — yeni bir sayı uydurmuyoruz). Takvim
ekranları sınırsız kalır: orada genişlik boşa gitmiyor, bir güne bir sütun
düşüyor.

Sınırlanacaklar: Alışkanlıklar, Rutinler, Yapılacaklar, Raporlar.
Sınırlanmayacaklar: Hafta, Ay, Yıl, Gün (gün de bir zaman ekseni).

### C1f — Bu plan hiçbir rengi, akışı ve davranışı değiştirmez

Değişen tek şey ölçü. Renk `AppPalette`'ten okunmaya devam eder, kontrast
kuralları ve testleri olduğu gibi kalır, hiçbir widget kaldırılmaz veya
eklenmez — `ContentColumn` dışında, o da yalnız bir `Center` + `ConstrainedBox`
sarmalı.

---

## 4. Dilimler

### C1 — Ölçekler temaya girer, hiçbir çağrı yeri değişmez ✅ `e474a98`

`theme.dart`'a `S` ve `T` eklenir; `textTheme` `T`'den türetilir. Ekran
dosyalarına **dokunulmaz**.

**Bitti sayılır:** `flutter analyze` temiz, `flutter test` 446/446 yeşil
(hiçbiri değişmediği için aynen geçmeli), `theme_test.dart`'a iki kural eklenir
ve geçer: (a) `T` kademeleri artan sırada ve hiçbiri 10'un altında değil,
(b) `textTheme.headlineSmall.fontSize == T.headline`.

### C2 — Hizalama: başlık ile gövde aynı çizgiye gelir ✅ `d598c3a`

`SectionHeader` yatay boşluğunu `S.gutter`'dan okur. Onu kullanan yedi ekranın
liste/gövde boşluğu da aynı sabite bağlanır. Ay ve Gün ekranlarının ızgara
gövdeleri C1d'ye göre muaf; yalnız başlıkları hizalanır.

**Bitti sayılır:** `grep -rn "fromLTRB(2[04]" lib/screens/` artık ekran
kenarında elle yazılmış boşluk göstermiyor; Windows derlemesinde yedi sekme
sırayla gezildiğinde başlık yatayda **hiç zıplamıyor** (elle görsel doğrulama).

### C3 — Geniş pencerede okuma genişliği ✅ `0fb2735`

`ContentColumn` widget'ı (`lib/widgets/content_column.dart`) yazılır ve C1e'nin
dört ekranına geçirilir.

**Bitti sayılır:** pencere 1920'ye çekildiğinde Alışkanlıklar, Rutinler,
Yapılacaklar ve Raporlar ortada 720 piksellik bir sütunda duruyor; 800
piksellik pencerede hiçbir şey değişmemiş görünüyor (sınır devreye girmiyor).
Bir widget testi: dar ve geniş iki genişlikte kart genişliği ölçülür, geniş
olanda 720'yi aşmadığı doğrulanır.

### C4 — Tipografi ölçeğe geçer ✅ `d72fe4f`

182 satır içi `TextStyle`'ın `fontSize`'ları `T` kademelerine bağlanır. Ekran
ekran gidilir, her dosya kendi commit'i olmaz — dilim tek commit, ama sıra
şöyle: paylaşılan widget'lar (`section_header`, `task_list_scaffold`,
`user_avatar`) → liste ekranları → takvim ekranları → sheet'ler.

**Bitti sayılır:** `grep -rhoE "fontSize: [0-9.]+" lib/ | sort -u` **yalnız
`T`'nin sekiz kademesini** döndürür; `T.dense` yalnız `week_time_grid.dart`,
`monthly_view_screen.dart`, `year_view_screen.dart` ve `habit_heatmap.dart`
içinde geçer (bu kural bir teste yazılır). `flutter test` yeşil.

### C5 — Boşluklar ölçeğe geçer ✅ `cb425ee`

`SizedBox` ve `EdgeInsets` değerleri `S` kademelerine yuvarlanır (C1c).

**Bitti sayılır:** `grep -rhoE "SizedBox\((height|width): [0-9.]+"` yalnız `S`
kademelerini döndürür. Windows derlemesinde tüm ekranlar elle gezilir — hiçbir
yerde taşma (`RenderFlex overflow`) ve hiçbir yerde yapışmış iki öğe yok.

### C6 — Mikro cila ✅

Ölçekler oturduktan sonra görülebilen küçük işler, tek tek:

* `EmptyState` dairesi (62 px) ve ikonu (26 px) `S`/`T` kademelerine oturur.
* FAB'ın liste altındaki 100 piksellik boşlukla ilişkisi tek sabite bağlanır
  (bugün üç dosyada elle 100 yazılı).
* Kart iç boşluğu tek değere iner (bugün 15, 18 ve `all(18)` bir arada).
* `SectionHeader` alt satırı `T.caption`'a geçer (bugün 12.5).

**Bitti sayılır:** elle görsel tur; her ekranda kartların iç boşluğu ve boş
durumların dikey ritmi aynı.

---

## 5. Kapsam Dışı

Renkler (`AppPalette`, `kTaskColors` — ikisi de bitti ve dokunulmuyor), yazı
tipi seçimi (`Inter` kalıyor), yarıçap ölçeği `R` (zaten tutarlı), hareket
süreleri `Motion` (zaten tutarlı), yeni ekran veya yeni özellik, ızgara
yoğunluğu seçenekleri (`GridDensity`), animasyon eklemek, ikon setini
değiştirmek.

Bu plan **hiçbir yeni davranış getirmiyor**. Getirmemesi bilinçli: ölçü işiyle
davranış işi aynı commit'e girerse, bir şey bozulduğunda hangisinin bozduğu
anlaşılmaz.

---

## 6. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| Yazı boyu yukarı yuvarlanınca ızgarada blok taşar | **Yüksek** | C1b'nin `T.dense` kademesi tam bu risk için; C4'ün ölçütü elle ızgara turu içeriyor |
| Boşluk aşağı yuvarlanınca iki öğe yapışır | Orta | C5 elle turla kapanıyor; 6→4 ve 10→8 kararı sıkışık bağlamlara göre verildi |
| Golden test olmadığı için görsel gerileme sessiz kalır | **Kesin** | Depoda golden yok (doğrulandı). Her dilimin ölçütü elle görsel tur içeriyor — bu planın maliyeti ve kabul edilen bedeli |
| 182 çağrı yerinin göçü tek commit'te karışır | Orta | C4 ve C5 ayrı dilimler; her biri kendi grep ölçütüyle kapanıyor |
| Genişlik sınırı dar pencerede içeriği daraltır | Düşük | `ConstrainedBox` yalnız üst sınır koyar; 720'nin altında etkisiz |

---

## 7. Kapanış notu — C4–C6 (15 Ağustos)

Altı dilimin altısı indi. Test sayısı 446'dan **457**'ye çıktı,
`flutter analyze` temiz, Windows sürümü derleniyor.

**Sonuç, tek cümlede:** artık `lib/` altında elle yazılmış tek bir yazı boyu,
tek bir ara verici, tek bir kenar boşluğu ve tek bir simge boyu yok.

**Planda olmayıp çıkan iş: `I` — simge kutusu ölçeği.** C6 "boş durum
dairesini ve ikonunu ölçeğe oturt" diye yazılmıştı. Oraya gelindiğinde asıl
sorunun daha büyük olduğu görüldü: ikon, avatar ve marka işareti — hepsi
yazının yanında duran kare kutular — **on altı ayrı boyda** çiziliyordu
(11'den 60'a). Boş durumun dairesini düzeltip bu tabloyu bırakmak, C4 ve
C5'in kapattığı deliği başka bir yerden açık tutmak olurdu. `R`/`S`/`T` ile
aynı dilde bir dördüncü ölçek eklendi: `I` (xs/sm/md/lg/xl/hero).

**C6'nın planda yazılı üç maddesi kendiliğinden kapandı.** Kart iç boşluğu
(15, 18 ve `all(18)` bir aradaydı) C5'in yuvarlamasıyla tek değere indi;
`SectionHeader`'ın alt satırı (12.5) C4'te `T.caption`'a geçti; FAB payı C1'de
`S.fabGap` olarak adlandırıldı. Geriye yalnız boş durum dairesi kalmıştı —
o da `I.hero` (62 → 56) oldu, içindeki ikon `I.lg`.

**C5'te bilinçli bırakılan iki şey.** Çocuklu `SizedBox` ölçeğe sokulmadı:
`SizedBox(width: 3, child: ColoredBox(...))` bir renk şeridinin kalınlığıdır,
boşluk değil. Ve `0` serbest bırakıldı — sıfır bir kademe değil, boşluğun
yokluğu.

**Bu dilimlerin bedeli.** Golden test olmadığı için C4/C5/C6'nın görsel
sonucu **testlerle değil, gözle** doğrulanır. Testler yalnız "ölçek dışına
çıkılmadı"yı garanti ediyor; "daha güzel durdu mu" sorusunun yanıtı derlenmiş
exe'de.

---

## 8. Ara kapanış notu — C1–C3 (15 Ağustos)

Üç dilim indi, test sayısı 446'dan 453'e çıktı, `flutter analyze` temiz.

**Planın düzeltildiği yer.** §2'nin ilk hâli Gün ve Ay ekranlarının da
`SectionHeader` kullandığını varsayıyordu; kullanmıyorlar. Oradaki kayma
başlık-gövde değil, **gövde-gövde** kaymasıymış. Tablo düzeltildi ve C2 o
ekranlarda kendi içlerindeki hizalamayı kapattı — Ay'daki iki piksel, plan
yazılırken hiç fark edilmemiş bir bulguydu.

**Ölçekte verilen iki karar.** `textTheme`'in `bodyLarge` ve `bodyMedium`
rolleri aynı kademeye (14) düştü: aralarındaki eski 1 punto fark hiçbir yerde
bir hiyerarşi anlatmıyordu. `headlineSmall` 21'den 20'ye indi — ekran
başlıkları bir punto küçüldü, ölçeğin dışında kalan tek sayıydı.

**Planda olmayıp eklenen.** `S.fabGap`: üç ekranda listenin altına elle `100`
yazılıydı ve bu bir ölçek kademesi değil, FAB'ın boyuna bağlı bir **ölçü**.
Ölçeğe kademe olarak sokmak yerine adı konmuş bir sabit oldu.

**Test tarafı.** Yeni `test/layout_test.dart`: başlık ile listenin kenarları
eşit; 1600 piksellik pencerede sütun 720'de duruyor; 600'de sınır devreye
girmiyor; başlık listeyle aynı sol kenarda kalıyor. Depoda golden test
olmadığı için ölçü kaymaları gözle görülene kadar sessiz kalıyordu — bu dört
kural o sessizliği kapatıyor.

**Kalan.** C4 (182 satır içi `TextStyle`'ın göçü) ve C5 (boşluk göçü) hâlâ
açık; ölçekler kurulu ama çağrı yerleri eski sayılarını kullanmaya devam
ediyor. C6 ancak ikisi bittikten sonra anlamlı.

---

## 9. Sıra

C1 → C2 → C3 → C4 → C5 → C6.

C1 tek başına gönderilebilir ve hiçbir şeyi değiştirmez — yalnız sonraki beş
dilimin dayanacağı zemini kurar. C2 ve C3 gözle görülür kazancı en ucuza veren
ikili: dördü de birkaç satır, etkisi her ekranda. C4 ve C5 uzun ve mekanik.
C6 ancak ölçekler oturduktan sonra anlamlı.
