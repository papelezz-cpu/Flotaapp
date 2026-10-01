# Pega las cadenas de conexión UNA vez por ventana de Git Bash.
#
# ── Por qué existe ──────────────────────────────────────────────────────────
#
# El 2026-09-30 hubo que pegar la cadena de producción y la de pruebas una
# decena de veces: cada comparación de paridad pide las dos, cada aplicación
# pide la suya. Todos los guiones de supabase/ ya aceptan las cadenas por
# variables de entorno (PORTGO_DB_URL_PROD, PORTGO_DB_URL_PRUEBAS) y no las
# piden si existen; faltaba una forma segura de ponerlas.
#
# ── Qué hace ────────────────────────────────────────────────────────────────
#
# Pide cada cadena SIN mostrarla (el mismo conectar_a de lib-conexion.sh:
# limpia, valida y prueba la conexión) y la exporta SOLO en esta ventana.
#   · No escribe nada en disco ni en el historial de la terminal.
#   · Al cerrar la ventana, desaparecen.
#   · Comprueba que cada cadena es del proyecto que dice ser: la de producción
#     tiene que ser de xnyqsewaluezkkrlyhxg, y la de pruebas NO puede serlo.
#
# Tener la de producción cargada NO quita ninguna protección:
# aplicar-a-produccion.sh sigue pidiendo que se escriba «APLICAR A PRODUCCION».
# Si prefieres que producción siga pidiéndose cada vez, carga solo pruebas.
#
# ── Uso (en Git Bash, con «source», no con «bash») ──────────────────────────
#
#   source supabase/sesion-conexiones.sh              # las dos
#   source supabase/sesion-conexiones.sh pruebas      # solo pruebas
#   source supabase/sesion-conexiones.sh produccion   # solo producción
#   source supabase/sesion-conexiones.sh olvidar      # borra las dos de la ventana
#
# Con «bash» no sirve: las variables morirían al terminar el guion. Por eso
# este archivo no se ejecuta; se carga.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Este archivo se carga con «source», no se ejecuta:" >&2
  echo "  source supabase/sesion-conexiones.sh" >&2
  exit 2
fi

_portgo_sesion() {
  local AQUI REF_PROD="xnyqsewaluezkkrlyhxg" REF_PRUE="xskgnudiznryhgagxadu" que="${1:-las-dos}"
  AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [ "$que" = "olvidar" ]; then
    unset PORTGO_DB_URL_PROD PORTGO_DB_URL_PRUEBAS
    echo "  ✓ Cadenas borradas de esta ventana."
    return 0
  fi

  # shellcheck source=/dev/null
  source "$AQUI/lib-conexion.sh" || return 1
  export PGCLIENTENCODING=UTF8

  if [ "$que" = "las-dos" ] || [ "$que" = "produccion" ]; then
    unset PORTGO_DB_URL_PROD
    if conectar_a "PRODUCCIÓN" "$REF_PROD" ""; then
      local c; c="$(cadena_autonoma "$CONN")"; unset PGPASSWORD
      if [[ "$c" != *"$REF_PROD"* ]]; then
        echo "  ❌ Esa cadena no es de producción ($REF_PROD). No se guardó." >&2
      else
        export PORTGO_DB_URL_PROD="$c"
        echo "  ✓ Producción cargada en esta ventana."
      fi
    fi
    echo
  fi

  if [ "$que" = "las-dos" ] || [ "$que" = "pruebas" ]; then
    unset PORTGO_DB_URL_PRUEBAS
    if conectar_a "el proyecto DE PRUEBAS" "$REF_PRUE" ""; then
      local c; c="$(cadena_autonoma "$CONN")"; unset PGPASSWORD
      if [[ "$c" == *"$REF_PROD"* ]]; then
        echo "  ❌ ALTO: pegaste la cadena de PRODUCCIÓN como si fuera la de pruebas. No se guardó." >&2
      elif [[ "$c" != *"$REF_PRUE"* ]]; then
        echo "  ❌ Esa cadena no es de pruebas ($REF_PRUE). No se guardó." >&2
      else
        export PORTGO_DB_URL_PRUEBAS="$c"
        echo "  ✓ Pruebas cargada en esta ventana."
      fi
    fi
    echo
  fi

  unset CONN RESPUESTA
  # Nunca se imprime la cadena: lleva la contraseña dentro.
  local p="no" q="no"
  [ -n "${PORTGO_DB_URL_PROD:-}" ]    && p="sí"
  [ -n "${PORTGO_DB_URL_PRUEBAS:-}" ] && q="sí"
  echo "  Cargadas en esta ventana → producción: $p · pruebas: $q"
  echo "  Se borran al cerrar la ventana, o con: source supabase/sesion-conexiones.sh olvidar"
}

_portgo_sesion "$@"
unset -f _portgo_sesion
