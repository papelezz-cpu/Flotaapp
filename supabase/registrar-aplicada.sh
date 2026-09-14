#!/usr/bin/env bash
#
# Anota en supabase/aplicadas.tsv que un archivo .sql se aplicó a un proyecto.
#
# ── Por qué existe ────────────────────────────────────────────────────────
#
# supabase/migrations/ es una carpeta de archivos y nada más. No dice cuáles
# corren en producción y cuáles en pruebas, así que la única forma de saberlo
# era preguntar a quien los aplicó o deducirlo del esquema.
#
# El sistema de paridad NO responde a esto. Responde a «¿son iguales las dos
# bases?», que es otra pregunta: dos bases pueden ser idénticas y estar las dos
# sin una migración.
#
# ── Por qué se guarda el hash ─────────────────────────────────────────────
#
# Porque un archivo de migración se puede editar DESPUÉS de aplicarse, y
# entonces el nombre ya no identifica lo que entró. Pasó el 2026-09-11:
# 20260911140000 falló, se corrigió el archivo y se volvió a aplicar. Sin el
# hash, el registro diría «aplicada» y no habría forma de saber cuál de las dos
# versiones está dentro.
#
# Con el hash, `estado-migraciones.sh` distingue tres cosas: aplicada y sin
# tocar, aplicada pero el archivo cambió después, y sin aplicar.
#
# Uso (normalmente lo llaman solos aplicar-a-pruebas.sh y aplicar-a-produccion.sh):
#   bash supabase/registrar-aplicada.sh <pruebas|produccion> <ref-proyecto> <archivo.sql> [...]
#
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$AQUI/.." && pwd)"
LIBRO="$AQUI/aplicadas.tsv"

ENTORNO="${1:-}"
REF="${2:-}"
shift 2 2>/dev/null || true

if [ -z "$ENTORNO" ] || [ -z "$REF" ] || [ $# -eq 0 ]; then
  echo "Uso: bash supabase/registrar-aplicada.sh <pruebas|produccion> <ref> <archivo.sql> [...]" >&2
  exit 2
fi

if [ ! -f "$LIBRO" ]; then
  {
    printf '# Libro mayor de migraciones aplicadas.\n'
    printf '#\n'
    printf '# Una línea por (archivo, proyecto). Lo escriben aplicar-a-pruebas.sh y\n'
    printf '# aplicar-a-produccion.sh al terminar bien; no se edita a mano.\n'
    printf '#\n'
    printf '# ⚠ Las migraciones ANTERIORES a la creación de este archivo no están\n'
    printf '#   registradas: no se sabe cuáles corren dónde, y por eso existe esto.\n'
    printf '#   Lo de aquí es fiable; la ausencia de una línea no prueba nada sobre\n'
    printf '#   lo anterior al 2026-09-11.\n'
    printf '#\n'
    printf '# fecha_utc\tentorno\tproyecto_ref\tarchivo\tsha256\n'
  } > "$LIBRO"
fi

AHORA="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

for ARCHIVO in "$@"; do
  [ -f "$ARCHIVO" ] || { echo "  ⚠ No existe, no se registra: $ARCHIVO" >&2; continue; }

  # Ruta relativa a la raíz del repo, para que el libro no dependa de dónde se
  # ejecutó el guion.
  REL="$(cd "$(dirname "$ARCHIVO")" && pwd)/$(basename "$ARCHIVO")"
  REL="${REL#$RAIZ/}"

  SHA="$(sha256sum "$ARCHIVO" | cut -d' ' -f1)"

  # Una sola línea viva por (archivo, entorno, proyecto): si se vuelve a
  # aplicar —porque falló y se corrigió— gana la última.
  TMP="$(mktemp)"
  awk -F'\t' -v rel="$REL" -v ent="$ENTORNO" -v ref="$REF" \
    '/^#/ { print; next } !($2 == ent && $3 == ref && $4 == rel) { print }' \
    "$LIBRO" > "$TMP"
  printf '%s\t%s\t%s\t%s\t%s\n' "$AHORA" "$ENTORNO" "$REF" "$REL" "$SHA" >> "$TMP"
  mv "$TMP" "$LIBRO"

  echo "  · registrada en el libro: $(basename "$REL") → $ENTORNO"
done

echo
echo "  Libro mayor: supabase/aplicadas.tsv — commitéalo junto con la migración."
