-- El trigger guard_pedido_update() (20260724090000) restringe a un admin a
-- solo tocar un pedido mientras esta en fase de oferta abierta ('abierto' o
-- 'en_negociacion'). Eso bloquea sin querer un flujo legitimo: cuando el
-- admin cancela una reservacion YA activa (acuerdo ya aprobado por
-- superadmin), cancelarReserva() en reservaciones.js necesita reabrir el
-- pedido (acordado -> abierto) para que vuelva a recibir ofertas. La
-- actualizacion fallaba en silencio, asi que el pedido se quedaba en
-- 'acordado' para siempre: el cliente lo veia como acordado y ninguna
-- empresa (ni la que cancelo ni otras) lo volvia a ver en "Solicitudes
-- disponibles".
--
-- Se agrega una excepcion puntual: un admin puede reabrir (acordado ->
-- abierto) SOLO si su propia oferta en ese pedido sigue en estado
-- 'aceptada' -- es decir, solo el admin cuyo acuerdo se esta cancelando,
-- nunca un tercero.

CREATE OR REPLACE FUNCTION public.guard_pedido_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  es_admin boolean;
BEGIN
  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  -- Cliente dueno del pedido: puede tocarlo, pero 'acordado'/'rechazado' son
  -- transiciones exclusivas de superadmin.
  IF OLD.cliente_id = auth.uid() THEN
    IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado IN ('acordado', 'rechazado') THEN
      RAISE EXCEPTION 'No autorizado: esa transicion de estado requiere aprobacion del superadmin';
    END IF;
    RETURN NEW;
  END IF;

  SELECT (rol = 'admin') INTO es_admin FROM public.perfiles WHERE user_id = auth.uid();

  IF es_admin THEN
    -- Fase de oferta abierta: puede tocar el pedido, salvo transiciones
    -- exclusivas de superadmin.
    IF OLD.estado IN ('abierto', 'en_negociacion') THEN
      IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado IN ('acordado', 'rechazado', 'cancelado') THEN
        RAISE EXCEPTION 'No autorizado: esa transicion de estado no la puede hacer un admin';
      END IF;
      RETURN NEW;
    END IF;

    -- Excepcion puntual: reabrir un pedido ya acordado porque el admin cuya
    -- oferta fue aceptada cancelo la reservacion (ver cancelarReserva() en
    -- js/reservaciones.js).
    IF OLD.estado = 'acordado' AND NEW.estado = 'abierto' THEN
      IF EXISTS (
        SELECT 1 FROM public.ofertas o
        WHERE o.pedido_id = OLD.id AND o.admin_id = auth.uid() AND o.estado = 'aceptada'
      ) THEN
        RETURN NEW;
      END IF;
    END IF;

    RAISE EXCEPTION 'No autorizado: este pedido ya no esta en fase de negociacion';
  END IF;

  RAISE EXCEPTION 'No autorizado';
END;
$$;
