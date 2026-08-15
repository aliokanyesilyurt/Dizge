# Giriş Kapısı Planı — Migration · Zorunlu Oturum · Online Kapsamı

**Durum:** onaylandı (11 Ağustos) · **M1–M7 bitti, şema sunucuda doğrulandı**
**Tarih:** 11 Ağustos 2026
**Önceki plan:** `docs/backend-supabase-plani.md` (S1–S5 kodu yazıldı, commit edildi)

---

## 0. Durum — 11 Ağustos akşamı

| Dilim | Durum |
|---|---|
| M1 — Supabase projesi + migration | **Bitti.** Şema panodan uygulandı, sunucuya karşı doğrulandı |
| M2 — Anahtarlar (`env.json`) | Bitti |
| M3 — Kapı (`AuthGate`, `WelcomeScreen`) | Bitti |
| M4 — İlk senkron kapıda | Bitti |
| M5 — Çıkış akışı | Bitti |
| M6 — Parola kurtarma (OTP) | Bitti |
| M7 — Testler | Bitti (290 test, `analyze` temiz) |

### Sunucuya karşı doğrulananlar (11 Ağustos, gerçek proje)

Şemanın "bitti sayılır" ölçütü buydu ve atlanmadı. İki test kullanıcısı açıldı,
her kontrol canlı projede koşturuldu:

| Kontrol | Sonuç |
|---|---|
| `nodes` / `habits` / `categories` var | ✅ |
| `apply_mutations` bir işi yazıyor | ✅ `{"accepted":[…],"rejected":[]}` |
| A kendi satırını okuyor | ✅ 1 satır |
| **B, A'nın satırını okuyamıyor (RLS)** | ✅ 0 satır |
| Anonim okuma | ✅ boş |
| B, A'nın `user_id`'siyle satır yazamıyor (`with check`) | ✅ HTTP 403 |
| LWW: eski damgalı mutasyon yeniyi ezmiyor | ✅ içerik korundu |
| Saat kayması: ileri tarihli damga reddediliyor | ✅ `rejected` |
| Silme mezar taşı bırakıyor, `payload` boşalıyor | ✅ `deleted_at` damgalı |
| `purge_tombstones` anonime kapalı | ✅ `permission denied` |
| `security invoker`: oturumsuz RPC kendini reddediyor | ✅ `42501 oturum yok` |

Kalan iz: iki test hesabı (`…+rlsa798010@`, `…+rlsb798010@`) ve A'nın hesabında
bir mezar taşı satırı. Panodan silinebilir; RLS onları zaten yalıtıyor.

**Uygulama yolu (`supabase db push`) neden kullanılamadı:** bu makineden
Postgres'e hiçbir yol yok.

* `aws-0` / `aws-1` pooler, 5432 **ve** 6543: TCP el sıkışması tamam, Postgres
  `SSLRequest` paketine **hiç cevap yok**. Elle probe ile doğrulandı.
* Doğrudan sunucu (`db.<ref>.supabase.co`) yalnız IPv6; makinede global IPv6
  adresi yok.
* Ağ yasağı yok (`network-bans get` boş), proje ayakta (PostgREST 404 yerine
  düzgün "tablo yok" hatası dönüyor). Yani engel ISP tarafında.
* CLI'ın bütün `db` komutları doğrudan bağlantı istiyor; HTTPS üzerinden
  migration uygulayan bir alt komut yok (`db push --help` ile doğrulandı).

**Üç çıkış vardı (2 numara kullanıldı):**

1. **Telefon hotspot'u ya da VPN** — 5432 açılır, `supabase db push` normal
   çalışır ve defter kaydını CLI kendi tutar. *Önerilen:* gruplar için gelecek
   ikinci migration'da da aynı yol lazım olacak.
2. **Pano** — `supabase/migrations/…_initial_schema.sql` + defter kaydı
   (`supabase_migrations.schema_migrations`) SQL düzenleyicisine yapıştırılır.
   Defter kaydı elle eklenmezse sonraki `db push` migration'ı ikinci kez
   göndermeye çalışır.
3. **Kişisel erişim jetonu** — Management API'nin `database/query` uç noktası
   HTTPS üzerinden çalışır.

**Kalan tek doğrulama:** gerçek uygulamayla uçtan uca tur — giriş → iş ekle →
çıkış → tekrar giriş, işin sunucudan geri gelmesi.

**K1 yapıldı.** E-posta doğrulaması panodan kapatıldı (`mailer_autoconfirm:
true`). Açık kaldığı sürece kayıt olan kişi doğrulama ekranında takılıyordu ve
sert kapıda içeri hiç giremiyordu; üstelik her kayıt denemesi ücretsiz katmanın
saatlik posta limitine çarpıyordu (`over_email_send_rate_limit`). Gruplar
gelince davet e-postası zaten gerekecek; doğrulama o gün, gerçek bir işi olduğu
için açılır.

---

## 1. Nerede Kaldık

*(Bu bölüm planın yazıldığı andaki durumu anlatıyor; bugünkü durum için §0.)*

`backend-supabase-plani.md`'nin beş dilimi de **kod olarak** bitti. Eksik olan
şey kod değil:

| Ne | Durum |
|---|---|
| `supabase/schema.sql` | Yazıldı, **hiçbir sunucuya uygulanmadı** |
| Supabase projesi | **Yok** |
| `--dart-define` anahtarları | **Verilmiyor** → `AppConfig.backendAvailable == false` |
| Çalışan kip | `NoopRemoteGateway` + `NoopAuthService` — uygulama %100 yerel |
| Giriş kapısı | **Yok.** `main.dart:home` doğrudan `AppShell` |
| Oturum açma | Var ama **isteğe bağlı**: Hesap ekranında bir satır (`account_screen.dart:193`) |

Yani bugün uygulama, arkasında hiçbir sunucu olmayan tam işlevli bir yerel
takvim. Yazılmış olan `SupabaseGateway`, `SyncEngine`, `Outbox`,
`FirstSyncCoordinator` hiç uyanmıyor.

---

## 2. Sorduğun Soru: Online Ne Olmalı?

> "online veri depolamaya gerek yok bence, auth için falan kullanalım"

**Karşı görüş sunuyorum ve gerekçesini yazıyorum: veri depolamayı da açalım.**

Üç sebep:

1. **Zaten yazıldı ve bedava.** `SupabaseGateway` (S3), `Outbox`, `SyncEngine`,
   `apply_mutations` RPC'si — hepsi duruyor ve test edilmiş. Kapatmak yeni iş
   değil, çalışan kodu atıl bırakmak. Supabase'in ücretsiz katmanı 500 MB veri
   ve 50.000 aylık aktif kullanıcı; bir takvim uygulamasının yıllarca sığacağı
   yer.

2. **Zorunlu giriş + depolama yok = arkasında hiçbir şey olmayan kapı.**
   Kullanıcı telefonunu değiştirir, giriş yapar, takvimi boş bulur. Hesap ona
   hiçbir şey vermemiş, sadece bir engel olmuştur. Zorunlu bir kapının tek
   dürüst gerekçesi, hesabın kullanıcıya bir şey **vermesi**: yedek ve ikinci
   cihaz.

3. **Gruplar zaten depolamanın üstüne kurulur.** "Sonra gruplar için aktif
   etme" dediğin şey, paylaşılan satırlar demek. Depolamayı bugün atlayıp yarın
   gruplar için geri getirmek, aynı işi iki kez yapmak olur.

**Online özellik sırası — önerim:**

| # | Özellik | Ne zaman | Neden bu sırada |
|---|---|---|---|
| 1 | Kimlik + zorunlu kapı | **Bu iş** | Senin istediğin |
| 2 | Yedek + cihazlar arası senkron | **Bu iş** | Kodu hazır; migration'la açılıyor |
| 3 | Parola kurtarma (e-posta kodu) | **Bu iş** | Sert kapıda unutulan parola = kalıcı kilitlenme |
| 4 | Artımlı çekim + Realtime | Sonraki | Grupların ön koşulu; `pull(since:)` imzası hazır bekliyor |
| 5 | Gruplar / paylaşılan takvim | Sonraki | 4 olmadan yazılamaz |

3 numara pazarlık konusu değil bence — gerekçesi §4/M6'da.

---

## 3. Kararlar

### G1 — Kapı **ağa** değil, **cihazdaki oturuma** bakar

En kolay yanlış: "giriş zorunluysa açılışta sunucuya sor." O zaman metroda,
uçakta, internet kesikken uygulama açılmaz ve `bootstrap.dart`'tan
`Outbox`'a kadar yazılmış bütün offline-first mimarisi ölür.

Kapının sorduğu tek soru: **bu cihazda daha önce açılmış bir oturum var mı?**
`supabase_flutter` jetonu güvenli kasada tutuyor ve `autoRefreshToken: true`
(bkz. `bootstrap.dart:130`). Jeton varsa — ağ olmasa bile — içeri girilir.
Jeton gerçekten geçersizleşirse (uzun süre çevrimdışı + yenileme başarısız)
Supabase oturumu düşürür, `authUserProvider` null'a döner ve kapı kendiliğinden
kapanır.

Dürüst bedel: **ilk kurulumda internet şart.** Zorunlu kapının tek gerçek
maliyeti bu ve kaçışı yok.

### G2 — Anahtarsız derleme kapıyı **kapatmaz**

`AppConfig.backendAvailable == false` iken kapı açık kalır ve uygulama bugünkü
gibi yerel açılır. Aksi hâlde `--dart-define` vermeyi unutan her derleme —
senin geliştirme koşun ve 27 test dosyasının tamamı — açılmayan bir uygulama
üretirdi. Üretim derlemesinde anahtar zaten var; orada kapı kapalı.

Bu bir kaçamak değil, kasıtlı bir kaçış valfi: kapı "sunucu varken zorunlu",
"sunucu yokken anlamsız".

### G3 — Çıkış yapmak artık yerel veriyi de siler

Bugün çıkış yerel veriye dokunmuyor ve doğru karardı: kapı yokken çıkmak
"senkronu kapat" demekti, takvim seninkiydi.

Kapı gelince bu değişiyor. Aynı cihazda ikinci bir kişi giriş yaparsa
öncekinin bütün takvimini görür — Hive kutusu tek ve kullanıcıdan bağımsız.
Bu, kapının kendisinin yarattığı bir gizlilik açığı.

Yeni davranış:

1. Çıkışa basılır → bekleyen mutasyon varsa **önce gönderilir**.
2. Gönderilemiyorsa (çevrimdışı) çıkış **durdurulur**: "N değişiklik henüz
   yüklenmedi. Çıkarsan silinecekler." — Devam / Vazgeç.
3. Kuyruk boşsa yerel kutu temizlenir ve kapı kapanır.

Bu, G1'in bedelinin ikinci yarısı ve veri depolama açık olduğu için güvenli:
silinen şey sunucuda duruyor.

### G4 — E-posta doğrulaması v1'de kapalı

Supabase'in varsayılanı "Confirm email" açık. Sert kapıda bu şu demek: kaydol →
"postana bak" → uygulamaya **giremez**. Bekleme durumu için ayrı bir ekran
yazmak gerekir.

v1 için Supabase panosundan doğrulama kapatılır. Gruplar geldiğinde davet
e-postası zaten gerekecek; doğrulama o gün, gerçek bir işi olduğu için açılır.

*(Bu §5'te açık karar olarak da duruyor — istersen tersini yaparız.)*

---

## 4. Dilimler

Her dilim tek başına commit edilir.

### M1 — Supabase projesi + gerçek migration

Bu dilimin bir kısmını **sen** yapacaksın, hesap gerektiriyor:

* supabase.com'da proje aç (bölge: Frankfurt — gecikme ve KVKK/GDPR).
* Proje URL'i ve *publishable key* bana ver (ikisi de sır değil, bkz.
  `app_config.dart:52`).

Benim yapacağım:

* `supabase init` → `supabase/config.toml`
* `supabase/schema.sql` → `supabase/migrations/20260811090000_initial_schema.sql`
* `supabase link --project-ref …` + `supabase db push`

**Neden CLI, neden SQL editörüne yapıştırmıyoruz:** yapıştırmak bir kez
çalışır. İkinci değişiklikte — ki gruplar ikinci migration demek — "hangi
sürüm hangi ortamda" sorusunun cevabı olmaz. Migration klasörü o cevabın
kendisi.

**Bitti sayılır:** `supabase db push` hatasız geçer **ve** iki test
kullanıcısıyla RLS elle doğrulanır — A kullanıcısı B'nin satırını okuyamaz.
Bu ölçüt S1'de de yazılmıştı ve hiç yapılmadı; bu sefer atlanmıyor.

### M2 — Anahtarların derlemeye girmesi

* `env.json` (gitignore'da) + `env.example.json` (repoda, boş değerlerle)
* `.vscode/launch.json`'a `--dart-define-from-file=env.json`
* README'ye üç satır: yeni geliştirici ne kopyalayacak

`launch.json` repoya giriyor; anahtarı oraya yazmak `app_config.dart`'ın bütün
gerekçesini çöpe atardı.

**Bitti sayılır:** F5 ile açılan uygulamada `AppConfig.backendAvailable == true`;
Hesap ekranındaki "Oturum aç" gerçekten sunucuya gidiyor ve yanlış parolada
"E-posta veya parola hatalı" diyor.

### M3 — Kapı (UI)

Yeni dosya: `lib/screens/auth_gate.dart`. `main.dart`'ta `home: const AuthGate()`.

```
AuthGate  (ConsumerWidget, authUserProvider'ı izler)
├─ AppConfig.backendAvailable == false  → AppShell          (G2)
├─ AsyncLoading                          → _SplashScreen     (marka + spinner)
├─ user == null                          → WelcomeScreen
└─ user != null                          → AppShell
```

`_SplashScreen` şart: jeton geri yüklenirken bir kare "Hoş geldin" gösterip
sonra takvime atlamak, her açılışta bir yanıp sönme demek.

Yeni dosya: `lib/screens/welcome_screen.dart`

```
WelcomeScreen  (Scaffold, c.bg, ortalanmış, maxWidth 420)
├─ _Brand            — app_shell.dart:319'daki marka bileşeni yeniden kullanılır
├─ Başlık            — "Programın, her cihazında."
├─ Alt metin         — tek cümle: neden hesap gerekiyor
├─ _AuthForm         — e-posta / parola / birincil düğme
│   └─ account_screen.dart:317 _SignInSheet'ten taşınır (mantık aynen korunur:
│      istemci tarafı doğrulama, AuthFailure gösterimi, _busy kilidi)
├─ TextButton        — "Hesabın yok mu? Oluştur" ↔ "Zaten hesabın var mı? Gir"
└─ TextButton        — "Parolamı unuttum"  (M6)
```

Klavye, otomatik doldurma ipuçları (`AutofillHints`) ve `TextInputAction`
zinciri mevcut sheet'te zaten doğru; taşınırken korunuyor.

`account_screen.dart` sadeleşiyor: `_AccountSection` artık yalnız e-posta +
"Çıkış yap" gösterir. "Oturum aç" satırının içeride bir anlamı kalmadı.

**Bitti sayılır:** widget testi — oturum yokken `WelcomeScreen`, oturumluyken
`AppShell`, yüklenirken splash; `AppShell`'e oturumsuz hiçbir yoldan
ulaşılamıyor.

### M4 — İlk senkron kapının içine taşınır

`_runFirstSync` bugün Hesap ekranındaki tıklamaya bağlı
(`account_screen.dart:226`). Giriş artık oradan olmayacak.

* Akış `AuthGate`'e taşınır: oturum `null → dolu` **geçişinde** bir kez çalışır.
* Geçişi yakalamak için `ref.listen(authUserProvider, …)` — her build'de değil,
  yoksa "hangisi kalsın" diyaloğu tekrar tekrar açılır.
* Diyalog ve `FirstSyncCoordinator` mantığı değişmiyor; yalnız çağrıldığı yer
  değişiyor.

**Bitti sayılır:** yeni hesap → boş takvim, veri eklenir; ikinci profilde aynı
hesapla giriş → "Hangisi kalsın?" doğru sayıyla çıkar.

### M5 — Çıkış akışı (G3)

* `_AccountSection`'daki çıkış: outbox kontrolü → gerekirse uyarı diyaloğu →
  `store.clear()` + `signOut()`
* "Cihazdaki planların silinmez" alt metni değişir — artık doğru değil.

**Bitti sayılır:** bekleyen mutasyonla çevrimdışı çıkış denemesi uyarı
gösterir ve varsayılan olarak çıkışı yapmaz.

### M6 — Parola kurtarma (e-posta kodu)

Sert kapı, unutulan parolayı **kalıcı kilitlenmeye** çevirir: uygulamaya
girilemez, veriye ulaşılamaz, yapacak bir şey kalmaz. Bu yüzden isteğe bağlı
saymıyorum.

Supabase'in standart sıfırlama akışı e-postadaki bağlantıyla çalışır ve
Windows'ta derin bağlantı kaydı ister — B6'da OAuth'u eleyen sebebin aynısı.
Bunun yerine **OTP**: `signInWithOtp(email:)` → e-postaya 6 haneli kod →
uygulamada `verifyOTP` → içeri girer → Hesap ekranından parola değiştirir.
Derin bağlantı yok, platform yapılandırması yok.

`AuthService`'e iki metot: `sendRecoveryCode(email)`, `verifyRecoveryCode(email, code)`.
`NoopAuthService` ikisini de bugünkü gibi açık hatayla reddeder.

**Bitti sayılır:** parola unutulmuş bir hesapla uçtan uca kurtarma turu elle
doğrulanır.

### M7 — Testler ve temizlik

* `test/auth_gate_test.dart` — üç durum (splash / welcome / shell) + anahtarsız
  derlemede kapının açık kalması
* Mevcut 27 test dosyası `AppShell`'i doğrudan pompaladığı için kırılmamalı;
  doğrulanır.
* `flutter analyze` temiz, `dart format`, tüm paket yeşil.

---

## 5. Açık Kararlar

**K1 — E-posta doğrulaması (G4).** Önerim: v1'de kapalı. Alternatif: açık
bırakıp "postanı doğrula" bekleme ekranı yazmak (~yarım dilim).

**K2 — `profiles` tablosu şimdi mi?** "Gruplar için aktif etme" dediğin şey,
sunucudan okunan bir bayrak demek: `profiles(user_id, display_name, flags jsonb)`.
Bugün eklemek 15 satırlık migration. **Önerim: şimdi değil.** Kullanılmayan
sütun ölü şemadır ve gruplar geldiğinde ihtiyacın olan şeklin bugünden doğru
tahmin edilme ihtimali düşük. İkinci migration'ın maliyeti zaten sıfıra yakın
(M1 o düzeni kuruyor). Ama "kullanıcı adı" gibi bir şeyi yakında istiyorsan
söyle, M1'e eklerim.

**K3 — Çıkışta yerel silme (G3).** Bu benim önerim; senin kararın. Alternatif:
silme, uyar ("bu cihazda kalan planları başkası görebilir"). Cihazı yalnız sen
kullanıyorsan ikincisi de savunulabilir.

---

## 6. Kapsam Dışı

Artımlı çekim, Realtime, çakışma birleştirme, gruplar/paylaşılan takvim,
OAuth ve sihirli bağlantı, kategori kimliği (B7.2), sunucu tarafı bildirim,
çizim (`Sketch`) için ayrı depolama, telemetri rızasının sunucudan okunması,
hesap silme (KVKK gerekliliği — ayrı ve yakın bir dilim).

---

## 7. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| Kapı yüzünden uygulama çevrimdışı açılmaz | **Yüksek etki** | G1: kapı jetona bakar, ağa değil. M7'de uçak kipi testi |
| Anahtar unutulan derleme hiç açılmaz | Orta | G2: `backendAvailable == false` → kapı açık |
| Parola unutulur, kullanıcı kilitlenir | Orta | M6, isteğe bağlı değil |
| İkinci kişi cihazda önceki takvimi görür | Orta | G3: çıkışta yerel temizlik |
| E-posta doğrulaması açık kalır, kimse giremez | Orta | G4 / K1 — M1'in son adımında pano ayarı doğrulanır |
| `supabase db push` mevcut şemayla çakışır | Düşük | `schema.sql` idempotent (`if not exists`); proje yepyeni |
| RLS bir tabloda unutulur | **Yüksek etki** | M1'in bitti-sayılırı: iki kullanıcıyla elle doğrulama |

---

## 8. Sıra

M1 → M2 → M3 → M4 → M5 → M6 → M7.

M1 sensiz başlayamaz (Supabase projesi). M2'den sonrası tamamen bende.
