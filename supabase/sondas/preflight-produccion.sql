-- Lo que haria fallar las migraciones de la ronda 2 en produccion.
-- Solo lee. Si las tres consultas salen vacias, los indices unicos entran.
--
-- Por que hace falta: los indices unicos se crean sobre datos que en pruebas
-- no son los mismos. La migracion de la placa arregla UN duplicado concreto
-- (R-8C5DEE8E contra T-001); cualquier otro par que exista en produccion
-- tumba el CREATE UNIQUE INDEX y revierte la transaccion entera.

\echo '--- Placas duplicadas (bloquean uq_camiones_placas) ---'
SELECT lower(btrim(placas)) AS placa, count(*), string_agg(id, ', ' ORDER BY id) AS unidades
  FROM public.camiones
 WHERE placas IS NOT NULL AND btrim(placas) <> ''
 GROUP BY 1 HAVING count(*) > 1
 ORDER BY 2 DESC;

\echo '--- CURP duplicados por empresa (bloquean uq_operadores_curp) ---'
SELECT propietario_id, lower(btrim(curp)) AS curp, count(*)
  FROM public.operadores
 WHERE curp IS NOT NULL AND btrim(curp) <> ''
 GROUP BY 1, 2 HAVING count(*) > 1
 ORDER BY 3 DESC;

\echo '--- Numero de trabajador duplicado por empresa ---'
SELECT propietario_id, num_trabajador, count(*)
  FROM public.operadores
 WHERE num_trabajador IS NOT NULL
 GROUP BY 1, 2 HAVING count(*) > 1
 ORDER BY 3 DESC;

\echo '--- La pareja que la migracion espera encontrar ---'
SELECT id, placas, tipo, aprobacion
  FROM public.camiones
 WHERE id IN ('T-001', 'R-8C5DEE8E');
