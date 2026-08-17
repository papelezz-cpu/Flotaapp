-- Permite a la empresa cambiar la unidad asignada a una reserva 'Activa'
-- (p. ej. si la unidad original se descompuso), exigiendo un motivo.
--
-- De paso, restaura protecciones de guard_reservacion_update que un pull
-- anterior (feature de CancelacionSolicitada) pisó sin querer al hacer
-- CREATE OR REPLACE FUNCTION con un cuerpo mas viejo: 'Completada' habia
-- vuelto a ser alcanzable directo por la empresa (bypass de la aprobacion
-- del superadmin), y la empresa podia tocar evidencias_cliente/completado_en
-- sin restriccion. Este migration reune ambos flujos (finalizacion +
-- cancelacion) en un solo cuerpo, y agrega el de cambio de unidad.

ALTER TABLE public.reservaciones
  ADD COLUMN IF NOT EXISTS motivo_cambio_unidad text;

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

  -- El propietario del recurso controla tracking, pago, evidencias, estado, etc.
  IF OLD.propietario_id = auth.uid() THEN
    -- Resolver una solicitud de cancelacion es decision del superadmin.
    IF OLD.estado = 'CancelacionSolicitada' AND NEW.estado IS DISTINCT FROM OLD.estado THEN
      RAISE EXCEPTION 'No autorizado: la solicitud de cancelacion la resuelve el superadmin';
    END IF;

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

    -- Cambiar la unidad asignada: solo mientras esta Activa, y con motivo.
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

  -- El cliente de la reservacion: campos operativos quedan bloqueados.
  IF OLD.cliente_user_id = auth.uid() THEN
    IF NEW.tracking_estado IS DISTINCT FROM OLD.tracking_estado
       OR NEW.pagado          IS DISTINCT FROM OLD.pagado
       OR NEW.evidencias       IS DISTINCT FROM OLD.evidencias
       OR NEW.precio_acordado  IS DISTINCT FROM OLD.precio_acordado
       OR NEW.unidad           IS DISTINCT FROM OLD.unidad
       OR NEW.motivo_cambio_unidad IS DISTINCT FROM OLD.motivo_cambio_unidad
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
