# Zaman Aralıkları, Alışkanlık–Rutin Ayrımı ve Adlandırma Planı

**Durum:** onay bekliyor
**Tarih:** 16 Ağustos 2026
**Önceki:** `esnek-plan-sistemi-plani.md` (Günü Kurtar, esnek/sabit ekseni),
`neon-kategori-renkleri-plani.md` (kategori adlarının kalıcılığı dersi)

---

## 1. İstenen

Üç istek, tek oturumda geldi:

1. **Saat aralığı seçilebilsin** — bir iş o günün belli saatlerinde olsun.
   Hem *pencere* ("09:00–12:00 arasında bir yerde") hem *çoklu saat*
   ("08:00 / 14:00 / 20:00") istendi; ikisi de kapsamda.
2. **Alışkanlık ile rutin anlamca ayrışsın** — ikisi de kalacaksa:
   **alışkanlık = süreksiz, esnek işler**; **rutin = sürekli, düzenli işler**.
   Ayrım yalnız yazıda değil, modelde de olsun.
3. **Özellik adları Başlık Düzeni'ne geçsin** — "Kalıcı iş" değil
   **"Kalıcı İş"**. Diğer özellikler de aynı kurala uysun.

---

## 2. Bugün ne var (doğrulandı)

| Ne | Nerede | Durum |
|---|---|---|
| İşin saati | `models/task.dart:175` | Tek `startHour` (0–24, null = saatsiz) + `durationHours` |
| Esnek/sabit ekseni | `models/task.dart:224` `isFixed` | "Kımıldatılamaz / Esnek"; Günü Kurtar yalnız esnek işe dokunur |
| Günü Kurtar | `core/day_rescue.dart:53` `planDayRescue` | Esnek işleri havuza alır; **saat kısıtı yok** |
| Kategoriler | `models/task.dart:576` | Yedi hazır kategori, ad **metin olarak** kaydediliyor (`categoryName`, `:178`) |
| Alışkanlık | `models/habit.dart:8` | `HabitCadence.daily` / `.weekly`; seri + ısı haritası |
| Rutin | `models/task.dart:89` `Repeat` | Tekrar eden takvim işi; gün gün tamamlanır/atlanır |
| Yerel şema | `core/app_config.dart:120` | `kSchemaVersion = 3`, göç `data/local_store.dart:60` |
| Sunucu göçleri | `supabase/migrations/` | Sırada `05_` var (dördü inmiş) |

**Kritik bulgu — alışkanlıktaki `daily` bugünkü ayrımı çürütüyor.** İstenen
tanımda alışkanlık *süreksiz* olacak; oysa `HabitCadence.daily` "her gün
yapılması beklenir" diyor ve `habit.dart:6` haftalık ritmi "esnek rutin" diye
anıyor. Yani bugünkü model iki kavramı birbirinin içine geçirmiş durumda.
Ayrımı yalnız ekran yazısıyla anlatmak bu çelişkiyi bırakırdı.

---

## 3. Karar Za — Pencere ile çoklu saat **iki ayrı alan**, tek alan değil

İkisini tek listeye sıkıştırmak mümkündü (ör. "saat aralıkları listesi").
Reddedildi: anlamları farklı.

* **Pencere** bir *kısıt*tır: iş **bir kez** yapılır, yeri serbesttir.
  "09:00–12:00 arasında" demek "üç saat sürecek" demek değildir.
* **Çoklu saat** bir *çoğalma*dır: aynı iş o gün **birkaç kez** olur ve her
  tekrar ayrı tamamlanır.

Tek alana yüklenselerdi "09:00–12:00" ifadesi hem "arada bir yerde" hem "üç
saat boyunca sürekli" diye okunabilirdi — kullanıcı hangisini kastettiğini
söyleyemezdi. `isFixed` kararında (`task.dart:217`) aynı gerekçe var: *iki
eksen tek alana yüklenirse ikisi de anlamını yitirir.*

## 4. Karar Zb — Pencere, esnekliğin **ölçüsü**; yeni bir eksen değil

Pencere yalnız esnek işlerde anlamlı: kımıldatılamaz bir işin (randevu, uçuş)
zaten çivili bir saati vardır. Bu yüzden pencere `isFixed`'i **değiştirmez**,
onu *nicelendirir*:

| İş | Bugün | Penceresiyle |
|---|---|---|
| Kımıldatılamaz | 14:00'te, taşınamaz | pencere alanı kapalı |
| Esnek, penceresiz | herhangi bir saate taşınabilir | bugünkü davranış korunur |
| Esnek, pencereli | — | yalnız pencere içinde taşınabilir |

Sonuç: Günü Kurtar bir işi pencerenin dışına **atamaz**. Pencereye sığdıramazsa
havuza alır — bugünkü davranışın aynısı, yalnız sınırı dar.

## 5. Karar Zc — Alışkanlık süreksiz, rutin sürekli; `daily` ritmi kalkıyor

| | Alışkanlık | Rutin |
|---|---|---|
| Ritim | **Süreksiz** — haftada N kez yeter | **Sürekli** — her gün / her hafta, düzenli |
| Saat | Yok; gün içinde istediğin an | Var; takvimde blok |
| Ölçü | Seri (streak) + ısı haritası | Tamamlama / atlama |
| Yer | Alışkanlıklar ekranı | Haftalık ızgara |

`HabitCadence.daily` kalkıyor. Bir şeyi *her gün belli saatte* yapmak
alışkanlık değil rutindir; uygulamada zaten rutin olarak daha iyi
karşılanıyor.

**Var olan günlük alışkanlıklar ne olacak.** Silinmez, susturulmaz: göçte
`daily` → `weekly(7)` olur. Anlamı korunur ("her gün" = "haftada yedi"),
serisi ve ısı haritası aynı verinin üstünde çalışmaya devam eder. Kullanıcı
isterse hedefi düşürür. Alternatif — günlük alışkanlıkları rutine çevirmek —
reddedildi: rutinin saati var, alışkanlığın yok; uydurulmuş bir saat
kullanıcının takvimine davetsiz blok koyardı.

## 6. Karar Zd — Ad değişikliği **görünen katmanda**, depoda değil

"Kalıcı iş" → "Kalıcı İş" masum görünüyor ama `categoryName` bir **metin** ve
hem yerelde hem sunucuda öyle duruyor (`task.dart:178`, `:466`). Düz yeniden
adlandırma üç yerde kırar: eski anlık görüntüler, senkronda bekleyen kayıtlar
ve **eski sürümdeki ikinci cihaz** — o cihaz eski adı geri yazar ve kategori
ikiye bölünür.

Karar: **depolanan değer değişmiyor**, `TaskCategory` bir *görünen ad* taşıyor.
Ekranlar görünen adı, depo eski anahtarı kullanıyor. Göç yok, senkron riski
yok, geri dönüş bedava.

| Depoda (değişmez) | Ekranda (yeni) |
|---|---|
| `Kalıcı iş` | **Kalıcı İş** |
| `Günlük rutin` | **Günlük Rutin** |
| `Haftalık / ara sıra` | **Haftalık / Ara Sıra** |
| `Önemli / acil` | **Önemli / Acil** |
| `Hobi / keyfi` | **Hobi / Keyfi** |
| `Sosyal`, `Diğer` | değişmiyor |

Aynı kural diğer özellik değerlerine de uygulanır: **Tek Günlük**, **Rutin**,
**Esnek**, **Kımıldatılamaz**, **Haftalık**, **Süreksiz**.

**Türkçe tuzağı — `toUpperCase()` kullanılmayacak.** Dart'ta `'iş'
.toUpperCase()` varsayılan yerelde **`IŞ`** verir, `İŞ` değil. Büyük harfe
çevirmeyi koda bırakmak "Kalıcı Iş" üretirdi. Görünen adlar **elle yazılıyor**;
bir test paletin tamamını tarayıp noktasız `I` arıyor (kategori renklerinde
kullanılan tarama kalıbının aynısı).

Kullanıcının eklediği özel kategoriler **olduğu gibi** gösterilir: kullanıcının
yazdığı ada karışmak, kendi verisini tanınmaz hâle getirmek olurdu.

---

## 7. Dilimler

### Z1 — Adlandırma: görünen ad katmanı ve Başlık Düzeni

`TaskCategory`'ye görünen ad; ekranlardaki özellik değerleri Başlık Düzeni'ne.

**Bitti sayılır:** depolanan hiçbir değer değişmedi (kalıcılık testi eski
anlık görüntüyü aynen okuyor); ekranlarda yeni yazım görünüyor; noktasız `I`
taraması yeşil.

### Z2 — Zaman penceresi: model ve kalıcılık

`Task.windowStart` / `windowEnd` (double?, 0–24). Şema 3 → **4**; eski kayıtta
alan yok → pencere yok.

**Bitti sayılır:** pencereli iş yazılıp okunuyor; sürüm 3 anlık görüntüsü
kayıpsız açılıyor; `windowStart > windowEnd` yazılamıyor.

### Z3 — Pencere: düzenleyicide seçim

`task_editor_sheet` içinde saat aralığı alanı. Kımıldatılamaz işte kapalı
(Zb), esnek işte açık.

**Bitti sayılır:** widget testi — kımıldatılamaz işaretlenince alan
kayboluyor; seçilen aralık kaydedilip geri açılışta duruyor.

### Z4 — Pencere: ızgarada görünmesi

Pencere, blokun arkasında soluk bir şerit. Blok şeridin içinde kayabilir.

**Bitti sayılır:** pencereli bir iş ızgarada şeritle çiziliyor; penceresiz iş
bugünkü gibi görünüyor (görünüm testi).

### Z5 — Pencere: Günü Kurtar'a saygı ✅

`planDayRescue` pencereyi kısıt olarak okur.

**Plandan bilinçli sapma.** §Zb "Günü Kurtar bir işi pencerenin dışına atamaz"
diyordu; bu, işleri saatlerini değiştirerek taşıyan bir kurtarma varsayıyordu.
Oysa kurtarma **hiçbir işin saatini değiştirmiyor** — havuza alıyor ya da
atlıyor. Pencerenin buradaki gerçek karşılığı, var olan "başlamış iş
süpürülmez" kuralının pencereli hâli oldu:

* Pencere **açıksa** (başladı, kapanmadı) iş korunuyor — başlamış saatli iş gibi.
* Pencere **kapandıysa** korunmuyor: o iş bugün artık olamaz, kenara
  alınacakların tam da kendisi. Açık pencereyle aynı kefeye konsaydı günün en
  kesin ölü işi ekranda kalırdı.
* Pencere **ileride** ise bugünkü davranış sürüyor.

Kural yalnız **saatsiz** işe uygulanıyor: saatli işte zaten `startHour`
kararı veriyor.

**Bitti sayılır:** birim testi — açık pencere korunuyor, kapanmış pencere
havuza iniyor, ileride duran pencere ve penceresiz iş bugünkü davranışta.

### Z6 — Çoklu saat: model ve tamamlanma

`Task.timesOfDay` (List&lt;double&gt;). `startHour` **kalıyor** ve listenin ilk
öğesinin aynası oluyor: `date`'in nullable yapılmama gerekçesiyle aynı gerekçe
(`task.dart:205`) — `startHour` kod tabanında çok yerde okunuyor, kaldırmak her
çağrı yerine bir hata fırsatı eklerdi.

Tamamlanma slot başına: `completedOn` gün hassasiyetinde kalır, yanına
`completedSlots` gelir. Aynı kümede toplansalardı "sabah içtim" ile "üçünü de
içtim" ayırt edilemezdi — `completedOn`/`skippedOn` ayrımının (`task.dart:231`)
aynı mantığı.

**Bitti sayılır:** üç saatli bir iş üç kez ayrı işaretlenebiliyor; ikisi
işaretliyken iş "tamamlandı" saymıyor; kalıcılık testi yeşil.

### Z7 — Çoklu saat: düzenleyici ve ızgara

Saat listesi (ekle/çıkar) ve ızgarada aynı günde birden çok blok.

**Bitti sayılır:** üç saat girilen iş ızgarada üç blok çiziyor; her blok kendi
başına işaretleniyor.

### Z8 — Sunucu göçü

`05_<damga>_zaman_araliklari.sql`: pencere, çoklu saat ve slot tamamlanma
alanları. Ad, sıra numarası taşıyan kalıba uyar.

**Bitti sayılır:** şema testi yeni alanları görüyor; eski istemci yeni sütunlar
karşısında kırılmıyor (alanlar nullable).

### Z9 — Alışkanlık–rutin ayrışması ✅

`HabitCadence.daily` kalkar, göçte `weekly(7)` olur (Zc). Alışkanlıklar ve
Rutinler ekranlarının başlık/boş durum metinleri ayrımı anlatır.

**Bitti sayılır:** günlük alışkanlık taşınmış ve serisi bozulmamış; iki ekranın
metinleri ayrımı söylüyor; alışkanlık ekranında saat alanı hiç yok.

---

## 8. Kapsam Dışı

Pencerenin senkron çakışmasında alan bazlı birleştirilmesi (son yazan kazanır
duruyor), çoklu saatin bildirim/hatırlatmaya bağlanması (bildirim özelliği
henüz yok), pencerenin rutinlerde gün gün farklılaşması, alışkanlığın saatli
hâle gelmesi, özel kategori adlarının otomatik düzeltilmesi.

---

## 9. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| Kategori adını depoda değiştirmek veriyi ikiye böler | **Yüksek** | Zd: depo dokunulmuyor, yalnız görünen ad değişiyor |
| `toUpperCase()` ile "Kalıcı Iş" üretmek | **Yüksek** | Adlar elle yazılıyor; noktasız `I` taraması test altında |
| `startHour`'ı listeye çevirmek çok yeri kırar | **Yüksek** | Z6: alan kalıyor, liste yanına geliyor |
| Pencere + çoklu saat birlikte anlamsız hâle gelir | Orta | Düzenleyicide ikisi aynı anda açılamaz; test bunu bekliyor |
| Günlük alışkanlıkların göçü seriyi bozar | Orta | `weekly(7)` anlamı koruyor; göç testi seriyi ölçüyor |
| Kapsam büyük, tek oturumda bitmez | **Kesin** | Dokuz dilim; Z1 tek başına bile istenen adlandırmayı verir |

---

## 10. Sıra

Z1 → Z2 → Z3 → Z4 → Z5 → Z6 → Z7 → Z8 → Z9.

Z1 önde: risksiz, göçsüz ve istenen üç şeyden birini tek başına bitiriyor.
Pencere (Z2–Z5) çoklu saatten (Z6–Z7) önce: pencere var olan esnek/sabit
eksenine oturuyor, çoklu saat ise tamamlanma modeline dokunuyor — sırayla
gidilirse ikincisi birincinin testleri altında yapılır. Z9 en sonda: veri göçü
taşıyor ve gerisi ondan bağımsız çalışıyor.
