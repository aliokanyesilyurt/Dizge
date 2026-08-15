-- =============================================================================
-- 04 için doğrulama · Profiller ve okuma sınırı  (docs/gruplar-y4-4-plani.md §10)
--
-- Migration değil, **denetim**. Bu dosya sunucuya kalıcı bir şey eklemez;
-- profil satırlarının kime açık olduğunu sorar.
--
-- Neden gerekiyor: `profiles` tablosu, tasarımı gereği **başkasının**
-- okuyabildiği ilk tablomuz. 03'e kadar her satırın cevabı "yalnız sahibi"
-- ya da "grubun üyeleri"ydi; burada araya "ortak grubu olan" giriyor ve o
-- şart yanlış yazılırsa tablo bir kullanıcı dizinine dönüşür.
--
-- -----------------------------------------------------------------------------
-- NASIL ÇALIŞTIRILIR
--
-- 1. Üç test hesabının kimliğini al:
--
--      select id, email from auth.users order by created_at;
--
--    Üç hesap şart. İkisi aynı grupta, biri **dışarıda**: asıl aranan şey
--    dışarıdakinin hiçbir ad görememesi.
--
-- 2. Aşağıdaki üç uuid'yi doldur.
-- 3. Dosyanın tamamını Supabase panosundaki SQL düzenleyicisine yapıştır.
--
-- Beklenen çıktı **bir hata mesajı**:
--
--      TÜMÜ GEÇTİ — 7 kontrol, değişiklikler geri alındı
--
-- Evet, hata. Betik kendi yazdıklarını temizlemek için sonunda bilerek
-- `raise exception` atıyor: Postgres'te bir istisna bütün işlemi geri alır.
-- Başka bir mesaj görürsen kalan **odur**.
-- =============================================================================

do $$
declare
  -- ↓↓↓ DOLDUR ↓↓↓
  ali  uuid := '00000000-0000-0000-0000-000000000001';  -- grup sahibi
  veli uuid := '00000000-0000-0000-0000-000000000002';  -- aynı grubun üyesi
  ayse uuid := '00000000-0000-0000-0000-000000000003';  -- grubun DIŞINDA
  -- ↑↑↑ DOLDUR ↑↑↑

  gid     uuid;
  tok     text;
  n       int;
  ad      text;
  patladi boolean;
begin
  if ali = '00000000-0000-0000-0000-000000000001' then
    raise exception 'Önce dosyanın başındaki üç uuid doldurulmalı';
  end if;

  ---------------------------------------------------------------------------
  -- 1. Geri dolum çalıştı mı: üç hesabın da profili var ve adı boş değil
  --
  -- Trigger yalnız **yeni** kullanıcıları yakalar. Bu kontrol, migration'ın
  -- §6'daki geri dolumunun gerçekten koştuğunu soruyor: koşmasaydı bugünkü
  -- hesaplar adsız kalır ve özellik kendi geliştiricisinde denenemezdi.
  ---------------------------------------------------------------------------
  select count(*) into n
    from public.profiles
   where user_id in (ali, veli, ayse) and btrim(display_name) <> '';
  if n <> 3 then
    raise exception 'KALDI · adım 1: üç hesabın % tanesinde dolu profil var — geri dolum eksik', n;
  end if;

  ---------------------------------------------------------------------------
  -- 2. Ali kendi adını görür ve değiştirebilir
  ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', ali)::text, true);
  execute 'set local role authenticated';

  update public.profiles
     set display_name = 'Ali Doğrulama', updated_at = now()
   where user_id = ali;

  select display_name into ad from public.profiles where user_id = ali;
  if ad <> 'Ali Doğrulama' then
    raise exception 'KALDI · adım 2: kullanıcı kendi adını değiştiremedi';
  end if;

  ---------------------------------------------------------------------------
  -- 3. Ali başkasının adını **değiştiremez**
  --
  -- Politika `update ... using (user_id = auth.uid())` olduğu için satır
  -- hiç görünmez ve güncelleme sessizce 0 satırı etkiler. Aranan şey bir
  -- hata değil, **değişmemiş** bir ad.
  ---------------------------------------------------------------------------
  update public.profiles set display_name = 'Ele geçirildi' where user_id = veli;

  execute 'reset role';
  select display_name into ad from public.profiles where user_id = veli;
  if ad = 'Ele geçirildi' then
    raise exception 'KALDI · adım 3: SIZINTI — başkasının adı değiştirilebildi';
  end if;

  ---------------------------------------------------------------------------
  -- 4. Ortak grup yokken kimse kimseyi görmez  ← bu dilimin asıl sorusu
  --
  -- Grup kurulmadan **önce** sorulması şart: sonra sorulsaydı "hiç göremiyor"
  -- ile "grubu olmadığı için göremiyor" birbirine karışırdı.
  ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', ayse)::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.profiles where user_id in (ali, veli);
  if n <> 0 then
    raise exception 'KALDI · adım 4: SIZINTI — ortak grubu olmayan % profil görüyor', n;
  end if;

  ---------------------------------------------------------------------------
  -- 5. Ali grup kurar, Veli katılır
  ---------------------------------------------------------------------------
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', ali)::text, true);
  execute 'set local role authenticated';

  gid := public.create_group('Profil doğrulama grubu');
  tok := public.create_invite(gid);

  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', veli)::text, true);
  execute 'set local role authenticated';

  if public.accept_invite(tok) <> gid then
    raise exception 'KALDI · adım 5: davet yanlış grubu döndürdü';
  end if;

  ---------------------------------------------------------------------------
  -- 6. Artık Veli Ali'nin adını görür — ve yalnız onu
  ---------------------------------------------------------------------------
  select display_name into ad from public.profiles where user_id = ali;
  if ad is distinct from 'Ali Doğrulama' then
    raise exception 'KALDI · adım 6: grup arkadaşı adı göremiyor (ortak grup şartı fazla dar)';
  end if;

  select count(*) into n from public.profiles where user_id = ayse;
  if n <> 0 then
    raise exception 'KALDI · adım 6: SIZINTI — grup dışındaki hesabın adı görünüyor';
  end if;

  ---------------------------------------------------------------------------
  -- 7. Ayşe hâlâ dışarıda: grup kurulmuş olması onu içeri almaz
  ---------------------------------------------------------------------------
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', ayse)::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.profiles where user_id in (ali, veli);
  if n <> 0 then
    raise exception 'KALDI · adım 7: SIZINTI — grup dışındaki hesap % profil görüyor', n;
  end if;

  -- `user_id`'yi başkasınınkine çevirerek satır çalmak da yasak: `with check`
  -- olmasaydı Ayşe kendi satırını Ali'ninkine dönüştürebilirdi.
  patladi := false;
  begin
    update public.profiles set user_id = ali where user_id = ayse;
  exception when others then
    patladi := true;
  end;

  execute 'reset role';
  if not patladi then
    select count(*) into n from public.profiles where user_id = ayse;
    if n = 0 then
      raise exception 'KALDI · adım 7: SIZINTI — satırın sahibi değiştirilebildi';
    end if;
  end if;

  ---------------------------------------------------------------------------
  -- Temizlik: istisna bütün işlemi geri alır.
  ---------------------------------------------------------------------------
  raise exception 'TÜMÜ GEÇTİ — 7 kontrol, değişiklikler geri alındı';
end
$$;
