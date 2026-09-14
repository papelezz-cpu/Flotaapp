-- ============================================================================
-- Cambiar el rol de un usuario nunca funcionó, y el error se tragaba
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- trg_guard_perfil_self_update se dispara en TODA actualizacion de perfiles,
-- no solo cuando alguien edita su propia fila. Su unica salida es:
--
--     IF public.is_superadmin() THEN RETURN NEW; END IF;
--
-- e is_superadmin() es `... WHERE user_id = auth.uid()`.
--
-- La Edge Function gestionar-usuario escribe con la CLAVE DE SERVICIO, donde
-- auth.uid() es NULL. Luego is_superadmin() devuelve false y el guard trata al
-- superadmin que edita a otro como si fuera un usuario intentando ascenderse:
--
--     RAISE EXCEPTION 'No autorizado: no puedes cambiar tu rol'
--
-- Comprobado a mano en pruebas el 2026-09-14: editar el rol de un usuario
-- cualquiera desde la pantalla Usuarios devuelve ese mensaje. La funcionalidad
-- no ha funcionado nunca.
--
-- ── Por que no se habia visto ─────────────────────────────────────────────
--
-- Porque gestionar-usuario no comprobaba el resultado del UPDATE y devolvia
-- ok:true pasara lo que pasara. El superadmin veia "Usuario actualizado" y el
-- rol seguia igual. Lo destapo el arreglo A4 de la tercera auditoria, que puso
-- la comprobacion — no lo causo: lo hizo audible.
--
-- ── Por que una RPC y no abrir el guard ───────────────────────────────────
--
-- La salida corta seria `IF auth.role() = 'service_role' THEN RETURN NEW`. Una
-- linea, y abre el guard entero a cualquier cosa que tenga esa clave.
--
-- Se descarto. El guard es la pieza que decide que transiciones son legales, y
-- abrirlo por completo para resolver un caso concreto es pagar de mas. En su
-- lugar se sigue el patron que este proyecto YA usa dos veces —portgo.sync en
-- sincronizar_estados_pedidos(), portgo.cierre_acuerdo en cerrar_acuerdo()—:
-- una marca local a la transaccion que solo enciende una funcion concreta.
--
-- Asi el permiso queda acotado a cambiar el rol, y nada mas. set_config vive en
-- pg_catalog, fuera del esquema que PostgREST expone, asi que nadie puede
-- encender la marca por su cuenta.
--
-- ── Quien puede llamarla ──────────────────────────────────────────────────
--
-- Solo service_role. NO authenticated. La autorizacion de quien puede gestionar
-- usuarios ya vive en gestionar-usuario, que verifica el JWT del llamante
-- contra perfiles.rol = 'superadmin' antes de hacer nada; repetirla aqui contra
-- auth.uid() seria imposible, porque es justo lo que no existe con la clave de
-- servicio. Lo que si se comprueba aqui es lo que no depende del llamante: que
-- el rol sea valido y que no se quede la plataforma sin superadmin.
--
-- ── Reversion ─────────────────────────────────────────────────────────────
--
--   drop function if exists public.cambiar_rol(uuid, text);
--   -- y volver a aplicar el cuerpo del guard del volcado.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. El guard reconoce la marca
-- ─────────────────────────────────────────────────────────────────────────
-- Cuerpo identico al vigente salvo el primer bloque. Todo lo demas —el rol, el
-- estado de aprobacion, los campos de verificacion— sigue vigilado igual para
-- cualquier otra via.

CREATE OR REPLACE FUNCTION public.guard_perfil_self_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  -- Cambio de rol hecho por cambiar_rol(), que ya comprobo lo que habia que
  -- comprobar. La marca es local a la transaccion y solo la enciende esa
  -- funcion: set_config vive en pg_catalog y PostgREST no lo expone.
  IF current_setting('portgo.cambio_rol', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  IF NEW.rol IS DISTINCT FROM OLD.rol THEN
    RAISE EXCEPTION 'No autorizado: no puedes cambiar tu rol';
  END IF;

  IF NEW.aprobacion_cuenta IS DISTINCT FROM OLD.aprobacion_cuenta THEN
    IF NOT (OLD.aprobacion_cuenta = 'rechazada' AND NEW.aprobacion_cuenta = 'pendiente') THEN
      RAISE EXCEPTION 'No autorizado: no puedes cambiar el estado de aprobacion de tu cuenta';
    END IF;
  END IF;

  IF NEW.verificado           IS DISTINCT FROM OLD.verificado
     OR NEW.docs_aprobados_en   IS DISTINCT FROM OLD.docs_aprobados_en
     OR NEW.docs_aprobados_por  IS DISTINCT FROM OLD.docs_aprobados_por
     OR NEW.metodo_verificacion IS DISTINCT FROM OLD.metodo_verificacion THEN
    RAISE EXCEPTION 'No autorizado: campos de verificacion solo modificables por superadmin';
  END IF;

  RETURN NEW;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. La funcion que cambia el rol, y solo el rol
-- ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cambiar_rol(p_user_id uuid, p_rol text)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_rol_actual text;
BEGIN
  IF p_rol NOT IN ('cliente', 'admin', 'superadmin') THEN
    RAISE EXCEPTION 'Rol no valido: %. Debe ser cliente, admin o superadmin.', p_rol;
  END IF;

  SELECT rol INTO v_rol_actual FROM public.perfiles WHERE user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese usuario no tiene perfil. No se puede cambiar su rol.';
  END IF;

  IF v_rol_actual = p_rol THEN
    RETURN;   -- nada que hacer, y sin encender la marca
  END IF;

  -- Sin superadmin no se aprueban cuentas, ni recursos, ni solicitudes, y no
  -- hay vuelta desde la aplicacion. gestionar-usuario ya lo comprueba, pero
  -- esta es la comprobacion que manda: la de la base.
  IF v_rol_actual = 'superadmin' AND p_rol <> 'superadmin' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.perfiles
       WHERE rol = 'superadmin' AND user_id <> p_user_id
    ) THEN
      RAISE EXCEPTION 'Es el unico superadmin. Cambiarle el rol dejaria la '
                      'plataforma sin quien apruebe cuentas, recursos ni '
                      'solicitudes. Nombra otro antes.';
    END IF;
  END IF;

  PERFORM set_config('portgo.cambio_rol', 'on', true);
  UPDATE public.perfiles SET rol = p_rol WHERE user_id = p_user_id;
END;
$$;

COMMENT ON FUNCTION public.cambiar_rol(uuid, text) IS
  'Cambia el rol de un perfil saltando guard_perfil_self_update por una marca '
  'local a la transaccion. Solo service_role: la autorizacion vive en la Edge '
  'Function gestionar-usuario, que verifica el JWT del llamante.';

-- Solo la clave de servicio. Un usuario con sesion no puede llamarla ni
-- sabiendo que existe.
REVOKE ALL    ON FUNCTION public.cambiar_rol(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cambiar_rol(uuid, text) TO service_role;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────

do $$
begin
  if has_function_privilege('authenticated', 'public.cambiar_rol(uuid, text)', 'EXECUTE') then
    raise exception 'cambiar_rol no debe ser ejecutable por authenticated.';
  end if;
  if not has_function_privilege('service_role', 'public.cambiar_rol(uuid, text)', 'EXECUTE') then
    raise exception 'cambiar_rol tiene que ser ejecutable por service_role.';
  end if;
  raise notice 'cambiar_rol: solo service_role, como debe ser.';
end $$;
