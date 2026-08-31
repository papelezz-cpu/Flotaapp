#!/usr/bin/env bash
#
# Saca de producción el esquema completo (tablas, RLS, triggers, funciones,
# buckets) y lo deja en archivos versionables. Es el paso que faltaba para
# poder levantar un ambiente de pruebas idéntico.
#
# POR QUÉ HACE FALTA: supabase/migrations/ solo tiene el CREATE TABLE de 8
# tablas. Las 14 centrales (perfiles, pedidos, ofertas, reservaciones,
# camiones, custodios, patios, lavados, operadores, mensajes, notificaciones,
# calificaciones, solicitudes_cuenta, reservaciones_historico) se crearon a
# mano en el panel y no están en ningún archivo. Sin esto no se puede
# reconstruir la base: ni para pruebas, ni si algún día hay que restaurarla.
#
# ⚠ ESTE SCRIPT SOLO LEE. No modifica producción, no borra nada, no escribe
#   una sola fila. Únicamente hace SELECT y pg_dump del esquema.
#
# ⚠ NO EXPORTA DATOS PERSONALES. Del contenido solo se copian los catálogos
#   de referencia (catalogos, documentos_catalogo, app_config): combos y
#   listas, cero datos de clientes, empresas o viajes. Los perfiles, pedidos
#   y reservaciones NO salen de producción.
#
# La contraseña nunca se pasa como argumento: se pide de forma interactiva y
# vive en PGPASSWORD solo mientras corre.
#
# Uso:
#   bash supabase/volcar-esquema.sh
#
set -euo pipefail

REF="xnyqsewaluezkkrlyhxg"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SALIDA="$RAIZ/supabase/esquema"

mkdir -p "$SALIDA"

# Sin esto, psql en Windows anuncia la codificación del sistema (WIN1252) y
# cualquier acento que viaje en un -c termina rechazado por el servidor.
export PGCLIENTENCODING=UTF8

# pg_dump nativo, no el de la CLI de Supabase: esa lo corre dentro de Docker y
# aquí Docker Desktop suele estar apagado.
if ! command -v pg_dump >/dev/null 2>&1; then
  echo "❌ No encontré pg_dump."
  echo "   Viene con el cliente de PostgreSQL. En este equipo estaba en:"
  echo "   ~/scoop/apps/postgresql/current/bin"
  exit 1
fi

echo "──────────────────────────────────────────────────────────"
echo " PortGo · volcar esquema de producción"
echo " Proyecto: $REF   (solo lectura)"
echo "──────────────────────────────────────────────────────────"
echo

# La conexión y su diagnóstico viven en lib-conexion.sh, compartidos con
# preparar-pruebas.sh. Se puede saltar el prompt exportando PORTGO_DB_URL.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-conexion.sh"

conectar_a "PRODUCCIÓN" "$REF" "PORTGO_DB_URL" || exit 1

# Con --probar solo se comprueba la conexión y se sale, para poder atinarle a
# la cadena sin esperar el volcado completo.
if [ "${1:-}" = "--probar" ]; then
  echo "Listo: la cadena y la contraseña sirven."
  echo "Vuelve a correrlo sin --probar para hacer el volcado."
  exit 0
fi


# ── 1) Esquema de public: tablas, índices, RLS, triggers, funciones ────────
echo "── 1/4 · Esquema de public ──"
# Se usa pg_dump nativo en vez de `supabase db dump`: ese último corre
# pg_dump dentro de Docker, y aquí Docker Desktop puede estar apagado.
# El cliente 18.x lee servidores 15/17 sin problema.
pg_dump "$CONN" --schema-only --schema=public --no-publications --no-subscriptions \
  -f "$SALIDA/01-esquema-public.sql"
echo "   → supabase/esquema/01-esquema-public.sql"
echo

# ── 2) Políticas y objetos del esquema storage ────────────────────────────
echo "── 2/4 · Esquema storage ──"
pg_dump "$CONN" --schema-only --schema=storage --no-publications --no-subscriptions -f "$SALIDA/02-storage.sql" \
  || echo "   (sin acceso al esquema storage, se omite)"
echo

# ── 3) Los buckets, como INSERT reproducible ──────────────────────────────
# Los buckets son filas de storage.buckets, no DDL: pg_dump del esquema no
# los trae. Sin ellos, en pruebas fallaría toda subida de archivos.
echo "── 3/4 · Buckets de Storage ──"
{
  echo "-- Buckets de Storage copiados de producción."
  echo "-- Ojo con la columna public: unidades, registros y documentos-viaje"
  echo "-- son privados y se leen con URL firmada."
  echo
  psql "$CONN" -Atc "
    select format(
      'insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values (%L, %L, %L, %s, %s) on conflict (id) do nothing;',
      id, name, public,
      coalesce(file_size_limit::text, 'null'),
      case when allowed_mime_types is null then 'null'
           else quote_literal(allowed_mime_types::text) || '::text[]' end)
      from storage.buckets order by id;"
} > "$SALIDA/03-buckets.sql"
echo "   → supabase/esquema/03-buckets.sql"
# El SQL que se manda con -c va en ASCII puro a propósito: en Windows, psql
# entrega los acentos con otra codificación y el servidor los rechaza
# ("invalid byte sequence for encoding UTF8"). Los acentos van en el echo.
psql "$CONN" -Atc "select '   - ' || id || (case when public then '  (publico)' else '  (privado)' end) from storage.buckets order by id;"
echo

# ── 4) Datos de referencia (sin información personal) ──────────────────────
echo "── 4/4 · Catálogos de referencia ──"
pg_dump "$CONN" --data-only \
  --table public.catalogos --table public.documentos_catalogo --table public.app_config \
  -f "$SALIDA/04-catalogos.sql" || echo "   (alguna tabla de catálogo no existe todavía)"
echo "   → supabase/esquema/04-catalogos.sql"
echo

# ── Revisión: que no se haya colado nada personal ──────────────────────────
#
# Se revisa SOLO el archivo de datos. Los de esquema son puro DDL: ahí
# "curp text" es el nombre de una columna, no la CURP de nadie, y buscar la
# palabra suelta daba una falsa alarma en cada corrida.
echo "── Revisión de privacidad ──"
FUGA=0
DATOS="$SALIDA/04-catalogos.sql"

if [ -f "$DATOS" ]; then
  # Se buscan formas de dato real, no nombres de campo.
  declare -A SOSPECHAS=(
    ["correos"]='[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
    ["RFC o CURP"]='[A-Z]{4}[0-9]{6}[A-Z0-9]{3}'
    ["teléfonos de 10 dígitos"]='(^|[^0-9])[0-9]{10}([^0-9]|$)'
  )
  for etiqueta in "${!SOSPECHAS[@]}"; do
    N=$(grep -cE "${SOSPECHAS[$etiqueta]}" "$DATOS" 2>/dev/null || true)
    if [ "${N:-0}" -gt 0 ]; then
      echo "   ⚠ $N línea(s) con algo que parece $etiqueta en 04-catalogos.sql"
      echo "     Revísalo antes de commitear."
      FUGA=1
    fi
  done

  # Que no se haya colado ninguna tabla que no sea de catálogo.
  TABLAS_DATOS=$(grep -o "COPY public\.[a-z_]*" "$DATOS" | sed 's/COPY public\.//' | sort -u | tr '\n' ' ')
  for t in $TABLAS_DATOS; do
    case "$t" in
      catalogos|documentos_catalogo|app_config) ;;
      *) echo "   ⚠ El volcado de datos incluye la tabla '$t', que no es de catálogo"; FUGA=1 ;;
    esac
  done
  if [ -n "$TABLAS_DATOS" ]; then echo "   Tablas con datos exportadas: $TABLAS_DATOS"; fi
fi

if [ "$FUGA" = "0" ]; then
  echo "   ✓ Sin datos personales: solo estructura y catálogos de referencia"
fi
echo

echo "──────────────────────────────────────────────────────────"
echo " Listo. Archivos en supabase/esquema/"
ls -la "$SALIDA"
echo
echo " Revisa 01-esquema-public.sql antes de commitear: es el plano"
echo " completo de la base y debe quedar en el repo."
echo "──────────────────────────────────────────────────────────"
