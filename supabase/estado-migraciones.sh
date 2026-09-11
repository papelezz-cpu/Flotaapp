#!/usr/bin/env bash
#
# Dice qué migración está aplicada en qué proyecto, leyendo supabase/aplicadas.tsv.
#
# No toca ninguna base de datos: es un diff entre la carpeta de migraciones y el
# libro mayor. Por eso es instantáneo y se puede correr siempre.
#
#   bash supabase/estado-migraciones.sh              # las dos columnas
#   bash supabase/estado-migraciones.sh pruebas      # solo una
#
# Tres estados por archivo y entorno:
#
#   ✓  aplicada, y el archivo no ha cambiado desde entonces
#   ≠  aplicada, pero el archivo CAMBIÓ después — lo que corre en la base no es
#      lo que dice el repositorio. Hay que mirarlo.
#   ·  sin aplicar, o aplicada antes de que existiera el libro (2026-09-11)
#
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$AQUI/.." && pwd)"
LIBRO="$AQUI/aplicadas.tsv"
FILTRO="${1:-}"

cd "$RAIZ"

if [ ! -f "$LIBRO" ]; then
  echo "No hay libro mayor todavía ($LIBRO)." >&2
  echo "Se crea solo la primera vez que apliques algo con aplicar-a-pruebas.sh" >&2
  echo "o aplicar-a-produccion.sh." >&2
  exit 1
fi

estado_de() {           # $1 = archivo relativo, $2 = entorno
  local rel="$1" ent="$2" linea sha_libro sha_hoy
  linea="$(awk -F'\t' -v rel="$rel" -v ent="$ent" \
           '!/^#/ && $2 == ent && $4 == rel { l = $0 } END { print l }' "$LIBRO")"
  [ -z "$linea" ] && { printf '·'; return; }
  sha_libro="$(printf '%s' "$linea" | cut -f5)"
  sha_hoy="$(sha256sum "$rel" | cut -d' ' -f1)"
  if [ "$sha_libro" = "$sha_hoy" ]; then printf '✓'; else printf '≠'; fi
}

printf '\n  Estado de las migraciones — según %s\n\n' "supabase/aplicadas.tsv"
# Ancho fijo y no %-Ns para las filas: printf cuenta BYTES, y ✓ / ≠ / · ocupan
# varios en UTF-8, así que las columnas se descuadraban. La cabecera va sin
# acentos ni caracteres de dibujo por el mismo motivo.
printf '  %-9s%-12s%s\n' "PRUEBAS" "PRODUCCION" "ARCHIVO"
printf '  %-9s%-12s%s\n' "-------" "----------" "-------"

n_pru=0; n_prod=0; n_dif=0; n_total=0
for f in supabase/migrations/*.sql; do
  n_total=$((n_total + 1))
  e_pru="$(estado_de "$f" pruebas)"
  e_prod="$(estado_de "$f" produccion)"
  [ "$e_pru"  = "✓" ] && n_pru=$((n_pru + 1))
  [ "$e_prod" = "✓" ] && n_prod=$((n_prod + 1))
  { [ "$e_pru" = "≠" ] || [ "$e_prod" = "≠" ]; } && n_dif=$((n_dif + 1))

  if [ -n "$FILTRO" ]; then
    case "$FILTRO" in
      pruebas)    [ "$e_pru"  = "·" ] || continue ;;
      produccion) [ "$e_prod" = "·" ] || continue ;;
    esac
  fi
  # Un símbolo + relleno explícito: ver la nota de la cabecera.
  printf '  %s        %s           %s\n' "$e_pru" "$e_prod" "$(basename "$f")"
done

printf '\n  %s de %s registradas en pruebas · %s en producción' "$n_pru" "$n_total" "$n_prod"
[ "$n_dif" -gt 0 ] && printf ' · ⚠ %s con el archivo cambiado tras aplicarse' "$n_dif"
printf '\n\n'

printf '  Un · no significa "sin aplicar": las anteriores al 2026-09-11 no se\n'
printf '  registraron nunca, porque el libro no existía. Solo lo marcado con ✓ o ≠\n'
printf '  está verificado.\n\n'
