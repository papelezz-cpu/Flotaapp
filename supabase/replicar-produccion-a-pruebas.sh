#!/usr/bin/env bash
#
# Deja portgo-pruebas siendo una COPIA FIEL de producción: mismo esquema,
# mismos permisos, mismos datos, mismos usuarios con las mismas contraseñas,
# misma publicación de Realtime, mismos buckets.
#
# Esto se corre ANTES de sembrar datos o de correr cualquier prueba. Sin eso,
# lo que pasa en pruebas no dice nada de lo que pasaría en producción: el
# 2026-08-27 pruebas tenía 82 permisos de función más abiertos que producción
# y la publicación de Realtime VACÍA mientras producción replicaba seis
# tablas. Las dos bases "funcionaban". No eran la misma base.
#
# ⚠ PRODUCCIÓN SOLO SE LEE. Ni una escritura, ni dentro de transacción.
# ⚠ PRUEBAS SE BORRA Y SE VUELVE A LLENAR. Eso es una operación destructiva y
#   por Regla #1 se pide autorización explícita antes, con el inventario de lo
#   que se va a perder a la vista.
#
# Uso:
#   PORTGO_DB_URL_PROD="postgresql://...xnyq..." \
#   PORTGO_DB_URL_PRUEBAS="postgresql://...xskg..." \
#   bash supabase/replicar-produccion-a-pruebas.sh [opciones]
#
#   --solo-datos   no reconstruye el esquema, solo vacía y recarga los datos
#                  (más rápido; úsalo cuando la última verificación dijo que
#                  la estructura ya era idéntica)
#   --solo-volcar  se queda en el volcado de producción y no toca pruebas
#   --desde-permisos  retoma en el paso 4 (permisos + verificación), sin volver
#                  a volcar ni reconstruir. Solo si el paso 3 ya terminó
#
# Los archivos del volcado quedan en supabase/espejo/, que está en .gitignore
# porque contiene datos personales reales de producción.
set -uo pipefail

REF_PRODUCCION="xnyqsewaluezkkrlyhxg"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ESPEJO="$RAIZ/supabase/espejo"
mkdir -p "$ESPEJO"

export PGCLIENTENCODING=UTF8

SOLO_DATOS=0; SOLO_VOLCAR=0; DESDE_PERMISOS=0
for a in "$@"; do
  case "$a" in
    --solo-datos)  SOLO_DATOS=1 ;;
    --solo-volcar) SOLO_VOLCAR=1 ;;
    --desde-permisos) DESDE_PERMISOS=1 ;;
    -h|--ayuda) sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "Opción desconocida: $a" >&2; exit 2 ;;
  esac
done

for bin in psql pg_dump; do
  command -v "$bin" >/dev/null 2>&1 || { echo "❌ Falta $bin (cliente de PostgreSQL)." >&2; exit 1; }
done

# ── Conexiones ────────────────────────────────────────────────────────────
source "$AQUI/lib-conexion.sh"

obtener() { # obtener <etiqueta> <ref> <var_env>
  local etiqueta="$1" ref="$2" var="$3"
  if [ -n "${!var:-}" ]; then printf '%s' "${!var}"; return 0; fi
  conectar_a "$etiqueta" "$ref" "$var" >&2 || return 1
  local c; c="$(cadena_autonoma "$CONN")"; unset PGPASSWORD
  printf '%s' "$c"
}

PROD="$(obtener "PRODUCCIÓN (solo lectura)" "$REF_PRODUCCION" PORTGO_DB_URL_PROD)" || exit 1
PRUE="$(obtener "el proyecto DE PRUEBAS (se sobrescribe)" "<ref-de-pruebas>" PORTGO_DB_URL_PRUEBAS)" || exit 1

_host() { local s="${1#*://}"; s="${s#*@}"; echo "${s%%/*}"; }

# psql.exe es un binario nativo de Windows y escribe la salida en modo texto:
# cada línea termina en CRLF. Al leerla desde bash, un nombre de tabla sale
# como "app_config\r" y `pg_dump --table public.app_config\r` no coincide con
# nada — que es exactamente cómo se cayó la primera corrida. `q` es psql para
# LEER: idéntico, pero sin el retorno de carro. Para aplicar archivos se sigue
# usando psql a secas. Con `set -o pipefail` el fallo de psql sigue viajando.
q() { psql "$@" | tr -d '\r'; }

# ── Candados. Van antes de cualquier cosa que escriba ─────────────────────
if [[ "$PRUE" == *"$REF_PRODUCCION"* ]]; then
  echo "❌ ALTO: el DESTINO es producción ($REF_PRODUCCION). Cancelado." >&2; exit 2
fi
if [ "$(_host "$PROD")" = "$(_host "$PRUE")" ]; then
  echo "❌ ALTO: origen y destino son el mismo host. Cancelado." >&2; exit 2
fi
if [[ "$PROD" != *"$REF_PRODUCCION"* ]]; then
  echo "❌ El ORIGEN no es producción ($REF_PRODUCCION)." >&2
  echo "   Copiar desde otro sitio dejaría pruebas pareciéndose a algo que no" >&2
  echo "   es lo que corre para los usuarios. Cancelado." >&2
  exit 2
fi
psql "$PROD" -Atc "select 1" >/dev/null || { echo "❌ Sin conexión a producción." >&2; exit 1; }
psql "$PRUE" -Atc "select 1" >/dev/null || { echo "❌ Sin conexión a pruebas." >&2; exit 1; }

echo
echo "══════════════════════════════════════════════════════════════════"
echo " PortGo · replicar producción -> pruebas"
echo "   origen : $(_host "$PROD")   (SOLO LECTURA)"
echo "   destino: $(_host "$PRUE")   (se sobrescribe)"
echo "══════════════════════════════════════════════════════════════════"
echo

if [ "$DESDE_PERMISOS" = "1" ]; then
  echo "── --desde-permisos: se saltan el volcado y la reconstrucción ──"
  echo "   Se retoma en el paso 4 con lo que ya está en supabase/espejo/."
  echo "   Úsalo solo si la corrida anterior llegó a terminar el paso 3."
  echo
fi

# ── 1. Volcado de producción ──────────────────────────────────────────────
if [ "$DESDE_PERMISOS" = "0" ]; then
echo "── 1/6 · Volcado de producción (solo lectura) ──"

echo -n "   esquema de public ....... "
pg_dump "$PROD" --schema-only --schema=public --no-publications --no-subscriptions \
        --no-owner -f "$ESPEJO/01-esquema-public.sql" && echo "ok"

echo -n "   esquema de storage ...... "
pg_dump "$PROD" --schema-only --schema=storage --no-publications --no-subscriptions \
        --no-owner -f "$ESPEJO/02-storage.sql" 2>/dev/null && echo "ok" || echo "sin acceso, se omite"

echo -n "   buckets ................. "
q "$PROD" -Atq -c "
  select format(
    'insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values (%L,%L,%L,%s,%s) on conflict (id) do update set name=excluded.name, public=excluded.public, file_size_limit=excluded.file_size_limit, allowed_mime_types=excluded.allowed_mime_types;',
    id, name, public,
    coalesce(file_size_limit::text,'null'),
    case when allowed_mime_types is null then 'null'
         else quote_literal(allowed_mime_types::text)||'::text[]' end)
    from storage.buckets order by id;" > "$ESPEJO/03-buckets.sql" && echo "$(wc -l < "$ESPEJO/03-buckets.sql" | tr -d ' ')"

# Orden de carga aproximado: padres antes que hijos donde se puede. Ya NO es
# lo que garantiza que la carga funcione —las FK se aplazan al final de la
# transacción, ver abrir_carga()— porque el grafo tiene un ciclo (pedidos y
# ofertas se apuntan mutuamente) y con un ciclo no existe ningún orden válido.
# Se conserva porque un volcado ordenado es más fácil de leer y de diagnosticar.
echo -n "   orden de carga .......... "
q "$PROD" -Atq -c "
  with recursive tablas as (
    select c.oid, c.relname::text as nombre
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relkind='r'
  ), fk as (
    select con.conrelid as hijo, con.confrelid as padre
      from pg_constraint con
      join tablas h on h.oid = con.conrelid
      join tablas p on p.oid = con.confrelid
     where con.contype='f' and con.conrelid <> con.confrelid
  ), nivel as (
    select t.oid, 0 as n from tablas t
     where not exists (select 1 from fk where fk.hijo = t.oid)
    union all
    select f.hijo, nv.n + 1 from nivel nv join fk f on f.padre = nv.oid where nv.n < 15
  )
  select t.nombre
    from tablas t
    left join (select oid, max(n) as n from nivel group by oid) x on x.oid = t.oid
   order by coalesce(x.n, 99), t.nombre;" > "$ESPEJO/orden-tablas.txt"
NTABLAS=$(wc -l < "$ESPEJO/orden-tablas.txt" | tr -d ' ')
echo "$NTABLAS tablas"

echo -n "   datos de public ......... "
: > "$ESPEJO/05-datos-public.sql"
while read -r t; do
  t="${t%$'\r'}"   # cinturón y tirantes: aunque el archivo ya viene limpio
  [ -z "$t" ] && continue
  pg_dump "$PROD" --data-only --no-owner --no-privileges --table "public.$t" \
    >> "$ESPEJO/05-datos-public.sql" || { echo; echo "   ❌ falló el volcado de $t"; exit 1; }
done < "$ESPEJO/orden-tablas.txt"
echo "$(du -h "$ESPEJO/05-datos-public.sql" | cut -f1)"

# auth.users y auth.identities van aparte y ANTES que los datos de public:
# media docena de tablas tienen FK contra auth.users. Se copia el hash de la
# contraseña tal cual, que es lo que permite entrar a pruebas con las mismas
# cuentas reales sin conocer ninguna contraseña.
echo -n "   usuarios de auth ........ "
pg_dump "$PROD" --data-only --no-owner --no-privileges --table auth.users \
  -f "$ESPEJO/06-auth-users.sql" 2>/dev/null && \
pg_dump "$PROD" --data-only --no-owner --no-privileges --table auth.identities \
  -f "$ESPEJO/06-auth-identities.sql" 2>/dev/null \
  && echo "$(q "$PROD" -Atc 'select count(*) from auth.users') usuarios" \
  || { echo "SIN ACCESO"; AUTH_FALLO=1; }

echo -n "   secuencias .............. "
q "$PROD" -Atq -c "
  select format('select setval(%L, %s, true);', schemaname||'.'||sequencename, last_value)
    from pg_sequences where schemaname='public' and last_value is not null;" \
  > "$ESPEJO/07-secuencias.sql" && echo "$(wc -l < "$ESPEJO/07-secuencias.sql" | tr -d ' ')"

echo -n "   publicación Realtime .... "
q "$PROD" -Atq -c "
  select stmt from (
    select 1 as o, 'drop publication if exists supabase_realtime;' as stmt
    union all
    select 2, format('create publication supabase_realtime%s with (publish = %L);',
             case when puballtables then ' for all tables' else '' end,
             array_to_string(array_remove(array[
               case when pubinsert then 'insert' end,
               case when pubupdate then 'update' end,
               case when pubdelete then 'delete' end,
               case when pubtruncate then 'truncate' end], null), ','))
      from pg_publication where pubname='supabase_realtime'
    union all
    select 3, format('alter publication supabase_realtime add table %I.%I;', t.schemaname, t.tablename)
      from pg_publication_tables t
      join pg_publication p on p.pubname = t.pubname
     where t.pubname='supabase_realtime' and not p.puballtables
  ) s order by o, stmt;" > "$ESPEJO/08-realtime.sql"
echo "$(grep -c 'add table' "$ESPEJO/08-realtime.sql" || true) tablas replicadas"

# La lista de objetos de Storage no copia los archivos (viven en S3, no en la
# base): la consume pruebas/04-copiar-archivos.mjs, que sí los baja y los sube.
echo -n "   lista de archivos ....... "
q "$PROD" -Atq -F $'\t' -c "
  select bucket_id, name from storage.objects where bucket_id is not null order by bucket_id, name;" \
  > "$ESPEJO/10-objetos.tsv" 2>/dev/null && echo "$(wc -l < "$ESPEJO/10-objetos.tsv" | tr -d ' ') objetos" || echo "sin acceso"

# Las extensiones que viven DENTRO de public se van con el DROP SCHEMA, y el
# volcado no las recrea: pg_dump --schema=public no emite un solo CREATE
# EXTENSION. En producción ahí está btree_gist, del que depende la restricción
# reservaciones_sin_solape (EXCLUDE USING gist). Sin recrearla antes, el
# esquema falla a media aplicación y pruebas queda inservible.
echo -n "   extensiones de public ... "
q "$PROD" -Atq -c "
  select format('create extension if not exists %I with schema %I;', e.extname, n.nspname)
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace
   where n.nspname = 'public' order by e.extname;" > "$ESPEJO/09b-extensiones-public.sql"
echo "$(wc -l < "$ESPEJO/09b-extensiones-public.sql" | tr -d ' ')"

# Los trabajos de pg_cron no están en public ni en el volcado: se listan aquí
# para poder compararlos. Un cron que corre en una base y no en la otra las
# separa cada vez que se dispara.
echo -n "   trabajos de cron ........ "
q "$PROD" -Atq -c "
  select coalesce(jobname,'')||' | '||schedule||' | activo='||active||' | '||
         replace(replace(command, chr(10), ' '), chr(13), '')
    from cron.job order by jobid;" > "$ESPEJO/11-cron.txt" 2>/dev/null \
  && echo "$(wc -l < "$ESPEJO/11-cron.txt" | tr -d ' ')" || echo "no legible"

# Y las sentencias para recrearlos. expire_stale_offers() corre cada hora en
# producción y mueve ofertas y pedidos: si pruebas no lo tiene, las dos bases
# se separan solas aunque la copia haya salido perfecta.
q "$PROD" -Atq -c "
  select format('select cron.schedule(%L, %L, %L);', jobname, schedule, command)||chr(10)||
         format('select cron.alter_job((select jobid from cron.job where jobname = %L), active := %L::boolean);', jobname, active)
    from cron.job where jobname is not null order by jobid;" > "$ESPEJO/11-cron.sql" 2>/dev/null || : > "$ESPEJO/11-cron.sql"

echo -n "   extensiones ............. "
q "$PROD" -Atq -c "
  select e.extname||' '||e.extversion||' en '||n.nspname
    from pg_extension e join pg_namespace n on n.oid=e.extnamespace order by 1;" \
  > "$ESPEJO/09-extensiones.txt" && echo "$(wc -l < "$ESPEJO/09-extensiones.txt" | tr -d ' ')"
echo

if [ "$SOLO_VOLCAR" = "1" ]; then
  echo "── --solo-volcar: pruebas no se tocó. Archivos en supabase/espejo/ ──"
  exit 0
fi

# ── 2. Autorización explícita (Regla #1) ──────────────────────────────────
echo "── 2/6 · Lo que se va a BORRAR en pruebas ──"
echo
INV_TABLAS=$(q "$PRUE" -Atc "select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE'")
INV_FILAS=$(q "$PRUE" -Atc "
  select coalesce(sum((xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', table_name), false, true, '')))[1]::text::bigint), 0)
    from information_schema.tables where table_schema='public' and table_type='BASE TABLE'" 2>/dev/null || echo '?')
INV_USUARIOS=$(q "$PRUE" -Atc "select count(*) from auth.users" 2>/dev/null || echo '?')
INV_OBJETOS=$(q "$PRUE" -Atc "select count(*) from storage.objects" 2>/dev/null || echo '?')
INV_CRON=$(q "$PRUE" -Atc "select count(*) from cron.job" 2>/dev/null || echo '0')

cat <<RESUMEN
  QUÉ  · base $(_host "$PRUE")
         - $INV_TABLAS tablas de public con $INV_FILAS filas en total
         - $INV_USUARIOS usuarios de auth (y sus sesiones)
         - metadatos de $INV_OBJETOS objetos de Storage
         - $INV_CRON trabajo(s) de cron: se desprograman y se ponen los de producción
$( [ "$SOLO_DATOS" = "0" ] && echo "         - el esquema public entero: se hace DROP SCHEMA ... CASCADE" )

  PARA QUÉ SIRVE · es el ambiente donde se prueban los cambios antes de
         producción. Todo lo que hay ahí es desechable POR DISEÑO: son datos
         de prueba o una copia vieja de producción. Nada de esto es la fuente
         de verdad de nada, y no hay usuario final que dependa de estas filas.

  POR QUÉ BORRARLO · para volver a llenarlo con el estado exacto de producción
         de hoy. Si se conservara lo que ya está, pruebas seguiría siendo una
         mezcla de datos viejos y datos de test, y una prueba que pasa ahí no
         probaría nada sobre producción — que es justo lo que se quiere evitar.

  SI SALE MAL · se pierde el estado actual de pruebas (recuperable volviendo a
         correr este guion) y, mientras corre, pruebas queda a medias. En
         PRODUCCIÓN no se escribe nada en ningún caso.

RESUMEN

cat <<'AVISO'
  ⚠ ANTES DE SEGUIR · el correo de pruebas debe estar bloqueado YA.
        En cuanto esta réplica termine, pruebas va a tener las direcciones
        REALES de los clientes y las empresas de producción. Si la salida de
        correo sigue activa, el primer flujo que dispare una notificación le
        escribe a un cliente de verdad. Se bloquea así:

          npx supabase secrets set CORREO_SALIDA=bloqueada --project-ref <ref-pruebas>
          npx supabase functions deploy enviar-notificacion --project-ref <ref-pruebas>

        y se comprueba con:  node pruebas/05-sonda-correo.mjs

AVISO

read -r -p "  Escribe REEMPLAZAR PRUEBAS para continuar: " OK
# Se acepta en minúsculas y con espacios de sobra. La salvaguarda es teclear la
# frase completa a propósito; acertarle a las mayúsculas no protege de nada y
# solo hace que una autorización real se pierda por un detalle. Un enter, una
# "s" o cualquier otra cosa siguen sin valer.
OK="$(printf '%s' "$OK" | tr -d '\r' | tr '[:lower:]' '[:upper:]' \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]]\{1,\}/ /g')"
if [ "$OK" != "REEMPLAZAR PRUEBAS" ]; then echo "  Cancelado. No se tocó nada."; exit 0; fi
echo

# ── 3. Reconstrucción ─────────────────────────────────────────────────────
echo "── 3/6 · Reconstruir pruebas ──"

# Tres líneas del volcado no aplican en un proyecto nuevo y las de ALTER
# DEFAULT PRIVILEGES son los permisos de fábrica de Supabase, a nombre de un
# rol de plataforma que postgres no puede tocar. Se neutralizan al vuelo para
# no alterar el volcado, que debe seguir siendo copia fiel de producción.
#
# -b (modo binario) NO es opcional aquí. El sed de Windows abre en modo texto y
# se come los retornos de carro: los 871 CR que trae el volcado están DENTRO de
# los cuerpos de 22 funciones —producción las tiene así porque se pegaron desde
# Windows en el editor de Supabase— y sin -b llegaban a pruebas sin ellos.
# Mismo comportamiento, texto distinto, dimensión de funciones divergiendo con
# toda la razón. Si el sed de turno no conoce -b, se sigue sin él y la
# verificación lo dirá; no se falla en silencio.
if sed -b '' </dev/null >/dev/null 2>&1; then SEDB="-b"; else SEDB=""; fi
limpiar_ddl() {
  sed ${SEDB:-} -E 's/^(CREATE SCHEMA public;|ALTER SCHEMA public OWNER TO .*;|COMMENT ON SCHEMA public IS .*;|ALTER DEFAULT PRIVILEGES .*;)/-- [omitido al aplicar] \1/'
}

if [ "$SOLO_DATOS" = "0" ]; then
  # TODO el esquema entra en UNA transacción: borrar public, recrearlo, poner
  # las extensiones que vivían dentro (btree_gist, de la que depende el EXCLUDE
  # de reservaciones_sin_solape) y aplicar el volcado.
  #
  # Por qué en una sola: Supabase tiene un event trigger que hace NOTIFY en
  # cada DDL para que PostgREST recargue su caché de esquema. Aplicando el
  # volcado sentencia por sentencia, PostgREST reintrospecciona decenas de
  # veces mientras nosotros seguimos creando objetos, y los dos procesos
  # terminan cruzándose los locks: "deadlock detected" a media aplicación, con
  # el esquema medio creado y pruebas inservible. Dentro de una transacción el
  # NOTIFY se dispara una sola vez, al commit, y si algo falla revierte entero:
  # pruebas se queda como estaba en vez de quedar a medias.
  reconstruir_esquema() {
    {
      echo "set lock_timeout = '60s';"
      echo "drop schema if exists public cascade;"
      echo "create schema public;"
      echo "grant usage on schema public to postgres, anon, authenticated, service_role;"
      echo "grant create on schema public to postgres;"
      [ -s "$ESPEJO/09b-extensiones-public.sql" ] && cat "$ESPEJO/09b-extensiones-public.sql"
      limpiar_ddl < "$ESPEJO/01-esquema-public.sql"
    } > "$ESPEJO/aplicar-esquema.sql"

    # -f archivo, NO una tubería. psql en Windows lee stdin en modo texto y
    # convierte CRLF en LF. Da igual para el SQL... salvo dentro de $$ ... $$,
    # que es un literal: 22 funciones de producción tienen CRLF en su cuerpo
    # (las pegaron desde Windows en el editor de Supabase) y al entrar por
    # tubería llegaban a pruebas sin esos CR. Mismo comportamiento, texto
    # distinto, y la dimensión de funciones divergía con toda la razón. Con -f
    # psql abre el archivo en binario y el cuerpo llega byte a byte.
    psql "$PRUE" --single-transaction -v ON_ERROR_STOP=1 -q -o /dev/null \
         -f "$ESPEJO/aplicar-esquema.sql" 2>"$ESPEJO/error-esquema.txt"
  }

  echo -n "   esquema completo ........ "
  INTENTO=1
  until reconstruir_esquema; do
    if [ "$INTENTO" -ge 3 ]; then
      echo "FALLÓ tras $INTENTO intentos"
      echo "   Error:"
      grep -iv "^NOTICE\|^DETAIL\|^drop cascades" "$ESPEJO/error-esquema.txt" | head -6 | sed 's/^/     /'
      echo
      echo "   La transacción revirtió, así que pruebas quedó como estaba antes"
      echo "   de este intento. Detalle completo:"
      echo "     psql \"<cadena-pruebas>\" --single-transaction -v ON_ERROR_STOP=1 -f supabase/espejo/01-esquema-public.sql"
      exit 1
    fi
    # Un deadlock es cuestión de con quién te cruzas, no de que la sentencia
    # esté mal: reintentar suele bastar. Y como revirtió entero, se reintenta
    # desde el mismo punto de partida, no sobre restos del intento anterior.
    echo -n "reintento $((INTENTO + 1))… "
    INTENTO=$((INTENTO + 1))
    sleep 3
  done
  echo "ok ($(grep -c '^CREATE TABLE' "$ESPEJO/01-esquema-public.sql") tablas, en una transacción)"

  # Las políticas de storage referencian funciones de public (is_superadmin),
  # así que el DROP SCHEMA ... CASCADE se las lleva por delante. Hay que
  # volver a ponerlas o pruebas dejaría de exigir que el primer tramo de la
  # ruta sea el auth.uid(), y las pruebas de archivos mentirían.
  echo -n "   políticas de storage .... "
  if [ -f "$ESPEJO/02-storage.sql" ]; then
    psql "$PRUE" -q -c "
      do \$\$ declare p record; begin
        for p in select policyname, tablename from pg_policies where schemaname='storage' loop
          execute format('drop policy if exists %I on storage.%I', p.policyname, p.tablename);
        end loop; end \$\$;" >/dev/null 2>&1
    awk '/^CREATE POLICY/ {c=1} c {print} /;[[:space:]]*$/ {c=0}' "$ESPEJO/02-storage.sql" \
      | psql "$PRUE" -q >/dev/null 2>&1
    echo "$(q "$PRUE" -Atc "select count(*) from pg_policies where schemaname='storage'") aplicadas"
  else
    echo "sin volcado, se omite"
  fi
fi

echo -n "   buckets ................. "
psql "$PRUE" -q -f "$ESPEJO/03-buckets.sql" >/dev/null 2>&1
echo "$(q "$PRUE" -Atc "select count(*) from storage.buckets")"

# Con --solo-datos el esquema sigue en pie: hay que vaciar las tablas antes de
# recargarlas o los INSERT chocarían contra las claves primarias.
if [ "$SOLO_DATOS" = "1" ]; then
  echo -n "   vaciar tablas ........... "
  psql "$PRUE" -v ON_ERROR_STOP=1 -q <<'SQL' >/dev/null || { echo "FALLÓ"; exit 1; }
do $$
declare s text;
begin
  select string_agg(format('public.%I', c.relname), ', ')
    into s
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r';
  if s is not null then execute 'truncate table '||s||' restart identity cascade'; end if;
end $$;
SQL
  echo "ok"
fi

# Los triggers de negocio (notificaciones, guardianes de transición) se apagan
# durante la carga. Si no, copiar una reservación de producción dispararía
# notificaciones nuevas y los guardianes rechazarían estados que en producción
# son perfectamente válidos: la copia saldría distinta del original.
apagar_triggers() { # apagar_triggers <disable|enable>
  psql "$PRUE" -v ON_ERROR_STOP=1 -q -c "
    do \$\$ declare t record; begin
      for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
                where n.nspname='public' and c.relkind='r' loop
        execute format('alter table public.%I $1 trigger user', t.relname);
      end loop; end \$\$;" >/dev/null
  [ "$1" = "disable" ] && TRIGGERS_APAGADOS=1 || TRIGGERS_APAGADOS=0
  return 0
}

# Si la corrida se corta a media carga (Ctrl+C, la red, un error), los triggers
# no pueden quedarse apagados: una base con los guardianes desactivados acepta
# transiciones que producción rechaza, y sería la peor forma de divergir —
# invisible, y justo en lo que las pruebas intentan comprobar.
TRIGGERS_APAGADOS=0
trap '[ "$TRIGGERS_APAGADOS" = "1" ] && apagar_triggers enable >/dev/null 2>&1' EXIT

# Los usuarios, en una sola transacción: borrar los de pruebas y poner los de
# producción tiene que ser todo o nada. A medias deja una base sin cuentas con
# las que entrar, que es peor que no haber empezado.
echo -n "   usuarios de auth ........ "
if [ -f "$ESPEJO/06-auth-users.sql" ] && [ -z "${AUTH_FALLO:-}" ]; then
  if { echo "set lock_timeout = '60s';"
       echo "delete from auth.identities;"
       echo "delete from auth.users;"
       cat "$ESPEJO/06-auth-users.sql"
       cat "$ESPEJO/06-auth-identities.sql"
     } | psql "$PRUE" --single-transaction -v ON_ERROR_STOP=1 -q -o /dev/null 2>"$ESPEJO/error-auth.txt"; then
    echo "$(q "$PRUE" -Atc 'select count(*) from auth.users') copiados"
  else
    echo "FALLÓ"
    grep -i "error" "$ESPEJO/error-auth.txt" | head -3 | sed 's/^/     /'
    echo "   Revirtió entero. Sin los usuarios de producción las cuentas reales"
    echo "   no entran en pruebas y el flujo completo no se puede correr."
    exit 1
  fi
else
  echo "no se pudieron leer de producción"
fi

# Los datos, igual: apagar triggers, cargar y volver a encenderlos dentro de la
# misma transacción. Si algo revienta a media carga, revierte todo —incluido el
# apagado de los triggers—, en vez de dejar una base con los guardianes
# desactivados, que es la peor forma de divergir: invisible.
abrir_carga() {
cat <<'SQL'
set lock_timeout = '60s';

-- Los triggers de negocio se apagan: copiar una reservación de producción no
-- debe disparar notificaciones nuevas, y los guardianes de transición
-- rechazarían estados que en producción son perfectamente válidos.
do $$ declare t record; begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r'
  loop execute format('alter table public.%I disable trigger user', t.relname); end loop;
end $$;

-- Y las claves foráneas se aplazan al final de la transacción. NO es una
-- comodidad para no pensar el orden: pedidos.oferta_pendiente_id apunta a
-- ofertas y ofertas.pedido_id apunta a pedidos, así que el grafo tiene un
-- ciclo y no existe ningún orden de carga que las satisfaga fila por fila.
do $$ declare c record; begin
  for c in select conrelid::regclass::text as t, conname from pg_constraint
            where contype = 'f' and connamespace = 'public'::regnamespace
  loop execute format('alter table %s alter constraint %I deferrable initially deferred', c.t, c.conname); end loop;
end $$;
SQL
}

cerrar_carga() {
cat <<'SQL'
-- Aquí se comprueban TODAS las claves foráneas aplazadas, de golpe. Si un dato
-- no cuadra, revienta en esta línea y revierte la transacción entera: aplazar
-- no es dejar pasar, es comprobar al final.
--
-- Y va ANTES de los ALTER de abajo por una razón concreta: Postgres se niega a
-- hacer ALTER TABLE sobre una tabla que todavía tiene comprobaciones en cola
-- ("cannot ALTER TABLE ... because it has pending trigger events"). Primero se
-- vacía la cola, después se toca la definición.
set constraints all immediate;

-- Devueltas a su definición original, que es como están en producción: si se
-- quedaran DEFERRABLE, la dimensión de restricciones saldría divergente y con
-- razón, porque no serían las mismas restricciones.
do $$ declare c record; begin
  for c in select conrelid::regclass::text as t, conname from pg_constraint
            where contype = 'f' and connamespace = 'public'::regnamespace
  loop execute format('alter table %s alter constraint %I not deferrable', c.t, c.conname); end loop;
end $$;

do $$ declare t record; begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r'
  loop execute format('alter table public.%I enable trigger user', t.relname); end loop;
end $$;
SQL
}

echo -n "   datos de public ......... "
if { abrir_carga
     cat "$ESPEJO/05-datos-public.sql"
     cerrar_carga
     cat "$ESPEJO/07-secuencias.sql"
   } | psql "$PRUE" --single-transaction -v ON_ERROR_STOP=1 -q -o /dev/null 2>"$ESPEJO/error-datos.txt"; then
  echo "ok ($(q "$PRUE" -Atc "select coalesce(sum((xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', table_name), false, true, '')))[1]::text::bigint),0) from information_schema.tables where table_schema='public' and table_type='BASE TABLE'") filas)"
else
  echo "FALLÓ"
  grep -i "error" "$ESPEJO/error-datos.txt" | head -4 | sed 's/^/     /'
  echo "   Revirtió entero: los triggers quedaron encendidos y pruebas sin los"
  echo "   datos a medias. Detalle completo en supabase/espejo/error-datos.txt"
  exit 1
fi

echo -n "   publicación Realtime .... "
if psql "$PRUE" -v ON_ERROR_STOP=1 -q -f "$ESPEJO/08-realtime.sql" >/dev/null 2>&1; then
  echo "$(q "$PRUE" -Atc "select count(*) from pg_publication_tables where pubname='supabase_realtime'") tablas"
else
  echo "FALLÓ — revísalo a mano (supabase/espejo/08-realtime.sql)"
fi

# No se aborta si pg_cron no está en pruebas: a estas alturas ya está todo lo
# demás copiado, y la verificación final lo va a marcar como divergencia con
# nombre y apellido. Mejor eso que tirar la corrida entera al final.
echo -n "   trabajos de cron ........ "
if [ ! -s "$ESPEJO/11-cron.sql" ]; then
  echo "producción no tiene, no se crea ninguno"
elif ! q "$PRUE" -Atc "select to_regclass('cron.job') is not null" 2>/dev/null | grep -q '^t$'; then
  echo "pg_cron NO está instalado en pruebas"
  echo "     Actívalo en el panel de pruebas → Database → Extensions → pg_cron"
  echo "     y vuelve a correr. Mientras tanto expire_stale_offers() corre cada"
  echo "     hora en producción y en pruebas no: las bases se separan solas."
else
  psql "$PRUE" -q -c "select cron.unschedule(jobid) from cron.job;" >/dev/null 2>&1
  if psql "$PRUE" -v ON_ERROR_STOP=1 -q -f "$ESPEJO/11-cron.sql" >/dev/null 2>&1; then
    echo "$(q "$PRUE" -Atc "select count(*) from cron.job") programados"
  else
    echo "FALLÓ — revísalo a mano (supabase/espejo/11-cron.sql)"
  fi
fi
echo

fi   # fin de --desde-permisos: aquí terminan los pasos 1 a 3

# ── 4. Permisos de función ────────────────────────────────────────────────
# Van aparte porque no viajan en el volcado: el ALTER DEFAULT PRIVILEGES de
# Supabase concede EXECUTE a anon en cada CREATE FUNCTION, y pg_dump no emite
# los REVOKE que en producción ya estaban hechos. Sin este paso pruebas queda
# siempre más permisiva que producción.
echo "── 4/6 · Permisos de función ──"
PORTGO_DB_URL_PROD="$PROD" PORTGO_DB_URL_PRUEBAS="$PRUE" bash "$AQUI/alinear-permisos-pruebas.sh" \
  | sed 's/^/   /' || echo "   ⚠ la alineación de permisos terminó con error"
echo

# ── 5. Extensiones (se informa, no se toca) ───────────────────────────────
echo "── 5/6 · Extensiones ──"
q "$PRUE" -Atq -c "
  select e.extname||' '||e.extversion||' en '||n.nspname
    from pg_extension e join pg_namespace n on n.oid=e.extnamespace order by 1;" > "$ESPEJO/09-extensiones-pruebas.txt"
if diff -q "$ESPEJO/09-extensiones.txt" "$ESPEJO/09-extensiones-pruebas.txt" >/dev/null; then
  echo "   ✓ las mismas extensiones en las dos bases"
else
  echo "   ⚠ difieren. Instalar extensiones necesita privilegios que este guion"
  echo "     no usa a propósito; hazlo desde el panel de Supabase:"
  diff "$ESPEJO/09-extensiones.txt" "$ESPEJO/09-extensiones-pruebas.txt" | sed 's/^/     /' | head -12
fi
echo

# Inventario de los archivos que hay en pruebas. Solo lectura, y lo consume
# pruebas/04-copiar-archivos.mjs para saber cuáles sobran: subir los 357 de
# producción no basta si en pruebas quedan otros que producción no tiene.
q "$PRUE" -Atq -F $'\t' -c "
  select bucket_id, name from storage.objects where bucket_id is not null
   order by bucket_id, name;" > "$ESPEJO/12-objetos-pruebas.tsv" 2>/dev/null \
  || : > "$ESPEJO/12-objetos-pruebas.tsv"

# ── 6. Verificación ───────────────────────────────────────────────────────
echo "── 6/6 · Verificación de paridad ──"
echo
PORTGO_DB_URL_PROD="$PROD" PORTGO_DB_URL_PRUEBAS="$PRUE" bash "$AQUI/verificar-paridad.sh"
VEREDICTO=$?

echo
echo "══════════════════════════════════════════════════════════════════"
if [ "$VEREDICTO" -eq 0 ]; then
  echo " Falta lo que no vive en la base:"
  echo
  echo "   1. Archivos de Storage (los bytes viven en S3, no en Postgres):"
  echo "        node pruebas/04-copiar-archivos.mjs"
  echo "      Sin esto, todo documento o evidencia abierto desde pruebas da 404."
  echo
  echo "   2. Edge Functions con el MISMO código que producción y el secreto"
  echo "      que bloquea el correo — la única diferencia permitida:"
  echo "        npx supabase functions deploy enviar-notificacion --project-ref <ref-pruebas>"
  echo "        npx supabase functions deploy gestionar-usuario   --project-ref <ref-pruebas>"
  echo "        npx supabase secrets set CORREO_SALIDA=bloqueada  --project-ref <ref-pruebas>"
  echo "      Compruébalo con: node pruebas/05-sonda-correo.mjs"
  echo
  echo "   3. Panel de pruebas -> Authentication -> Emails: apagar los correos"
  echo "      de Supabase (confirmación, recuperación). Ahora pruebas tiene las"
  echo "      direcciones REALES de los clientes de producción."
else
  echo " ⚠ La verificación NO dio paridad. Revisa las diferencias de arriba"
  echo "   antes de sembrar o probar nada."
fi
echo "══════════════════════════════════════════════════════════════════"
exit "$VEREDICTO"
