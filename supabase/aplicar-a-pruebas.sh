#!/usr/bin/env bash
#
# Aplica un archivo .sql al proyecto de PRUEBAS y solo a él.
#
# Existe porque aplicar-migraciones.sh apunta a producción, y el flujo normal
# (Regla #2) es al revés: primero pruebas, se verifica, y ahí se para. Sin un
# guion para el lado seguro, la tentación es usar el de producción "con
# cuidado", que es como se cometen los accidentes.
#
# Todo va en UNA transacción: si algo falla, revierte entero y pruebas se queda
# como estaba, no a medias.
#
# Uso:
#   bash supabase/aplicar-a-pruebas.sh supabase/migrations/2026...sql
#
set -uo pipefail

REF_PRODUCCION="xnyqsewaluezkkrlyhxg"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ARCHIVO="${1:-}"
if [ -z "$ARCHIVO" ] || [ ! -f "$ARCHIVO" ]; then
  echo "Uso: bash supabase/aplicar-a-pruebas.sh <archivo.sql>" >&2
  exit 2
fi

export PGCLIENTENCODING=UTF8
source "$AQUI/lib-conexion.sh"

if [ -n "${PORTGO_DB_URL_PRUEBAS:-}" ]; then
  CONN_PRUE="$PORTGO_DB_URL_PRUEBAS"
else
  conectar_a "el proyecto DE PRUEBAS" "<ref-de-pruebas>" PORTGO_DB_URL_PRUEBAS || exit 1
  CONN_PRUE="$(cadena_autonoma "$CONN")"; unset PGPASSWORD
fi

# El candado, antes de escribir nada.
if [[ "$CONN_PRUE" == *"$REF_PRODUCCION"* ]]; then
  echo "❌ ALTO: esa cadena es la de PRODUCCIÓN ($REF_PRODUCCION)." >&2
  echo "   Este guion no corre contra producción. Cancelado." >&2
  exit 2
fi

echo
echo "── Se va a aplicar a PRUEBAS ──"
echo "   archivo: $ARCHIVO"
echo "   destino: $(s="${CONN_PRUE#*://}"; s="${s#*@}"; echo "${s%%/*}")"
echo
echo "── Lo que contiene ──"
grep -vE '^\s*(--)?\s*$' "$ARCHIVO" | grep -v '^\s*--' | sed 's/^/   /'
echo

read -r -p "  ¿Aplicar? [s/N] " R
[[ "$R" =~ ^[sS]$ ]] || { echo "  Cancelado. No se tocó nada."; exit 0; }

# -f archivo (no tubería): psql lo abre en binario y respeta los CRLF que
# puedan venir dentro de un cuerpo de función. Ver replicar-produccion-a-pruebas.sh
if psql "$CONN_PRUE" --single-transaction -v ON_ERROR_STOP=1 -q -o /dev/null -f "$ARCHIVO"; then
  echo "  ✓ Aplicado."
  echo
  echo "  Ahora vuelve a verificar la paridad para dejar constancia de en qué"
  echo "  se separa pruebas de producción por este cambio:"
  echo "    bash supabase/verificar-paridad.sh --detalle"
  echo
  echo "  Y recuerda: aplicarlo a PRODUCCIÓN es una promoción aparte, con su"
  echo "  propia autorización explícita (Regla #2)."
else
  echo "  ✗ Falló. La transacción revirtió: pruebas quedó como estaba." >&2
  exit 1
fi
