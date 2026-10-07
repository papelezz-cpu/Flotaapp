-- ============================================================================
-- MEDICION de produccion — SOLO LECTURA
-- ============================================================================
-- Lo corre supabase/medir-produccion.sh; no se pasa a mano. Responde lo que
-- ninguna auditoria desde la 2a pudo medir (docs/AUDITORIA.md §6):
--   · donde se va el tiempo de la base, y cuanto es de Realtime (A2-C1);
--   · que indices se usan de verdad (decide H-17 y A2-M11);
--   · como se usa cada tabla, conexiones y slots de replicacion.
--
-- No escribe nada: el guion abre la sesion con default_transaction_read_only
-- y aborta antes de llegar aqui si no quedo puesta.
--
-- Sin datos personales: pg_stat_statements guarda las consultas normalizadas
-- ($1, $2...), y de realtime.subscription solo se cuentan filas por tabla.
-- Aun asi la salida va a supabase/espejo/, que esta fuera de Git.
--
-- ASCII puro a proposito: en Windows psql entrega los acentos con otra
-- codificacion y el servidor los rechaza.
-- ============================================================================

\pset pager off
\pset null '-'
set search_path = public, extensions;
set statement_timeout = '30s';

\echo ''
\echo '=== 0. CONTEXTO: desde cuando cuentan las estadisticas ==='
select now()                                   as medido_en,
       current_setting('server_version')       as version,
       pg_postmaster_start_time()              as servidor_arrancado,
       (select stats_reset from pg_stat_statements_info) as statements_desde,
       (select stats_reset from pg_stat_database where datname = current_database()) as tablas_desde,
       pg_size_pretty(pg_database_size(current_database())) as tamano_base;

\echo ''
\echo '=== 1. TIEMPO TOTAL POR ROL (quien consume la base) ==='
with t as (select sum(total_exec_time) tot from pg_stat_statements)
select r.rolname,
       round((100 * sum(s.total_exec_time) / nullif(t.tot, 0))::numeric, 1) as pct_tiempo,
       sum(s.calls)                                             as llamadas,
       round(sum(s.total_exec_time))                            as ms_total
  from pg_stat_statements s join pg_roles r on r.oid = s.userid, t
 group by r.rolname, t.tot
 order by 2 desc nulls last;

\echo ''
\echo '=== 2. REALTIME Y WAL: cuanto del tiempo total (A2-C1 midio 84 %) ==='
with t as (select sum(total_exec_time) tot from pg_stat_statements)
select round((100 * sum(total_exec_time) / nullif(max(t.tot), 0))::numeric, 1) as pct_tiempo,
       sum(calls)                                                as llamadas,
       round(sum(total_exec_time))                               as ms_total
  from pg_stat_statements, t
 where query ilike any (array['%realtime.%', '%pg_logical_slot%', '%wal2json%', '%list_changes%'])
   and query not ilike '%entity::regclass%';   -- la propia seccion 11 de esta sonda

\echo ''
\echo '=== 3. LAS 25 CONSULTAS QUE MAS TIEMPO CONSUMEN ==='
with t as (select sum(total_exec_time) tot from pg_stat_statements)
select round((100 * s.total_exec_time / nullif(t.tot, 0))::numeric, 1) as pct,
       s.calls, round(s.total_exec_time) as ms_total,
       round(s.mean_exec_time::numeric, 2) as ms_medio, s.rows, r.rolname,
       left(regexp_replace(s.query, '\s+', ' ', 'g'), 160) as consulta
  from pg_stat_statements s join pg_roles r on r.oid = s.userid, t
 order by s.total_exec_time desc
 limit 25;

\echo ''
\echo '=== 4. LAS 15 MAS LENTAS EN PROMEDIO (al menos 10 llamadas) ==='
select round(mean_exec_time::numeric, 2) as ms_medio, round(max_exec_time::numeric, 1) as ms_max,
       calls, left(regexp_replace(query, '\s+', ' ', 'g'), 160) as consulta
  from pg_stat_statements
 where calls >= 10
 order by mean_exec_time desc
 limit 15;

\echo ''
\echo '=== 5. USO DE CADA INDICE de public (idx_scan = 0: nunca usado desde el reinicio) ==='
select s.relname as tabla, s.indexrelname as indice, s.idx_scan,
       pg_size_pretty(pg_relation_size(s.indexrelid)) as tamano,
       case when i.indisprimary then 'PK' when i.indisunique then 'UNIQUE' else '' end as tipo
  from pg_stat_user_indexes s join pg_index i on i.indexrelid = s.indexrelid
 where s.schemaname = 'public'
 order by s.idx_scan, s.relname, s.indexrelname;

\echo ''
\echo '=== 6. USO DE CADA TABLA de public ==='
select relname as tabla, n_live_tup as filas, n_dead_tup as muertas,
       seq_scan, seq_tup_read, idx_scan,
       n_tup_ins as ins, n_tup_upd as upd, n_tup_del as del,
       last_autovacuum::date as autovacuum, last_autoanalyze::date as autoanalyze
  from pg_stat_user_tables
 where schemaname = 'public'
 order by seq_tup_read desc;

\echo ''
\echo '=== 7. ACIERTO DE CACHE (por debajo de 99 % en una base asi de pequena seria raro) ==='
select round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) as pct_cache_base
  from pg_stat_database where datname = current_database();

\echo ''
\echo '=== 8. CONEXIONES AHORA (foto de este instante) ==='
select usename, application_name, state, count(*) as conexiones
  from pg_stat_activity
 where datname = current_database()
 group by 1, 2, 3
 order by 4 desc;
select current_setting('max_connections') as max_connections;

\echo ''
\echo '=== 9. SLOTS DE REPLICACION (Realtime lee el WAL por aqui) ==='
select slot_name, plugin, slot_type, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as wal_retenido
  from pg_replication_slots;

\echo ''
\echo '=== 10. TABLAS PUBLICADAS en supabase_realtime ==='
select schemaname, tablename from pg_publication_tables
 where pubname = 'supabase_realtime' order by 1, 2;

\echo ''
\echo '=== 11. SUSCRIPCIONES REALTIME VIVAS por tabla (solo el recuento) ==='
select entity::regclass as tabla, count(*) as suscripciones
  from realtime.subscription group by 1 order by 2 desc;

\echo ''
\echo '=== 12. TAMANO de las 15 tablas mayores (con indices y TOAST) ==='
select relname as tabla, pg_size_pretty(pg_total_relation_size(relid)) as total
  from pg_statio_user_tables
 order by pg_total_relation_size(relid) desc
 limit 15;

\echo ''
\echo '=== FIN ==='
