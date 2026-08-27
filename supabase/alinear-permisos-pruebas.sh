#!/usr/bin/env bash
# Alinea los permisos de FUNCIONES de portgo-pruebas con los de PRODUCCION.
#
#   PORTGO_DB_URL_PROD="postgresql://...xnyq..." \
#   PORTGO_DB_URL_PRUEBAS="postgresql://...xskg..." \
#   ./supabase/alinear-permisos-pruebas.sh [--solo-ver]
#
# ── POR QUE HACE FALTA ESTO ────────────────────────────────────────────────
#
# Los dos proyectos tienen ALTER DEFAULT PRIVILEGES concediendo EXECUTE a
# anon, authenticated y service_role sobre CUALQUIER funcion nueva de public
# (lo pone Supabase de fabrica, a nombre de supabase_admin y de postgres).
#
# Consecuencia: cuando preparar-pruebas.sh aplica el volcado, cada
# CREATE FUNCTION nace concedida a anon y authenticated. El volcado solo trae
# "REVOKE ... FROM PUBLIC", que NO deshace esas concesiones explicitas — y no
# trae los REVOKE a anon/authenticated porque en produccion esas concesiones
# ya no existen, asi que pg_dump no tiene nada que emitir.
#
# Resultado: pruebas queda SIEMPRE mas permisiva que produccion, por mucho que
# la siembra "funcione". Comprobado el 2026-08-27: 82 desajustes de permisos
# entre las dos bases, con notificar_superadmins abierta a anon en pruebas y
# cerrada en produccion.
#
# Este guion lee el estado REAL de produccion y lo replica. Hay que correrlo:
#   · despues de cada preparar-pruebas.sh
#   · despues de aplicar a pruebas cualquier migracion que cree funciones
#
# ── OJO CON PRODUCCION ─────────────────────────────────────────────────────
# El mismo ALTER DEFAULT PRIVILEGES rige en produccion. Toda migracion que
# cree una funcion nueva alli la deja ejecutable por anon salvo que la propia
# migracion revoque. Las migraciones nuevas deben terminar con:
#   REVOKE ALL ON FUNCTION public.<fn>(<args>) FROM PUBLIC, anon, authenticated;
#   GRANT EXECUTE ON FUNCTION public.<fn>(<args>) TO authenticated;  -- si aplica
#
# Este guion NO escribe nada en produccion: solo la lee.
set -uo pipefail

PROD="${PORTGO_DB_URL_PROD:-}"
PRUE="${PORTGO_DB_URL_PRUEBAS:-}"
SOLO_VER=0
[ "${1:-}" = "--solo-ver" ] && SOLO_VER=1

if [ -z "$PROD" ] || [ -z "$PRUE" ]; then
  echo "Faltan PORTGO_DB_URL_PROD y/o PORTGO_DB_URL_PRUEBAS." >&2
  echo "  Supabase -> proyecto -> Connect -> Session pooler -> URI (puerto 5432)" >&2
  exit 1
fi

_host() { local s="${1#*://}"; s="${s#*@}"; echo "${s%%/*}"; }
echo "── Origen (solo lectura): $(_host "$PROD")"
echo "── Destino:               $(_host "$PRUE")"
echo

for par in "PRODUCCION:$PROD" "PRUEBAS:$PRUE"; do
  if ! psql "${par#*:}" -Atc "select 1" >/dev/null 2>&1; then
    echo "No se pudo conectar a ${par%%:*}." >&2; exit 1
  fi
done

# Salvaguarda: si las dos cadenas apuntan al mismo sitio, abortar. Escribir
# los "permisos de produccion" sobre produccion seria inofensivo, pero que el
# guion se lo crea significa que alguien se equivoco de cadena.
if [ "$(_host "$PROD")" = "$(_host "$PRUE")" ]; then
  echo "ALTO: origen y destino son el mismo host. Revisa las cadenas." >&2; exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# PUBLIC primero: anon y authenticated son miembros de PUBLIC, asi que
# revocarles a ellos sin revocar a PUBLIC puede no quitar nada.
{
  psql "$PROD" -Atc "
    select 'REVOKE EXECUTE ON FUNCTION public.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||') FROM PUBLIC;'
      from pg_proc p where p.pronamespace='public'::regnamespace order by p.proname"
  psql "$PROD" -Atc "
    select case when has_function_privilege(r, p.oid, 'EXECUTE')
                then 'GRANT EXECUTE ON FUNCTION public.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||') TO '||r||';'
                else 'REVOKE EXECUTE ON FUNCTION public.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||') FROM '||r||';'
           end
      from pg_proc p, unnest(array['anon','authenticated','service_role']) r
     where p.pronamespace='public'::regnamespace order by p.proname, r"
} > "$TMP"

echo "   sentencias generadas desde produccion: $(grep -c ';' "$TMP")"

if [ "$SOLO_VER" = "1" ]; then
  echo; echo "── --solo-ver: no se aplica nada ──"; cat "$TMP"; exit 0
fi

# Solo se aplican las que afectan a funciones que existan en el destino.
# Pruebas puede ir por delante (migraciones aun sin promover): esas funciones
# conservan los permisos que les puso su propia migracion.
if psql "$PRUE" -v ON_ERROR_STOP=1 -q -f "$TMP"; then
  echo "   ✓ aplicadas a pruebas"
else
  echo "   ✗ Fallo al aplicar. Lo mas probable: una funcion que existe en" >&2
  echo "     produccion y todavia no en pruebas. Aplica antes las migraciones." >&2
  exit 1
fi

echo
echo "══ COMPROBACION ══"
Q="select p.proname||'('||pg_get_function_identity_arguments(p.oid)||')|'||r||'|'||has_function_privilege(r,p.oid,'EXECUTE')
     from pg_proc p, unnest(array['anon','authenticated','service_role']) r
    where p.pronamespace='public'::regnamespace order by 1"
A="$(mktemp)"; B="$(mktemp)"; trap 'rm -f "$TMP" "$A" "$B"' EXIT
psql "$PROD" -Atc "$Q" | sort > "$A"
psql "$PRUE" -Atc "$Q" | sort > "$B"
RESTO="$(comm -13 "$A" "$B" | cut -d'|' -f1 | sort -u)"
if [ -z "$RESTO" ]; then
  echo "   ✓ Los permisos de funcion son identicos en las dos bases."
else
  echo "   Funciones que solo existen en pruebas (normal si hay migraciones"
  echo "   sin promover; sus permisos los fija su propia migracion):"
  echo "$RESTO" | sed 's/^/     /'
fi
