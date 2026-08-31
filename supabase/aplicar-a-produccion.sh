#!/usr/bin/env bash
#
# Aplica uno o varios .sql a PRODUCCIÓN. La pareja de aplicar-a-pruebas.sh, con
# el candado al revés: aquí se EXIGE que la cadena sea la de producción, para
# que nadie aplique "a producción" contra otra base creyendo que sí.
#
# ⚠ REGLA #2. Esto no se corre porque el cambio parezca inofensivo ni porque
#   haya pasado en pruebas. Se corre cuando el usuario lo ha autorizado para
#   ESE cambio concreto, sabiendo qué se aplica, qué se verificó y qué no.
#   Pasar en portgo-pruebas es el permiso para PREGUNTAR, no para aplicar.
#
# Todo va en UNA transacción, aunque sean varios archivos: o entra el conjunto
# o no entra nada. Un cambio de RLS a medias deja huecos abiertos.
#
# Uso:
#   bash supabase/aplicar-a-produccion.sh archivo1.sql [archivo2.sql ...]
#
set -uo pipefail

REF_PRODUCCION="xnyqsewaluezkkrlyhxg"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$#" -gt 0 ] || { echo "Uso: bash supabase/aplicar-a-produccion.sh <archivo.sql> [...]" >&2; exit 2; }
for f in "$@"; do
  [ -f "$f" ] || { echo "No existe: $f" >&2; exit 2; }
done

export PGCLIENTENCODING=UTF8
source "$AQUI/lib-conexion.sh"

if [ -n "${PORTGO_DB_URL_PROD:-}" ]; then
  CONN_PROD="$PORTGO_DB_URL_PROD"
else
  conectar_a "PRODUCCIÓN" "$REF_PRODUCCION" PORTGO_DB_URL_PROD || exit 1
  CONN_PROD="$(cadena_autonoma "$CONN")"; unset PGPASSWORD
fi

# El candado invertido: si NO es producción, no es lo que se pidió aplicar.
if [[ "$CONN_PROD" != *"$REF_PRODUCCION"* ]]; then
  echo "❌ ALTO: esa cadena no es la de producción ($REF_PRODUCCION)." >&2
  echo "   Para el proyecto de pruebas está supabase/aplicar-a-pruebas.sh." >&2
  exit 2
fi

echo
echo "══════════════════════════════════════════════════════════════════"
echo " SE VA A ESCRIBIR EN PRODUCCIÓN"
echo "   destino: $(s="${CONN_PROD#*://}"; s="${s#*@}"; echo "${s%%/*}")"
echo "   archivos: $#"
echo "══════════════════════════════════════════════════════════════════"
for f in "$@"; do
  echo
  echo "── $f ──"
  grep -vE '^\s*--|^\s*$' "$f" | sed 's/^/   /'
done
echo
echo "  Todo esto va en UNA transacción: entra completo o no entra nada."
echo

read -r -p "  Escribe APLICAR A PRODUCCION para continuar: " OK
# El acento se quita ANTES de mayusculizar: tr trabaja por bytes y a la "ó"
# (dos bytes en UTF-8) la deja intacta, así que después ya no hay forma de
# reconocerla. Escribir "producción" bien acentuado no puede ser el motivo de
# que una autorización real no se registre.
OK="$(printf '%s' "$OK" | tr -d '\r' | sed 's/ó/o/g; s/Ó/O/g' | tr '[:lower:]' '[:upper:]' \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]]\{1,\}/ /g')"
if [ "$OK" != "APLICAR A PRODUCCION" ]; then echo "  Cancelado. No se tocó nada."; exit 0; fi
echo

# -f por archivo dentro de una sola sesión con --single-transaction: psql abre
# cada archivo en binario y respeta los CRLF que puedan vivir dentro de un
# cuerpo de función. Ver replicar-produccion-a-pruebas.sh.
ARGS=()
for f in "$@"; do ARGS+=(-f "$f"); done

if psql "$CONN_PROD" --single-transaction -v ON_ERROR_STOP=1 -q -o /dev/null "${ARGS[@]}"; then
  echo "  ✓ Aplicado a producción."
  echo
  echo "  Comprueba que producción y pruebas volvieron a coincidir:"
  echo "    bash supabase/verificar-paridad.sh --detalle"
else
  echo "  ✗ Falló. La transacción revirtió: producción quedó como estaba." >&2
  exit 1
fi
