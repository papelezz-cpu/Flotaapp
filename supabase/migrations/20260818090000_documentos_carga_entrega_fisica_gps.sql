-- ──────────────────────────────────────────────────────────────────────────
-- 1) Documentos de carga sueltos (Carta Porte, documentación de maniobra)
--    Sin checklist: el cliente los sube en cuanto hay match, igual que ya
--    sube 'evidencias_cliente' al cerrar el servicio.
-- ──────────────────────────────────────────────────────────────────────────
ALTER TABLE public.reservaciones
  ADD COLUMN IF NOT EXISTS documentos_carga text[];

-- El bucket 'unidades' solo deja leer bajo tu propio uid (o a superadmin) —
-- así que sin esto la empresa nunca podría ver la Carta Porte que sube el
-- cliente, aunque sea justo quien la necesita para el viaje. Se agrega una
-- política adicional (las de SELECT se combinan con OR, no reemplaza nada)
-- solo para rutas de documentos-carga, verificando que quien lee sea el
-- propietario de la reservación a la que pertenece esa carpeta.
DROP POLICY IF EXISTS docs_carga_propietario_lee ON storage.objects;
CREATE POLICY docs_carga_propietario_lee ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'unidades'
    AND (storage.foldername(name))[2] = 'documentos-carga'
    AND EXISTS (
      SELECT 1 FROM public.reservaciones r
      WHERE r.id::text = (storage.foldername(name))[3]
        AND r.propietario_id = auth.uid()
    )
  );

-- ──────────────────────────────────────────────────────────────────────────
-- 2) Entrega física de documentos del expediente (en vez de subir archivo)
--    Reemplaza TODO el checklist de esa etapa: el cliente declara que los
--    entrega en persona, con dirección y contacto.
-- ──────────────────────────────────────────────────────────────────────────
ALTER TABLE public.expedientes
  ADD COLUMN IF NOT EXISTS entrega_fisica boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS entrega_fisica_direccion text,
  ADD COLUMN IF NOT EXISTS entrega_fisica_contacto text;

-- ──────────────────────────────────────────────────────────────────────────
-- 3) Link de GPS temporal
--    La empresa lo guarda en cualquier momento; el cliente solo lo ve una
--    vez que el tracking avanzó del primer paso (mismo momento en que ya
--    se exige tener chofer asignado).
-- ──────────────────────────────────────────────────────────────────────────
ALTER TABLE public.reservaciones
  ADD COLUMN IF NOT EXISTS gps_link text;

-- guard_reservacion_update: documentos_carga es del cliente (la empresa no
-- lo toca, igual que evidencias_cliente); gps_link es de la empresa (el
-- cliente no lo toca, igual que unidad/operador).
CREATE OR REPLACE FUNCTION public.guard_reservacion_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  IF OLD.propietario_id = auth.uid() THEN
    IF OLD.estado = 'CancelacionSolicitada' AND NEW.estado IS DISTINCT FROM OLD.estado THEN
      RAISE EXCEPTION 'No autorizado: la solicitud de cancelacion la resuelve el superadmin';
    END IF;

    IF NEW.evidencias_cliente IS DISTINCT FROM OLD.evidencias_cliente THEN
      RAISE EXCEPTION 'No autorizado: esa evidencia la sube el cliente';
    END IF;
    IF NEW.documentos_carga IS DISTINCT FROM OLD.documentos_carga THEN
      RAISE EXCEPTION 'No autorizado: esos documentos los sube el cliente';
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

    IF NEW.unidad IS DISTINCT FROM OLD.unidad THEN
      IF OLD.estado <> 'Activa' THEN
        RAISE EXCEPTION 'No autorizado: solo puedes cambiar la unidad de una reserva activa';
      END IF;
      IF NEW.motivo_cambio_unidad IS NULL OR btrim(NEW.motivo_cambio_unidad) = '' THEN
        RAISE EXCEPTION 'Se requiere indicar el motivo del cambio de unidad';
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  IF OLD.cliente_user_id = auth.uid() THEN
    IF NEW.tracking_estado IS DISTINCT FROM OLD.tracking_estado
       OR NEW.pagado          IS DISTINCT FROM OLD.pagado
       OR NEW.evidencias       IS DISTINCT FROM OLD.evidencias
       OR NEW.precio_acordado  IS DISTINCT FROM OLD.precio_acordado
       OR NEW.unidad           IS DISTINCT FROM OLD.unidad
       OR NEW.motivo_cambio_unidad IS DISTINCT FROM OLD.motivo_cambio_unidad
       OR NEW.operador_id      IS DISTINCT FROM OLD.operador_id
       OR NEW.operador_nombre  IS DISTINCT FROM OLD.operador_nombre
       OR NEW.gps_link         IS DISTINCT FROM OLD.gps_link
       OR NEW.propietario_id   IS DISTINCT FROM OLD.propietario_id
       OR NEW.recurso_tipo     IS DISTINCT FROM OLD.recurso_tipo
       OR NEW.cancelacion_resuelta_en     IS DISTINCT FROM OLD.cancelacion_resuelta_en
       OR NEW.cancelacion_resuelta_por    IS DISTINCT FROM OLD.cancelacion_resuelta_por
       OR NEW.cancelacion_nota_resolucion IS DISTINCT FROM OLD.cancelacion_nota_resolucion THEN
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
      ELSIF NEW.estado = 'CancelacionSolicitada' THEN
        IF OLD.estado <> 'Activa' THEN
          RAISE EXCEPTION 'No autorizado: el cliente solo puede solicitar la cancelacion de una reserva activa';
        END IF;
        IF NEW.cancelacion_motivo IS NULL OR btrim(NEW.cancelacion_motivo) = '' THEN
          RAISE EXCEPTION 'Se requiere indicar el motivo de la cancelacion';
        END IF;
      ELSE
        RAISE EXCEPTION 'No autorizado: el cliente solo puede solicitar el cierre o la cancelacion del servicio';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$function$;
