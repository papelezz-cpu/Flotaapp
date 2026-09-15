-- Cuánto cuesta Realtime en ESTA base, y si lo que se replica sirve de algo.
-- Solo lee. Se corre contra PRODUCCIÓN: es la única donde el dato significa algo,
-- porque mide uso real acumulado.
--
-- ── Por qué existe ────────────────────────────────────────────────────────
--
-- La 2ª auditoría (2026-08-28) midió que la decodificación WAL de Realtime se
-- llevaba el 84 % del tiempo de CPU de la base: 680 007 llamadas y 64,8 minutos,
-- frente a los 22 segundos de TODAS las consultas de la aplicación juntas.
--
-- Después de eso se aplicaron dos migraciones —20260828120000 y
-- 20260828160000— que dejaron la publicación declarativa y sacaron las tablas
-- que nadie escuchaba. Nunca se volvió a medir. La 3ª auditoría no pudo
-- hacerlo: trabajó sobre un volcado, no sobre la base viva.
--
-- Esta sonda responde tres preguntas, en orden de importancia.

\echo ''
\echo '════════════════════════════════════════════════════════════════'
\echo ' 1. ¿Sigue Realtime dominando el gasto de la base?'
\echo '════════════════════════════════════════════════════════════════'
\echo '    Compara con el 2026-08-28: WAL 84,0 % · aplicacion 0,48 %.'
\echo '    Si el reparto sigue igual, las migraciones de agosto no bastaron.'

SELECT
  CASE
    WHEN query LIKE 'SELECT wal->>%'  THEN 'Realtime — decodificacion WAL'
    WHEN query LIKE '%pgrst_source%'  THEN 'Aplicacion (PostgREST)'
    WHEN query LIKE '%pg_timezone%'
      OR query LIKE '%pg_catalog.pg_type%' THEN 'PostgREST — recarga de esquema'
    ELSE 'Resto (backups, catalogos, auth)'
  END AS concepto,
  sum(calls)                                   AS llamadas,
  round(sum(total_exec_time)::numeric / 1000, 1) AS segundos,
  -- El cast va FUERA de la division: sum(sum(...)) OVER () devuelve double
  -- precision, y numeric/double vuelve a ser double, para el que no existe
  -- round(x, n). Fallo real el 2026-09-14.
  round((100 * sum(total_exec_time)
        / nullif(sum(sum(total_exec_time)) OVER (), 0))::numeric, 2) AS pct_acumulado
  FROM extensions.pg_stat_statements
 GROUP BY 1
 ORDER BY 4 DESC NULLS LAST;

\echo ''
\echo '    ⚠ ESE PORCENTAJE ES ACUMULADO, Y ENGANA SI NO SE MIRA DESDE CUANDO.'
\echo '    El 2026-09-14 el acumulado seguia diciendo 84 % para Realtime, pero'
\echo '    incluia los 4 meses y medio ANTERIORES al arreglo de agosto. Medido'
\echo '    por ritmo diario, Realtime habia bajado un 88 %: de 4 964 llamadas'
\echo '    al dia a 571. Mirar el acumulado sin mirar stats_reset lleva a la'
\echo '    conclusion contraria y a "optimizar" lo que ya esta optimizado.'
SELECT stats_reset,
       now() - stats_reset            AS lleva_acumulando,
       'divide entre los dias para tener el ritmo' AS como_leerlo
  FROM extensions.pg_stat_statements_info;

\echo ''
\echo '    Ritmo diario de Realtime — esto SI refleja el comportamiento actual:'
SELECT sum(calls)                                        AS llamadas_totales,
       round((sum(calls) / greatest(extract(epoch from now() - i.stats_reset)/86400, 1))::numeric, 0)
                                                         AS llamadas_por_dia,
       round((sum(total_exec_time)/1000
              / greatest(extract(epoch from now() - i.stats_reset)/86400, 1))::numeric, 1)
                                                         AS segundos_por_dia
  FROM extensions.pg_stat_statements, extensions.pg_stat_statements_info i
 WHERE query LIKE 'SELECT wal->>%'
 GROUP BY i.stats_reset;

\echo ''
\echo '════════════════════════════════════════════════════════════════'
\echo ' 2. ¿Lo que se publica coincide con lo que alguien escucha?'
\echo '════════════════════════════════════════════════════════════════'
\echo '    Publicar una tabla que nadie oye es decodificar WAL para nada.'
\echo '    Suscribirse a una que no se publica es esperar algo que no llega.'
\echo ''
\echo '    Lo que js/main.js escucha, a dia de hoy:'
\echo '      notificaciones, camiones, custodios, patios, lavados,'
\echo '      reservaciones, pedidos, ofertas'
\echo ''
\echo '    pedidos y ofertas NO estaban publicadas a proposito: renderPedidos()'
\echo '    escribia sobre pedidos al dibujar la lista, y publicarla habria hecho'
\echo '    que cada render despertara a todos los clientes. Eso cambio el 8-sep,'
\echo '    cuando la maquina de estados bajo a pg_cron. Conviene revisarlo.'

SELECT c.relname                       AS tabla,
       c.relreplident                  AS replica_identity,
       CASE c.relreplident
         WHEN 'd' THEN 'default — solo la PK en UPDATE/DELETE'
         WHEN 'f' THEN 'full — la fila entera (mas WAL)'
         WHEN 'n' THEN 'nothing — UPDATE/DELETE no se replican'
         WHEN 'i' THEN 'index'
       END                             AS que_significa,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS tamano
  FROM pg_publication_tables pt
  JOIN pg_class c      ON c.relname = pt.tablename
  JOIN pg_namespace n  ON n.oid = c.relnamespace AND n.nspname = pt.schemaname
 WHERE pt.pubname = 'supabase_realtime'
 ORDER BY pg_total_relation_size(c.oid) DESC;

\echo ''
\echo '    Y que se publica en total (deberia ser solo supabase_realtime):'
SELECT pubname, puballtables, pubinsert, pubupdate, pubdelete, pubtruncate
  FROM pg_publication;

\echo ''
\echo '════════════════════════════════════════════════════════════════'
\echo ' 3. ¿Hay WAL acumulandose sin consumir?'
\echo '════════════════════════════════════════════════════════════════'
\echo '    Un slot inactivo o muy retrasado retiene WAL en disco y obliga a'
\echo '    decodificar de mas. Es la causa tipica de que el gasto no baje'
\echo '    aunque se hayan quitado tablas de la publicacion.'

SELECT slot_name,
       slot_type,
       active,
       pg_size_pretty(
         pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retenido,
       pg_size_pretty(
         pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS sin_confirmar
  FROM pg_replication_slots
 ORDER BY 4 DESC;

\echo ''
\echo '    Las diez consultas mas caras, por si el reparto ha cambiado de dueno:'
SELECT left(regexp_replace(query, '\s+', ' ', 'g'), 70) AS consulta,
       calls,
       round(total_exec_time::numeric / 1000, 1) AS segundos
  FROM extensions.pg_stat_statements
 ORDER BY total_exec_time DESC
 LIMIT 10;

\echo ''
