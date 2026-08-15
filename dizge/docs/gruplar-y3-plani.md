# Y3 Planı — Grup Şeması, Üyelik ve RLS

**Durum:** uygulandı (12 Ağustos) — migration sunucuda **çalıştırılmayı
bekliyor**, üç kullanıcılı doğrulama (§11) yapılmadı.
**Üst plan:** `gruplar-plani.md` §4 — oradaki taslak kararlar burada gözden
geçirildi ve **ikisi değişti** (Y3a, Y3g).
**Önkoşul:** Y1 (artımlı çekim) ve Y2 (Realtime sinyali) bitti ve commit'lendi.

---

## 0. Başlamadan önce: uygulanmamış bir migration var

`supabase/migrations/20260811180000_realtime_publication.sql` panoya üretildi
ama Supabase panelinde çalıştırıldığı doğrulanmadı. Çalıştırılmadıysa Y2'nin
kodu derlenir, abone olur, **hata da vermez** — sadece hiç olay gelmez.

Y3'e geçmeden bu doğrulanmalı; Y3'ün kendi migration'ı da aynı yoldan
gidecek (§8).

---

## 1. Bu dilim ne, ne değil

Y3 tek başına kullanıcıya hiçbir şey göstermez. Amacı: **bir satırın birden
fazla kişiye ait olabildiği bir dünyaya geçmek**, arayüz olmadan. Y4 bunun
üstüne bağlam seçiciyi ve davet ekranını koyar.

Bu yüzden Y3'ün "bitti" ölçüsü ekran değil, **üç kullanıcıyla elle yapılan bir
güvenlik doğrulaması** (§7).

---

## 2. Karar Y3a — Birincil anahtar `user_id`'den çıkar *(taslaktan sapma)*

Üst plandaki taslak "`nodes`/`habits` tablolarına `group_id` sütunu ekle"
diyordu. Bu tek başına **bozuk**: bugünkü birincil anahtar `(user_id, id)`.

Sonuç şu olurdu: Ali'nin oluşturduğu grup görevini Veli düzenlerse,
`apply_mutations` satırı `user_id = auth.uid()` ile yazdığı için **aynı `id`'ye
sahip ikinci bir satır** açılır. İki satır sonsuza dek yan yana yaşar; Ali
silince Veli'nin kopyası kalır, artımlı çekim ikisini de gönderir ve istemci
`id`'ye göre anahtarladığı için hangisinin kazandığı çekim sırasına kalır.

Bu yüzden birincil anahtar **yalnız `id`** olur. İstemci `id`'leri zaten uuid
üretiyor; çakışma pratikte imkânsız ve zaten bugün de istemci deposu `id`'yi
tek anahtar sayıyor. Şema nihayet istemciyle aynı şeyi söyler.

`categories` dışarıda kalır — anahtarı `(user_id, name)` ve kimliği adı (B7.2);
bkz. Y3g.

## 3. Karar Y3b — `user_id` gider, yerine `owner_id` + boş bırakılabilir `group_id`

* `owner_id uuid not null` — satırı **oluşturan** kişi. Sahiplik değil, köken:
  Y4'teki "kimin işi" işareti bunu okuyacak.
* `group_id uuid null` — null ise kişisel satır, doluysa grubun.

Sütunu yeniden adlandırmak kozmetik değil: `user_id` adı "bu satır bu
kullanıcıya ait, başkası göremez" sözü veriyordu ve Y3'ten sonra bu söz yalan.
Adı bırakmak, altı ay sonra birinin `user_id = auth.uid()` diye bir sorgu daha
yazmasını davet etmek olurdu.

Taşıma sırasında mevcut satırların hepsi `group_id = null` alır: bugünkü
davranış birebir korunur.

## 4. Karar Y3c — RLS: alt sorgu değil, `security definer` yardımcı

Taslaktaki politika şuydu:

```sql
user_id = auth.uid() or group_id in (
  select group_id from group_members where user_id = auth.uid()
)
```

İki ayrı sorunu var:

**Performans.** Alt sorgu, satır başına yeniden değerlendirilebilir. S1'de
`(select auth.uid())` sarmalının neden konduğu aynı sebep: alt sorgu olarak
yazılınca planlayıcı onu bir kez çalışan InitPlan'a çeviriyor.

**Özyineleme.** `group_members` tablosunun kendisi de RLS'li olacak ve onun
politikası da "üyesi olduğum grupların satırlarını görebilirim" diyecek —
yani `group_members`'ı sorgulayacak. Postgres bunu `infinite recursion
detected in policy` ile reddeder. Bu, Supabase'de üyelik tablosu yazan herkesin
düştüğü çukur.

İkisinin de tek çözümü var: üyeliği **`security definer`** bir fonksiyona almak.
Fonksiyon RLS'i baypas ederek `group_members`'ı okur (özyineleme kırılır),
`stable` işaretlenir ve politikada `(select ...)` ile sarılır (tek kez çalışır).

```sql
create or replace function public.my_group_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public          -- definer fonksiyonda şart
as $$ select group_id from group_members where user_id = auth.uid() $$;
```

Politika:

```sql
using (
  owner_id = (select auth.uid())
  or group_id in (select public.my_group_ids())
)
```

`security definer` yazmak, güvenliği bir fonksiyonun içine taşımak demek —
`search_path` sabitlenmezse çağıran kendi şemasını araya sokabilir. Bu yüzden
`set search_path` pazarlığa açık değil.

**`with check` ayrı yazılır.** `using` yalnız okumayı süzer; S1'de bu ders
alınmıştı. Yazma tarafında ek bir şart var: kullanıcı bir satıra `group_id`
yazarken o grubun **üyesi olmalı**, yoksa herkes kendi görevini başkasının
grubuna atabilir.

## 5. Karar Y3d — `apply_mutations` da yetkiyi denetler

RLS `with check` yazmayı durdurur, ama `apply_mutations` bir
`security definer` fonksiyon değilse bile mutasyonu **kendi** yazdığı için
niyeti orada da açık etmek gerekir: gelen mutasyonda `group_id` varsa üyelik
kontrol edilir, yoksa o mutasyon **sessizce atlanmaz, hata verir**.

Sessiz atlama, istemcinin gönderdiğini sandığı değişikliğin kaybolması demek —
kuyruk boşalır, veri gitmez. Y1'in imleç kuralıyla aynı mantık: yarım kalan bir
işi başarılı saymayacağız.

## 6. Karar Y3e — Gruba katılınca imleç sıfırlanır *(gözden kaçması en kolay hata)*

`SyncEngine` tek bir imleç tutuyor: `LocalStore`'da `sync_cursor`, son görülen
`server_at`. Artımlı çekim "bu damgadan **sonra** değişenleri" istiyor
(`fetchSince`, kesin büyük).

Veli bir gruba bugün katılırsa, grubun geçen hafta yazılmış satırlarının
`server_at`'i Veli'nin imlecinden **eskidir**. RLS artık o satırları
göstermeye izin verir ama artımlı çekim onları hiç sormaz: Veli grubu boş
görür, üstelik hata da almaz.

Karar: **üyelik değişimi imleci siler.** Bir sonraki tur `since: null` ile tam
çekim yapar. Üyelik değişimi seyrek bir olay; tam çekimin maliyeti burada
doğru fiyat.

Tetikleyici Y4'te üyelik akışına bağlanacak; Y3'te `SyncEngine`'e imleci
sıfırlayan bir giriş noktası açmak yeterli.

## 7. Karar Y3f — Davet: tek kullanımlık token + `security definer` kabul

`group_invites(token, group_id, email, expires_at, accepted_at)`.

Davet edilen kişi henüz üye değil — yani RLS'e göre ne grubu ne daveti
görebilir. Bu yüzden kabul, doğrudan tabloya yazma olamaz:
`accept_invite(token)` adında `security definer` bir RPC token'ı doğrular,
süresini ve daha önce kullanılıp kullanılmadığını kontrol eder, üyelik satırını
açar ve daveti işaretler — hepsi tek işlemde.

Token'ın kendisi tahmin edilebilir olmamalı: `gen_random_bytes` tabanlı,
veritabanında üretilen bir değer. İstemcinin ürettiği bir uuid burada yeterli
değil, çünkü token tek başına bir gruba giriş anahtarı.

E-posta gönderimi Y3'ün kapsamı dışında: Y3 token'ı üretir ve kabul eder,
Y4 onu bir bağlantı hâline getirir.

## 8. Karar Y3g — Kategoriler grup dışında kalır *(taslaktan sapma)*

Taslak kategorilere değinmiyordu. Karar: **girmiyorlar.** Kimlikleri adları
(B7.2) ve liste bütün olarak değiştiriliyor (`replace_categories`). Paylaşılan
bir kategori listesinde iki üyenin aynı anda sıralama değiştirmesi, listeyi
bütün olarak ezen bir çağrıda LWW'ye düşer — sessiz veri kaybı.

Grup görevi, üyenin **kendi** kategorisiyle görünür. Ortak kategori listesi
ayrı bir tasarım işi ve Y3'ün konusu değil.

---

## 9. Migration ve indeksler

Tek dosya: `supabase/migrations/20260812090000_groups.sql`, idempotent —
panodan iki kez çalıştırılabilmeli (Realtime migration'ında olduğu gibi).

İçeriği sırasıyla:

1. `groups`, `group_members`, `group_invites` tabloları
2. `nodes`/`habits`: `user_id` → `owner_id` yeniden adlandırma, `group_id`
   sütunu, birincil anahtarın `id`'ye taşınması
3. `my_group_ids()` ve `is_group_member(uuid)` yardımcıları
4. Politikaların yeniden yazılması (eski `*_owner` politikaları düşürülür)
5. `apply_mutations` ve `replace_categories` güncellemesi
6. İndeksler:
   * `group_members (user_id, group_id)` — yardımcı fonksiyonun sıcak yolu
   * `nodes (group_id, server_at desc) where group_id is not null`
   * mevcut `(user_id, ...)` indeksleri `owner_id`'ye taşınır
7. Yeni tablolara RLS + Realtime yayını **hayır** (§10)

## 10. Realtime

`groups`/`group_members` yayına **eklenmez**. Y2a'nın kuralı: Realtime bir
sinyal. Üyelik değişimi zaten tam çekimi tetikliyor (Y3e) ve saniyelik
gecikmesi olan bir olay değil.

`nodes`/`habits` zaten yayında. Realtime politikayı ayrıca değerlendirdiği için
grup satırlarının olayları üyelere **kendiliğinden** akar — yeni bir iş yok.
Bu, §4'teki politikanın doğru yazıldığının ayrıca doğrulanması gereken bir
sonucu: yanlış politika burada da sızdırır.

---

## 11. Bitti sayılır

Otomatik:

* `backend_schema_test.dart` yeni üç tablonun da RLS'li olduğunu bekçiler
  (politikasız tablo = herkese açık tablo).
* Birleştirme testleri: aynı `id`'nin iki kez yazılmadığı, grup satırının
  istemcide kişisel satırla aynı yoldan işlendiği.

Elle — **S1'deki iki kullanıcılı doğrulamanın üç kullanıcılı tekrarı**:

| # | Kim | Beklenen |
|---|---|---|
| 1 | Ali grup kurar, Veli'yi davet eder | Veli daveti kabul edince üye |
| 2 | Ali grup görevi yazar | Veli görür |
| 3 | **Ayşe (üye değil)** aynı sorguyu atar | **hiçbir satır** |
| 4 | Veli grup görevini düzenler | Ali görür, satır **tek** kalır |
| 5 | Ayşe kendi görevine Ali'nin `group_id`'sini yazmayı dener | reddedilir |
| 6 | Veli gruptan çıkar | grup satırları Veli'de kaybolur |

3 ve 5 geçmeden bu dilim bitmiş sayılmaz.

---

## 11b. Uygulamada verilen üç ek karar

Plan yazılırken görünmeyen, kod yazılırken çıkan kararlar:

**Davet etme hakkı yalnız grup sahibinde.** Üst plan grup içi rolleri kapsam
dışı bırakıyor ("herkes her şeyi düzenler") ve bu **içerik** için doğru. Davet
içerik değil, grubun sınırını genişleten bir işlem: her üyenin yabancı
çağırabildiği bir grup, sahibinin haberi olmadan büyür. `role` sütunu zaten
`owner|member` ayrımını taşıyordu; ilk gerçek kullanımı bu oldu.

**Her mutasyonun yazımı kendi hata kalkanına alındı.** Anahtar artık genel
olduğu için (Y3a) bir upsert, RLS'in göstermediği bir satıra çarpabilir —
örneğin başkasının kişisel satırıyla aynı `id`. O hata eskiden bütün turu
düşürürdü. Kısmi başarı zaten `apply_mutations`'ın sözleşmesiydi (B2); kalkan
onu grup dünyasında da geçerli kılıyor.

**Grup kurmak da bir RPC.** `create_group` iki tabloya birden yazıyor (grup +
sahibin üyelik satırı) ve arada kalırsa sahipsiz bir grup bırakırdı. Politikayla
ifade edilemeyeceği için `accept_invite` gibi `security definer`.

---

## 12. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| Politika üye olmayana takvim açar | **Yüksek etki** | §11 adım 3 ve 5, üç ayrı hesapla |
| `group_members` politikası özyinelemeye girer | Yüksek | Y3c: `security definer` yardımcı |
| Alt sorgu satır başına çalışır, sorgu çöker | Orta | Y3c: `stable` + `(select ...)` sarmalı |
| Katılan üye grubu boş görür | **Yüksek** (sessiz) | Y3e: üyelik değişimi imleci siler |
| Anahtar taşıması mevcut veriyi bozar | Orta | Taşıma öncesi yedek; migration idempotent |
| `security definer` fonksiyon şema kaçırma | Orta | `set search_path = public` |

---

## 13. Kapsam dışı

Grup içi rol/izin ayrıntısı (herkes her şeyi düzenler), ortak kategori listesi
(Y3g), e-posta gönderimi (Y4), grup sohbeti, bildirimler, grup silme ve
üyelikten atma, alan bazlı çakışma birleştirme.
