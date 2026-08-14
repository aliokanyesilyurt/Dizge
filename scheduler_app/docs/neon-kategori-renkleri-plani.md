# Neon Kategori Renkleri Planı — Yeni Palet + Eski Renklerin Göçü

`neon-tema-plani.md` §T4'ün erteleyip "bugünden sonra sırada" diye bıraktığı
iş. Tema neonlaştı, kategori renkleri Material'ın pastellerinde kaldı:
`#FF6090`, `#4FC3F7`, `#81C784`… Camgöbeği `#22D3EE` ve magenta `#F0ABFC`'nin
yanında bunlar sönük duruyor.

---

## 1. Neden liste tek başına değiştirilemez

`kTaskColors` yalnız **seçicinin** listesi. Bir iş kendi rengini `colorHex`
olarak saklıyor (`task.dart:465`), alışkanlık da (`habit.dart:136`),
kategoriler de (`app_store.dart:583`). Listeyi neonlaştırmak diskte yazılı
hiçbir rengi değiştirmez:

* eski işler pastel kalır,
* seçiciden gelen yeniler neon olur,
* takvim yarı pastel yarı neon olur.

Yarım renkli bir takvim, tutarlı-sönük bir takvimden kötüdür. Bu yüzden iş
**iki parçadır**: yeni palet + eski değerlerin yeni karşılığına eşlenmesi.

Eşlemenin **tam** olabildiği bu noktada doğrulandı: uygulamada serbest renk
seçici yok. `task_editor_sheet.dart:856` ve `habits_screen.dart:340`
yalnızca `kTaskColors`'ı geziyor, `AppData.categories`'in yedi hazır kategorisi
de aynı sekizlinin yedisini kullanıyor. Yani diskte duran her renk, sekiz
pastelden biridir — eşleme kalıntı bırakmaz.

---

## 2. Karar N5a — Göç **okuma** anında olur, yazma anında değil

Üç seçenek vardı:

| # | Nerede | Sorun |
|---|---|---|
| A | `migrateSnapshot` v3→v4, yerel anlık görüntüyü bir kez yeniden yaz | Sunucudaki satırlar pastel kalır; sonraki artımlı çekim yereli geri pastele çevirir. Göç kendi kendini bozar. |
| B | Göç + mutasyon kuyruğuna yaz (sunucuya it) | Grup işleri **başkasının**. Bir cihazın bütün üyelerin iş renklerini yeniden yazması hem küstah hem outbox tavanını (§`kMaxOutbox`) tek hamlede doldurur. |
| C | `colorFromHex` içinde okurken eşle | Round-trip saflığı kırılır (aşağıda). |

**C seçildi.** `colorFromHex` (`node.dart:135`) bu uygulamadaki her kalıcı
rengin tek geçididir: iş, alışkanlık, kategori — yerelden de gelse sunucudan da
gelse oradan geçer. Tek nokta, unutulması imkânsız. A'nın aksine sunucudan
gelen eski satır da düzelir; B'nin aksine kimsenin verisine dokunulmaz.

Bedeli açıkça yazılıyor: **`fromJson(toJson(x)) == x` artık eski renkler için
geçerli değil.** Pastel yazılır, neon okunur. Bu kusur değil, işin ta kendisi —
ama testlerde yankısı var (§5).

Sunucudaki satırlar pastel kalmaya devam eder ve her istemci okurken çevirir.
Bir satır bir sonraki düzenlemesinde neon olarak yazılır. Kalıcı bir "karışık
sunucu" durumu doğar; görüntü her istemcide doğru olduğu için kabul ediliyor.
Eski sürüm istemci sahada yok (dağıtım: Windows zip + yandan yüklenen APK).

### `kSchemaVersion` artmıyor

Yazılan **şekil** değişmiyor, yalnız değerler. `AppConfig.kSchemaVersion`'ın
belgesi sürümü "model alanı ekleyip çıkardıkça" artırmayı söylüyor; adımsız bir
sürüm artışı `migrateSnapshot`'a boş bir dal eklemek olurdu. Yerel dosya zaten
ilk tam yazımda (anlık görüntü tümüyle üzerine yazılır) neonlaşır.

---

## 3. Karar N5b — Yeni sekizli ve ölçüleri

Seçim ölçütü üç madde: (1) koyu temada zeminden ayrışsın, (2) `inkOn` ile
üstüne konan mürekkep AA'yı geçsin, (3) `readableOn` yazıyı gövde mürekkebine
çekerken az adımda dursun — çok adım demek, kategori renginin yazıda
tanınmaması demek.

| Eski | Yeni | Şerit/koyu zemin | `inkOn` AA | Yazı adımı (koyu/açık) |
|---|---|---|---|---|
| `#FF6090` pembe | **`#FF3D8B`** | 5.82 | 5.42 | 0/6 |
| `#4FC3F7` mavi | **`#38BDF8`** | 9.07 | 8.44 | 0/9 |
| `#81C784` yeşil | **`#34E39B`** | 11.66 | 10.86 | 0/10 |
| `#FFB74D` turuncu | **`#FF9E3D`** | 9.44 | 8.79 | 0/9 |
| `#BA68C8` mor | **`#A78BFA`** | 7.14 | 6.64 | 0/7 |
| `#4DD0E1` turkuaz | **`#00E5C7`** | 12.05 | 11.22 | 0/10 |
| `#FFF176` sarı | **`#F2E14C`** | 14.47 | 13.48 | 0/11 |
| `#E57373` kırmızı | **`#FF5C5C`** | 6.42 | 5.97 | 0/7 |

Sekizinin de şerit/koyu oranı 3:1 eşiğinin (WCAG 1.4.11, metin dışı içerik)
çok üstünde ve `inkOn` hepsinde koyu mürekkebi seçip 4.5:1'i geçiyor. Koyu
temada yazı **hiç** kaydırılmıyor (0 adım): kategori rengi blokta olduğu gibi
okunuyor.

Hue seçiminde tema jetonlarından **kaçınıldı**: `accent` `#22D3EE`, `warning`
`#FDE047`, `danger` `#FF4D6D`, `nowLine` `#FF2BD6`. Kategori renkleri bunlarla
birebir aynı olsaydı, "şu an" çizgisiyle bir iş bloğu ya da tehlike rengiyle
kırmızı kategori aynı sinyali taşırdı. Komşu tonlar seçildi, aynıları değil.

### Açık temada şerit zayıf — bilinen, gerilemiş değil

Açık temada sarı şeridin beyaz zemine oranı 1.34 (eskisi 1.16). Bütün palette
açık tema oranı 1.6–3.3 arası. Şerit tek ipucu değil — blok yazısı da
`readableOn` ile aynı renkten türüyor ve orada AA garantili. Ölçülüp
kayda geçiyor, kapıya bağlanmıyor.

---

## 4. Karar N5c — `kUnknownCategoryColor` da neonlaşır, ama sabit kalır

`#529CCA` (`theme.dart:600`) rengi bilinmeyen kategorinin grafikteki rengi.
`neon-tema-plani` §T5 bunu `p.accent`'e bağlamayı öngörmüştü; kod bunun yerine
adlandırılmış bir sabitte bıraktı ve gerekçesini yazdı: rapor hizmeti
`BuildContext` görmüyor, görmemeli. **Bu gerekçe hâlâ geçerli, sabit kalıyor.**
Yalnız tonu neonlaşıyor: `#5AA9FF` (şerit/koyu 7.91, `inkOn` AA 7.37) — mavi
kategoriden (`#38BDF8`) ayırt edilebilir kalsın diye bir tık moru.

`#529CCA` de eşleme tablosuna giriyor: testlerde ve eski kayıtlarda geçiyor.

---

## 5. Testlerdeki yankı

Yaklaşık 20 test, nesne kurarken gelişigüzel bir pastel yazıyor
(`Color(0xFF4FC3F7)`, `Color(0xFF81C784)`, `Color(0xFF529CCA)`) ve kimi
`persistence_test` / `data_layer_test` / `first_sync_test` kaydı gidip geri
okuyup **eşitlik** bekliyor. §2'deki kararla bunlar kırmızıya döner.

Bu testlerin hiçbiri rengin *kendisiyle* ilgilenmiyor — bir renge ihtiyaçları
var, o kadar. Sabitler yeni karşılıklarına süpürülüyor. Süpürme mekanik ama
**körlemesine değil**: her dosyada rengin iddianın parçası olup olmadığına
bakılacak.

Yeni testler (`theme_test.dart` + yeni `category_colors_test.dart`):

* Sekiz rengin her biri koyu zeminde 3:1'i geçiyor.
* `inkOn(renk)` her renkte 4.5:1'i geçiyor.
* Eski sekiz hex okunduğunda yeni karşılığı dönüyor.
* Yeni hex okunduğunda **kendisi** dönüyor (eşleme etkisiz eleman).
* Palette olmayan bir hex (ör. `#123456`) dokunulmadan geçiyor.
* `null`/bozuk hex hâlâ yedeğe düşüyor, yedek de neon.
* Eşleme tablosunun anahtarları ile `kTaskColors` aynı boyda ve birebir.

---

## 6. Dilimler

| # | İş | Dosyalar |
|---|---|---|
| **N5a** | Yeni sekizli + hazır kategoriler + `kUnknownCategoryColor` | `models/task.dart`, `theme.dart` |
| **N5b** | Eski→yeni eşleme `colorFromHex` içinde + göç testleri | `models/node.dart`, `test/category_colors_test.dart` |
| **N5c** | Test sabitlerinin süpürülmesi | `test/*.dart` (~20 nokta) |
| **N5d** | Belgeler: T4 kapanışı, `ana-ekran-plani` §14 düzeltmesi | `docs/*.md` |

N5a tek başına yeşil kalır (mevcut testler `kTaskColors`'ı geziyor, sabit
beklemiyor). N5b indiğinde N5c aynı commit'te olmak zorunda — arada testler
kırmızı durur.

---

## 7. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| Eşleme, kullanıcının bilinçli seçtiği bir rengi değiştirir | Düşük | Serbest renk seçici yok; diskteki her değer sekiz pastelden biri (§1) |
| Round-trip testleri sessizce yanlış yöne süpürülür | Orta | Süpürme dosya dosya okunarak; rengin iddianın parçası olduğu yerlerde eşleme testi ayrıca var |
| Sunucuda pastel, istemcide neon — karışık durum | Yüksek (kabul) | Her istemci okurken çeviriyor; görüntü tutarlı, satır bir sonraki düzenlemede neonlaşır |
| Neon renkler açık temada göz yorar | Orta | Gövde `%13` opaklıkla harmanlanıyor, ham renk yalnız ince şeritte |
| Sekiz neon hue renk körlüğünde birbirine yaklaşır | Orta | Eskisiyle aynı sekiz hue ailesi korundu — gerileme yok, ama iyileşme de yok; ayrı iş |

---

## 8. Kapsam dışı

Avatar rozet merdiveni (`theme.dart:618`, Y4.4c) — kimlik renkleri, kişinin
rozet rengini değiştirmek sebepsiz kayma olur. Serbest renk seçici. Renk
körlüğü kipi. Kategori başına ikon. `shadcn_ui` sürüm yükseltmesi.
