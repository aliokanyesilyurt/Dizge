# Y4 Planı — Grup Arayüzü

**Durum:** Y4.1–Y4.3 indi; sırada Y4.4 (12 Ağustos)
**Önceki:** `gruplar-plani.md` §5 (taslak), `gruplar-y3-plani.md` (şema indi)
**Önkoşul:** Y3 migration'ı sunucuda çalıştı; §11 doğrulaması henüz koşmadı.

---

## 1. Y3 ne bıraktı, Y4 ne bulacak

Sunucu artık grup satırı tutabiliyor. İstemci **hiçbir şey bilmiyor**: bugün
uygulamada grup diye bir kavram yok, bir görevin gruba ait olduğunu anlatan tek
bir alan bile yok.

Üst plan Y4'ü üç maddeyle özetlemişti (bağlam seçici, davet akışı, sahiplik
işareti). Kodun bugünkü hâline bakınca ortaya dördüncü ve **ilk yapılması
gereken** iş çıkıyor: grup bilgisinin istemciye kadar taşınması. Sıra bu yüzden
görsel işlerle başlamıyor.

---

## 2. Karar Y4a — Grup bilgisi payload'ın içinde değil, sütunda

`SupabaseGateway._livePayloads` sunucudan gelen satırın yalnız `payload`
sütununu alıyor. `group_id` ve `owner_id` ise **satırın sütunları**, payload'ın
içinde değil — yani bugünkü çekim onları sessizce yere bırakıyor.

Karar: gateway, satırı payload'a çevirirken bu iki sütunu payload'ın içine
katar (`groupId`, `ownerId`). Alternatif —istemciye ikinci bir "satır meta"
kanalı açmak— `AppStore.mergeJson`'ın sözleşmesini değiştirirdi; sözleşme
"düğümlerin JSON'u" ve grup da o düğümün bir niteliği.

Gönderim yönü zaten hazır: `apply_mutations` Y3'te `groupId` anahtarını kabul
ediyor ve **anahtarın yokluğu** ile `null` değerini ayırıyor. `Mutation` bu
anahtarı yalnız grup gerçekten değiştiğinde yazacak.

## 3. Karar Y4b — Bağlam bir süzgeç, ikinci bir depo değil

"Kişisel" ve grup adları arasında geçiş, verinin nereden geldiğini değil
**hangisinin gösterildiğini** değiştirir. Yerel depo tektir; kişisel işler
`groupId == null`, grup işleri o grubun kimliğini taşır.

İki ayrı `AppStore` tutmak (bağlam başına bir tane) ilk bakışta temiz görünüyor
ve yanlış: senkron motoru, outbox, geri alma yığını ve arama indeksi tek bir
depoya bağlı. İkiye bölmek dört sistemi birden ikiye bölmek olurdu.

Süzgeç `Provider` katmanında duruyor (`tasksForWeekProvider` ve kardeşleri
zaten oradan geçiyor), widget'ların içinde değil.

## 4. Karar Y4c — Bağlamda üretilen iş o bağlamın olur

Grup bağlamındayken açılan hızlı ekleme, doğan görevi o grubun kimliğiyle
yazar. Sürükleyip taşımak grubu **değiştirmez**; taşımak bir zaman işlemi.

Bağlam değiştirmenin tek yolu açık bir eylem olacak: görev düzenleyicide
"Kişisel / <grup>" seçimi. Örtük geçiş (ör. görevi grup görünümüne sürükleyince
gruba girmesi) tehlikeli: paylaşmak geri alınabilir görünen ama karşı tarafta
görünen bir iş.

## 5. Karar Y4d — Gruptan çıkınca yereldeki satırlar **silinir**

Y3e imleci başa alıyor, yani çekim eksik kalmıyor. Ama artımlı çekim yalnız
**ekler**: gruptan çıkan kullanıcının cihazında o grubun görevleri sonsuza dek
kalır. Sunucu artık onları göndermez, mezar taşı da yollamaz — çünkü satır
silinmedi, yalnız görünmez oldu.

Karar: üyelik kaybında o `groupId`'ye ait yerel satırlar **yerelden silinir** ve
bu silme outbox'a **yazılmaz**. Sunucudaki satır Y3'ün sahibinin ve orada
kalmalı; burada olan şey bir senkron değil, görüş alanının daralması.

Bu ayrımı yapmayan bir uygulama, "gruptan çıktım ama işleri hâlâ duruyor,
sildim, karşı tarafta da silindi" hikâyesini üretir.

## 6. Karar Y4e — "Kimin işi" için `profiles` tablosu gerekiyor *(migration 04)*

Sahiplik işareti `owner_id` ile geliyor ama bir uuid kullanıcıya
gösterilemez. `auth.users` başka kullanıcıya kapalı ve kapalı kalmalı — orada
e-posta, telefon, sağlayıcı kimlikleri var.

Bu yüzden Y4 küçük bir migration getirir:

* `profiles(user_id primary key, display_name text, updated_at)`
* RLS: herkes kendi satırını yazar; **okuma** yalnız ortak grubu olanlara açık
  (`user_id = auth.uid() or user_id in (select ... group_members ...)`) —
  yardımcı fonksiyon üzerinden, Y3c'deki özyineleme tuzağının aynısı burada da
  var.
* Kayıt olurken `display_name` e-postanın `@` öncesi kısmıyla dolar; hesap
  ekranından değiştirilebilir.

Ad göstermek istemeyen bir sürüm "ben / başkası" ayrımıyla da yaşayabilirdi,
ama paylaşılan bir takvimde "başkası" bilgi taşımıyor.

## 7. Karar Y4f — Grup işlemleri çevrimdışı kuyruğa girmez

Outbox `Mutation` taşıyor: düğüm ve alışkanlık. Grup kurmak, davet etmek,
daveti kabul etmek birer RPC ve hiçbiri LWW ile birleştirilemez — "çevrimdışıyken
kurduğum grup" ile "aynı anda başkasının kurduğu grup" arasında hakem yok.

Karar: bu üç işlem çevrimiçi ister ve çevrimdışıyken düğme pasif olur, sessizce
kuyruğa alınmaz. Hata mesajı da öyle söyler.

## 8. Karar Y4g — Davet token'ı elle yapıştırılır

E-posta gönderimi Y4'ün dışında (Edge Function + sağlayıcı + şablon: ayrı bir
iş). Y4'te sahip daveti üretir, uygulama token'ı panoya kopyalar; davet edilen
kişi "Daveti kabul et" alanına yapıştırır.

Adrese yazılı davet (Y3f) burada da geçerli: sahip e-posta girerse token yalnız
o hesapta çalışır. Bağlantı sızsa bile işe yaramaz.

---

## 9. Dilimler

| # | Ne | Tek başına değeri |
|---|---|---|
| Y4.1 | `groupId`/`ownerId` istemciye kadar taşınır; modele, JSON'a, mutasyona girer | Görünmez ama Y4.2'siz hiçbir şey olmaz |
| Y4.2 | Kenar çubuğunda bağlam seçici + süzgeç | **Evet** — tek kişilik grupla bile çalışır |
| Y4.3 | Grup kur / davet et / daveti kabul et / gruptan çık | **Evet** — paylaşım burada gerçek olur |
| Y4.4 | `profiles` + blok üstünde sahiplik işareti | **Evet** — "Ali toplantıyı taşımış" |

Y4.1, Y4.2 ve Y4.3 indi.

Y4.2 seçiciyi grubu olmayan kullanıcıda gizlemişti (gizlenecek iş yokken ölü
bir düğme durmasın diye). **Y4.3 bunu geri aldı**: ilk grubun kurulduğu yer o
menü ve gizlenirse hiç grup kurulamıyor. Planın "her zaman görünür" cümlesi
sonuçta doğru çıktı — ama gerekçesi yazılandan farklı.

Y4.3'ün üç işi de tek bir menüden çıkıyor (kur / katıl / yönet) ve üçü de
diyalog; grup yönetimi için ayrı bir ekran açmak, kullanıcıyı takvimden koparıp
dönüş yolunu ona bırakmak olurdu.

Sıra zorunlu: Y4.1 → Y4.2 → Y4.3 → Y4.4. Y4.3 inmeden ikinci bir kullanıcı
gruba giremeyeceği için Y4.2 tek kişiyle test edilir (kendi kurduğun grup).

---

## 10. Bitti sayılır

Kod tarafı (otomatik doğrulanan):

* [x] Gruptan çıkan cihazda o grubun işleri yerelden siliniyor ve **silme
  outbox'a yazılmıyor** — karşı tarafta duruyor.
* [x] Çevrimdışıyken grup düğmeleri pasif; kuyruğa hiçbir şey yazılmıyor.
* [x] `flutter analyze` temiz, testler yeşil.

Elle doğrulanacak (Y4.4'ten önce, iki gerçek hesapla):

* [ ] Aynı hesabın iki cihazında aynı grup görünür; birinde grup bağlamında
  yazılan iş diğerinde **grup bağlamında** belirir, kişiselde belirmez.
* [ ] İki ayrı hesap aynı grupta: A'nın taşıdığı blok B'de saniyeler içinde
  yerine oturur (Y2 sinyali + Y1 çekimi).
* [ ] Adrese yazılı davet başka bir hesapta reddediliyor.
* [ ] Windows sürümü derleniyor.

---

## 11. Riskler

| Risk | Olasılık | Karşılık |
|---|---|---|
| Kişisel görünüm grup işlerini sessizce gizler, kullanıcı "işim kayboldu" der | **Yüksek** | Y4.2'de bağlam seçici her zaman görünür; boş grup ekranı ne olduğunu yazar |
| Gruptan çıkan cihazda satırlar kalır | Yüksek | Y4d: üyelik kaybında yerelden silme, outbox'a yazmadan |
| Yerel şema `groupId` alanıyla değişir, eski kayıtlar bozulur | Orta | Alan **isteğe bağlı**; `fromJson` yokluğunda `null` — sürüm artışı gerekmez |
| Örtük paylaşım: kullanıcı işini farkında olmadan gruba atar | Orta | Y4c: bağlam değişimi yalnız açık seçimle |
| `profiles` politikası e-posta sızdırır | Orta | Tabloda e-posta yok, yalnız görünen ad; okuma ortak grup şartına bağlı |
| Grup RPC'leri çevrimdışı sessizce yutulur | Düşük | Y4f: düğme pasif, kuyruk yok |

---

## 12. Kapsam dışı

E-posta gönderimi, grup içi roller ve izinler, gruptan üye atma, grup silme,
ortak kategori listesi (Y3g), grup sohbeti, bildirim, takvim paylaşım bağlantısı.
