-- El chofer ya no es obligatorio al ofertar: se puede asignar después,
-- justo antes de que el viaje arranque (ver js/reservaciones.js). Hasta
-- ahora solo vivía en `ofertas`, que es un registro de la negociación, no
-- de la reserva activa — así que se agrega a `reservaciones` para poder
-- asignarlo/cambiarlo ya con el trato cerrado.
ALTER TABLE public.reservaciones
  ADD COLUMN IF NOT EXISTS operador_id text,
  ADD COLUMN IF NOT EXISTS operador_nombre text;

-- cerrar_acuerdo: copiar el chofer de la oferta (si ya lo trae) a la reservación.
CREATE OR REPLACE FUNCTION public.cerrar_acuerdo(p_oferta_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_oferta        public.ofertas%ROWTYPE;
  v_pedido        public.pedidos%ROWTYPE;
  v_recurso_tipo  text;
  v_tabla_recurso text;
  v_reserva_id    uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  SELECT * INTO v_oferta FROM public.ofertas WHERE id = p_oferta_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La oferta ya no existe.';
  END IF;
  IF v_oferta.estado <> 'aceptada' THEN
    RAISE EXCEPTION 'Esta oferta todavía no está aceptada.';
  END IF;

  SELECT * INTO v_pedido FROM public.pedidos WHERE id = v_oferta.pedido_id;
  IF v_pedido.estado <> 'pendiente_acuerdo' OR v_pedido.oferta_pendiente_id IS DISTINCT FROM p_oferta_id THEN
    SELECT id INTO v_reserva_id FROM public.reservaciones WHERE pedido_id = v_pedido.id ORDER BY created_at DESC LIMIT 1;
    RETURN v_reserva_id;
  END IF;

  IF NOT public.is_superadmin() AND auth.uid() NOT IN (v_pedido.cliente_id, v_oferta.admin_id) THEN
    RAISE EXCEPTION 'No autorizado: no eres parte de este acuerdo.';
  END IF;

  UPDATE public.ofertas SET estado = 'rechazada'
   WHERE pedido_id = v_pedido.id AND id <> p_oferta_id AND estado IN ('enviada', 'contra_oferta');

  INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
  SELECT o.admin_id, 'oferta_no_seleccionada', 'Tu oferta no fue seleccionada',
         'El cliente eligió otro proveedor para su solicitud de ' || COALESCE(v_pedido.tipo_camion, 'servicio')
         || CASE WHEN v_pedido.origen IS NOT NULL
                 THEN ' (' || v_pedido.origen || COALESCE(' → ' || v_pedido.destino, '') || ')' ELSE '' END
         || '. Gracias por participar.',
         false
  FROM public.ofertas o
  WHERE o.pedido_id = v_pedido.id AND o.id <> p_oferta_id AND o.estado = 'rechazada';

  UPDATE public.pedidos SET estado = 'acordado' WHERE id = v_pedido.id;

  v_recurso_tipo := public.recurso_tipo_de_servicio(v_pedido.tipo_camion);

  INSERT INTO public.reservaciones (
    pedido_id, unidad, recurso_tipo, cliente, cliente_email, cliente_user_id,
    propietario_id, fecha_ini, fecha_fin, descripcion, estado, precio_acordado, plazo_pago,
    operador_id, operador_nombre
  ) VALUES (
    v_pedido.id, v_oferta.camion_id, v_recurso_tipo, v_pedido.cliente_nombre, v_pedido.cliente_email, v_pedido.cliente_id,
    v_oferta.admin_id, v_pedido.fecha_ini, COALESCE(v_pedido.fecha_fin, v_pedido.fecha_ini), v_pedido.descripcion,
    'Activa', v_oferta.precio_oferta, v_pedido.plazo_pago,
    v_oferta.operador_id, v_oferta.operador_nombre
  ) RETURNING id INTO v_reserva_id;

  IF v_oferta.camion_id IS NOT NULL AND v_pedido.fecha_ini <= current_date THEN
    v_tabla_recurso := CASE v_recurso_tipo
      WHEN 'custodio' THEN 'custodios' WHEN 'patio' THEN 'patios' WHEN 'lavado' THEN 'lavados' ELSE 'camiones' END;
    EXECUTE format('UPDATE public.%I SET estado = %L WHERE id = %L', v_tabla_recurso, 'ocupado', v_oferta.camion_id);
  END IF;

  INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido) VALUES
    (v_pedido.cliente_id, 'acuerdo_aprobado', 'Acuerdo cerrado',
     'Tu acuerdo de ' || COALESCE(v_pedido.tipo_camion, 'servicio') || ' quedó confirmado. Ya tienes una reservación activa.', false),
    (v_oferta.admin_id, 'acuerdo_aprobado', 'Acuerdo cerrado',
     'El acuerdo con ' || COALESCE(v_pedido.cliente_nombre, 'el cliente') || ' para ' || COALESCE(v_pedido.tipo_camion, 'servicio')
     || ' quedó confirmado. Revisa tus reservaciones.', false);

  RETURN v_reserva_id;
END;
$$;

-- guard_reservacion_update: el propietario ya puede tocar cualquier campo no
-- explícitamente bloqueado (así quedó operador_id/operador_nombre libre para
-- él sin tocar nada), pero el cliente SÍ necesita el bloqueo explícito, igual
-- que unidad/propietario_id/recurso_tipo — si no, quedaría libre por default.
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
