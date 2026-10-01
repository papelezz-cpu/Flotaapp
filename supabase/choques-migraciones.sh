#!/usr/bin/env bash
#
# ¿Esta migración choca con el trabajo de otra persona que aún no llegó a
# producción?
#
# ── Por qué existe ──────────────────────────────────────────────────────────
#
# Dos personas trabajan a la vez sobre PortGo, las dos empiezan en `dev` y
# promueven después. El libro mayor (aplicadas.tsv) dice QUÉ se aplicó DÓNDE,
# pero no impide nada. El 2026-09-29/30 pasó, en dos días:
#   · dos migraciones con el mismo número (…140000 y …120000);
#   · objetos compartidos (perfiles, pedidos, ofertas, sus guards) tocados por
#     las dos personas con horas de diferencia.
# El choque que más duele no da error: si dos migraciones reescriben la misma
# función, gana la última que se aplica y el cambio de la otra desaparece en
# silencio.
#
# ── Qué hace ────────────────────────────────────────────────────────────────
#
# Para cada archivo dado, saca los objetos que toca y los cruza con las
# migraciones PENDIENTES DE PROMOVER — las que el libro mayor tiene en pruebas
# y no en producción, más las escritas y sin aplicar en ninguna parte (desde
# 2026-09-11, cuando empieza el libro). Avisa de:
#   · CHOQUE  — el mismo objeto (función, trigger, política, índice,
#               restricción, permiso o definición de tabla);
#   · ZONA    — la misma tabla, tocada de cualquier forma (más débil: puede no
#               ser nada, pero conviene mirarlo);
#   · NÚMERO  — dos migraciones con el mismo prefijo de 14 dígitos.
#
# ⚠ SOLO LEE archivos del repositorio. No se conecta a ninguna base.
# ⚠ Es un aviso, no una garantía: no ve el SQL que se arma en tiempo de
#   ejecución (EXECUTE format(...)) ni lo que una función toca por dentro más
#   allá de nombrar tablas. Que no avise no prueba que no haya choque.
#
# Uso:
#   bash supabase/choques-migraciones.sh supabase/migrations/2026...sql [...]
#
# Sale con 0 si no hay nada que avisar y con 1 si hay algún aviso. Lo llaman
# aplicar-a-pruebas.sh y aplicar-a-produccion.sh antes de pedir confirmación.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$AQUI/.." && pwd)"
LIBRO="$AQUI/aplicadas.tsv"
MIG_DIR="supabase/migrations"
DESDE_LIBRO="20260911"   # antes de esto, «sin fila en el libro» no significa «pendiente»

[ "$#" -gt 0 ] || { echo "Uso: bash supabase/choques-migraciones.sh <archivo.sql> [...]" >&2; exit 2; }

# Rutas relativas a la raíz del repo, que es como las guarda el libro.
rel() { local p="$1"; p="${p#./}"; p="${p#"$RAIZ"/}"; echo "$p"; }

declare -A OBJETIVO=()
for f in "$@"; do
  [ -f "$f" ] || [ -f "$RAIZ/$f" ] || { echo "No existe: $f" >&2; exit 2; }
  OBJETIVO["$(rel "$f")"]=1
done

# ── Los objetos que toca un .sql ─────────────────────────────────────────────
# Imprime una clave por línea:  obj:<tipo>:<nombre>   o   tabla:<nombre>
objetos() {
  sed -e 's/--.*$//' "$1" | tr -d '\r' | tr '[:upper:]' '[:lower:]' | gawk '
    BEGIN { RS = ";" }
    {
      s = $0; gsub(/[\n\t]+/, " ", s); gsub(/  +/, " ", s); gsub(/"/, "", s)
      t = s
      while (match(t, /(create( or replace)?|alter|drop) function( if exists)? (public\.)?([a-z0-9_]+)/, m)) {
        print "obj:funcion:" m[5]; t = substr(t, RSTART + RLENGTH) }
      t = s
      while (match(t, /public\.([a-z0-9_]+)\([^)]*\)'"'"'::regprocedure/, m)) {
        print "obj:funcion:" m[1]; t = substr(t, RSTART + RLENGTH) }
      t = s
      while (match(t, /(create( or replace)?|alter|drop) trigger( if exists)? ([a-z0-9_]+)[^;]* on (public\.)?([a-z0-9_]+)/, m)) {
        print "obj:trigger:" m[4] "@" m[6]; print "tabla:" m[6]; t = substr(t, RSTART + RLENGTH) }
      t = s
      while (match(t, /(create|alter|drop|comment on) policy( if exists)? ([^ ]+) on (public\.)?([a-z0-9_]+)/, m)) {
        print "obj:politica:" m[3] "@" m[5]; print "tabla:" m[5]; t = substr(t, RSTART + RLENGTH) }
      t = s
      while (match(t, /(create|alter|drop) table( if (not )?exists)?( only)? (public\.)?([a-z0-9_]+)/, m)) {
        # Crear o borrar la tabla es el objeto; alterarla (añadir columnas,
        # restricciones...) solo es zona: dos ALTER distintos no se pisan.
        if (m[1] != "alter") print "obj:tabla:" m[6]
        print "tabla:" m[6]; t = substr(t, RSTART + RLENGTH) }
      t = s
      while (match(t, /create (unique )?index( if not exists)? ([a-z0-9_]+) on (public\.)?([a-z0-9_]+)/, m)) {
        print "obj:indice:" m[3]; print "tabla:" m[5]; t = substr(t, RSTART + RLENGTH) }
      t = s
      while (match(t, /add constraint ([a-z0-9_]+)/, m)) {
        print "obj:restriccion:" m[1]; t = substr(t, RSTART + RLENGTH) }
      t = s
      while (match(t, /(grant|revoke) [a-z, ]+ on (table |function )?(public\.)?([a-z0-9_]+)/, m)) {
        print "obj:permiso:" m[4]; t = substr(t, RSTART + RLENGTH) }
      t = s
      while (match(t, /(insert into|update|delete from) (only )?(public\.)?([a-z0-9_]+)/, m)) {
        if (m[4] !~ /^(set|q[0-9]+_|v_)/) print "tabla:" m[4]; t = substr(t, RSTART + RLENGTH) }
    }' | grep -vE '^(obj:[a-z]+:|tabla:)public(@|$)' | sort -u
}

# ── Qué está pendiente de promover ──────────────────────────────────────────
declare -A EN_PRUEBAS=() EN_PROD=()
if [ -f "$LIBRO" ]; then
  while IFS=$'\t' read -r fecha entorno ref archivo hash; do
    [[ "$fecha" =~ ^# ]] && continue
    [ -n "${archivo:-}" ] || continue
    archivo="${archivo%$'\r'}"
    case "$entorno" in
      pruebas)    EN_PRUEBAS["$archivo"]=1 ;;
      produccion) EN_PROD["$archivo"]=1 ;;
    esac
  done < "$LIBRO"
fi

# Lo que ya esta en main (lo que se promovio). Sin red, se usa lo ultimo que
# se trajo; si no hay origin/main, nada cuenta como promovido por esta via.
declare -A EN_MAIN=()
while IFS= read -r r; do EN_MAIN["$r"]=1; done < <(
  git -C "$RAIZ" ls-tree --name-only origin/main "$MIG_DIR/" 2>/dev/null || true)

PENDIENTES=()
for f in "$RAIZ/$MIG_DIR"/*.sql; do
  r="$(rel "$f")"; b="$(basename "$f")"
  [ -n "${OBJETIVO[$r]:-}" ] && continue
  [ -n "${EN_PROD[$r]:-}" ] && continue
  if [ -n "${EN_PRUEBAS[$r]:-}" ]; then
    PENDIENTES+=("$r|en pruebas, no en producción")
  elif [[ "${b:0:8}" > "$DESDE_LIBRO" || "${b:0:8}" == "$DESDE_LIBRO" ]]        && [ -z "${EN_MAIN[$r]:-}" ]; then
    # Sin fila en el libro Y fuera de main: escrita y no promovida. Las que
    # estan en main pero sin fila se aplicaron fuera de los guiones.
    PENDIENTES+=("$r|sin aplicar en ninguna base")
  fi
done

autor() { git -C "$RAIZ" log --diff-filter=A --format='%an' -1 -- "$1" 2>/dev/null || true; }

AVISOS=0
echo "── Choques con trabajo pendiente de promover ──"
for objetivo in "${!OBJETIVO[@]}"; do
  mias="$(objetos "$RAIZ/$objetivo")"
  echo "   $(basename "$objetivo")"
  if [ -z "$mias" ]; then
    echo "     (no se reconocieron objetos; revisa a mano)"
  fi

  # NÚMERO repetido, contra TODAS las migraciones.
  pref="$(basename "$objetivo")"; pref="${pref:0:14}"
  for f in "$RAIZ/$MIG_DIR/${pref}"_*.sql; do
    [ -f "$f" ] || continue
    [ "$(rel "$f")" = "$objetivo" ] && continue
    echo "     ⚠ NÚMERO: $(basename "$f") usa el mismo prefijo $pref ($(autor "$(rel "$f")"))"
    AVISOS=1
  done

  for p in "${PENDIENTES[@]}"; do
    otro="${p%%|*}"; estado="${p#*|}"
    suyos="$(objetos "$RAIZ/$otro")"
    [ -n "$suyos" ] || continue
    comunes="$(comm -12 <(echo "$mias") <(echo "$suyos"))"
    [ -n "$comunes" ] || continue
    fuertes="$(echo "$comunes" | grep '^obj:' || true)"
    zonas="$(echo "$comunes" | grep '^tabla:' | sed 's/^tabla://' | paste -sd, - || true)"
    quien="$(autor "$otro")"
    if [ -n "$fuertes" ]; then
      echo "     ✗ CHOQUE con $(basename "$otro") — $estado${quien:+, de $quien}:"
      echo "$fuertes" | sed 's/^obj:/         · /; s/:/ /'
      AVISOS=1
    fi
    if [ -n "$zonas" ] && [ -z "$fuertes" ]; then
      echo "     ⚠ ZONA con $(basename "$otro") — $estado${quien:+, de $quien}: tabla(s) $zonas"
      AVISOS=1
    fi
  done
done

if [ "$AVISOS" -eq 0 ]; then
  echo "   ✓ Nada en común con lo pendiente de promover."
else
  echo
  echo "   Antes de seguir: habla con quien escribió la otra migración. Si las dos"
  echo "   tocan el mismo objeto, la que se aplique DESPUÉS gana, sin error."
fi
echo
exit "$AVISOS"
