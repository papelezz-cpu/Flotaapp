-- ============================================================================
-- PREFLIGHT de la auditoria — SOLO LECTURA
-- ============================================================================
-- Se pasa ANTES de aplicar las migraciones de la auditoria a una base:
--
--   psql "$CONN" -f supabase/preflight-auditoria.sql
--
-- No escribe nada. Responde las tres preguntas que deciden si las
-- restricciones se pueden aplicar sin romper nada, mas contexto de volumen.
--
-- En portgo-pruebas (2026-08-26) las tres salieron limpias. Eso NO se hereda:
-- produccion es mas vieja y tiene historia real.
--
-- Todo el SQL va en ASCII puro a proposito: en Windows psql entrega los
-- acentos con otra codificacion y el servidor los rechaza.
-- ============================================================================

\echo ''
\echo '=========================================================='
\echo ' PUERTA 1 - CHECK reservaciones_partes_presentes'
\echo '=========================================================='
\echo 'Un CHECK NOT VALID no revisa el historico, pero SI valida'
\echo 'cada UPDATE. Si aqui sale algo distinto de cero, marcar como'
\echo 'pagada o avanzar el tracking de esas filas FALLARIA.'
\echo ''
SELECT count(*) FILTER (WHERE cliente_user_id IS NULL) AS sin_cliente,
       count(*) FILTER (WHERE propietario_id  IS NULL) AS sin_propietario,
       count(*)                                        AS total
  FROM reservaciones;

\echo ''
\echo 'Si hay filas, aqui salen para poder mirarlas una a una:'
SELECT id, estado, unidad, fecha_ini, cliente_email
  FROM reservaciones
 WHERE cliente_user_id IS NULL OR propietario_id IS NULL
 ORDER BY created_at DESC
 LIMIT 20;

\echo ''
\echo '=========================================================='
\echo ' PUERTA 2 - indice unico en calificaciones'
\echo '=========================================================='
\echo 'Si hay duplicados, el CREATE UNIQUE INDEX falla en seco.'
\echo ''
SELECT reservacion_id, count(*) AS veces
  FROM calificaciones
 WHERE reservacion_id IS NOT NULL
 GROUP BY reservacion_id
HAVING count(*) > 1;

\echo '(sin filas arriba = se puede aplicar)'

\echo ''
\echo '=========================================================='
\echo ' PUERTA 3 - CHECK de estado y recurso_tipo'
\echo '=========================================================='
\echo 'Cualquier valor listado aqui como FUERA rompe los UPDATE de'
\echo 'esas filas en cuanto se aplique el CHECK.'
\echo ''
SELECT estado,
       count(*) AS filas,
       CASE WHEN estado IN ('Pendiente','Activa','PorAprobar',
                            'CancelacionSolicitada','Completada',
                            'Cancelada','Rechazada')
            THEN 'dentro' ELSE '>>> FUERA <<<' END AS veredicto
  FROM reservaciones GROUP BY estado ORDER BY 2 DESC;

SELECT coalesce(recurso_tipo,'(null)') AS recurso_tipo,
       count(*) AS filas,
       CASE WHEN recurso_tipo IN ('camion','custodio','patio','lavado')
            THEN 'dentro' ELSE '>>> FUERA <<<' END AS veredicto
  FROM reservaciones GROUP BY recurso_tipo ORDER BY 2 DESC;

\echo ''
\echo '=========================================================='
\echo ' CONTEXTO - volumen real (el hueco que dejo la auditoria)'
\echo '=========================================================='
SELECT relname AS tabla, n_live_tup AS filas
  FROM pg_stat_user_tables
 WHERE schemaname = 'public'
 ORDER BY n_live_tup DESC;

\echo ''
\echo '=========================================================='
\echo ' CONTEXTO - estado de partida'
\echo '=========================================================='
SELECT count(*) AS tablas_arco_presentes
  FROM pg_tables
 WHERE schemaname='public' AND tablename IN ('consentimientos','solicitudes_arco');
\echo '(0 = la migracion de ARCO nunca se aplico aqui)'

SELECT count(*) AS indices_no_pk
  FROM pg_indexes i
 WHERE schemaname='public'
   AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conname = i.indexname);

SELECT has_function_privilege('anon', 'public.notificar_superadmins(text,text,text)', 'EXECUTE')
       AS anon_puede_notificar_superadmins;
\echo '(t = el hueco de seguridad tambien esta aqui)'

\echo ''
\echo '=========================================================='
\echo ' INFORMATIVO - solapes (para el EXCLUDE de la Fase 5)'
\echo '=========================================================='
\echo 'No bloquea nada de lo que se aplica ahora.'
\echo ''
SELECT count(*) AS pares_solapados
  FROM reservaciones a
  JOIN reservaciones b
    ON a.unidad = b.unidad AND a.id < b.id
   AND a.fecha_ini <= b.fecha_fin AND b.fecha_ini <= a.fecha_fin
 WHERE a.estado IN ('Pendiente','Activa')
   AND b.estado IN ('Pendiente','Activa');

\echo ''
\echo '== fin del preflight - no se escribio nada =='
