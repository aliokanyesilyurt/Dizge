-- =============================================================================
-- 03 için doğrulama · Gruplar, üyelik ve RLS  (docs/gruplar-y3-plani.md §11)
--
-- Migration değil, **denetim**. Bu dosya sunucuya bir şey eklemez; grup
-- politikasının gerçekten sızdırıp sızdırmadığını sorar.
--
-- Neden gerekiyor: S1'de RLS iki gerçek kullanıcıyla doğrulanmıştı. Y3 aynı
-- politikayı üçüncü bir duruma açtı — "üyesi olduğum grup" — ve yanlış
-- yazılmış tek bir satır, grup üyesi olmayan birine başkasının takvimini
-- açar. Bunu gözle okuyarak doğrulamak yeterli değil.
--
-- -----------------------------------------------------------------------------
-- NASIL ÇALIŞTIRILIR
--
-- 1. Üç test hesabının kimliğini al:
--
--      select id, email from auth.users order by created_at;
--
--    Üç hesap şart. İkisi grubun içinde, biri **dışında** olacak: asıl
--    aranan şey dışarıdakinin hiçbir şey görememesi.
--
-- 2. Aşağıdaki üç uuid'yi doldur.
-- 3. Dosyanın tamamını Supabase panosundaki SQL düzenleyicisine yapıştır.
--
-- Beklenen çıktı **bir hata mesajı**:
--
--      TÜMÜ GEÇTİ — 8 kontrol, değişiklikler geri alındı
--
-- Evet, hata. Betik kendi yazdıklarını temizlemek için sonunda bilerek
-- `raise exception` atıyor: Postgres'te bir istisna bütün işlemi geri alır ve
-- geriye tek bir test grubu bile kalmaz. Başka bir mesaj görürsen kalan
-- **odur** — hangi adımda kaldığını söyler.
-- =============================================================================

do $$
declare
  -- ↓↓↓ DOLDUR ↓↓↓
  ali  uuid := '00000000-0000-0000-0000-000000000001';  -- grup sahibi
  veli uuid := '00000000-0000-0000-0000-000000000002';  -- davet edilecek üye
  ayse uuid := '00000000-0000-0000-0000-000000000003';  -- grubun DIŞINDA
  -- ↑↑↑ DOLDUR ↑↑↑

  gid       uuid;
  tok       text;
  gorev     text := gen_random_uuid()::text;
  ayse_isi  text := gen_random_uuid()::text;
  ayse_mail text;
  sonuc     jsonb;
  n         int;
  sahip     uuid;
  patladi   boolean;
begin
  if ali = '00000000-0000-0000-0000-000000000001' then
    raise exception 'Önce dosyanın başındaki üç uuid doldurulmalı';
  end if;

  ---------------------------------------------------------------------------
  -- 1. Ali grup kurar
  ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', ali)::text, true);
  execute 'set local role authenticated';

  gid := public.create_group('Doğrulama grubu');

  select count(*) into n
    from public.group_members
   where group_id = gid and user_id = ali and role = 'owner';
  if n <> 1 then
    raise exception 'KALDI · adım 1: grup kuruldu ama sahibin üyelik satırı yok';
  end if;

  ---------------------------------------------------------------------------
  -- 2. Ali davet üretir, Veli kabul eder
  ---------------------------------------------------------------------------
  tok := public.create_invite(gid);

  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', veli)::text, true);
  execute 'set local role authenticated';

  if public.accept_invite(tok) <> gid then
    raise exception 'KALDI · adım 2: davet yanlış grubu döndürdü';
  end if;

  -- Tek kullanımlık olmak bir söz: ikinci kabul patlamalı.
  patladi := false;
  begin
    perform public.accept_invite(tok);
  exception when others then
    patladi := true;
  end;
  if not patladi then
    raise exception 'KALDI · adım 2: davet ikinci kez kabul edildi';
  end if;

  ---------------------------------------------------------------------------
  -- 3. Ali grup görevi yazar, Veli görür
  ---------------------------------------------------------------------------
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', ali)::text, true);
  execute 'set local role authenticated';

  sonuc := public.apply_mutations(jsonb_build_array(jsonb_build_object(
    'id',       gen_random_uuid()::text,
    'kind',     'task',
    'entityId', gorev,
    'op',       'upsert',
    'at',       now()::text,
    'payload',  jsonb_build_object('title', 'Grubun işi'),
    'groupId',  gid::text
  )));
  if jsonb_array_length(sonuc -> 'rejected') <> 0 then
    raise exception 'KALDI · adım 3: grup görevi reddedildi: %', sonuc;
  end if;

  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', veli)::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.nodes where id = gorev;
  if n <> 1 then
    raise exception 'KALDI · adım 3: Veli grup görevini görmüyor (paylaşım yok)';
  end if;

  ---------------------------------------------------------------------------
  -- 4. Ayşe hiçbir şey görmez  ← bu dilimin asıl sorusu
  ---------------------------------------------------------------------------
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', ayse)::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.nodes where id = gorev;
  if n <> 0 then
    raise exception 'KALDI · adım 4: SIZINTI — üye olmayan grup görevini görüyor';
  end if;

  select count(*) into n from public.groups where id = gid;
  if n <> 0 then
    raise exception 'KALDI · adım 4: SIZINTI — üye olmayan grubu görüyor';
  end if;

  select count(*) into n from public.group_members where group_id = gid;
  if n <> 0 then
    raise exception 'KALDI · adım 4: SIZINTI — üye olmayan üye listesini görüyor';
  end if;

  ---------------------------------------------------------------------------
  -- 5. Ayşe kendi işini yabancı bir gruba atayamaz
  ---------------------------------------------------------------------------
  sonuc := public.apply_mutations(jsonb_build_array(jsonb_build_object(
    'id',       'ayse-deneme',
    'kind',     'task',
    'entityId', ayse_isi,
    'op',       'upsert',
    'at',       now()::text,
    'payload',  jsonb_build_object('title', 'İçeri sızma denemesi'),
    'groupId',  gid::text
  )));
  if not jsonb_exists(sonuc -> 'rejected', 'ayse-deneme') then
    raise exception 'KALDI · adım 5: yabancı gruba yazma reddedilmedi: %', sonuc;
  end if;

  execute 'reset role';
  select count(*) into n from public.nodes where id = ayse_isi and group_id is not null;
  if n <> 0 then
    raise exception 'KALDI · adım 5: SIZINTI — satır yine de gruba yazıldı';
  end if;

  ---------------------------------------------------------------------------
  -- 6. Veli grup görevini düzenler: satır **tek** kalır, sahibi değişmez
  ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', veli)::text, true);
  execute 'set local role authenticated';

  sonuc := public.apply_mutations(jsonb_build_array(jsonb_build_object(
    'id',       gen_random_uuid()::text,
    'kind',     'task',
    'entityId', gorev,
    'op',       'upsert',
    'at',       (now() + interval '1 second')::text,
    'payload',  jsonb_build_object('title', 'Veli düzenledi'),
    'groupId',  gid::text
  )));
  if jsonb_array_length(sonuc -> 'rejected') <> 0 then
    raise exception 'KALDI · adım 6: üye grup görevini düzenleyemedi: %', sonuc;
  end if;

  -- Anahtar taşınmasının (Y3a) sınavı. Eski `(user_id, id)` anahtarıyla burada
  -- **iki** satır olurdu: Ali'ninki ve Veli'ninki, aynı id'yle yan yana.
  execute 'reset role';
  select count(*) into n from public.nodes where id = gorev;
  if n <> 1 then
    raise exception 'KALDI · adım 6: aynı id ile % satır var — anahtar taşınmamış', n;
  end if;

  select owner_id into sahip from public.nodes where id = gorev;
  if sahip <> ali then
    raise exception 'KALDI · adım 6: düzenleme satırın sahibini değiştirdi';
  end if;

  ---------------------------------------------------------------------------
  -- 7. Adrese yazılı davet başkasına açılmaz
  ---------------------------------------------------------------------------
  select email into ayse_mail from auth.users where id = ayse;
  if ayse_mail is null or ayse_mail = '' then
    -- Adressiz davet **herkese açıktır** (bilinçli bir seçenek). Adres yoksa
    -- bu adım hiçbir şey sınamaz; sessizce geçmesindense durması doğru.
    raise exception 'KALDI · adım 7: üçüncü hesabın e-postası yok, sınanamıyor';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', ali)::text, true);
  execute 'set local role authenticated';
  tok := public.create_invite(gid, ayse_mail);

  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', veli)::text, true);
  execute 'set local role authenticated';

  patladi := false;
  begin
    perform public.accept_invite(tok);
  exception when others then
    patladi := true;
  end;
  if not patladi then
    raise exception 'KALDI · adım 7: adrese yazılı daveti başkası kabul etti';
  end if;

  ---------------------------------------------------------------------------
  -- 8. Veli gruptan çıkınca grup satırları kayboluyor
  ---------------------------------------------------------------------------
  delete from public.group_members where group_id = gid and user_id = veli;

  select count(*) into n from public.nodes where id = gorev;
  if n <> 0 then
    raise exception 'KALDI · adım 8: SIZINTI — ayrılan üye hâlâ görüyor';
  end if;

  ---------------------------------------------------------------------------
  -- Bitti. İstisna bilerek: işlemi geri alıp test grubunu ortadan kaldırıyor.
  ---------------------------------------------------------------------------
  execute 'reset role';
  raise exception 'TÜMÜ GEÇTİ — 8 kontrol, değişiklikler geri alındı';
end
$$;
