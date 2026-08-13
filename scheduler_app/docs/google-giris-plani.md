# Google ile Giriş Planı — Tek Akış, Beş Platform

**Durum:** G8.1–G8.3 indi, sağlayıcı açıldı (13 Ağustos). **G8.4 düştü** —
sunucuda "Confirm email" açık çıktı, G8c karşılanıyor. Kalan: §7.3'ün pano
kontrolü ve §10'daki elle tur.
**Önceki:** `giris-kapisi-plani.md` (M1–M7 bitti), `backend-supabase-plani.md`
**Önkoşul:** Supabase panosunda Google sağlayıcısı + Google Cloud'da OAuth
istemcisi. İkisi de **kod dışı** ve sende (§7).

---

## 1. Bugün ne var

Hesap sistemi duruyor ve çalışıyor: e-posta + parola ile kayıt, giriş, çıkış,
parola kurtarma (e-posta kodu), parola değiştirme. Şema sunucuda, RLS iki
gerçek kullanıcıyla doğrulanmış (migration 01).

Eksik olan tek şey **ikinci bir giriş yolu**. Bu plan onu ekliyor; e-posta yolu
olduğu gibi kalıyor.

---

## 2. Karar G8a — Tarayıcı akışı (`signInWithOAuth`), `google_sign_in` değil

İki yol var:

| | `google_sign_in` (yerel) | `signInWithOAuth` (tarayıcı) |
|---|---|---|
| Windows | **desteklemiyor** | çalışıyor |
| Android/iOS | yerel seçici, en iyi his | tarayıcı açılır |
| Kurulum | platform başına client ID | tek redirect URL |

Birincil hedef Windows ve `google_sign_in` orada yok. İki paketi birden
kullanmak — mobilde yerel, masaüstünde tarayıcı — iki ayrı akış, iki ayrı hata
yüzeyi ve iki ayrı "neden bu cihazda giremiyorum" hikâyesi demek.

Karar: **tek akış, `signInWithOAuth`.** Bedeli dürüstçe: giriş sistem
tarayıcısında açılıyor ve kullanıcı uygulamaya geri dönüyor. Mobilde yerel
seçici kadar akıcı değil.

## 3. Karar G8b — Geri dönüş özel şemayla: `dizge://login-callback`

Tarayıcıda giriş bitince Supabase, jetonu bir adrese geri yollar. Masaüstü ve
mobilde bu adres bir **özel şema** olmalı.

`supabase_flutter` bu dönüşü `app_links` ile kendisi yakalıyor ve `app_links`
Windows'u destekliyor (WM_COPYDATA ile tekil örneğe iletim). Yani Dart tarafında
yazılacak bir dinleyici yok — yapılacak iş **platform kaydı**:

* Windows: registry'de şema kaydı. Kurulumda yapılır; geliştirmede bir `.reg`
  dosyası (§7.4, üreteceğim).
* Android: `AndroidManifest.xml`'e intent-filter.
* iOS/macOS: `Info.plist`'e `CFBundleURLTypes`.
* Web: dönüş normal bir URL, özel şema yok.

Şema `dizge` seçiliyor — marka adı. `io.supabase.*` gibi bir ön ek, uygulamanın
adını altyapı sağlayıcısına bağlardı.

## 4. Karar G8c — Aynı e-posta iki yoldan gelirse **aynı hesap**

Kullanıcı önce e-posta+parola ile kaydolup sonra Google ile girerse iki ayrı
hesap oluşmamalı: takvimi ikiye bölünürdü.

Supabase bunu e-posta üzerinden birleştiriyor, ama **koşullu**: yalnız e-posta
doğrulanmışsa. Doğrulanmamış bir hesabın üstüne Google ile girmek hesap
devralmaya açık bir kapı — Google e-postayı doğrulanmış sayar, bizimki
saymaz.

Karar: panoda **"Confirm email" açık** olacak (§7.2). Açık değilse bu plan
eksik iner. Bugün kapalıysa bu, e-posta yoluna da bir doğrulama adımı
eklemek demek — kapsamda ve §6'da dilim olarak duruyor.

**13 Ağustos:** sunucu `auth/v1/settings` ile soruldu, `mailer_autoconfirm`
`false` döndü — doğrulama açık. Koşul sağlandı, G8.4 yazılmayacak.

## 5. Karar G8d — Sağlayıcı kapalıyken düğme ne yapar

Kod indiği anda Supabase'de Google sağlayıcısı henüz açık olmayabilir. O aralık
için üç seçenek vardı: düğmeyi gizleyen bir bayrak, sessiz başarısızlık, ya da
sunucunun hatasını olduğu gibi göstermek.

Karar: **düğme her zaman görünür**, sağlayıcı kapalıysa hata metni bunu
söyler ("Google girişi bu sunucuda açık değil"). Bir yapılandırma bayrağı,
tek kişilik bir projede unutulacak ikinci bir anahtar olurdu; sessiz
başarısızlık ise en kötüsü.

## 6. Dilimler

| # | Ne | Tek başına değeri |
|---|---|---|
| G8.1 | `AuthService.signInWithGoogle()` + Supabase uygulaması + sahte | Görünmez, testlerle sabit |
| G8.2 | Karşılama ekranında "Google ile devam et" düğmesi + hata yolları | **Evet** — web'de bu kadarı çalışır |
| G8.3 | Platform kaydı: Windows `.reg`, Android manifest, iOS/macOS plist | **Evet** — masaüstü ve mobilde dönüş kapanır |
| ~~G8.4~~ | *(düştü)* E-posta doğrulama adımı — G8c zaten sağlanıyordu | — |

G8.4 yalnız §7.2'de "Confirm email" kapalı çıkarsa yapılacaktı; açık çıktı.

### Ne indi (13 Ağustos)

**G8.1** — `AuthService.signInWithGoogle()`. Sözleşme bir şeyi açıkça
söylüyor: dönen `Future` girişin değil **tarayıcının açıldığının** haberi.
`SupabaseAuthService` `_guard`'ı atlıyor, çünkü buradaki hata ağ hatası
değil — `signInWithOAuth` sunucuya hiç gitmez, adresi kendi kurar ve
tarayıcıyı açar; "sunucuya ulaşılamadı" yanlış teşhis olurdu. Sağlayıcı
kapalı ve izin reddedildi durumları için iki yeni çeviri. Sahte servis
(`FakeAuthService`) dönüşü ve dönüşteki hatayı ayrı ayrı taklit ediyor.

**G8.2** — Karşılama ekranında "ya da" ayracı ve "Google ile devam et".
Kurtarma adımlarında görünmüyor. Çevrimdışıyken pasif ve sebebi altında
yazıyor. Düğmeye basınca `google_sign_in_started` gidiyor; huninin bu
koluyla giriş sayısı arasındaki fark, tarayıcıya gidip dönmeyenleri
gösterecek.

Planın yazarken görülmeyen yeri buydu: **dönüş yolundaki hata çağrıya
değil oturum akışına düşüyor.** Ekran yalnız `await`'i dinleseydi
sağlayıcı kapalıyken kullanıcı tarayıcıya gidip boş dönecek ve hiçbir şey
olmamış gibi duran bir formla karşılaşacaktı — G8d'nin kapatmak istediği
deliğin ta kendisi. Ekran şimdi ikisini birden dinliyor
(`ref.listen(authUserProvider)`), test de bunu ayrıca sınıyor.

**G8.3** — Platform kaydı. Android'e intent-filter (`singleTop` zaten
vardı: onsuz dönüş uygulamanın ikinci kopyasını açardı), iOS ve macOS
plist'lerine `CFBundleURLTypes`. Windows iki parça istedi:

* `windows/runner/main.cpp` — `SendAppLinkToInstance`. Windows dönüşte
  uygulamayı **yeni bir süreç** olarak başlatıyor; bu olmadan kullanıcının
  önünde iki kopya kalırdı. Adres `WM_COPYDATA` ile çalışan örneğe
  geçiyor, yeni süreç pencere açmadan kapanıyor.
* `tools/dizge_scheme.ps1` — registry kaydı. **Planda `.reg` yazıyordu,
  betik indi:** kayıt exe'nin tam yolunu taşımak zorunda ve o yol her
  makinede, her derleme kipinde farklı. Repoya sabit bir yol yazmak,
  sessizce yanlış kopyaya bağlanan bir kayıt üretirdi. Betik HKCU'ya
  yazıyor (yönetici hakkı istemiyor) ve `-Unregister` ile geri alıyor.

İki bilinçli eksik:

* **Google'ın resmî "G" işareti paketlenmedi.** Düğme şimdilik yalnız
  metin. Elle çizilmiş bir yaklaşığı koymak, markayı yanlış göstermek
  olurdu; varlık Google'ın kılavuzundan alınıp `assets/brand/` içine
  konunca düğmeye eklenir.
* **Linux kaydı yok.** Plan beş platform sayıyor ve Linux onlarda değil;
  `.desktop` girdisi gerektiğinde ayrı bir iş.

## 7. Senin yapman gerekenler (kod dışı)

1. ~~**Google Cloud Console**~~ **(bitti)** → yeni proje → *APIs & Services* → *Credentials* →
   *OAuth client ID* → **Web application**. Authorized redirect URI olarak
   Supabase'in verdiği adresi gir:
   `https://bugiplynazovapqudceh.supabase.co/auth/v1/callback`
   Client ID ve Client Secret'ı al.
2. ~~**Supabase panosu** → *Authentication* → *Providers* → *Google*~~
   **(bitti** — sağlayıcı açık, istemci `131689805479-…`; *Confirm email*
   de açık**)**
3. **Supabase panosu** → *Authentication* → *URL Configuration* → *Redirect
   URLs* listesine `dizge://login-callback` ekle. **Kalan tek pano işi.**
   Dışarıdan doğrulanamıyor: `/authorize` izinsiz bir adresi de geçiriyor,
   liste ancak dönüşte (`/callback`) sınanıyor. Eksikse giriş tamamlanır ama
   tarayıcı uygulamaya değil *Site URL*'e döner ve jeton hiç gelmez.
4. **Windows geliştirme**: `tools\dizge_scheme.ps1` çalıştır — şemayı
   derlenmiş exe'ye bağlar (`.reg` yerine betik; gerekçe §6'da). Kurulum
   paketi bunu kendisi yapacak.

Ben bunları yapamam: pano erişimi ve gizli anahtar gerekiyor.

## 8. Bitti sayılır

Kodla sınananlar (`test/google_sign_in_test.dart`, 8 test) işaretli.

* [x] Düğme akışı başlatıyor, dönüşte kapı takvimi açıyor *(sahte serviste;
  gerçek tarayıcı turu §10'da)*.
* [ ] Aynı Google hesabıyla ikinci girişte **ilk senkron sorusu çıkmıyor**
  (AuthGate'in "az önce giriş yaptı" ayrımı OAuth dönüşünde de doğru
  çalışıyor) — elle.
* [ ] E-posta+parola ile kurulmuş hesap, aynı adresli Google girişinde **aynı
  kullanıcı** oluyor — takvim ikiye bölünmüyor. Elle; §7.2'ye bağlı.
* [x] Sağlayıcı kapalıyken düğme hata metnini gösteriyor, sessizce yutmuyor —
  hem çağrıdan hem akıştan gelen hata için.
* [x] Çevrimdışıyken düğme pasif (G2 ile aynı kural).
* [x] `flutter analyze` temiz, 392 test yeşil, `flutter build windows`
  geçiyor.

## 9. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| Aynı e-posta iki hesap açar, takvim ikiye bölünür | **Yüksek etki** | G8c: e-posta doğrulama açık; §8'de elle doğrulanıyor |
| Windows'ta dönüş gelmez, kullanıcı tarayıcıda kalır | Yüksek | G8b: registry kaydı `tools/dizge_scheme.ps1` + runner'da tekil örnek; dönmezse e-posta yolu duruyor |
| Tarayıcı akışı mobilde hantal hissettirir | Orta | G8a'nın kabul edilmiş bedeli; yerel seçici sonraki iş |
| OAuth dönüşü ilk senkronu yanlış tetikler | Orta | AuthGate'in `previous.hasValue` ayrımı değişmiyor; §8'de sınanıyor |
| Sağlayıcı kapalıyken kullanıcı sebebini bulamaz | Düşük | G8d: sunucunun hatası olduğu gibi gösteriliyor |
| Dönüşteki hata `supabase_flutter`'ın eleğine takılmaz | Düşük | Paket, hatayı yalnız adres parçasında (`#error_description`) arıyor; sorgu dizesinde gelirse adresi sessizce yutar. GoTrue bugün ikisini de yolluyor. Yutulursa ekran "tarayıcıya git" yazısında kalır — form kilitli değil, kullanıcı tekrar deneyebilir ya da e-postayla girer. Gerçekten yaşanırsa çözüm kendi `app_links` dinleyicimiz |

## 10. Elle doğrulama sırası

Kod indi ama bu yol ancak gerçek bir tarayıcı turuyla bitmiş sayılır.
Sıra önemli: her adım bir öncekinin kurulumuna yaslanıyor.

1. §7.1–7.3 (Google Cloud + Supabase panosu). Bunlar bende değil.
2. ~~Derle ve şemayı kaydet~~ **(bitti, 13 Ağustos)**
   — `flutter build windows --release --dart-define-from-file=env.json`,
   sonra `tools\dizge_scheme.ps1`. Kayıt `HKCU\Software\Classes\dizge`
   altında ve Release exe'sine bakıyor.

   Windows dönüş yolu ayrıca sınandı: uygulama açıkken `dizge://login-callback`
   çağrıldığında ikinci süreç doğuyor, adresi çalışan pencereye geçirip
   kapanıyor — geriye tek örnek kalıyor.

   **Anahtarsız derleme işe yaramaz:** `AppConfig.backendAvailable` false
   olur, kapı kaçış valfiyle (G2) açık kalır ve karşılama ekranı hiç
   görünmez.
3. Uygulamayı **derlenmiş exe'den** aç (registry oraya bağlı, `flutter run`
   başka bir yola derler). "Google ile devam et" → tarayıcı → dönüş.
4. Çık, aynı Google hesabıyla tekrar gir: ilk senkron sorusu çıkmamalı.
5. E-posta+parolayla kurulmuş bir hesabın adresiyle Google'dan gir: takvim
   ikiye bölünmemeli. Bölünüyorsa §7.2 kapalı demektir ve G8.4 devreye
   girer.

## 11. Kapsam dışı

Apple ile giriş, hesap ayarlarından ikinci kimlik bağlama/çözme, Google
takvim/drive kapsamları, yerel Google seçici (mobil), tek oturum açma (SSO).
