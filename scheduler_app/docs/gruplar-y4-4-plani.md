# Y4.4 Planı — Kimlik: profiller, avatarlar, sahiplik işareti

**Durum:** ✅ **kod tarafı bitti** — altı dilimin altısı indi (13 Ağustos).
Kalan: migration 04'ün panoda çalıştırılması ve §10'daki elle tur.
**Tarih:** 13 Ağustos 2026
**Önceki:** `gruplar-y4-plani.md` §6 (karar Y4e), `gruplar-y3-plani.md` (migration 03)
**Önkoşul:** Migration 03 sunucuda çalıştı; `owner_id` istemciye kadar geliyor (Y4.1).

---

## 1. Bugün ne var

Sahiplik bilgisi **zaten istemcide**: Y4.1 `owner_id` sütununu payload'a katıyor,
`Task.ownerId` ve `Node.ownerId` dolu geliyor. Eksik olan tek şey onu insana
çevirmek — bugün elimizde yalnız bir uuid var ve uuid kimseye gösterilemez.

Kodun bugünkü hâli:

| Yer | Durum |
|---|---|
| `profiles` tablosu | **yok** |
| `display_name` | `lib/` içinde hiç geçmiyor |
| `AuthUser` | yalnız `{id, email}` — Google'ın gönderdiği ad ve fotoğraf `user_metadata`'da duruyor, okunmuyor |
| Hesap ekranı `_ProfileHeader` | gradyanlı kutu + jenerik `Icons.person_rounded`; başlık satırı e-posta |
| Bloklar, aylık hücreler, listeler | sahiplik işareti yok |

G8 ile Google girişi indi; yani bugünden itibaren kaydolan kullanıcıların
**adı ve fotoğrafı sunucuda mevcut** ve kullanılmıyor.

---

## 2. Karar Y4.4a — `profiles` tablosu *(migration 04)*

Plan Y4e'nin uygulaması. `auth.users` başkasına kapalı ve kapalı kalmalı
(orada e-posta, telefon, sağlayıcı kimlikleri var). Gösterilebilir alanlar
ayrı bir tabloya çıkar:

```
profiles(user_id pk → auth.users, display_name text, avatar_url text, updated_at)
```

**RLS:** herkes kendi satırını yazar; **okuma** kendi satırı + ortak grubu
olanlar. Ortaklık sorgusu politikanın içine düz yazılamaz — Y3c'de öğrenilen
özyineleme ve satır-başına-değerlendirme tuzağının aynısı burada da var.
Bu yüzden `security definer`, `stable`, `search_path` sabitli bir yardımcı:

```sql
public.shares_group_with(other uuid) returns boolean
```

**Dolum:** `auth.users` üzerinde bir `after insert` trigger'ı:

* `display_name` ← `raw_user_meta_data->>'full_name'` → `->>'name'` →
  `split_part(email, '@', 1)` (ilk dolu olan)
* `avatar_url` ← `raw_user_meta_data->>'avatar_url'` → `->>'picture'`

Google ile gelenler adlarını ve fotoğraflarını kendiliğinden alır; e-postayla
kaydolanlar e-postanın `@` öncesini alır ve hesap ekranından değiştirir.

**Geri dolum:** dosya idempotent olduğu için mevcut kullanıcılar da aynı
mantıkla `insert … select from auth.users … on conflict do nothing` ile
doldurulur. Trigger'ı yazıp bugünkü iki hesabı dışarıda bırakmak, özelliği
kendi geliştiricisine kapalı açmak olurdu.

**Realtime:** `profiles` yayına **girmiyor**. Y2a'nın kuralı: Realtime bir
sinyal, veri yolu değil — ve ad değişimi saniyelik gecikmesi olan bir olay
değil.

## 3. Karar Y4.4b — Avatar bir işaret; fotoğraf varsa fotoğraf, yoksa baş harf

Tek bir `UserAvatar` widget'ı, üç durumu da kendi içinde çözer:

1. `avatar_url` dolu ve ağ var → fotoğraf,
2. yoksa / yüklenemezse → renkli baş harf rozeti,
3. profil hiç bilinmiyorsa (yeni üye, önbellek soğuk) → nötr `?` rozeti.

**Yeni paket eklenmiyor.** `cached_network_image` fotoğrafı diske yazardı;
bir avatar için başkasının fotoğrafını kullanıcının diskinde kalıcılaştırmak
ağır bir borç. Flutter'ın bellek içi `ImageCache`'i oturum boyunca yeter:
uygulama açıkken fotoğraf bir kez iner. **Çevrimdışı açılışta baş harfler
görünür** — bu bir kusur değil, bilinçli sınır.

## 4. Karar Y4.4c — Baş harf addan, renk **kimlikten** türer

Seçim ekranında "ad değişince renk de değişir" yazmıştım; koda dökerken bu
yanlış çıktı ve kararı düzeltiyorum:

* **Baş harf** addan gelir: ilk iki sözcüğün baş harfleri (`Ali Okan` → `AO`),
  tek sözcükse ilk harf, boş/tanınmayan ad için `?`.
* **Renk** `user_id`'den gelir: sabit bir hash → sabit bir palet dizisi.

Gerekçe: renk, tarama anında "aynı kişi" demenin en hızlı yolu. Ada bağlasaydım
biri adını "Ali"den "Ali Okan"a çevirdiğinde geçmiş haftalardaki bütün blokları
renk değiştirirdi — kullanıcı için sebepsiz bir kayma. Baş harf değişmeli
(çünkü ad değişti), renk değişmemeli (çünkü kişi değişmedi).

Palet 8 renk; baş harf mürekkebi `AppPalette.readableOn()` ile üretilir, yani
kontrast bir test temennisi değil rengi üreten kodun kendisi (ana ekran
planının §9'undaki kuralın aynısı).

## 5. Karar Y4.4d — Ad payload'a yazılmaz, ayrı önbellekten okunur

Satırda `ownerId` var; adı da oraya yazmak iki şeyi bozardı: veri çoğalırdı ve
biri adını değiştirdiğinde eski satırlar sonsuza dek eski adı gösterirdi.

Karar: `uuid → Profile` haritası ayrı durur, `groups.cache` deseninin aynısıyla
`profiles.cache` anahtarına yazılır. Tazeleme grup listesiyle **aynı anda**
olur (`GroupContextController.refresh`) — profiller yalnız grup bağlamında
görünüyor, ayrı bir tazeleme takvimi icat etmeye değmez.

Hata yutulur: ad gelmezse baş harf `?` olur, ekran açılmaya devam eder.

## 6. Karar Y4.4e — Rozet grup bağlamında **herkeste**, kişiselde hiç kimsede

Kişisel bağlamda her satır zaten senin; oradaki avatar yalnız gürültü olurdu.

Grup bağlamında ise seninkiler dahil herkes rozet taşır. Alternatif ("yalnız
başkalarınınkiler işaretlensin") daha sessiz görünüyor ama işaretin **yokluğunu**
anlamlı kılıyor: öğrenilmesi gereken sessiz bir kural, ve boş bir haftada
öğrenilemez.

## 7. Karar Y4.4f — Tam ad detayda, rozet yüzeyde

| Yüzey | Boyut | Ne gösterir |
|---|---|---|
| Haftalık ızgara bloğu | 14px, sağ üst | Avatar. Tam ad `ShadTooltip`'te ve `Semantics`'te |
| Aylık hücre satırı | 12px, başlıktan önce | Avatar |
| Liste ekranları (yapılacaklar, notlar) | 16px, satır başı | Avatar |
| Kenar çubuğu, bağlam seçici yanı | 24px | **Kendi** avatarın |
| Hesap ekranı başlığı | 60px | Kendi avatarın; jenerik ikonun yerine |
| Blok önizleme (`ShadPopover`) ve görev düzenleyici | — | Avatar **+ tam ad metni** |

Ana ekran planının tasarım sözleşmesi geçerli: 4'ün katları boşluk, yeni süre
yok, doygun renk yalnız avatarın kendisinde.

## 8. Karar Y4.4g — Görünen ad hesap ekranından değişir

`_ProfileHeader`'ın altına bir alan: kırpılmış ad boş olamaz, en fazla 40
karakter. Kaydetme `profiles` satırını upsert eder ve **yerel önbelleği
anında** günceller — sunucudan tazelemeyi beklemek, kullanıcıya kendi yazdığı
adın bir tur sonra görünmesi demekti.

Çevrimdışıyken düğme pasif (Y4f'nin aynı gerekçesi: bu bir `Mutation` değil,
outbox'a giremez).

---

## 9. Dilimler

Her dilim sonunda: `flutter analyze` temiz, testler yeşil, `flutter build
windows` ayakta, commit.

| # | Dilim | Kapsam | Kabul ölçütü |
|---|---|---|---|
| **Y4.4a** | Migration 04 | `profiles`, RLS, `shares_group_with`, trigger, geri dolum, `dogrulama-04-profiller.sql` | Panodan iki kez hatasız çalışır; iki hesapla okuma sınırı doğrulanır |
| **Y4.4b** | Boru hattı | `Profile` modeli, `fetchProfiles`/`updateProfile`, `profiles.cache`, `profilesProvider` | Görsel değişiklik **yok**; gateway testleri yeşil |
| **Y4.4c** | `UserAvatar` | Widget + renk paleti + baş harf mantığı | İzole widget testleri: fotoğraf, baş harf, `?`, kontrast |
| **Y4.4d** | Yüzeyler | Hafta ızgarası, aylık, listeler, kenar çubuğu | Kişisel bağlamda rozet **yok**; 390px'te taşma yok |
| **Y4.4e** | Hesap ekranı | Kendi avatarın + ad düzenleme | Ad kaydedilir, önbellek anında güncellenir, çevrimdışı pasif |
| **Y4.4f** | Detay + erişilebilirlik | Popover ve düzenleyicide tam ad; `Semantics` cümlesine ad eklenir | Ekran okuyucu cümlesi: "Toplantı, Salı 14:00 – 15:30, Ali Okan" |

**Sıralama gerekçesi:** a → b görünmez ama zorunlu; c yüzeylerden **önce**
çünkü avatarı dört ekrana dağıtıp sonra düzeltmek dört ekranı birden
düzeltmek olurdu.

---

## 10. Bitti sayılır

Kod tarafı (otomatik doğrulanan):

* [x] Kişisel bağlamda hiçbir yüzeyde rozet yok.
* [x] Grup bağlamında her iş rozet taşıyor; profil bilinmiyorsa `?`.
* [x] Fotoğraf yüklenemediğinde baş harfe düşülüyor, hata kutusu açılmıyor.
* [x] Baş harf mürekkebi her palet renginde AA eşiğini geçiyor.
* [x] Ad değişince baş harf değişiyor, **renk değişmiyor**.
* [x] Çevrimdışıyken ad kaydetme düğmesi pasif; outbox'a hiçbir şey yazılmıyor.
* [x] `flutter analyze` temiz, **435 test yeşil**, Windows sürümü derleniyor.

Yeni testler: `profile_directory_test` (16), `user_avatar_test` (10),
`owner_avatar_test` (5), `display_name_test` (7), `owner_details_test` (5).

Elle doğrulanacak (iki gerçek hesapla):

* [ ] A'nın yazdığı iş B'de A'nın adı ve fotoğrafıyla görünüyor.
* [ ] Ortak grubu olmayan üçüncü bir hesap A'nın profil satırını **okuyamıyor**.
* [ ] A adını değiştirdiğinde B tazelemeden sonra yeni adı görüyor.

---

## 11. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| `profiles` okuma politikası ad sızdırır | Orta | Okuma ortak grup şartına bağlı; tabloda e-posta **yok**, yalnız ad ve fotoğraf URL'i |
| Politika özyinelemesi (`profiles` → `group_members` → politika) | Orta | Y3c deseni: `security definer` + sabit `search_path` yardımcı |
| Fotoğraf ağdan geldiği için çevrimdışı boş kalır | Yüksek | Baş harfe düşer — kabul edilen sınır (§3) |
| Yüzlerce blokta avatar çizimi ızgarayı yavaşlatır | Düşük | Baş harf rozeti tek `Container` + `Text`; fotoğraf `ImageCache`'ten gelir |
| İki cihazdan aynı anda ad değişimi | Düşük | `updated_at` ile LWW — satır tek, hakem var |
| Trigger var olan kullanıcıları atlar | Orta | Geri dolum aynı migration'da (§2) |

---

## 11b. Kapanış notu

Altı dilim de indi. Plandan sapılan üç yer:

* **`updated_at` trigger'ı** (§2) — plan bu sütunu istemciye yazdırıyordu.
  Cihaz saatine bırakılan bir hakem, saati ileri kurulmuş bir telefonun
  yazdığı adı sonsuza dek kazanan yapardı; migration'a tek satırlık bir
  trigger girdi (04 §5b). `apply_mutations`'ın saat kayması korumasının aynı
  gerekçesi.
* **`Tooltip` ekran okuyucuda adı iki kez okuyordu** — ipucu kendi etiketini de
  ağaca koyuyor. `excludeFromSemantics` ile susturuldu; anlamı rozetin kendi
  `Semantics` düğümü taşıyor.
* **Hesap ekranı başlığında e-posta iki kez** — profil bilinmiyorken başlık
  e-postaya düşüyor ve alt satır da e-postaydı. Alt satır artık başlığın ne
  olduğuna bakıyor.

Planın öngörmediği bir iş de yol boyunca kapandı: kenar çubuğundaki hesap
kutusu "Misafir" yazan sabit bir metindi, artık gerçek adı gösteriyor.

---

## 12. Kapsam dışı

Kendi fotoğrafını yükleme (Supabase Storage), grup üye listesi ekranı,
çevrimdışı fotoğraf önbelleği, "kim ne zaman değiştirdi" geçmişi, grup içi
roller, e-posta ile davet gönderimi.
