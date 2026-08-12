-- =============================================================================
-- Gruplar: şema, üyelik, davet ve RLS
--
-- Plan: docs/gruplar-y3-plani.md
--
-- Bu migration bir satırın **birden fazla kişiye** ait olabildiği bir dünyaya
-- geçiriyor. Arayüz getirmiyor (o Y4); getirdiği şey, yanlış yazılırsa
-- başkasının takvimini açacak olan politikalar.
--
-- Dosya idempotent: panodan iki kez çalıştırılabilmeli.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Grup tabloları
-- -----------------------------------------------------------------------------

create table if not exists public.groups (
  id         uuid        primary key default gen_random_uuid(),
  name       text        not null,
  owner_id   uuid        not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.group_members (
  group_id  uuid        not null references public.groups (id) on delete cascade,
  user_id   uuid        not null references auth.users (id) on delete cascade,
  role      text        not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),

  primary key (group_id, user_id)
);

-- Davet, üye **olmayan** birine gösterilecek tek şey. Bu yüzden token'ın
-- kendisi bir giriş anahtarı: tahmin edilebilir olmamalı.
--
-- `email` doluysa daveti yalnız o adresin sahibi kabul edebilir (bkz.
-- `accept_invite`). Boşsa davet, bağlantıyı eline geçiren herkese açıktır —
-- bu bilinçli bir seçenek, kazayla oluşan bir durum değil.
create table if not exists public.group_invites (
  token       text        primary key,
  group_id    uuid        not null references public.groups (id) on delete cascade,
  email       text,
  created_by  uuid        not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '7 days',
  accepted_at timestamptz,
  accepted_by uuid        references auth.users (id) on delete set null
);

alter table public.groups        enable row level security;
alter table public.group_members enable row level security;
alter table public.group_invites enable row level security;


-- -----------------------------------------------------------------------------
-- 2. `nodes` / `habits`: anahtarın taşınması (Y3a)
--
-- Bugünkü birincil anahtar `(user_id, id)`. Grup satırında bu **bozuk**:
-- Ali'nin yazdığı görevi Veli düzenlerse `apply_mutations` satırı kendi
-- kimliğiyle yazar ve aynı `id`'ye sahip ikinci bir satır açılır. İki satır
-- sonsuza dek yan yana yaşar; Ali silince Veli'nin kopyası kalır.
--
-- Anahtar bu yüzden yalnız `id`. İstemci zaten uuid üretiyor ve yerel deposu
-- `id`'yi tek anahtar sayıyor — şema nihayet istemciyle aynı şeyi söylüyor.
--
-- `user_id` de `owner_id` oluyor. Kozmetik değil: eski ad "bu satır bu
-- kullanıcıya ait, başkası göremez" sözü veriyordu ve o söz artık yalan.
-- Adı bırakmak, altı ay sonra birinin `user_id = auth.uid()` diye bir sorgu
-- daha yazmasını davet etmek olurdu.
-- -----------------------------------------------------------------------------

do $$
declare
  t   text;
  n   int;
  dup boolean;
begin
  foreach t in array array['nodes', 'habits']
  loop
    -- 2a. Yeniden adlandırma (yalnız bir kez).
    if exists (
      select 1
        from information_schema.columns
       where table_schema = 'public' and table_name = t and column_name = 'user_id'
    ) then
      execute format('alter table public.%I rename column user_id to owner_id', t);
    end if;

    -- 2b. Grup sütunu. Null ise kişisel satır.
    --
    -- `on delete set null`: grup silinirse satırlar **kişiselleşir**, yok
    -- olmaz. Bir grubu dağıtmak, üyelerin geçmişini silmek anlamına gelmemeli.
    execute format(
      'alter table public.%I add column if not exists group_id uuid '
      'references public.groups (id) on delete set null', t
    );

    -- 2c. Birincil anahtarın taşınması.
    select array_length(conkey, 1) into n
      from pg_constraint
     where conrelid = format('public.%I', t)::regclass and contype = 'p';

    if n = 2 then
      execute format(
        'select exists (select 1 from public.%I group by id having count(*) > 1)', t
      ) into dup;

      -- Sessizce çözmek (birini silmek, birini yeniden adlandırmak) veri
      -- kaybı olurdu. Böyle bir satır varsa taşıma durur ve elle çözülür.
      if dup then
        raise exception
          '%: aynı id birden çok kullanıcıda var, anahtar taşınamaz — önce elle çözülmeli', t;
      end if;

      execute format('alter table public.%I drop constraint %I', t, t || '_pkey');
      execute format('alter table public.%I add constraint %I primary key (id)', t, t || '_pkey');
    end if;
  end loop;
end
$$;


-- -----------------------------------------------------------------------------
-- 3. Üyelik yardımcıları (Y3c)
--
-- Politikanın içine `select ... from group_members` yazmanın iki ayrı sorunu
-- var ve ikisi de bu fonksiyonlarla çözülüyor:
--
--   1. **Özyineleme.** `group_members`'ın kendi politikası da üyeliğe bakacak.
--      Politikanın içinden aynı tabloyu sorgulamak Postgres'te
--      `infinite recursion detected in policy` demek. `security definer`
--      fonksiyon RLS'i baypas ederek okur ve döngüyü kırar.
--
--   2. **Performans.** `stable` işaretli fonksiyon, politikada `(select ...)`
--      ile sarıldığında satır başına değil sorgu başına bir kez çalışır —
--      S1'de `(select auth.uid())` sarmalının konduğu sebebin aynısı.
--
-- `security definer` yazmak güvenliği fonksiyonun içine taşımaktır:
-- `search_path` sabitlenmezse çağıran araya kendi şemasını sokabilir. Bu
-- yüzden `set search_path` burada pazarlığa açık değil.
-- -----------------------------------------------------------------------------

create or replace function public.my_group_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select group_id from public.group_members where user_id = (select auth.uid());
$$;

create or replace function public.is_group_member(gid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.group_members
     where group_id = gid and user_id = (select auth.uid())
  );
$$;

create or replace function public.is_group_owner(gid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.groups where id = gid and owner_id = (select auth.uid())
  );
$$;


-- -----------------------------------------------------------------------------
-- 4. Politikalar
--
-- `using` okumayı süzer, `with check` yazmayı. İkisi ayrı yazılmazsa
-- kullanıcı göremediği bir satıra yazabilir (S1'de öğrenildi).
-- -----------------------------------------------------------------------------

-- 4a. Veri satırları: kendi satırım ya da üyesi olduğum grubun satırı.
--
-- Yazma tarafındaki ek şart, `using`'de olmayan bir şeyi söylüyor: bir satıra
-- `group_id` yazabilmek için o grubun **üyesi** olmak gerekir. Olmasaydı
-- herkes kendi görevini başkasının grubuna atabilirdi.

drop policy if exists nodes_owner on public.nodes;
drop policy if exists nodes_access on public.nodes;
create policy nodes_access on public.nodes
  for all
  using (
    owner_id = (select auth.uid())
    or group_id in (select public.my_group_ids())
  )
  with check (
    (group_id is null and owner_id = (select auth.uid()))
    or (group_id is not null and public.is_group_member(group_id))
  );

drop policy if exists habits_owner on public.habits;
drop policy if exists habits_access on public.habits;
create policy habits_access on public.habits
  for all
  using (
    owner_id = (select auth.uid())
    or group_id in (select public.my_group_ids())
  )
  with check (
    (group_id is null and owner_id = (select auth.uid()))
    or (group_id is not null and public.is_group_member(group_id))
  );

-- 4b. Gruplar: üye okur, yalnız sahip yazar.

drop policy if exists groups_access on public.groups;
create policy groups_access on public.groups
  for all
  using (
    owner_id = (select auth.uid())
    or id in (select public.my_group_ids())
  )
  with check (owner_id = (select auth.uid()));

-- 4c. Üyelik satırları: **yazma politikası yok.**
--
-- Üyelik açmak yalnız `accept_invite` ile olur; o `security definer` olduğu
-- için politikaya takılmaz. Buraya bir `insert` politikası yazmak, davet
-- akışının yanından dolaşan ikinci bir kapı açmak olurdu.
--
-- Silme tek istisna: insan kendi üyeliğini bırakabilir.

drop policy if exists group_members_read on public.group_members;
create policy group_members_read on public.group_members
  for select
  using (
    user_id = (select auth.uid())
    or group_id in (select public.my_group_ids())
  );

drop policy if exists group_members_leave on public.group_members;
create policy group_members_leave on public.group_members
  for delete
  using (user_id = (select auth.uid()));

-- 4d. Davetler: üye görebilir, kimse doğrudan yazamaz (`create_invite`).
--
-- Davet edilen kişi burada **hiçbir satır göremez** — henüz üye değil. Onun
-- yolu token'ı `accept_invite`'a vermek; tabloyu okumak değil.

drop policy if exists group_invites_read on public.group_invites;
create policy group_invites_read on public.group_invites
  for select
  using (
    created_by = (select auth.uid())
    or group_id in (select public.my_group_ids())
  );


-- -----------------------------------------------------------------------------
-- 5. Grup kurma, davet etme, daveti kabul etme
--
-- Üçü de `security definer`: hiçbiri politikayla ifade edilemez. Grup kurmak
-- iki tabloya birden yazıyor (grup + sahip üyeliği) ve arada kalırsa sahipsiz
-- bir grup bırakırdı; daveti kabul eden ise henüz üye değil, yani daveti
-- göremiyor.
-- -----------------------------------------------------------------------------

create or replace function public.create_group(group_name text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := (select auth.uid());
  gid uuid;
begin
  if uid is null then
    raise exception 'oturum yok' using errcode = '42501';
  end if;

  if coalesce(btrim(group_name), '') = '' then
    raise exception 'grup adı boş olamaz' using errcode = '22023';
  end if;

  insert into public.groups (name, owner_id)
  values (btrim(group_name), uid)
  returning id into gid;

  -- Sahip de bir üyedir. Ayrıcalığı `groups.owner_id`'de duruyor; üyelik
  -- satırı olmadan kendi grubunun satırlarını `my_group_ids()` üzerinden
  -- göremezdi.
  insert into public.group_members (group_id, user_id, role)
  values (gid, uid, 'owner');

  return gid;
end;
$$;

-- Davet etme hakkı **yalnız sahipte**.
--
-- Üst plan grup içi rolleri kapsam dışı bırakıyor ("herkes her şeyi
-- düzenler") ve bu içerik için doğru; davet ise içerik değil, grubun
-- sınırını genişleten bir işlem. Her üyenin yabancı çağırabildiği bir grup,
-- sahibinin haberi olmadan büyür.
create or replace function public.create_invite(gid uuid, invite_email text default null)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := (select auth.uid());
  tok text;
begin
  if uid is null then
    raise exception 'oturum yok' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.groups where id = gid and owner_id = uid
  ) then
    raise exception 'yalnız grup sahibi davet edebilir' using errcode = '42501';
  end if;

  -- Token bir giriş anahtarı, kimlik değil: istemcinin ürettiği bir uuid
  -- yeterli olmazdı. `gen_random_uuid()` Postgres'in güçlü rastgeleliğini
  -- kullanıyor; ikisi birleşince 64 karakterlik, tahmin edilemez bir dize.
  tok := replace(gen_random_uuid()::text, '-', '')
      || replace(gen_random_uuid()::text, '-', '');

  insert into public.group_invites (token, group_id, email, created_by)
  values (tok, gid, nullif(btrim(coalesce(invite_email, '')), ''), uid);

  return tok;
end;
$$;

create or replace function public.accept_invite(invite_token text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid       uuid := (select auth.uid());
  inv       public.group_invites;
  user_mail text;
begin
  if uid is null then
    raise exception 'oturum yok' using errcode = '42501';
  end if;

  -- `for update`: tek kullanımlık olmanın tek gerçek güvencesi kilit.
  -- Kontrol ile işaretleme arasına ikinci bir çağrı girerse davet iki kez
  -- kabul edilirdi.
  select * into inv
    from public.group_invites
   where token = invite_token
     for update;

  if inv.token is null then
    raise exception 'davet bulunamadı' using errcode = '42501';
  end if;

  if inv.accepted_at is not null then
    raise exception 'davet zaten kullanılmış' using errcode = '42501';
  end if;

  if inv.expires_at < now() then
    raise exception 'davetin süresi dolmuş' using errcode = '42501';
  end if;

  -- Adrese yazılmış davet yalnız o adresin sahibine açılır. Aksi hâlde
  -- bağlantıyı gören herkes gruba girerdi.
  if inv.email is not null then
    select email into user_mail from auth.users where id = uid;
    if lower(coalesce(user_mail, '')) <> lower(inv.email) then
      raise exception 'davet başka bir adrese yazılmış' using errcode = '42501';
    end if;
  end if;

  insert into public.group_members (group_id, user_id, role)
  values (inv.group_id, uid, 'member')
  on conflict (group_id, user_id) do nothing;

  update public.group_invites
     set accepted_at = now(), accepted_by = uid
   where token = inv.token;

  return inv.group_id;
end;
$$;


-- -----------------------------------------------------------------------------
-- 6. apply_mutations: grup farkındalığı
--
-- Değişen üç şey var:
--   * `on conflict (user_id, id)` → `on conflict (id)` (anahtar taşındı),
--   * mutasyon `groupId` taşıyabilir; taşıyorsa üyelik denetlenir,
--   * her mutasyonun yazımı kendi hata kalkanına alındı.
--
-- Kalkan Y3 ile zorunlu hâle geldi: anahtar artık genel olduğu için bir
-- upsert, RLS'in göstermediği bir satıra çarpabilir ve o hata bütün turu
-- düşürürdü. Kısmi başarı zaten bu fonksiyonun sözleşmesi (B2) — zehirli tek
-- mutasyon kendi id'siyle `rejected`'a düşer, kalan 39'u gider.
--
-- `security invoker` (B5) korunuyor: RLS içeride de geçerli, yani buradaki
-- denetimler politikanın yerine değil, **üstüne** yazılmış ikinci kat.
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
          insert into public.categories (user_id, name, color_hex, position, updated_at)
          values (
            uid,
            m_entity,
            coalesce(m -> 'payload' ->> 'colorHex', '#808080'),
            coalesce((m -> 'payload' ->> 'position')::int, 0),
            m_at
          )
          on conflict (user_id, name) do update
            set color_hex  = excluded.color_hex,
                position   = excluded.position,
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
-- 7. İndeksler
--
-- Adlar sütunla birlikte taşınıyor: `nodes_user_server_at_idx` artık
-- `owner_id` üzerinde ve eski adıyla kalması yanıltıcı olurdu.
-- -----------------------------------------------------------------------------

alter index if exists nodes_user_server_at_idx  rename to nodes_owner_server_at_idx;
alter index if exists habits_user_server_at_idx rename to habits_owner_server_at_idx;
alter index if exists nodes_user_live_idx       rename to nodes_owner_live_idx;

-- `my_group_ids()` her politika değerlendirmesinde çalışıyor: sıcak yol.
create index if not exists group_members_user_idx
  on public.group_members (user_id, group_id);

-- Artımlı çekim artık grup satırlarını da soruyor: "şu damgadan sonra
-- değişen, benim gruplarımın satırları".
create index if not exists nodes_group_server_at_idx
  on public.nodes (group_id, server_at desc) where group_id is not null;

create index if not exists habits_group_server_at_idx
  on public.habits (group_id, server_at desc) where group_id is not null;


-- -----------------------------------------------------------------------------
-- 8. Realtime
--
-- Grup ve üyelik tabloları yayına **eklenmiyor**. Y2a'nın kuralı: Realtime bir
-- sinyal, veri yolu değil — ve üyelik değişimi zaten istemcide tam çekimi
-- tetikliyor (Y3e), saniyelik gecikmesi olan bir olay değil.
--
-- `nodes`/`habits` zaten yayında. Realtime politikayı ayrıca değerlendirdiği
-- için grup satırlarının olayları üyelere kendiliğinden akar — yeni bir iş
-- yok. Bunun aynası da doğru: yukarıdaki politika sızdırıyorsa, Realtime de
-- sızdırır.
-- -----------------------------------------------------------------------------
