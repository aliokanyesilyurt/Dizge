# Esnek Plan Sistemi Planı — Havuz · Kaos · Tikler · Enerji

**Durum:** onaylandı, sıraya alındı · **Tarih:** 3 Ağustos 2026
**Başlama koşulu:** ana ekran planı (`ana-ekran-plani.md`) D7'ye kadar bitecek;
bu plan ondan sonra Ö3'ten başlar.

---

## 1. Amaç

Takvimi "her işi bir saate çakmak" zorunluluğundan kurtarmak. Dört özellik tek
bir fikrin parçaları: **plan tutmadığında suçluluk üretmeyen bir sistem.**

Bu plan koda dalmıyor. Önce veri modeli kararlarını ve dilimleri onaylıyoruz.

---

## 2. Mevcut Durum (doğrulanmış)

| Ne | Nerede | Durum |
|---|---|---|
| `Task` modeli | `lib/models/task.dart` (402 sat.) | `date` **zorunlu**, `startHour` null olabilir, `tags`/`status`/`priority` var |
| `Habit` modeli | `lib/models/habit.dart` (134 sat.) | Seri, haftalık hedef, ısı haritası, JSON — **tamamı hazır** |
| Alışkanlık ekranı | `lib/screens/habits_screen.dart` (412 sat.) | Ayrı bölüm; ana ekranda görünmüyor |
| Mutasyon/senkron | `lib/data/sync/mutation.dart` | `EntityKind { task, note, habit, category }`, LWW |
| Saatsiz işler | `week_view_screen.dart` `_UntimedRow` | `startHour == null` ama **güne bağlı** |

**Kritik bulgu:** `Ö3 (onay kutuları)` için yeni model gerekmiyor. `Habit`
zaten istediğin şey — seri psikolojisi dahil. Eksik olan tek şey ana ekranda
görünmemesi. Bu, dördü içinde en ucuz ve en hızlı kazanç.

**İkinci bulgu:** `task.date` kod tabanında 9 dosyada, 31 yerde okunuyor.
Havuz tasarımının tamamı bu tek gerçeğe bağlı (bkz. K1).

---

## 3. Mimari Kararlar

### K1 — Havuz: `date` nullable **yapılmaz**, `inPool` bayrağı eklenir

En doğal görünen çözüm `DateTime? date`. Reddediyorum:

* 31 çağrı yerinin tamamı null denetimi ister; her biri ayrı bir hata fırsatı.
* `occursOn`, `dayKey`, `compare`, aylık/yıllık ızgaralar sessizce bozulur.
* Eski kayıtlarda `date` her zaman dolu — geriye dönük okuma belirsizleşir.

Yerine `Task`'a tek alan:

```dart
/// Havuzda bekleyen iş: takvimde hiçbir günde görünmez.
/// `date` silinmez — hangi günden çekildiği bilgisi "geri koy" için lazım.
bool inPool = false;
```

Tek bir kapı yeter, çünkü **her takvim okuması `occursOn`'dan geçiyor**:

```dart
bool occursOn(DateTime day) {
  if (inPool) return false;   // ← tek satır, 31 çağrı yeri kapsanır
  ...
}
```

`date`'in korunması bonus: havuzdan çekerken "eskiden Salı'daydı" önerilebilir.
JSON'da anahtar yoksa `false` — eski kayıtlar bedelsiz açılır.

### K2 — Havuza yalnız tek günlük işler girer

Rutinin havuzda ne anlama geldiği tanımsız: "her gün tekrarlayan ama hiçbir gün
görünmeyen iş" bir çelişki. Rutin için doğru eylem havuz değil, **o günü
atlamak** (bkz. K4). Bu kural modelde `assert` değil, UI'da uygulanır —
rutinlerde "Havuza at" eylemi hiç gösterilmez.

### K3 — "Esnek" ayrı bir alan olur, `priority`'ye yüklenmez

Kaos butonunun neyi taşıyıp neyi bırakacağını bilmesi gerek. `priority` (0–3)
bu iş için yanlış: aciliyet ile **kımıldatılamazlık** aynı şey değil. Doktor
randevusu düşük öncelikli ama sabittir; refactor yüksek öncelikli ama esnektir.

```dart
/// Kaos butonunun dokunamayacağı iş: randevu, ders, uçuş.
/// Varsayılan `false` — çoğu iş esnektir, istisna işaretlenir.
bool isFixed = false;
```

Varsayılanın `false` olması bilinçli: kullanıcı hiçbir şey işaretlemezse Kaos
butonu **çalışır**. Tersi olsaydı özellik sessizce ölü doğardı.

### K4 — Rutinler için `skippedOn`

Kaos, günün geri kalanını temizlerken rutinlere ne yapacak? "Yarına at"
anlamsız (rutin zaten yarın var), "havuza at" K2'ye aykırı, silmek yıkıcı.

`completedOn`'a simetrik ikinci bir küme:

```dart
/// Rutinin bilerek atlandığı günler. `completedOn`'dan ayrı tutuluyor:
/// "yapmadım" ile "bugün geçiyorum" aynı şey değil — seri istatistiği
/// ikisini karıştırırsa sayı yalan söyler.
final Set<DateTime> skippedOn;
```

### K5 — Enerji: kapalı bir enum, `tags` değil

`tags` (`Set<String>`) hazır duruyor ama serbest metin: "Yüksek Efor",
"yüksek efor", "YuksekEfor" üçü ayrı etiket olur. Filtre ve renk için kapalı
küme şart:

```dart
enum Energy {
  high('Yüksek efor'), medium('Orta efor'),
  low('Düşük efor'), discharge('Deşarj');
}
```

`Energy? energy` — null "belirtilmemiş" demek. Zorunlu yapmak her görev
eklemeye bir karar daha eklerdi; hızlı eklemenin tek nefesliği bozulur.

**Karar (3 Ağustos):** dört kademe. "Düşük efor" ile "Orta efor" ayrımı üç
kademeye indirilebilirdi, ama asıl kullanım senaryosu — yorgun dönüp
*"beynimi yakmadan ne yapabilirim"* — tam olarak bu ikisinin arasından
seçmek. Ayrımı silmek özelliğin sebebini silerdi.

### K6 — Kaos geri alınabilir olmak zorunda

Tek tıkla 8 işi taşıyan bir düğme, geri alınamıyorsa kullanılmaz — kullanıcı
basmaya korkar. Bu bir cila değil, **özelliğin çalışma şartı**. Ö2, ana ekran
planındaki D6'nın (`ShadSonner` + geri al) üstüne kurulur.

---

## 4. Sıralama — karar verildi

Ana ekran planının D3–D7'si hâlâ açık ve **aynı ekrana** dokunuyor. İki plan
paralel yürürse aynı dosyalar iki kez elden geçer.

**Karar (3 Ağustos): önce ana ekran planı D7'ye kadar bitecek.** Bu plan
sonra, Ö3'ten başlayarak yürür.

Bedeli açık: havuz ve Kaos gecikiyor. Karşılığı, dördünün de oturmuş bir
görsel dile tek seferde doğru yerleşmesi — tik şeridi, havuz paneli ve enerji
rozetleri D3–D5'te tanımlanan tipografi, jeton ve blok diline yaslanacak.

---

## 5. Dilimler

Her dilim sonunda: `flutter analyze` temiz, testler yeşil, build ayakta, commit.

| # | Dilim | Kapsam | Kabul ölçütü |
|---|---|---|---|
| ~~**Ö3**~~ | ~~Günlük tikler~~ | `DailyHabitStrip` — ana ekranın üstünde, günlük ritimli alışkanlıklar için kutucuk + seri rozeti. **Yeni model yok.** | **İndi (4 Ağustos).** Bkz. §5.1 |
| ~~**Ö4a**~~ | ~~Enerji modeli~~ | `Energy` enum, `Task.energy`, JSON + geri uyum, düzenleyicide seçici | **İndi (4 Ağustos).** Bkz. §5.2 |
| ~~**Ö4b**~~ | ~~Enerji filtresi~~ | Başlıkta "Bugün enerjim" seçici; ızgara yüksek eforluları soluklaştırır (gizlemez) | **İndi (4 Ağustos).** Bkz. §5.3 |
| ~~**Ö1a**~~ | ~~Havuz modeli~~ | `inPool`, `occursOn` kapısı, `AppStore.moveToPool` / `pullFromPool`, mutasyon kaydı | **İndi (4 Ağustos).** Bkz. §5.4 |
| ~~**Ö1b**~~ | ~~Havuz paneli~~ | "Kenarda Bekleyenler" — sağda daraltılabilir sütun; ızgaradan sürükleyip bırakma çift yönlü | **İndi (4 Ağustos).** Bkz. §5.5 |
| **Ö2** | Kaos düğmesi | `isFixed`, `skippedOn`, "Günü kurtar" eylemi + onay + **geri al** | Sabitler yerinde kalır, tamamlananlar dokunulmaz, tek tıkla geri alınır |

**Sıralama gerekçesi:** Ö3 en ucuz ve en yüksek duygusal getiri — önce o.
Ö2 en son, çünkü hem Ö1'in havuzuna hem D6'nın geri alma altyapısına yaslanıyor.

### 5.1 Ö3 kapanış notu (4 Ağustos)

`lib/screens/week/daily_habit_strip.dart` — 7 test, `flutter analyze` temiz,
Windows derlemesi ayakta. Plandan iki sapma, ikisi de bilinçli:

1. **Haftalık ritimli alışkanlıklar da şeritte.** Plan "günlük ritimli"
   diyordu; dışarıda bırakmak "haftada 3 spor" tutan birine özelliği tümden
   görünmez kılardı — tik zaten günlük bir eylem, hedefin haftalık olması bunu
   değiştirmiyor. Rozet ayrışıyor: günlükte alev + seri (`🔥 5`), haftalıkta bu
   haftanın ilerlemesi (`2/3`). Haftalık olana "5 günlük seri" demek hedefin
   kendisini görünmez kılardı. Modele tek okuma yardımcısı eklendi
   (`Habit.doneInWeekOf`) — veri şeması değişmedi.
2. **Şerit `PageView`'in dışında.** Sayfaların içinde olsaydı geçen haftaya
   bakarken atılan tik sessizce oraya yazılır, seri yalan söylerdi. Şerit hep
   bugünü işaretler; bunu görünür kılmak için başında sabit bir "BUGÜN"
   etiketi var. Bir test bu kararı bekçiliyor.

Ayrıca `AppStore.toggleHabit` bir `source` alanı kazandı (`habits` /
`week_strip`). Şeridin varlık sebebi "tik atmak kolaylaşsın"dı; hangi kapıdan
geçildiği ölçülmeden bilinemezdi.

**Not:** "hiç alışkanlık yoksa şerit gizli" kuralı, alışkanlık ekleme yolunun
ana ekranda hiç görünmemesi demek. Şu an eklemek için Alışkanlıklar bölümüne
gitmek gerekiyor; bu bilinçli (ana ekranda ikinci bir birincil eylem yok) ama
Ö1b'de havuz paneli gelirken yeniden bakılmalı.

### 5.2 Ö4a kapanış notu (4 Ağustos)

`Energy` enum'ı `task.dart`'ta, K5'te kararlaştırıldığı gibi dört kademe.
`Task.energy` nullable, JSON'da `energy` anahtarı. Düzenleyicide "Efor"
satırı — kategori satırının hemen altında, ikisi de "bu ne tür bir iş"
sorusunun parçası. 10 test, `flutter analyze` temiz, derleme ayakta.

Plana ek olarak üç küçük karar:

* **`Energy.byName`** eksik *ve* tanınmayan değeri null'a indiriyor. Yalnız
  geriye değil ileri de uyum: başka bir cihazda eklenen bir kademe geri
  okunduğunda kayıt açılmamazlık etmiyor, o alan sessizce boş kalıyor.
* **Seçili kademeye tekrar dokunmak seçimi kaldırıyor.** Aksi hâlde
  yanlışlıkla işaretlenen bir iş bir daha "belirtilmemiş"e dönemezdi;
  seçiciye ayrı bir "temizle" çipi koymaktan sessiz.
* **`task_created` / `task_updated` olayları `energy` taşıyor** (`none` dahil).
  Ö4b'nin filtresi kimseye hitap etmiyorsa bunu ancak bu sayı söyler.

Enerji şu an yalnız *yazılıyor*; ızgarada hiçbir görsel karşılığı yok. Bu
bilinçli — rozet ve soluklaştırma Ö4b'nin işi.

### 5.3 Ö4b kapanış notu (4 Ağustos)

`core/energy_filter_controller.dart` + başlıkta "Bugün enerjim" seçici.
Enerjinin üstünde efor isteyen bloklar %40 saydamlığa iniyor — ızgarada ve
"Saatsiz" şeridinde aynı kural. 12 test, `flutter analyze` temiz, derleme
ayakta.

**Plandan tek sapma — tercih güne bağlı.** Plan "tercih kalıcı" diyordu;
süresiz kalıcı yapmadım. "Bugün enerjim" tanımı gereği bugüne ait: dün akşam
"deşarj" işaretleyen biri ertesi sabah takvimini yarı solmuş bulur ve nedenini
aramazdı bile — filtreyi kendisinin açtığını unutmuş olurdu. Bu yüzden diske
`gün|kademe` yazılıyor; gün değişince filtre kendiliğinden kalkıyor. Gün içinde
ise tam kalıcı: uygulama kapanıp açılsa da seçim yerinde.

Yol boyunca çıkan iki şey:

* **Başlık 390px'te taştı** (1.7px, sonra "Bugün" düğmesi de açıkken 5.7px).
  Beşinci denetim o genişliğe sığmıyor. Çözüm boşlukları daraltmak *ve*
  dar ekranda "Bugün"ü ikona indirmek oldu — başlık zaten yoğunluk ve "Yeni"
  için aynı kuralı uyguluyordu, "Bugün"ün yazısını korumak tutarsızlıktı.
  `theme_test` buna göre güncellendi (artık `byTooltip('Bugün')` arıyor).
* **`Energy` kademelerinin sırası artık anlamlı** — karşılaştırma `index`
  üzerinden yapılıyor. Enum'a doküman notu ve sırayı bekçileyen bir test
  eklendi; araya yeni bir kademe girerse doğru yere girmeli.

Ö4b, ana ekran planının 13.3 maddesindeki açık soruyu (telefon düzeni) daha
görünür kıldı: 390px'te başlık artık dolu. Bir denetim daha eklenecekse orada
karar vermek gerekecek.

### 5.4 Ö1a kapanış notu (4 Ağustos)

K1 olduğu gibi uygulandı: `Task.inPool`, `occursOn`'un ilk satırında tek kapı,
`date` korunuyor. `AppStore.moveToPool` / `pullFromPool` mutasyon kaydı ve
telemetriyle birlikte. 17 test, `flutter analyze` temiz, derleme ayakta.
Havuza atma/çıkarma arayüzü **yok** — o Ö1b'nin işi.

**§7'nin "hiçbir görünümde çıkmaz" ifadesini daralttım.** Havuzdaki iş bütün
*takvim* görünümlerinden (hafta, ay, gün, yıl sayacı) çekiliyor — bir test üç
ekranı tek tek geziyor. Ama **Yapılacaklar listesinde kalıyor.** Gerekçe: havuz
"takvimden çekildi" demek, "yok oldu" değil; Yapılacaklar bir takvim görünümü
değil, işlerin düz listesi. Aksi hâlde — özellikle panel inmeden önce — havuza
atılan iş uygulamada hiçbir yerde görünmezdi. Kaybolan iş, kaybolan güven.
Bu bir yorum; farklı isteniyorsa `todosProvider`'da tek satır.

Plana ek üç küçük karar:

* **`moveToPool` rutinde assert atıyor** (K2 "modelde assert değil" diyordu —
  o kural modelin kendisi için; store bir çağrı yeri unutulursa veriyi
  tutarsız bırakmamalı). Sürümde assert kapalıyken sessizce geçiyor.
* **`duplicateTo` havuz bayrağını devralmıyor**: bir güne kopyalamak o işi
  takvime koymak demek. Kopya da havuzda doğsaydı kullanıcı kopyaladığı şeyi
  hiçbir yerde göremezdi.
* **`poolProvider` en eski bekleyeni önce veriyor** — havuzun asıl riski çöp
  kutusuna dönmesi; en uzun bekleyen üstteyse unutulmuş iş göze çarpar.
  `task_unpooled` olayı `days_waited` taşıyor, aynı sorunun ölçüsü.

### 5.5 Ö1b kapanış notu (4 Ağustos)

`screens/week/pool_panel.dart` (`PoolPanel` + `PoolRail`) ve
`core/pool_panel_controller.dart`. 10 test; toplam 203 test yeşil,
`flutter analyze` temiz, derleme ayakta.

**§8'in 4. maddesi** planın kendi önerisiyle kapatıldı: ≥900px'te sağda 248px
sütun, altında açılır katman. Panel varsayılan **kapalı** ve havuz boşken
ekranda hiçbir iz bırakmıyor — havuzu kullanmayandan 44 piksel almak,
kullananın bir tıklamasından pahalı.

Kararlar:

* **Havuza atmanın yolu üç tane, hiçbiri tek başına yetmiyordu.** Sürükleyip
  panele bırakmak masaüstünde doğal ama dokunmatikte zor; sağ tık menüsü
  telefonda **hiç yok** (`longPressEnabled: false`, çünkü uzun basma sürüklemeyi
  başlatıyor). Bu yüzden asıl yol bloğa dokununca açılan önizlemedeki
  "Kenara al" düğmesi oldu — her girdi türünde çalışan tek yol o.
* **Panel kartları uzun basmayla kalkıyor**, düz sürüklemeyle değil: kartlar
  dikey kaydırılan bir listede ve düz sürükleme her kaydırma denemesinde kartı
  kaldırırdı. Izgaradaki blok da aynı dili konuşuyor.
* **Rutinde "Kenara al" hiç çizilmiyor** (K2). Blok yine sürüklenebiliyor ama
  havuza bırakılırsa yerinde kalıyor.
* **Kenara alma ve geri koyma geri alınabilir** (D6'nın `ShadSonner` altyapısı).
* Önizleme kartı 260px'ten 320px'e genişledi: iki düğme yan yana 43 piksel
  taşıyordu.
* 30 günü geçen kart soluklaşıyor, her kart "3 gündür bekliyor" yazıyor.

**Bilinen pürüz:** hafta tamamen boşken ızgaranın ortasındaki "Bu hafta boş"
kartı bir sürükleme hedefi değil — havuzdan çekilen iş tam oraya bırakılırsa
düşmüyor, kartın dışına bırakmak gerekiyor. Kartı sürükleme sırasında gizlemek
ekran düzeyinde bir sürükleme durumu taşımayı gerektiriyor; şimdilik not
edildi, düzeltilmedi.

---

## 6. Kaos Butonunun Davranış Sözleşmesi

Belirsiz bırakılırsa yıkıcı olabilecek tek özellik bu. Kuralları önden yazıyorum:

| Durum | Davranış |
|---|---|
| Kapsam | Yalnız **bugün**, yalnız **şu andan sonrası** |
| Tamamlanmış iş | Dokunulmaz |
| `isFixed` iş | Dokunulmaz |
| Tek günlük, esnek | **Havuza** taşınır (`date` korunur) — karar 3 Ağustos |
| Rutin, esnek | Bugün için `skippedOn`'a yazılır — silinmez, seri "atlandı" sayar |
| Hiç uygun iş yoksa | Düğme pasif; boşa basış hissi verilmez |
| Basıldıktan sonra | "6 iş kenara alındı · Geri al" — 10 sn |
| Onay | Sayı ≥ 5 ise önce özet gösterilir; altındaysa doğrudan uygulanır + geri al |

---

## 7. Riskler

| Risk | Etki | Karşılık |
|---|---|---|
| `inPool` bir yerde unutulur, iş hem havuzda hem takvimde görünür | Yüksek | Tek kapı `occursOn`; "havuzdaki iş hiçbir görünümde yok" testi tüm ekranları gezer |
| Kaos yanlış işi taşır, kullanıcı güvenini kaybeder | Yüksek | §6 sözleşmesi test altına alınır; geri al şart (K6) |
| Havuz sınırsız büyür, "çöp kutusu"na döner | Orta | Ö1b'de en eski öğe yaşı gösterilir; 30 günü geçenler soluklaşır |
| Ana ekran dört yeni öğeyle kalabalıklaşır | Orta | Havuz daraltılabilir, tik şeridi boşken gizli, enerji yalnız rozet |
| İki plan aynı dosyalara dokunur | Orta | §4 kararı; B seçilirse Ö3 ayrı dosyada, çakışma yok |

---

## 8. Kararlar

**Verilenler (3 Ağustos):**

1. **Sıralama** — ana ekran planı önce, D7'ye kadar. (§4)
2. **Kaos'un hedefi** — esnek havuz. "Yarın" yığını öteler, suçluluğu ertesi
   güne taşırdı. (§6)
3. **Enerji kademesi** — dört: Yüksek / Orta / Düşük / Deşarj. (K5)

4. **Havuz paneli nerede** — §8'in önerisi uygulandı (4 Ağustos): masaüstünde
   (≥900px) sağda daraltılabilir sütun, dar ekranda açılır katman. Kullanıcı
   ayrıca karar bildirmedi; öneri uygulandı, değiştirmek tek yerde.

---

## 9. Kapsam Dışı

Notlar, raporlar, yıllık görünüm, Pomodoro, senkron protokolü, `shadcn_ui`
sürüm yükseltmesi. Alışkanlık ekranının kendisi de değişmiyor — Ö3 yalnız
ana ekrana bir görünüm ekler, mevcut ekranı olduğu gibi bırakır.
