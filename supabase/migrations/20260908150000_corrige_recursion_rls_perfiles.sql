-- ============================================================================
-- URGENTE: recursion infinita en las politicas de perfiles
-- ============================================================================
--
-- SINTOMA. Cualquier UPDATE sobre public.perfiles hecho por alguien que no sea
-- superadmin falla con:
--
--     ERROR 42P17: infinite recursion detected in policy for relation "perfiles"
--
-- Medido en portgo-pruebas el 2026-09-08:
--
--     INSERT simple de un perfil propio ........ 201 OK
--     SELECT de la fila propia ................. OK
--     UPSERT (INSERT ... ON CONFLICT DO UPDATE) . 500  42P17
--     UPDATE de la fila propia .................. 500  42P17
--
-- QUE ROMPE, en produccion, desde el 2026-09-08:
--
--   · El registro de cuentas. js/auth.js:792 hace un upsert sobre perfiles y
--     NO comprueba el error, asi que el alta continua: se crea la fila de
--     solicitudes_cuenta y el usuario de auth, pero el PERFIL NO EXISTE. La
--     solicitud aparece en el panel del superadmin y el globo de "por aprobar"
--     no la cuenta, porque ese globo cuenta perfiles.aprobacion_cuenta.
--     Peor: al aprobarla, js/aprobaciones.js:904 hace un UPDATE sobre una fila
--     que no existe — cero filas, error nulo — y la cuenta queda aprobada sin
--     perfil.
--   · Editar el perfil propio (js/admin.js:266).
--   · Cambiar las preferencias de correo (js/preferencias.js:99).
--
-- ── La causa, y es mia ────────────────────────────────────────────────────
--
-- La introdujo 20260831210000_perfiles_ficha_publica.sql al anadir:
--
--     CREATE POLICY perfiles_superadmin_select ON public.perfiles
--       FOR SELECT USING ( (SELECT public.is_superadmin()) );
--
-- El ciclo es este:
--
--   1. Un UPDATE sobre perfiles evalua la politica "Superadmin update any
--      profile", que ya existia y lleva dentro una subconsulta A PERFILES:
--        EXISTS (SELECT 1 FROM public.perfiles p WHERE p.user_id = auth.uid()
--                AND p.rol = 'superadmin')
--   2. Esa subconsulta esta sujeta a las politicas de SELECT de perfiles.
--   3. Una de ellas es ahora perfiles_superadmin_select, que llama a
--      is_superadmin().
--   4. is_superadmin() vuelve a leer perfiles.
--   5. Vuelta al punto 2.
--
-- Antes del 31 de agosto no recursaba porque las dos politicas de SELECT que
-- habia —"Leer nombre de empresa" y "Leer propio perfil"— no leian perfiles.
-- La subconsulta del paso 1 terminaba ahi. Al sustituirlas por una que si lo
-- hace, se cerro el ciclo.
--
-- Lo que esto ensena, y conviene dejarlo escrito: is_superadmin() es SECURITY
-- DEFINER pero NO se salta el RLS de perfiles. Funciona en las otras ~70
-- politicas porque esas estan sobre OTRAS tablas; su lectura interna de
-- perfiles se resolvia contra politicas triviales. En cuanto una politica DE
-- PERFILES la llama, recursa.
--
-- ── El arreglo ────────────────────────────────────────────────────────────
--
-- Se rompe el ciclo en el eslabon 4: que is_superadmin() deje de leer la tabla
-- sujeta a politicas y lea una VISTA que las evita.
--
-- Una vista con security_invoker en su valor por defecto corre con permisos de
-- su dueno y no aplica el RLS de la tabla base. Eso no es teoria: es
-- exactamente el mecanismo por el que empresas_publico funciona hoy — un
-- cliente ve por ella las 3 empresas mientras un SELECT directo a perfiles le
-- devuelve solo su propia fila. Comprobado en pruebas el 2026-09-01.
--
-- Se prefiere esto a las alternativas:
--
--   · Retirar perfiles_superadmin_select romperia el panel de aprobaciones, la
--     verificacion, la gestion de usuarios y las vigencias.
--   · Devolver la politica ancha "Leer nombre de empresa" reabriria H-01, que
--     es la fuga que se acaba de cerrar.
--   · Tocar las ~70 politicas que usan is_superadmin() seria mucho mas riesgo
--     por el mismo resultado.
--
-- Este cambio no toca ninguna politica: solo cambia por donde lee la funcion.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. Una vista interna de perfiles que no pasa por las politicas
-- ─────────────────────────────────────────────────────────────────────────
-- Solo las dos columnas que is_superadmin() necesita. Cuanto menos exponga,
-- menos dano hace si alguna vez se concede por error.
--
-- security_invoker se queda en su valor por defecto (false) A PROPOSITO: con
-- true aplicaria el RLS del que consulta y volveriamos al ciclo.

CREATE OR REPLACE VIEW public.perfiles_roles_interno AS
  SELECT user_id, rol FROM public.perfiles;

COMMENT ON VIEW public.perfiles_roles_interno IS
  'Uso interno de is_superadmin(). Evita el RLS de perfiles para romper la recursion de politicas. NO exponer a anon ni a authenticated.';

-- Nadie la lee desde fuera. Sin esto PostgREST la publicaria como endpoint y
-- cualquier autenticado veria el rol de todo el mundo.
REVOKE ALL ON public.perfiles_roles_interno FROM PUBLIC, anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. is_superadmin() lee de la vista
-- ─────────────────────────────────────────────────────────────────────────
-- Mismo nombre, misma firma, misma semantica: cierto si el que llama es
-- superadmin. Lo unico que cambia es de donde lee, y con eso deja de disparar
-- las politicas de perfiles.
--
-- Las ~70 politicas que la usan no se tocan y siguen comportandose igual.

CREATE OR REPLACE FUNCTION public.is_superadmin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.perfiles_roles_interno
     WHERE user_id = auth.uid() AND rol = 'superadmin'
  );
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. La politica de UPDATE deja de consultar perfiles a mano
-- ─────────────────────────────────────────────────────────────────────────
-- "Superadmin update any profile" lleva la subconsulta cruda que es el
-- eslabon 1 del ciclo. Aunque con el arreglo de arriba ya no recursaria, se
-- cambia por la funcion: es el mismo criterio escrito una sola vez, y evita
-- que el ciclo pueda reaparecer si alguien vuelve a tocar las politicas de
-- SELECT.
--
-- Envuelta en SELECT para que se evalue una vez por consulta y no una por
-- fila, como el resto desde 20260827200000.

DROP POLICY IF EXISTS "Superadmin update any profile" ON public.perfiles;
CREATE POLICY "Superadmin update any profile" ON public.perfiles
  FOR UPDATE TO authenticated
  USING ( (SELECT public.is_superadmin()) );


-- ─────────────────────────────────────────────────────────────────────────
-- 4. Reparar las cuentas que quedaron sin perfil
-- ─────────────────────────────────────────────────────────────────────────
-- Mientras el bug estuvo vivo, cada alta creo su usuario de auth y su fila de
-- solicitudes_cuenta, pero no el perfil. Esas cuentas no pueden entrar: la
-- app decide el rol leyendo perfiles.
--
-- Se reconstruyen desde solicitudes_cuenta, que si tiene el rol y el nombre.
-- El estado de aprobacion se deriva del estado de la solicitud, para no
-- aprobar de mas ni dejar en revision algo que ya se aprobo:
--
--     solicitud aprobada  -> aprobacion_cuenta NULL      (cuenta activa)
--     solicitud pendiente -> aprobacion_cuenta pendiente (sale en el globo)
--     solicitud rechazada -> aprobacion_cuenta rechazada
--
-- Solo toca usuarios SIN fila en perfiles: no pisa ningun perfil existente.

INSERT INTO public.perfiles (user_id, nombre, rol, aprobacion_cuenta)
SELECT sc.user_id,
       COALESCE(NULLIF(btrim(sc.nombre), ''), split_part(sc.email, '@', 1), 'Sin nombre'),
       CASE WHEN sc.rol = 'cliente' THEN 'cliente' ELSE 'admin' END,
       CASE sc.estado
         WHEN 'aprobada'  THEN NULL
         WHEN 'rechazada' THEN 'rechazada'
         ELSE 'pendiente'
       END
  FROM public.solicitudes_cuenta sc
 WHERE NOT EXISTS (SELECT 1 FROM public.perfiles p WHERE p.user_id = sc.user_id)
ON CONFLICT (user_id) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────────────
-- 5. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_huerfanos int;
BEGIN
  SELECT count(*) INTO v_huerfanos
    FROM public.solicitudes_cuenta sc
   WHERE NOT EXISTS (SELECT 1 FROM public.perfiles p WHERE p.user_id = sc.user_id);

  IF v_huerfanos <> 0 THEN
    RAISE EXCEPTION 'quedan % solicitudes sin perfil', v_huerfanos;
  END IF;

  RAISE NOTICE 'recursion corregida; solicitudes sin perfil: 0';
END $$;
