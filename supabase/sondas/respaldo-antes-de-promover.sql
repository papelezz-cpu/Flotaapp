-- Respaldo de las filas que las dos migraciones de datos van a cambiar.
-- Solo lee de la base; escribe tres CSV en la carpeta desde la que corras psql.
--
-- Correr ANTES de aplicar 20260908130000 y 20260910120000 a produccion.
-- Sin esto, esas dos son las unicas de la tanda que no se pueden deshacer:
-- una pisa una placa y la otra rellena campos vacios, y despues ya no se sabe
-- cuales estaban vacios.

\echo '--- Respaldando camiones con placa duplicada ---'
\copy (SELECT id, placas, tipo, aprobacion, propietario_id FROM public.camiones WHERE lower(btrim(placas)) IN (SELECT lower(btrim(placas)) FROM public.camiones WHERE placas IS NOT NULL AND btrim(placas) <> '' GROUP BY 1 HAVING count(*) > 1) OR id IN ('T-001','R-8C5DEE8E') ORDER BY placas, id) TO 'respaldo-camiones-placas.csv' WITH CSV HEADER

\echo '--- Respaldando los perfiles que la copia de ficha va a rellenar ---'
\copy (SELECT p.user_id, p.nombre, p.rol, p.razon_social, p.rfc, p.telefono, p.tipo_persona FROM public.perfiles p JOIN public.solicitudes_cuenta s ON s.user_id = p.user_id WHERE s.estado = 'aprobada' AND nullif(btrim(s.razon_social), '') IS NOT NULL AND nullif(btrim(p.razon_social), '') IS NULL ORDER BY p.nombre) TO 'respaldo-perfiles-ficha.csv' WITH CSV HEADER

\echo '--- Y lo que van a recibir, para poder comparar despues ---'
\copy (SELECT s.user_id, s.nombre, s.razon_social, s.rfc, s.telefono, s.tipo_persona FROM public.solicitudes_cuenta s JOIN public.perfiles p ON p.user_id = s.user_id WHERE s.estado = 'aprobada' AND nullif(btrim(s.razon_social), '') IS NOT NULL AND nullif(btrim(p.razon_social), '') IS NULL ORDER BY s.nombre) TO 'respaldo-solicitudes-origen.csv' WITH CSV HEADER

\echo 'Listo. Tres archivos CSV escritos. Contienen datos personales reales: no los subas al repositorio.'
