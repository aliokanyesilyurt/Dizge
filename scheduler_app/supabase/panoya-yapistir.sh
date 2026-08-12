#!/usr/bin/env bash
# Panoya yapıştırılacak SQL'i üretir: migration + CLI migration defteri kaydı.
#
# Neden var: bu geliştirme makinesinde Postgres portları (5432 ve 6543) ağ
# tarafından yutuluyor — TCP el sıkışması tamamlanıyor ama `SSLRequest` paketine
# hiç cevap gelmiyor. `supabase db push` bu yüzden çalışamıyor ve şema Supabase
# panosundaki SQL düzenleyicisinden uygulanıyor.
#
# Defter kaydı elle ekleniyor çünkü panodan uygulanan şemayı CLI görmez:
# `supabase_migrations.schema_migrations` boş kalır ve bir sonraki `db push`
# aynı migration'ı ikinci kez göndermeye çalışır.
#
# Çıktı dosyası git'e girmez (bkz. supabase/.gitignore): türetilmiş bir kopya,
# repoda durursa şemanın ikinci bir gerçeği olur ve zamanla ayrışır.
#
# Ağ düzeldiğinde (telefon hotspot'u, VPN) bu betiğe gerek kalmaz:
#   supabase db push
#
# Varsayılan olarak **son** migration'ı paketler. Birden fazlası bekliyorsa
# (ör. Realtime uygulanmadan gruplar geldiyse) hepsi sırayla verilebilir:
#   supabase/panoya-yapistir.sh supabase/migrations/2026081118*.sql \
#                               supabase/migrations/2026081209*.sql
# Migration'lar idempotent yazıldığı için zaten uygulanmış olanı tekrar
# göndermek zararsız; eksik bırakmak değil.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT='supabase/panoya-yapistir.sql'

if [ "$#" -gt 0 ]; then
  FILES=("$@")
else
  FILES=("$(ls supabase/migrations/*.sql | sort | tail -1)")
fi

{
  echo "-- Bu dosya TÜRETİLMİŞ bir yardımcıdır ve git'e girmez."
  echo "-- Tek gerçek kaynak: ${FILES[*]}"
  echo "-- Buradaki tek fark, sonundaki migration defteri kaydı."
  echo "--"
  echo "-- Yeniden üretmek için: supabase/panoya-yapistir.sh"
  echo

  for f in "${FILES[@]}"; do
    cat "$f"
    echo
    echo
  done

  echo '-- ============================================================================='
  echo '-- Migration defteri'
  echo '-- ============================================================================='
  echo
  echo 'create schema if not exists supabase_migrations;'
  echo
  echo 'create table if not exists supabase_migrations.schema_migrations ('
  echo '  version    text primary key,'
  echo '  statements text[],'
  echo '  name       text'
  echo ');'
  echo
  for f in "${FILES[@]}"; do
    version=$(basename "$f" | cut -d_ -f1)
    name=$(basename "$f" .sql | cut -d_ -f2-)
    echo 'insert into supabase_migrations.schema_migrations (version, name)'
    echo "values ('$version', '$name')"
    echo 'on conflict (version) do nothing;'
    echo
  done
} > "$OUT"

echo "Üretildi: $OUT  ($(wc -l < "$OUT") satır)"
for f in "${FILES[@]}"; do echo "  · $(basename "$f")"; done
