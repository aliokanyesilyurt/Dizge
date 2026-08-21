# Onay · Gezinme · Rapor · Havuz Planı

**Durum:** ✅ **tamamlandı** — D1–D4 indi, D5 canlı konum yerine **yer
önerisi** olarak indi (21 Ağustos kullanıcı kararı)
**Tarih:** 21 Ağustos 2026
**Kaynak:** kullanıcının beş maddelik geri bildirimi (21 Ağustos)

---

## 1. Amaç

Beş şikâyetin dördü aynı kökten geliyor: **var olan bir yetenek ekranda
görünmüyor.** Atlama var ama yalnız haftalık ızgarada; havuz var ama boşken
hiç iz bırakmıyor; tamamlama var ama tek bir ekranda; rapor gün aralığını
hesaplıyor ama grafik onu göstermiyor.

Bu yüzden plan yeni bir sistem kurmuyor. Yaptığı şey: **her yeteneğin
kullanıcının onu aradığı yerde bir düğmesi olması.** Beşinci madde (canlı
konum) tek gerçek yeni özellik ve en sona konuyor.

---

## 2. Mevcut Durum (doğrulanmış)

| Şikâyet | Kod gerçeği | Dosya |
|---|---|---|
| "aylık geçiş için üstte buton yok" | Başlıkta yalnız "12 ay" ve "Rutinler" var; ay geçişi **yalnız yatay kaydırma**, üstelik ipucu küçük punto | `screens/monthly_view_screen.dart:126-163` |
| aynısı — daha kötüsü | `final int year = DateTime.now().year;` — `PageView` **12 sayfa**. Aralık'tan Ocak'a geçilemiyor, geçen yıla bakılamıyor | `monthly_view_screen.dart:78`, `year_view_screen.dart:30` |
| "raporlar gün sayısına göre düzenlenmiyor" | `HBarChart` çubukları **kendi içinde en büyüğe göre** normalleştiriyor → 7g ile 90g'de çubuklar birebir aynı boyda çıkıyor, yalnız sağdaki küçük süre metni değişiyor | `widgets/report_charts.dart:126` |
| aynısı | `dailyCompletion` hesaplanıyor ama **hiçbir grafik onu çizmiyor** — trend çizgisi yok, yani aralığın tek gerçek görsel karşılığı eksik | `services/productivity_report.dart:36`, `screens/reports_screen.dart` |
| aynısı | Atlanan rutin günü `planned` sayılıyor, `completed` sayılmıyor → bilerek atlanan gün oranı **cezalandırıyor** | `productivity_report.dart:84-102` |
| "onay tuşu yok" | `TaskListScaffold._Row` satırında onay kutusu yok; Rutinler ve Yapılacaklar ekranlarında tamamlama **mümkün değil** | `screens/task_list_scaffold.dart:148-252` |
| "takvimden işaretleyemiyorsun" | Blok önizlemesinde dört eylem var — Düzenle · Kopyala · Sil · Bugün atla — **"Yaptım" yok** | `widgets/week_grid/block_preview.dart`, `event_block.dart:330-370` |
| aynısı | Aylık hücrede işler yazılı ama hücre **tek bir `GestureDetector`** — tek işe dokunmak mümkün değil | `monthly_view_screen.dart:285` |
| tamamlamanın tek yeri | `setTaskDone` yalnız iki yerden çağrılıyor: gün görünümü ve haftalık saatsiz satır (uzun basış) | `day_view_screen.dart:236`, `week_view_screen.dart:547` |
| "havuzun nerede olduğu belli değil" | Havuz boş **ve** panel kapalıysa `SizedBox.shrink()` — ekranda sıfır iz. Kenar çubuğunda da girişi yok | `week_view_screen.dart:615` |
| "tek gün iptal" | Model hazır: `skippedOn`, `setSkipped`, `inPool`, `moveToPool` hepsi var ve sınanmış. Eksik olan yalnız arayüz kapısı | `models/task.dart:400-415`, `data/app_store.dart:315-405` |
| "canlı konum" | `place` düz metin. Konum paketi yok, izin tanımı yok | `models/task.dart:173`, `pubspec.yaml` |

**Kritik bulgu:** beş maddenin dördü için **model değişikliği gerekmiyor.**
Yalnızca D5 (konum) yeni alan istiyor.

**İkinci bulgu:** rapor şikâyeti gerçek bir hata. Kullanıcı "sayılar
değişmiyor" derken haklı — çubuk grafiği kendi maksimumuna göre ölçeklendiği
için 7 günle 90 gün **görsel olarak birebir aynı** çıkıyor.

---

## 3. Mimari Kararlar

### K1 — `NavState.month` mutlak ay damgasına çevrilir

Bugünkü hâli `int? month` (0 = Ocak) ve **yıl bilgisi taşımıyor**. Aylık ekran
da bu yüzden `DateTime.now().year` diye sabitliyor. Sonsuz gezinme bu alan
düzelmeden mümkün değil.

Yerine:

```dart
/// [AppSection.month] için açılacak ay (ayın ilk günü). Boşsa içinde
/// bulunulan ay. Yıl artık burada — takvim yıl sınırında durmasın.
final DateTime? monthAnchor;
```

`PageView` sayfa numarası da mutlak ay indeksine bağlanır
(`y * 12 + (m - 1)`), `itemCount` kaldırılır. Aynı düzeltme yıl görünümüne de
uygulanır (`YearViewScreen` zaten `year` parametresi alıyor, yalnız kimse
vermiyor).

**Reddedilen alternatif:** `PageView`'i 12 yerine 1200 sayfa yapmak. Sayı
büyütmek sınırı gizler, kaldırmaz — ve Aralık→Ocak geçişi hâlâ yıl atlamaz.

### K2 — Tek bir onay kontrolü, dört ekranda aynısı

Yeni `lib/widgets/task_check.dart` → `TaskCheck` widget'ı. Onay kutusunun
görsel dili, dokunma alanı, animasyonu ve erişilebilirlik etiketi tek yerde
tanımlanır; Yapılacaklar, Rutinler, blok önizlemesi ve aylık hücre onu
kullanır.

**Neden ayrı widget:** aynı işaretin dört ekranda dört farklı boyda çizilmesi
"bu ikisi aynı şey mi" sorusunu üretir. Onay, uygulamanın en sık yapılan
hareketi — dört yerde de aynı görünmesi lüks değil.

**Rutinlerde tamamlama gün bağlıdır.** Rutinler ekranı takvimden bağımsız düz
bir liste; oradaki onay kutusu **bugünü** işaretler ve alt metinde bunu yazar
("bugün tamamlandı"). Aksi hâlde tek kutu, tekrar eden bir işin hangi gününü
kastettiğini söyleyemez.

### K3 — "Bugün iptal" tek kapıdan geçer

Kullanıcı "bir işi tek bir gün içinde iptal etmek" istiyor. Kod bunu **iki
ayrı mekanizmayla** yapıyor ve hangisinin geçerli olduğunu kullanıcının
bilmesini bekliyor:

* rutin → `skipRoutineOn` ("Bugün atla")
* tek günlük iş → `moveToPool` ("Kenara al")

Ayrım doğru (bkz. `esnek-plan-sistemi-plani.md` K2) ama **kullanıcıya
yansıtılmamalı.** `AppStore`'a tek kapı:

```dart
/// İşi o gün için iptal eder. Rutinse günü atlar, tek günlük işse havuza
/// alır. Çağıran tarafın hangisi olduğunu bilmesi gerekmiyor — menüde tek
/// satır görünsün diye.
void cancelOn(Task task, DateTime day);
```

Menü etiketi her yerde aynı: **"Bugün iptal"** / geri alma **"İptali geri
al"**. Bildirimde ne olduğu yazılır ("kenara alındı" / "bugünlük atlandı"),
böylece mekanizma gizlenmiyor, yalnızca *seçtirilmiyor*.

### K4 — Havuz kenar çubuğuna çıkar

Havuz bugün yalnız haftalık görünümün sağ kenarında ve **boşken görünmez**.
Kullanıcı onu bulamamasının sebebi bu: hiç kullanmamış biri için hiç yok.

Kenar çubuğunda "Listeler" başlığı altına üçüncü satır:
`Kenarda Bekleyenler` (`Icons.inbox_rounded`), sayı rozetiyle. Yeni
`AppSection.pool` + `PoolScreen` — `TaskListScaffold`'u yeniden kullanır,
satır eylemi "Takvime geri koy".

Haftalık ızgaradaki şerit **kalır**: sürükle-bırak hedefi olarak orada olması
gerekiyor. Değişen tek şey, havuzun artık ikinci bir kapısının olması.

### K5 — Atlanan gün planlanan sayılmaz

`ProductivityReport.build` içinde tek satır:

```dart
if (t.isSkippedOn(day)) continue;  // bilerek atlanan gün oranı düşürmez
```

**Neden doğru karar:** "planımı tutamadım" ile "bu işi bugün yapmamaya karar
verdim" aynı şey değil. Sistemin tüm amacı (bkz. esnek plan sistemi planı §1)
suçluluk üretmemek; atlanan günü kaçırılmış saymak tam tersini yapıyor.

### K6 — Aralık grafiği: mutlak toplam değil, **günlük ortalama**

`HBarChart` kendi maksimumuna göre ölçeklendiği için aralık değişince şekil
değişmiyor. İki düzeltme:

1. Kategori/etiket çubukları **günde ortalama saat** gösterir
   (`hours / days`), sağdaki metin "günde 1s 20d" olur. Aralık değişince sayı
   da anlamı da değişir.
2. `dailyCompletion` için yeni `TrendChart` — aralık boyunca tamamlanma
   çizgisi. 7g'de 7 nokta, 90g'de 90 nokta: aralığın **görünür** karşılığı bu
   grafik. Zaten hesaplanıyordu, yalnız çizilmiyordu.

Ayrıca üst kartta "günde ortalama X iş" satırı — üç mutlak sayının yanında
aralığa duyarlı tek metrik.

### K7 — Konum: koordinat modele girer, adres girmez · **düştü**

> **21 Ağustos:** kullanıcı canlı konumu istemedi. Bu karar uygulanmadı;
> yerine K7′ (aşağıda) geçti. Bölüm, neden vazgeçildiği görünsün diye duruyor.

`Task`'a iki opsiyonel alan (`double? lat, lon`). Ters coğrafi kodlama
(koordinat → "Kadıköy, İstanbul") **çevrimiçi bir servis** ister; uygulama
offline-first ve dışarı veri göndermeme sözü verdi
(`services/productivity_report.dart` başlık notu). Bu yüzden:

* `place` alanı kullanıcının yazdığı metin olarak kalır,
* "Konumumu al" düğmesi koordinatı yakalar ve `place` boşsa oraya
  `41.0082, 28.9784` biçiminde koyar — kullanıcı üstüne yazabilir,
* harita ve adres çözümleme **kapsam dışı**.

**Bu dilim en sona ve isteğe bağlı işaretli.** Sebebi: `geolocator` üç
platformda üç ayrı izin tanımı, Android'de `ACCESS_FINE_LOCATION` (mağaza
dışı yan yükleme için bile kullanıcı onayı ekranı) ve APK'ya ek boyut
demek — kullanıcının kendi deyimiyle "fark da etmez".

---

### K7′ — Yer önerisi kullanıcının kendi geçmişinden gelir

"Yazınca konum çıksın" iki biçimde okunabilir: çevrimiçi bir yer arama
servisi, ya da daha önce yazdığın yerlerin tamamlanması. Birincisi her tuş
vuruşunda dışarı istek atar — uygulamanın "veri dışarı gitmez" sözünü
(`services/productivity_report.dart` başlık notu) bozar ve API anahtarı
ister. İkincisi hem offline hem de pratikte daha isabetli: kimse her gün yeni
bir yere gitmiyor, "Ev · Ofis · Spor salonu" listesi üç işten sonra doluyor.

Bu yüzden öneriler **var olan işlerin `place` alanlarından** türetilir,
sıklığa göre sıralanır. Model değişmiyor, bağımlılık eklenmiyor.

---

## 4. Dilimler

Sıra bilinçli: en çok şikâyet edilen ve en ucuz olan önce.

### D1 — Ay ve yıl gezinmesi (K1)

* `NavState.month` → `monthAnchor` (DateTime); `openMonth(DateTime)`.
* `MonthlyViewScreen`: başlığa **‹ ›** düğmeleri + "Bugün"; `PageView` sonsuz,
  sayfa indeksi mutlak ay damgası.
* `YearViewScreen`: başlığa **‹ ›** yıl düğmeleri; `year` durum olarak tutulur.
* `AppShell._contentFor` yeni imzaya uyar.

**Kabul ölçütü:** Aralık'ta ›'ye basınca Ocak (gelecek yıl) açılır; yıl
görünümünde ‹ geçen yılı getirir; kaydırma davranışı bozulmaz.
**Test:** `test/monthly_navigation_test.dart` — yıl sınırı geçişi, "Bugün"
dönüşü.

#### D1 kapanış notu (21 Ağustos) — **tamamlandı**

Planlanandan bir adım fazlası yapıldı: başlık ve hafta günü satırı
`PageView`'in **dışına** alındı. İçerideyken her ayın kendi kopyası vardı;
oklar ay değiştirirken yatayda kayıyor, gün adları da ayla birlikte
sürükleniyordu. Dışarı alınınca ok düğmeleri tek örnek oldu — testin tek bir
`Sonraki ay` bulabilmesinin sebebi de bu.

`NavState.month` → `anchor` göçü beklenenden ucuz çıktı: alan yalnız üç yerde
okunuyordu (`app_shell`, `year_view`, `shell_navigation_test`). Yıl görünümü
de `ConsumerWidget`'tan `ConsumerStatefulWidget`'a geçti, çünkü yıl artık
dışarıdan verilen değil ekranın gezdirdiği bir değer.

"Bugün", haftalık başlıktaki gibi ayrı bir düğme olmadı: ipucu satırının
yerine geçen bir bağlantı. Ay başlığında dört ikon düğmesi zaten var; beşinci
bir kutu, bulunduğun ayda hiçbir işe yaramayacakken sürekli yer kaplardı.

**Durum:** 9 yeni test, toplam 576 test geçiyor, `flutter analyze` temiz.

### D2 — Onay tuşu dört ekranda (K2)

* Yeni `widgets/task_check.dart`.
* `TaskListScaffold._Row`: satır başına onay kutusu; `onToggleDone` geri
  çağrısı eklenir (opsiyonel — vermeyen ekranlar kutusuz kalır).
* `TodosScreen`: kutu `t.date` gününü işaretler.
* `RoutinesScreen`: kutu **bugünü** işaretler, alt metinde bugünkü durum.
* `block_preview.dart`: en üste birincil eylem olarak "Yaptım / Geri al".
* `event_block.dart`: üstüne gelince çıkan eylem sırasına onay ikonu.
* `monthly_view_screen.dart` `_entry`: her iş satırı kendi `GestureDetector`'ı
  olur; dokunuş o işi tamamlar, hücrenin boşluğuna dokunuş eski davranışta
  kalır (seç → aç).

**Kabul ölçütü:** aynı işi beş ekrandan da işaretleyip geri alabilmek; işaret
her ekranda anında yansımak (store zaten `_touched` yayınlıyor).
**Test:** `test/task_check_test.dart` — her ekran için işaretle/geri al.

#### D2 kapanış notu (21 Ağustos) — **tamamlandı**

Plandan üç sapma, üçü de uygulamada ortaya çıktı:

**1. Önizlemede düğme değil kutu.** Karta üçüncü bir `ShadButton` eklemek
320 pikseli taşırıyordu. Ama kartın başlık satırında zaten bir yer vardı:
tamamlanmışlığı *bildiren* soluk ✓ ikonu. O ikonun yerine `TaskCheck`
konunca kart hiç büyümedi ve eylem, göz zaten baktığı yerde belirdi.

**2. Sağ tık menüsüne de kondu, en üste.** Fare kullanıcısının kestirmesi;
önizlemeyi açmayı beklemesin diye.

**3. Çoklu saatli işlerde tik tekrarın kendisi.** Izgara `done` durumunu
zaten `isSlotDone` ile hesaplıyordu (Z6); kutunun yazdığı yer de aynı
olmalıydı. `WeekTimeGrid.onToggleDone` bu yüzden üç parametreli:
`(task, day, slotHour?)`. Sabah dozunu işaretlemek akşamkini bitirmiyor.

Aylık hücrede iş satırı **kendisi** onay kutusu oldu; ayrı bir kutu, T.dense
yüksekliğindeki bir satırın yanına sığmazdı. Nokta bitmişken ✓ oluyor —
tamamlanmışlık yalnız dolgunun yokluğuna bağlı kalmasın diye (WCAG 1.4.1).
Hücrenin boşluğu eski davranışında: bir dokunuş seçer, ikincisi günü açar.

`TaskListScaffold` onay kutusunu **isteğe bağlı** aldı (`isDone` null ise
çizilmiyor): tamamlama kavramı olmayan bir liste iskeleti kullanabilsin.
Rutinlerde `checkScopeLabel: 'bugün'` zorunlu — tekrar eden bir işin
yanındaki tek kutu, hangi günü kastettiğini söylemezse "bu rutini tamamen
bitirdim" diye okunur.

**Durum:** 8 yeni test, toplam 584 test geçiyor, `flutter analyze` temiz.

### D3 — Rapor düzeltmesi (K5, K6)

* `productivity_report.dart`: atlanan gün elenir; `TimeBucket`'a `perDay`
  türetimi; `days` alanı rapora eklenir (grafiklerin bölene erişmesi için).
* `report_charts.dart`: yeni `TrendChart` (çizgi + soluk alan, 0–1 ekseni).
* `reports_screen.dart`: trend kartı eklenir; kategori/etiket metinleri
  "günde …" olur; üst karta "günde ortalama X iş".
* Aralıkta veri yoksa boş durum metni aralığı söyler ("son 7 günde iş yok").

**Kabul ölçütü:** 7g ↔ 90g arasında geçiş yapınca **her üç grafik de** gözle
görülür biçimde değişir; atlanan rutin oranı düşürmez.
**Test:** `test/productivity_report_test.dart` — atlanan gün senaryosu,
aralık duyarlılığı (aynı veriyle 7g ≠ 30g).

#### D3 kapanış notu (21 Ağustos) — **tamamlandı**

Uygulamada K6'nın birinci maddesinin **tek başına yetmediği** görüldü ve
plan bu noktada düzeltildi.

Günlük ortalamaya geçmek sayıları anlamlı yapıyor ama **çubukların şeklini
değiştirmiyor**: `HBarChart` kendi maksimumuna göre ölçekliyor, bütün
değerleri aynı sabite bölmek oranları hiç kımıldatmıyor. Yani "grafikler
değişmiyor" şikâyetinin gerçek cevabı ikinci madde: **trend grafiği.**
Aralıkta kaç gün varsa o kadar nokta çiziyor — 7g'de yedi, 90g'de doksan.
Ekranda aralığı gerçekten gösteren tek şey o.

Günlük ortalama yine de yapıldı, ama başka bir gerekçeyle: mutlak toplam
aralık uzadıkça zaten büyür. "90 günde 90 saat", "7 günde 7 saat"ten fazla
bir şey söylemez; günde ortalama iki aralığı karşılaştırılabilir kılıyor.

`dailyCompletion` için **-1 sentinel'i** eklendi (eskiden 0 yazıyordu). İş
yazılmamış bir günü sıfırla göstermek, onu "planladım hiçbirini yapmadım"
günüyle aynı kefeye koyuyordu; trend o günlerde sıfıra inmek yerine kopuyor.
`weekdayCompletion` zaten aynı sözleşmeyi kullanıyordu — ikisi artık tutarlı.

Test yazarken iki kendi hatam çıktı ve ikisi de öğreticiydi: 60 gün önce
başlayan bir rutin 90 günlük pencerede 61 tekrar veriyor (fixture düzeltildi),
ve `formatDuration` "1 sa" yazıyor "1s" değil.

**Durum:** 10 yeni test, toplam 594 test geçiyor, `flutter analyze` temiz.

#### D3 ek kapanış (21 Ağustos akşamı) — boş durum aralığı söylüyor

Dilimin "aralıkta veri yoksa boş durum metni aralığı söyler" maddesi atlanmış;
metin sabit kalmıştı ("Rapor için yeterli veri yok"). Ekranda aralık zaten
başlıkta yazdığı için etkisi küçüktü ama tavsiye yanlıştı: aralık dışında
kalmış verisi olan kullanıcıya "birkaç görev ekleyin" deniyordu.

Boş durum artık iki hâli ayırıyor: hiç iş yoksa görev eklemeyi, iş varken bu
aralığa düşen yoksa **aralığı genişletmeyi** söylüyor — 90g seçiliyken
genişletme tavsiyesi düşüyor, gidecek yer kalmadığı için.

**Durum:** 2 yeni test, toplam 621 test geçiyor, `flutter analyze` temiz.

### D4 — "Bugün iptal" ve havuzun görünürlüğü (K3, K4)

* `AppStore.cancelOn(task, day)` + `undoCancelOn`.
* Blok önizlemesi, aylık hücre uzun basışı ve liste satırları: tek etiket
  "Bugün iptal".
* `AppSection.pool` + `PoolScreen` + kenar çubuğu satırı (sayı rozetli).
* Haftalık şerit yerinde kalır.

**Kabul ölçütü:** rutin ve tek günlük iş, aynı menü satırıyla iptal edilir;
iptal edilen tek günlük iş kenar çubuğundaki Havuz ekranında görünür; "Geri
al" ikisini de eski hâline döndürür.
**Test:** `test/cancel_on_test.dart` — iki tür iş, iptal + geri alma.

#### D4 kapanış notu (21 Ağustos) — **tamamlandı**

Plan "menüde tek satır görünsün" diyordu; uygulamada görüldü ki **etiketi
birleştirmek yetmiyor**, geri çağrıyı da birleştirmek gerekiyor. Blok iki ayrı
alan (`onMoveToPool`, `onToggleSkip`) taşımaya devam etseydi, hangisinin
çizileceğine yine widget karar verecekti — yani ayrım ekrandan silinip koda
gömülecekti. İkisi tek bir `onCancel`'a indi; `EventBlock` bir alan kaybetti.

`cancelOn` bir **cümle döndürüyor** ("kenara alındı" / "bugünlük atlandı").
Önce `void` idi ve bildirimi ekran kuruyordu; ama o zaman her çağrı yerinin
`task.isRoutine`'e bakması gerekiyordu — kapının tek olmasının anlamı da
kalmıyordu. Mekanizmayı bilen tek yer mağaza, cümleyi de o kuruyor.

**Önizleme kartındaki sıra `Row` değil `Wrap` oldu.** Etiket duruma göre
uzuyor ("Bugün iptal" → "İptali geri al") ve 320 pikselde taşıyordu. Kart bir
kez genişlemişti (260 → 320); üçüncü kez genişletmek yerine sıra kırılabilir
oldu. Yan kazanç: yazı tipi büyütülmüş bir ekranda da taşmıyor.

Aylık hücrede iptal **uzun basış**: kısa dokunuş zaten en sık istenen şeyi
(tamamlama) yapıyor ve hücrede menü açacak yer yok. Atlanan gün orada da
solgun + üstü çizili, işareti ✓ değil ↷ — "yapıldı" ile "bugünlük geçildi"
aynı simgeyle anlatılamaz.

`TaskListScaffold` iki şey kazandı: satır sonunda tek bir `TaskRowAction` ve
**isteğe bağlı** kayan ekleme düğmesi. Havuz ekranında "Yeni" yok — havuz iş
kurulan yer değil, var olan işin bekleme yeri. Onay kutusu da yok: kenara
alınmış bir işi "yaptım" diye işaretlemek, önce takvime dönmesi gereken bir
işi atlamak olurdu.

Geri alma bildirimi (`_offerUndo`) haftalık ekranın özel metoduydu; iptal dört
ekrana yayılınca `widgets/undo_toast.dart`'a çıktı. Kenar çubuğundaki rozet
daraltılmış halde sayı yerine nokta gösteriyor, sayıyı ipucuna veriyor; ekran
okuyucuya da "2 iş bekliyor" diye okunuyor — çıplak bir "2" neyin ikisi
olduğunu söylemiyordu.

Test yazarken bir kendi hatam çıktı: günlük rutin aylık ızgaranın **her**
hücresinde duruyor, yani `find.text('↻ Koşu').first` atlanan güne değil ayın
birine denk geliyordu. Doğru soru "hangisi çizili" değil, "kaç tanesi çizili".

**Durum:** 13 yeni test, toplam 607 test geçiyor, `flutter analyze` temiz.

### D5 — Yer önerisi (K7′) · *canlı konumun yerine geçti*

**21 Ağustos, kullanıcı kararı:** "canlı konumu alma, yazınca konum çıksın."
GPS dilimi düştü; yerine yer alanının **kendi geçmişinden** öneri veren bir
tamamlama kondu.

* Yeni `lib/widgets/editor/place_field.dart`:
  * saf fonksiyon `placeSuggestions(tasks, query, {limit})` — daha önce
    yazılmış `place` değerlerinden, **kullanım sıklığına** göre sıralı liste;
  * `PlaceField` — metin alanı + altında öneri çipleri.
* `task_editor_sheet.dart` `_placeRow`: düz `TextField` yerine `PlaceField`.
* Eşleme Türkçe katlamalı (`İstanbul` ≡ `istanbul`), önce baştan eşleşenler.
* Alan boşken sık kullanılan ilk birkaç yer görünür — öneri, aramadan önce de
  var; kullanıcı hiç yazmadan seçebilsin.

**Kabul ölçütü:** "Ev" bir kez yazıldıktan sonra, ikinci işte "e" yazınca
öneri çıkıyor ve çipe dokunmak alanı dolduruyor; hiç yer yazılmamış bir
kurulumda hiçbir çip çıkmıyor.
**Test:** `test/place_suggest_test.dart` — sıralama/katlama (saf fonksiyon) ve
editörde çipe dokunuş.

#### D5 kapanış notu (21 Ağustos) — **tamamlandı**

Plandan tek sapma, testin ortaya çıkardığı bir kural değişikliği:

**Elenen öneri "aynı yer" değil, "aynı yazım".** Önce katlanmış anahtar
sorguya eşitse öneri gizleniyordu; o kural "sisli" yazan kullanıcıya
"Şişli"yi göstermiyordu — yani katlama eşlemeyi kolaylaştırıp tam da
kolaylaştırdığı yerde susuyordu. Şimdi yalnız **birebir** aynı yazım eleniyor:
"Şişli" yazana öneri çıkmıyor, "sisli" yazana çıkıyor ve dokunuş yazılanı
düzeltiyor. Öneri listesi böylece ikinci bir iş görüyor — aynı yerin üç ayrı
yazımla birikmesini engelliyor.

Sıralama iki basamaklı: önce ön ek ("of" yazan "Ofis"i arıyor, "Yeni ofis"i
değil), sonra sıklık. Üçüncü basamak alfabetik — eşit sıklıkta liste her
açılışta aynı sırada çıksın diye; `Map` sırasına bırakmak testi de kırılgan
yapardı.

Alan boşken çıkan çiplerin üstünde "Daha önce yazdıkların" yazıyor. Etiketsiz
hâlde çipler "önerilen yerler" gibi okunuyordu; oysa hepsini kullanıcı kendi
yazmış, uygulama hiçbir yer bilmiyor.

**Durum:** 12 yeni test, toplam 619 test geçiyor, `flutter analyze` temiz.

### D5-eski — Canlı konum (K7) · **düşürüldü**

`geolocator` + üç platformda izin tanımı + APK boyutu, kullanıcının
"fark da etmez" dediği bir özellik için. Koordinat saklama kararı (K7) da
onunla birlikte düştü: `Task` yeni alan almadı, model olduğu gibi kaldı.
Harita ve adres çözümleme zaten kapsam dışıydı.

## 5. Riskler

| Risk | Karşılık |
|---|---|
| `NavState` imza değişikliği kabuk + üç ekranı kırar | Tek commit'te; `flutter analyze` + 567 test kapı olarak |
| Aylık hücrede iş satırı tıklanır olunca hücre seçimi zorlaşır | İş satırları hücrenin **üstünde** ayrı hedef; boşluk payı korunur (satır yüksekliği ≥ 18px) |
| Rutinler ekranındaki onay kutusunun "hangi gün" belirsizliği | Alt metin her satırda bugünü yazar; K2'de karara bağlandı |
| `geolocator` APK boyutunu büyütür | D5 isteğe bağlı ve en sonda; istenmezse hiç eklenmez (bkz. ABI filtreleme çalışması) |
| Rapor formülü değişince eski ekran görüntüleri tutmaz | Kasıtlı: eski sayı yanlıştı |

---

## 6. Kapsam Dışı

* Harita görünümü, adres çözümleme, konuma göre hatırlatma.
* Rapor için yeni metrik türleri (odak süresi, pomodoro dökümü).
* Havuz için otomatik yeniden planlama önerisi.
* Aylık görünümde sürükle-bırak.
* Geçmişe dönük çok adımlı geri alma.

---

## 7. Kararlar

| # | Karar | Gerekçe |
|---|---|---|
| K1 | `NavState.month` → `monthAnchor: DateTime` | Yıl sınırı ancak böyle kalkar |
| K2 | Tek `TaskCheck` widget'ı | En sık hareket dört ekranda aynı görünmeli |
| K3 | "Bugün iptal" tek kapı, mekanizma gizli | Kullanıcı rutin/tek-günlük ayrımını bilmek zorunda değil |
| K4 | Havuz kenar çubuğuna çıkar, şerit kalır | Boşken görünmeyen özellik keşfedilemez |
| K5 | Atlanan gün planlanan sayılmaz | Bilerek atlama başarısızlık değil |
| K6 | Grafikler günlük ortalamaya geçer + trend eklenir | Aralık seçicisinin görünür bir karşılığı olsun |
| ~~K7~~ | ~~Koordinat saklanır, adres çözülmez~~ | **Düştü** — kullanıcı canlı konumu istemedi (21 Ağustos) |
| K7′ | Yer önerisi kullanıcının kendi `place` geçmişinden | Çevrimiçi yer araması offline-first sözünü bozardı; sıklık listesi pratikte daha isabetli |
