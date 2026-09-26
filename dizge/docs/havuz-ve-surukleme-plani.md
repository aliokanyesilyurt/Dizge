# Havuz ve Sürükleme Planı — Süre Tutamağı · Aylık Taşıma · Sorumluluk Havuzu

**Durum:** **tamamlandı** — D1–D6 indi (26 Eylül 2026). Açık sorularda varsayılanlar: elle sıralama yok, "Bu hafta/Sonra" ayrımı yok.
**Tarih:** 26 Eylül 2026

---

## 1. Amaç

Üç istek, tek fikir: **işi elle tutup yerine koymak.**

1. Haftalık ızgarada süre tutamağı çalışmıyor → onar.
2. Aylık görünümde işler günler arasında sürüklenebilsin.
3. Havuz, "iptal edilen işin çöp kutusu" olmaktan çıkıp **sorumluluk
   havuzuna** dönüşsün: işler önce havuza yazılır, sonra haftanın günlerine
   sürüklenerek dağıtılır.

---

## 2. Mevcut Durum (doğrulanmış)

| Ne | Nerede | Durum |
|---|---|---|
| Süre tutamağı | `week_time_grid.dart` `_onResizeUpdate` | **Bozuk** — ayrıntı §3 H1 |
| Aylık iş satırı | `monthly_view_screen.dart` `_TaskBox` | Dokun = tamamla, uzun bas = hızlı menü. Sürükleme yok, hücre bırakma hedefi değil |
| Havuza giriş | `AppStore.moveToPool` | **Tek yol** "Bugün iptal". Havuza doğrudan iş yazılamıyor |
| Havuz paneli | `week/pool_panel.dart` | Yalnız haftalıkta, yalnız ≥900 px, boş+kapalıyken görünmez |
| Havuzdan bırakma | `WeekTimeGrid` `DragTarget` | Yalnız **saat ızgarasına** — iş zorunlu olarak bir saate çakılıyor |
| Gün başlığı / saatsiz şerit | `day_headers.dart`, `untimed_row.dart` | Bırakma hedefi **değil** |
| Havuz ekranı | `pool_screen.dart` | "Yeni" bilinçli olarak yok: *"iş takvimde doğar, buraya çekilir"* |
| Telefon | `app_shell.dart` | Havuz ayrı sekme — sürükleyecek takvim yanında değil |

**Kritik bulgu:** Havuzun "entegre değil" hissettirmesinin sebebi bir eksik
özellik değil, **eski bir tasarım kararı**. Havuz bilerek *bekleme yeri* olarak
kuruldu (esnek-plan K1, onay-gezinme K4). İstenen şey onu *başlangıç yeri*
yapmak. Bu plan o kararı açıkça tersine çeviriyor.

---

## 3. Kararlar

### H1 — Süre tutamağı: kök sebep bulundu

```dart
final next = snapHour(resize.duration + details.delta.dy / _m.hourHeight)
```

Her fare olayının **küçük adımı** (1–5 px) ayrı ayrı 15 dakikaya yuvarlanıyor.
60 px/saatte 3 px = 3 dk → 0'a yuvarlanıyor → süre hiç değişmiyor. Yalnız hızlı
çekişte (bir olayda ≥8 px) basamak atlıyor; bu yüzden "bazen çalışıyor, çoğu
zaman çalışmıyor" hissi. Yoğunluk "rahat"a alındıysa saat yüksekliği arttığı
için daha da kötüleşiyor.

**Doğrulandı:** geçici bir testte 20 × 3 px'lik yavaş çekme → `onResize`
**hiç çağrılmadı**. Mevcut test tek hamlede 60 px çektiği için hatayı
yakalamıyordu.

**Onarım:** `ResizeState`'e başlangıç süresi + birikmiş ham piksel eklenir;
yuvarlama her adımda değil **toplamda** yapılır. Aynı test kalıcı olarak
eklenir (yavaş çekme).

### H2 — Aylık taşıma: saat korunur, rutin taşınmaz

* Tek günlük iş başka güne bırakılınca **yalnız günü** değişir; saati (varsa)
  aynen kalır. `moveTask` bunu yapamıyor (saati zorunlu yazıyor, saatsiz işi
  00:00'a çakardı) → depoya `moveTaskToDay(task, day)` eklenir.
* **Rutinler aylıkta sürüklenmez.** Haftalıkta haftalık rutini sürüklemek
  "tüm salıları perşembe yap" demek ve bunu gösteren ekran orası. Ayın 3'ünden
  12'sine çekilen bir rutinin ne yapacağı aylık ızgarada görünmüyor —
  sessiz, geniş bir değişiklik olurdu. Rutinde "Bugün iptal" zaten var.
* Geri al bildirimi her taşımada (`offerUndo`).

### H3 — Aylıkta uzun basma iki işe bölünür

`_TaskBox`'ta uzun basma bugün hızlı menüyü açıyor; sürükleme de uzun basma
ister (dokunmatikte düz sürükleme ay kaydırmasıyla çakışır).

* **Fare:** düz sürükle (anında). Hızlı menü sağ tıkla.
* **Dokunmatik:** uzun bas + sürükle = taşı. Uzun bas + **kıpırdamadan bırak**
  = hızlı menü (bugünkü davranış korunur).

### H4 — Havuza doğrudan yazılır (eski kararı tersine çevirir)

* Havuz panelinin başına tek satırlık giriş: yaz, Enter → havuza düşer.
  Beyin boşaltma hızında olmalı; düzenleyici açılmaz.
* Hızlı eklemede "Gün seçme → Havuza" seçeneği.
* Havuz ekranına "Yeni" düğmesi gelir.
* Model değişmiyor: iş `inPool = true`, `date = bugün` (K1 gereği dolu),
  `startHour = null`. Göç yok, senkron yok — alanlar zaten var.
* Boş hâl metni değişir: *"Bu hafta yapman gerekenleri yaz, sonra günlere
  sürükle."*

### H5 — Güne bırakmak ≠ saate bırakmak

Bugün havuzdan gelen iş yalnız saat ızgarasına bırakılabiliyor, yani her iş
bir saate çakılmak zorunda. Esnekliğin tam tersi.

| Nereye bırakıldı | Sonuç |
|---|---|
| Saat ızgarası | Gün + saat (bugünkü davranış) |
| Gün başlığı ya da saatsiz şerit | **Yalnız gün**, saat yok — saatsiz şeritte görünür |

Aynı hedefler haftalıkta saatsiz işlerin günler arası taşınmasına da açılır.

### H6 — Telefonda havuz çekmecesi

<900 px'de yan panel sığmıyor ve havuz ayrı bir sekmede — sürükleme imkânsız.
Haftalık görünümün altına daraltılabilir yatay bir şerit: havuz kartları
yan yana, uzun bas + gün başlığına sürükle. Kapalıyken yalnız "Havuz · 4"
yazan ince bir çubuk.

---

## 4. Dilimler

Her dilim sonunda: `flutter analyze` temiz, testler yeşil, commit.

### D1 — Süre tutamağı onarımı (H1) · küçük
* `ResizeState`: `startDuration` + `accumulatedDy`.
* `_onResizeUpdate` toplamı yuvarlar.
* Test: yavaş çekme (20 × 3 px → +1 sa), küçültme, süresiz işten başlama.

### D2 — Aylık sürükle-bırak (H2, H3)
* `AppStore.moveTaskToDay` + birim testi (saatli / saatsiz / rutin reddi).
* `_TaskBox`: fare `Draggable`, dokunmatik `LongPressDraggable`; rutinde kapalı.
* `_Cell`: `DragTarget<Task>` + bırakma vurgusu (`c.dropTarget`).
* Hızlı menü: sağ tık + "kıpırdamadan bırak".
* Widget testi: işi 3'ünden 5'ine taşı, saat korunuyor, geri al çalışıyor.

### D3 — Havuza doğrudan ekleme (H4)
* `AppStore.addToPool(title, {category, energy})`.
* Panel başında giriş satırı; hızlı eklemede "Havuza"; havuz ekranında "Yeni".
* Panel boşken de şerit görünür kalır (artık havuz bir başlangıç yeri).
* Testler: Enter ile ekleme, havuzda görünme, takvimde görünmeme.

### D4 — Gün başlığı ve saatsiz şerit bırakma hedefi (H5)
* `DayHeaderRow` ve `UntimedRow` hücreleri `DragTarget<Task>`.
* Havuzdan → yalnız gün; saatsiz iş → başka güne taşı.
* Testler: başlığa bırakınca `startHour == null`, `inPool == false`.

### D5 — Telefonda havuz çekmecesi (H6)
* `PoolDrawer` — alt şerit, kartlar `LongPressDraggable`.
* Hedefler D4'ünkiler (3 günlük görünümde de çalışır).

### D6 — (isteğe bağlı) Aylıkta havuz paneli
* Aynı `PoolPanel` aylık ekranın sağında; D2'deki hücre hedefi havuzdan
  geleni de kabul eder. "Ayın 30 gününü görerek dağıtmak" için.

**Sıra önerisi:** D1 → D2 → D3 → D4 → D5 → D6. D1 bağımsız ve hemen
indirilebilir; D3+D4 birlikte havuzu gerçekten kullanılır kılan çekirdek.

---

## 5. Açık Sorular

1. **Havuz sırası:** bugün "en uzun bekleyen üstte". Sorumluluk listesi için
   elle sıralama (sürükleyerek) ister misin, yoksa şimdilik yeterli mi?
2. **"Bu hafta" / "Sonra" ayrımı:** havuzu iki bölüme ayırmak (bu hafta
   dağıtılacaklar vs. bir gün) — bu plana mı, sonraya mı?
3. **D6** gerekli mi, yoksa aylık yalnız kendi içinde taşıma yeterli mi?

## 6. Kapsam Dışı

* Havuzdan otomatik günlere dağıtma önerisi.
* Havuz işine son tarih alanı (model değişikliği + göç ister).
