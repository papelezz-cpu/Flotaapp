#!/usr/bin/env bash
#
# Imprime los PRIVILEGIOS POR OMISIÓN (pg_default_acl) del esquema public.
#
# ── Por qué existe ──────────────────────────────────────────────────────────
#
# R-07 lo dejó anotado el 2026-09-18: una diferencia en los privilegios por
# omisión es invisible hasta que alguien crea un objeto nuevo, y entonces se
# manifiesta como diferencia *de ese objeto*.
#
# ⚠ **Desde el 2026-09-24 `pg_default_acl` SÍ es una dimensión de
#   verificar-paridad.sh** (`acl_por_defecto`, la 19ª). Antes no lo era, y este
#   guion existía porque era la única forma de mirarlo. Sigue siendo útil para
#   LEER una sola base y entender qué concede —la salida es legible, la del
#   verificador es un diff— pero **la comparación ya no depende de que alguien
#   se acuerde de correrlo dos veces**.
#
# Ocurrió esa misma noche. Al aplicar 20260918150000 a los dos proyectos, las
# dos funciones nuevas salieron con EXECUTE para service_role en producción y
# sin él en pruebas — con la MISMA migración, que no menciona service_role por
# ningún lado. No lo dio la migración: lo dio el esquema.
#
#   produccion  reporte_kpis()|service_role|true
#   pruebas     reporte_kpis()|service_role|false
#
# Igualar esas dos funciones a mano no arregla nada: la siguiente que se cree
# volverá a divergir. Lo que hay que comparar es esto.
#
# ── Qué hace ────────────────────────────────────────────────────────────────
#
# Solo LEE. Una consulta a un catálogo del sistema, sin escribir nada. Pide la
# cadena de conexión por teclado en vez de aceptarla como argumento, para que
# no acabe en el historial de la terminal — y por eso tampoco lleva el candado
# de "no apuntes a producción": leer producción aquí es justo lo que hace falta.
#
# Uso:
#   bash supabase/ver-privilegios-por-omision.sh produccion
#   bash supabase/ver-privilegios-por-omision.sh pruebas
#
# Se corre UNA VEZ POR PROYECTO, para poder comparar las dos salidas. El
# argumento solo sirve para que los mensajes de error digan qué usuario
# esperaba la cadena (postgres.<ref>), que es donde casi siempre falla.
#
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -uo pipefail
export PGCLIENTENCODING=UTF8
source "$AQUI/lib-conexion.sh"

case "${1:-}" in
  produccion|prod) ETIQUETA="PRODUCCIÓN"; REF="xnyqsewaluezkkrlyhxg" ;;
  pruebas|dev)    ETIQUETA="el proyecto DE PRUEBAS"; REF="xskgnudiznryhgagxadu" ;;
  *)
    echo "Uso: bash supabase/ver-privilegios-por-omision.sh [produccion|pruebas]" >&2
    echo "     Solo lee. Corre los dos y compara las salidas." >&2
    exit 2 ;;
esac

conectar_a "$ETIQUETA" "$REF" PORTGO_DB_URL_LECTURA || exit 1

echo
echo "── Privilegios por omisión en el esquema public ──"
echo "   (quién los fijó · sobre qué tipo de objeto · qué concede)"
echo

psql "$(cadena_autonoma "$CONN")" -X -q -v ON_ERROR_STOP=1 <<'SQL'
select
  defaclrole::regrole::text as "fijado por",
  case defaclobjtype
    when 'r' then 'tablas y vistas'
    when 'S' then 'secuencias'
    when 'f' then 'funciones'
    when 'T' then 'tipos'
    when 'n' then 'esquemas'
    else defaclobjtype::text
  end                       as "sobre",
  defaclacl::text           as "concede"
from pg_default_acl
where defaclnamespace = 'public'::regnamespace
order by 1, 2;
SQL

echo
echo "  Cómo leer la columna «concede»: cada entrada es  destinatario=privilegios/otorgante."
echo "  Para funciones, X es EXECUTE. Así que  service_role=X/postgres  significa que"
echo "  toda función nueva creada por postgres nace con EXECUTE para service_role."
echo
echo "  Corre esto también contra el OTRO proyecto y compara las dos salidas."
echo
