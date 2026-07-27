-- Cierra dos huecos de RLS en pedidos/ofertas, mapeados contra cada flujo legitimo
-- del codigo (ver analisis de seguridad 2026-07-24):
--
-- 1) pedidos: cualquier admin podia tocar CUALQUIER pedido (no solo los que estan en
--    fase de oferta abierta), y tanto el cliente como el admin podian, en teoria,
--    poner estado en 'acordado'/'rechazado' directo por REST -- transiciones que en
--    el codigo SIEMPRE son exclusivas de superadmin (aprobarSolicitud, cerrarAcuerdo).
--
-- 2) ofertas: no habia WITH CHECK que restringiera cuando una oferta puede pasar a
--    'aceptada'. Un admin podia poner su PROPIA oferta en 'aceptada' sin que el
--    cliente la hubiera aceptado, y el lazy-fix de pedidos.js (pedido en_negociacion
--    con una oferta aceptada -> pendiente_acuerdo) la habria tomado como legitima.

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
    -- Un admin solo puede tocar el pedido mientras esta en fase de oferta abierta.
    IF OLD.estado NOT IN ('abierto', 'en_negociacion') THEN
      RAISE EXCEPTION 'No autorizado: este pedido ya no esta en fase de negociacion';
    END IF;
    IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado IN ('acordado', 'rechazado', 'cancelado') THEN
      RAISE EXCEPTION 'No autorizado: esa transicion de estado no la puede hacer un admin';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'No autorizado';
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_pedido_update ON public.pedidos;
CREATE TRIGGER trg_guard_pedido_update
  BEFORE UPDATE ON public.pedidos
  FOR EACH ROW EXECUTE FUNCTION public.guard_pedido_update();

CREATE OR REPLACE FUNCTION public.guard_oferta_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  es_cliente_pedido boolean;
BEGIN
  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado = 'aceptada' THEN
    IF auth.uid() = OLD.admin_id THEN
      -- El admin solo puede "aceptar" (cerrar el trato) cuando esta aceptando
      -- la contraoferta que el cliente le envio.
      IF OLD.estado IS DISTINCT FROM 'contra_oferta' THEN
        RAISE EXCEPTION 'No autorizado: solo puedes aceptar tu propia oferta al responder una contraoferta del cliente';
      END IF;
    ELSE
      SELECT EXISTS(
        SELECT 1 FROM public.pedidos p WHERE p.id = OLD.pedido_id AND p.cliente_id = auth.uid()
      ) INTO es_cliente_pedido;
      IF NOT es_cliente_pedido THEN
        RAISE EXCEPTION 'No autorizado';
      END IF;
      -- El cliente solo puede aceptar una oferta original (primera ronda).
      IF OLD.estado IS DISTINCT FROM 'enviada' THEN
        RAISE EXCEPTION 'No autorizado: solo puedes aceptar una oferta en estado enviada';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_oferta_update ON public.ofertas;
CREATE TRIGGER trg_guard_oferta_update
  BEFORE UPDATE ON public.ofertas
  FOR EACH ROW EXECUTE FUNCTION public.guard_oferta_update();
