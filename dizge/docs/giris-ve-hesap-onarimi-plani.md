# Giriş ve Hesap Onarımı Planı — Kapı, Misafir, Hesap Değiştirme, Profil

**Durum:** A1–C3 kodda (işlenmedi); cihazda doğrulama ve göç bekliyor.
Tarih: 9 Eylül 2026, güncelleme 10 Eylül 2026.

Kullanıcının bildirdiği üç şikâyet:

1. "Giriş sisteminde sıkıntı var, hâlâ tam giremiyorum; Google ile giriş
   çalışmıyor." — Belirti: *"tarayıcı açılıyor, dönünce misafir sekmesi ayrı
   bir uygulama penceresi olarak açılıyor, tarayıcı dönüp duruyor."*
2. Oturumun içindeyken **çıkış yapma** bulunamıyor.
3. **Hesap değiştirme** ve **profil özelleştirme** eksik.

Bu belge her birinin gerçek sebebini ve kapatma yolunu yazıyor. Şikâyet 2'nin
sebebi şaşırtıcı: çıkış düğmesi *var* — kullanıcı ona hiç ulaşamıyor.

---

## 1. Kök sebep: kapı iki ayrı yerden kırılmış

Belirtinin tamamı iki kusurun üst üste binmesinden geliyor. İkisi de çalışma
ağacındaki **işlenmemiş (uncommitted) değişikliklerle** girmiş.

### K1 — Pencere başlığı, tekil örnek korumasını sessizce bozdu

`windows/runner/main.cpp`, tarayıcıdan dönen `dizge://login-callback`
adresini çalışan uygulamaya `FindWindow(..., L"Dizge")` ile — yani pencere
**başlığından** — buluyor. Dosyanın kendi yorumu bunu bir değişmez olarak
yazmış:

> Pencere başlığı aşağıdaki `window.Create` çağrısıyla **birebir aynı**
> olmalı; ayrışırlarsa dönüş sessizce ikinci bir kopya açar.

`lib/main.dart`'a işlenmemiş olarak eklenen `window_manager` bloğu başlığı
çalışma anında `'Program & Takvim'` yapıyor. Artık `FindWindow` çalışan
pencereyi bulamıyor → tarayıcının başlattığı süreç adresi devredemiyor,
kendisi **ikinci bir pencere** olarak açılıyor. Kullanıcının gördüğü "ayrı bir
uygulama penceresi" tam olarak bu.

**Durum: düzeltildi.** `WindowOptions.title` `'Dizge'` yapıldı ve değişmezi
açıklayan yorum yanına yazıldı, bir daha kazara ayrışmasın diye.

### K2 — Misafir kipi, gerçek oturumu yutuyor

`AuthGate.build` şu sırayla karar veriyor (işlenmemiş değişiklik):

```dart
if (!canAuthenticate) return const AppShell();
final isGuest = ref.watch(guestModeProvider);
if (isGuest) return const AppShell();      // ← burada duruyor
_listenForLogin(context, ref);              // ← hiç kurulmuyor
final auth = ref.watch(authUserProvider);   // ← hiç okunmuyor
```

`guest_mode` yerel depoda **kalıcı**. Kullanıcı "Misafir olarak devam et"e bir
kez bastıysa kapı bir daha `authUserProvider`'a hiç bakmıyor. Google girişi
sunucu tarafında başarıyla tamamlansa bile uygulama misafir kabuğunda kalıyor.
Şikâyet 1'deki "hâlâ tam giremiyorum" bu.

Aynı kusur şikâyet 2'yi de doğuruyor: `AccountSection` misafir kipinde yalnız
"Oturum aç" satırını çiziyor, "Çıkış yap" ve "Parolanı değiştir" hiç
görünmüyor. Çıkış düğmesi eksik değil — kullanıcı onun bulunduğu duruma
giremiyor.

**Karar A — gerçek oturum misafir kipini her zaman yener.** Misafir olmak bir
*tercih* değil, oturum yokken verilen bir *izin*. Oturum açıldığı anda o iznin
konusu kalmıyor. Kapı önce kullanıcıya bakacak; gerçek kullanıcı varsa
`guest_mode` temizlenip takvim onun oturumuyla açılacak.

Alternatif — "misafir kipindeyken giriş düğmesi göster" — reddedildi: kullanıcı
zaten tarayıcıda giriş yapmış oluyor, ona bir kez daha sormak yaptığı işi yok
saymak olurdu.

### K3 — İki süreç aynı Hive kutusunu açıyor

K1 yüzünden açılan ikinci süreç, birincinin tuttuğu şifreli kutuyu açmaya
çalışıyor. Bugün gözle görülür bir hata vermiyor ama şifreli tek kutuya iki
süreçten yazmak veri kaybı riski. K1 kapandığında ikinci süreç hiç pencere
açmadan çıkacağı için sorun kendiliğinden düşüyor; yine de **taşıyıcı süreç
`bootstrap()`'a hiç girmemeli**. Bugün girmiyor (devir `wWinMain`'in ilk
satırında) — bu madde doğrulama listesinde kalacak, kod değişikliği yok.

### K4 — Artık dosya

`lib/screens/auth_gate.dart_patch` boş ve izlenmiyor. Silinecek.

---

## 2. Şikâyet 3: hesap değiştirme

Bugün yok. Var olan tek yol: Çıkış yap → karşılama ekranı → yeni hesapla gir.

**Karar B — "Hesap değiştir", çıkışın kısayolu olacak, ayrı bir mekanizma
değil.** Sebebi mimari: Hive kutusu **tek ve kullanıcıdan bağımsız**. İki
hesabın verisini aynı anda cihazda tutmanın yolu yok; "hızlı hesap değiştirme"
(çıkmadan geçiş) ancak kutuyu kullanıcı başına bölerek yapılabilir ve bu, şema
göçü + `LocalStore` yeniden yazımı demek. Bu planın kapsamı dışında.

Öyleyse hesap değiştirme, `_signOut`'un bugün yaptığı her şeyi yapacak
(kuyruğu boşalt → gönderilmemiş değişiklik varsa uyar → oturumu kapat → yerel
veriyi sil) ve sonunda karşılama ekranını **giriş kipinde** bırakacak.

Bunu ayrı bir satır olarak göstermenin değeri, kullanıcının aradığı kelimenin
"çıkış" değil "hesap değiştir" olması. Ama **bedeli gizlenmeyecek**: satırın
alt metni bu cihazdaki planların silineceğini söyleyecek, tıpkı çıkışta olduğu
gibi.

---

## 3. Şikâyet 3: profil özelleştirme

Bugün oturum açmış kullanıcı için var olan tek şey **görünen ad**
(`DisplayNameField`) ve o da çevrimiçi olmayı şart koşuyor. Avatar rengi
`userId`'nin karmasından türüyor (`palette.dart:633`), yani kullanıcı
seçemiyor. Google fotoğrafı (`Profile.avatarUrl`) sağlayıcıdan geliyor,
değiştirilemiyor.

İronik biçimde **misafirin** özelleştirmesi daha zengin: çalışma ağacındaki
yarım kalmış `_continueAsGuest` diyaloğu ad **ve renk** soruyor.

**Karar C — renk seçimi oturum açmış kullanıcıya da gelecek.** Rozet grup
arkadaşlarının gördüğü şey; onu seçememek, adı seçebilip yüzü seçememek
demek.

Bunun bir sunucu maliyeti var: renk `profiles` tablosuna bir sütun
(`avatar_color smallint`) ister ve bir göç dosyası demek. Göç adı sıra
numarası taşıyacak (mevcut kural).

**Karar D — misafir profili düzgün modellenecek.** Çalışma ağacındaki
`guestProfileProvider`, rengi taşımak için `userId: 'guest_color_$idx'` gibi
sahte bir kimlik uyduruyor ve `profileProvider` bu dizeyi ön ekinden tanımaya
çalışıyor. Kimliğin içine veri gömmek, ilerideki her `userId` karşılaştırmasını
sessizce bozar. Renk `Profile`'ın kendi alanı olacak (Karar C'nin sunucu
sütununun istemci karşılığı), misafir de gerçek kullanıcı da aynı alanı
kullanacak.

---

## 4. Dilimler

| # | İş | Dosyalar | Görünür mü |
|---|-----|----------|------------|
| **A1** | Pencere başlığı `'Dizge'` + değişmez yorumu | `lib/main.dart` | Windows'ta Google dönüşü tek pencerede kalır |
| **A2** | Gerçek oturum misafir kipini yener; giriş anında `guest_mode` temizlenir | `lib/screens/auth_gate.dart` | **Evet** — giriş artık gerçekten içeri alır |
| **A3** | Artık dosyayı sil | `auth_gate.dart_patch` | Hayır |
| **B1** | `Profile.avatarColor` alanı + `fromRow`/`toJson`/`copyWith` | `lib/models/profile.dart` | Hayır |
| **B2** | `profiles.avatar_color` sütunu + göç dosyası (sıra numaralı ad) | `supabase/` | Hayır |
| **B3** | Misafir profili sahte kimlik yerine gerçek alanı kullanır | `lib/core/profile_directory.dart` | Hayır |
| **C1** | "Hesap değiştir" satırı (çıkışın kısayolu, aynı korumalar) | `lib/screens/account/session_section.dart` | **Evet** |
| **C2** | Renk seçici: oturum açmış kullanıcı için profil bölümüne | `lib/screens/account/profile_section.dart` | **Evet** |
| **C3** | Misafir diyaloğunu tamamla (denetleyici sızıntısı dahil) | `lib/screens/welcome_screen.dart` | **Evet** |

A1–A3 girişi açar; onlar olmadan B ve C'nin görüleceği bir ekran yok. Bu
yüzden A dilimi tek başına da inebilir.

### Bilinçli kapsam dışı

* **Kutuyu kullanıcı başına bölmek.** Karar B'nin gerekçesi. Gerçek hızlı hesap
  değiştirmenin önkoşulu ama ayrı bir plan.
* **Profil fotoğrafı yükleme.** Depolama kovası + boyutlandırma + moderasyon
  demek; renk ve ad bugünkü ihtiyacı karşılıyor.
* **Çevrimdışı ad değişikliği.** Bugünkü "kaydet pasif" davranışı doğru
  (`profile_section.dart`'taki gerekçe duruyor).

---

## 5. Senin yapman gerekenler (kod dışı)

1. **Windows'ta şemayı yeniden bağla.** Registry bugün `Release\Dizge.exe`'ye
   bakıyor (7 Eylül derlemesi) ama sen Debug'ı çalıştırıyorsun. A1'den sonra
   devir çalıştığı için hangi kopyanın başlatıldığı önemsizleşiyor — yine de
   kaydı güncel exe'ye bağlamak temiz olur:

   ```
   powershell -ExecutionPolicy Bypass -File tools\dizge_scheme.ps1
   ```

2. **Supabase panosu → Redirect URLs.** *(bitti — kullanıcı doğruladı,
   `dizge://login-callback` listede.)*

3. **Göç 05'i panoda çalıştırmak:**
   `supabase/migrations/05_20260909120000_profil_rengi.sql`. `profiles`
   tablosuna dayanıyor, yani önce 04 (`04_..._profiles.sql`) çalışmış olmalı.
   İki kez yapıştırmak zararsız. Dosyanın sonundaki doğrulama sorgusu
   `avatar_color | smallint | YES` döndürmeli.

---

## 6. Bitti sayılır

* [ ] Windows'ta Google ile giriş: tarayıcı açılır, hesap seçilir, **tek**
  pencereye dönülür ve takvim o hesapla açılır.
* [ ] Daha önce misafir olarak devam etmiş bir cihazda Google/e-posta girişi
  içeri alır; misafir kabuğunda takılmaz.
* [ ] Oturum açıkken Hesap ekranında **Çıkış yap**, **Hesap değiştir** ve
  **Parolanı değiştir** üçü de görünür.
* [ ] "Hesap değiştir" gönderilmemiş değişiklik varken uyarır, vazgeçilirse
  hiçbir şey silmez.
* [ ] Oturum açmış kullanıcı rozet rengini seçebilir; seçim yeniden açılışta ve
  grup arkadaşlarında görünür.
* [ ] Misafir adı ve rengi seçilebilir; ikinci açılışta korunur.
* [x] `flutter analyze` temiz, tüm testler yeşil (638). Kırık 8 test bu
  plandan değil, aynı ağaçtaki mobil arayüz paketinden geliyordu; 10 Eylül'de
  kapandı: geniş ekranda havuz şeridi geri geldi, aylık hücrede dokunuş yine
  tamamlıyor (uzun basış/sağ tık menü açıyor), sahiplik rozeti geri kondu,
  elle yazılmış ölçüler ölçeğe döndü.
* [x] Kapıyı sınayan yeni testler: misafirken giriş, hesap değiştirme akışı.

---

## 7. Riskler

| Risk | Etki | Karşılık |
|------|------|----------|
| Pencere başlığı ileride yine değişir, dönüş sessizce bozulur | Yüksek | A1'in yanındaki yorum; ayrıca `main.cpp` zaten uyarıyor. Bir test yazılamıyor — süreçler arası. |
| Misafir verisi girişte ilk senkron sorusunu tetikler | Orta | `FirstSyncCoordinator` bu soruyu zaten soruyor; misafirin yazdıkları "bu cihazdakiler" seçeneğiyle korunabiliyor. |
| `avatar_color` göçü panoda çalıştırılmazsa renk seçimi sessizce kaybolur | Orta | İstemci sütun yokken eski davranışa (karma renk) düşecek, hata vermeyecek. |
| İki hesap aynı cihazda, biri diğerinin verisini görür | Yüksek | Karar B: hesap değiştirme yerel veriyi siliyor — `_signOut`'un bugünkü davranışı korunuyor. |
