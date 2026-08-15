# Gruplar Planı — Artımlı Çekim · Realtime · Paylaşılan Takvim

**Durum:** yazıldı ve uygulanmaya başlandı (11 Ağustos)
**Önceki planlar:** `backend-supabase-plani.md`, `giris-kapisi-plani.md`,
`tema-ve-giris-deneyimi-plani.md`

---

## 1. Neden gruplar doğrudan yazılamaz

Bugünün senkron sözleşmesi (B4) tek cümle: **oturum açılışında tam çekim,
sonrasında yalnız gönderim.** İkinci bir cihazın değişikliği, uygulama kapatılıp
açılana kadar gelmiyor.

Tek kullanıcı + bir buçuk cihaz için bu dürüst bir v1'di. Grup için değil:
paylaşılan bir takvimde karşı tarafın değişikliğini görmemek, özelliğin
kendisinin yokluğu demek. "Ali toplantıyı saat 3'e aldı" bilgisi uygulama
yeniden başlatılınca gelirse ortada paylaşılan bir takvim yoktur.

Bu yüzden sıra: **önce senkronu gerçek zamanlı hâle getir, sonra paylaş.**

| Dilim | Ne | Tek başına değeri var mı |
|---|---|---|
| Y1 | Artımlı çekim + birleştirme | **Evet** — iki cihaz bugün de eşitlenir |
| Y2 | Realtime: sunucu değişince haber ver | **Evet** — gecikme saniyeye iner |
| Y3 | Grup şeması + üyelik + RLS | Hayır (Y4 ile anlamlı) |
| Y4 | Grup arayüzü: oluştur, davet et, geç | — |

---

## 2. Y1 — Artımlı çekim

### Sorun

`RemoteGateway.pull({since})` imzası artımlı çekimi vaat ediyor ama
`SupabaseGateway` `since`'i bilerek yok sayıyor. Sebebi koda yazılmış: gelen
kayıtları yerel duruma **birleştirmek** gerekiyor ve `AppStore.loadJson` yıkıp
yeniden kuruyor.

### Karar Y1a — Birleştirmenin hakemi yine LWW, yine `updatedAt`

Üç modelin de (`Task`, `Note`, `Habit`) `updatedAt` alanı var ve JSON'a
yazılıyor. Birleştirme kuralı sunucudaki `apply_mutations` ile **birebir aynı**:
gelen kayıt yereldekinden yeniyse yazılır, değilse atlanır.

Aynı hakemi iki yerde uygulamak tekrar değil, zorunluluk: sunucu kimin
kazandığına yazarken karar veriyor, istemci okurken. İkisi farklı kural
kullansaydı iki cihaz farklı sonuca varırdı.

### Karar Y1b — Silme mezar taşıyla gelir, `payload` ile değil

Tam çekimde silinmiş satırlar süzülüyor (`_livePayloads`). Artımlı çekimde bu
**yanlış**: "gelmedi" ile "silindi" ayırt edilemez.

`pull(since:)` bu yüzden iki liste döner: yaşayan kayıtların payload'ları ve
**silinenlerin kimlikleri**. Şema zaten `deleted_at` tutuyor (B3), yeni bir
sunucu işi yok.

### Karar Y1c — İmleç sunucu saati, cihaz saati değil

Bir sonraki çekimin nereden devam edeceğini `server_at` söyler — şemaya tam bu
iş için konmuştu. Cihaz saatiyle sayfalamak, saati geri alınmış bir telefonda
değişiklikleri sonsuza dek atlamak demekti.

İmleç `LocalStore`'da saklanır ve **yalnız başarılı bir birleştirmeden sonra**
ilerler: yarıda kalan bir çekim, bir daha hiç gelmeyecek kayıtlar bırakmaz.

### Karar Y1d — Kategoriler artımlıya girmez

Kategoriler sıralı bir liste ve kimlikleri adları (B7.2). Artımlı çekimde
"silinen kategori" diye bir kayıt yok — liste bütün olarak taşınıyor. Her
artımlı turda tam kategori listesi çekilir; üç satırlık bir tablo için bu
maliyet gürültü seviyesinde.

### Karar Y1e — Çekim gönderimden **sonra**

Kuyrukta bekleyen mutasyon varken çekmek, kullanıcının henüz gönderilmemiş
değişikliğini sunucunun eski hâliyle ezebilir. Sıra bu yüzden sabit: önce
`push`, sonra `pull`. `SyncEngine` zaten her turda gönderiyor; çekim aynı turun
sonuna ekleniyor.

**Bitti sayılır:** iki `AppStore` örneği aynı sahte sunucuya bağlanır; birinde
yapılan değişiklik diğerinde belirir, silme silinir, eski damgalı bir kayıt
yeniyi ezmez.

---

## 3. Y2 — Realtime

### Karar Y2a — Realtime bir **sinyal**, veri yolu değil

Supabase Realtime satırın yeni hâlini de gönderebiliyor. Kullanmıyoruz: gelen
payload'ı doğrudan uygulamak, birleştirme mantığının ikinci bir kopyasını
yazmak demek. Üstelik güvenilmez — bağlantı koptuğu sürede olan olaylar hiç
gelmez ve o boşluğu yine artımlı çekim kapatır.

Realtime'ın işi tek: **"bir şey değişti" demek.** Gerisi Y1'in yolu. Böylece
gerçek zamanlılık, doğruluğun üstüne eklenen bir hız katmanı olur; doğruluğun
kendisi ona bağlı olmaz.

### Karar Y2b — Sinyal debounce edilir

Bir sürükleme oturumu onlarca satır değiştirebilir. Her olayda çekim yapmak
gidiş-dönüş israfı; sinyaller `AppConfig.syncDebounce` penceresinde birleşir.

**Bitti sayılır:** sahte bir sinyal akışı çekimi tetikler; art arda on sinyal
tek çekime iner.

---

## 4. Y3 — Grup şeması *(sonraki dilim)*

Taslak kararlar, uygulanmadan önce ayrıca gözden geçirilecek:

* `groups(id, name, owner_id, created_at)`
* `group_members(group_id, user_id, role, joined_at)` — `role`: `owner|member`
* `nodes`/`habits` tablolarına `group_id uuid null` sütunu. Null ise kişisel.
* RLS: `user_id = auth.uid() OR group_id in (select group_id from
  group_members where user_id = auth.uid())`
* Davet: `group_invites(token, group_id, email, expires_at)` — e-postayla
  gönderilen tek kullanımlık kod, kabul edilince üyelik satırı açar.

**Bu dilimin en büyük riski RLS.** Politikanın alt sorgusu her satırda
çalışırsa performans çöker; `security definer` bir yardımcı fonksiyon ya da
`(select ...)` sarmalı şart. Ayrıca yanlış yazılmış tek bir politika, grup
üyesi olmayan birine başkasının takvimini açar — S1'deki iki-kullanıcı
doğrulaması burada üç kullanıcıyla tekrarlanmalı.

---

## 5. Y4 — Grup arayüzü *(sonraki dilim)*

* Kenar çubuğunda bağlam seçici: "Kişisel" / grup adları
* Grup oluştur, e-postayla davet et, daveti kabul et
* Bloğun üstünde küçük bir sahiplik işareti (kimin işi)

---

## 6. Kapsam Dışı

Çakışma birleştirme (alan bazlı), grup içi rol/izin ayrıntısı (herkes her şeyi
düzenler), grup sohbeti, bildirimler, takvim paylaşım bağlantısı, dışa aktarma.

---

## 7. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| Birleştirme yerel değişikliği ezer | **Yüksek etki** | Y1a: LWW hakemi sunucuyla aynı; Y1e: çekim gönderimden sonra |
| İmleç yarıda kalan çekimde ilerler, kayıt atlanır | Orta | Y1c: imleç yalnız başarılı birleştirmeden sonra yazılır |
| Realtime bağlantısı sessizce ölür | Orta | Y2a: doğruluk artımlı çekimde; Realtime yalnız hızlandırıcı |
| Grup RLS'i sızdırır | **Yüksek etki** | Y3: üç kullanıcıyla elle doğrulama, S1'deki gibi |
| Realtime her tuşta çekim tetikler | Orta | Y2b: debounce |
