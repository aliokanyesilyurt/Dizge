# Migration'lar

| # | Dosya | Ne getirdi | Sunucuda |
|---|---|---|---|
| 01 | `20260811090000_initial_schema.sql` | `nodes`, `habits`, `categories`, RLS, `apply_mutations` | ✅ uygulandı, iki kullanıcıyla doğrulandı (11 Ağu) |
| 02 | `20260811180000_realtime_publication.sql` | Realtime yayını + `replica identity full` (Y2) | ⏳ panodan çalıştırıldı (12 Ağu), doğrulanmadı |
| 03 | `20260812090000_groups.sql` | Gruplar, üyelik, davet, grup RLS'i (Y3) | ⏳ panodan çalıştırıldı (12 Ağu), üç kullanıcılı doğrulama yapılmadı |

## Adlandırma

`<14 haneli damga>_<NN>_<ad>.sql` — örn. `20260812110000_04_gruplar-arayuzu.sql`

Sıra numarası okunurluk için: çıplak damga kaçıncı migration olduğunu
söylemiyor. Damga yine de başta duruyor ve bunun iki sebebi var:

* Dosyalar **dize olarak** sıralanıyor (`panoya-yapistir.sh` içindeki
  `sort | tail -1` dâhil). `0004_...` biçimi mevcut damgalı dosyaların
  **önüne** düşer ve sıralama tersine dönerdi.
* İlk `_`'ye kadar olan kısım `supabase_migrations.schema_migrations`
  tablosuna **birincil anahtar** olarak yazılıyor. Uygulanmış bir dosyayı
  yeniden adlandırmak defteri sessizce bozar — bu yüzden yukarıdaki üç dosya
  eski adıyla kalıyor, numaraları yalnız bu tabloda.

## Uygulama

Bu makinede Postgres portları (5432, 6543) ağ tarafından yutulduğu için
`supabase db push` çalışmıyor; şema Supabase panosundaki SQL düzenleyicisinden
uygulanıyor. Yapıştırılacak metni üreten betik:

```sh
supabase/panoya-yapistir.sh                          # yalnız son migration
supabase/panoya-yapistir.sh <dosya> <dosya> ...      # birden fazla bekliyorsa
```

Betik migration'ın sonuna defter kaydını ekliyor; o olmadan CLI panodan
uygulanan şemayı görmez ve bir sonraki `db push` aynı migration'ı ikinci kez
göndermeye çalışır.
