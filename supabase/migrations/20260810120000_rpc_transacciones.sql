-- ──────────────────────────────────────────────────────────────────────────
-- TRANSACCIONES DE NEGOCIO COMO RPC  (opción B del análisis móvil)
--
-- Hasta ahora cada flujo multi-paso lo orquestaba el navegador: cancelar una
-- reservación son 7 escrituras encadenadas desde js/reservaciones.js, sin
-- atomicidad. Si el usuario cierra la pestaña a la mitad, la unidad se queda
-- 'ocupado' y el pedido colgado en 'acordado' — ya pasó (ver la migración
-- 20260728120000, que existe justo por una de esas roturas).
--
-- Con apps nativas de iOS y Android entrando al mismo backend, esa lógica
-- tendría que existir tres veces, en tres lenguajes, y divergiría. Aquí baja a
-- Postgres una sola vez y los tres clientes llaman la misma función.
--
-- ── Cómo se comportan estas funciones ─────────────────────────────────────
--
-- SECURITY DEFINER, pero eso NO las vuelve superusuario del negocio:
-- auth.uid() se lee del JWT de la petición, no del dueño de la función, así
-- que los guard triggers (guard_pedido_update, guard_oferta_update,
-- guard_reservacion_update…) SIGUEN aplicando dentro de cada función. Son la
-- red de seguridad, no un estorbo: si una de estas funciones intentara una
-- transición que el guard prohíbe, la transacción entera se revierte.
--
-- Por eso el ORDEN de las escrituras importa y está comentado donde no es
-- obvio. Cada función además revalida quién llama, porque SECURITY DEFINER sí
-- salta las políticas RLS de SELECT/UPDATE.
--
-- ── Lo que deliberadamente NO se movió aquí ───────────────────────────────
--
--   · Los correos. Siguen siendo fire-and-forget del cliente a la Edge
--     Function enviar-notificacion. Meter SMTP dentro de una transacción de
--     base de datos ata el commit a que Gmail responda.
--   · La creación del pedido. Es un solo INSERT que RLS ya cubre; envolverlo
--     no compra atomicidad y sí obligaría a versionar aquí sus ~60 columnas.
--   · Las aprobaciones del superadmin (aprobar solicitud, cerrar acuerdo,
--     aprobar finalización). Fuera del alcance de las apps móviles.
-- ──────────────────────────────────────────────────────────────────────────


-- ══════════════════════════════════════════════════════════════════════════
-- Helpers
-- ══════════════════════════════════════════════════════════════════════════

-- Nombre visible del usuario en curso, para los textos de las notificaciones.
CREATE OR REPLACE FUNCTION public.mi_nombre()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT COALESCE(nombre, 'Un usuario') FROM public.perfiles WHERE user_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.mi_nombre() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mi_nombre() TO authenticated;

-- Notifica a todos los superadmins. Se usa en varios flujos.
CREATE OR REPLACE FUNCTION public.notificar_superadmins(
  p_tipo text, p_titulo text, p_mensaje text
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
  SELECT user_id, p_tipo, p_titulo, p_mensaje, false
    FROM public.perfiles WHERE rol = 'superadmin';
$$;

REVOKE ALL ON FUNCTION public.notificar_superadmins(text, text, text) FROM PUBLIC, anon, authenticated;

-- Secuencia de seguimiento según el tipo de recurso.
-- Réplica exacta de TRACKING_POR_TIPO en js/tracking.js — si una cambia, la
-- otra tiene que cambiar igual, o el móvil y la web mostrarán pasos distintos.
CREATE OR REPLACE FUNCTION public.tracking_pasos(p_recurso_tipo text)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_recurso_tipo
    WHEN 'custodio' THEN ARRAY['Confirmado','Asignado','En ruta','En servicio','Finalizado']
    WHEN 'patio'    THEN ARRAY['Confirmado','Listo','Recibido','En almacenaje','Liberado']
    WHEN 'lavado'   THEN ARRAY['Confirmado','Recibido','En lavado','Control','Listo']
    ELSE                 ARRAY['Confirmado','En camino','En carga','En tránsito','Entregado']
  END;
$$;

GRANT EXECUTE ON FUNCTION public.tracking_pasos(text) TO authenticated;

-- Tabla de flota que corresponde a un recurso_tipo.
CREATE OR REPLACE FUNCTION public.tabla_recurso(p_recurso_tipo text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_recurso_tipo
    WHEN 'custodio' THEN 'custodios'
    WHEN 'patio'    THEN 'patios'
    WHEN 'lavado'   THEN 'lavados'
    ELSE                 'camiones'
  END;
$$;

-- ¿El tipo de servicio del pedido lo cubre un camión?
-- Réplica de _esServicioCamion() en js/pedidos.js y de esServicioCamion() en
-- la Edge Function enviar-notificacion.
CREATE OR REPLACE FUNCTION public.es_servicio_camion(p_tipo text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(p_tipo, '') <> ''
     AND p_tipo NOT LIKE 'Custodio%'
     AND p_tipo <> 'Supervisión remota'
     AND p_tipo NOT LIKE 'Patio%'
     AND p_tipo <> 'Bodega'
     AND p_tipo NOT LIKE 'Lavado%'
     AND p_tipo <> 'Desinfección';
$$;

GRANT EXECUTE ON FUNCTION public.es_servicio_camion(text) TO authenticated;

-- Tipo de recurso que implica un tipo de servicio.
-- Réplica de la derivación de recursoTipo en cerrarAcuerdo() (js/pedidos.js).
CREATE OR REPLACE FUNCTION public.recurso_tipo_de_servicio(p_tipo text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_tipo LIKE 'Custodio%' OR p_tipo = 'Supervisión remota' THEN 'custodio'
    WHEN p_tipo LIKE 'Patio%'    OR p_tipo = 'Bodega'             THEN 'patio'
    WHEN p_tipo LIKE 'Lavado%'   OR p_tipo IN ('Desinfección', 'Lavado Contenedor') THEN 'lavado'
    ELSE 'camion'
  END;
$$;

GRANT EXECUTE ON FUNCTION public.recurso_tipo_de_servicio(text) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 1) ENVIAR OFERTA  (empresa)
--    Reemplaza _enviarOfertaCore() — js/pedidos.js:1947
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.enviar_oferta(
  p_pedido_id       uuid,
  p_camion_id       text,
  p_precio          numeric,
  p_operador_id     text DEFAULT NULL,
  p_operador_nombre text DEFAULT NULL,
  p_mensaje         text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_pedido      public.pedidos%ROWTYPE;
  v_tipo_camion text;
  v_oferta_id   uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF p_precio IS NULL OR p_precio <= 0 THEN
    RAISE EXCEPTION 'Ingresa un precio válido.';
  END IF;
  IF p_camion_id IS NULL THEN
    RAISE EXCEPTION 'Debes seleccionar el recurso que asignarás.';
  END IF;

  SELECT * INTO v_pedido FROM public.pedidos WHERE id = p_pedido_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La solicitud ya no existe.';
  END IF;
  IF v_pedido.estado NOT IN ('abierto', 'en_negociacion') THEN
    RAISE EXCEPTION 'Esta solicitud ya no admite ofertas.';
  END IF;

  -- El recurso tiene que ser tuyo y estar aprobado. RLS no aplica dentro de
  -- SECURITY DEFINER, así que esto se verifica a mano.
  IF public.recurso_tipo_de_servicio(v_pedido.tipo_camion) = 'camion' THEN
    SELECT tipo INTO v_tipo_camion
      FROM public.camiones
     WHERE id = p_camion_id AND propietario_id = auth.uid() AND aprobacion = 'aprobada';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'La unidad no es tuya o todavía no está aprobada.';
    END IF;

    -- Mismo gate que la web: el camión ofertado debe ser del tipo pedido.
    IF public.es_servicio_camion(v_pedido.tipo_camion)
       AND v_tipo_camion IS DISTINCT FROM v_pedido.tipo_camion THEN
      RAISE EXCEPTION 'El camión seleccionado es tipo "%" pero la solicitud requiere "%".',
        v_tipo_camion, v_pedido.tipo_camion;
    END IF;

    -- El chofer es obligatorio en servicios de camión.
    IF p_operador_id IS NULL THEN
      RAISE EXCEPTION 'Debes seleccionar un chofer para este servicio.';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.operadores
       WHERE id = p_operador_id AND propietario_id = auth.uid() AND aprobacion = 'aprobada'
    ) THEN
      RAISE EXCEPTION 'El chofer no es tuyo o todavía no está aprobado.';
    END IF;
  END IF;

  INSERT INTO public.ofertas (
    pedido_id, admin_id, admin_nombre, camion_id,
    operador_id, operador_nombre, precio_oferta, mensaje
  ) VALUES (
    p_pedido_id, auth.uid(), public.mi_nombre(), p_camion_id,
    p_operador_id, p_operador_nombre, p_precio, NULLIF(btrim(COALESCE(p_mensaje, '')), '')
  )
  RETURNING id INTO v_oferta_id;

  -- El aviso al cliente lo dispara el trigger notificar_nueva_oferta.
  IF v_pedido.estado = 'abierto' THEN
    UPDATE public.pedidos SET estado = 'en_negociacion' WHERE id = p_pedido_id;
  END IF;

  RETURN v_oferta_id;
END;
$$;

REVOKE ALL ON FUNCTION public.enviar_oferta(uuid, text, numeric, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enviar_oferta(uuid, text, numeric, text, text, text) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 2) RESPONDER OFERTA  (cliente)
--    Reemplaza responderOferta() / enviarContraoferta() / confirmarRechazarOferta()
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.responder_oferta(
  p_oferta_id     uuid,
  p_accion        text,                  -- 'aceptar' | 'contraofertar' | 'rechazar'
  p_contra_precio numeric DEFAULT NULL,
  p_nota          text    DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_oferta public.ofertas%ROWTYPE;
  v_pedido public.pedidos%ROWTYPE;
  v_ruta   text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  SELECT * INTO v_oferta FROM public.ofertas WHERE id = p_oferta_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La oferta ya no existe.';
  END IF;

  SELECT * INTO v_pedido FROM public.pedidos WHERE id = v_oferta.pedido_id;
  IF v_pedido.cliente_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'No autorizado: esta solicitud no es tuya.';
  END IF;
  IF v_oferta.estado <> 'enviada' THEN
    RAISE EXCEPTION 'Esta oferta ya fue respondida.';
  END IF;
  IF v_oferta.expira_en IS NOT NULL AND v_oferta.expira_en < now() THEN
    RAISE EXCEPTION 'Esta oferta ya venció.';
  END IF;

  v_ruta := COALESCE(v_pedido.tipo_camion, 'servicio')
         || CASE WHEN v_pedido.origen IS NOT NULL
                 THEN ' (' || v_pedido.origen
                      || COALESCE(' → ' || v_pedido.destino, '') || ')'
                 ELSE '' END;

  IF p_accion = 'aceptar' THEN
    -- El guard exige que la oferta venga de 'enviada' para que el cliente la
    -- acepte; ya está verificado arriba.
    UPDATE public.ofertas SET estado = 'aceptada' WHERE id = p_oferta_id;

    -- Queda pendiente de que el superadmin apruebe el acuerdo. Es él quien
    -- luego crea la reservación (cerrarAcuerdo), no este flujo.
    UPDATE public.pedidos
       SET estado = 'pendiente_acuerdo', oferta_pendiente_id = p_oferta_id
     WHERE id = v_pedido.id;

    INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
    VALUES (v_oferta.admin_id, 'respuesta_oferta', '✓ Tu oferta fue aceptada',
            'El cliente aceptó tu oferta de ' || v_ruta
            || '. Queda pendiente la aprobación del administrador.', false);

    PERFORM public.notificar_superadmins(
      'revision_acuerdo', '🤝 Acuerdo por aprobar',
      public.mi_nombre() || ' aceptó una oferta de ' || v_ruta
      || '. Revísalo en Pendientes de aprobación.');

  ELSIF p_accion = 'contraofertar' THEN
    IF p_contra_precio IS NULL OR p_contra_precio <= 0 THEN
      RAISE EXCEPTION 'Ingresa un precio válido para la contraoferta.';
    END IF;

    UPDATE public.ofertas
       SET estado = 'contra_oferta', contra_precio = p_contra_precio, ronda = 2
     WHERE id = p_oferta_id;

    INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
    VALUES (v_oferta.admin_id, 'respuesta_oferta', '💬 Recibiste una contraoferta',
            'El cliente respondió tu oferta de ' || v_ruta
            || ' con $' || to_char(p_contra_precio, 'FM999,999,999') || ' MXN.', false);

  ELSIF p_accion = 'rechazar' THEN
    UPDATE public.ofertas SET estado = 'rechazada' WHERE id = p_oferta_id;

    INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
    VALUES (v_oferta.admin_id, 'respuesta_oferta', 'Tu oferta fue rechazada',
            'El cliente rechazó tu oferta de ' || v_ruta
            || COALESCE('. Motivo: ' || NULLIF(btrim(p_nota), ''), '.'), false);

    -- Si ya no queda ninguna oferta viva, la solicitud vuelve a estar abierta.
    -- Es la misma regla que la web aplica de forma perezosa al listar.
    IF NOT EXISTS (
      SELECT 1 FROM public.ofertas
       WHERE pedido_id = v_pedido.id
         AND estado IN ('enviada', 'contra_oferta')
         AND (expira_en IS NULL OR expira_en >= now())
    ) THEN
      UPDATE public.pedidos SET estado = 'abierto' WHERE id = v_pedido.id;
    END IF;

  ELSE
    RAISE EXCEPTION 'Acción no reconocida: %', p_accion;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.responder_oferta(uuid, text, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.responder_oferta(uuid, text, numeric, text) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 3) RESPONDER CONTRAOFERTA  (empresa)
--    Reemplaza responderContra() — js/pedidos.js:2032
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.responder_contraoferta(
  p_oferta_id uuid,
  p_accion    text                       -- 'aceptar' | 'rechazar'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_oferta public.ofertas%ROWTYPE;
  v_pedido public.pedidos%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  SELECT * INTO v_oferta FROM public.ofertas WHERE id = p_oferta_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La oferta ya no existe.';
  END IF;
  IF v_oferta.admin_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'No autorizado: esta oferta no es tuya.';
  END IF;
  IF v_oferta.estado <> 'contra_oferta' THEN
    RAISE EXCEPTION 'Esta oferta no tiene una contraoferta pendiente.';
  END IF;

  SELECT * INTO v_pedido FROM public.pedidos WHERE id = v_oferta.pedido_id;

  IF p_accion = 'aceptar' THEN
    -- El guard permite al admin poner 'aceptada' solo viniendo de
    -- 'contra_oferta' — exactamente este caso.
    UPDATE public.ofertas
       SET estado = 'aceptada', precio_oferta = COALESCE(v_oferta.contra_precio, v_oferta.precio_oferta)
     WHERE id = p_oferta_id;

    UPDATE public.pedidos
       SET estado = 'pendiente_acuerdo', oferta_pendiente_id = p_oferta_id
     WHERE id = v_pedido.id;

    INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
    VALUES (v_pedido.cliente_id, 'respuesta_contra_oferta', '✓ Aceptaron tu contraoferta',
            public.mi_nombre() || ' aceptó tu contraoferta. Queda pendiente la aprobación del administrador.',
            false);

    PERFORM public.notificar_superadmins(
      'revision_acuerdo', '🤝 Acuerdo por aprobar',
      'Se cerró una negociación de ' || COALESCE(v_pedido.tipo_camion, 'servicio')
      || '. Revísalo en Pendientes de aprobación.');

  ELSIF p_accion = 'rechazar' THEN
    UPDATE public.ofertas SET estado = 'rechazada' WHERE id = p_oferta_id;

    INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
    VALUES (v_pedido.cliente_id, 'respuesta_contra_oferta', 'No aceptaron tu contraoferta',
            public.mi_nombre() || ' no aceptó tu contraoferta de '
            || COALESCE(v_pedido.tipo_camion, 'servicio') || '.', false);

    IF NOT EXISTS (
      SELECT 1 FROM public.ofertas
       WHERE pedido_id = v_pedido.id
         AND estado IN ('enviada', 'contra_oferta')
         AND (expira_en IS NULL OR expira_en >= now())
    ) THEN
      UPDATE public.pedidos SET estado = 'abierto' WHERE id = v_pedido.id;
    END IF;

  ELSE
    RAISE EXCEPTION 'Acción no reconocida: %', p_accion;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.responder_contraoferta(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.responder_contraoferta(uuid, text) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 4) CANCELAR RESERVACIÓN  (empresa / propietario)
--    Reemplaza cancelarReserva() — js/reservaciones.js:453
--    Es la más crítica: 7 escrituras que hoy no son atómicas.
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.cancelar_reservacion(
  p_reserva_id uuid,
  p_motivo     text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_r      public.reservaciones%ROWTYPE;
  v_tabla  text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  SELECT * INTO v_r FROM public.reservaciones WHERE id = p_reserva_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La reservación ya no existe.';
  END IF;
  IF v_r.propietario_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'No autorizado: esta reservación no es tuya.';
  END IF;
  IF v_r.estado IN ('Completada', 'Cancelada') THEN
    RAISE EXCEPTION 'Esta reservación ya está cerrada.';
  END IF;
  -- Una cancelación que el cliente ya solicitó la resuelve el superadmin.
  IF v_r.estado = 'CancelacionSolicitada' THEN
    RAISE EXCEPTION 'Hay una solicitud de cancelación en revisión del administrador.';
  END IF;

  UPDATE public.reservaciones
     SET estado = 'Cancelada',
         cancelacion_motivo = COALESCE(NULLIF(btrim(p_motivo), ''), cancelacion_motivo)
   WHERE id = p_reserva_id;

  -- Liberar el recurso.
  IF v_r.unidad IS NOT NULL THEN
    v_tabla := public.tabla_recurso(v_r.recurso_tipo);
    EXECUTE format('UPDATE public.%I SET estado = %L WHERE id = %L',
                   v_tabla, 'disponible', v_r.unidad);
  END IF;

  IF v_r.pedido_id IS NOT NULL THEN
    -- ORDEN IMPORTANTE: reabrir el pedido va ANTES de tocar las ofertas.
    -- guard_pedido_update solo deja a un admin hacer 'acordado' → 'abierto'
    -- mientras SU oferta en ese pedido siga en 'aceptada' (ver la migración
    -- 20260728120000). Si se rechazara la oferta primero, la excepción del
    -- guard dejaría de cumplirse y la reapertura fallaría.
    UPDATE public.pedidos
       SET estado = 'abierto', oferta_pendiente_id = NULL
     WHERE id = v_r.pedido_id;

    -- Quien canceló un acuerdo ya cerrado no puede volver a ofertar en esta
    -- misma solicitud.
    UPDATE public.ofertas
       SET estado = 'rechazada', permite_reoferta = false
     WHERE pedido_id = v_r.pedido_id AND estado = 'aceptada';

    -- Las demás sí podrán ofertar de nuevo en la solicitud reabierta.
    UPDATE public.ofertas
       SET estado = 'rechazada'
     WHERE pedido_id = v_r.pedido_id AND estado IN ('enviada', 'contra_oferta');
  END IF;

  IF v_r.cliente_user_id IS NOT NULL THEN
    INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
    VALUES (v_r.cliente_user_id, 'reserva_cancelada', 'Reserva cancelada',
            'Tu reserva fue cancelada por el proveedor. Tu solicitud está abierta de nuevo para recibir ofertas.',
            false);
  END IF;

  PERFORM public.notificar_superadmins(
    'reserva_cancelada_admin', 'Un acuerdo aprobado se canceló',
    public.mi_nombre() || ' canceló la reserva con ' || COALESCE(v_r.cliente, 'un cliente')
    || ' después de que el acuerdo ya había sido aprobado. La solicitud volvió a estar abierta.');
END;
$$;

REVOKE ALL ON FUNCTION public.cancelar_reservacion(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancelar_reservacion(uuid, text) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 5) SOLICITAR CANCELACIÓN  (cliente)
--    Reemplaza confirmarSolicitudCancelacion() — js/reservaciones.js:824
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.solicitar_cancelacion(
  p_reserva_id uuid,
  p_motivo     text,
  p_detalle    text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_r public.reservaciones%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF NULLIF(btrim(COALESCE(p_motivo, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Se requiere indicar el motivo de la cancelación.';
  END IF;

  SELECT * INTO v_r FROM public.reservaciones WHERE id = p_reserva_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La reservación ya no existe.';
  END IF;
  IF v_r.cliente_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'No autorizado: esta reservación no es tuya.';
  END IF;
  IF v_r.estado <> 'Activa' THEN
    RAISE EXCEPTION 'Solo puedes solicitar la cancelación de una reserva activa.';
  END IF;

  -- El punto del viaje en que se pidió se congela para el expediente: no es lo
  -- mismo cancelar antes de salir que con la carga en tránsito.
  UPDATE public.reservaciones
     SET estado                      = 'CancelacionSolicitada',
         cancelacion_solicitada_en   = now(),
         cancelacion_solicitada_por  = auth.uid(),
         cancelacion_motivo          = btrim(p_motivo),
         cancelacion_detalle         = NULLIF(btrim(COALESCE(p_detalle, '')), ''),
         cancelacion_tracking_estado = COALESCE(tracking_estado, 'Confirmado')
   WHERE id = p_reserva_id;

  IF v_r.propietario_id IS NOT NULL THEN
    INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
    VALUES (v_r.propietario_id, 'cancelacion_solicitada', '⚠ El cliente pidió cancelar',
            COALESCE(v_r.cliente, 'El cliente') || ' solicitó cancelar el servicio "'
            || COALESCE(v_r.unidad, '') || '". El administrador lo revisará.', false);
  END IF;

  PERFORM public.notificar_superadmins(
    'revision_cancelacion', '⚠ Cancelación por revisar',
    COALESCE(v_r.cliente, 'Un cliente') || ' solicitó cancelar una reserva activa. Motivo: '
    || btrim(p_motivo));
END;
$$;

REVOKE ALL ON FUNCTION public.solicitar_cancelacion(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.solicitar_cancelacion(uuid, text, text) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 6) SUBIR EVIDENCIAS / SOLICITAR CIERRE  (cliente y empresa)
--    Reemplaza subirEvidencias() — js/reservaciones.js:648
--    Los archivos se suben a Storage desde el cliente; aquí solo se registran
--    las rutas y se mueve el estado, que es la parte que debe ser atómica.
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.registrar_evidencias(
  p_reserva_id uuid,
  p_paths      text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_r           public.reservaciones%ROWTYPE;
  v_es_cliente  boolean;
  v_actor       text;
  v_existentes  text[];
  v_solicitando boolean;
  v_otro_id     uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF p_paths IS NULL OR array_length(p_paths, 1) IS NULL THEN
    RAISE EXCEPTION 'Selecciona al menos un archivo.';
  END IF;

  SELECT * INTO v_r FROM public.reservaciones WHERE id = p_reserva_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la reserva.';
  END IF;

  v_es_cliente := (v_r.cliente_user_id = auth.uid());
  IF NOT v_es_cliente AND v_r.propietario_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'No autorizado: no participas en esta reservación.';
  END IF;

  -- Cada lado tiene su columna: la empresa en `evidencias`, el cliente en
  -- `evidencias_cliente`. El guard de reservaciones ya impide cruzarlas.
  v_actor      := CASE WHEN v_es_cliente THEN 'cliente' ELSE 'empresa' END;
  v_existentes := COALESCE(
    CASE WHEN v_es_cliente THEN v_r.evidencias_cliente ELSE v_r.evidencias END,
    ARRAY[]::text[]);

  v_solicitando := (v_r.estado = 'Activa');

  IF NOT v_solicitando AND v_r.estado <> 'PorAprobar' THEN
    RAISE EXCEPTION 'Esta reserva no admite evidencias en su estado actual.';
  END IF;

  -- La empresa solo puede pedir el cierre con el seguimiento en el último paso.
  IF v_solicitando AND NOT v_es_cliente THEN
    IF COALESCE(v_r.tracking_estado, 'Confirmado')
       IS DISTINCT FROM (public.tracking_pasos(v_r.recurso_tipo))[5] THEN
      RAISE EXCEPTION 'Primero avanza el seguimiento hasta "%".',
        (public.tracking_pasos(v_r.recurso_tipo))[5];
    END IF;
  END IF;

  -- Plazo de 5 días, solo cuando el cierre ya se había solicitado.
  IF NOT v_solicitando AND v_r.completado_en IS NOT NULL
     AND v_r.completado_en < now() - interval '5 days' THEN
    RAISE EXCEPTION 'El plazo de 5 días para subir evidencias ha vencido.';
  END IF;

  IF array_length(v_existentes, 1) IS NOT NULL
     AND array_length(v_existentes, 1) + array_length(p_paths, 1) > 5 THEN
    RAISE EXCEPTION 'Solo puedes tener 5 evidencias. Ya tienes %.', array_length(v_existentes, 1);
  END IF;

  IF v_es_cliente THEN
    UPDATE public.reservaciones
       SET evidencias_cliente = v_existentes || p_paths,
           estado             = CASE WHEN v_solicitando THEN 'PorAprobar' ELSE estado END,
           finalizacion_solicitada_por = CASE WHEN v_solicitando THEN v_actor
                                              ELSE finalizacion_solicitada_por END,
           completado_en      = CASE WHEN v_solicitando AND completado_en IS NULL
                                     THEN now() ELSE completado_en END
     WHERE id = p_reserva_id;
  ELSE
    UPDATE public.reservaciones
       SET evidencias = v_existentes || p_paths,
           estado             = CASE WHEN v_solicitando THEN 'PorAprobar' ELSE estado END,
           finalizacion_solicitada_por = CASE WHEN v_solicitando THEN v_actor
                                              ELSE finalizacion_solicitada_por END,
           completado_en      = CASE WHEN v_solicitando AND completado_en IS NULL
                                     THEN now() ELSE completado_en END
     WHERE id = p_reserva_id;
  END IF;

  IF v_solicitando THEN
    v_otro_id := CASE WHEN v_es_cliente THEN v_r.propietario_id ELSE v_r.cliente_user_id END;
    IF v_otro_id IS NOT NULL THEN
      INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
      VALUES (v_otro_id, 'finalizacion_solicitada', '📎 Confirma la finalización del servicio',
              CASE WHEN v_es_cliente THEN 'El cliente' ELSE 'La empresa' END
              || ' marcó el servicio como completado. Sube tu propia evidencia para enviarlo a revisión del superadmin.',
              false);
    END IF;

    PERFORM public.notificar_superadmins(
      'revision_finalizacion', '🏁 Finalización de servicio por revisar',
      COALESCE(v_r.cliente, 'Un cliente')
      || ' tiene un servicio marcado como completado, pendiente de tu aprobación.');

  ELSIF array_length(v_existentes, 1) IS NULL THEN
    -- La otra parte ya había pedido el cierre y este lado sube su evidencia por
    -- primera vez: ya están ambas, el superadmin puede resolver.
    PERFORM public.notificar_superadmins(
      'revision_finalizacion', '🏁 Ya están ambas evidencias',
      COALESCE(v_r.cliente, 'Un cliente')
      || ' y la empresa ya subieron su evidencia de cierre. Puedes revisarla y aprobarla.');
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.registrar_evidencias(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_evidencias(uuid, text[]) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 7) AVANZAR SEGUIMIENTO  (empresa)
--    Reemplaza avanzarTracking() — js/tracking.js:87
--    Incluye la apertura automática del expediente de vacíos al entregar,
--    que hoy son 3 escrituras sueltas más en el cliente.
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.avanzar_tracking(p_reserva_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_r         public.reservaciones%ROWTYPE;
  v_pasos     text[];
  v_idx       int;
  v_siguiente text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  SELECT * INTO v_r FROM public.reservaciones WHERE id = p_reserva_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La reservación ya no existe.';
  END IF;
  IF v_r.propietario_id IS DISTINCT FROM auth.uid() AND NOT public.is_superadmin() THEN
    RAISE EXCEPTION 'No autorizado: esta reservación no es tuya.';
  END IF;
  IF v_r.estado <> 'Activa' THEN
    RAISE EXCEPTION 'Solo se puede avanzar el seguimiento de una reserva activa.';
  END IF;

  v_pasos := public.tracking_pasos(v_r.recurso_tipo);
  v_idx   := COALESCE(
    array_position(v_pasos, COALESCE(v_r.tracking_estado, v_pasos[1])), 1);

  IF v_idx >= array_length(v_pasos, 1) THEN
    RAISE EXCEPTION 'El seguimiento ya está en el último paso.';
  END IF;

  v_siguiente := v_pasos[v_idx + 1];

  UPDATE public.reservaciones SET tracking_estado = v_siguiente WHERE id = p_reserva_id;

  IF v_r.cliente_user_id IS NOT NULL THEN
    INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
    VALUES (v_r.cliente_user_id, 'tracking_actualizado', v_siguiente,
            'Tu servicio "' || COALESCE(v_r.unidad, '') || '" avanzó a: ' || v_siguiente || '.',
            false);
  END IF;

  -- Al entregar se abre solo el expediente de vacíos si hubo contenedor: es
  -- justo donde empiezan a correr las demoras, y nadie se acuerda de pedirlo.
  IF v_siguiente = 'Entregado' THEN
    PERFORM public.abrir_expediente(p_reserva_id, 'entrega_vacios', true);
  END IF;

  RETURN v_siguiente;
END;
$$;

REVOKE ALL ON FUNCTION public.avanzar_tracking(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.avanzar_tracking(uuid) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 8) ABRIR EXPEDIENTE DOCUMENTAL  (empresa; cliente si se adelanta)
--    Reemplaza solicitarDocumentacion() y abrirExpedienteVaciosSiAplica()
--    — js/expedientes.js:45 y :368
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.abrir_expediente(
  p_reserva_id      uuid,
  p_etapa           text,                  -- 'ingreso_puerto' | 'entrega_vacios'
  p_solo_si_aplica  boolean DEFAULT false  -- true: no falla si no procede
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_r     public.reservaciones%ROWTYPE;
  v_ped   public.pedidos%ROWTYPE;
  v_exp   uuid;
  v_label text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF p_etapa NOT IN ('ingreso_puerto', 'entrega_vacios') THEN
    RAISE EXCEPTION 'Etapa no reconocida: %', p_etapa;
  END IF;

  SELECT * INTO v_r FROM public.reservaciones WHERE id = p_reserva_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La reservación ya no existe.';
  END IF;
  IF v_r.cliente_user_id IS DISTINCT FROM auth.uid()
     AND v_r.propietario_id IS DISTINCT FROM auth.uid()
     AND NOT public.is_superadmin() THEN
    RAISE EXCEPTION 'No autorizado: no participas en esta reservación.';
  END IF;

  -- El expediente de vacíos solo tiene sentido si el viaje llevó contenedor.
  IF p_etapa = 'entrega_vacios' AND p_solo_si_aplica THEN
    IF v_r.pedido_id IS NULL THEN RETURN NULL; END IF;
    SELECT * INTO v_ped FROM public.pedidos WHERE id = v_r.pedido_id;
    IF NOT (COALESCE(v_ped.categoria_carga, '') = 'Contenerizada'
            OR COALESCE(v_ped.num_contenedores, 0) > 0) THEN
      RETURN NULL;
    END IF;
  END IF;

  -- Idempotente: la UNIQUE (reserva_id, etapa) ya lo garantiza, pero devolver
  -- el existente evita que el cliente tenga que distinguir el error.
  SELECT id INTO v_exp FROM public.expedientes
   WHERE reserva_id = p_reserva_id AND etapa = p_etapa;
  IF FOUND THEN RETURN v_exp; END IF;

  INSERT INTO public.expedientes (reserva_id, etapa, solicitado_por)
  VALUES (p_reserva_id, p_etapa, auth.uid())
  RETURNING id INTO v_exp;

  -- El checklist se COPIA del catálogo, no se referencia: si mañana editan el
  -- catálogo, este expediente debe seguir diciendo lo que se pidió.
  INSERT INTO public.expediente_documentos
    (expediente_id, nombre, descripcion, obligatorio, orden)
  SELECT v_exp, nombre, descripcion, obligatorio, orden
    FROM public.documentos_catalogo
   WHERE etapa = p_etapa AND activo = true
   ORDER BY orden;

  IF v_r.cliente_user_id IS NOT NULL AND v_r.cliente_user_id <> auth.uid() THEN
    v_label := CASE p_etapa
                 WHEN 'ingreso_puerto' THEN 'documentos de ingreso a puerto'
                 ELSE 'documentos de entrega de vacíos' END;
    INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
    VALUES (v_r.cliente_user_id, 'documentos_solicitados', '📄 Documentación solicitada',
            'El transportista necesita los ' || v_label || ' para el servicio "'
            || COALESCE(v_r.unidad, '') || '". Súbelos desde Reservaciones.', false);
  END IF;

  RETURN v_exp;
END;
$$;

REVOKE ALL ON FUNCTION public.abrir_expediente(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.abrir_expediente(uuid, text, boolean) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 9) CALIFICAR SERVICIO  (cliente)
--    Reemplaza enviarCalificacion() — js/reservaciones.js:775
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.calificar_servicio(
  p_reserva_id uuid,
  p_rating     int,
  p_comentario text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_r public.reservaciones%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'La calificación debe ser de 1 a 5 estrellas.';
  END IF;

  SELECT * INTO v_r FROM public.reservaciones WHERE id = p_reserva_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La reservación ya no existe.';
  END IF;
  IF v_r.cliente_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'No autorizado: esta reservación no es tuya.';
  END IF;
  IF v_r.estado <> 'Completada' THEN
    RAISE EXCEPTION 'Solo puedes calificar un servicio completado.';
  END IF;
  IF COALESCE(v_r.calificado, false) THEN
    RAISE EXCEPTION 'Este servicio ya fue calificado.';
  END IF;

  INSERT INTO public.calificaciones (reservacion_id, admin_id, cliente_id, rating, comentario)
  VALUES (p_reserva_id, v_r.propietario_id, auth.uid(), p_rating,
          NULLIF(btrim(COALESCE(p_comentario, '')), ''));

  UPDATE public.reservaciones SET calificado = true WHERE id = p_reserva_id;

  IF v_r.propietario_id IS NOT NULL THEN
    INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
    VALUES (v_r.propietario_id, 'nueva_calificacion', '⭐ Recibiste una calificación',
            COALESCE(v_r.cliente, 'Un cliente') || ' calificó tu servicio con '
            || p_rating || ' de 5 estrellas.', false);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.calificar_servicio(uuid, int, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.calificar_servicio(uuid, int, text) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 10) MENSAJE DE CHAT  (cliente y empresa)
--     Reemplaza enviarMensaje() — js/chat.js:153
--     Lo que gana al bajar aquí: el candado anti-desintermediación. Hoy vive
--     solo en el navegador (_contieneTelefono), así que cualquier cliente que
--     no lo implemente — una app nativa, curl — lo salta.
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.enviar_mensaje(
  p_texto         text,
  p_participantes uuid[],
  p_reserva_id    uuid DEFAULT NULL,
  p_pedido_id     uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_id    uuid;
  v_texto text := btrim(COALESCE(p_texto, ''));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF v_texto = '' THEN
    RAISE EXCEPTION 'El mensaje está vacío.';
  END IF;
  IF (p_reserva_id IS NULL) = (p_pedido_id IS NULL) THEN
    RAISE EXCEPTION 'Un mensaje pertenece a una reserva o a una solicitud, no a ambas.';
  END IF;
  IF NOT (auth.uid() = ANY (p_participantes)) THEN
    RAISE EXCEPTION 'No autorizado: no participas en esta conversación.';
  END IF;

  -- Mismo criterio que _contieneTelefono() en js/chat.js: 10 o más dígitos,
  -- aunque vengan separados por espacios, puntos, guiones o paréntesis.
  -- No bloquea precios ni fechas (menos de 10 dígitos).
  IF v_texto ~ '(\+?[0-9][ .\-()]*){10,}' THEN
    RAISE EXCEPTION 'Por seguridad no se permiten números de teléfono en el chat. Mantén el trato dentro de PortGo.';
  END IF;

  INSERT INTO public.mensajes (de_user_id, de_nombre, texto, leido, reserva_id, pedido_id, participantes)
  VALUES (auth.uid(), public.mi_nombre(), v_texto, false, p_reserva_id, p_pedido_id, p_participantes)
  RETURNING id INTO v_id;

  -- El aviso al destinatario lo dispara fn_notificar_nuevo_mensaje.
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.enviar_mensaje(text, uuid[], uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enviar_mensaje(text, uuid[], uuid, uuid) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 11) RECOMENDAR UNIDAD
--     Traducción de _recomendarCamion() — js/pedidos.js:835
--
--     No mueve nada: es una función pura. Está aquí igual porque es la regla
--     que convierte "qué voy a mover" en "qué camión necesito", y de ella sale
--     el `tipo_camion` que decide QUÉ EMPRESAS reciben el aviso y quién puede
--     ofertar. Tenerla escrita tres veces (JS, Kotlin, Swift) garantiza que
--     tarde o temprano un cliente vea una unidad distinta según por dónde
--     entró, y que la solicitud le llegue a las empresas equivocadas.
--
--     Devuelve la unidad y el PORQUÉ. El porqué no es adorno: si el cliente no
--     entiende de dónde salió, no confía y la cambia a lo loco.
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.recomendar_unidad(
  p_categoria        text,
  p_peso_ton         numeric DEFAULT NULL,
  p_num_tarimas      int     DEFAULT NULL,
  p_num_contenedores int     DEFAULT NULL,
  p_alto_m           numeric DEFAULT NULL
)
RETURNS TABLE (tipo text, razon text)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  -- Peso máximo y tarimas que aguanta cada unidad, de menor a mayor.
  unidades   text[]    := ARRAY['Camioneta 1.5 ton caja seca','Camioneta 3.5 ton caja seca','Rabón','Torton caja seca','Full'];
  topes_ton  numeric[] := ARRAY[1.5, 3.5, 8, 20, 30];
  topes_tar  int[]     := ARRAY[4, 8, 12, 20, 32];

  ALTO_LOWBOY constant numeric := 4.25;  -- gálibo de puentes, en metros
  PESO_LOWBOY constant numeric := 30;    -- toneladas

  cat   text    := COALESCE(p_categoria, 'General');
  peso  numeric := COALESCE(p_peso_ton, 0);
  tar   int     := COALESCE(p_num_tarimas, 0);
  ncont int     := COALESCE(p_num_contenedores, 0);
  alto  numeric := COALESCE(p_alto_m, 0);

  i          int;
  idx_final  int := NULL;
  idx_peso   int := NULL;
BEGIN
  IF cat = 'Hazmat' THEN
    RETURN QUERY SELECT 'HAZMAT'::text,
      'Los materiales peligrosos solo pueden moverse en unidades con permiso HAZMAT.'::text;
    RETURN;
  END IF;

  IF cat = 'Sobredimensionada' THEN
    IF alto > ALTO_LOWBOY THEN
      RETURN QUERY SELECT 'Lowboy'::text,
        format('Con %s m de alto necesitas una cama baja para no exceder el gálibo de puentes.', alto);
      RETURN;
    ELSIF peso > PESO_LOWBOY THEN
      RETURN QUERY SELECT 'Lowboy'::text,
        format('Con %s ton necesitas una cama baja por distribución de peso.', peso);
      RETURN;
    END IF;
    RETURN QUERY SELECT 'Plataforma de 3 ejes (sobrepeso)'::text,
      'Carga que excede medidas estándar pero entra en plataforma reforzada.'::text;
    RETURN;
  END IF;

  IF cat = 'Contenerizada' OR ncont > 0 THEN
    IF ncont >= 2 THEN
      RETURN QUERY SELECT 'Full porta contenedor 40/20'::text,
        'Dos contenedores requieren doble remolque (full).'::text;
    ELSE
      RETURN QUERY SELECT 'Sencillo porta contenedor 40/20'::text,
        'Un contenedor va en un sencillo porta contenedor.'::text;
    END IF;
    RETURN;
  END IF;

  IF peso <= 0 THEN
    RETURN QUERY SELECT NULL::text,
      'Captura el peso de la carga para calcular la unidad.'::text;
    RETURN;
  END IF;

  -- La unidad tiene que aguantar el peso Y el espacio. Manda la restricción
  -- más exigente: eso es cubicaje. Un camión se llena por peso o por volumen,
  -- lo que ocurra primero.
  FOR i IN 1 .. array_length(unidades, 1) LOOP
    IF idx_peso IS NULL AND peso <= topes_ton[i] THEN
      idx_peso := i;
    END IF;
    IF idx_final IS NULL AND peso <= topes_ton[i] AND (tar = 0 OR tar <= topes_tar[i]) THEN
      idx_final := i;
    END IF;
  END LOOP;

  idx_final := COALESCE(idx_final, array_length(unidades, 1));
  idx_peso  := COALESCE(idx_peso,  array_length(unidades, 1));

  IF tar > 0 AND idx_peso <> idx_final THEN
    RETURN QUERY SELECT unidades[idx_final],
      format(
        'Tus %s tarimas son las que mandan: por las %s ton bastaría un %s, pero no cabrían. '
        'Un camión se llena por peso o por espacio, lo que ocurra primero.',
        tar, peso, lower(unidades[idx_peso]));
  ELSIF tar > 0 THEN
    RETURN QUERY SELECT unidades[idx_final],
      format('Para %s ton en %s tarima%s de carga %s, esta unidad es la que corresponde.',
             peso, tar, CASE WHEN tar = 1 THEN '' ELSE 's' END, lower(cat));
  ELSE
    RETURN QUERY SELECT unidades[idx_final],
      format('Para %s ton de carga %s, esta unidad es la que corresponde. '
             'Si va en tarimas, captura cuántas: puede cambiar la recomendación.',
             peso, lower(cat));
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.recomendar_unidad(text, numeric, int, int, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.recomendar_unidad(text, numeric, int, int, numeric) TO authenticated;
