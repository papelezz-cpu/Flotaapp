#!/usr/bin/env bash
# ============================================================================
# Que las confirmaciones de supabase/*.sh no se contesten solas (R-06)
# ============================================================================
#
# El fallo: al pegar un comando de varias lineas —lo normal aqui, con las
# variables de entorno delante y continuaciones con "\"— el terminal deja el
# salto de linea sobrante en el bufer. El primer `read` se lo come como si
# fuera la respuesta, sale cadena vacia, y el guion se cancela solo SIN dejar
# escribir nada. Visto el 2026-09-15 en replicar-produccion-a-pruebas.sh.
#
# Se arreglo alli a mano y se olvido en los demas. Ahora la pregunta vive una
# sola vez, en lib-conexion.sh, y esto la ejercita.
#
# Como se simula un terminal sin tener consola: con una tuberia con nombre a la
# que se escribe la basura primero y la respuesta despues de una pausa. Eso es
# exactamente lo que hace una persona —la basura ya esta en el bufer, la
# respuesta todavia no—, y es lo que un archivo normal NO puede reproducir,
# porque de un archivo se lee todo de golpe.
#
#   bash pruebas/08-sonda-preguntar.sh
#
# No toca ninguna base de datos ni ninguna red.
# ============================================================================

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source supabase/lib-conexion.sh

V=$'\e[32m'; R=$'\e[31m'; G=$'\e[90m'; N=$'\e[1m'; F=$'\e[0m'
FALLOS=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

comprobar() { # comprobar "nombre" "esperado" "obtenido"
  if [ "$2" = "$3" ]; then
    printf '  %s  OK  %s  %s\n' "$V" "$F" "$1"
  else
    printf '  %s FALLA%s  %s\n         %sesperaba [%s], obtuve [%s]%s\n' \
      "$R" "$F" "$1" "$G" "$2" "$3" "$F"
    FALLOS=$((FALLOS + 1))
  fi
}

# Escribe en la tuberia: primero lo que ya estaria en el bufer, pausa, y luego
# lo que la persona teclea. La pausa (0.4s) es ocho veces el tiempo que espera
# el vaciado (0.05s), para que la prueba no dependa de la suerte.
con_terminal() { # con_terminal "basura" "respuesta" -> deja RESPUESTA
  local basura="$1" respuesta="$2" fifo="$TMP/tty"
  rm -f "$fifo"; mkfifo "$fifo"
  # Se deja un descriptor propio abierto mientras dura la pregunta. El ayudante
  # abre y cierra el terminal en cada lectura —igual que hace con /dev/tty— y
  # sin esto la tuberia se queda sin lector en ese hueco, el escritor muere con
  # SIGPIPE, y la respuesta no llega nunca: las seis pruebas salian vacias.
  exec 9<>"$fifo"
  { printf '%b' "$basura"; sleep 0.4; printf '%b' "$respuesta"; } > "$fifo" &
  local escritor=$!
  PORTGO_TTY_PRUEBA="$fifo" "${@:3}" 2>/dev/null
  wait "$escritor" 2>/dev/null || true
  exec 9>&-
}

echo
echo "${N}── R-06 · la pregunta no se contesta sola ──${F}"
echo

# ── 1. El fallo original, tal cual ─────────────────────────────────────────
# Un salto de linea suelto en el bufer y la respuesta despues. Antes esto
# devolvia cadena vacia y el guion se cancelaba.
con_terminal '\n' 's\n' preguntar "  p1 "
comprobar "un salto suelto en el bufer no contesta por ti" "s" "$RESPUESTA"

# ── 2. Un pegado de varias lineas, que es el caso real ─────────────────────
con_terminal '\n\n\n' 'APLICAR A PRODUCCION\n' preguntar "  p2 "
comprobar "tres saltos tampoco" "APLICAR A PRODUCCION" "$RESPUESTA"

# ── 3. Sin basura delante sigue funcionando ────────────────────────────────
# El vaciado no debe comerse una respuesta que ya estuviera escrita a tiempo.
con_terminal '' 'N\n' preguntar "  p3 "
comprobar "sin basura delante, la respuesta llega igual" "N" "$RESPUESTA"

# ── 4. El retorno de carro de Windows ──────────────────────────────────────
con_terminal '\n' 's\r\n' preguntar "  p4 "
comprobar "el retorno de carro se quita" "s" "$RESPUESTA"

# ── 5. La confirmacion tecleada con espacios de mas sigue valiendo ─────────
con_terminal '\n' '  s  \n' preguntar "  p5 "
comprobar "los espacios sobrantes se recortan" "s" "$RESPUESTA"

# ── 6. La contrasena, al reves: los espacios SON parte de ella ─────────────
con_terminal '\n' ' clave con espacios \n' preguntar_secreto "  p6 "
comprobar "la contrasena conserva sus espacios" " clave con espacios " "$RESPUESTA"

# ── 7. Sin terminal, nadie dice que si ─────────────────────────────────────
# Si el guion corre sin consola, la pregunta tiene que fallar y dejar la
# respuesta vacia. Lo que NO puede es salir algo que parezca un "s".
RESPUESTA="basura previa"
if PORTGO_TTY_PRUEBA="$TMP/no-existe" preguntar "  p7 " 2>/dev/null; then
  comprobar "sin terminal devuelve error" "rc distinto de 0" "rc 0"
else
  comprobar "sin terminal devuelve error" "rc distinto de 0" "rc distinto de 0"
fi
comprobar "sin terminal la respuesta queda vacia" "" "$RESPUESTA"

# ── 8. Que el arreglo este puesto en los cuatro sitios ─────────────────────
# Sirve de poco tener el ayudante si un guion sigue llamando a `read` a pelo.
echo
sueltos=""
for f in supabase/aplicar-a-pruebas.sh supabase/aplicar-a-produccion.sh \
         supabase/preparar-pruebas.sh supabase/replicar-produccion-a-pruebas.sh \
         supabase/lib-conexion.sh; do
  # Se ignoran los comentarios y el propio ayudante, que si usa read.
  if grep -vE '^\s*#' "$f" | grep -v 'basura < "\$tty"' \
     | grep -v 'RESPUESTA < "\$tty"' | grep -qE '\bread -r?\s+-?[a-z]*\s*-p'; then
    sueltos="$sueltos $(basename "$f")"
  fi
done
comprobar "ningun guion pregunta con read a pelo" "" "$sueltos"

echo
if [ "$FALLOS" -eq 0 ]; then
  echo "${V}${N}  Las confirmaciones esperan a que escribas.${F}"
else
  echo "${R}${N}  $FALLOS fallan.${F}"
  exit 1
fi
