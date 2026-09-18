-- Ninguna VISTA de public debe aceptar escrituras: ni de anon, ni de
-- authenticated, ni de service_role.
-- Solo lee. Si las dos consultas salen vacias, el invariante se cumple.
--
-- ── Por que existe ────────────────────────────────────────────────────────
--
-- Nace de H-01 de la cuarta auditoria (2026-09-14). empresas_publico tenia
-- concedidos INSERT, UPDATE y DELETE a authenticated, y como es una vista
-- simple sobre una sola tabla, PostgreSQL la considera AUTO-ACTUALIZABLE: esas
-- escrituras llegaban a perfiles. Ademas corre con security_invoker en su valor
-- por omision (false) A PROPOSITO, para poder leer fichas ajenas sin chocar con
-- el RLS de perfiles. Juntando las dos cosas, cualquier cuenta con sesion podia
-- escribir y borrar filas de perfiles saltandose el RLS.
--
-- Comprobado explotable en un clon local antes de arreglarlo: un UPDATE como
-- authenticated cambio fecha_vencimiento_permiso_sct de una empresa ajena — la
-- columna que lee guard_oferta_update para decidir quien puede cerrar un trato.
--
-- ── Por que no se puede prevenir, y hay que detectar ──────────────────────
--
-- Porque las vistas NACEN asi. El esquema lleva puesto, para dos roles
-- distintos:
--
--     ALTER DEFAULT PRIVILEGES ... IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
--
-- y en PostgreSQL "TABLES" incluye las vistas. Luego toda vista creada en
-- public nace con ALL concedido a authenticated, y un `grant select` posterior
-- no retira nada: vuelve a conceder algo que ya estaba dentro de ALL. Fue
-- exactamente lo que le paso a 20260831210000.
--
-- Cerrar esos privilegios por omision no es opcion, por dos motivos:
--
--   · Los de supabase_admin NO SE PUEDEN cambiar sin ser miembro de ese rol
--     (ERROR 42501, comprobado el 2026-09-11 — es A5, ver exposicion-anon.sql).
--   · Los de postgres si se podrian, pero alcanzarian tambien a las TABLAS
--     futuras, que en este proyecto SI necesitan esos permisos: ahi RLS es la
--     frontera, no el GRANT. Comprobado: 20260728160000 y 20260729160000 crean
--     tablas y no conceden nada explicitamente.
--
-- Asi que, igual que con A5, se detecta en vez de prevenir.
--
-- ── Por que no basta verificar-paridad.sh ─────────────────────────────────
--
-- Porque compara las dos bases entre si. Si las dos tienen la misma vista
-- escribible, la paridad sale "identica" y todo parece correcto. De hecho eso
-- es justo lo que pasaba: el 14/09 el sello decia `permisos_tabla: identica`
-- con el agujero abierto en las dos. Esta sonda no compara: afirma.
--
-- ── Cuando correrla ───────────────────────────────────────────────────────
--
-- Contra el proyecto que se quiera auditar, pruebas o produccion:
--   psql "<cadena>" -f supabase/sondas/escritura-en-vistas.sql
--
-- Y SIEMPRE despues de crear una vista nueva. El plan de la auditoria propone
-- cuatro (camiones_publico, custodios_publico, patios_publico,
-- lavados_publico): cada una nacera con este defecto, y esta sonda es lo que lo
-- va a cantar.
--
-- El arreglo, cuando la consulta 1 devuelva algo:
--   revoke insert, update, delete, maintain on public.<vista> from authenticated;
-- o volver a ejecutar el bloque 2 de 20260914130000, que es idempotente y hace
-- justo eso preguntandole al catalogo.

\echo ''
\echo '=== 1. Vistas de public que ACEPTAN ESCRITURAS — debe salir vacia ==='
\echo '    Una vista no tiene RLS detras. Si ademas es auto-actualizable, cada'
\echo '    privilegio de escritura aqui es una via directa a la tabla base que'
\echo '    NO pasa por ninguna politica.'
SELECT c.relname AS vista,
       CASE c.relkind WHEN 'v' THEN 'vista' ELSE 'vista materializada' END AS tipo,
       g.rol,
       CASE WHEN has_table_privilege(g.rol, c.oid, 'INSERT')   THEN 'INSERT '   ELSE '' END ||
       CASE WHEN has_table_privilege(g.rol, c.oid, 'UPDATE')   THEN 'UPDATE '   ELSE '' END ||
       CASE WHEN has_table_privilege(g.rol, c.oid, 'DELETE')   THEN 'DELETE '   ELSE '' END ||
       CASE WHEN has_table_privilege(g.rol, c.oid, 'MAINTAIN') THEN 'MAINTAIN ' ELSE '' END AS concedido,
       -- pg_relation_is_updatable devuelve una mascara: 4=UPDATE, 8=INSERT,
       -- 16=DELETE. Comprobado a mano, no de memoria: una vista simple sobre
       -- una tabla da 28 (las tres), y una con GROUP BY da 0.
       -- Esto separa el permiso peligroso del inofensivo: conceder UPDATE
       -- sobre una vista agregada no hace nada, porque no hay donde escribir.
       CASE WHEN pg_relation_is_updatable(c.oid, true) = 0
            THEN 'no — la vista no es escribible, el permiso no hace nada'
            ELSE 'SI, llega a la tabla base: ' ||
                 CASE WHEN (pg_relation_is_updatable(c.oid, true) &  8) =  8 THEN 'INSERT ' ELSE '' END ||
                 CASE WHEN (pg_relation_is_updatable(c.oid, true) &  4) =  4 THEN 'UPDATE ' ELSE '' END ||
                 CASE WHEN (pg_relation_is_updatable(c.oid, true) & 16) = 16 THEN 'DELETE ' ELSE '' END
       END AS efecto_real
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  -- service_role entra desde el 2026-09-18. No estaba, y por eso nadie vio
  -- que empresas_publico llevaba escribible por la clave de servicio desde
  -- que se creo, en los dos proyectos: el barrido de H-01 solo miro los dos
  -- primeros roles. No concede privilegio nuevo -esa clave ya se salta el
  -- RLS y tiene ALL sobre las tablas base- pero una vista declarada de solo
  -- lectura tiene que serlo para todos, o la declaracion no significa nada.
  CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) AS g(rol)
 WHERE n.nspname = 'public'
   AND c.relkind IN ('v', 'm')
   AND (has_table_privilege(g.rol, c.oid, 'INSERT')
     OR has_table_privilege(g.rol, c.oid, 'UPDATE')
     OR has_table_privilege(g.rol, c.oid, 'DELETE')
     OR has_table_privilege(g.rol, c.oid, 'MAINTAIN'))
 ORDER BY 1, 3;

\echo ''
\echo '=== 2. Vistas sin security_invoker que SI se leen con sesion ==='
\echo '    No es un fallo: es como funciona empresas_publico a proposito, para'
\echo '    poder ensenar fichas ajenas sin chocar con el RLS de perfiles.'
\echo '    Es INFORMATIVO, y la lista debe ser corta y conocida: cada fila es'
\echo '    una vista que entrega datos SIN que ninguna politica los filtre, asi'
\echo '    que sus columnas son la unica frontera. Si aparece una que nadie'
\echo '    recuerda haber creado, mirar que columnas expone.'
SELECT c.relname AS vista,
       CASE WHEN has_table_privilege('authenticated', c.oid, 'SELECT') THEN 'authenticated' ELSE '' END ||
       CASE WHEN has_table_privilege('anon', c.oid, 'SELECT') THEN ' anon' ELSE '' END AS lo_lee,
       (SELECT count(*) FROM pg_attribute a
         WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) AS columnas
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relkind IN ('v', 'm')
   AND NOT COALESCE((SELECT option_value::boolean
                       FROM pg_options_to_table(c.reloptions)
                      WHERE option_name = 'security_invoker'), false)
   AND (has_table_privilege('authenticated', c.oid, 'SELECT')
     OR has_table_privilege('anon', c.oid, 'SELECT'))
 ORDER BY 1;
