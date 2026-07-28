-- Cierre de servicio con aprobación de superadmin (antes: la empresa marcaba
-- 'Completada' directo, sin revisión ni evidencia del cliente).
--
-- Nuevo flujo: cliente o empresa, con la reserva 'Activa', solicitan el cierre
-- (sube su propia evidencia) -> estado pasa a 'PorAprobar'. Cada lado tiene su
-- columna de evidencia (evidencias = empresa, evidencias_cliente = cliente).
-- El superadmin revisa ambas, el precio y si ya se marcó pagado, y aprueba
-- (-> 'Completada', dispara el cierre del pedido) o rechaza (-> 'Activa').

ALTER TABLE public.reservaciones
  ADD COLUMN IF NOT EXISTS evidencias_cliente text[],
  ADD COLUMN IF NOT EXISTS finalizacion_solicitada_por text,
  ADD COLUMN IF NOT EXISTS finalizacion_nota text,
  ADD COLUMN IF NOT EXISTS finalizacion_aprobada_por uuid,
  ADD COLUMN IF NOT EXISTS finalizacion_aprobada_en timestamptz;

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

  IF OLD.propietario_id = auth.uid() THEN
    -- La empresa no toca la evidencia del cliente ni la fecha ya fijada.
    IF NEW.evidencias_cliente IS DISTINCT FROM OLD.evidencias_cliente THEN
      RAISE EXCEPTION 'No autorizado: esa evidencia la sube el cliente';
    END IF;
    IF NEW.completado_en IS DISTINCT FROM OLD.completado_en AND OLD.completado_en IS NOT NULL THEN
      RAISE EXCEPTION 'No autorizado: no puedes modificar la fecha de finalizacion';
    END IF;
    IF NEW.estado IS DISTINCT FROM OLD.estado THEN
      IF NEW.estado = 'Completada' THEN
        RAISE EXCEPTION 'No autorizado: la finalizacion la aprueba el superadmin';
      END IF;
      IF NEW.estado = 'PorAprobar' AND OLD.estado NOT IN ('Activa', 'PorAprobar') THEN
        RAISE EXCEPTION 'No autorizado: solo puedes solicitar el cierre desde una reserva activa';
      END IF;
      IF OLD.estado = 'PorAprobar' AND NEW.estado NOT IN ('PorAprobar', 'Cancelada') THEN
        RAISE EXCEPTION 'No autorizado: la revision de cierre la resuelve el superadmin';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.cliente_user_id = auth.uid() THEN
    IF NEW.tracking_estado  IS DISTINCT FROM OLD.tracking_estado
       OR NEW.pagado          IS DISTINCT FROM OLD.pagado
       OR NEW.evidencias       IS DISTINCT FROM OLD.evidencias
       OR NEW.precio_acordado  IS DISTINCT FROM OLD.precio_acordado
       OR NEW.unidad           IS DISTINCT FROM OLD.unidad
       OR NEW.propietario_id   IS DISTINCT FROM OLD.propietario_id
       OR NEW.recurso_tipo     IS DISTINCT FROM OLD.recurso_tipo THEN
      RAISE EXCEPTION 'No autorizado: el cliente no puede modificar estos campos de la reservacion';
    END IF;
    IF NEW.completado_en IS DISTINCT FROM OLD.completado_en AND OLD.completado_en IS NOT NULL THEN
      RAISE EXCEPTION 'No autorizado: no puedes modificar la fecha de finalizacion';
    END IF;
    IF NEW.estado IS DISTINCT FROM OLD.estado THEN
      IF NEW.estado = 'PorAprobar' THEN
        IF OLD.estado NOT IN ('Activa', 'PorAprobar') THEN
          RAISE EXCEPTION 'No autorizado: solo puedes solicitar el cierre desde una reserva activa';
        END IF;
      ELSIF NEW.estado <> 'Cancelada' THEN
        RAISE EXCEPTION 'No autorizado: el cliente solo puede cancelar o solicitar el cierre del servicio';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;
