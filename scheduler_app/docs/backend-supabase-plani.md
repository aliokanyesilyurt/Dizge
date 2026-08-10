# Backend Planı — Supabase · Şema · Gateway · Oturum

**Durum:** onay bekliyor
**Tarih:** 10 Ağustos 2026
**Kapsam kararı (10 Ağustos):** şema + gateway + oturum açma, üçü birden.

---

## 1. Amaç

Uygulamayı "bu cihazdaki veri" olmaktan çıkarıp **hesaba bağlı** hâle getirmek.
Bugünün sonunda: kullanıcı e-posta/parola ile oturum açar, yaptığı her değişiklik
buluta gider, ikinci bir cihazda aynı takvimi bulur.

Offline-first bozulmuyor. Ağ yoksa uygulama bugünkü hızıyla çalışmaya devam
eder; `Outbox` birikir, bağlantı gelince boşalır. Bu bir davranış değişikliği
değil, hâlihazırda yazılmış motorun ilk kez gerçek bir sunucuya bağlanması.

---

## 2. Mevcut Durum (doğrulanmış)

Bu iş için mimari zaten hazırlanmış. Eksik olan tek şey, soyutlamanın arkasına
gerçek bir uygulama koymak.

| Ne | Nerede | Durum |
|---|---|---|
| Uzak sunucu arayüzü | `lib/data/sync/remote_gateway.dart` | `RemoteGateway` soyut sınıfı **hazır** — `push` / `pull` / `pushSnapshot` |
| Bağlı olan | aynı dosya, satır 63 | `NoopRemoteGateway` — her şeyi "kabul edildi" sayar |
| Kuyruk | `lib/data/sync/outbox.dart` | `enqueue` / `ack` / `markFailed` / `needsFullPush` **hazır** |
| Motor | `lib/data/sync/sync_engine.dart` | Debounce, üstel geri çekilme, ağ dinleme **hazır** |
| Mutasyon | `lib/data/sync/mutation.dart` | `id` idempotency anahtarı, LWW damgası `at` **hazır** |
| Bağlama noktası | `lib/bootstrap.dart:32` | `bootstrap({RemoteGateway? gateway})` — parametre zaten var |
| Sırlar | `lib/core/app_config.dart` | `--dart-define` deseni **hazır**, Supabase alanları eksik |
| Hesap ekranı | `lib/screens/account_screen.dart:87` | "Oturum aç" satırı var, **işlevsiz** |

**Kritik bulgu — bu planın tamamı 4 yeni dosya ve 3 dosyada değişiklik.**
Ekranların hiçbiri, `AppStore`'un tek bir eylemi, hiçbir model dosyası
`supabase` kelimesini görmeyecek. Soyutlama tam da bunun için yazılmıştı.

---

## 3. Mimari Kararlar

### B1 — Şema: hibrit. Tipli sütunlar + `payload jsonb`

En doğal görünen çözüm, `Task`'ın 22 alanını 22 sütuna açmak. **Reddediyorum.**

`Task` bu yaz üç kez alan kazandı: `inPool` (Ö1a), `isFixed`/`skippedOn` (Ö2),
`energy` (Ö4a). Tam normalize şemada bunların her biri bir SQL migrasyonu, bir
dağıtım penceresi ve eski istemcilerle bir uyumluluk sorusu demekti. Dördüncüsü
gelecek — ve o gün eski sürümdeki telefon yeni sütunu görmezden gelemez.

Yerine her satır şunu taşır:

```sql
create table public.nodes (
  user_id     uuid not null references auth.users on delete cascade,
  id          text not null,              -- istemcinin ürettiği uuid
  kind        text not null,              -- 'task' | 'note'
  payload     jsonb not null,             -- Task.toJson() / Note.toJson() aynen
  updated_at  timestamptz not null,       -- LWW hakemi
  deleted_at  timestamptz,                -- mezar taşı (bkz. B3)
  primary key (user_id, id)
);
```

Sunucunun **filtrelemesi/sıralaması gereken** alanlar dışarı çıkar (`kind`,
`updated_at`, `deleted_at`); geri kalan her şey `payload` içinde yaşar. Şemanın
tek gerçeği istemcide, `toJson`/`fromJson` çiftinde kalır — bugün de orada.

Bedeli dürüstçe: sunucu tarafında "gelecek hafta enerjisi yüksek işler" gibi bir
sorgu yazmak jsonb operatörü ister. Bugün böyle bir sorgu yok; rapor ekranı da
istemcide hesaplıyor. Gerektiğinde `payload->>'energy'` üzerine indeks tek
satır.

`habits` ve `categories` için aynı desen, ayrı tablolar (`EntityKind` ile birebir).

### B2 — Gönderim: tek RPC, `apply_mutations(jsonb)`

`push` bir listeyle gelir. Her mutasyon için ayrı bir HTTP çağrısı, 40 blokluk
bir sürükleme oturumunda 40 gidiş-dönüş demek. Bunun yerine tek bir Postgres
fonksiyonu:

```sql
create function public.apply_mutations(muts jsonb) returns jsonb
```

İçinde döngü, her mutasyon için LWW upsert:

```sql
insert into public.nodes (...) values (...)
on conflict (user_id, id) do update
  set payload = excluded.payload, updated_at = excluded.updated_at
  where public.nodes.updated_at < excluded.updated_at;  -- ← LWW hakemi
```

Dönüş: `{"accepted": [...], "rejected": [...]}` — `PushResult`'ın tam karşılığı.
Kısmi başarı bedava gelir: zehirli tek bir kayıt bütün turu düşürmez, kendi
id'siyle `rejected`'a düşer ve `Outbox.markFailed` onu 8 denemeden sonra atar.

**Neden `at` damgası hakem, sunucu saati değil:** offline yapılan bir düzenleme
saatler sonra gönderilir. Sunucu saati kullansaydık, geç gelen eski değişiklik
yeni olanı ezerdi. `Mutation.at` cihaz saatidir; cihaz saatinin yanlış olması
riski (bkz. §7) bu ezilmeden daha küçük bir kötülük.

### B3 — Silme: mezar taşı zorunlu

Bugün `AppStore.loadJson` her şeyi silip yeniden kuruyor — tam çekimde bu
yeterli. Ama artımlı çekim (`pull(since:)`) mezar taşı olmadan **silmeyi
taşıyamaz**: "bu kayıt gelmedi" ile "bu kayıt silindi" ayırt edilemez.

Bu yüzden `delete` mutasyonu satırı silmez; `deleted_at` damgalar ve `payload`'ı
boşaltır (`'{}'::jsonb` — silinen bir işin içeriğini sunucuda tutmanın gerekçesi
yok). Temizlik ayrı bir işin görevi: 90 günden eski mezar taşları düşer.

### B4 — Çekim: v1 yalnız **tam** çekim, oturum açılışında

`RemoteGateway.pull({since})` imzası artımlı çekimi vaat ediyor. Bugün onu
**uygulamıyorum** ve nedenini yazıyorum: artımlı çekim, gelen kayıtları yerel
duruma **birleştirmeyi** gerektirir. `AppStore`'un böyle bir yolu yok —
`loadJson` yıkıp yeniden kuruyor. Birleştirme yazmak, her koleksiyon için ayrı
LWW kararı ve `TaskRepository.all` üzerinde kimlik bazlı arama demek; kendi
başına bir dilim.

v1 sözleşmesi bu yüzden şöyle:

* **Oturum açıldığında** tam çekim → `loadJson` (yerel durumu değiştirir).
* **Sonrasında** yalnız gönderim. İkinci cihazın değişikliği, uygulamayı
  kapatıp açana kadar gelmez.

Bu, tek kullanıcı + bir buçuk cihaz için dürüst bir v1. Artımlı çekim ve gerçek
zamanlı akış (Supabase Realtime) sonraki dilim — ve o dilim `pull(since:)`
imzası zaten durduğu için gateway'e dokunmadan yazılabilir.

**Kritik ayrıntı:** oturum açan cihazda zaten yerel veri varsa tam çekim onu
ezer. Bu yüzden ilk oturumda kullanıcıya sorulur (bkz. §5 / A4).

### B5 — Güvenlik: RLS her tabloda, istisnasız

Her tabloda `user_id = auth.uid()` üzerine tek politika. Anon anahtar istemcide
duruyor — güvenliği sağlayan o değil, RLS. Politika yazılmamış tek bir tablo,
anon anahtarı olan herkese bütün kullanıcıların takvimini açar.

`apply_mutations` fonksiyonu **`security invoker`** olarak tanımlanır (varsayılan
`definer` değil): fonksiyon çağıranın hakkıyla çalışır, RLS içeride de geçerlidir.
`definer` seçseydik fonksiyon RLS'i baypas ederdi ve `user_id`'yi doğru yazmak
tek başına fonksiyonun dikkatine kalırdı.

### B6 — Oturum: e-posta + parola

Magic link ve OAuth, masaüstünde (Windows) derin bağlantı kaydı ister — ayrı bir
platform işi. E-posta/parola hiçbir platform yapılandırması istemez ve Supabase
Auth oturumu kendi yeniler.

Oturum jetonu `flutter_secure_storage`'da tutulur — Hive kutusunun yanında değil,
platform kasasında. `SecureKeyStore` deseni zaten kurulu.

### B7 — Şemaya sığmayan iki alan (bugün kapatılıyor)

Kod okumasında iki gerçek boşluk çıktı:

1. **`Habit.updatedAt` yok.** LWW hakemi olmadan iki cihazdaki alışkanlık
   değişikliği rastgele kazanır. `Task` ve `Note`'ta bu alan var; `Habit`'e
   ekleniyor, `kSchemaVersion` 2 → 3 ve migrasyonda eski kayıtlara `createdAt`
   yazılıyor.
2. **`TaskCategory`'nin kimliği yok** — adı kimliği. Bugün **bu böyle kalıyor**:
   kategoriye kimlik vermek, adı değişince bütün işlerin `categoryName` alanını
   göçürmek demek — ayrı bir dilim, bugünün işi değil.

   *Düzeltme (S2 sırasında):* bu maddenin ilk hâli "`AppStore` kategori için
   mutasyon üretmiyor" diyordu. **Yanlış.** `AppStore.addCategory`
   `EntityKind.category` mutasyonu kaydediyor; yalnız *silme* ve *yeniden
   adlandırma* yolu yok. Şemadaki kategori desteği bu yüzden ileriye dönük bir
   nezaket değil, gereklilik.

---

## 4. Dilimler

Her dilim tek başına çalışır ve tek başına commit edilir.

### S1 — Şema (SQL, Dart yok)

`supabase/schema.sql` dosyası repoya girer; Supabase SQL editöründe çalıştırılır.

* `nodes`, `habits`, `categories` tabloları (B1)
* Her birinde RLS + `user_id = auth.uid()` politikası (B5)
* `apply_mutations(jsonb)` fonksiyonu, `security invoker` (B2)
* `(user_id, updated_at)` üzerinde indeks — artımlı çekim için hazır dursun
* Mezar taşı sütunu ve 90 günlük temizlik fonksiyonu (B3)

**Bitti sayılır:** SQL editöründe hatasız çalışır; iki farklı test kullanıcısıyla
birbirinin satırını okuyamadığı elle doğrulanır.

### S2 — `Habit.updatedAt` + şema sürümü 3

* `Habit`'e `updatedAt`, `toJson`/`fromJson`, `copyWith` yolu
* `AppConfig.kSchemaVersion` 3
* `LocalStore` migrasyonuna bir adım: alan yoksa `createdAt` yazılır
* `AppStore.updateHabit` damgayı tazeler

**Bitti sayılır:** `persistence_test.dart`'a "sürüm 2 kaydı sürüm 3 olarak
okunur" testi eklenir ve geçer.

### S3 — `AppConfig` + `SupabaseGateway`

* `AppConfig`'e `supabaseUrl`, `supabaseAnonKey`, `backendAvailable`
* `pubspec.yaml`'a `supabase_flutter`
* `lib/data/sync/supabase_gateway.dart` — `RemoteGateway` uygulaması:
  * `isConfigured` → anahtar var **ve** oturum açık
  * `push` → `apply_mutations` RPC'si, `PushResult`'a çevrim
  * `pull` → üç tablodan tam okuma, `loadJson` şemasına derleme
  * `pushSnapshot` → tam görüntüyü mutasyon listesine çevirip aynı RPC

**Bitti sayılır:** sahte bir HTTP katmanıyla birim testler geçer — kabul/ret
ayrımı, kalıcı hata (`fatal`) yolu, boş kuyruk.

### S4 — Oturum: `AuthService` + hesap ekranı

* `lib/core/auth_service.dart` — kaydol / giriş / çıkış / oturum akışı
* `account_screen.dart`'taki işlevsiz "Oturum aç" satırı gerçek bir sheet'e bağlanır
* Oturum durumu ekranda görünür: e-posta, son senkron, `SyncState` rozeti
* Çıkışta yerel veriye **dokunulmaz** (cihazdaki takvim kullanıcınındır);
  yalnız jeton silinir ve gateway `isConfigured == false`'a döner

**Bitti sayılır:** widget testi — oturum açılmamışken "Oturum aç", açıkken
e-posta ve "Çıkış" görünür.

### S5 — Bağlama + ilk senkron kapısı

* `main.dart` → `bootstrap(gateway: SupabaseGateway(...))`
* Oturum açıldığında tam çekim; **yerel veri varsa kullanıcıya sorulur** (A4)
* `SyncEngine` zaten `isConfigured`'a bakıyor — ek iş yok

**Bitti sayılır:** gerçek Supabase projesine karşı elle uçtan uca tur:
oturum aç → iş ekle → uygulamayı kapat → başka cihazda/yeni profilde aç → iş orada.

---

## 5. Açık Kararlar

**A4 — Oturum açılırken cihazda zaten veri varsa ne olur?**

Üç yol var:

1. **Sunucu kazanır** — yerel veri gider. Basit, ama ilk kullanıcı deneyimi
   felaket: aylardır cihazda duran takvim, hesap açar açmaz siliniyor.
2. **Cihaz kazanır** — yerel durum sunucuya tam görüntü olarak basılır.
   `pushSnapshot` zaten bunun için var.
3. **Sor** — "Bu cihazdaki 84 işi hesabına yükleyelim mi, yoksa hesaptakini mi
   indirelim?"

**Önerim: 2 + 3'ün bileşimi.** Sunucu boşsa sessizce (2) — soru sormanın anlamı
yok. Sunucuda da veri varsa (3) sorulur. Bu, S5'te bir diyalog demek.

Aksini söylemezsen bunu uygulayacağım.

---

## 6. Kapsam Dışı

Artımlı çekim (B4), Realtime akış, çakışma birleştirme, kategori kimliği (B7.2),
paylaşılan takvim, ekip/çoklu kullanıcı, sunucu tarafı bildirim, dosya/çizim
yükleme (`Sketch` bugün `payload` içinde JSON olarak gidiyor — büyürse ayrı
depolama işi), telemetri rızasının sunucudan okunması.

---

## 7. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| Cihaz saati yanlış → LWW yanlış hakem verir | Düşük | Sunucu, `updated_at`'i "şimdi + 5dk"tan ileriyse reddeder; `rejected`'a düşer |
| `Sketch` payload'ı satırı şişirir | Orta | Çizim strok listesi; 1 MB üstü satır uyarısı için indeks yerine kontrol; gerekirse ayrı depolama dilimi |
| Anon anahtar repoya kaçar | Düşük | `--dart-define` deseni zaten kurulu; `schema.sql` dışında hiçbir anahtar dosyaya yazılmaz |
| RLS politikası unutulan bir tablo | **Yüksek etki** | S1'in bitti-sayılır ölçütü iki kullanıcıyla elle doğrulama; testi atlamıyoruz |
| Tam çekim yerel veriyi ezer | Orta | A4 kararı |
| `supabase_flutter` Windows'ta sorun çıkarır | Düşük | Paket saf Dart HTTP + WebSocket; masaüstü destekli. S3 sonunda Windows derlemesi doğrulanır |

---

## 8. Bugünün Sırası

S1 → S2 → S3 → S4 → S5. S1 ve S2 birbirinden bağımsız; S2 istersen tema işiyle
paralel gidebilir.
