# 10 Eylül Geri Bildirimi — Giriş Dönüşü, Parola Güvenliği, Bildirimler, Gruplar, Havuz, Süre, Kategoriler

**Durum:** onay bekliyor. Tarih: 10 Eylül 2026.
**Önceki:** `giris-ve-hesap-onarimi-plani.md` (Google girişi artık içeri alıyor),
`zaman-araliklari-ve-adlandirma-plani.md` (Zd — görünen ad katmanı).

Gelen dokuz madde, her birinin kodda doğrulanmış sebebi ve kapatma yolu.
Kod yazılmadı; onaydan sonra dilim dilim ilerlenecek.

---

## 0. Önce: çalışma ağacını işlemek

Ağaçta ~50 dosyalık işlenmemiş değişiklik var. İçinde **iki ayrı iş** var:
giriş/hesap onarımı (A–D) ve plan dışı bir mobil arayüz paketi (alt menü, 3
günlük hafta, aylık menü, gün görünümü okları, bildirim servisi). Bu planın
dilimleri o dosyaların çoğuna yeniden dokunacak. Önce işlemezsek yeni işi
eskisinden ayırmanın yolu kalmaz.

**Öneri:** iki commit — (1) giriş/hesap onarımı + göç 05, (2) mobil arayüz
paketi + 10 Eylül test onarımları. Onayınla yapılır.

---

## 1. Google girişi: tarayıcı sekmesi "yükleniyor"da kalıyor

**Sebep.** Dönüş adresi özel şema: `dizge://login-callback`. Tarayıcı bu
adrese yönlenince uygulamayı açıyor, ama **kendisi gösterecek bir sayfa
bulamıyor**. Sekme Google'ın son sayfasında dönüp duruyor. Giriş başarılı,
yalnızca tarayıcı tarafı yarım kalıyor. Bir sekmeyi betikle kapatmak da
mümkün değil: tarayıcılar yalnız betiğin kendi açtığı pencereyi kapattırıyor.

**Karar G1 — masaüstünde dönüş yerel bir adrese yapılacak.** Uygulama giriş
başlarken `127.0.0.1` üzerinde sabit bir portta (öneri: `53682`) küçük bir
HTTP dinleyici açar. Dönüş adresi `http://127.0.0.1:53682/auth-callback` olur.
Tarayıcı oraya döndüğünde:

1. Uygulama gelen kodu oturuma çevirir (`getSessionFromUrl`, PKCE).
2. Tarayıcıya **bizim sayfamızı** gönderir: Dizge işareti, "Giriş tamamlandı —
   bu sekmeyi kapatıp Dizge'ye dönebilirsin". Hata varsa "Giriş tamamlanmadı"
   ve sebebi.
3. Uygulama penceresini öne getirir (`windowManager.focus()`).
4. Dinleyiciyi kapatır. Tek kullanımlık; 5 dakika içinde dönüş olmazsa
   kendiliğinden kapanır.

Port doluysa bugünkü özel şema yoluna düşülür; giriş yine çalışır.

* **Android değişmiyor:** orada özel şema zaten uygulamaya geçiş yapıyor ve
  bir şikâyet gelmedi.
* **Bedeli:** Supabase panosunda Redirect URLs listesine bir adres eklemek
  (§10).

## 2. Giriş düğmelerinde simge

* **Google ile devam et** → solda resmî 4 renkli Google "G" işareti. Google'ın
  marka kılavuzundaki SVG, `assets/brand/google_g.svg` olarak eklenir.
  `flutter_svg` bağımlılığı gelir. Kodda şimdi "resmî varlık yok, yaklaşık
  çizmeyeceğim" diyen bir yorum var; bu dilim o varlığı ekliyor.
* **Giriş yap / Hesap oluştur** (e-posta düğmesi) → zarf simgesi
  (`Icons.mail_outline_rounded`).
* **Misafir olarak devam et** → kişi simgesi. Üç düğme aynı dili konuşsun
  diye.

---

## 3. Parola ve e-posta güvenliği

**Bugün ne var (doğrulandı):**

| Akış | Durum | Sorun |
|---|---|---|
| Kayıt | e-posta + tek parola | Tekrar yok; kural gösterilmiyor. Sunucuda "e-posta onayı" açıksa kayıttan sonra ekran **hiçbir şey demiyor**. |
| Parola kuralı | "en az 6 karakter" | Zayıf; kullanıcı hatayı ancak gönderince görüyor. |
| Parolamı unuttum | e-postaya kod → giriş | Yeni parola **sorulmuyor**; "sonra Hesap ekranından değiştir" deniyor. Çoğu kişi değiştirmez. |
| Parola değiştir | tek alanlı diyalog | Eski parola yok, tekrar yok, kural yok. Oturumu açık bırakılmış bir cihazda herkes parolayı değiştirebilir. |
| E-posta metinleri | Supabase varsayılanı | İngilizce. Bağlantılı olanlar Windows'ta açılmıyor (derin bağlantı). |

**Karar P1 — tek parola politikası, sunucuyla aynı, ekranda görünür.**
Kural: **en az 8 karakter, en az bir harf, en az bir rakam**. Supabase
panosunda da aynısı ayarlanır (§10). İstemci kuralı yazılırken gösterir, bir
onay listesi olarak:

```
Parola
[••••••••••      ]
 ✓ En az 8 karakter
 ✓ Harf içeriyor
 ○ Rakam içeriyor
 Güç: ▮▮▮▯ Orta
Parola (tekrar)
[••••••••••      ]  ✓ Eşleşiyor
```

Güç göstergesi kurala ek bir ipucu (uzunluk + karakter çeşitliliği), engel
değil. Engel yalnız kural. Sunucunun zayıf parola hatası (`weak_password`) da
Türkçeye çevrilir.

**Karar P2 — e-postadaki her şey bağlantı değil KOD.** Kurtarmada zaten böyle
yapılıyor, gerekçesi aynı: bağlantılar Windows'ta derin bağlantı istiyor ve
tarayıcıda açılıp kalıyor. Kayıt onayı da 6 haneli kodla olur:

* **Kayıt:** e-posta, parola, parola tekrar → "E-postanı doğrula" adımı: kod
  alanı, "Kodu yeniden gönder" (60 sn bekleme sayacıyla), "E-postayı
  değiştir".
* **Parolamı unuttum:** e-posta → kod → **"Yeni parolanı belirle"** adımı
  (yeni + tekrar + kural listesi). Parola kaydedilince takvim açılır.
  Kurtarma yarım kalmaz.
* **Parola değiştir** (Hesap → ayrı bir sayfa, diyalog değil):
  * Mevcut parola + yeni + tekrar + kural listesi.
  * Mevcut parola sunucuda doğrulanır (yeniden giriş). Yanlışsa hiçbir şey
    değişmez.
  * "Mevcut parolanı hatırlamıyor musun?" → e-postaya doğrulama kodu gider
    (`reauthenticate`), kodla değiştirilir.
  * ☐ "Diğer cihazlardaki oturumları kapat". Parola sızdı diye
    değiştiriyorsan asıl istediğin budur.
  * Yalnız Google ile giren hesapta sayfanın adı **"Parola belirle"**
    olur. Mevcut parola alanı olmaz, doğrulama kodla yapılır. Böylece o
    hesap e-postayla da girebilir.

**Karar P3 — e-posta şablonları Türkçe ve depoda.**
`supabase/templates/` altına beş şablon eklenir: kayıt onayı, giriş/kurtarma
kodu, yeniden doğrulama, e-posta değişikliği, parola değişti bildirimi. Hepsi
kodu (`{{ .Token }}`) büyük ve kopyalanabilir gösterir. Sen panoya
yapıştırırsın (§10).

**Önemli kısıt — Supabase'in yerleşik e-posta servisi.** Yerleşik servis
saatte yalnız birkaç e-posta gönderiyor ve ekip üyesi olmayan adreslere
gönderimi kısıtlıyor. Bu durumda kayıt onayı ve kurtarma kodu gerçek
kullanıcılara **ulaşmaz**. Kalıcı çözüm özel SMTP: Resend/Brevo gibi bir
servisin ücretsiz katmanı yeterli. Kod bunu çözemez; §10'da adım adım.

---

## 4. Bildirimler çalışmıyor + eski uyarı

**Sebepler (hepsi doğrulandı):**

1. **Hesap ekranındaki "Bildirimler" satırı kasten ölü.** `AccountTile`
   sönük bir yer tutucu; dokununca hiçbir şey olmuyor.
   (`account_screen.dart:97`)
2. **Üstündeki uyarı eskiden kalma.** "Hesap sistemi backend eklendiğinde
   çalışır hale gelecek…" (`account_tiles.dart:105`). Hesap sistemi çoktan
   çalışıyor. Silinecek.
3. **Windows'ta bildirim hiç yok.** `flutter_local_notifications` 17.x
   Windows'u desteklemiyor. Destekleyen sürüme yükseltilecek; hangi sürüm
   olduğu yükseltirken doğrulanacak.
4. **Android'de zamanlanan bildirim hiç düşmüyor.** Manifestte ne bildirim
   izni (`POST_NOTIFICATIONS`) var ne de zamanlayıcı alıcıları
   (`ScheduledNotificationReceiver`, açılışta yeniden kurma). Üstüne tam
   saatli alarm izni istenmeden `exactAllowWhileIdle` kullanılıyor, bu da
   Android 14'te hata fırlatır.
5. **Saat dilimi yanlış.** `tz.local` hiç ayarlanmıyor, varsayılanı UTC. Yani
   14:00'lük iş Türkiye'de **17:00'de** hatırlatılır.
6. **Yalnız tek günlük işler kuruluyor.** Rutinler, çoklu saatler ve başka
   cihazdan senkronla gelen işler hiç kurulmuyor. Tamamlanan ya da iptal
   edilen işin bildirimi de iptal edilmiyor.

**Karar N1 — tek bir "bildirim planlayıcı", iş işin ekleme yoluna değil
depoya bağlı.** İş eklemede tek tek kurmak yerine depo her değiştiğinde
(birkaç saniyelik gecikmeyle) önümüzdeki 7 günün hatırlatmaları baştan
hesaplanır:

* Kapsam: rutinler ve çoklu saatler dahil; tamamlanan, iptal edilen ve
  havuzdaki işler hariç.
* Üst sınır 60 hatırlatma.
* Bildirim kimlikleri kararlı bir karmayla üretilir (`iş kimliği + gün +
  saat`). Böylece aynı hatırlatma iki kez kurulmaz.

Senkronla gelen iş de bu yoldan kendiliğinden kurulur.

**Karar N2 — "Bildirimler" gerçek bir ayar sayfası.**

```
Bildirimler
 [●] Hatırlatmalar açık
 Ne zaman?   ( Tam saatinde | 5 dk | 10 dk | 15 dk | 30 dk önce )
 [●] Rutinleri de hatırlat
 İzin durumu: ✓ Verildi   /   ⚠ Kapalı — [Sistem ayarlarını aç]
 [ Deneme bildirimi gönder ]
```

Deneme düğmesi "çalışıyor mu" sorusuna tek dokunuşla cevap. Bildirim izni
açılışta değil **bu sayfada ya da ilk saatli iş eklenince** istenir. Bugün
açılışın ilk saniyesinde bağlamsız soruluyor.

---

## 5. Grup kurmak "kurulmuş gibi hissettirmiyor"

**Sebep.** Bugünkü akışta:

* Diyalog yalnız ad soruyor. "Kur" deyince grup oluşuyor, diyalog kapanıyor
  ve bağlam gruba geçiyor.
* Ama takvim **aynı görünüyor**. Grup bağlamı yalnız bir süzgeç; yeni grupta
  iş olmadığı için ekranda hiçbir şey değişmiyor.
* Grubun kendi sayfası yok. Başarı anı, üye listesi ya da davet adımı da yok.
* Modelde `description` ve `color` alanları eklenmiş (plan dışı paket), ama
  sunucuda karşılıkları yok. Hiçbir ekran da onları sormuyor.

**Karar R1 — tek ekranda kur.** "Yeni grup" bir alt sayfa (sheet):

```
Yeni grup
 ┌───────────────┐
 │ (E)  Ev       │   ← canlı önizleme: renkli rozet + ad
 └───────────────┘
 Grup adı      [Ev                    ]
 Renk          ● ● ● ● ● ● ● ●
 Açıklama      [Ev işleri ve alışveriş] (isteğe bağlı)
                                [ Grubu kur ]
```

Ad yazılır yazılmaz kurulmaz. Her şey tek formda seçilir, "Grubu kur" tek
adımdır.

**Karar R2 — başarı anı + davet, aynı sayfada.** Düğme basılınca "Grup
kuruluyor…" gösterilir. Bitince sayfa **başarı hâline** döner:

```
 ✓ "Ev" kuruldu
 Birini davet et: [e-posta (isteğe bağlı)] [Davet kodu üret]
 (kod üretilince panoya kopyalanır ve burada görünür)
                     [ Sonra ]   [ Gruba git → ]
```

**Karar R3 — grubun kendi sayfası.** "Gruba git" ve grup menüsündeki yeni
"Grup sayfası" satırı buraya açılır:

* Başlık: renk şeridi, ad, açıklama.
* Üyeler: rozet + ad, sahip işaretli.
* Davet (yalnız sahip).
* Bu haftanın grup işleri (özet).
* Ayarlar: ad/renk/açıklama düzenleme (yalnız sahip), gruptan çık.

Takvimde grup bağlamındayken üstte **grubun renginde ince bir şerit** ve
adı durur. "Şu an Ev grubundasın" ada bakmadan da görünür.

**Sunucu:** göç **06** — `groups.description`, `groups.color` sütunları;
`create_group` ad + renk + açıklama alır; sahip için `update_group`. Üye
listesi için sunucudaki üyelik okuma kuralına bakılacak. Gerekirse aynı göçe
bir okuma fonksiyonu eklenir.

---

## 6. "Kenarda Bekleyenler" → **Havuz**

Kullanıcı haklı: iki kelimelik, ne olduğunu söylemeyen bir ad. Bütün
yüzeylerde:

| Bugün | Olacak |
|---|---|
| Kenarda Bekleyenler (menü, panel, şerit, ekran başlığı) | **Havuz** |
| Kenara al (blok önizlemesi) | **Havuza al** |
| Kenara alındı (geri al bildirimi) | **Havuza alındı** |
| "6 iş kenara alındı" (Günü kurtar) | "6 iş havuza alındı" |
| Kenarda bekleyen iş yok. | Havuz boş. |

Metinler tek bir sabit dosyasında toplanır. Aynı ad bir daha dört yerde ayrı
ayrı değiştirilmesin (`cancelLabel` ile aynı ders).

---

## 7. Saat ve süre

**Bugün.** Düzenleyicide "Saat ve Süre" tek satır (plan dışı paket iki
satırı birleştirdi). Model dört durumdan yalnız üçünü taşıyor:

| | Süreli | Süresiz |
|---|---|---|
| **Saatli** | 14:00, 1 sa (blok) ✓ | 14:00'te ara, **yok** ✗ |
| **Saatsiz** | bugün bir yerde 2 sa ✓ | yalnız "bugün" ✓ (süre gizli 1 sa) |

"Süresiz" diye bir seçenek yok. Süre en az 15 dakika, varsayılan 1 saat.

**Anladığım istek** (yanlışsa düzelt): başlangıç saati ve süre birbirinden
**bağımsız** iki ayar olsun. Her ikisi de "yok" olabilsin. Özellikle eksik
durum eklensin: **saati var, süresi yok** ("15:00'te annemi ara").

**Karar Z1 — iki ayrı satır, ikisi de "yok" diyebilir.**

```
Saat   [ Saatsiz | 09:00 | 12:00 | … | Diğer… ]
Süre   [ Süresiz | 15 dk | 30 dk | 1 sa | 2 sa | … ]  + ince ayar
```

* Süresiz iş, depoda `durationHours = 0`. Sunucu şeması değişmez; iş verisi
  zaten JSON olarak gidiyor.
* **Izgarada:** saatli-süresiz iş, kendi saatinde ince bir **işaret çizgisi
  + başlık hapı** olarak durur (blok değil). Başka blokları itmez, ama
  tıklanıp taşınabilir.
* **Günü kurtar ve raporlar:** süresiz iş 0 dakika sayılır. Kurtarma onu
  zamanı yetmedi diye havuza atmaz.

`durationHours` 31 yerde okunuyor. Her biri "0 olabilir" varsayımına göre
gözden geçirilir, özellikle bitiş saati hesabı ve ızgara yüksekliği.

---

## 8. Kategoriler: kısa ad + özel ad/renk

**Bugün.** Adlar iki eksen karıştırıyor: tür ("Hobi / keyfi") ile sıklık
("Haftalık / ara sıra", "Günlük rutin"). Sıklık zaten işin kendi ayarı (Tek
Günlük / Rutin). Kullanıcı kategori ekleyebiliyor, ama **var olanın adını ya
da rengini değiştiremiyor**.

**Karar K1 — tek kelimelik varsayılan adlar (öneri — değiştirebilirsin).**
Zd kararı korunuyor: **depodaki anahtar değişmez**, yalnız ekrandaki ad
değişir. Senkron ve eski cihaz riski yok.

| Depoda (değişmez) | Bugün ekranda | Önerilen |
|---|---|---|
| Kalıcı iş | Kalıcı İş | **Mesai** |
| Günlük rutin | Günlük Rutin | **Gündelik** |
| Haftalık / ara sıra | Haftalık / Ara Sıra | **Seyrek** |
| Önemli / acil | Önemli / Acil | **Acil** |
| Hobi / keyfi | Hobi / Keyfi | **Hobi** |
| Sosyal | Sosyal | Sosyal |
| Diğer | Diğer | Diğer |

("Rutin" bilerek kullanılmadı: işin türü "Rutin" ile çakışır.)

**Karar K2 — her kategoriye özel ad ve renk.** Hesap → Görünüm'e "Kategoriler"
sayfası:

```
Kategoriler
 ● Mesai        ✎
 ● Gündelik     ✎
 ● Hobi         ✎
 …
 [+ Yeni kategori]
```

✎ → ad alanı + renk paleti. Hazır kategoride "Varsayılana dön", özelde "Sil".

* Ad değişikliği yalnız **görünen ada** yazılır (yeni `label` alanı). Anahtar
  aynı kalır.
* Renk değişince, o kategoride olup rengi elle değiştirilmemiş işler de yeni
  rengi alır.
* Senkron: kategori satırına `label` sütunu. Göç **06**'ya eklenir, kategori
  mutasyon fonksiyonu bu alanı da yazar.

Düzenleyicideki kategori seçicide de en sonda "Düzenle…" kısayolu olur.

---

## 9. Konum — ertelendi

Kendin "acil değil" dedin. D5'te canlı konum bilerek düşürüldü (izin + pil +
masaüstünde anlamsız). Kapsam dışı. İleride istersen "Şu anki konumu ekle"
tek düğmesi olarak ayrı bir plan.

---

## 10. Senin yapman gerekenler (kod dışı)

1. **Supabase → Authentication → URL Configuration → Redirect URLs:**
   `http://127.0.0.1:53682/auth-callback` ekle (G1).
2. **Authentication → Providers → Email:**
   * "Confirm email" açık.
   * "Secure password change" açık.
   * Minimum parola uzunluğu **8**.
   * Parola gereksinimi "letters and digits".
3. **Authentication → Email Templates:** `supabase/templates/` içindeki beş
   şablonu ilgili kutulara yapıştır (P3).
4. **Özel SMTP (önemli):** Resend veya Brevo'da ücretsiz hesap → Supabase →
   Project Settings → Auth → SMTP. Yapılmazsa kayıt/kurtarma kodları gerçek
   kullanıcılara ulaşmaz (§3).
5. **Göç 05 ve 06'yı panoda çalıştır** (sırayla).

---

## 11. Dilimler

| # | İş | Görünür mü | Bağımlılık |
|---|---|---|---|
| **S0** | Ağacı iki commit'e böl | Hayır | onay |
| **H1** | Havuz adlandırması + metin sabitleri | Evet | — |
| **N1** | Bildirim paketi yükseltme, Android manifest, saat dilimi | Hayır | — |
| **N2** | Planlayıcı (depoya bağlı, 7 gün, rutinler dahil) | Evet | N1 |
| **N3** | Bildirim ayar sayfası + eski uyarıyı silme | Evet | N2 |
| **G1** | Masaüstünde yerel dönüş adresi + "giriş tamamlandı" sayfası | Evet | pano §10.1 |
| **G2** | Google "G" + zarf + kişi simgeleri | Evet | — |
| **P1** | Parola politikası + canlı kural listesi + güç göstergesi (paylaşılan bileşen) | Evet | — |
| **P2** | Kayıt: parola tekrar + e-posta doğrulama kodu adımı | Evet | P1 |
| **P3** | Unuttum: kod → yeni parola adımı | Evet | P1 |
| **P4** | Parola değiştir sayfası (eski parola, kodla doğrulama, diğer oturumları kapat, Google hesabında "belirle") | Evet | P1 |
| **P5** | Türkçe e-posta şablonları + hata çevirileri | Hayır | — |
| **R1** | Göç 06 (grup renk/açıklama, `update_group`, kategori `label`) | Hayır | — |
| **R2** | Tek ekranda grup kurma + başarı/davet hâli | Evet | R1 |
| **R3** | Grup sayfası + takvimde grup şeridi | Evet | R2 |
| **Z1** | Süre ve saat ayrı satırlar, "Süresiz" | Evet | — |
| **Z2** | Süresiz işin ızgarada işaret çizgisi; kurtarma/rapor uyumu | Evet | Z1 |
| **K1** | Kısa varsayılan adlar | Evet | — |
| **K2** | Kategoriler sayfası: ad/renk düzenleme, senkron | Evet | K1, R1 |

**Önerilen sıra:** S0 → H1 → N1–N3 → G1–G2 → P1–P5 → Z1–Z2 → K1 → R1 →
R2–R3 → K2. Önce küçük ve bozuk olanlar (ad, bildirim), sonra güvenlik, en
son sunucu göçü isteyenler (göçü bir kez, toplu çalıştırasın diye).

Her dilim: test → `flutter analyze` temiz → tam takım yeşil → kendi commit'i.

---

## 12. Bitti sayılır

* [ ] Windows'ta Google girişi: tarayıcıda "Giriş tamamlandı" sayfası çıkar,
  uygulama öne gelir.
* [ ] Google düğmesinde resmî G, e-posta düğmesinde zarf.
* [ ] Kayıt: parola tekrarı ve kural listesi var; e-posta kodla doğrulanıyor;
  kod yeniden istenebiliyor.
* [ ] Unuttum: koddan sonra yeni parola soruluyor.
* [ ] Parola değiştir: eski parola yanlışsa hiçbir şey değişmiyor; kodla
  değiştirme çalışıyor; Google hesabında "Parola belirle".
* [ ] Deneme bildirimi Windows'ta ve Android'de düşüyor; 14:00'lük iş
  14:00'te (seçilen önceden-süre kadar erken) hatırlatılıyor.
* [ ] Hesap ekranında eski "backend eklendiğinde" uyarısı yok.
* [ ] Grup tek formda ad+renk+açıklamayla kuruluyor; başarı anı ve davet
  görünüyor; "Gruba git" grup sayfasını açıyor; takvimde grup şeridi var.
* [ ] Hiçbir yüzeyde "Kenarda" yazmıyor; her yerde "Havuz".
* [ ] Saatli-süresiz iş yazılabiliyor ve ızgarada işaret olarak görünüyor.
* [ ] Kategoriler tek kelime; ad ve renk değiştirilebiliyor, ikinci cihazda
  da görünüyor.

## 13. Riskler

| Risk | Etki | Karşılık |
|---|---|---|
| 53682 portu başka programda | Düşük | Özel şema yoluna düşülür; giriş yine çalışır. |
| Özel SMTP kurulmaz | **Yüksek** | Kayıt/kurtarma kodu ulaşmaz. §10.4; ekranda "kod gelmedi mi?" yardımı. |
| `durationHours = 0` beklenmedik yerde bölme/boş blok | Orta | 31 kullanım tek tek gözden geçirilir; ızgara, kurtarma, rapor testleri. |
| Bildirim paketi yükseltmesi Android derlemesini kırar | Orta | N1 tek başına bir dilim; APK derlenip denenmeden N2'ye geçilmez. |
| Göç 06 çalıştırılmadan istemci renk/açıklama/etiket yollar | Orta | Göç 05'teki gibi: sütun yoksa alan yok sayılır, eski davranış. |
| Kategori `label` eski sürümdeki cihazda yok | Düşük | Eski cihaz depodaki adı gösterir. Veri bozulmaz, yalnız ad eski görünür. |
