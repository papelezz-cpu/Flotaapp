-- Solicitud de cancelacion por parte del cliente, con revision del superadmin.
--
-- Hasta ahora el cliente no tenia forma de cancelar una reservacion ya
-- acordada desde la aplicacion. Pero el trigger guard_reservacion_update SI le
-- permitia mover el estado a 'Cancelada' por REST, y esa via no ejecuta ninguna
-- limpieza: la unidad se quedaba 'ocupado' y el pedido colgado en 'acordado'.
-- Aqui se cierra ese hueco y se sustituye por un flujo revisado.
--
-- Nuevo estado: 'CancelacionSolicitada'. El cliente lo pide con un motivo; el
-- superadmin aprueba (se cancela de verdad, con su limpieza) o rechaza (vuelve
-- a 'Activa').

alter table public.reservaciones
  add column if not exists cancelacion_solicitada_en   timestamptz,
  add column if not exists cancelacion_solicitada_por  uuid references auth.users(id) on delete set null,
  add column if not exists cancelacion_motivo          text,
  add column if not exists cancelacion_detalle         text,
  -- Punto del viaje en que se pidio: no es lo mismo cancelar antes de salir
  -- que con la carga en transito. Se congela para el expediente.
  add column if not exists cancelacion_tracking_estado text,
  add column if not exists cancelacion_resuelta_en     timestamptz,
  add column if not exists cancelacion_resuelta_por    uuid references auth.users(id) on delete set null,
  add column if not exists cancelacion_nota_resolucion text;

create index if not exists idx_reservaciones_cancelacion
  on public.reservaciones (estado, cancelacion_solicitada_en)
  where estado = 'CancelacionSolicitada';

-- ── Guard actualizado ───────────────────────────────────────────────
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
    -- Resolver una solicitud de cancelacion es decision del superadmin.
    IF OLD.estado = 'CancelacionSolicitada' AND NEW.estado IS DISTINCT FROM OLD.estado THEN
      RAISE EXCEPTION 'No autorizado: la solicitud de cancelacion la resuelve el superadmin';
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
       OR NEW.propietario_id   IS DISTINCT FROM OLD.propietario_id
       OR NEW.recurso_tipo     IS DISTINCT FROM OLD.recurso_tipo
       OR NEW.completado_en    IS DISTINCT FROM OLD.completado_en
       -- La resolucion de la cancelacion no la escribe el cliente.
       OR NEW.cancelacion_resuelta_en     IS DISTINCT FROM OLD.cancelacion_resuelta_en
       OR NEW.cancelacion_resuelta_por    IS DISTINCT FROM OLD.cancelacion_resuelta_por
       OR NEW.cancelacion_nota_resolucion IS DISTINCT FROM OLD.cancelacion_nota_resolucion THEN
      RAISE EXCEPTION 'No autorizado: el cliente no puede modificar estos campos de la reservacion';
    END IF;

    -- El cliente ya NO puede cancelar de forma unilateral: solo puede SOLICITAR
    -- la cancelacion de una reserva activa. Cancelar de verdad implica liberar
    -- la unidad y cerrar el pedido, y eso lo hace el superadmin al aprobar.
    IF NEW.estado IS DISTINCT FROM OLD.estado THEN
      IF NOT (OLD.estado = 'Activa' AND NEW.estado = 'CancelacionSolicitada') THEN
        RAISE EXCEPTION 'No autorizado: el cliente solo puede solicitar la cancelacion de una reserva activa';
      END IF;
      IF NEW.cancelacion_motivo IS NULL OR btrim(NEW.cancelacion_motivo) = '' THEN
        RAISE EXCEPTION 'Se requiere indicar el motivo de la cancelacion';
      END IF;
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
