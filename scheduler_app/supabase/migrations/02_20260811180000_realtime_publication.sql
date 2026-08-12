-- =============================================================================
-- 02 · Realtime yayını        (damga: 20260811180000)
--
-- Durum: panodan hatasız çalıştırıldı (12 Ağustos); olay akışı iki cihazla
-- henüz denenmedi.
--
-- Plan: docs/gruplar-plani.md (Y2)
--
-- Supabase'in `postgres_changes` olayları, tablo `supabase_realtime`
-- yayınında **değilse hiç ateşlenmez**. İstemci kanala abone olur, hata da
-- almaz, sadece sessizce hiçbir şey gelmez — bu yüzden migration olmadan
-- Y2'nin kodu doğru yazılmış olsa bile çalışmaz.
--
-- Güvenlik: yayına eklemek RLS'i **baypas etmez**. Realtime, `postgres_changes`
-- için politikayı ayrıca değerlendirir; kullanıcı yalnız kendi satırlarının
-- olayını alır. Yani S1'de kurulan `user_id = auth.uid()` politikası burada da
-- geçerli.
--
-- Taşınan şey veri değil, yalnız "bir şey değişti" sinyali (Y2a): istemci
-- olayın payload'ını kullanmıyor, artımlı çekimi tetikliyor.
-- =============================================================================

-- `alter publication ... add table` aynı tablo için ikinci kez çalıştırılırsa
-- hata veriyor; bu dosya idempotent olmalı (panodan iki kez çalıştırılabilir).
do $$
declare
  t text;
begin
  foreach t in array array['nodes', 'habits', 'categories']
  loop
    if not exists (
      select 1
        from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = t
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I', t
      );
    end if;
  end loop;
end
$$;

-- Realtime'ın satırı kimin göreceğine karar verebilmesi için eski hâli de
-- gerekiyor: `replica identity full` olmadan silme olaylarında yalnız birincil
-- anahtar gelir ve RLS değerlendirmesi eksik kalır.
alter table public.nodes      replica identity full;
alter table public.habits     replica identity full;
alter table public.categories replica identity full;
