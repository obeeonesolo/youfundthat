#!/usr/bin/env bash
# Déploiement du schéma SQL sur Supabase production.
# Usage : DATABASE_URL="postgresql://postgres.REF:PASSWORD@aws-0-eu-west-1.pooler.supabase.com:5432/postgres" ./scripts/deploy-supabase.sh
# Obtenir DATABASE_URL : Project Settings → Database → Connection string → Session pooler (port 5432)
# Note : sur le plan gratuit Supabase, utiliser le Session Pooler (port 5432), pas la connexion directe.

set -euo pipefail

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "Erreur : variable DATABASE_URL non définie." >&2
  echo "Usage : DATABASE_URL='postgresql://...' ./scripts/deploy-supabase.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"

echo "=== Déploiement YouFundThat sur Supabase ==="
echo "URL : ${DATABASE_URL%%:*}://...@$(echo "$DATABASE_URL" | grep -o '@[^/]*')"

echo ""
echo "--- 01_schema.sql ---"
$PSQL -f "$ROOT/sql/01_schema.sql"

echo ""
echo "--- 02_scoring.sql ---"
$PSQL -f "$ROOT/sql/02_scoring.sql"

echo ""
echo "--- 04_audit.sql ---"
$PSQL -f "$ROOT/sql/04_audit.sql"

echo ""
echo "--- 05_rls.sql ---"
$PSQL -f "$ROOT/sql/05_rls.sql"

echo ""
echo "--- 06_integrations.sql ---"
$PSQL -f "$ROOT/sql/06_integrations.sql"

echo ""
echo "=== Schéma déployé avec succès ==="
echo ""
echo "Prochaine étape — bootstrap admin (via SQL Editor Supabase) :"
echo "  INSERT INTO editors (user_id, role)"
echo "  VALUES ('<uuid-de-ton-compte-auth.users>', 'admin');"
echo ""
echo "Puis configurer frontend/config.js avec l'URL et la clé anon de ton projet."
