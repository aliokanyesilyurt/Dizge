-- =============================================================================
-- 06 — Grup rengi/açıklaması ve kategori görünen adı
--
-- Plan: docs/geri-bildirim-10-eylul-plani.md §5 (R1) ve §8 (K2).
--
-- Üç değişiklik, üçü de **eklemeli**: sütunlar nullable, eski istemci onları
-- hiç yollamasa da yazması kırılmıyor. Göç çalıştırılmadan yeni istemci
-- çalışırsa renk/açıklama/ad yalnız bu cihazda kalır; hiçbir şey bozulmaz.
--
-- Çalıştırma sırası: 05'ten sonra. İki kez yapıştırmak zararsız.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Grup rengi ve açıklaması
--
-- `color` bir **palet sırası** (smallint), hex değil — 05'teki `avatar_color`
-- ile aynı gerekçe: palet temanın parçası ve ayarlanabilir olmalı; sunucuya
-- donmuş bir hex yazmak her palet düzeltmesini eski gruplarda etkisiz
-- bırakırdı.
--
-- Yeni fonksiyon gerekmiyor: `create_group` grubu kuruyor, renk ve açıklamayı
-- istemci hemen ardından yazıyor. Yazma hakkı zaten yalnız sahipte
-- (`groups_access`'in `with check (owner_id = auth.uid())` koşulu).
-- -----------------------------------------------------------------------------

alter table public.groups
  add column if not exists description text,
  add column if not exists color smallint;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'groups_color_range'
  ) then
    alter table public.groups
      add constraint groups_color_range
      check (color is null or color >= 0) not valid;
    alter table public.groups validate constraint groups_color_range;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'groups_description_length'
  ) then
    alter table public.groups
      add constraint groups_description_length
      check (description is null or char_length(description) <= 200) not valid;
    alter table public.groups validate constraint groups_description_length;
  end if;
end $$;


-- -----------------------------------------------------------------------------
-- 2. Kategori görünen adı
--
-- Kategorinin kimliği adıdır (`name`) ve değişmez (plan §Zd): yeniden
-- adlandırmak senkronu, eski anlık görüntüleri ve eski sürümdeki ikinci
-- cihazı kırardı. Kullanıcının verdiği ad ayrı bir sütunda; null =
-- "uygulamanın varsayılan adını göster".
-- -----------------------------------------------------------------------------

alter table public.categories
  add column if not exists label text;


-- -----------------------------------------------------------------------------
-- 3. apply_mutations — kategori dalı `label`ı da yazıyor
--
-- Fonksiyonun geri kalanı 03'teki tanımın **birebir kopyası** (bu dosya bir
-- betikle üretildi); yalnız kategori ekleme/güncelleme dalına `label` girdi.
-- -----------------------------------------------------------------------------

create or replace function public.apply_mutations(muts jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  uid         uuid := (select auth.uid());
  m           jsonb;
  m_id        text;
  m_kind      text;
  m_entity    text;
  m_op        text;
  m_at        timestamptz;
  m_group     uuid;
  m_has_group boolean;
  m_ok        boolean;
  accepted    text[] := '{}';
  rejected    text[] := '{}';
begin
  if uid is null then
    raise exception 'oturum yok' using errcode = '42501';
  end if;

  for m in select value from jsonb_array_elements(coalesce(muts, '[]'::jsonb))
  loop
    m_id     := m ->> 'id';
    m_kind   := coalesce(m ->> 'kind', 'task');
    m_entity := m ->> 'entityId';
    m_op     := coalesce(m ->> 'op', 'upsert');

    -- Bozuk damga fonksiyonu düşürmemeli; o mutasyon reddedilir, tur sürer.
    begin
      m_at := (m ->> 'at')::timestamptz;
    exception when others then
      m_at := null;
    end;

    -- Kimliksiz mutasyon raporlanamaz (istemci onu ack edemez); sessizce atlanır.
    if m_id is null then
      continue;
    end if;

    -- Saat kayması koruması (§7). İleri tarihli bir damga, LWW'de sonsuza dek
    -- kazanan bir kayıt üretirdi — sonraki her düzenleme sessizce yutulurdu.
    if m_entity is null
       or m_at is null
       or m_at > now() + interval '5 minutes' then
      rejected := rejected || m_id;
      continue;
    end if;

    -- `groupId` **anahtarının varlığı** ile değerinin null olması farklı iki
    -- şey: ilki "grubu şu yap", ikincisi "gruptan çıkar". Anahtarın hiç
    -- olmaması ise "grubuna dokunma" demek — bugünün istemcisi `groupId`
    -- göndermiyor ve gönderilmeyeni yokluk saymak, grup görevlerini sessizce
    -- kişiselleştirirdi.
    m_has_group := jsonb_exists(m, 'groupId');

    -- Bozuk bir uuid'yi burada yakalamak şart: gövdenin geri kalanı kendi
    -- kalkanının içinde ama bu satır dışarıda ve cast hatası bütün turu
    -- düşürürdü.
    m_ok    := true;
    m_group := null;
    begin
      m_group := nullif(m ->> 'groupId', '')::uuid;
    exception when others then
      m_ok := false;
    end;

    if not m_ok then
      rejected := rejected || m_id;
      continue;
    end if;

    if m_has_group and m_group is not null and not public.is_group_member(m_group) then
      rejected := rejected || m_id;
      continue;
    end if;

    m_ok := true;
    begin
      if m_kind in ('task', 'note') then
        if m_op = 'delete' then
          insert into public.nodes (owner_id, id, kind, payload, updated_at, deleted_at, group_id)
          values (uid, m_entity, m_kind, '{}'::jsonb, m_at, m_at, m_group)
          on conflict (id) do update
            set payload    = '{}'::jsonb,
                deleted_at = excluded.updated_at,
                updated_at = excluded.updated_at,
                group_id   = case when m_has_group
                                  then excluded.group_id
                                  else public.nodes.group_id end,
                server_at  = now()
            where public.nodes.updated_at < excluded.updated_at;
        else
          insert into public.nodes (owner_id, id, kind, payload, updated_at, deleted_at, group_id)
          values (uid, m_entity, m_kind, coalesce(m -> 'payload', '{}'::jsonb), m_at, null, m_group)
          on conflict (id) do update
            set payload    = excluded.payload,
                kind       = excluded.kind,
                deleted_at = null,        -- yeniden dirilen kayıt (geri al) canlanır
                updated_at = excluded.updated_at,
                group_id   = case when m_has_group
                                  then excluded.group_id
                                  else public.nodes.group_id end,
                server_at  = now()
            where public.nodes.updated_at < excluded.updated_at;  -- ← LWW hakemi
        end if;

      elsif m_kind = 'habit' then
        if m_op = 'delete' then
          insert into public.habits (owner_id, id, payload, updated_at, deleted_at, group_id)
          values (uid, m_entity, '{}'::jsonb, m_at, m_at, m_group)
          on conflict (id) do update
            set payload    = '{}'::jsonb,
                deleted_at = excluded.updated_at,
                updated_at = excluded.updated_at,
                group_id   = case when m_has_group
                                  then excluded.group_id
                                  else public.habits.group_id end,
                server_at  = now()
            where public.habits.updated_at < excluded.updated_at;
        else
          insert into public.habits (owner_id, id, payload, updated_at, deleted_at, group_id)
          values (uid, m_entity, coalesce(m -> 'payload', '{}'::jsonb), m_at, null, m_group)
          on conflict (id) do update
            set payload    = excluded.payload,
                deleted_at = null,
                updated_at = excluded.updated_at,
                group_id   = case when m_has_group
                                  then excluded.group_id
                                  else public.habits.group_id end,
                server_at  = now()
            where public.habits.updated_at < excluded.updated_at;
        end if;

      elsif m_kind = 'category' then
        -- Kategoriler gruba girmiyor (Y3g): kimlikleri adları ve liste bütün
        -- olarak değişiyor. Paylaşılan bir listede iki üyenin aynı anda
        -- sıralama değiştirmesi, listeyi ezen tek çağrıda sessiz kayıp olurdu.
        if m_op = 'delete' then
          delete from public.categories where user_id = uid and name = m_entity;
        else
          insert into public.categories (user_id, name, color_hex, position, label, updated_at)
          values (
            uid,
            m_entity,
            coalesce(m -> 'payload' ->> 'colorHex', '#808080'),
            coalesce((m -> 'payload' ->> 'position')::int, 0),
            -- 06: kullanıcının verdiği görünen ad; yoksa null ("varsayılan").
            nullif(btrim(m -> 'payload' ->> 'label'), ''),
            m_at
          )
          on conflict (user_id, name) do update
            set color_hex  = excluded.color_hex,
                position   = excluded.position,
                label      = excluded.label,
                updated_at = excluded.updated_at
            where public.categories.updated_at < excluded.updated_at;
        end if;

      else
        -- Tanınmayan tür: reddet. Sessizce kabul etmek veriyi kaybetmek olurdu.
        m_ok := false;
      end if;
    exception when others then
      -- RLS reddi, bozuk uuid, tanınmayan sütun… hepsi tek mutasyonun sorunu.
      m_ok := false;
    end;

    -- LWW `where`'i tutmadıysa satır yazılmadı — ama bu bir **hata değil**:
    -- sunucudaki kayıt zaten daha yeni. İstemci onu tekrar göndermemeli, o
    -- yüzden kabul edilmiş sayılır.
    if m_ok then
      accepted := accepted || m_id;
    else
      rejected := rejected || m_id;
    end if;
  end loop;

  return jsonb_build_object(
    'accepted', to_jsonb(accepted),
    'rejected', to_jsonb(rejected)
  );
end;
$$;


-- -----------------------------------------------------------------------------
-- 4. replace_categories — tam gönderimde de `label`
-- -----------------------------------------------------------------------------

create or replace function public.replace_categories(cats jsonb)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then
    raise exception 'oturum yok' using errcode = '42501';
  end if;

  delete from public.categories where user_id = uid;

  insert into public.categories (user_id, name, color_hex, position, label, updated_at)
  select
    uid,
    c.value ->> 'name',
    coalesce(c.value ->> 'colorHex', '#808080'),
    (c.ordinality - 1)::int,
    nullif(btrim(c.value ->> 'label'), ''),
    now()
  from jsonb_array_elements(coalesce(cats, '[]'::jsonb)) with ordinality as c
  where c.value ->> 'name' is not null
  on conflict (user_id, name) do update
    set color_hex = excluded.color_hex,
        position  = excluded.position,
        label     = excluded.label;
end;
$$;


-- -----------------------------------------------------------------------------
-- 5. Doğrulama
--
--   select column_name from information_schema.columns
--    where table_schema = 'public'
--      and ((table_name = 'groups' and column_name in ('description', 'color'))
--        or (table_name = 'categories' and column_name = 'label'));
--   -- beklenen: üç satır
-- -----------------------------------------------------------------------------
