-- ──────────────────────────────────────────────────────────────────────────
-- 1) LICENCIA DE MATERIALES PELIGROSOS DEL OPERADOR
--    Hoy solo el camión tenía permiso de carga peligrosa; el chofer no.
-- ──────────────────────────────────────────────────────────────────────────
ALTER TABLE public.operadores
  ADD COLUMN IF NOT EXISTS doc_licencia_peligrosa text,
  ADD COLUMN IF NOT EXISTS fecha_vencimiento_licencia_peligrosa date;

COMMENT ON COLUMN public.operadores.doc_licencia_peligrosa IS
  'Licencia/certificación para manejo de materiales peligrosos (HAZMAT). Requerida para asignarse a pedidos de carga peligrosa.';

-- ──────────────────────────────────────────────────────────────────────────
-- 2) DOCUMENTOS VENCIDOS: de advertencia blanda a bloqueo duro
--    Antes el superadmin veía un aviso y podía aprobar el acuerdo "de todas
--    formas" aunque la empresa tuviera permiso SCT, seguro RC o seguro de
--    carga vencidos. Ahora es un bloqueo real al momento en que la oferta se
--    acepta (por cualquiera de los dos caminos) — es lo que hace seguro
--    quitar la aprobación manual del acuerdo final.
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.guard_oferta_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  es_cliente_pedido boolean;
BEGIN
  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado = 'aceptada' THEN
    IF EXISTS (
      SELECT 1 FROM public.perfiles p
      WHERE p.user_id = OLD.admin_id
        AND (
          (p.fecha_vencimiento_permiso_sct  IS NOT NULL AND p.fecha_vencimiento_permiso_sct  < current_date) OR
          (p.fecha_vencimiento_seguro_rc    IS NOT NULL AND p.fecha_vencimiento_seguro_rc    < current_date) OR
          (p.fecha_vencimiento_seguro_carga IS NOT NULL AND p.fecha_vencimiento_seguro_carga < current_date)
        )
    ) THEN
      RAISE EXCEPTION 'DOCUMENTOS_VENCIDOS: la empresa tiene documentos vencidos (permiso SCT, seguro RC o seguro de carga)';
    END IF;

    IF auth.uid() = OLD.admin_id THEN
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
      IF OLD.estado IS DISTINCT FROM 'enviada' THEN
        RAISE EXCEPTION 'No autorizado: solo puedes aceptar una oferta en estado enviada';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- ──────────────────────────────────────────────────────────────────────────
-- 3) CIERRE AUTOMÁTICO DEL ACUERDO
--    Antes: pendiente_acuerdo esperaba a que el superadmin le diera clic a
--    "Aprobar acuerdo". Ahora que los documentos vencidos son un bloqueo
--    duro (arriba), ya no hace falta ese paso: en cuanto la oferta queda
--    'aceptada', cliente o empresa (quien haya cerrado el trato) puede
--    disparar el cierre real ellos mismos.
--
--    Es SECURITY DEFINER porque cierra el trato con una operación que toca
--    varias tablas a la vez (rechazar las demás ofertas, marcar el pedido,
--    crear la reservación, ocupar el recurso) — y rechazar la oferta de
--    OTRA empresa está fuera del alcance normal de RLS de quien cierra.
--    guard_pedido_update sigue validando la transición pendiente_acuerdo ->
--    acordado contra la oferta aceptada real, así que esta función no es
--    una puerta trasera: solo hace lo que el guard ya permite.
-- ──────────────────────────────────────────────────────────────────────────
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
    -- Ya se cerró (llamada duplicada) o está en un estado inesperado: no es
    -- un error del usuario, solo no hay nada que hacer.
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
    propietario_id, fecha_ini, fecha_fin, descripcion, estado, precio_acordado, plazo_pago
  ) VALUES (
    v_pedido.id, v_oferta.camion_id, v_recurso_tipo, v_pedido.cliente_nombre, v_pedido.cliente_email, v_pedido.cliente_id,
    v_oferta.admin_id, v_pedido.fecha_ini, COALESCE(v_pedido.fecha_fin, v_pedido.fecha_ini), v_pedido.descripcion,
    'Activa', v_oferta.precio_oferta, v_pedido.plazo_pago
  ) RETURNING id INTO v_reserva_id;

  IF v_oferta.camion_id IS NOT NULL AND v_pedido.fecha_ini <= current_date THEN
    v_tabla_recurso := CASE v_recurso_tipo
      WHEN 'custodio' THEN 'custodios' WHEN 'patio' THEN 'patios' WHEN 'lavado' THEN 'lavados' ELSE 'camiones' END;
    EXECUTE format('UPDATE public.%I SET estado = %L WHERE id = %L', v_tabla_recurso, 'ocupado', v_oferta.camion_id);
  END IF;

  INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido) VALUES
    (v_pedido.cliente_id, 'acuerdo_aprobado', '¡Acuerdo cerrado!',
     'Tu acuerdo de ' || COALESCE(v_pedido.tipo_camion, 'servicio') || ' quedó confirmado. Ya tienes una reservación activa.', false),
    (v_oferta.admin_id, 'acuerdo_aprobado', '¡Acuerdo cerrado!',
     'El acuerdo con ' || COALESCE(v_pedido.cliente_nombre, 'el cliente') || ' para ' || COALESCE(v_pedido.tipo_camion, 'servicio')
     || ' quedó confirmado. Revisa tus reservaciones.', false);

  RETURN v_reserva_id;
END;
$$;

REVOKE ALL ON FUNCTION public.cerrar_acuerdo(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cerrar_acuerdo(uuid) TO authenticated;

-- ──────────────────────────────────────────────────────────────────────────
-- 4) guard_pedido_update: permitir que cliente/empresa cierren pendiente_acuerdo
--    -> acordado ellos mismos, siempre que la oferta marcada como pendiente
--    ya esté 'aceptada' y les pertenezca (mismo criterio que ya usa cerrar_acuerdo).
--    'rechazado' se mantiene exclusivo del superadmin.
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.guard_pedido_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  es_admin boolean;
BEGIN
  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  IF OLD.cliente_id = auth.uid() THEN
    IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado = 'rechazado' THEN
      RAISE EXCEPTION 'No autorizado: esa transicion de estado requiere aprobacion del superadmin';
    END IF;
    IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado = 'acordado' THEN
      IF OLD.estado <> 'pendiente_acuerdo' OR NOT EXISTS (
        SELECT 1 FROM public.ofertas o WHERE o.id = OLD.oferta_pendiente_id AND o.estado = 'aceptada'
      ) THEN
        RAISE EXCEPTION 'No autorizado: esa transicion de estado requiere aprobacion del superadmin';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  SELECT (rol = 'admin') INTO es_admin FROM public.perfiles WHERE user_id = auth.uid();

  IF es_admin THEN
    IF OLD.estado IN ('abierto', 'en_negociacion') THEN
      IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado IN ('acordado', 'rechazado', 'cancelado') THEN
        RAISE EXCEPTION 'No autorizado: esa transicion de estado no la puede hacer un admin';
      END IF;
      RETURN NEW;
    END IF;

    IF OLD.estado = 'acordado' AND NEW.estado = 'abierto' THEN
      IF EXISTS (
        SELECT 1 FROM public.ofertas o
        WHERE o.pedido_id = OLD.id AND o.admin_id = auth.uid() AND o.estado = 'aceptada'
      ) THEN
        RETURN NEW;
      END IF;
    END IF;

    IF OLD.estado = 'pendiente_acuerdo' AND NEW.estado = 'acordado' THEN
      IF EXISTS (
        SELECT 1 FROM public.ofertas o
        WHERE o.id = OLD.oferta_pendiente_id AND o.admin_id = auth.uid() AND o.estado = 'aceptada'
      ) THEN
        RETURN NEW;
      END IF;
    END IF;

    RAISE EXCEPTION 'No autorizado: este pedido ya no esta en fase de negociacion';
  END IF;

  RAISE EXCEPTION 'No autorizado';
END;
$function$;
