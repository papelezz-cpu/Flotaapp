#!/usr/bin/env bash
#
# Aplica las migraciones de PortGo contra la base de producción.
#
# Por qué existe este script en vez de simplemente `supabase db push`: esa vía
# necesita `supabase login` con un token de acceso personal y un flujo de
# navegador. Si ya lo tienes configurado, úsala — es mejor, porque además lleva
# el registro de qué migración se aplicó. Esto es la alternativa directa por
# psql, que ya está instalado en este equipo.
#
# ⚠ NO HAY AMBIENTE DE PRUEBAS. Lo que corras aquí pega en producción de
#   inmediato. Léelo antes de ejecutarlo.
#
# La contraseña NUNCA se pasa como argumento (quedaría en el historial del
# shell y en la lista de procesos): el script la pide de forma interactiva y
# psql la toma de PGPASSWORD solo durante la ejecución.
#
# Uso:
#   bash supabase/aplicar-migraciones.sh                 # las dos migraciones nuevas
#   bash supabase/aplicar-migraciones.sh --solo-rpc      # solo la obligatoria
#   bash supabase/aplicar-migraciones.sh --verificar     # no aplica nada, solo revisa
#
set -euo pipefail

REF="xnyqsewaluezkkrlyhxg"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/migrations"

RPC="$DIR/20260810120000_rpc_transacciones.sql"
SYNC="$DIR/20260810130000_sincronizar_estados_OPCIONAL.sql"

MODO="${1:-todo}"

echo "──────────────────────────────────────────────────────────"
echo " PortGo · aplicar migraciones"
echo " Proyecto: $REF  (PRODUCCIÓN)"
echo "──────────────────────────────────────────────────────────"
echo

# La forma fiable de obtener la cadena es copiarla del panel: la región del
# pooler cambia según dónde esté alojado el proyecto, y adivinarla falla.
#
#   Supabase → Project Settings → Database → Connection string → URI
#   Usa el modo "Session" (puerto 5432). El modo "Transaction" (6543) NO
#   sirve para DDL.
#
# Se puede pasar por la variable PORTGO_DB_URL para no teclearla cada vez.
CONN="${PORTGO_DB_URL:-}"

if [ -z "$CONN" ]; then
  echo "Pega la cadena de conexión (Supabase → Settings → Database →"
  echo "Connection string → URI, modo Session / puerto 5432)."
  echo "Déjala vacía para probar la conexión directa del proyecto."
  echo
  read -r -p "Cadena: " CONN
  if [ -z "$CONN" ]; then
    CONN="postgresql://postgres@db.${REF}.supabase.co:5432/postgres"
  fi
fi

# La contraseña se pide aparte y nunca como argumento: así no queda en el
# historial del shell ni en la lista de procesos del sistema.
if [[ "$CONN" != *":"*"@"* ]] || [[ "$CONN" == *"[YOUR-PASSWORD]"* ]]; then
  echo
  echo "Contraseña: Supabase → Project Settings → Database → Database password"
  read -r -s -p "Contraseña de la base: " DBPASS
  echo
  export PGPASSWORD="$DBPASS"
  CONN="${CONN/\[YOUR-PASSWORD\]/}"
  CONN="${CONN//:@/@}"
fi

if ! psql "$CONN" -Atc "select 1" >/dev/null 2>&1; then
  echo
  echo "❌ No se pudo conectar."
  echo
  echo "Verifica la cadena en Supabase → Project Settings → Database."
  echo "Si el proyecto solo acepta IPv6 en la conexión directa, usa la del"
  echo "pooler en modo Session (puerto 5432)."
  echo
  echo "También puedes aplicarla a mano:"
  echo "  psql \"<tu-connection-string>\" -v ON_ERROR_STOP=1 -f \"$RPC\""
  exit 1
fi

echo "✓ Conectado."
echo

verificar() {
  echo "── Funciones RPC presentes ──"
  psql "$CONN" -Atc "
    select p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in (
         'enviar_oferta','responder_oferta','responder_contraoferta',
         'cancelar_reservacion','solicitar_cancelacion','registrar_evidencias',
         'avanzar_tracking','abrir_expediente','calificar_servicio',
         'enviar_mensaje','recomendar_unidad','sincronizar_estados_pedidos')
     order by 1;"
}

if [ "$MODO" = "--verificar" ]; then
  verificar
  exit 0
fi

# ON_ERROR_STOP hace que psql aborte al primer error en vez de seguir
# ejecutando el resto del archivo sobre un estado a medias.
aplicar() {
  local archivo="$1"
  echo "── Aplicando $(basename "$archivo") ──"
  psql "$CONN" -v ON_ERROR_STOP=1 -f "$archivo"
  echo "✓ OK"
  echo
}

aplicar "$RPC"

if [ "$MODO" != "--solo-rpc" ]; then
  echo "──────────────────────────────────────────────────────────"
  echo " La segunda migración es OPCIONAL y modifica un guard de"
  echo " seguridad (guard_pedido_update). Lee su encabezado antes"
  echo " de decidir."
  echo "──────────────────────────────────────────────────────────"
  read -r -p "¿Aplicar también la sincronización de estados? [s/N] " RESP
  if [[ "$RESP" =~ ^[sS]$ ]]; then
    aplicar "$SYNC"
  else
    echo "Omitida."
    echo
  fi
fi

verificar

echo
echo "Listo. Recuerda además dar de alta el deep link:"
echo "  Supabase → Authentication → URL Configuration → Redirect URLs"
echo "  agregar:  portgo://auth"
