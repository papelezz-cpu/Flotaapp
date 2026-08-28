-- ============================================================================
-- puede_notificar() deja de calcularlo todo para responder que sí
-- ============================================================================
-- Esta funcion decide la politica insertar_notificaciones, asi que corre en
-- CADA fila que se inserta en notificaciones — la tabla que mas crece.
--
-- La version anterior resolvia las cinco condiciones dentro de un unico SELECT
-- asignado a v_ok. Eso tiene dos costes:
--
--   · auth.uid() se invoca CINCO veces, y cada una lee un GUC y parsea JSONB.
--   · los dos EXISTS caros —el de reservaciones y el JOIN ofertas x pedidos—
--     se planifican junto al resto, en vez de quedar detras de las
--     comprobaciones baratas.
--
-- La reescritura no cambia ni una de las cinco condiciones ni su orden logico.
-- Solo las convierte en salidas tempranas y guarda auth.uid() en una variable:
--
--   1. me notifico a mi mismo        -> sin tocar disco
--   2. soy superadmin                -> is_superadmin(), que es STABLE
--   3. el destinatario es superadmin -> una lectura de perfiles
--   4. contraparte de una reservacion
--   5. contraparte de una oferta     -> la mas cara, y ahora la ultima
--
-- El caso mas frecuente con diferencia es el 3: notificar a los superadmins.
-- Antes tambien recorria reservaciones y hacia el JOIN de ofertas para nada.
--
-- Los indices que añadio la auditoria (reservaciones.propietario_id y
-- cliente_user_id, ofertas.admin_id, pedidos.cliente_id) son los que hacen que
-- los EXISTS 4 y 5 dejen de ser seq scans cuando se llega a ellos.
--
-- Se añade ademas la salida por auth.uid() nulo, que antes no existia: sin
-- sesion, las cinco condiciones daban NULL o false y se acababa devolviendo
-- false igual, pero despues de haberlas evaluado todas.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.puede_notificar(p_target uuid) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_target IS NULL THEN
    RETURN false;
  END IF;

  -- 1. A mi mismo.
  IF p_target = v_uid THEN
    RETURN true;
  END IF;

  -- 2. Soy superadmin: puedo notificar a cualquiera.
  IF public.is_superadmin() THEN
    RETURN true;
  END IF;

  -- 3. El destinatario es superadmin. Es el caso mas comun de todos.
  IF EXISTS (SELECT 1 FROM perfiles pf
              WHERE pf.user_id = p_target AND pf.rol = 'superadmin') THEN
    RETURN true;
  END IF;

  -- 4. Somos las dos partes de una misma reservacion.
  IF EXISTS (SELECT 1 FROM reservaciones r
              WHERE (r.propietario_id  = v_uid AND r.cliente_user_id = p_target)
                 OR (r.cliente_user_id = v_uid AND r.propietario_id  = p_target)) THEN
    RETURN true;
  END IF;

  -- 5. Somos las dos partes de una negociacion. La mas cara: va al final.
  IF EXISTS (SELECT 1 FROM ofertas o JOIN pedidos p ON p.id = o.pedido_id
              WHERE (o.admin_id = v_uid AND p.cliente_id = p_target)
                 OR (p.cliente_id = v_uid AND o.admin_id = p_target)) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$fn$;

-- Los privilegios se reponen explicitamente: CREATE OR REPLACE los conserva,
-- pero dejarlo escrito evita depender de eso.
REVOKE ALL    ON FUNCTION public.puede_notificar(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.puede_notificar(uuid) TO authenticated;
