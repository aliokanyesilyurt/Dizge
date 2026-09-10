-- =============================================================================
-- 05 — Profil rozet rengi
--
-- Karar C (docs/giris-ve-hesap-onarimi-plani.md): rozet rengi kullanıcının
-- seçimi olacak.
--
-- Bugüne kadar renk `avatarColorFor(userId)` ile kimlikten türüyordu. Türetme
-- iyi bir varsayılan — aynı kişi her cihazda, her temada aynı renk — ama
-- **seçim değil**. Rozet, grup arkadaşlarının seni tanıdığı şey; adını
-- seçebilip yüzünü seçememek tuhaf bir eksiklikti.
--
-- Bu göç çalıştırılmasa da uygulama çalışır: sütun yoksa istemciye `null`
-- gelir ve eski türetme davranışına düşer (`Profile.avatarColor` null =
-- "seçilmedi"). Yani renk seçici sessizce çalışmaz, ama hiçbir şey kırılmaz.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Sütun
--
-- `smallint`: değer `kAvatarColors` listesindeki sıra, bugün 0–7. `text` ile
-- renk kodu ("#7FB2E5") saklamak cazipti ve reddedildi — palet temanın parçası
-- ve bir gün ayarlanacak; sunucuya donmuş bir hex yazmak, paleti değiştiren
-- her düzeltmeyi eski kullanıcılarda etkisiz bırakırdı. Sıra ise "kullanıcı
-- soldan dördüncüyü seçti" der ve palet güncellendiğinde onunla gelir.
--
-- **Nullable ve varsayılansız.** `default 0` yazsaydım hiç renk seçmemiş
-- herkes aynı maviye düşerdi; rozetin insanları ayırma işlevi biterdi. null
-- burada "veri yok" değil, "seçim yok" demek ve istemci onu kimlikten türeyen
-- renge çeviriyor.
--
-- `if not exists`: bu dosya panoya iki kez yapıştırılırsa ikincisi hata
-- vermesin. Bütün göç dosyalarının kuralı.
-- -----------------------------------------------------------------------------

alter table public.profiles
  add column if not exists avatar_color smallint;


-- -----------------------------------------------------------------------------
-- 2. Aralık kısıtı
--
-- Üst sınır **yazılmıyor**. Palete dokuzuncu bir renk eklendiğinde `<= 7`
-- diyen bir kısıt, sunucuya yeni bir göç yazana kadar o rengi seçen herkese
-- anlaşılmaz bir hata verirdi — istemcinin paleti ile sunucunun kısıtı ayrı
-- hızlarda güncellenir. İstemci zaten modülü alıyor (`avatarColorOf`), yani
-- aralık dışı bir sayı rozeti bozamaz.
--
-- Negatif değer ise başka bir şey: hiçbir istemci üretmiyor, üretiliyorsa
-- ortada bir hata var ve sessizce saklanmasındansa reddedilmesi doğru.
--
-- `not valid` + ayrı `validate`: tablo bugün küçük ama kısıt eklemenin tam
-- tablo kilidi aldığı desen burada da korunuyor (03'te öğrenildi).
-- -----------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_avatar_color_range'
  ) then
    alter table public.profiles
      add constraint profiles_avatar_color_range
      check (avatar_color is null or avatar_color >= 0) not valid;

    alter table public.profiles
      validate constraint profiles_avatar_color_range;
  end if;
end $$;


-- -----------------------------------------------------------------------------
-- 3. Politikalar ve tetikleyici: değişiklik yok
--
-- `profiles_read` / `profiles_update` sütun değil **satır** düzeyinde çalışıyor;
-- yeni sütun kendiliğinden aynı kuralın altına giriyor. `profiles_touch_updated_at`
-- de `before update` olduğu için rengi değiştiren upsert damgayı yine tazeliyor.
--
-- Kayıt tetikleyicisine (`handle_new_user`) renk **eklenmedi**: yeni hesaba
-- rastgele bir renk yazmak, seçim yapmış biriyle yapmamış birini sunucuda
-- ayırt edilemez hâle getirirdi. Türetme istemcinin işi.
-- -----------------------------------------------------------------------------


-- -----------------------------------------------------------------------------
-- 4. Doğrulama
--
-- Panoda çalıştırdıktan sonra:
--
--   select column_name, data_type, is_nullable
--     from information_schema.columns
--    where table_schema = 'public'
--      and table_name   = 'profiles'
--      and column_name  = 'avatar_color';
--   -- beklenen: avatar_color | smallint | YES
--
-- Kendi satırına yazabildiğini görmek için (oturum açık bir istemciden değil,
-- panodan çalıştırırsan `auth.uid()` null döner ve satır bulunmaz — bu normal):
--
--   select user_id, display_name, avatar_color from public.profiles limit 5;
-- -----------------------------------------------------------------------------
