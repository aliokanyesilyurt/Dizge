-- =============================================================================
-- Scheduler — Supabase şeması
--
-- Plan: docs/backend-supabase-plani.md (S1)
-- Bu dosya Supabase SQL düzenleyicisinde bir kez çalıştırılır. Yeniden
-- çalıştırılabilir (idempotent): her nesne `if not exists` ya da
-- `create or replace` ile tanımlı.
--
-- Tasarım kararı (B1) — hibrit şema. Sunucunun süzmesi/sıralaması gereken
-- alanlar tipli sütun; kaydın geri kalanı `payload jsonb`. Şemanın tek gerçeği
-- istemcideki `toJson`/`fromJson` çiftinde kalır. `Task` bu yaz üç kez alan
-- kazandı (inPool, isFixed/skippedOn, energy); tam normalize bir şemada
-- bunların her biri bir migrasyon ve bir dağıtım penceresi olurdu.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Tablolar
-- -----------------------------------------------------------------------------

-- Görevler ve notlar. İkisi tek tabloda çünkü istemcide ikisi de `Node` ve
-- `AppStore.toJson` onları tek bir `nodes` dizisinde taşıyor.
create table if not exists public.nodes (
  user_id     uuid        not null references auth.users (id) on delete cascade,
  id          text        not null,               -- istemcinin ürettiği uuid
  kind        text        not null check (kind in ('task', 'note')),
  payload     jsonb       not null default '{}'::jsonb,

  -- LWW hakemi: **cihaz** saati (Mutation.at). Sunucu saati değil — çevrimdışı
  -- yapılıp saatler sonra gönderilen bir düzenleme, sunucu saatiyle damgalansa
  -- kendinden eski olan değişikliği ezerdi.
  updated_at  timestamptz not null,

  -- Mezar taşı (B3). Satır silinmez: artımlı çekimde "gelmedi" ile "silindi"
  -- ayırt edilemezdi.
  deleted_at  timestamptz,

  -- Sunucunun kendi damgası. Artımlı çekim (`pull(since:)`) bunu kullanacak;
  -- cihaz saati güvenilmez olduğu için sayfalama ona bağlanamaz.
  server_at   timestamptz not null default now(),

  primary key (user_id, id)
);

create table if not exists public.habits (
  user_id     uuid        not null references auth.users (id) on delete cascade,
  id          text        not null,
  payload     jsonb       not null default '{}'::jsonb,
  updated_at  timestamptz not null,
  deleted_at  timestamptz,
  server_at   timestamptz not null default now(),

  primary key (user_id, id)
);

-- Kategoriler bir **liste**, bir koleksiyon değil: sırası kullanıcıya görünür
-- ve kimlikleri adlarıdır (B7.2). Bu yüzden tek tek değil, bütün olarak
-- değiştirilir — bkz. `replace_categories`.
create table if not exists public.categories (
  user_id     uuid        not null references auth.users (id) on delete cascade,
  name        text        not null,
  color_hex   text        not null,
  position    integer     not null default 0,
  updated_at  timestamptz not null default now(),

  primary key (user_id, name)
);


-- -----------------------------------------------------------------------------
-- 2. İndeksler
-- -----------------------------------------------------------------------------

-- Artımlı çekim için hazır dursun: "şu damgadan sonra değişenler".
create index if not exists nodes_user_server_at_idx
  on public.nodes (user_id, server_at desc);

create index if not exists habits_user_server_at_idx
  on public.habits (user_id, server_at desc);

-- Tam çekimde silinmiş satırlar okunmaz; kısmi indeks yalnız canlıları taşır.
create index if not exists nodes_user_live_idx
  on public.nodes (user_id, kind) where deleted_at is null;


-- -----------------------------------------------------------------------------
-- 3. Satır düzeyi güvenlik (B5)
--
-- İstemcideki anon anahtar bir sır değil — güvenliği sağlayan o değil, bu
-- bölüm. Politikası olmayan tek bir tablo, anon anahtarı olan herkese bütün
-- kullanıcıların takvimini açar. `test/backend_schema_test.dart` bunu bekçiler.
-- -----------------------------------------------------------------------------

alter table public.nodes      enable row level security;
alter table public.habits     enable row level security;
alter table public.categories enable row level security;

-- `(select auth.uid())` sarmalı bilinçli: alt sorgu olarak yazıldığında
-- Postgres onu satır başına değil sorgu başına bir kez hesaplar (initplan).
-- Çıplak `auth.uid()` binlerce satırda ölçülebilir yavaşlık demek.
--
-- `with check` şart: `using` yalnız okumayı süzer. O olmadan kullanıcı, başka
-- birinin `user_id`'siyle satır yazabilirdi.

drop policy if exists nodes_owner on public.nodes;
create policy nodes_owner on public.nodes
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists habits_owner on public.habits;
create policy habits_owner on public.habits
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists categories_owner on public.categories;
create policy categories_owner on public.categories
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));


-- -----------------------------------------------------------------------------
-- 4. Gönderim: apply_mutations (B2)
--
-- Outbox bir **liste** boşaltır. Her mutasyon için ayrı HTTP çağrısı, 40
-- bloklu bir sürükleme oturumunda 40 gidiş-dönüş demekti. Tek tur:
--
--   giriş : Mutation.toJson() dizisi
--   çıkış : {"accepted": [...], "rejected": [...]}  → PushResult'ın karşılığı
--
-- Kısmi başarı bedava gelir: zehirli tek bir kayıt bütün turu düşürmez, kendi
-- id'siyle `rejected`'a düşer ve `Outbox.markFailed` onu 8 denemede atar.
--
-- `security invoker` (B5): fonksiyon çağıranın hakkıyla çalışır, RLS içeride
-- de geçerlidir. `definer` olsaydı fonksiyon RLS'i baypas ederdi ve doğru
-- user_id yazmak tek başına bu gövdenin dikkatine kalırdı.
-- -----------------------------------------------------------------------------

create or replace function public.apply_mutations(muts jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  uid       uuid := (select auth.uid());
  m         jsonb;
  m_id      text;
  m_kind    text;
  m_entity  text;
  m_op      text;
  m_at      timestamptz;
  accepted  text[] := '{}';
  rejected  text[] := '{}';
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

    if m_kind in ('task', 'note') then
      if m_op = 'delete' then
        insert into public.nodes (user_id, id, kind, payload, updated_at, deleted_at)
        values (uid, m_entity, m_kind, '{}'::jsonb, m_at, m_at)
        on conflict (user_id, id) do update
          set payload    = '{}'::jsonb,
              deleted_at = excluded.updated_at,
              updated_at = excluded.updated_at,
              server_at  = now()
          where public.nodes.updated_at < excluded.updated_at;
      else
        insert into public.nodes (user_id, id, kind, payload, updated_at, deleted_at)
        values (uid, m_entity, m_kind, coalesce(m -> 'payload', '{}'::jsonb), m_at, null)
        on conflict (user_id, id) do update
          set payload    = excluded.payload,
              kind       = excluded.kind,
              deleted_at = null,        -- yeniden dirilen kayıt (geri al) canlanır
              updated_at = excluded.updated_at,
              server_at  = now()
          where public.nodes.updated_at < excluded.updated_at;  -- ← LWW hakemi
      end if;

    elsif m_kind = 'habit' then
      if m_op = 'delete' then
        insert into public.habits (user_id, id, payload, updated_at, deleted_at)
        values (uid, m_entity, '{}'::jsonb, m_at, m_at)
        on conflict (user_id, id) do update
          set payload    = '{}'::jsonb,
              deleted_at = excluded.updated_at,
              updated_at = excluded.updated_at,
              server_at  = now()
          where public.habits.updated_at < excluded.updated_at;
      else
        insert into public.habits (user_id, id, payload, updated_at, deleted_at)
        values (uid, m_entity, coalesce(m -> 'payload', '{}'::jsonb), m_at, null)
        on conflict (user_id, id) do update
          set payload    = excluded.payload,
              deleted_at = null,
              updated_at = excluded.updated_at,
              server_at  = now()
          where public.habits.updated_at < excluded.updated_at;
      end if;

    elsif m_kind = 'category' then
      -- İstemci bugün kategori mutasyonu üretmiyor (B7.2): kategoriler
      -- `replace_categories` ile bütün olarak gidiyor. Yine de destekleniyor,
      -- çünkü desteklenmeseydi ileride üretilen ilk kategori mutasyonu
      -- kuyruğu sekiz denemelik bir geri çekilmeye sokardı.
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
      rejected := rejected || m_id;
      continue;
    end if;

    -- LWW `where`'i tutmadıysa satır yazılmadı — ama bu bir **hata değil**:
    -- sunucudaki kayıt zaten daha yeni. İstemci onu tekrar göndermemeli, o
    -- yüzden kabul edilmiş sayılır.
    accepted := accepted || m_id;
  end loop;

  return jsonb_build_object(
    'accepted', to_jsonb(accepted),
    'rejected', to_jsonb(rejected)
  );
end;
$$;


-- -----------------------------------------------------------------------------
-- 5. Kategoriler: bütün olarak değiştir
--
-- Kategoriler sıralı bir liste ve kimlikleri adları. Tek tek upsert, silinmiş
-- bir kategoriyi sunucuda bırakırdı. Tam görüntü gönderiminde (pushSnapshot)
-- liste olduğu gibi yerine geçer.
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

  insert into public.categories (user_id, name, color_hex, position, updated_at)
  select
    uid,
    c.value ->> 'name',
    coalesce(c.value ->> 'colorHex', '#808080'),
    (c.ordinality - 1)::int,
    now()
  from jsonb_array_elements(coalesce(cats, '[]'::jsonb)) with ordinality as c
  where c.value ->> 'name' is not null
  on conflict (user_id, name) do update
    set color_hex = excluded.color_hex,
        position  = excluded.position;
end;
$$;


-- -----------------------------------------------------------------------------
-- 6. Bakım: mezar taşı temizliği (B3)
--
-- 90 günden eski mezar taşları düşer. Bu fonksiyon **bütün** kullanıcıların
-- satırlarına dokunur; o yüzden `security definer` olmak zorunda — ve tam bu
-- yüzden çağrı hakkı geri alınır. Zamanlayıcıya (pg_cron / Edge Function)
-- servis rolüyle bağlanır.
-- -----------------------------------------------------------------------------

create or replace function public.purge_tombstones()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  removed integer := 0;
  n integer;
begin
  delete from public.nodes
   where deleted_at is not null and deleted_at < now() - interval '90 days';
  get diagnostics n = row_count;
  removed := removed + n;

  delete from public.habits
   where deleted_at is not null and deleted_at < now() - interval '90 days';
  get diagnostics n = row_count;
  removed := removed + n;

  return removed;
end;
$$;

revoke execute on function public.purge_tombstones() from public;
revoke execute on function public.purge_tombstones() from anon;
revoke execute on function public.purge_tombstones() from authenticated;
