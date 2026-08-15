-- =============================================================================
-- 04 · Profiller: görünen ad, avatar ve okuma sınırı   (damga: 20260813170000)
--
-- Plan: docs/gruplar-y4-4-plani.md §2
--
-- Y4.1 `owner_id`'yi istemciye kadar getirdi ama elimizdeki şey bir uuid ve
-- uuid kimseye gösterilemez. Bu migration onu insana çeviriyor.
--
-- `auth.users` başkasına kapalı ve **kapalı kalmalı**: orada e-posta, telefon
-- ve sağlayıcı kimlikleri var. Gösterilebilir olan iki alan (ad, fotoğraf)
-- bu yüzden ayrı bir tabloya çıkıyor; tablonun tamamı "başkası görebilir"
-- varsayımıyla yazıldı.
--
-- Dosya idempotent: panodan iki kez çalıştırılabilmeli.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Tablo
--
-- Tabloda **e-posta yok** ve olmayacak. Ortak grubu olan birine gösterilmesi
-- gereken şey "bu işi kim yazdı" sorusunun cevabı; iletişim bilgisi değil.
--
-- `avatar_url` sağlayıcının (bugün Google) CDN adresi. Fotoğrafın kendisini
-- kopyalamıyoruz: Storage'a yazmak, kullanıcının sağlayıcıdan sildiği bir
-- fotoğrafı bizim sunucumuzda yaşatmak olurdu.
-- -----------------------------------------------------------------------------

create table if not exists public.profiles (
  user_id      uuid        primary key references auth.users (id) on delete cascade,
  display_name text        not null default '',
  avatar_url   text,
  updated_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;


-- -----------------------------------------------------------------------------
-- 2. Ortak grup yardımcısı (Y3c deseni)
--
-- Politikanın içine `select ... from group_members` yazmanın iki sorunu var ve
-- ikisi de 03'te öğrenildi:
--
--   1. **Özyineleme riski.** Buradaki sorgu `group_members`'a bakıyor, onun
--      politikası da üyeliğe bakıyor. `security definer` RLS'i baypas ederek
--      okur ve döngüyü kırar.
--   2. **Performans.** `stable` fonksiyon, politikada `(select ...)` ile
--      sarıldığında satır başına değil sorgu başına bir kez çalışır.
--
-- `search_path` sabitlenmezse çağıran araya kendi şemasını sokabilir; bu
-- satır pazarlığa açık değil.
-- -----------------------------------------------------------------------------

create or replace function public.shares_group_with(other uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.group_members mine
      join public.group_members theirs on theirs.group_id = mine.group_id
     where mine.user_id = (select auth.uid())
       and theirs.user_id = other
  );
$$;


-- -----------------------------------------------------------------------------
-- 3. Politikalar
--
-- Okuma ve yazma ayrı yazılıyor. Tek bir `for all` politikası yazsaydım
-- "gördüğüm profili düzenleyebilirim" çıkardı — grup arkadaşının adını
-- değiştirebilmek.
-- -----------------------------------------------------------------------------

-- 3a. Okuma: kendi satırım + ortak grubum olanların satırı.
--
-- Ortak grubu olmayan biri **hiçbir satır göremez**. Ad bir dizin değil;
-- yalnız birlikte çalıştığın insanların adını görürsün.
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select
  using (
    user_id = (select auth.uid())
    or public.shares_group_with(user_id)
  );

-- 3b. Yazma: yalnız kendi satırım. `using` ve `with check` ikisi de gerekli —
-- yalnız `using` yazsaydım kullanıcı satırının `user_id`'sini başkasınınkiyle
-- değiştirebilirdi (S1'de öğrenildi).
drop policy if exists profiles_write on public.profiles;
create policy profiles_write on public.profiles
  for insert
  with check (user_id = (select auth.uid()));

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Silme politikası **yok**: profil satırı hesabın ömrüne bağlı ve
-- `on delete cascade` ile gidiyor. Elle silmek, grup arkadaşlarına adı
-- boş görünen bir hayalet bırakmak olurdu.


-- -----------------------------------------------------------------------------
-- 4. Adın nereden geldiği
--
-- Sıra: Google'ın gönderdiği tam ad → adı → e-postanın `@` öncesi.
--
-- Google ile girenler (G8) adlarını ve fotoğraflarını kendiliğinden alır.
-- E-postayla kaydolanlar `aliokan` gibi bir adla başlar ve hesap ekranından
-- değiştirir — boş bir ad göstermektense tahmin edilebilir bir ad iyi.
-- -----------------------------------------------------------------------------

create or replace function public.profile_name_from(meta jsonb, mail text)
returns text
language sql
immutable
set search_path = pg_temp
as $$
  select coalesce(
    nullif(btrim(coalesce(meta ->> 'full_name', '')), ''),
    nullif(btrim(coalesce(meta ->> 'name',      '')), ''),
    nullif(split_part(coalesce(mail, ''), '@', 1), ''),
    'Adsız'
  );
$$;

create or replace function public.profile_avatar_from(meta jsonb)
returns text
language sql
immutable
set search_path = pg_temp
as $$
  -- Supabase sağlayıcıya göre iki ayrı anahtar yazıyor; ikisine de bakmak
  -- gerekiyor. Boş dize `null` sayılır: istemci "fotoğraf var" sanıp boş bir
  -- istek atmasın.
  select coalesce(
    nullif(btrim(coalesce(meta ->> 'avatar_url', '')), ''),
    nullif(btrim(coalesce(meta ->> 'picture',    '')), '')
  );
$$;


-- -----------------------------------------------------------------------------
-- 5. Yeni kullanıcı → profil satırı
--
-- `security definer`: trigger `auth` şemasında, hedef tablo `public`'te ve
-- kaydolan kullanıcının henüz oturumu yok — RLS'in `auth.uid()`'si burada
-- güvenilmez.
--
-- Hata **yutuluyor**: profil satırı yazılamadığı için bir kaydın düşmesi
-- kabul edilemez. Kayıt asıl iş, profil onun süsü; eksik kalırsa geri dolum
-- (§6) ya da kullanıcının kendi kaydetmesi kapatır.
-- -----------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  begin
    insert into public.profiles (user_id, display_name, avatar_url)
    values (
      new.id,
      public.profile_name_from(new.raw_user_meta_data, new.email),
      public.profile_avatar_from(new.raw_user_meta_data)
    )
    on conflict (user_id) do nothing;
  exception when others then
    null;  -- Kayıt sürsün.
  end;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- -----------------------------------------------------------------------------
-- 5b. `updated_at` sunucu saatinden
--
-- İki cihazın hakemi bu sütun. İstemciye bırakılsaydı hakem, saati yanlış
-- kurulmuş bir telefon olurdu: ileri tarihli tek bir damga o adı sonsuza dek
-- kazanan yapardı. `apply_mutations`'ın §7'deki saat kayması korumasının aynı
-- gerekçesi, burada bir satırlık trigger'la çözülüyor.
-- -----------------------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before insert or update on public.profiles
  for each row execute function public.touch_updated_at();


-- -----------------------------------------------------------------------------
-- 6. Geri dolum
--
-- Trigger'ı yazıp bugünkü hesapları dışarıda bırakmak, özelliği kendi
-- geliştiricisine kapalı açmak olurdu: elimizdeki iki test hesabı adsız
-- kalırdı ve Y4.4 hiçbir yerde denenemezdi.
--
-- `do nothing`: adını çoktan değiştirmiş birinin satırını ezmez.
-- -----------------------------------------------------------------------------

insert into public.profiles (user_id, display_name, avatar_url)
select
  u.id,
  public.profile_name_from(u.raw_user_meta_data, u.email),
  public.profile_avatar_from(u.raw_user_meta_data)
  from auth.users u
on conflict (user_id) do nothing;


-- -----------------------------------------------------------------------------
-- 7. İndeks ve Realtime
--
-- `profiles` **yayına eklenmiyor**. Y2a'nın kuralı: Realtime bir sinyal, veri
-- yolu değil — ve ad değişimi saniyelik gecikmesi olan bir olay değil, grup
-- listesiyle birlikte tazelenir.
--
-- Ayrı bir indeks de yok: birincil anahtar `user_id` ve bütün sorgular
-- (`in (...)` ile toplu çekim dahil) onun üzerinden gidiyor.
-- -----------------------------------------------------------------------------
