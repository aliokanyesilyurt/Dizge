# Program & Takvim

Haftalık planlama ve zaman yönetimi uygulaması. Takvim, rutinler, alışkanlıklar
ve bağlantılı notlar tek yerde; tamamen çevrimdışı çalışır, veriler cihazda
şifreli durur.

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
flutter test      # 84 test
```

---

## Mimari

Katmanlı yapı; her katman yalnızca altındakini tanır.

```
lib/
├─ main.dart              Uygulama girişi (MaterialApp, tema, yerelleştirme)
├─ bootstrap.dart         Açılış sırası: telemetri → şifreli depo → hidrasyon → senkron
│
├─ core/                  Altyapı. UI ve modelden bağımsız, saf.
│  ├─ app_config.dart     Derleme zamanı yapılandırma (--dart-define)
│  ├─ telemetry.dart      Telemetri sözleşmesi + PostHog + rıza kapısı
│  ├─ secure_key_store.dart  AES anahtarı (Keystore / Keychain / DPAPI)
│  ├─ connectivity.dart   Çevrimiçi/çevrimdışı durumu
│  └─ time_grid.dart      Izgara geometrisi + çakışma yerleşim algoritması
│
├─ models/                Veri modelleri. JSON serileştirme burada.
│  ├─ node.dart           Task + Note ortak sözleşmesi ([[bağlantı]] tabanı)
│  ├─ task.dart           Görev, tekrar kuralı, çizim, TaskRepository
│  └─ habit.dart          Alışkanlık, seri (streak), ısı haritası verisi
│
├─ data/                  Durum ve kalıcılık.
│  ├─ app_store.dart      Merkezi reaktif store + Riverpod provider'ları
│  ├─ local_store.dart    Şifreli Hive kutusu / bellek düşüşü
│  ├─ persistence_providers.dart
│  └─ sync/               Offline-first senkron
│     ├─ mutation.dart    Tek bir değişiklik kaydı (idempotency key'li)
│     ├─ outbox.dart      Kalıcı gönderim kuyruğu (daraltmalı)
│     ├─ remote_gateway.dart  Backend arayüzü — Supabase/Firebase buraya takılır
│     └─ sync_engine.dart Üstel geri çekilmeli boşaltma
│
├─ screens/               Ekranlar (sunum katmanı)
├─ widgets/               Yeniden kullanılan bileşenler
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
| `APP_ENV` | release'de `prod`, aksi `dev` | Olaylara ortam etiketi ekler |
| `POSTHOG_API_KEY` | *(boş)* | Boşsa PostHog hiç başlatılmaz |
| `POSTHOG_HOST` | `https://eu.i.posthog.com` | Veri ikametgâhı |

```bash
flutter build appbundle \
  --dart-define=POSTHOG_API_KEY=phc_xxx \
  --dart-define=APP_ENV=prod
```

---

## Backend bağlama (Supabase / Firebase)

Uygulama kodunun hiçbir yeri backend paketini tanımaz. Tek yapılacak
`RemoteGateway`'i uygulayıp `bootstrap()`'a geçirmek:

```dart
class SupabaseGateway implements RemoteGateway {
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
final container = await bootstrap(gateway: SupabaseGateway(client));
```

`isConfigured` true olur olmaz `SyncEngine` kendiliğinden başlar. `pull`'un
döndürdüğü harita `AppStore.toJson()` ile aynı şemadadır.

Şu an `NoopRemoteGateway` bağlı: uygulama %100 yerel çalışır, outbox şişmez.

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

---

## Testler

```
test/
├─ helpers.dart            Ortak ProviderScope kabuğu
├─ time_grid_test.dart     Geometri + çakışma algoritması (saf Dart)
├─ store_actions_test.dart Sürükleme/süre değiştirmenin modele etkisi
├─ persistence_test.dart   Şifreli depo round-trip, outbox daraltma
├─ week_grid_test.dart     Izgara jestleri (sürükle, resize, boş dokunuş)
├─ quick_add_test.dart     Hızlı ekleme akışı
├─ task_flow_test.dart     Uçtan uca görev/rutin akışları
├─ data_layer_test.dart    JSON round-trip, [[bağlantı]] indeksi
├─ features_test.dart      Alışkanlık serisi, üretkenlik raporu
├─ features_widget_test.dart  Ekran çizim testleri
└─ app_shell_test.dart     Kabuk ve gezinme
```

Testler provider'ları override etmediği için otomatik olarak güvenli koşar:
telemetri no-op, depolama bellekte, senkron motoru kapalı.

---

## Bilinen sınırlar

- **Hesap/oturum** yer tutucu; backend eklenince açılacak.
- **Bildirim/hatırlatma** henüz yok.
- Izgarada **sıkıştırarak yakınlaştırma (pinch)** yok; yoğunluk başlıktaki
  düğmeyle üç kademeli değişiyor. Sıkıştırma jesti dikey kaydırmayla aynı
  arenada yarışıyor ve güvenilir çalışmıyordu.
- Senkron çakışması **son yazan kazanır**; alan bazlı birleştirme yok.
