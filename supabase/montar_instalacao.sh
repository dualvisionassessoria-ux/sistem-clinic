#!/usr/bin/env bash
# Junta todas as migrações num único arquivo para colar no SQL Editor do Supabase.
set -euo pipefail
cd "$(dirname "$0")"
{
  echo "-- Sistem Clinic · instalação completa (gerado por montar_instalacao.sh)"
  echo "-- Cole tudo no SQL Editor do Supabase e clique em Run. Rode UMA vez num projeto vazio."
  for f in migrations/*.sql; do
    echo; echo "-- >>> $f"; cat "$f"
  done
} > instalar.sql
echo "Gerado supabase/instalar.sql"
