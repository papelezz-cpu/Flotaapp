#!/usr/bin/env bash
#
# Rehace el banco local desde cero con el esquema de producción.
#
# ── Por qué existe ──────────────────────────────────────────────────────────
#
# El 2026-09-19 se intentó comprobar que el bloque de verificación de una
# migración sabía FALLAR, saboteándola a propósito. Pasó en verde las dos
# veces — y no porque el bloque estuviera bien, sino porque la corrida buena
# anterior ya había dejado el permiso como debía y la migración no lo deshace.
# Se estaba probando sobre un banco sucio: el estado sobreviviente contestaba
# por la migración.
#
# Una migración solo se prueba de verdad desde el estado ANTERIOR a ella.
#
# Uso:  bash pruebas/banco-local/rehacer-banco.sh [nombre_bd]
#
# No toca ninguna base remota. Solo el Postgres local.
set -uo pipefail

BD="${1:-portgo_h04}"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$AQUI/../.." && pwd)"
ESQUEMA="$RAIZ/supabase/espejo/01-esquema-public.sql"

[ -f "$ESQUEMA" ] || { echo "❌ Falta $ESQUEMA (volcado de producción, gitignored)." >&2; exit 2; }

export PGCLIENTENCODING=UTF8
psql -U postgres -d postgres -q -c "drop database if exists $BD;" -c "create database $BD;" || exit 1

for r in anon authenticated service_role supabase_admin authenticator \
         supabase_auth_admin supabase_storage_admin dashboard_user pgbouncer; do
  psql -U postgres -d "$BD" -q -c "create role $r;" 2>/dev/null
done

psql -U postgres -d "$BD" -q <<'SQL'
create schema if not exists auth;
create schema if not exists storage;
create schema if not exists extensions;
create extension if not exists pgcrypto;
create table auth.users (id uuid primary key default gen_random_uuid(), email text);

-- Sustitutos de lo que Supabase pone y un Postgres desnudo no tiene. auth.uid()
-- se lee de una variable de sesión, así que se puede simular a cualquier
-- usuario con:  set request.jwt.claim.sub = '<uuid>';
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create or replace function auth.role() returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'authenticated') $$;
SQL

# Extensiones que el esquema necesita ANTES de cargarse. btree_gist es
# obligatoria: sin ella `reservaciones_sin_solape` —el EXCLUDE con GiST sobre
# `unidad text`— no se puede crear, y el banco quedaba SIN la protección contra
# doble reserva sin decir nada. Se descubrió el 2026-09-25 al ir a probar H-06.
EXT="$RAIZ/supabase/espejo/09b-extensiones-public.sql"
[ -f "$EXT" ] && psql -U postgres -d "$BD" -q -f "$EXT" 2>/dev/null

psql -U postgres -d "$BD" -q -f "$ESQUEMA" > /tmp/carga-banco.log 2>&1
# `grep -c '^ERROR'` NO funciona, y este guion lo usó hasta el 2026-09-25: psql
# prefija cada error con `psql:<archivo>:<linea>: `, así que el ancla de
# principio de línea nunca casaba y el contador daba 0 SIEMPRE. La guarda de
# abajo no salto ni una vez, y el banco se daba por limpio con el EXCLUDE sin
# crear. Un contador que solo sabe decir cero no es un contador.
ERRS=$(grep -cE '(^|: )ERROR:' /tmp/carga-banco.log || true)
# «schema public already exists» sale siempre y es inofensivo: el `create schema
# if not exists` de arriba ya lo creó. Se descuenta para que la guarda sirva.
ERRS=$(( ERRS - $(grep -cE 'ERROR:  schema "public" already exists' /tmp/carga-banco.log || true) ))
TABLAS=$(psql -U postgres -d "$BD" -tAc "select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE';")

echo "  banco $BD rehecho · $TABLAS tablas · $ERRS errores de carga"
[ "$ERRS" -eq 0 ] || { echo "  ⚠ hubo errores, míralos en /tmp/carga-banco.log" >&2; exit 1; }
