#!/usr/bin/env bash
#
# Levanta el proyecto de PRUEBAS con el mismo esquema que producción.
#
# ⚠ Esto es el ARRANQUE de un proyecto vacío, y solo copia la ESTRUCTURA.
#   Para el día a día —dejar pruebas siendo una copia de producción antes de
#   sembrar o de probar, con datos, usuarios, permisos y Realtime incluidos—
#   usa supabase/replicar-produccion-a-pruebas.sh (Regla #3 de CLAUDE.md).
#
# Antes de correrlo:
#   1. bash supabase/volcar-esquema.sh        (saca el plano de producción)
#   2. Crear el proyecto en Supabase → New project → nombre: portgo-pruebas
#      Guarda la contraseña de la base que te genere: se pide aquí.
#
# ⚠ Este script escribe, pero SOLO en el proyecto de pruebas. Verifica dos
#   veces la cadena de conexión antes de darle enter: si pegas la de
#   producción, aplica DDL sobre datos reales.
#
# Uso:
#   bash supabase/preparar-pruebas.sh
#   bash supabase/preparar-pruebas.sh --con-sincronizacion   # incluye la migración OPCIONAL
#
set -euo pipefail

REF_PRODUCCION="xnyqsewaluezkkrlyhxg"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ESQ="$RAIZ/supabase/esquema"

MODO="${1:-normal}"

echo "──────────────────────────────────────────────────────────"
echo " PortGo · preparar ambiente de PRUEBAS"
echo "──────────────────────────────────────────────────────────"
echo

if [ ! -f "$ESQ/01-esquema-public.sql" ]; then
  echo "❌ Falta supabase/esquema/01-esquema-public.sql"
  echo "   Corre primero:  bash supabase/volcar-esquema.sh"
  exit 1
fi

# Misma conexión y mismo diagnóstico que volcar-esquema.sh.
# La contraseña del proyecto de pruebas sí se puede dejar en una variable:
# protege datos desechables. Se llama distinto que la de producción a
# propósito, para que no exista forma de confundirlas.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-conexion.sh"

conectar_a "el proyecto DE PRUEBAS" "<ref-de-pruebas>" "PORTGO_DB_URL_PRUEBAS" || exit 1

# Red de seguridad. Va después de conectar porque hasta aquí solo se hizo un
# "select 1"; nada se ha escrito todavía y todavía estamos a tiempo de abortar.
if [[ "$CONN" == *"$REF_PRODUCCION"* ]]; then
  echo "❌ Esa cadena es la de PRODUCCIÓN ($REF_PRODUCCION)."
  echo "   Este script aplica DDL y no corre contra producción. Cancelado."
  exit 1
fi

# Confirmación explícita: si la base ya tiene tablas de PortGo, algo va mal.
TABLAS=$(psql "$CONN" -Atc "select count(*) from information_schema.tables where table_schema='public'")
echo "✓ Conectado. Tablas actuales en public: $TABLAS"
if [ "$TABLAS" -gt 0 ] && [ "$MODO" != "--completar" ]; then
  echo
  echo "⚠ La base de pruebas NO está vacía. Aplicar el esquema encima puede"
  echo "  fallar o dejarla a medias. Revisa que sea el proyecto correcto."
  read -r -p "¿Continuar de todos modos? [s/N] " R
  [[ "$R" =~ ^[sS]$ ]] || { echo "Cancelado."; exit 0; }
fi
echo

aplicar() {
  local archivo="$1" etiqueta="$2" obligatorio="${3:-si}"
  if [ ! -f "$archivo" ]; then
    echo "── $etiqueta: no existe, se omite"
    return 0
  fi
  echo "── $etiqueta ──"
  # Tres líneas del volcado fallan en una base nueva y no hacen falta: el
  # esquema public ya viene creado en cualquier proyecto de Supabase, con
  # dueño y comentario idénticos. Se neutralizan al vuelo para no alterar el
  # volcado, que debe seguir siendo copia fiel de producción.
  # Además, las 24 líneas de ALTER DEFAULT PRIVILEGES: son los permisos de
  # fábrica de Supabase (la mitad a nombre de supabase_admin, un rol de
  # plataforma que el usuario postgres no puede tocar). Todo proyecto nuevo
  # ya los trae, así que aplicarlos sobra y además revienta.
  if sed -E 's/^(CREATE SCHEMA public;|ALTER SCHEMA public OWNER TO .*;|COMMENT ON SCHEMA public IS .*;|ALTER DEFAULT PRIVILEGES .*;)/-- [omitido al aplicar] \1/' "$archivo" \
       | psql "$CONN" -v ON_ERROR_STOP=1 >/dev/null; then
    echo "   ✓ OK"
  elif [ "$obligatorio" = "si" ]; then
    echo "   ❌ Falló. Revisa el error corriendo:"
    echo "      psql \"<cadena>\" -v ON_ERROR_STOP=1 -f \"$archivo\""
    exit 1
  else
    echo "   ⚠ Con errores (normal en objetos que Supabase ya administra)"
  fi
  echo
}

# Del volcado de storage solo sirven las políticas de PortGo sobre
# storage.objects: el esquema, sus tablas y sus funciones son de Supabase y ya
# vienen en cualquier proyecto. Aplicar el archivo completo aborta en la
# primera línea ("schema storage already exists") y las políticas —que son las
# que exigen que el primer tramo de la ruta sea el auth.uid()— se quedan sin
# aplicar, con lo que las pruebas de archivos dejarían de reflejar producción.
extraer_politicas() {
  awk '/^CREATE POLICY/ {c=1} c {print} /;[[:space:]]*$/ {c=0}' "$1"
}

aplicar_politicas_storage() {
  local archivo="$ESQ/02-storage.sql"
  if [ ! -f "$archivo" ]; then
    echo "── 2/4 · Políticas de storage: no existe, se omite"
    echo
    return 0
  fi
  echo "── 2/4 · Políticas de storage ──"
  local n
  n=$(extraer_politicas "$archivo" | grep -c '^CREATE POLICY' || true)
  if [ "${n:-0}" -eq 0 ]; then
    echo "   (el volcado no trae políticas propias)"
    echo
    return 0
  fi
  if extraer_politicas "$archivo" | psql "$CONN" -v ON_ERROR_STOP=1 >/dev/null 2>&1; then
    echo "   ✓ $n políticas aplicadas sobre storage.objects"
  else
    echo "   ⚠ Alguna no entró. Detalle:"
    extraer_politicas "$archivo" | psql "$CONN" 2>&1 | grep -i "error" | sed 's/^/     /' | head -6
    echo "     (si dice \"already exists\", ya estaban y no hay problema)"
  fi
  echo
}

# --completar salta el esquema y aplica solo lo que falta. Sirve cuando el
# esquema ya entró pero la corrida se cortó antes de buckets y catálogos:
# volver a aplicar el 01 fallaría con "la relación ya existe".
if [ "$MODO" = "--completar" ]; then
  echo "Modo --completar: se omite el esquema, ya está aplicado."
  echo
else
  aplicar "$ESQ/01-esquema-public.sql" "1/4 · Esquema de public"     si
fi
aplicar_politicas_storage
aplicar "$ESQ/03-buckets.sql"        "3/4 · Buckets"                 si
# El volcado de catálogos es un COPY: si las filas ya están, reinsertarlas
# choca contra la clave primaria. No es un fallo, es que ya estaba hecho.
FILAS_CAT=$(psql "$CONN" -Atc "select count(*) from public.catalogos" 2>/dev/null || echo 0)
if [ "${FILAS_CAT:-0}" -gt 0 ]; then
  echo "── 4/4 · Catálogos de referencia ──"
  echo "   ✓ Ya estaban ($FILAS_CAT filas en catalogos), se omite"
  echo
else
  aplicar "$ESQ/04-catalogos.sql"    "4/4 · Catálogos de referencia" no
fi

# La migración de sincronización nunca se aplicó en producción. El ambiente de
# pruebas es justo donde se puede probar sin riesgo antes de decidir.
if [ "$MODO" = "--con-sincronizacion" ]; then
  aplicar "$RAIZ/supabase/migrations/20260810130000_sincronizar_estados_OPCIONAL.sql" \
          "extra · Sincronización de estados por pg_cron" no
fi

# Se compara contra lo que trae el volcado, no contra números escritos a mano:
# si mañana cambia el esquema de producción, la verificación sigue sirviendo.
ESP_TABLAS=$(grep -c '^CREATE TABLE' "$ESQ/01-esquema-public.sql")
ESP_POLIT=$(grep -c '^CREATE POLICY' "$ESQ/01-esquema-public.sql")
ESP_BUCKETS=$(grep -c '^insert into storage.buckets' "$ESQ/03-buckets.sql" || echo 0)
ESP_POL_STORAGE=$(grep -c '^CREATE POLICY' "$ESQ/02-storage.sql" 2>/dev/null || echo 0)

comparar() {
  local etiqueta="$1" obtenido="$2" esperado="$3"
  if [ "$obtenido" = "$esperado" ]; then
    echo "   ✓ $etiqueta: $obtenido"
  else
    echo "   ⚠ $etiqueta: $obtenido (en producción hay $esperado)"
  fi
}

echo "── Verificación ──"
comparar "tablas en public" \
  "$(psql "$CONN" -Atc "select count(*) from information_schema.tables where table_schema='public'")" \
  "$ESP_TABLAS"
comparar "tablas con RLS activo" \
  "$(psql "$CONN" -Atc "select count(*) from pg_tables t join pg_class c on c.relname=t.tablename where t.schemaname='public' and c.relrowsecurity")" \
  "$ESP_TABLAS"
comparar "politicas RLS" \
  "$(psql "$CONN" -Atc "select count(*) from pg_policies where schemaname='public'")" \
  "$ESP_POLIT"
comparar "buckets de Storage" \
  "$(psql "$CONN" -Atc "select count(*) from storage.buckets")" \
  "$ESP_BUCKETS"
comparar "politicas sobre storage.objects" \
  "$(psql "$CONN" -Atc "select count(*) from pg_policies where schemaname='storage' and tablename='objects'")" \
  "$ESP_POL_STORAGE"
comparar "funciones RPC de negocio" \
  "$(psql "$CONN" -Atc "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('enviar_oferta','responder_oferta','responder_contraoferta','cancelar_reservacion','solicitar_cancelacion','registrar_evidencias','avanzar_tracking','abrir_expediente','calificar_servicio','enviar_mensaje','recomendar_unidad')")" \
  "11"
echo "   filas en catalogos: $(psql "$CONN" -Atc "select count(*) from public.catalogos" 2>/dev/null || echo '0 (tabla ausente)')"
echo

cat <<'FIN'
──────────────────────────────────────────────────────────
 Base de pruebas lista. Faltan tres cosas que solo se
 hacen desde el panel o con la CLI:

 1) Edge Functions
      npx supabase login
      npx supabase functions deploy gestionar-usuario   --project-ref <ref-pruebas>
      npx supabase functions deploy enviar-notificacion --project-ref <ref-pruebas>
    y sus secretos (SUPABASE_SERVICE_ROLE_KEY del proyecto de pruebas).

 2) Authentication → URL Configuration
      Site URL:       http://localhost:3000
      Redirect URLs:  http://localhost:3000/**, portgo://auth

 3) js/config.js → AMBIENTES.pruebas
      url y anon del proyecto de pruebas (Settings → API)
    y pruebas/credenciales.local.json → bloque "pruebas"
      url, anon y service_role, para poder sembrar usuarios.

 Después:  node pruebas/02-sembrar.mjs
──────────────────────────────────────────────────────────
FIN
