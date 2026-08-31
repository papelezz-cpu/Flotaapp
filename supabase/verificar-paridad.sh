#!/usr/bin/env bash
#
# ¿portgo-pruebas es de verdad una copia de producción?
#
# Compara las dos bases dimensión por dimensión y deja un sello en
# supabase/espejo/paridad.json. Los guiones de siembra y de flujo (pruebas/)
# leen ese sello y se niegan a correr si dice que las bases divergen: sin eso,
# una prueba "verde" en pruebas no prueba nada sobre producción.
#
# ⚠ SOLO LEE. No escribe una sola fila en ninguna de las dos bases.
#
# Uso:
#   PORTGO_DB_URL_PROD="postgresql://...xnyq..." \
#   PORTGO_DB_URL_PRUEBAS="postgresql://...xskg..." \
#   bash supabase/verificar-paridad.sh [--rapido] [--detalle]
#
#   --rapido   omite el hash de contenido tabla por tabla (lo más caro)
#   --detalle  imprime las líneas que difieren, no solo cuántas
#
# La única diferencia PERMITIDA entre las dos bases es la salida de correo,
# que en pruebas está bloqueada (secreto CORREO_SALIDA=bloqueada en la Edge
# Function enviar-notificacion). Eso no se ve desde SQL: se declara aquí y se
# comprueba aparte, con node pruebas/05-sonda-correo.mjs
set -uo pipefail

REF_PRODUCCION="xnyqsewaluezkkrlyhxg"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ESPEJO="$RAIZ/supabase/espejo"
Q="$ESPEJO/consultas"
SELLO="$ESPEJO/paridad.json"
mkdir -p "$Q"

export PGCLIENTENCODING=UTF8

RAPIDO=0; DETALLE=0
for a in "$@"; do
  case "$a" in
    --rapido)  RAPIDO=1 ;;
    --detalle) DETALLE=1 ;;
    -h|--ayuda) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "Opción desconocida: $a" >&2; exit 2 ;;
  esac
done

# ── Conexiones ────────────────────────────────────────────────────────────
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-conexion.sh"

# La contraseña se incrusta en cada cadena y PGPASSWORD se limpia: son dos
# bases distintas en la misma corrida y PGPASSWORD es una sola variable.
obtener() { # obtener <etiqueta> <ref> <var_env>
  local etiqueta="$1" ref="$2" var="$3"
  if [ -n "${!var:-}" ]; then printf '%s' "${!var}"; return 0; fi
  conectar_a "$etiqueta" "$ref" "$var" >&2 || return 1
  local c; c="$(cadena_autonoma "$CONN")"; unset PGPASSWORD
  printf '%s' "$c"
}

PROD="$(obtener "PRODUCCIÓN (solo lectura)" "$REF_PRODUCCION" PORTGO_DB_URL_PROD)" || exit 1
PRUE="$(obtener "el proyecto DE PRUEBAS" "<ref-de-pruebas>" PORTGO_DB_URL_PRUEBAS)" || exit 1

_host() { local s="${1#*://}"; s="${s#*@}"; echo "${s%%/*}"; }

# El host del pooler es compartido (aws-N-....pooler.supabase.com): no dice a
# qué proyecto se conectó. El ref va en el usuario, postgres.<ref>, y es lo que
# el sello tiene que guardar para que los guiones de pruebas/ puedan comprobar
# que la verificación fue contra SU base y no contra otra cualquiera.
_ref() {
  local u="${1#*://}"; u="${u%%@*}"; u="${u%%:*}"
  case "$u" in postgres.*) echo "${u#postgres.}" ;; *) _host "$1" ;; esac
}

if [ "$(_host "$PROD")" = "$(_host "$PRUE")" ]; then
  echo "ALTO: origen y destino son el mismo host. Revisa las cadenas." >&2; exit 2
fi
if [[ "$PRUE" == *"$REF_PRODUCCION"* ]]; then
  echo "ALTO: el destino es PRODUCCIÓN. Las cadenas están cruzadas." >&2; exit 2
fi
if [[ "$PROD" != *"$REF_PRODUCCION"* ]]; then
  echo "⚠ El origen no menciona el ref de producción ($REF_PRODUCCION)."
  echo "  Se compara igual, pero el sello dirá contra qué se comparó."
fi

for par in "PRODUCCIÓN:$PROD" "PRUEBAS:$PRUE"; do
  if ! psql "${par#*:}" -Atc "select 1" >/dev/null 2>&1; then
    echo "No se pudo conectar a ${par%%:*}." >&2; exit 1
  fi
done

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

# ── Dimensiones ───────────────────────────────────────────────────────────
# Cada una es una consulta que devuelve una línea por objeto. Se corre igual
# en las dos bases, se ordena y se comparan. Lo que no aparece aquí no se está
# verificando: por eso la lista es larga a propósito.
ORDEN=()
dim() { local n="$1"; ORDEN+=("$n"); cat > "$Q/$n.sql"; }

dim columnas <<'SQL'
select c.relname||'|'||a.attname||'|'||format_type(a.atttypid, a.atttypmod)||'|'||
       a.attnotnull||'|'||coalesce(pg_get_expr(d.adbin, d.adrelid), '')
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
 where c.relkind in ('r','v','m','p');
SQL

dim restricciones <<'SQL'
select c.conrelid::regclass::text||'|'||c.conname||'|'||pg_get_constraintdef(c.oid)
  from pg_constraint c
  join pg_namespace n on n.oid = c.connamespace and n.nspname = 'public';
SQL

dim indices <<'SQL'
select indexdef from pg_indexes where schemaname = 'public';
SQL

dim rls <<'SQL'
select c.relname||'|'||c.relrowsecurity||'|'||c.relforcerowsecurity
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
 where c.relkind = 'r';
SQL

dim politicas <<'SQL'
select tablename||'|'||policyname||'|'||coalesce(permissive,'')||'|'||
       coalesce(array_to_string(roles, ','), '')||'|'||cmd||'|'||
       coalesce(qual,'')||'|'||coalesce(with_check,'')
  from pg_policies where schemaname = 'public';
SQL

dim triggers <<'SQL'
-- tgenabled es de tipo "char", no text: sin el cast, el || no encuentra
-- operador y la dimensión entera se queda sin verificar.
select c.relname||'|'||t.tgname||'|'||t.tgenabled::text||'|'||pg_get_triggerdef(t.oid)
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
 where not t.tgisinternal;
SQL

dim funciones <<'SQL'
select p.proname||'('||pg_get_function_identity_arguments(p.oid)||')|'||
       p.prosecdef||'|'||coalesce(array_to_string(p.proconfig, ','), '')||'|'||
       md5(coalesce(p.prosrc, ''))
  from pg_proc p where p.pronamespace = 'public'::regnamespace;
SQL

dim permisos_funcion <<'SQL'
select p.proname||'('||pg_get_function_identity_arguments(p.oid)||')|'||r||'|'||
       has_function_privilege(r, p.oid, 'EXECUTE')
  from pg_proc p, unnest(array['anon','authenticated','service_role']) r
 where p.pronamespace = 'public'::regnamespace;
SQL

dim permisos_tabla <<'SQL'
select c.relname||'|'||r||'|'||pr||'|'||has_table_privilege(r, c.oid, pr)
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public',
       unnest(array['anon','authenticated','service_role']) r,
       unnest(array['SELECT','INSERT','UPDATE','DELETE']) pr
 where c.relkind in ('r','v','p');
SQL

dim extensiones <<'SQL'
select e.extname||'|'||e.extversion||'|'||n.nspname
  from pg_extension e join pg_namespace n on n.oid = e.extnamespace;
SQL

dim realtime <<'SQL'
select 'publicacion|'||p.pubname||'|'||p.pubinsert||p.pubupdate||p.pubdelete||p.pubtruncate
  from pg_publication p
union all
select 'tabla|'||schemaname||'.'||tablename
  from pg_publication_tables where pubname = 'supabase_realtime';
SQL

# pg_cron está instalado en producción. Un trabajo programado que corra en una
# base y no en la otra las separa cada vez que se dispara, y no aparece en
# ninguna de las demás dimensiones. El guardia de to_regclass evita que la
# consulta reviente donde pg_cron no exista: ahí devuelve una línea que dice
# justo eso, y la comparación la detecta como la diferencia que es.
dim cron <<'SQL'
select coalesce(
         (xpath('/table/row/c/text()',
                query_to_xml($q$ select string_agg(coalesce(jobname,'')||'|'||schedule||'|'||active||'|'||
                                                   replace(replace(command, chr(10), ' '), chr(13), ''),
                                                   chr(10) order by jobid) as c from cron.job $q$,
                             false, true, '')))[1]::text,
         '(sin trabajos de cron)')
  where to_regclass('cron.job') is not null
union all
select '(pg_cron no instalado)'
  where to_regclass('cron.job') is null;
SQL

dim buckets <<'SQL'
select id||'|'||name||'|'||public||'|'||coalesce(file_size_limit::text,'')||'|'||
       coalesce(allowed_mime_types::text,'')
  from storage.buckets;
SQL

dim politicas_storage <<'SQL'
select tablename||'|'||policyname||'|'||cmd||'|'||coalesce(array_to_string(roles,','),'')||'|'||
       coalesce(qual,'')||'|'||coalesce(with_check,'')
  from pg_policies where schemaname = 'storage';
SQL

# ── Datos ─────────────────────────────────────────────────────────────────
# Conteo EXACTO, no la estimación de pg_stat_user_tables: esa se desfasa entre
# un ANALYZE y el siguiente, y aquí un "casi igual" no sirve de nada.
dim filas <<'SQL'
select t.table_name||'|'||
       (xpath('/row/c/text()',
              query_to_xml(format('select count(*) as c from public.%I', t.table_name),
                           false, true, '')))[1]::text
  from information_schema.tables t
 where t.table_schema = 'public' and t.table_type = 'BASE TABLE';
SQL

# La contraseña se compara por hash: no sale de la base, pero si en pruebas no
# es la misma, las cuentas reales no entran y la prueba no reproduce nada.
dim usuarios <<'SQL'
select u.id::text||'|'||coalesce(u.email,'')||'|'||md5(coalesce(u.encrypted_password,''))||'|'||
       coalesce(u.role,'')||'|'||(u.email_confirmed_at is not null)::text||'|'||
       md5(coalesce(u.raw_user_meta_data::text,''))
  from auth.users u;
SQL

dim archivos <<'SQL'
select bucket_id||'|'||count(*)||'|'||md5(string_agg(name, ',' order by name))
  from storage.objects group by bucket_id;
SQL

# El hash de contenido es la única dimensión que compara los DATOS de verdad,
# fila por fila y columna por columna. Las demás comparan estructura o conteos,
# y dos tablas con el mismo número de filas pueden decir cosas distintas.
if [ "$RAPIDO" = "0" ]; then
dim contenido <<'SQL'
select t.table_name||'|'||
       (xpath('/row/c/text()',
              query_to_xml(
                format('select md5(coalesce(string_agg(h, '','' order by h), '''')) as c from (select md5(x::text) as h from public.%I x) s',
                       t.table_name),
                false, true, '')))[1]::text
  from information_schema.tables t
 where t.table_schema = 'public' and t.table_type = 'BASE TABLE';
SQL
fi

etiqueta() {
  case "$1" in
    columnas)          echo "tablas y columnas" ;;
    restricciones)     echo "PK / FK / UNIQUE / CHECK" ;;
    indices)           echo "índices" ;;
    rls)               echo "RLS activo por tabla" ;;
    politicas)         echo "políticas RLS de public" ;;
    triggers)          echo "triggers" ;;
    funciones)         echo "funciones (cuerpo y search_path)" ;;
    permisos_funcion)  echo "permisos EXECUTE por rol" ;;
    permisos_tabla)    echo "permisos de tabla por rol" ;;
    extensiones)       echo "extensiones instaladas" ;;
    realtime)          echo "publicación Realtime" ;;
    cron)              echo "trabajos programados (pg_cron)" ;;
    buckets)           echo "buckets de Storage" ;;
    politicas_storage) echo "políticas sobre storage.objects" ;;
    filas)             echo "filas por tabla (conteo exacto)" ;;
    usuarios)          echo "usuarios de auth (id, correo, clave)" ;;
    archivos)          echo "objetos en Storage" ;;
    contenido)         echo "contenido de cada tabla (hash)" ;;
    *)                 echo "$1" ;;
  esac
}

echo "──────────────────────────────────────────────────────────────────"
echo " PortGo · paridad producción <-> pruebas"
echo " origen : $(_host "$PROD")   (solo lectura)"
echo " destino: $(_host "$PRUE")"
[ "$RAPIDO" = "1" ] && echo " modo   : --rapido (sin hash de contenido)"
echo "──────────────────────────────────────────────────────────────────"
echo

TOTAL_DIF=0
NO_VERIFICADAS=0
JSON_DIM=""

for n in "${ORDEN[@]}"; do
  eti="$(etiqueta "$n")"
  # tr -d '\r': psql.exe escribe CRLF en Windows. Las dos bases lo traen igual,
  # así que la comparación no se rompe, pero el detalle impreso saldría lleno
  # de ^M y las líneas serían más difíciles de leer justo cuando importa.
  psql "$PROD" -Atq -f "$Q/$n.sql" 2>"$D/$n.errA" | tr -d '\r' | sort > "$D/$n.a"
  psql "$PRUE" -Atq -f "$Q/$n.sql" 2>"$D/$n.errB" | tr -d '\r' | sort > "$D/$n.b"

  # Una dimensión que no se puede leer NO cuenta como igual. Ese fue justo el
  # error de agosto: dar por buena una base porque nadie miró la publicación.
  if [ -s "$D/$n.errA" ] || [ -s "$D/$n.errB" ]; then
    printf '  ?  %-38s no verificable\n' "$eti"
    cat "$D/$n.errA" "$D/$n.errB" 2>/dev/null | head -2 | cut -c1-100 | sed 's/^/       /'
    NO_VERIFICADAS=$((NO_VERIFICADAS + 1))
    JSON_DIM="$JSON_DIM    \"$n\": \"no_verificable\",\n"
    continue
  fi

  soloA=$(comm -23 "$D/$n.a" "$D/$n.b" | wc -l | tr -d ' ')
  soloB=$(comm -13 "$D/$n.a" "$D/$n.b" | wc -l | tr -d ' ')
  dif=$((soloA + soloB))

  if [ "$dif" -eq 0 ]; then
    printf '  ✓  %-38s %s líneas idénticas\n' "$eti" "$(wc -l < "$D/$n.a" | tr -d ' ')"
    JSON_DIM="$JSON_DIM    \"$n\": \"identica\",\n"
  else
    printf '  ✗  %-38s %s diferencias (%s solo en prod, %s solo en pruebas)\n' \
           "$eti" "$dif" "$soloA" "$soloB"
    TOTAL_DIF=$((TOTAL_DIF + dif))
    JSON_DIM="$JSON_DIM    \"$n\": \"diverge:$dif\",\n"
    if [ "$DETALLE" = "1" ]; then
      comm -23 "$D/$n.a" "$D/$n.b" | head -12 | cut -c1-160 | sed 's/^/       - solo en produccion: /'
      comm -13 "$D/$n.a" "$D/$n.b" | head -12 | cut -c1-160 | sed 's/^/       + solo en pruebas   : /'
    else
      comm -3 "$D/$n.a" "$D/$n.b" | head -4 | cut -c1-140 | sed 's/^/       /'
      [ "$dif" -gt 4 ] && echo "       ... ($((dif - 4)) más; corre con --detalle)"
    fi
  fi
done

echo
echo "──────────────────────────────────────────────────────────────────"
if [ "$TOTAL_DIF" -eq 0 ] && [ "$NO_VERIFICADAS" -eq 0 ]; then
  VEREDICTO="identicas"
  echo " ✓ PARIDAD. Hoy pruebas es la misma base que producción."
elif [ "$TOTAL_DIF" -eq 0 ]; then
  VEREDICTO="incompleta"
  echo " ⚠ Sin diferencias en lo comparado, pero $NO_VERIFICADAS dimensión(es)"
  echo "   no se pudieron leer. No se puede afirmar paridad."
else
  VEREDICTO="diverge"
  echo " ✗ DIVERGEN: $TOTAL_DIF diferencias."
  echo "   Corre  bash supabase/replicar-produccion-a-pruebas.sh  antes de"
  echo "   sembrar o probar nada. Una prueba sobre esta base no dice qué"
  echo "   pasaría en producción."
fi
echo "──────────────────────────────────────────────────────────────────"
echo
echo " Diferencia declarada y PERMITIDA (no se ve desde SQL):"
echo "   · salida de correo bloqueada en pruebas — Edge Function"
echo "     enviar-notificacion con el secreto CORREO_SALIDA=bloqueada."
echo "     Compruébalo con:  node pruebas/05-sonda-correo.mjs"
echo

printf '{\n  "verificado_en": "%s",\n  "origen_ref": "%s",\n  "destino_ref": "%s",\n  "veredicto": "%s",\n  "diferencias": %s,\n  "no_verificables": %s,\n  "modo": "%s",\n  "excepcion_declarada": "salida de correo bloqueada en pruebas (CORREO_SALIDA=bloqueada)",\n  "dimensiones": {\n%s  }\n}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$(_ref "$PROD")" "$(_ref "$PRUE")" \
  "$VEREDICTO" "$TOTAL_DIF" "$NO_VERIFICADAS" \
  "$([ "$RAPIDO" = "1" ] && echo rapido || echo completo)" \
  "$(printf "$JSON_DIM" | sed '$ s/,$//')" > "$SELLO"

echo " Sello escrito en supabase/espejo/paridad.json"
echo " (los guiones de pruebas/ lo leen y se niegan a correr si dice 'diverge')"
echo

[ "$VEREDICTO" = "identicas" ] && exit 0 || exit 1
