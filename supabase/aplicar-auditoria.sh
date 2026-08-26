#!/usr/bin/env bash
# Aplica el lote de la Fase 1 de la auditoría y comprueba el resultado.
#
#   PORTGO_DB_URL="postgresql://..." ./supabase/aplicar-auditoria.sh
#
# Solo AÑADE objetos: tablas, índices y restricciones. No borra nada.
# Es reejecutable: si algo falla a mitad, se corrige y se vuelve a pasar.
#
# Las dos migraciones son independientes entre sí, pero se aplican en orden
# de fecha para que el historial quede coherente.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONN="${PORTGO_DB_URL:-}"

if [ -z "$CONN" ]; then
  echo "Falta PORTGO_DB_URL." >&2
  echo "  Supabase → proyecto → Connect → Session pooler → URI (puerto 5432)" >&2
  exit 1
fi

# Nunca imprimir la contraseña: solo host y usuario, para saber a dónde va.
_sin_esquema="${CONN#*://}"
echo "── Destino ──"
echo "   usuario: ${_sin_esquema%%:*}"
_resto="${_sin_esquema#*@}"
echo "   host:    ${_resto%%/*}"
echo

if ! psql "$CONN" -Atc "select 1" >/dev/null 2>&1; then
  echo "No se pudo conectar. Revisa la cadena (debe ser Session pooler, puerto 5432)." >&2
  exit 1
fi
echo "   Conexión OK · base: $(psql "$CONN" -Atc "select current_database()")"
echo

MIGRACIONES=(
  "20260728160000_consentimientos_y_arco.sql"
  "20260826120000_auditoria_indices_e_integridad.sql"
)

FALLOS=0
for m in "${MIGRACIONES[@]}"; do
  echo "── Aplicando $m ──"
  # ON_ERROR_STOP aborta al primer error en vez de seguir dejando a medias.
  # Sin --single-transaction: CREATE INDEX CONCURRENTLY no puede ir dentro
  # de un bloque de transacción.
  if psql "$CONN" -v ON_ERROR_STOP=1 -f "$RAIZ/supabase/migrations/$m"; then
    echo "   ✓ aplicada"
  else
    echo "   ✗ FALLÓ" >&2
    FALLOS=$((FALLOS + 1))
  fi
  echo
done

# ── Comprobación del resultado ────────────────────────────────────────────
echo "══ COMPROBACIÓN ══"
echo

echo "── Índices inválidos (los deja un CONCURRENTLY que falló) ──"
# El SQL que va con -c se manda en ASCII puro a proposito: en Windows, psql
# entrega los acentos con otra codificacion y el servidor los rechaza
# ("invalid byte sequence for encoding UTF8"). Los acentos van en los echo.
psql "$CONN" -Atc "
  select '   INVALIDO: ' || c.relname
    from pg_index i join pg_class c on c.oid = i.indexrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and not i.indisvalid;"
echo "   (sin líneas arriba = ninguno; si aparece alguno hay que eliminarlo y rehacerlo)"
echo

echo "── Índices por tabla ──"
psql "$CONN" -c "
  select tablename as tabla, count(*) as indices
    from pg_indexes where schemaname = 'public'
   group by 1 order by 2 desc, 1;"

echo "── Restricciones nuevas de reservaciones ──"
psql "$CONN" -c "
  select conname as restriccion,
         case when convalidated then 'validada' else 'NOT VALID (solo filas nuevas)' end as estado
    from pg_constraint
   where conrelid = 'public.reservaciones'::regclass and contype = 'c'
   order by conname;"

echo "── Tablas de consentimientos y ARCO ──"
psql "$CONN" -c "
  select tablename as tabla,
         (select count(*) from pg_policies p
           where p.schemaname='public' and p.tablename=t.tablename) as politicas,
         (select count(*) from pg_indexes i
           where i.schemaname='public' and i.tablename=t.tablename) as indices
    from pg_tables t
   where schemaname='public' and tablename in ('consentimientos','solicitudes_arco')
   order by 1;"

echo
if [ "$FALLOS" -eq 0 ]; then
  echo "✓ Las ${#MIGRACIONES[@]} migraciones se aplicaron sin errores."
else
  echo "✗ $FALLOS migración(es) fallaron. Revisa la salida de arriba." >&2
  exit 1
fi
