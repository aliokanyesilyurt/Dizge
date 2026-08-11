# Açık Tema · Boş Hafta · Giriş Deneyimi · Telemetri Düğmesi

**Durum:** onay bekliyor
**Tarih:** 11 Ağustos 2026
**Önceki plan:** `docs/giris-kapisi-plani.md` (M1–M7 bitti, şema sunucuda)

---

## 1. Dört İş

| # | İş | Neden şimdi |
|---|---|---|
| T1 | Açık tema neon ailesine geçiyor | İki tema farklı **marka** gibi duruyor |
| T2 | "Bu hafta boş" kartı ekranın ortasından kalkıyor | Plan yapılmayan hafta bir hata değil |
| T3 | Giriş akışı + funnel ölçümü | Yeni kullanıcının ilk beş dakikası ölçülmüyor |
| T4 | "Anonim kullanım istatistikleri" düğmesi ölü | Kök sebep bulundu (§5) |

Sıra: **T1 → T2 → T4 → T3.** T4, T3'ün önüne alındı çünkü funnel'ı ölçmenin
yolu çalışan bir telemetriden geçiyor.

---

## 2. T1 — Açık tema neon ailesine geçiyor

### Sorun

Koyu tema `N1–N4` dilimlerinde yeniden kuruldu: mürekkep siyahı zemin, **neon
camgöbeği** (`#22D3EE`) vurgu, **magenta** (`#F0ABFC`) ikincil renk, magenta
"şu an" çizgisi. Açık tema o işe hiç girmedi ve **eski indigo/gül** paletinde
kaldı:

| Rol | Koyu (bugün) | Açık (bugün) | İlişki |
|---|---|---|---|
| `accent` | `#22D3EE` camgöbeği | `#4F46E5` indigo | **yok** |
| `secondary` | `#F0ABFC` magenta | `#E11D48` gül | **yok** |
| `nowLine` | `#FF2BD6` magenta | `#F43F5E` gül | **yok** |

Temayı değiştirmek bir tercih olmalı, başka bir uygulamaya geçmek değil.

### Karar T1a — Ton korunur, parlaklık değişir

Neon renkler beyaz kâğıtta okunmaz: `#22D3EE` beyaz üstünde **1.81:1** — WCAG
AA metin için 4.5:1 istiyor. O yüzden koyu temanın rengini kopyalamıyoruz;
**ton açısını (hue) koruyup** parlaklığı düşürüyoruz. Kimlik tonda taşınır,
okunabilirlik parlaklıkta.

Hesaplanmış öneri (kontrast beyaz `#FFFFFF` üstünde):

| Rol | Bugün | Öneri | Kontrast | Ton açısı (koyu → açık) |
|---|---|---|---|---|
| `accent` | `#4F46E5` | **`#0E7490`** | 5.36:1 ✅ | 188° → 193° |
| `secondary` | `#E11D48` | **`#A21CAF`** | 6.32:1 ✅ | 291° → 295° |
| `nowLine` | `#F43F5E` | **`#D6009E`** | 4.82:1 ✅ | 312° → 316° |

Üç rolde de ton farkı 5° altında — göz bunları "aynı renk ailesinin gündüz
hâli" olarak okur.

Elenenler ve niçin: `#22D3EE` (1.81), `#06B6D4` (2.43), `#0891B2` (3.68) — üçü
de metin eşiğinin altında. `#155E75` (7.27) geçiyor ama o kadar koyu ki
camgöbeği olmaktan çıkıp lacivert gibi duruyor; kimliği taşımıyor.

### Karar T1b — `warning` ve `danger` markaya bağlanmaz

`#B45309` (uyarı) ve `#DC2626` (tehlike) **değişmiyor**. Bunlar marka rengi
değil, evrensel işaret: sarı/kırmızı olmayan bir "sil" düğmesi tehlikeyi
anlatmaz. Tema değişince anlamları değişmemeli.

### Karar T1c — Açıkta parıltı yok, bu doğruydu

`glowAccent` açık temada şeffaf kalıyor. Beyaz kâğıt üstünde neon hale kir gibi
durur; derinliği gölge zaten taşıyor (koddaki gerekçe hâlâ geçerli). N4'ün "üç
yerde parıltı" kuralı koyu temaya özel kalır.

### Türeyen değerler

`accent` değişince ona bağlı beş token da değişmeli, yoksa indigo artıkları
kalır:

| Token | Bugün | Öneri |
|---|---|---|
| `accentSoft` | `#EEF0FE` indigo tint | `#E6F6FA` camgöbeği tint |
| `navActiveFill` | `#EEF0FE` | `#E6F6FA` |
| `navActiveInk` | `#4338CA` indigo | `#0E7490` |
| `gridTodayWash` | `0x0A4F46E5` | `0x0F0E7490` |
| `dropTarget` | `0x334F46E5` | `0x330E7490` |

**Bitti sayılır:** `theme_test.dart`'a "iki paletin `accent`/`secondary`/
`nowLine` ton açıları 15° içinde" testi eklenir ve geçer. Bu test, ileride
temalardan biri tek başına değiştirilirse haber verir — bugünkü ayrışmanın
sessizce tekrar oluşmasını engeller.

---

## 3. T2 — "Bu hafta boş" kartı

### Senin sözün

> "ben o hafta program yapmayacaksam girmedim tam ekran ortasına simetrik
> olmayan bi uyarı mesajı çıkmasına gerek yok"

Katılıyorum ve bir sebep daha ekleyeceğim.

### Kartın bugünkü hâli

`week_view_screen.dart:701` — ızgaranın üstünde bir `Stack` katmanı, ortada
yüzen, 300 piksel genişliğinde bir `ShadCard`. İçinde başlık, açıklama ve
"Yeni iş" düğmesi.

Var olma gerekçesi koda yazılmış: *"kullanıcı veriyi mi kaybettiğini yoksa
haftanın gerçekten boş mu olduğunu ayırt edemiyordu."* Bu gerekçe **ilk
kullanımda** doğru. Ama uygulamayı aylardır kullanan biri için boş bir hafta
bir belirsizlik değil, sadece bir bilgi: o hafta plan yapmadım.

### İkinci sebep: kart bir hatayı da beraberinde getirdi

`week_view_screen.dart:187`'de duran `_poolDragging` bayrağı **yalnızca bu kart
yüzünden** var. Kart ızgaranın üstünde bir katman olduğu ve `RenderStack`
vuruşu ön çocukta durduğu için, tam kartın üstüne bırakılan iş alttaki
`DragTarget`'a hiç ulaşmıyordu — boş bir haftaya havuzdan ilk işi koymak
**ekranın tam ortasında çalışmayan tek nokta** demekti. Bugün bir bayrakla
kartı sürükleme sırasında öne çekip yamanıyor.

Kartı kaldırmak bu yamayı da kaldırır: bir widget siliniyor, bir hata sınıfı
kapanıyor.

### Karar T2 — Yüzen kart gider, sakin bir satır gelir

Ortada yüzen kart yerine, **haftanın başlık çubuğunda** hizalı ve sessiz bir
satır:

```
┌─────────────────────────────────────────────────────┐
│  ‹  11–17 Ağustos  ›        Bu hafta boş · Yeni iş  │   ← başlık çubuğu
├─────────────────────────────────────────────────────┤
│  Pzt   Sal   Çar   Per   Cum   Cmt   Paz            │
│  (ızgara — üstünde hiçbir katman yok)               │
```

* Izgaranın üstünde katman kalmaz → `_poolDragging` yaması silinir.
* "Bu hafta boş" bir uyarı değil, bir durum bildirimi: `c.inkFaint`, 12.5 px,
  ikon yok, kutu yok.
* "Yeni iş" bir `TextButton` olarak kalır — ilk kullanıcı için giriş noktası
  kayboluyor değil, sadece bağırmıyor.
* Erişilebilirlik: satır `Semantics(liveRegion: true)` ile sarılır ki ekran
  okuyucu haftanın boş olduğunu söylesin. Bugün kart bunu yapıyordu.

**Bitti sayılır:** `accessibility_test.dart`'taki "boş hafta iş yokken kart
görünür, ilk işten sonra kaybolur" testi yeni şekle göre güncellenir; havuzdan
ızgaranın **tam ortasına** bırakma testi eklenir (bugün yamayla çalışan yol,
yarın yamasız çalışmalı).

---

## 4. T3 — Giriş akışı ve funnel

### Bugünkü akış

```
AuthGate → WelcomeScreen (giriş | kayıt | kurtarma)
             │ kayıt başarılı
             ▼
          AppShell — bomboş takvim, hiçbir yönlendirme yok
```

İki kopukluk var:

1. **Kayıt ile giriş aynı forma sıkışmış.** Yeni kullanıcı "Giriş yap" yazan
   bir düğme görüyor; hesabı yok ve önce alttaki bağlantıyı bulması gerekiyor.
   Funnel'ın ilk adımı, kullanıcıdan bir keşif istiyor.
2. **Kayıttan sonra boşluk.** Kapıdan geçen kişi bomboş bir haftaya düşüyor.
   T2 ile ortadaki kart da kalkacağı için burası büsbütün sessizleşir.

### Karar T3a — İlk kare "kayıt", "giriş" değil

Uygulamayı ilk kez açan (cihazda hiç oturum açılmamış) kişi doğrudan **kayıt**
kipinde karşılanır; "Zaten hesabım var" bağlantısı altta durur. Daha önce
oturum açılmış bir cihazda ise varsayılan **giriş** olur.

Ayrımı taşıyacak şey: `LocalStore`'a yazılan tek bir bayrak
(`has_signed_in_before`). Oturum jetonu bunun için kullanılamaz — çıkışta
silinir ve her çıkış kullanıcıyı yeniden "yeni kullanıcı" yapardı.

### Karar T3b — Kayıttan sonra tek bir soru

Onboarding sihirbazı **yazmıyorum**: üç ekranlık bir tanıtım turu, kullanıcının
görmek istediği şeyin (kendi takvimi) önüne konan bir engeldir.

Onun yerine ilk açılışta hafta ızgarasının üstünde tek satırlık bir davet —
T2'de kurulan aynı sakin satırın ilk-kullanım metni:

> Haftan boş. Bir saate dokun ya da **ilk işini ekle**.

Bir kez görünür (ilk iş eklenince bir daha çıkmaz), kutu değil, ortada değil.

### Karar T3c — Funnel gerçekten ölçülür

"İlerlemeyi görelim" için akışa dört olay konur (`Ev` sabitleri):

| Olay | Nerede | Cevapladığı soru |
|---|---|---|
| `welcome_seen` | `WelcomeScreen` ilk kare | Kaç kişi kapıya geldi |
| `signup_submitted` | Kayıt gönderildi | Kaçı denedi |
| `signup_succeeded` | Oturum açıldı | Kaçı içeri girdi |
| `first_task_created` | İlk iş eklendi | Kaçı gerçekten kullanmaya başladı |

Aradaki her düşüş bir tasarım sorusu. Bu olaylar **kişisel veri taşımaz**: iş
başlığı, e-posta, not içeriği yok — bugünkü `Telemetry` sözleşmesi zaten bunu
yasaklıyor (`bootstrap._installErrorHandlers`'daki not aynı gerekçeyle yazılmış).

Ve hepsi rızaya bağlı: `ConsentGate` kapalıyken tek olay gitmez. **Bu yüzden
T4, T3'ten önce.**

**Bitti sayılır:** yeni kullanıcı yolunda dört olayın sırayla üretildiği, rıza
kapalıyken hiçbirinin üretilmediği testle gösterilir.

---

## 5. T4 — "Anonim kullanım istatistikleri" düğmesi neden ölü

### Kök sebep

`account_screen.dart:493`:

```dart
final gate = telemetry is ConsentGate ? telemetry : null;
final available = gate != null;          // → Switch'in onChanged'i null
```

`bootstrap._initTelemetry()`:

```dart
if (!AppConfig.telemetryAvailable) {
  return kDebugMode ? const DebugTelemetry() : const NoopTelemetry();
}                                        // ← ConsentGate DEĞİL
return ConsentGate(inner, enabled: false);
```

`POSTHOG_API_KEY` verilmediği için (env.json'da yok) telemetri **hiç
`ConsentGate`'e sarılmıyor**; ekran da `ConsentGate` göremeyince anahtarı pasif
bırakıyor. Düğme bozuk değil — arkasında anahtar çevrilecek bir şey yok.

### İkinci kusur: tercih hiçbir yere yazılmıyor

`ConsentGate` kurulduğu durumda bile `enabled` yalnız bellekte. Uygulama
kapanıp açılınca rıza **sessizce kapanıyor**. `bootstrap`'ta bunun notu zaten
duruyor: *"Rıza tercihi backend/ayar deposuna bağlandığında başlangıç değeri
oradan okunacak."* O gün geldi.

### Karar T4 — Rıza her zaman gerçek bir tercih

1. Telemetri **her zaman** `ConsentGate`'e sarılır — içerideki gerçek PostHog
   olsun, `NoopTelemetry` olsun. Anahtar hep canlı olur.
2. Tercih `LocalStore`'a yazılır ve açılışta okunur. Rıza, hatırlanmayan bir
   şey olamaz: her açılışta sıfırlanan bir onay, onay değildir.
3. Anahtar sunucusu yapılandırılmamışken kart dürüst olur — altta tek satır:
   *"Bu derlemede analitik sunucusu yapılandırılmadı; tercihin yine de
   saklanıyor."* Çalışıyormuş gibi yapan bir anahtar, kapalı bir anahtardan
   daha kötüdür.

**Bitti sayılır:** anahtar açılır, uygulama yeniden kurulur (test içinde
`bootstrap` benzeri bir kurulum), rıza **açık** gelir. Kapalıyken hiçbir olayın
`_inner`'a ulaşmadığı da sınanır.

---

## 6. Açık Kararlar

**K1 — Analitik sunucusu ne olacak?**
Funnel'ı gerçekten *görmek* için bir yere yazılması lazım. Üç yol:

1. **PostHog** — kod zaten hazır (`PostHogTelemetry`), tek eksik anahtar.
   Ücretsiz katman aylık 1M olay. `env.json`'a bir satır. *Önerim bu.*
2. **Supabase tablosu** — yeni bir `events` tablosu + RLS. Veri sende kalır ama
   funnel panosunu da sen yazarsın; PostHog'un verdiği şey tam olarak o pano.
3. **Hiçbiri** — olaylar kodda durur, kimse görmez. T3c'nin anlamı kalmaz.

**K2 — Açık temada kenar mı, gölge mi?**
N3'te koyu tema derinliği gölgeden **kenara** taşımıştı. Açık tema hâlâ gölge
kullanıyor. Önerim: **gölge kalsın.** Beyaz üstünde ince kenar, kartları form
alanı gibi gösteriyor; gölge kâğıt hissini veriyor ve zaten çalışıyor. Ama
"iki tema aynı dili konuşsun" dersen bunu da hizalarız — o zaman T1'e bir
madde daha eklenir.

**K3 — "Yeni iş" düğmesi başlık çubuğunda mı kalsın?**
T2'de sakin satırın içinde duruyor. Alternatif: hiç olmasın, kullanıcı ızgaraya
dokunsun. Önerim: **kalsın** — ilk kullanıcının tek görünür giriş noktası o.

---

## 7. Kapsam Dışı

Onboarding sihirbazı/tanıtım turu, tema düzenleyici (kullanıcının kendi rengini
seçmesi), üçüncü bir tema, ekran görüntüsü tabanlı görsel regresyon testleri,
gruplar ve artımlı çekim (ayrı plan), bildirimler.

---

## 8. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| Açık temada indigo artığı bir yerde kalır | **Orta** | `theme_test`'e "açık palette indigo/gül hex'i geçmiyor" testi |
| Boş hafta kartını kaldırmak ilk kullanıcıyı boşlukta bırakır | Orta | T3b'deki tek satırlık davet aynı boşluğu dolduruyor |
| `_poolDragging` yaması silinince sürükleme bozulur | Düşük | Izgaranın tam ortasına bırakma testi (T2 bitti-sayılır) |
| Funnel olayları kişisel veri sızdırır | **Yüksek etki** | Olaylar yalnız sayısal; testte payload'ın anahtar kümesi sabitlenir |
| Rıza kapalıyken olay gider | **Yüksek etki** | `ConsentGate` testi (T4 bitti-sayılır) |
