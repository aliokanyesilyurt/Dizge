# Dizge

Haftalık planlama ve zaman yönetimi uygulaması. Takvim, rutinler, alışkanlıklar
ve bağlantılı notlar tek yerde.

**Önce çevrimdışı, sonra paylaşımlı.** Her yazma önce cihaza iner ve orada
AES-256 ile şifreli durur; ağ varsa Supabase'e senkronlanır, yoksa outbox'ta
bekler. Hesapsız da tam çalışır — giriş, veriyi cihazlar ve grup arkadaşları
arasında paylaşmak isteyince gerekir.

---

## Çalıştırma

```bash
flutter pub get
flutter run
```

Telemetri ve ortam ayarları derleme sırasında verilir (bkz. [Yapılandırma](#yapılandırma)):

```bash
flutter run --dart-define=APP_ENV=dev
```

Doğrulama:

```bash
flutter analyze   # uyarı bile çıkmamalı
flutter test      # 446 test
```

---

## Mimari

Katmanlı yapı; her katman yalnızca altındakini tanır.

```
lib/
├─ main.dart              Uygulama girişi (MaterialApp, tema, yerelleştirme)
├─ bootstrap.dart         Açılış sırası: telemetri → şifreli depo → hidrasyon → senkron
│
├─ theme.dart             AppPalette (tek renk kaynağı), inkOn, kategori paleti
│
├─ core/                  Altyapı. UI ve modelden bağımsız, saf.
│  ├─ app_config.dart     Derleme zamanı yapılandırma (--dart-define)
│  ├─ auth_service.dart   Oturum sözleşmesi (Noop + Supabase uygulaması var)
│  ├─ group_context.dart  Etkin bağlam: kişisel mi, hangi grup mu
│  ├─ profile_directory.dart  Ad/fotoğraf dizini (grup üyeleri için)
│  ├─ telemetry.dart      Telemetri sözleşmesi + PostHog + rıza kapısı
│  ├─ secure_key_store.dart  AES anahtarı (Keystore / Keychain / DPAPI)
│  ├─ connectivity.dart   Çevrimiçi/çevrimdışı durumu
│  ├─ time_grid.dart      Izgara geometrisi + çakışma yerleşim algoritması
│  ├─ day_rescue.dart     "Günü kurtar" — sığmayan işi kenara alma
│  └─ *_controller.dart   Tema kipi, ızgara yoğunluğu, enerji süzgeci, havuz
│
├─ models/                Veri modelleri. JSON serileştirme burada.
│  ├─ node.dart           Task + Note ortak sözleşmesi, renk hex çevrimi + göçü
│  ├─ task.dart           Görev, tekrar kuralı, çizim, kategori paleti
│  ├─ habit.dart          Alışkanlık, seri (streak), ısı haritası verisi
│  ├─ group.dart          Grup ve üyelik
│  └─ profile.dart        Kullanıcı adı, fotoğraf, baş harf
│
├─ data/                  Durum ve kalıcılık.
│  ├─ app_store.dart      Merkezi reaktif store + Riverpod provider'ları
│  ├─ local_store.dart    Şifreli Hive kutusu / bellek düşüşü + şema göçü
│  ├─ supabase_auth_service.dart  E-posta/parola + Google ile giriş
│  └─ sync/               Offline-first senkron
│     ├─ mutation.dart    Tek bir değişiklik kaydı (idempotency key'li)
│     ├─ outbox.dart      Kalıcı gönderim kuyruğu (daraltmalı)
│     ├─ remote_gateway.dart  Backend arayüzü (Noop + Supabase)
│     ├─ supabase_api.dart    RLS'e dayanan ince istemci sarmalayıcı
│     ├─ supabase_gateway.dart  Artımlı çekim, mezar taşları, realtime sinyali
│     ├─ first_sync.dart  İlk girişte "birleştir mi, sunucuyu al mı" kapısı
│     └─ sync_engine.dart Üstel geri çekilmeli boşaltma
│
├─ screens/               Ekranlar (sunum katmanı)
│  ├─ welcome_screen.dart / auth_gate.dart   Karşılama ve oturum kapısı
│  ├─ week_view_screen.dart + week/          Ana ekran ve parçaları
│  └─ …                   Gün, ay, yıl, notlar, alışkanlıklar, raporlar, hesap
├─ widgets/               Yeniden kullanılan bileşenler
│  ├─ week_time_grid.dart Haftalık ızgaranın kendisi
│  ├─ group_*.dart        Grup kur / davet et / katıl, bağlam değiştirici
│  └─ user_avatar.dart, owner_avatar.dart   Kim yazdı rozeti
└─ services/              Türetilmiş veri (üretkenlik raporu, bağlantı indeksi)
```

### State management — Riverpod

`AppStore` bir `ChangeNotifier`; ekranlar `ref.watch(appStoreProvider)` ile
izler. Görevlerin fiziksel deposu hâlâ `TaskRepository.all` listesidir, store
onun üzerine reaktif katman koyar.

**Kural:** her mutasyon store üzerinden yapılır. Store bir mutasyonda üç şey
yapar: dinleyicileri uyarır, değişikliği diske yazar (debounce'lu), senkron
kuyruğuna kayıt düşer. `TaskRepository`'ye doğrudan yazmak bu üçünü de atlar.

### Offline-first

```
kullanıcı → AppStore → bellek (anında UI)
                     → şifreli depo (400 ms debounce)
                     → Outbox → SyncEngine → RemoteGateway
```

Yerel yazma hiçbir zaman ağı beklemez. Bağlantı yoksa mutasyonlar outbox'ta
birikir ve uygulama kapansa bile kalıcıdır. Çakışmada **son yazan kazanır**;
her mutasyon zaman damgası ve idempotency anahtarı taşır.

---

## Veri güvenliği

| Ne | Nerede |
|---|---|
| Planlar, notlar, alışkanlıklar | Hive kutusu, **AES-256 şifreli** |
| Şifreleme anahtarı | Android Keystore / iOS Keychain / Windows DPAPI |
| Telemetri | Yalnızca sayı ve enum — içerik **asla** |

Anahtar veriyle aynı yerde durmaz: kutu dosyasını kopyalayan biri içeriği
açamaz. Hesap ekranındaki "Cihazdaki verileri sil" anahtarı yok eder
(kriptografik silme) — işlem geri alınamaz.

Güvenli kasa açılamazsa uygulama kilitlenmez: bellek deposuna düşer ve Hesap
ekranında "Şifreleme kullanılamıyor" uyarısı gösterir.

### Telemetri gizliliği

`SafeProps` serbest metni yakalayıp reddeder — 32 karakterden uzun ya da boşluk
içeren string'ler kullanıcı içeriği sayılır ve debug derlemede `assert` ile
patlar. Böylece bir görev başlığını kazara panoya göndermek mümkün değil.

Telemetri **varsayılan olarak kapalıdır** (`ConsentGate`); kullanıcı Hesap
ekranından açana kadar tek olay gitmez. Kapatılırsa geçmiş olaylar
biriktirilmez — sessiz izleme yok.

---

## Yapılandırma

Sırlar kaynak koda gömülmez; `--dart-define` ile verilir. Verilmezse ilgili
özellik sessizce kapanır ve uygulama yine çalışır.

| Anahtar | Varsayılan | Açıklama |
|---|---|---|
| `SUPABASE_URL` | *(boş)* | Boşsa backend hiç kurulmaz, uygulama yerel çalışır |
| `SUPABASE_PUBLISHABLE_KEY` | *(boş)* | Yayımlanabilir anahtar; koruma RLS'te, anahtarda değil |
| `APP_ENV` | release'de `prod`, aksi `dev` | Olaylara ortam etiketi ekler |
| `POSTHOG_API_KEY` | *(boş)* | Boşsa PostHog hiç başlatılmaz |
| `POSTHOG_HOST` | `https://eu.i.posthog.com` | Veri ikametgâhı |

Beşi tek dosyadan verilir. `env.example.json` kopyalanıp `env.json` yapılır
(git'te değil) ve derlemeye şöyle girer:

```bash
flutter run   --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json
```

Dosyayı unutmak sessiz bir kusur üretir: derleme başarılı olur, uygulama açılır,
ama hiçbir hesaba bağlanamaz. `tools/surum_cikar.ps1` tam da bu yüzden var.

---

## Sürüm çıkarma

```powershell
powershell -ExecutionPolicy Bypass -File tools\surum_cikar.ps1
```

Testleri koşar, iki hedefi de derler ve `build/surum/` altına koyar:

| Çıktı | Ne |
|---|---|
| `Dizge-<sürüm>-windows.zip` | Uygulama klasörü + `dizge_scheme.ps1` + `OKU-BENI.txt` |
| `Dizge-<sürüm>-<yapı>.apk` | Yandan yüklenebilir tek APK (ABI'ye bölünmemiş) |

`-Target windows` / `-Target android` ile tek hedef, `-SkipTests` ile testsiz.

Betiğin elle `flutter build` çalıştırmaktan farkı, **`env.json`'u unutmaması**.
Unutulduğunda derleme başarılı olur ama uygulama sunucusuz açılır: hatasız
çalışan, hiçbir hesaba bağlanamayan bir sürüm. Fark edilmesi en zor kusur bu.

### Android imzası

Yayın APK'sı `android/key.properties`ten okunan anahtarla imzalanır. Dosya
yoksa derleme durmaz, hata ayıklama anahtarına düşer ve **sesli uyarır** —
öyle bir APK kurulur ve çalışır ama gerçek anahtarlı bir sürüme sonradan
güncellenemez.

Anahtar deposu bir kez üretilir (parolayı sen seçersin):

```powershell
keytool -genkey -v -keystore $env:USERPROFILE\dizge-release.jks `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias dizge
```

Sonra `android/key.properties.example` kopyalanıp doldurulur. `.jks` dosyası
ve `key.properties` git'te değil ve olmamalı: parola sızarsa başkası senin
adına güncelleme yayımlayabilir, `.jks` kaybolursa uygulamayı bir daha
güncelleyemezsin. Yedeğini repo dışında tut.

### Windows'ta `dizge://`

Google ile giriş, tarayıcıdan uygulamaya `dizge://login-callback` ile dönüyor.
Windows bu adresi ancak registry'de bir kayıt varsa uygulamaya bağlar:

```powershell
powershell -ExecutionPolicy Bypass -File tools\dizge_scheme.ps1
```

Kayıt **çalıştırılabilir dosyanın tam yolunu** taşıyor; exe taşınırsa ya da
adı değişirse betik yeniden koşturulmalı.

---

## Backend — Supabase

Uygulama kodunun hiçbir yeri backend paketini tanımaz; her şey `RemoteGateway`
ve `AuthService` arayüzlerinden geçer. Bugün ikisinin de iki uygulaması var:
anahtar verilmediğinde `Noop*` (uygulama %100 yerel çalışır, outbox şişmez),
verildiğinde `SupabaseGateway` / `SupabaseAuthService`.

Anahtarlar `--dart-define-from-file=env.json` ile geliyor (bkz.
[Yapılandırma](#yapılandırma)); `SUPABASE_URL` ve `SUPABASE_PUBLISHABLE_KEY`
dolduğu anda `AppConfig.backendAvailable` true olur ve `SyncEngine` kendiliğinden
başlar.

Sunucu tarafı `supabase/migrations/` altında, sıra numaralı ve damgalı:

| Göç | Ne getirdi |
|---|---|
| `01_…_initial_schema` | Hibrit tablolar, RLS, `apply_mutations` |
| `02_…_realtime_publication` | Realtime yayını |
| `03_…_groups` | Gruplar, üyelik, davet; özyinelemesiz politikalar |
| `04_…_profiles` | Ad/fotoğraf, ortak-grup şartlı okuma, `updated_at` trigger'ı |

Politikaların gerçekten tuttuğu `supabase/dogrulama-*.sql` betikleriyle
sunucuda sınanıyor — RLS'i istemciden doğrulamak, kilidi kapının kendisine
sorarak denemektir.

Birkaç tasarım kararı, ayrıntısı `docs/` altındaki planlarda:

- **Çekim artımlı**, imleç sunucu saati; silme mezar taşıyla gelir.
- **Realtime bir sinyal**, veri yolu değil: "değişti" der, veriyi çekim getirir.
- **Çakışmada son yazan kazanır**, hakem `updatedAt`.
- **İlk girişte** yerelde veri varsa kapı sorar: birleştir mi, sunucuyu al mı.

Başka bir backend takmak isteyen için arayüz hâlâ yerinde duruyor:

```dart
class BaskaGateway implements RemoteGateway {
  @override
  bool get isConfigured => true;

  @override
  Future<PushResult> push(List<Mutation> mutations) async { /* … */ }

  @override
  Future<Map<String, dynamic>?> pull({DateTime? since}) async { /* … */ }

  @override
  Future<PushResult> pushSnapshot(Map<String, dynamic> snapshot) async { /* … */ }
}

// main.dart
final container = await bootstrap(gateway: BaskaGateway(client));
```

`pull`'un döndürdüğü harita `AppStore.toJson()` ile aynı şemadadır.

---

## Haftalık ızgara

Ana ekran. Google Takvim'in hafta görünümündeki modeli izler — dikeyde saatler,
yatayda günler — ama kromu atılmış, koyu ve sakin.

| Etkileşim | Sonuç |
|---|---|
| Boş alana dokun | O gün/saat için hızlı ekleme (30 dk'ya oturur) |
| Bloğa dokun | Tam editör |
| Bloğu basılı tut + sürükle | Başka gün/saate taşı (15 dk'ya oturur) |
| Bloğun alt kenarından çek | Süreyi değiştir |
| Sağa/sola kaydır | Hafta değiştir |
| Başlıktaki yoğunluk düğmesi | Sıkışık / Normal / Geniş |

Sürüklerken: hedef sütun aydınlanır, canlı saat rozeti görünür, ekran kenarına
yaklaşınca ızgara kendiliğinden kayar, her adımda dokunsal geri bildirim verilir.

**Rutin sürükleme semantiği** (bkz. `AppStore.moveTask`):
- Saat değişikliği rutinin **tüm** tekrarlarına uygulanır.
- Gün değişikliği yalnızca haftalık rutinde anlamlıdır: sürüklenen tekrarın
  haftagünü hedefe taşınır, diğerleri korunur.
- Günlük/aylık rutinde gün taşıması yok sayılır.

Çakışan işler sütunlara paylaştırılır (`core/time_grid.dart`); ayrı zaman
kümeleri birbirinin genişliğini etkilemez — akşamki dörtlü çakışma sabahki tek
işi daraltmaz.

### Izgaranın çevresi

Plan tutmadığında suçluluk üretmeyen çıkışlar, ana ekranın parçası:

| Ne | Nerede | Ne işe yarar |
|---|---|---|
| **Kenarda Bekleyenler** | Sağdaki havuz paneli | Takvimden çekilen iş silinmez, kenarda bekler; sonra geri sürüklenir |
| **Günü kurtar** | Başlık çubuğu | Sığmayan işleri havuza alır — günü "başarısız" ilan etmeden boşaltır |
| **Bugün enerjim** | Başlık çubuğu | Efor eksenine göre süzer; yetmeyecek işler soluklaşır, silinmez |
| **Günlük tikler** | Izgaranın üstündeki şerit | Alışkanlıklar takvimin içinde, ayrı ekrana gitmeden |

---

## Gruplar ve kimlik

Bir grup, takvimi paylaşan insanlar demek. Etkin bağlam kişisel ya da bir grup
(`core/group_context.dart`); kişisel bağlamda yazılan iş kimseye görünmez.

- **Kurma ve katılma**: grup kurulur, davet kodu paylaşılır, kod ile katılınır.
  Davet adrese yazılıysa başka bir hesapta reddedilir.
- **Kim yazdı**: grup bağlamındaki her iş sahibinin rozetini taşır — fotoğrafı,
  yoksa baş harfi. Kişisel bağlamda rozet **hiç** yok; tek kişilik bir takvimde
  her bloğa aynı yüzü basmak gürültüden başka bir şey değil.
- **Rozet rengi kimlikten türer, addan değil.** Biri adını değiştirince baş
  harfi değişir, rengi değişmez: ad değişti, kişi değişmedi.
- **Adlar ortak grup şartıyla okunur.** `profiles` tablosunda e-posta yok;
  yalnız ad ve fotoğraf adresi var ve onları da ancak seninle bir grubu
  paylaşan biri okuyabilir.

---

## Testler

446 test, 39 dosya. Konuya göre:

| Alan | Dosyalar |
|---|---|
| **Model ve veri** | `time_grid_test`, `data_layer_test`, `store_actions_test`, `persistence_test`, `energy_test`, `pool_test`, `day_rescue_test` |
| **Senkron** | `supabase_gateway_test`, `incremental_sync_test`, `first_sync_test`, `backend_schema_test` |
| **Oturum ve kimlik** | `auth_test`, `auth_gate_test`, `google_sign_in_test`, `display_name_test`, `profile_directory_test` |
| **Gruplar** | `group_context_test`, `group_switcher_test`, `owner_avatar_test`, `owner_details_test`, `user_avatar_test` |
| **Ana ekran** | `week_grid_test`, `week_header_bar_test`, `week_undo_test`, `daily_habit_strip_test`, `pool_panel_test`, `energy_filter_test`, `day_header_test` |
| **Tema ve erişilebilirlik** | `theme_test`, `grid_tokens_test`, `category_colors_test`, `accessibility_test` |
| **Akış ve kabuk** | `task_flow_test`, `quick_add_test`, `features_test`, `features_widget_test`, `app_shell_test`, `shell_navigation_test`, `telemetry_test` |

`helpers.dart` ortak `ProviderScope` kabuğunu kurar. Testler provider'ları
override etmediği için otomatik olarak güvenli koşar: telemetri no-op, depolama
bellekte, senkron motoru kapalı, backend `Noop`.

Renk ve kontrast testleri paleti **tek tek değil tarayarak** ölçüyor
(`for (final color in kTaskColors)`): kurala uymayan bir renk ileride
eklenirse test onu yakalar, gözden kaçmaz.

---

## Bilinen sınırlar

- **Bildirim/hatırlatma** henüz yok.
- **Kendi fotoğrafını yükleme** yok; avatar Google hesabından gelir, yoksa baş
  harf rozetine düşer. Fotoğraf ağdan geldiği için çevrimdışıyken de baş harf
  görünür.
- **Grup içi rol yok**: bir gruptaki herkes aynı yetkide. Grup üyelerini
  listeleyen bir ekran da yok.
- **Serbest renk seçici yok**; kategori rengi sekiz neon tondan seçilir. Eski
  pastel kayıtlar okunurken karşılıklarına taşınır (bkz.
  `docs/neon-kategori-renkleri-plani.md`).
- **Telefon düzeni bir varsayım, karar değil**: 390 px'te yedi sütun korunuyor,
  yalnız sayaç rozeti düşüyor. Telefon ciddiye alınacaksa ana ekran planına
  dönmek gerekir.
- Izgarada **sıkıştırarak yakınlaştırma (pinch)** yok; yoğunluk başlıktaki
  düğmeyle üç kademeli değişiyor. Sıkıştırma jesti dikey kaydırmayla aynı
  arenada yarışıyor ve güvenilir çalışmıyordu.
- Senkron çakışması **son yazan kazanır**; alan bazlı birleştirme yok.
