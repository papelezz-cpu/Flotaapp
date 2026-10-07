#!/usr/bin/env bash
#
# Mide producción: dónde se va el tiempo de la base, qué índices se usan,
# cómo se usa cada tabla, conexiones y Realtime. Las consultas están en
# medir-produccion.sql, al lado.
#
# Existe porque desde la 2ª auditoría (28/08) nadie pudo volver a medir: el
# 84 % de CPU atribuido a Realtime (A2-C1) y los índices sobrantes (H-17)
# siguen siendo hipótesis. docs/AUDITORIA.md §6.
#
# ⚠ SOLO LEE. La sesión se pone en default_transaction_read_only=on y el
#   guion lo comprueba ANTES de correr una sola consulta: si no quedó puesto,
#   aborta. Cualquier escritura fallaría con "read-only transaction".
#
# La salida va a supabase/espejo/medicion-<fecha>.txt (fuera de Git, como el
# resto de espejo/). No lleva datos personales —consultas normalizadas y
# recuentos—, pero tampoco hay motivo para publicarla.
#
# Uso, en Git Bash y en una línea (con `source supabase/sesion-conexiones.sh
# produccion` hecho antes no pide la cadena):
#   bash supabase/medir-produccion.sh
#
set -euo pipefail

REF="xnyqsewaluezkkrlyhxg"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL="$RAIZ/supabase/medir-produccion.sql"
mkdir -p "$RAIZ/supabase/espejo"
SALIDA="$RAIZ/supabase/espejo/medicion-$(date -u +%Y%m%d-%H%M).txt"

export PGCLIENTENCODING=UTF8

if ! command -v psql >/dev/null 2>&1; then
  echo "❌ No encontré psql (en este equipo: ~/scoop/apps/postgresql/current/bin)."
  exit 1
fi

echo "──────────────────────────────────────────────────────────"
echo " PortGo · medir producción   (solo lectura)"
echo " Proyecto: $REF"
echo "──────────────────────────────────────────────────────────"
echo

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-conexion.sh"
conectar_a "PRODUCCIÓN" "$REF" "PORTGO_DB_URL_PROD" || exit 1

# Que la cadena sea de producción y no de pruebas: medir pruebas y creer que
# es producción es el error que la Regla #3 describe. Las dos bases tienen
# los mismos datos; las estadísticas no.
case "$CONN" in
  *"$REF"*) ;;
  *) echo "❌ La cadena no es de producción ($REF). No mido otra base con este nombre."; exit 1 ;;
esac

# Solo lectura con un SET dentro de la sesión, NO con PGOPTIONS: el pooler de
# Supabase descarta las opciones de arranque y la sesión llegaba en
# read_only=off (medido el 07/10, el guion se negó a seguir, que era lo
# correcto). Esta comprobación es de una sesión aparte; la que mide repite el
# SET y vuelve a comprobarlo en el .sql antes de la primera consulta.
RO="$(psql "$CONN" -X -q -At -c "set default_transaction_read_only = on" -c "show default_transaction_read_only" 2>&1)" || {
  echo "❌ No pude conectar: $RO"; exit 1; }
if [ "$RO" != "on" ]; then
  echo "❌ La sesión no quedó en solo lectura (default_transaction_read_only=$RO). No sigo."
  exit 1
fi
echo "✓ Sesión en solo lectura. Midiendo…"
echo

{
  echo "# PortGo · medición de producción ($REF)"
  echo "# $(date -u '+%Y-%m-%d %H:%M UTC') · default_transaction_read_only=$RO"
  psql "$CONN" -X -v ON_ERROR_STOP=0 -f "$SQL" 2>&1
} | tee "$SALIDA"

echo
echo "✓ Guardado en ${SALIDA#$RAIZ/}"
echo "  Si alguna sección dice ERROR (permisos), el resto sigue valiendo: dímelo y lo veo."
