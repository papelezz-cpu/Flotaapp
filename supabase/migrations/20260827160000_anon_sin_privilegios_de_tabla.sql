-- ============================================================================
-- anon deja de tener privilegios sobre las tablas de public
-- ============================================================================
--
-- ── POR QUE ───────────────────────────────────────────────────────────────
--
-- Supabase concede de fabrica los cuatro privilegios a anon sobre cada tabla
-- nueva de public. Medido el 2026-08-27 en produccion: anon tenia SELECT,
-- INSERT, UPDATE y DELETE sobre las 24 tablas.
--
-- Hoy RLS lo contiene. Pero RLS es la UNICA puerta, y esa puerta ya fallo:
-- of_select estuvo como USING (true) sin clausula TO, entregando 34 ofertas
-- con nombre de empresa y precio a cualquiera con la clave anon, que viaja en
-- js/config.js. Si anon no hubiera tenido SELECT sobre la tabla, ese error
-- habria sido inofensivo.
--
-- El GRANT es la puerta gruesa y RLS la fina. Con una sola, un error de
-- politica es una brecha; con dos, es un error sin consecuencias. Y el error
-- se va a repetir: cada tabla nueva nace con los cuatro permisos y cada
-- politica se escribe a mano.
--
-- ── POR QUE NO ROMPE NADA ─────────────────────────────────────────────────
--
-- Ningun flujo anonimo toca una tabla:
--   · index.html (la landing) no hace ni una llamada a Supabase.
--   · main.js no consulta nada hasta que checkExistingSession() resuelve.
--   · El registro corre CON sesion. Tiene que hacerlo: sc_insert exige
--     auth.uid() = user_id, asi que como anonimo ya fallaba hoy. signUp va
--     contra GoTrue, que no depende de permisos de tabla.
--   · El arranque del cliente movil va por arranque_app(), SECURITY DEFINER:
--     lee app_config y catalogos como dueño, sin necesitar permisos de anon.
--
-- Se conserva un unico permiso: SELECT sobre app_config, que es deliberadamente
-- publica (version minima, aviso global y flags que el movil consulta antes
-- del login).
--
-- ── EFECTO SECUNDARIO BUENO ───────────────────────────────────────────────
-- Hoy un anonimo recibe 401 con el texto "permission denied for function
-- is_superadmin", que revela nombres internos del esquema. Pasa a ser un
-- permiso denegado sobre la tabla, sin detalle.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. Quitar los cuatro privilegios sobre todas las tablas
-- ─────────────────────────────────────────────────────────────────────────
-- No se tocan authenticated ni service_role. No se tocan las secuencias:
-- revocarlas podria romper un INSERT que dependa de su valor por omision.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. La unica excepcion
-- ─────────────────────────────────────────────────────────────────────────
GRANT SELECT ON public.app_config TO anon;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Que las tablas FUTURAS no vuelvan a nacer abiertas
-- ─────────────────────────────────────────────────────────────────────────
-- Sin esto, el REVOKE de arriba dura hasta la siguiente migracion que cree
-- una tabla. Las migraciones corren como `postgres`, asi que cambiar su
-- valor por omision cubre ese caso.
--
-- LIMITACION: no cubre las tablas creadas desde el panel de Supabase, que se
-- crean como supabase_admin o dashboard_user y siguen su propio ALTER DEFAULT
-- PRIVILEGES, que el rol postgres no puede modificar. Si alguien crea una
-- tabla por el panel, hay que revocarle anon a mano.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon;


-- ─────────────────────────────────────────────────────────────────────────
-- 4. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  con_permiso integer;
  detalle     text;
BEGIN
  SELECT count(*), string_agg(c.relname, ', ' ORDER BY c.relname)
    INTO con_permiso, detalle
    FROM pg_class c
   WHERE c.relnamespace = 'public'::regnamespace
     AND c.relkind = 'r'
     AND c.relname <> 'app_config'
     AND (has_table_privilege('anon', c.oid, 'SELECT')
       OR has_table_privilege('anon', c.oid, 'INSERT')
       OR has_table_privilege('anon', c.oid, 'UPDATE')
       OR has_table_privilege('anon', c.oid, 'DELETE'));

  IF con_permiso > 0 THEN
    RAISE EXCEPTION 'anon conserva privilegios en % tabla(s): %', con_permiso, detalle;
  END IF;

  IF NOT has_table_privilege('anon', 'public.app_config', 'SELECT') THEN
    RAISE EXCEPTION 'app_config quedo sin SELECT para anon: el arranque del movil se rompe';
  END IF;

  RAISE NOTICE 'Verificado: anon solo conserva SELECT sobre app_config.';
END $$;
