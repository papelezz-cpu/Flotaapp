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

# CREATE INDEX CONCURRENTLY no puede correr dentro de un bloque de transacción:
# Postgres lo rechaza con "cannot run inside a transaction block", y con
# --single-transaction eso tumba el archivo entero. Pasó con la migración
# 20260901150000, que hubo que aplicar a mano fuera de este guion.
#
# La respuesta NO es quitar --single-transaction para todos: la atomicidad es
# lo que evita que pruebas quede a medias, y vale para el 95% de los archivos.
# Se detecta el caso concreto y se avisa de lo que se pierde.
#
# La detección ignora los comentarios: esta misma migración habla de
# CONCURRENTLY en su cabecera sin usarlo, y eso no debe disparar nada.
SIN_TX=0
if grep -vE '^\s*--' "$ARCHIVO" | grep -qiE '\bCONCURRENTLY\b'; then
  SIN_TX=1
  echo "  ⚠ Este archivo usa CONCURRENTLY, que Postgres prohíbe dentro de una"
  echo "    transacción. Se aplicará SIN --single-transaction."
  echo
  echo "    Lo que eso significa: si una sentencia falla a mitad, las anteriores"
  echo "    YA quedaron aplicadas y pruebas se queda a medias. Habrá que mirar"
  echo "    qué entró y qué no, a mano."
  echo
  echo "    Si no necesitas CONCURRENTLY —y con tablas de miles de filas no hace"
  echo "    falta: el índice se construye en milisegundos— quítalo del archivo y"
  echo "    vuelve a correr esto para recuperar la atomicidad."
  echo
  read -r -p "  ¿Aplicar así, sin transacción? [s/N] " R2
  [[ "$R2" =~ ^[sS]$ ]] || { echo "  Cancelado. No se tocó nada."; exit 0; }
  echo
fi

# -f archivo (no tubería): psql lo abre en binario y respeta los CRLF que
# puedan venir dentro de un cuerpo de función. Ver replicar-produccion-a-pruebas.sh
if [ "$SIN_TX" = "1" ]; then
  psql "$CONN_PRUE" -v ON_ERROR_STOP=1 -q -o /dev/null -f "$ARCHIVO"
else
  psql "$CONN_PRUE" --single-transaction -v ON_ERROR_STOP=1 -q -o /dev/null -f "$ARCHIVO"
fi
if [ $? -eq 0 ]; then
  echo "  ✓ Aplicado."
  echo
  echo "  Ahora vuelve a verificar la paridad para dejar constancia de en qué"
  echo "  se separa pruebas de producción por este cambio:"
  echo "    bash supabase/verificar-paridad.sh --detalle"
  echo
  echo "  Y recuerda: aplicarlo a PRODUCCIÓN es una promoción aparte, con su"
  echo "  propia autorización explícita (Regla #2)."
else
  if [ "$SIN_TX" = "1" ]; then
    echo "  ✗ Falló, y este archivo corrió SIN transacción: lo que se ejecutó" >&2
    echo "    antes del error SIGUE APLICADO. Revisa qué entró antes de reintentar." >&2
  else
    echo "  ✗ Falló. La transacción revirtió: pruebas quedó como estaba." >&2
  fi
  exit 1
fi
