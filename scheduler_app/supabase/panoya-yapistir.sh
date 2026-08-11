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
set -euo pipefail

cd "$(dirname "$0")/.."

OUT='supabase/panoya-yapistir.sql'
LATEST=$(ls supabase/migrations/*.sql | sort | tail -1)
VERSION=$(basename "$LATEST" | cut -d_ -f1)
NAME=$(basename "$LATEST" .sql | cut -d_ -f2-)

{
  echo "-- Bu dosya TÜRETİLMİŞ bir yardımcıdır ve git'e girmez."
  echo "-- Tek gerçek kaynak: $LATEST"
  echo "-- Buradaki tek fark, sonundaki migration defteri kaydı."
  echo "--"
  echo "-- Yeniden üretmek için: supabase/panoya-yapistir.sh"
  echo
  cat "$LATEST"
  echo
  echo
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
  echo 'insert into supabase_migrations.schema_migrations (version, name)'
  echo "values ('$VERSION', '$NAME')"
  echo 'on conflict (version) do nothing;'
} > "$OUT"

echo "Üretildi: $OUT  ($(wc -l < "$OUT") satır, migration: $VERSION $NAME)"
