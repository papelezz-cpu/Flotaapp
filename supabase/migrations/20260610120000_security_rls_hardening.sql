-- Security hardening tras smoke test (2026-06-10)
-- Cierra 3 hallazgos de RLS encontrados ejercitando la API con sesiones reales:
--   1. CRITICO: cualquier usuario podia PATCHear su propio perfiles.rol -> superadmin
--      (y aprobacion_cuenta -> null) usando la politica "Update own profile".
--   2. El cliente podia modificar tracking_estado / pagado / evidencias de su reservacion
--      via API (el "solo lectura" estaba solo en la UI).
--   3. Los admin podian leer pedidos en cualquier estado (incluido pendiente_revision),
--      no solo los disponibles o aquellos en los que participan.

-- ──────────────────────────────────────────────────────────────────────────
-- 1) perfiles: impedir auto-escalada de rol / auto-aprobacion de cuenta
--    Un trigger BEFORE UPDATE bloquea cambios a columnas privilegiadas salvo superadmin.
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.guard_perfil_self_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- Los superadmin pueden modificar cualquier campo.
  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  -- Un usuario normal NUNCA puede cambiar su propio rol.
  IF NEW.rol IS DISTINCT FROM OLD.rol THEN
    RAISE EXCEPTION 'No autorizado: no puedes cambiar tu rol';
  END IF;

  -- aprobacion_cuenta: solo se permite la transicion rechazada -> pendiente (re-registro).
  -- Nunca auto-activarse (null) ni auto-aprobarse.
  IF NEW.aprobacion_cuenta IS DISTINCT FROM OLD.aprobacion_cuenta THEN
    IF NOT (OLD.aprobacion_cuenta = 'rechazada' AND NEW.aprobacion_cuenta = 'pendiente') THEN
      RAISE EXCEPTION 'No autorizado: no puedes cambiar el estado de aprobacion de tu cuenta';
    END IF;
  END IF;

  -- Metadatos de verificacion / aprobacion de documentos: solo superadmin.
  IF NEW.verificado        IS DISTINCT FROM OLD.verificado
     OR NEW.docs_aprobados_en  IS DISTINCT FROM OLD.docs_aprobados_en
     OR NEW.docs_aprobados_por IS DISTINCT FROM OLD.docs_aprobados_por THEN
    RAISE EXCEPTION 'No autorizado: campos de verificacion solo modificables por superadmin';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_perfil_self_update ON public.perfiles;
CREATE TRIGGER trg_guard_perfil_self_update
  BEFORE UPDATE ON public.perfiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_perfil_self_update();

-- ──────────────────────────────────────────────────────────────────────────
-- 2) reservaciones: el cliente solo puede calificar o cancelar su reservacion.
--    El propietario (empresa) y el superadmin conservan control operativo total.
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.guard_reservacion_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  -- El propietario del recurso controla tracking, pago, evidencias, estado, etc.
  IF OLD.propietario_id = auth.uid() THEN
    RETURN NEW;
  END IF;

  -- El cliente de la reservacion: campos operativos quedan bloqueados.
  IF OLD.cliente_user_id = auth.uid() THEN
    IF NEW.tracking_estado IS DISTINCT FROM OLD.tracking_estado
       OR NEW.pagado          IS DISTINCT FROM OLD.pagado
       OR NEW.evidencias       IS DISTINCT FROM OLD.evidencias
       OR NEW.precio_acordado  IS DISTINCT FROM OLD.precio_acordado
       OR NEW.unidad           IS DISTINCT FROM OLD.unidad
       OR NEW.propietario_id   IS DISTINCT FROM OLD.propietario_id
       OR NEW.recurso_tipo     IS DISTINCT FROM OLD.recurso_tipo
       OR NEW.completado_en    IS DISTINCT FROM OLD.completado_en THEN
      RAISE EXCEPTION 'No autorizado: el cliente no puede modificar estos campos de la reservacion';
    END IF;
    -- El cliente solo puede mover el estado a Cancelada (cancelar su reservacion).
    IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado <> 'Cancelada' THEN
      RAISE EXCEPTION 'No autorizado: el cliente solo puede cancelar la reservacion';
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_reservacion_update ON public.reservaciones;
CREATE TRIGGER trg_guard_reservacion_update
  BEFORE UPDATE ON public.reservaciones
  FOR EACH ROW EXECUTE FUNCTION public.guard_reservacion_update();

-- ──────────────────────────────────────────────────────────────────────────
-- 3) pedidos SELECT: el admin deja de ver TODOS los pedidos.
--    Ve los disponibles (abierto/en_negociacion), los suyos y aquellos en los
--    que ya hizo una oferta. El superadmin sigue viendo todo.
-- ──────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS ped_select ON public.pedidos;
CREATE POLICY ped_select ON public.pedidos
  FOR SELECT TO authenticated
  USING (
    public.is_superadmin()
    OR (estado = ANY (ARRAY['abierto'::text, 'en_negociacion'::text]))
    OR (cliente_id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.ofertas o
      WHERE o.pedido_id = pedidos.id AND o.admin_id = auth.uid()
    )
  );
