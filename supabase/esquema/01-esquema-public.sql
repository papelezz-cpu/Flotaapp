--
-- PostgreSQL database dump
--

\restrict qWlui5QX5pF87wBomBlViJXnU2Q9VXko7kfvQrYh4g8tcCWGYhIXVjXbTFxbUqk

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: abrir_expediente(uuid, text, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.abrir_expediente(p_reserva_id uuid, p_etapa text, p_solo_si_aplica boolean DEFAULT false) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
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


ALTER FUNCTION public.abrir_expediente(p_reserva_id uuid, p_etapa text, p_solo_si_aplica boolean) OWNER TO postgres;

--
-- Name: arranque_app(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.arranque_app(p_plataforma text DEFAULT 'android'::text, p_version text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_min     text;
  v_url     text;
  v_cfg     jsonb;
  v_aviso   jsonb;
  v_flags   jsonb;
  v_catalogos jsonb;
BEGIN
  SELECT valor INTO v_cfg FROM public.app_config
   WHERE clave = 'version_minima_' || COALESCE(p_plataforma, 'android');

  v_min := v_cfg ->> 'version';
  v_url := v_cfg ->> 'url';

  SELECT valor INTO v_aviso FROM public.app_config WHERE clave = 'aviso_global';
  SELECT valor INTO v_flags FROM public.app_config WHERE clave = 'flags';

  -- Los catálogos activos, agrupados por clave y ya ordenados.
  SELECT jsonb_object_agg(clave, items) INTO v_catalogos
    FROM (
      SELECT clave,
             jsonb_agg(
               jsonb_build_object(
                 'valor', valor, 'etiqueta', etiqueta,
                 'ayuda', ayuda, 'meta', meta)
               ORDER BY orden, etiqueta) AS items
        FROM public.catalogos
       WHERE activo
       GROUP BY clave
    ) t;

  RETURN jsonb_build_object(
    'soportada',      public.version_al_menos(p_version, v_min),
    'version_minima', v_min,
    'url_descarga',   v_url,
    'aviso',          v_aviso,
    'flags',          COALESCE(v_flags, '{}'::jsonb),
    'catalogos',      COALESCE(v_catalogos, '{}'::jsonb)
  );
END;
$$;


ALTER FUNCTION public.arranque_app(p_plataforma text, p_version text) OWNER TO postgres;

--
-- Name: avanzar_tracking(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.avanzar_tracking(p_reserva_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
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


ALTER FUNCTION public.avanzar_tracking(p_reserva_id uuid) OWNER TO postgres;

--
-- Name: calificar_servicio(uuid, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calificar_servicio(p_reserva_id uuid, p_rating integer, p_comentario text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
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


ALTER FUNCTION public.calificar_servicio(p_reserva_id uuid, p_rating integer, p_comentario text) OWNER TO postgres;

--
-- Name: cancelar_reservacion(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.cancelar_reservacion(p_reserva_id uuid, p_motivo text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
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


ALTER FUNCTION public.cancelar_reservacion(p_reserva_id uuid, p_motivo text) OWNER TO postgres;

--
-- Name: cerrar_acuerdo(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.cerrar_acuerdo(p_oferta_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
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
    RAISE EXCEPTION 'Esta oferta todavia no esta aceptada.';
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
         'El cliente eligio otro proveedor para su solicitud de ' || COALESCE(v_pedido.tipo_camion, 'servicio')
         || CASE WHEN v_pedido.origen IS NOT NULL
                 THEN ' (' || v_pedido.origen || COALESCE(' -> ' || v_pedido.destino, '') || ')' ELSE '' END
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
     'Tu acuerdo de ' || COALESCE(v_pedido.tipo_camion, 'servicio') || ' quedo confirmado. Ya tienes una reservacion activa.', false),
    (v_oferta.admin_id, 'acuerdo_aprobado', 'Acuerdo cerrado',
     'El acuerdo con ' || COALESCE(v_pedido.cliente_nombre, 'el cliente') || ' para ' || COALESCE(v_pedido.tipo_camion, 'servicio')
     || ' quedo confirmado. Revisa tus reservaciones.', false);

  RETURN v_reserva_id;
END;
$$;


ALTER FUNCTION public.cerrar_acuerdo(p_oferta_id uuid) OWNER TO postgres;

--
-- Name: check_reservacion_disponibilidad(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_reservacion_disponibilidad() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM reservaciones
    WHERE unidad = NEW.unidad
      AND estado IN ('Pendiente', 'Activa')
      AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND tstzrange(fecha_ini::timestamptz, fecha_fin::timestamptz, '[]')
       && tstzrange(NEW.fecha_ini::timestamptz, NEW.fecha_fin::timestamptz, '[]')
  ) THEN
    RAISE EXCEPTION 'RECURSO_NO_DISPONIBLE: El recurso ya tiene una reserva activa en esas fechas';
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_reservacion_disponibilidad() OWNER TO postgres;

--
-- Name: enviar_mensaje(text, uuid[], uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.enviar_mensaje(p_texto text, p_participantes uuid[], p_reserva_id uuid DEFAULT NULL::uuid, p_pedido_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
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


ALTER FUNCTION public.enviar_mensaje(p_texto text, p_participantes uuid[], p_reserva_id uuid, p_pedido_id uuid) OWNER TO postgres;

--
-- Name: enviar_oferta(uuid, text, numeric, text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.enviar_oferta(p_pedido_id uuid, p_camion_id text, p_precio numeric, p_operador_id text DEFAULT NULL::text, p_operador_nombre text DEFAULT NULL::text, p_mensaje text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
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


ALTER FUNCTION public.enviar_oferta(p_pedido_id uuid, p_camion_id text, p_precio numeric, p_operador_id text, p_operador_nombre text, p_mensaje text) OWNER TO postgres;

--
-- Name: es_servicio_camion(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.es_servicio_camion(p_tipo text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT COALESCE(p_tipo, '') <> ''
     AND p_tipo NOT LIKE 'Custodio%'
     AND p_tipo <> 'Supervisión remota'
     AND p_tipo NOT LIKE 'Patio%'
     AND p_tipo <> 'Bodega'
     AND p_tipo NOT LIKE 'Lavado%'
     AND p_tipo <> 'Desinfección';
$$;


ALTER FUNCTION public.es_servicio_camion(p_tipo text) OWNER TO postgres;

--
-- Name: expire_stale_offers(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.expire_stale_offers() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  expired_count integer;
BEGIN
  UPDATE ofertas
  SET estado = 'rechazada'
  WHERE estado IN ('enviada', 'contra_oferta')
    AND expira_en IS NOT NULL
    AND expira_en < NOW();

  GET DIAGNOSTICS expired_count = ROW_COUNT;
  RETURN expired_count;
END;
$$;


ALTER FUNCTION public.expire_stale_offers() OWNER TO postgres;

--
-- Name: fn_notificar_nuevo_mensaje(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_notificar_nuevo_mensaje() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  recipient uuid;
  ctx_tipo  text;
  ctx_id    uuid;
begin
  -- El destinatario es el participante que NO es el remitente
  select p into recipient
  from unnest(new.participantes) p
  where p <> new.de_user_id
  limit 1;

  if recipient is null then
    return new;
  end if;

  if new.reserva_id is not null then
    ctx_tipo := 'reserva';
    ctx_id   := new.reserva_id;
  else
    ctx_tipo := 'pedido';
    ctx_id   := new.pedido_id;
  end if;

  insert into notificaciones (user_id, tipo, titulo, mensaje, leido, meta)
  values (
    recipient,
    'nuevo_mensaje',
    'Nuevo mensaje de ' || new.de_nombre,
    left(new.texto, 100),
    false,
    jsonb_build_object(
      'ctx_tipo',      ctx_tipo,
      'ctx_id',        ctx_id::text,
      'de_user_id',    new.de_user_id::text,
      'de_nombre',     new.de_nombre,
      'participantes', array_to_json(new.participantes)
    )
  );

  return new;
end;
$$;


ALTER FUNCTION public.fn_notificar_nuevo_mensaje() OWNER TO postgres;

--
-- Name: guard_expediente_documento(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.guard_expediente_documento() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  es_cliente boolean;
BEGIN
  IF public.is_superadmin() THEN RETURN NEW; END IF;

  SELECT (r.cliente_user_id = auth.uid()) INTO es_cliente
  FROM public.expedientes e
  JOIN public.reservaciones r ON r.id = e.reserva_id
  WHERE e.id = NEW.expediente_id;

  -- Solo el transportista dictamina.
  IF es_cliente AND NEW.estado IN ('aceptado', 'rechazado')
     AND NEW.estado IS DISTINCT FROM OLD.estado THEN
    RAISE EXCEPTION 'No autorizado: solo el transportista revisa los documentos';
  END IF;

  -- Solo el cliente sube.
  IF NOT es_cliente AND NEW.archivo_path IS DISTINCT FROM OLD.archivo_path THEN
    RAISE EXCEPTION 'No autorizado: solo el cliente sube los documentos';
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.guard_expediente_documento() OWNER TO postgres;

--
-- Name: guard_expediente_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.guard_expediente_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  es_cliente boolean;
begin
  if public.is_superadmin() then return new; end if;

  select (r.cliente_user_id = auth.uid()) into es_cliente
  from public.reservaciones r
  where r.id = new.reserva_id;

  if es_cliente then
    if new.estado is distinct from old.estado
       or new.completado_en is distinct from old.completado_en
       or new.incidente_motivo is distinct from old.incidente_motivo
       or new.incidente_reportado_en is distinct from old.incidente_reportado_en
       or new.incidente_reportado_por is distinct from old.incidente_reportado_por
       or new.deposito_vacios is distinct from old.deposito_vacios
       or new.fecha_limite_vacios is distinct from old.fecha_limite_vacios then
      raise exception 'No autorizado: eso lo gestiona el transportista';
    end if;
  else
    if new.entrega_fisica is distinct from old.entrega_fisica
       or new.entrega_fisica_direccion is distinct from old.entrega_fisica_direccion
       or new.entrega_fisica_contacto is distinct from old.entrega_fisica_contacto then
      raise exception 'No autorizado: la entrega en fisico la declara el cliente';
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION public.guard_expediente_update() OWNER TO postgres;

--
-- Name: guard_fleet_resource_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.guard_fleet_resource_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  IF NEW.aprobacion IS DISTINCT FROM OLD.aprobacion AND NEW.aprobacion IS DISTINCT FROM 'pendiente' THEN
    RAISE EXCEPTION 'No autorizado: solo un superadmin puede aprobar o rechazar este recurso';
  END IF;

  IF NEW.propietario_id IS DISTINCT FROM OLD.propietario_id THEN
    RAISE EXCEPTION 'No autorizado: no puedes transferir la propiedad de este recurso';
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.guard_fleet_resource_update() OWNER TO postgres;

--
-- Name: guard_oferta_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.guard_oferta_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
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
$$;


ALTER FUNCTION public.guard_oferta_update() OWNER TO postgres;

--
-- Name: guard_operador_hazmat(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.guard_operador_hazmat() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  es_peligrosa boolean;
  licencia_ok boolean;
begin
  if new.operador_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.operador_id is not distinct from old.operador_id then
    return new;
  end if;

  select p.carga_peligrosa into es_peligrosa
  from public.pedidos p where p.id = new.pedido_id;

  if not coalesce(es_peligrosa, false) then return new; end if;

  select (o.doc_licencia_peligrosa is not null
          and o.fecha_vencimiento_licencia_peligrosa is not null
          and o.fecha_vencimiento_licencia_peligrosa >= current_date)
    into licencia_ok
  from public.operadores o where o.id = new.operador_id;

  if not coalesce(licencia_ok, false) then
    raise exception 'LICENCIA_PELIGROSA_REQUERIDA: este servicio es de carga peligrosa; el chofer necesita licencia vigente de materiales peligrosos';
  end if;

  return new;
end;
$$;


ALTER FUNCTION public.guard_operador_hazmat() OWNER TO postgres;

--
-- Name: guard_pedido_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.guard_pedido_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
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
$$;


ALTER FUNCTION public.guard_pedido_update() OWNER TO postgres;

--
-- Name: guard_perfil_self_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.guard_perfil_self_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  IF NEW.rol IS DISTINCT FROM OLD.rol THEN
    RAISE EXCEPTION 'No autorizado: no puedes cambiar tu rol';
  END IF;

  IF NEW.aprobacion_cuenta IS DISTINCT FROM OLD.aprobacion_cuenta THEN
    IF NOT (OLD.aprobacion_cuenta = 'rechazada' AND NEW.aprobacion_cuenta = 'pendiente') THEN
      RAISE EXCEPTION 'No autorizado: no puedes cambiar el estado de aprobacion de tu cuenta';
    END IF;
  END IF;

  IF NEW.verificado           IS DISTINCT FROM OLD.verificado
     OR NEW.docs_aprobados_en   IS DISTINCT FROM OLD.docs_aprobados_en
     OR NEW.docs_aprobados_por  IS DISTINCT FROM OLD.docs_aprobados_por
     OR NEW.metodo_verificacion IS DISTINCT FROM OLD.metodo_verificacion THEN
    RAISE EXCEPTION 'No autorizado: campos de verificacion solo modificables por superadmin';
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.guard_perfil_self_update() OWNER TO postgres;

--
-- Name: guard_reservacion_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.guard_reservacion_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
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
$$;


ALTER FUNCTION public.guard_reservacion_update() OWNER TO postgres;

--
-- Name: is_superadmin(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_superadmin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM perfiles WHERE user_id = auth.uid() AND rol = 'superadmin'
  );
$$;


ALTER FUNCTION public.is_superadmin() OWNER TO postgres;

--
-- Name: limitar_plantillas(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.limitar_plantillas() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if (select count(*) from public.plantillas_pedido where cliente_id = new.cliente_id) >= 12 then
    raise exception 'Alcanzaste el maximo de 12 solicitudes frecuentes. Elimina alguna para guardar otra.';
  end if;
  return new;
end;
$$;


ALTER FUNCTION public.limitar_plantillas() OWNER TO postgres;

--
-- Name: mi_nombre(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.mi_nombre() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT COALESCE(nombre, 'Un usuario') FROM public.perfiles WHERE user_id = auth.uid();
$$;


ALTER FUNCTION public.mi_nombre() OWNER TO postgres;

--
-- Name: notificar_cambio_reserva(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notificar_cambio_reserva() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF NEW.estado <> OLD.estado AND NEW.cliente_user_id IS NOT NULL THEN
    IF NEW.estado = 'Activa' THEN
      INSERT INTO notificaciones (user_id, tipo, titulo, mensaje, meta)
      VALUES (
        NEW.cliente_user_id,
        'reserva_aceptada',
        '¡Tu reserva fue aceptada! ✓',
        'Unidad ' || NEW.unidad || ' · Del ' ||
          TO_CHAR(NEW.fecha_ini::date, 'DD/MM/YYYY') || ' al ' ||
          TO_CHAR(NEW.fecha_fin::date, 'DD/MM/YYYY'),
        jsonb_build_object('reserva_id', NEW.id, 'unidad', NEW.unidad, 'estado', 'Activa')
      );
    ELSIF NEW.estado = 'Rechazada' THEN
      INSERT INTO notificaciones (user_id, tipo, titulo, mensaje, meta)
      VALUES (
        NEW.cliente_user_id,
        'reserva_rechazada',
        'Solicitud no aceptada',
        'Unidad ' || NEW.unidad || ' · Del ' ||
          TO_CHAR(NEW.fecha_ini::date, 'DD/MM/YYYY') || ' al ' ||
          TO_CHAR(NEW.fecha_fin::date, 'DD/MM/YYYY'),
        jsonb_build_object('reserva_id', NEW.id, 'unidad', NEW.unidad, 'estado', 'Rechazada')
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.notificar_cambio_reserva() OWNER TO postgres;

--
-- Name: notificar_nueva_oferta(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notificar_nueva_oferta() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE v_cid uuid;
BEGIN
  SELECT cliente_id INTO v_cid FROM pedidos WHERE id = NEW.pedido_id;
  INSERT INTO notificaciones(user_id, tipo, titulo, mensaje, meta)
  VALUES (
    v_cid, 'nueva_oferta',
    'Nueva oferta en tu pedido',
    NEW.admin_nombre || ' ofreció $' || to_char(NEW.precio_oferta, 'FM999,999') || ' MXN',
    jsonb_build_object('oferta_id', NEW.id, 'pedido_id', NEW.pedido_id)
  );
  RETURN NEW;
END;
$_$;


ALTER FUNCTION public.notificar_nueva_oferta() OWNER TO postgres;

--
-- Name: notificar_nueva_reserva(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notificar_nueva_reserva() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_owner_id uuid;
BEGIN
  SELECT propietario_id INTO v_owner_id FROM camiones WHERE id = NEW.unidad;
  IF v_owner_id IS NOT NULL THEN
    INSERT INTO notificaciones (user_id, tipo, titulo, mensaje, meta)
    VALUES (
      v_owner_id,
      'reserva_pendiente',
      'Nueva solicitud de reserva',
      'Cliente: ' || NEW.cliente || ' · Unidad: ' || NEW.unidad ||
        ' · Del ' || TO_CHAR(NEW.fecha_ini::date, 'DD/MM/YYYY') ||
        ' al '   || TO_CHAR(NEW.fecha_fin::date, 'DD/MM/YYYY'),
      jsonb_build_object(
        'reserva_id', NEW.id,
        'unidad',     NEW.unidad,
        'cliente',    NEW.cliente,
        'fecha_ini',  NEW.fecha_ini,
        'fecha_fin',  NEW.fecha_fin
      )
    );
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.notificar_nueva_reserva() OWNER TO postgres;

--
-- Name: notificar_respuesta_oferta(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notificar_respuesta_oferta() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE v_cid uuid;
BEGIN
  -- Ronda 1: cliente responde a oferta del admin
  IF OLD.estado = 'enviada' AND NEW.estado IN ('contra_oferta','aceptada','rechazada') THEN
    INSERT INTO notificaciones(user_id, tipo, titulo, mensaje, meta)
    VALUES (
      NEW.admin_id, 'respuesta_oferta',
      CASE NEW.estado
        WHEN 'aceptada'      THEN '✓ Oferta aceptada'
        WHEN 'rechazada'     THEN 'Oferta rechazada'
        WHEN 'contra_oferta' THEN 'Contraoferta recibida'
      END,
      CASE NEW.estado
        WHEN 'aceptada'      THEN 'Aceptaron tu oferta de $' || to_char(NEW.precio_oferta,'FM999,999')
        WHEN 'rechazada'     THEN 'Rechazaron tu oferta de $' || to_char(NEW.precio_oferta,'FM999,999')
        WHEN 'contra_oferta' THEN 'El cliente contraofertó con $' || to_char(NEW.contra_precio,'FM999,999')
      END,
      jsonb_build_object('oferta_id', NEW.id, 'pedido_id', NEW.pedido_id)
    );
  END IF;
  -- Ronda 2: admin responde a contraoferta del cliente
  IF OLD.estado = 'contra_oferta' AND NEW.estado IN ('aceptada','rechazada') THEN
    SELECT cliente_id INTO v_cid FROM pedidos WHERE id = NEW.pedido_id;
    INSERT INTO notificaciones(user_id, tipo, titulo, mensaje, meta)
    VALUES (
      v_cid, 'respuesta_contra_oferta',
      CASE NEW.estado WHEN 'aceptada' THEN '✓ Contraoferta aceptada' ELSE 'Contraoferta rechazada' END,
      CASE NEW.estado
        WHEN 'aceptada'  THEN NEW.admin_nombre || ' aceptó tu contraoferta de $' || to_char(NEW.contra_precio,'FM999,999')
        WHEN 'rechazada' THEN NEW.admin_nombre || ' rechazó tu contraoferta'
      END,
      jsonb_build_object('oferta_id', NEW.id, 'pedido_id', NEW.pedido_id)
    );
  END IF;
  RETURN NEW;
END;
$_$;


ALTER FUNCTION public.notificar_respuesta_oferta() OWNER TO postgres;

--
-- Name: notificar_superadmins(text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notificar_superadmins(p_tipo text, p_titulo text, p_mensaje text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  INSERT INTO public.notificaciones (user_id, tipo, titulo, mensaje, leido)
  SELECT user_id, p_tipo, p_titulo, p_mensaje, false
    FROM public.perfiles WHERE rol = 'superadmin';
$$;


ALTER FUNCTION public.notificar_superadmins(p_tipo text, p_titulo text, p_mensaje text) OWNER TO postgres;

--
-- Name: participa_en_expediente(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.participa_en_expediente(exp_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.expedientes e
    JOIN public.reservaciones r ON r.id = e.reserva_id
    WHERE e.id = exp_id
      AND (r.cliente_user_id = auth.uid() OR r.propietario_id = auth.uid())
  ) OR public.is_superadmin();
$$;


ALTER FUNCTION public.participa_en_expediente(exp_id uuid) OWNER TO postgres;

--
-- Name: puede_notificar(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.puede_notificar(p_target uuid) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_ok boolean;
BEGIN
  SELECT
    (p_target = auth.uid())
    OR is_superadmin()
    OR EXISTS (SELECT 1 FROM perfiles pf WHERE pf.user_id = p_target AND pf.rol = 'superadmin')
    OR EXISTS (
      SELECT 1 FROM reservaciones r
      WHERE (r.propietario_id = auth.uid() AND r.cliente_user_id = p_target)
         OR (r.cliente_user_id = auth.uid() AND r.propietario_id = p_target)
    )
    OR EXISTS (
      SELECT 1 FROM ofertas o JOIN pedidos p ON p.id = o.pedido_id
      WHERE (o.admin_id = auth.uid() AND p.cliente_id = p_target)
         OR (p.cliente_id = auth.uid() AND o.admin_id = p_target)
    )
  INTO v_ok;
  RETURN coalesce(v_ok, false);
END;
$$;


ALTER FUNCTION public.puede_notificar(p_target uuid) OWNER TO postgres;

--
-- Name: recomendar_unidad(text, numeric, integer, integer, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.recomendar_unidad(p_categoria text, p_peso_ton numeric DEFAULT NULL::numeric, p_num_tarimas integer DEFAULT NULL::integer, p_num_contenedores integer DEFAULT NULL::integer, p_alto_m numeric DEFAULT NULL::numeric) RETURNS TABLE(tipo text, razon text)
    LANGUAGE plpgsql IMMUTABLE
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


ALTER FUNCTION public.recomendar_unidad(p_categoria text, p_peso_ton numeric, p_num_tarimas integer, p_num_contenedores integer, p_alto_m numeric) OWNER TO postgres;

--
-- Name: recurso_tipo_de_servicio(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.recurso_tipo_de_servicio(p_tipo text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT CASE
    WHEN p_tipo LIKE 'Custodio%' OR p_tipo = 'Supervisión remota' THEN 'custodio'
    WHEN p_tipo LIKE 'Patio%'    OR p_tipo = 'Bodega'             THEN 'patio'
    WHEN p_tipo LIKE 'Lavado%'   OR p_tipo IN ('Desinfección', 'Lavado Contenedor') THEN 'lavado'
    ELSE 'camion'
  END;
$$;


ALTER FUNCTION public.recurso_tipo_de_servicio(p_tipo text) OWNER TO postgres;

--
-- Name: registrar_evidencias(uuid, text[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.registrar_evidencias(p_reserva_id uuid, p_paths text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
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


ALTER FUNCTION public.registrar_evidencias(p_reserva_id uuid, p_paths text[]) OWNER TO postgres;

--
-- Name: responder_contraoferta(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.responder_contraoferta(p_oferta_id uuid, p_accion text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
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


ALTER FUNCTION public.responder_contraoferta(p_oferta_id uuid, p_accion text) OWNER TO postgres;

--
-- Name: responder_oferta(uuid, text, numeric, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.responder_oferta(p_oferta_id uuid, p_accion text, p_contra_precio numeric DEFAULT NULL::numeric, p_nota text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
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
$_$;


ALTER FUNCTION public.responder_oferta(p_oferta_id uuid, p_accion text, p_contra_precio numeric, p_nota text) OWNER TO postgres;

--
-- Name: solicitar_cancelacion(uuid, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.solicitar_cancelacion(p_reserva_id uuid, p_motivo text, p_detalle text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
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


ALTER FUNCTION public.solicitar_cancelacion(p_reserva_id uuid, p_motivo text, p_detalle text) OWNER TO postgres;

--
-- Name: sync_datos_pago(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sync_datos_pago() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if new.pagado is true and (old.pagado is distinct from true) then
    new.pagado_en := coalesce(new.pagado_en, now());
  elsif new.pagado is not true then
    new.pagado_en      := null;
    new.pagado_por     := null;
    new.pago_metodo    := null;
    new.pago_referencia := null;
  end if;
  return new;
end;
$$;


ALTER FUNCTION public.sync_datos_pago() OWNER TO postgres;

--
-- Name: tabla_recurso(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.tabla_recurso(p_recurso_tipo text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT CASE p_recurso_tipo
    WHEN 'custodio' THEN 'custodios'
    WHEN 'patio'    THEN 'patios'
    WHEN 'lavado'   THEN 'lavados'
    ELSE                 'camiones'
  END;
$$;


ALTER FUNCTION public.tabla_recurso(p_recurso_tipo text) OWNER TO postgres;

--
-- Name: tracking_pasos(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.tracking_pasos(p_recurso_tipo text) RETURNS text[]
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_clave text := 'tracking_' || COALESCE(NULLIF(p_recurso_tipo, ''), 'camion');
  v_pasos text[];
BEGIN
  SELECT array_agg(valor ORDER BY orden) INTO v_pasos
    FROM public.catalogos WHERE clave = v_clave AND activo;

  IF v_pasos IS NOT NULL AND array_length(v_pasos, 1) >= 2 THEN
    RETURN v_pasos;
  END IF;

  -- Respaldo: si alguien vacía el catálogo por accidente, el cierre de
  -- servicios (registrar_evidencias comprueba el último paso) tiene que seguir
  -- funcionando.
  RETURN CASE p_recurso_tipo
    WHEN 'custodio' THEN ARRAY['Confirmado','Asignado','En ruta','En servicio','Finalizado']
    WHEN 'patio'    THEN ARRAY['Confirmado','Listo','Recibido','En almacenaje','Liberado']
    WHEN 'lavado'   THEN ARRAY['Confirmado','Recibido','En lavado','Control','Listo']
    ELSE                 ARRAY['Confirmado','En camino','En carga','En tránsito','Entregado']
  END;
END;
$$;


ALTER FUNCTION public.tracking_pasos(p_recurso_tipo text) OWNER TO postgres;

--
-- Name: version_al_menos(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.version_al_menos(p_version text, p_minima text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
  a int[]; b int[]; i int;
BEGIN
  IF p_minima IS NULL OR btrim(p_minima) = '' THEN RETURN true; END IF;
  IF p_version IS NULL OR btrim(p_version) = '' THEN RETURN false; END IF;

  -- Se ignora cualquier sufijo tipo "1.2.3-beta": solo interesan los números.
  a := string_to_array(split_part(btrim(p_version), '-', 1), '.')::int[];
  b := string_to_array(split_part(btrim(p_minima),  '-', 1), '.')::int[];

  FOR i IN 1 .. greatest(array_length(a,1), array_length(b,1)) LOOP
    IF COALESCE(a[i], 0) > COALESCE(b[i], 0) THEN RETURN true;  END IF;
    IF COALESCE(a[i], 0) < COALESCE(b[i], 0) THEN RETURN false; END IF;
  END LOOP;

  RETURN true;  -- iguales
EXCEPTION WHEN others THEN
  -- Una versión con formato raro no debe dejar a nadie fuera de la app.
  RETURN true;
END;
$$;


ALTER FUNCTION public.version_al_menos(p_version text, p_minima text) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: app_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.app_config (
    clave text NOT NULL,
    valor jsonb NOT NULL,
    descripcion text,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.app_config OWNER TO postgres;

--
-- Name: TABLE app_config; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.app_config IS 'Interruptores y versión mínima de las apps. No evita publicar versiones: las vuelve seguras, porque permite bloquear una versión vieja que escribiría datos mal en lugar de esperar a que todos actualicen.';


--
-- Name: calificaciones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.calificaciones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    reservacion_id uuid,
    admin_id uuid NOT NULL,
    cliente_id uuid NOT NULL,
    rating integer NOT NULL,
    comentario text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT calificaciones_rating_check CHECK (((rating >= 1) AND (rating <= 5)))
);


ALTER TABLE public.calificaciones OWNER TO postgres;

--
-- Name: camiones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.camiones (
    id text NOT NULL,
    tipo text NOT NULL,
    capacidad integer NOT NULL,
    operador text,
    estado text DEFAULT 'disponible'::text NOT NULL,
    emoji text DEFAULT '🚛'::text,
    created_at timestamp with time zone DEFAULT now(),
    propietario_id uuid,
    calificacion numeric(2,1),
    aprobacion text DEFAULT 'aprobada'::text NOT NULL,
    archivos jsonb DEFAULT '[]'::jsonb,
    precio_dia numeric(14,2),
    origen text,
    rutas text,
    tipo_carga text[],
    dimensiones text,
    placas text,
    tiempo_respuesta text,
    num_serie text,
    tipo_placa text,
    marca text,
    version text,
    modelo_anio integer,
    color text,
    num_motor text,
    num_economico text,
    tipo_combustible text,
    tarjeta_circulacion text,
    fecha_expedicion_tc date,
    imagen_tc text,
    caat text,
    vigencia_caat date,
    imagen_caat text,
    rechazo_nota text,
    rechazo_campos text[],
    es_edicion boolean DEFAULT false,
    campos_editados text[],
    snapshot_anterior jsonb,
    fecha_vencimiento_tc date,
    fecha_vencimiento_seguro date,
    fecha_vencimiento_permiso_sct date,
    fecha_vencimiento_verificacion date,
    doc_sct text,
    doc_seguro text,
    doc_caat text,
    doc_verificacion text,
    doc_permiso_peligrosa text,
    fecha_vencimiento_permiso_peligrosa date,
    CONSTRAINT camiones_aprobacion_check CHECK ((aprobacion = ANY (ARRAY['pendiente'::text, 'aprobada'::text, 'rechazada'::text]))),
    CONSTRAINT camiones_calificacion_check CHECK (((calificacion >= (1)::numeric) AND (calificacion <= (5)::numeric)))
);


ALTER TABLE public.camiones OWNER TO postgres;

--
-- Name: catalogos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.catalogos (
    clave text NOT NULL,
    valor text NOT NULL,
    etiqueta text NOT NULL,
    ayuda text,
    orden smallint DEFAULT 0 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    meta jsonb
);


ALTER TABLE public.catalogos OWNER TO postgres;

--
-- Name: TABLE catalogos; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.catalogos IS 'Listas de negocio que las apps móviles leen en vez de traerlas compiladas. Agregar un plazo de pago o un paso de seguimiento debe ser un INSERT, no una versión nueva en las tiendas.';


--
-- Name: custodios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.custodios (
    id text NOT NULL,
    propietario_id uuid,
    nombre text NOT NULL,
    tipo text NOT NULL,
    descripcion text,
    certificaciones text[],
    disponibilidad text DEFAULT '24/7'::text,
    precio_dia numeric(14,2),
    estado text DEFAULT 'disponible'::text,
    aprobacion text DEFAULT 'aprobada'::text,
    created_at timestamp with time zone DEFAULT now(),
    rechazo_nota text,
    rechazo_campos text[],
    es_edicion boolean DEFAULT false,
    campos_editados text[],
    snapshot_anterior jsonb,
    fecha_vencimiento_cert date,
    porta_arma boolean DEFAULT false,
    num_licencia_sedena text,
    fecha_vencimiento_licencia_sedena date,
    doc_licencia_sedena text
);


ALTER TABLE public.custodios OWNER TO postgres;

--
-- Name: custodios_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.custodios_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.custodios_seq OWNER TO postgres;

--
-- Name: documentos_catalogo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.documentos_catalogo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    etapa text NOT NULL,
    nombre text NOT NULL,
    descripcion text,
    obligatorio boolean DEFAULT true NOT NULL,
    orden smallint DEFAULT 0 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT documentos_catalogo_etapa_check CHECK ((etapa = ANY (ARRAY['ingreso_puerto'::text, 'entrega_vacios'::text])))
);


ALTER TABLE public.documentos_catalogo OWNER TO postgres;

--
-- Name: TABLE documentos_catalogo; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.documentos_catalogo IS 'Qué documentos se le piden al cliente en cada etapa. Editable por el superadmin: cada naviera y terminal pide cosas distintas.';


--
-- Name: documentos_fiscales; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.documentos_fiscales (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    reservacion_id uuid,
    tipo text NOT NULL,
    folio_fiscal text,
    numero_folio text,
    serie text,
    pac text,
    pac_id text,
    xml_url text,
    pdf_url text,
    estado text DEFAULT 'vigente'::text NOT NULL,
    cancelado_en timestamp with time zone,
    cancelado_por uuid,
    motivo_cancelacion text,
    emitido_por uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT documentos_fiscales_estado_check CHECK ((estado = ANY (ARRAY['vigente'::text, 'cancelado'::text]))),
    CONSTRAINT documentos_fiscales_tipo_check CHECK ((tipo = ANY (ARRAY['carta_porte'::text, 'factura'::text])))
);


ALTER TABLE public.documentos_fiscales OWNER TO postgres;

--
-- Name: expediente_documentos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.expediente_documentos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    expediente_id uuid NOT NULL,
    nombre text NOT NULL,
    descripcion text,
    obligatorio boolean DEFAULT true NOT NULL,
    orden smallint DEFAULT 0 NOT NULL,
    estado text DEFAULT 'pendiente'::text NOT NULL,
    archivo_path text,
    archivo_nombre text,
    nota_rechazo text,
    subido_en timestamp with time zone,
    subido_por uuid,
    CONSTRAINT expediente_documentos_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'subido'::text, 'aceptado'::text, 'rechazado'::text])))
);


ALTER TABLE public.expediente_documentos OWNER TO postgres;

--
-- Name: expedientes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.expedientes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    reserva_id uuid NOT NULL,
    etapa text NOT NULL,
    estado text DEFAULT 'solicitado'::text NOT NULL,
    solicitado_por uuid,
    solicitado_en timestamp with time zone DEFAULT now() NOT NULL,
    completado_en timestamp with time zone,
    nota text,
    deposito_vacios text,
    fecha_limite_vacios date,
    entrega_fisica boolean DEFAULT false NOT NULL,
    entrega_fisica_direccion text,
    entrega_fisica_contacto text,
    incidente_motivo text,
    incidente_reportado_en timestamp with time zone,
    incidente_reportado_por uuid,
    CONSTRAINT expedientes_estado_check CHECK ((estado = ANY (ARRAY['solicitado'::text, 'en_revision'::text, 'completo'::text]))),
    CONSTRAINT expedientes_etapa_check CHECK ((etapa = ANY (ARRAY['ingreso_puerto'::text, 'entrega_vacios'::text])))
);


ALTER TABLE public.expedientes OWNER TO postgres;

--
-- Name: COLUMN expedientes.fecha_limite_vacios; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.expedientes.fecha_limite_vacios IS 'Último día para devolver el contenedor sin que corran demoras. Se avisa a ambas partes conforme se acerca.';


--
-- Name: lavados; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lavados (
    id text NOT NULL,
    propietario_id uuid NOT NULL,
    nombre text NOT NULL,
    tipos_vehiculo text[] DEFAULT '{}'::text[] NOT NULL,
    tipos_lavado text[] DEFAULT '{}'::text[] NOT NULL,
    precio_lavado numeric(14,2),
    capacidad integer,
    ubicacion text,
    horario text,
    descripcion text,
    estado text DEFAULT 'disponible'::text NOT NULL,
    aprobacion text DEFAULT 'pendiente'::text NOT NULL,
    rechazo_nota text,
    rechazo_campos text[],
    es_edicion boolean DEFAULT false,
    campos_editados text[],
    snapshot_anterior jsonb,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT lavados_aprobacion_check CHECK ((aprobacion = ANY (ARRAY['pendiente'::text, 'aprobada'::text, 'rechazada'::text]))),
    CONSTRAINT lavados_estado_check CHECK ((estado = ANY (ARRAY['disponible'::text, 'ocupado'::text, 'no_disponible'::text])))
);


ALTER TABLE public.lavados OWNER TO postgres;

--
-- Name: mensajes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.mensajes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    de_user_id uuid NOT NULL,
    de_nombre text NOT NULL,
    texto text NOT NULL,
    leido boolean DEFAULT false NOT NULL,
    reserva_id uuid,
    pedido_id uuid,
    participantes uuid[] DEFAULT '{}'::uuid[] NOT NULL
);


ALTER TABLE public.mensajes OWNER TO postgres;

--
-- Name: notificaciones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.notificaciones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    tipo text DEFAULT 'reserva'::text NOT NULL,
    titulo text NOT NULL,
    mensaje text,
    leido boolean DEFAULT false,
    meta jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.notificaciones OWNER TO postgres;

--
-- Name: ofertas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ofertas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pedido_id uuid NOT NULL,
    admin_id uuid NOT NULL,
    admin_nombre text NOT NULL,
    camion_id text,
    precio_oferta numeric NOT NULL,
    mensaje text,
    contra_precio numeric,
    contra_mensaje text,
    ronda integer DEFAULT 1 NOT NULL,
    estado text DEFAULT 'enviada'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    expira_en timestamp with time zone DEFAULT (now() + '2 days'::interval),
    operador_id text,
    operador_nombre text,
    permite_reoferta boolean DEFAULT true NOT NULL,
    CONSTRAINT ofertas_estado_check CHECK ((estado = ANY (ARRAY['enviada'::text, 'contra_oferta'::text, 'aceptada'::text, 'rechazada'::text]))),
    CONSTRAINT ofertas_ronda_check CHECK ((ronda = ANY (ARRAY[1, 2])))
);


ALTER TABLE public.ofertas OWNER TO postgres;

--
-- Name: operadores; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.operadores (
    id text NOT NULL,
    propietario_id uuid,
    curp text,
    nombre text NOT NULL,
    primer_apellido text,
    segundo_apellido text,
    sexo text,
    rfc text,
    nss text,
    tipo_sanguineo text,
    num_trabajador text,
    nivel_estudio text,
    correo text,
    telefono text,
    area text,
    puesto text,
    fecha_examen_medico date,
    num_licencia text,
    clase_licencia text,
    tipo_licencia text,
    fecha_expedicion date,
    fecha_vencimiento date,
    foto_operador text,
    foto_licencia text,
    aprobacion text DEFAULT 'pendiente'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    rechazo_nota text,
    rechazo_campos text[],
    es_edicion boolean DEFAULT false,
    campos_editados text[],
    snapshot_anterior jsonb,
    fecha_examen_toxicologico date,
    fecha_carta_antecedentes date,
    doc_examen_toxicologico text,
    doc_carta_antecedentes text,
    doc_examen_medico text,
    doc_licencia_peligrosa text,
    fecha_vencimiento_licencia_peligrosa date,
    CONSTRAINT operadores_aprobacion_check CHECK ((aprobacion = ANY (ARRAY['pendiente'::text, 'aprobada'::text, 'rechazada'::text])))
);


ALTER TABLE public.operadores OWNER TO postgres;

--
-- Name: pagos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pagos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    reservacion_id uuid,
    monto numeric NOT NULL,
    moneda text DEFAULT 'MXN'::text NOT NULL,
    metodo text,
    proveedor text,
    proveedor_id text,
    estado text DEFAULT 'pendiente'::text NOT NULL,
    referencia text,
    comprobante_url text,
    registrado_por uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completado_en timestamp with time zone,
    nota text,
    CONSTRAINT pagos_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'completado'::text, 'fallido'::text, 'reembolsado'::text]))),
    CONSTRAINT pagos_metodo_check CHECK ((metodo = ANY (ARRAY['spei'::text, 'tarjeta'::text, 'efectivo'::text, 'transferencia'::text, 'otro'::text]))),
    CONSTRAINT pagos_proveedor_check CHECK ((proveedor = ANY (ARRAY['stripe'::text, 'conekta'::text, 'openpay'::text, 'manual'::text])))
);


ALTER TABLE public.pagos OWNER TO postgres;

--
-- Name: patios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.patios (
    id text NOT NULL,
    propietario_id uuid,
    nombre text NOT NULL,
    tipo text NOT NULL,
    ubicacion text,
    area_m2 numeric,
    capacidad_vehiculos integer,
    servicios text[],
    precio_dia numeric(14,2),
    estado text DEFAULT 'disponible'::text,
    aprobacion text DEFAULT 'aprobada'::text,
    created_at timestamp with time zone DEFAULT now(),
    rechazo_nota text,
    rechazo_campos text[],
    es_edicion boolean DEFAULT false,
    campos_editados text[],
    snapshot_anterior jsonb,
    fecha_vencimiento_permiso date,
    doc_permiso text
);


ALTER TABLE public.patios OWNER TO postgres;

--
-- Name: patios_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.patios_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.patios_seq OWNER TO postgres;

--
-- Name: pedidos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pedidos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cliente_id uuid,
    cliente_nombre text NOT NULL,
    cliente_email text NOT NULL,
    tipo_camion text DEFAULT 'Cualquiera'::text NOT NULL,
    tipo_carga text,
    capacidad_min integer,
    origen text,
    destino text,
    fecha_ini date,
    fecha_fin date,
    descripcion text,
    precio_cliente numeric,
    estado text DEFAULT 'abierto'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    peso_carga numeric,
    num_bultos integer,
    hora_carga text,
    contacto_nombre text,
    contacto_tel text,
    carga_peligrosa boolean DEFAULT false,
    temp_controlada boolean DEFAULT false,
    requiere_seguro boolean DEFAULT false,
    requiere_factura boolean DEFAULT false,
    num_custodios integer,
    horario_servicio text,
    zona_cobertura text,
    num_vehiculos integer,
    tipo_vehiculos text,
    area_necesaria numeric,
    detalles_lugar text,
    detalles_hora text,
    detalles_contacto_nombre text,
    detalles_contacto_tel text,
    detalles_completados boolean DEFAULT false,
    oferta_pendiente_id uuid,
    rechazo_nota text,
    tipo_contenedor text,
    plazo_pago text,
    categoria_carga text,
    refrigerado boolean DEFAULT false NOT NULL,
    temp_min numeric,
    temp_max numeric,
    num_contenedores smallint,
    contenedor_1_tipo text,
    contenedor_1_peso numeric,
    contenedor_2_tipo text,
    contenedor_2_peso numeric,
    largo_m numeric,
    ancho_m numeric,
    alto_m numeric,
    hazmat_clase text,
    hazmat_un text,
    tipo_camion_sugerido text,
    entra_a_puerto boolean DEFAULT false NOT NULL,
    num_tarimas smallint,
    volumen_m3 numeric,
    origen_lat numeric,
    origen_lng numeric,
    destino_lat numeric,
    destino_lng numeric,
    fecha_arribo_puerto date,
    patio_externo boolean DEFAULT false NOT NULL,
    CONSTRAINT pedidos_estado_check CHECK ((estado = ANY (ARRAY['abierto'::text, 'en_negociacion'::text, 'acordado'::text, 'cancelado'::text, 'pendiente_revision'::text, 'pendiente_acuerdo'::text, 'rechazado'::text, 'finalizado'::text, 'expirado'::text])))
);


ALTER TABLE public.pedidos OWNER TO postgres;

--
-- Name: COLUMN pedidos.categoria_carga; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.pedidos.categoria_carga IS 'General | Consolidada | Suelta | Sobredimensionada | Hazmat | Contenerizada. Determina qué campos pide el formulario y qué unidad se recomienda.';


--
-- Name: COLUMN pedidos.refrigerado; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.pedidos.refrigerado IS 'Atributo transversal: aplica a General, Consolidada, Suelta y Contenerizada. Reemplaza el antiguo checkbox temp_controlada, que se sigue escribiendo por compatibilidad.';


--
-- Name: COLUMN pedidos.tipo_camion_sugerido; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.pedidos.tipo_camion_sugerido IS 'Unidad que calculó el sistema. Si difiere de tipo_camion, el cliente la cambió a mano.';


--
-- Name: COLUMN pedidos.entra_a_puerto; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.pedidos.entra_a_puerto IS 'El transporte debe ingresar al recinto portuario. Habilita el expediente documental de ingreso en la reservación.';


--
-- Name: COLUMN pedidos.num_tarimas; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.pedidos.num_tarimas IS 'Tarimas o pallets que ocupa la carga. Junto con peso_carga determina la unidad: manda la restricción más exigente (cubicaje).';


--
-- Name: COLUMN pedidos.fecha_arribo_puerto; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.pedidos.fecha_arribo_puerto IS 'Arribo estimado del buque. Nula si la carga no viene por puerto. Siempre anterior o igual a fecha_ini (la recolección).';


--
-- Name: COLUMN pedidos.patio_externo; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.pedidos.patio_externo IS 'El contenedor vacio se devuelve a un deposito externo (no necesariamente el recinto portuario). Habilita el expediente documental de entrega de vacios apenas se cierra el acuerdo.';


--
-- Name: perfiles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.perfiles (
    user_id uuid NOT NULL,
    nombre text NOT NULL,
    rol text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    rfc text,
    razon_social text,
    anos_operacion integer,
    num_unidades integer,
    seguro_rc boolean DEFAULT false,
    seguro_carga boolean DEFAULT false,
    permiso_sct text,
    descripcion text,
    telefono text,
    aprobacion_cuenta text,
    nota_rechazo_cuenta text,
    regimen_fiscal text,
    cp_fiscal text,
    tipo_persona text,
    fecha_vencimiento_permiso_sct date,
    fecha_vencimiento_seguro_rc date,
    fecha_vencimiento_seguro_carga date,
    perfil_docs_pendiente boolean DEFAULT false,
    fecha_vencimiento_permiso_sct_pendiente date,
    fecha_vencimiento_seguro_rc_pendiente date,
    fecha_vencimiento_seguro_carga_pendiente date,
    doc_permiso_sct text,
    doc_seguro_rc text,
    doc_seguro_carga text,
    doc_permiso_sct_pendiente text,
    doc_seguro_rc_pendiente text,
    doc_seguro_carga_pendiente text,
    docs_aprobados_en timestamp with time zone,
    docs_aprobados_por uuid,
    verificado boolean DEFAULT false,
    metodo_verificacion text,
    fotos_verificacion jsonb DEFAULT '[]'::jsonb NOT NULL,
    notif_email boolean DEFAULT true NOT NULL,
    CONSTRAINT perfiles_metodo_verificacion_check CHECK (((metodo_verificacion IS NULL) OR (metodo_verificacion = ANY (ARRAY['fisica'::text, 'documental'::text])))),
    CONSTRAINT perfiles_rol_check CHECK ((rol = ANY (ARRAY['superadmin'::text, 'admin'::text, 'cliente'::text]))),
    CONSTRAINT perfiles_tipo_persona_check CHECK ((tipo_persona = ANY (ARRAY['fisica'::text, 'moral'::text])))
);


ALTER TABLE public.perfiles OWNER TO postgres;

--
-- Name: COLUMN perfiles.notif_email; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.perfiles.notif_email IS 'Si el usuario quiere recibir los correos frecuentes (oportunidades, ofertas, cola de revisión). Los correos transaccionales se envían siempre. Default true.';


--
-- Name: plantillas_pedido; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.plantillas_pedido (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cliente_id uuid NOT NULL,
    nombre text NOT NULL,
    tipo_camion text,
    tipo_carga text,
    capacidad_min numeric,
    peso_carga numeric,
    num_bultos integer,
    tipo_contenedor text,
    origen text,
    destino text,
    hora_carga text,
    contacto_nombre text,
    contacto_tel text,
    carga_peligrosa boolean DEFAULT false NOT NULL,
    temp_controlada boolean DEFAULT false NOT NULL,
    requiere_seguro boolean DEFAULT false NOT NULL,
    requiere_factura boolean DEFAULT false NOT NULL,
    precio_cliente numeric,
    plazo_pago text,
    descripcion text,
    num_custodios integer,
    zona_cobertura text,
    horario_servicio text,
    num_vehiculos integer,
    tipo_vehiculos text,
    area_necesaria numeric,
    veces_usada integer DEFAULT 0 NOT NULL,
    ultima_vez_usada timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    entra_a_puerto boolean DEFAULT false NOT NULL,
    categoria_carga text,
    refrigerado boolean DEFAULT false NOT NULL,
    temp_min numeric,
    temp_max numeric,
    num_contenedores smallint,
    contenedor_1_tipo text,
    contenedor_1_peso numeric,
    contenedor_2_tipo text,
    contenedor_2_peso numeric,
    largo_m numeric,
    ancho_m numeric,
    alto_m numeric,
    hazmat_clase text,
    hazmat_un text,
    num_tarimas smallint,
    volumen_m3 numeric,
    patio_externo boolean DEFAULT false NOT NULL
);


ALTER TABLE public.plantillas_pedido OWNER TO postgres;

--
-- Name: reservaciones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reservaciones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    unidad text,
    cliente text NOT NULL,
    telefono text,
    fecha_ini date NOT NULL,
    fecha_fin date NOT NULL,
    descripcion text,
    estado text DEFAULT 'Activa'::text,
    created_at timestamp with time zone DEFAULT now(),
    cliente_email text,
    cliente_user_id uuid,
    tracking_estado text DEFAULT 'Confirmado'::text,
    precio_acordado numeric,
    recurso_tipo text DEFAULT 'camion'::text NOT NULL,
    propietario_id uuid,
    completado_en timestamp with time zone,
    calificado boolean DEFAULT false,
    pagado boolean DEFAULT false,
    peso_kg numeric,
    descripcion_mercancia text,
    clave_sat_mercancia text,
    unidad_medida_sat text,
    num_piezas integer,
    num_pedido_factura text,
    evidencias text[],
    pedido_id uuid,
    evidencias_cliente text[],
    finalizacion_solicitada_por text,
    finalizacion_nota text,
    finalizacion_aprobada_por uuid,
    finalizacion_aprobada_en timestamp with time zone,
    plazo_pago text,
    fecha_vencimiento_pago date,
    pagado_en timestamp with time zone,
    pagado_por uuid,
    pago_metodo text,
    pago_referencia text,
    cancelacion_solicitada_en timestamp with time zone,
    cancelacion_solicitada_por uuid,
    cancelacion_motivo text,
    cancelacion_detalle text,
    cancelacion_tracking_estado text,
    cancelacion_resuelta_en timestamp with time zone,
    cancelacion_resuelta_por uuid,
    cancelacion_nota_resolucion text,
    motivo_cambio_unidad text,
    operador_id text,
    operador_nombre text,
    documentos_carga text[],
    gps_link text
);


ALTER TABLE public.reservaciones OWNER TO postgres;

--
-- Name: reservaciones_historico; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reservaciones_historico (
    id uuid NOT NULL,
    unidad text,
    recurso_tipo text,
    cliente text,
    cliente_email text,
    cliente_user_id uuid,
    empresa text,
    fecha_ini date,
    fecha_fin date,
    descripcion text,
    estado text,
    tracking_estado text,
    created_at timestamp with time zone,
    archivado_at timestamp with time zone DEFAULT now(),
    archivado_por uuid
);


ALTER TABLE public.reservaciones_historico OWNER TO postgres;

--
-- Name: solicitudes_cuenta; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.solicitudes_cuenta (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    rol text NOT NULL,
    email text NOT NULL,
    nombre text,
    telefono text,
    rfc text,
    curp text,
    tipo_persona text,
    razon_social text,
    calle text,
    colonia text,
    ciudad text,
    estado_mx text,
    cp text,
    nombre_representante text,
    curp_representante text,
    tipo_sociedad text,
    anos_operacion integer,
    num_unidades integer,
    seguro_rc boolean DEFAULT false,
    seguro_carga boolean DEFAULT false,
    permiso_sct text,
    descripcion text,
    doc_id_oficial text,
    doc_constancia_fiscal text,
    doc_comprobante_dom text,
    doc_foto_domicilio text,
    doc_acta_constitutiva text,
    doc_poder_notarial text,
    doc_id_representante text,
    doc_fotos_oficinas jsonb DEFAULT '[]'::jsonb,
    estado text DEFAULT 'pendiente'::text,
    nota_rechazo text,
    created_at timestamp with time zone DEFAULT now(),
    giro_empresa text,
    tipo_mercancia text,
    certificaciones text,
    of_calle text,
    of_colonia text,
    of_ciudad text,
    of_estado_mx text,
    of_cp text,
    doc_opinion_sat text,
    num_operaciones_mensuales integer,
    mercancia_operaciones text,
    CONSTRAINT solicitudes_cuenta_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'aprobada'::text, 'rechazada'::text]))),
    CONSTRAINT solicitudes_cuenta_rol_check CHECK ((rol = ANY (ARRAY['cliente'::text, 'admin'::text])))
);


ALTER TABLE public.solicitudes_cuenta OWNER TO postgres;

--
-- Name: app_config app_config_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.app_config
    ADD CONSTRAINT app_config_pkey PRIMARY KEY (clave);


--
-- Name: calificaciones calificaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.calificaciones
    ADD CONSTRAINT calificaciones_pkey PRIMARY KEY (id);


--
-- Name: camiones camiones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.camiones
    ADD CONSTRAINT camiones_pkey PRIMARY KEY (id);


--
-- Name: catalogos catalogos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.catalogos
    ADD CONSTRAINT catalogos_pkey PRIMARY KEY (clave, valor);


--
-- Name: custodios custodios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.custodios
    ADD CONSTRAINT custodios_pkey PRIMARY KEY (id);


--
-- Name: documentos_catalogo documentos_catalogo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.documentos_catalogo
    ADD CONSTRAINT documentos_catalogo_pkey PRIMARY KEY (id);


--
-- Name: documentos_fiscales documentos_fiscales_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.documentos_fiscales
    ADD CONSTRAINT documentos_fiscales_pkey PRIMARY KEY (id);


--
-- Name: expediente_documentos expediente_documentos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expediente_documentos
    ADD CONSTRAINT expediente_documentos_pkey PRIMARY KEY (id);


--
-- Name: expedientes expedientes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expedientes
    ADD CONSTRAINT expedientes_pkey PRIMARY KEY (id);


--
-- Name: expedientes expedientes_reserva_id_etapa_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expedientes
    ADD CONSTRAINT expedientes_reserva_id_etapa_key UNIQUE (reserva_id, etapa);


--
-- Name: lavados lavados_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lavados
    ADD CONSTRAINT lavados_pkey PRIMARY KEY (id);


--
-- Name: mensajes mensajes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mensajes
    ADD CONSTRAINT mensajes_pkey PRIMARY KEY (id);


--
-- Name: notificaciones notificaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notificaciones
    ADD CONSTRAINT notificaciones_pkey PRIMARY KEY (id);


--
-- Name: ofertas ofertas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ofertas
    ADD CONSTRAINT ofertas_pkey PRIMARY KEY (id);


--
-- Name: operadores operadores_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operadores
    ADD CONSTRAINT operadores_pkey PRIMARY KEY (id);


--
-- Name: pagos pagos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_pkey PRIMARY KEY (id);


--
-- Name: patios patios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patios
    ADD CONSTRAINT patios_pkey PRIMARY KEY (id);


--
-- Name: pedidos pedidos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos
    ADD CONSTRAINT pedidos_pkey PRIMARY KEY (id);


--
-- Name: perfiles perfiles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.perfiles
    ADD CONSTRAINT perfiles_pkey PRIMARY KEY (user_id);


--
-- Name: plantillas_pedido plantillas_pedido_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.plantillas_pedido
    ADD CONSTRAINT plantillas_pedido_pkey PRIMARY KEY (id);


--
-- Name: reservaciones_historico reservaciones_historico_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones_historico
    ADD CONSTRAINT reservaciones_historico_pkey PRIMARY KEY (id);


--
-- Name: reservaciones reservaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones
    ADD CONSTRAINT reservaciones_pkey PRIMARY KEY (id);


--
-- Name: solicitudes_cuenta solicitudes_cuenta_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.solicitudes_cuenta
    ADD CONSTRAINT solicitudes_cuenta_pkey PRIMARY KEY (id);


--
-- Name: idx_catalogos_clave; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_catalogos_clave ON public.catalogos USING btree (clave, orden) WHERE activo;


--
-- Name: idx_expdocs_expediente; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_expdocs_expediente ON public.expediente_documentos USING btree (expediente_id);


--
-- Name: idx_expedientes_reserva; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_expedientes_reserva ON public.expedientes USING btree (reserva_id);


--
-- Name: idx_pedidos_categoria_carga; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_pedidos_categoria_carga ON public.pedidos USING btree (categoria_carga) WHERE (categoria_carga IS NOT NULL);


--
-- Name: idx_plantillas_cliente; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_plantillas_cliente ON public.plantillas_pedido USING btree (cliente_id, veces_usada DESC, created_at DESC);


--
-- Name: idx_reservaciones_cancelacion; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_reservaciones_cancelacion ON public.reservaciones USING btree (estado, cancelacion_solicitada_en) WHERE (estado = 'CancelacionSolicitada'::text);


--
-- Name: idx_reservaciones_cobro; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_reservaciones_cobro ON public.reservaciones USING btree (pagado, fecha_vencimiento_pago) WHERE (estado = 'Completada'::text);


--
-- Name: mensajes_part_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX mensajes_part_idx ON public.mensajes USING gin (participantes);


--
-- Name: mensajes_pedido_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX mensajes_pedido_idx ON public.mensajes USING btree (pedido_id) WHERE (pedido_id IS NOT NULL);


--
-- Name: mensajes_reserva_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX mensajes_reserva_idx ON public.mensajes USING btree (reserva_id) WHERE (reserva_id IS NOT NULL);


--
-- Name: ofertas tr_oferta_nueva; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER tr_oferta_nueva AFTER INSERT ON public.ofertas FOR EACH ROW EXECUTE FUNCTION public.notificar_nueva_oferta();


--
-- Name: ofertas tr_oferta_respuesta; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER tr_oferta_respuesta AFTER UPDATE ON public.ofertas FOR EACH ROW EXECUTE FUNCTION public.notificar_respuesta_oferta();


--
-- Name: reservaciones trg_cambio_reserva; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_cambio_reserva AFTER UPDATE ON public.reservaciones FOR EACH ROW EXECUTE FUNCTION public.notificar_cambio_reserva();


--
-- Name: reservaciones trg_check_reservacion_disponibilidad; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_check_reservacion_disponibilidad BEFORE INSERT OR UPDATE ON public.reservaciones FOR EACH ROW EXECUTE FUNCTION public.check_reservacion_disponibilidad();


--
-- Name: camiones trg_guard_camiones_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guard_camiones_update BEFORE UPDATE ON public.camiones FOR EACH ROW EXECUTE FUNCTION public.guard_fleet_resource_update();


--
-- Name: custodios trg_guard_custodios_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guard_custodios_update BEFORE UPDATE ON public.custodios FOR EACH ROW EXECUTE FUNCTION public.guard_fleet_resource_update();


--
-- Name: expediente_documentos trg_guard_expediente_documento; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guard_expediente_documento BEFORE UPDATE ON public.expediente_documentos FOR EACH ROW EXECUTE FUNCTION public.guard_expediente_documento();


--
-- Name: expedientes trg_guard_expediente_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guard_expediente_update BEFORE UPDATE ON public.expedientes FOR EACH ROW EXECUTE FUNCTION public.guard_expediente_update();


--
-- Name: lavados trg_guard_lavados_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guard_lavados_update BEFORE UPDATE ON public.lavados FOR EACH ROW EXECUTE FUNCTION public.guard_fleet_resource_update();


--
-- Name: ofertas trg_guard_oferta_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guard_oferta_update BEFORE UPDATE ON public.ofertas FOR EACH ROW EXECUTE FUNCTION public.guard_oferta_update();


--
-- Name: ofertas trg_guard_operador_hazmat_ofertas; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guard_operador_hazmat_ofertas BEFORE INSERT OR UPDATE ON public.ofertas FOR EACH ROW EXECUTE FUNCTION public.guard_operador_hazmat();


--
-- Name: reservaciones trg_guard_operador_hazmat_reservaciones; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guard_operador_hazmat_reservaciones BEFORE UPDATE ON public.reservaciones FOR EACH ROW EXECUTE FUNCTION public.guard_operador_hazmat();


--
-- Name: operadores trg_guard_operadores_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guard_operadores_update BEFORE UPDATE ON public.operadores FOR EACH ROW EXECUTE FUNCTION public.guard_fleet_resource_update();


--
-- Name: patios trg_guard_patios_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guard_patios_update BEFORE UPDATE ON public.patios FOR EACH ROW EXECUTE FUNCTION public.guard_fleet_resource_update();


--
-- Name: pedidos trg_guard_pedido_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guard_pedido_update BEFORE UPDATE ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.guard_pedido_update();


--
-- Name: perfiles trg_guard_perfil_self_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guard_perfil_self_update BEFORE UPDATE ON public.perfiles FOR EACH ROW EXECUTE FUNCTION public.guard_perfil_self_update();


--
-- Name: reservaciones trg_guard_reservacion_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guard_reservacion_update BEFORE UPDATE ON public.reservaciones FOR EACH ROW EXECUTE FUNCTION public.guard_reservacion_update();


--
-- Name: plantillas_pedido trg_limitar_plantillas; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_limitar_plantillas BEFORE INSERT ON public.plantillas_pedido FOR EACH ROW EXECUTE FUNCTION public.limitar_plantillas();


--
-- Name: mensajes trg_notificar_nuevo_mensaje; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_notificar_nuevo_mensaje AFTER INSERT ON public.mensajes FOR EACH ROW EXECUTE FUNCTION public.fn_notificar_nuevo_mensaje();


--
-- Name: reservaciones trg_notificar_reserva; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_notificar_reserva AFTER INSERT ON public.reservaciones FOR EACH ROW EXECUTE FUNCTION public.notificar_nueva_reserva();


--
-- Name: reservaciones trg_sync_datos_pago; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_sync_datos_pago BEFORE UPDATE ON public.reservaciones FOR EACH ROW EXECUTE FUNCTION public.sync_datos_pago();


--
-- Name: calificaciones calificaciones_reservacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.calificaciones
    ADD CONSTRAINT calificaciones_reservacion_id_fkey FOREIGN KEY (reservacion_id) REFERENCES public.reservaciones(id) ON DELETE CASCADE;


--
-- Name: camiones camiones_propietario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.camiones
    ADD CONSTRAINT camiones_propietario_id_fkey FOREIGN KEY (propietario_id) REFERENCES public.perfiles(user_id) ON DELETE SET NULL;


--
-- Name: custodios custodios_propietario_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.custodios
    ADD CONSTRAINT custodios_propietario_fk FOREIGN KEY (propietario_id) REFERENCES public.perfiles(user_id) ON DELETE SET NULL NOT VALID;


--
-- Name: custodios custodios_propietario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.custodios
    ADD CONSTRAINT custodios_propietario_id_fkey FOREIGN KEY (propietario_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: documentos_fiscales documentos_fiscales_cancelado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.documentos_fiscales
    ADD CONSTRAINT documentos_fiscales_cancelado_por_fkey FOREIGN KEY (cancelado_por) REFERENCES auth.users(id);


--
-- Name: documentos_fiscales documentos_fiscales_emitido_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.documentos_fiscales
    ADD CONSTRAINT documentos_fiscales_emitido_por_fkey FOREIGN KEY (emitido_por) REFERENCES auth.users(id);


--
-- Name: documentos_fiscales documentos_fiscales_reservacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.documentos_fiscales
    ADD CONSTRAINT documentos_fiscales_reservacion_id_fkey FOREIGN KEY (reservacion_id) REFERENCES public.reservaciones(id);


--
-- Name: expediente_documentos expediente_documentos_expediente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expediente_documentos
    ADD CONSTRAINT expediente_documentos_expediente_id_fkey FOREIGN KEY (expediente_id) REFERENCES public.expedientes(id) ON DELETE CASCADE;


--
-- Name: expedientes expedientes_incidente_reportado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expedientes
    ADD CONSTRAINT expedientes_incidente_reportado_por_fkey FOREIGN KEY (incidente_reportado_por) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: expedientes expedientes_reserva_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expedientes
    ADD CONSTRAINT expedientes_reserva_id_fkey FOREIGN KEY (reserva_id) REFERENCES public.reservaciones(id) ON DELETE CASCADE;


--
-- Name: lavados lavados_propietario_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lavados
    ADD CONSTRAINT lavados_propietario_fk FOREIGN KEY (propietario_id) REFERENCES public.perfiles(user_id) ON DELETE SET NULL NOT VALID;


--
-- Name: lavados lavados_propietario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lavados
    ADD CONSTRAINT lavados_propietario_id_fkey FOREIGN KEY (propietario_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mensajes mensajes_de_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mensajes
    ADD CONSTRAINT mensajes_de_user_id_fkey FOREIGN KEY (de_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mensajes mensajes_pedido_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mensajes
    ADD CONSTRAINT mensajes_pedido_id_fkey FOREIGN KEY (pedido_id) REFERENCES public.pedidos(id) ON DELETE CASCADE;


--
-- Name: mensajes mensajes_reserva_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mensajes
    ADD CONSTRAINT mensajes_reserva_id_fkey FOREIGN KEY (reserva_id) REFERENCES public.reservaciones(id) ON DELETE CASCADE;


--
-- Name: ofertas ofertas_admin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ofertas
    ADD CONSTRAINT ofertas_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES auth.users(id);


--
-- Name: ofertas ofertas_pedido_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ofertas
    ADD CONSTRAINT ofertas_pedido_id_fkey FOREIGN KEY (pedido_id) REFERENCES public.pedidos(id) ON DELETE CASCADE;


--
-- Name: operadores operadores_propietario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operadores
    ADD CONSTRAINT operadores_propietario_id_fkey FOREIGN KEY (propietario_id) REFERENCES public.perfiles(user_id) ON DELETE CASCADE;


--
-- Name: pagos pagos_registrado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_registrado_por_fkey FOREIGN KEY (registrado_por) REFERENCES auth.users(id);


--
-- Name: pagos pagos_reservacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_reservacion_id_fkey FOREIGN KEY (reservacion_id) REFERENCES public.reservaciones(id);


--
-- Name: patios patios_propietario_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patios
    ADD CONSTRAINT patios_propietario_fk FOREIGN KEY (propietario_id) REFERENCES public.perfiles(user_id) ON DELETE SET NULL NOT VALID;


--
-- Name: patios patios_propietario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patios
    ADD CONSTRAINT patios_propietario_id_fkey FOREIGN KEY (propietario_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: pedidos pedidos_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos
    ADD CONSTRAINT pedidos_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES auth.users(id);


--
-- Name: pedidos pedidos_oferta_pendiente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos
    ADD CONSTRAINT pedidos_oferta_pendiente_id_fkey FOREIGN KEY (oferta_pendiente_id) REFERENCES public.ofertas(id);


--
-- Name: perfiles perfiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.perfiles
    ADD CONSTRAINT perfiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: plantillas_pedido plantillas_pedido_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.plantillas_pedido
    ADD CONSTRAINT plantillas_pedido_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: reservaciones reservaciones_cancelacion_resuelta_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones
    ADD CONSTRAINT reservaciones_cancelacion_resuelta_por_fkey FOREIGN KEY (cancelacion_resuelta_por) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: reservaciones reservaciones_cancelacion_solicitada_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones
    ADD CONSTRAINT reservaciones_cancelacion_solicitada_por_fkey FOREIGN KEY (cancelacion_solicitada_por) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: reservaciones_historico reservaciones_historico_archivado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones_historico
    ADD CONSTRAINT reservaciones_historico_archivado_por_fkey FOREIGN KEY (archivado_por) REFERENCES auth.users(id);


--
-- Name: reservaciones reservaciones_pagado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones
    ADD CONSTRAINT reservaciones_pagado_por_fkey FOREIGN KEY (pagado_por) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: reservaciones reservaciones_pedido_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones
    ADD CONSTRAINT reservaciones_pedido_id_fkey FOREIGN KEY (pedido_id) REFERENCES public.pedidos(id) ON DELETE SET NULL;


--
-- Name: solicitudes_cuenta solicitudes_cuenta_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.solicitudes_cuenta
    ADD CONSTRAINT solicitudes_cuenta_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: camiones Actualizar camiones; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Actualizar camiones" ON public.camiones FOR UPDATE USING (((propietario_id = auth.uid()) OR public.is_superadmin()));


--
-- Name: calificaciones Clientes pueden insertar calificaciones; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Clientes pueden insertar calificaciones" ON public.calificaciones FOR INSERT TO authenticated WITH CHECK ((cliente_id = auth.uid()));


--
-- Name: camiones Eliminar camiones; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Eliminar camiones" ON public.camiones FOR DELETE USING (((propietario_id = auth.uid()) OR public.is_superadmin()));


--
-- Name: perfiles Insert own profile; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Insert own profile" ON public.perfiles FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));


--
-- Name: camiones Insertar camiones; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Insertar camiones" ON public.camiones FOR INSERT WITH CHECK (((auth.uid() IS NOT NULL) AND ((propietario_id = auth.uid()) OR public.is_superadmin())));


--
-- Name: perfiles Leer nombre de empresa; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Leer nombre de empresa" ON public.perfiles FOR SELECT USING ((auth.uid() IS NOT NULL));


--
-- Name: perfiles Leer propio perfil; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Leer propio perfil" ON public.perfiles FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: perfiles Superadmin update any profile; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Superadmin update any profile" ON public.perfiles FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.perfiles p
  WHERE ((p.user_id = auth.uid()) AND (p.rol = 'superadmin'::text)))));


--
-- Name: calificaciones Todos pueden ver calificaciones; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Todos pueden ver calificaciones" ON public.calificaciones FOR SELECT TO authenticated USING (true);


--
-- Name: perfiles Update own profile; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Update own profile" ON public.perfiles FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: pagos admin_registra_pago_manual; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY admin_registra_pago_manual ON public.pagos FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.reservaciones r
  WHERE ((r.id = pagos.reservacion_id) AND (r.propietario_id = auth.uid())))));


--
-- Name: documentos_fiscales admin_ve_sus_docs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY admin_ve_sus_docs ON public.documentos_fiscales FOR SELECT USING ((emitido_por = auth.uid()));


--
-- Name: pagos admin_ve_sus_pagos; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY admin_ve_sus_pagos ON public.pagos FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.reservaciones r
  WHERE ((r.id = pagos.reservacion_id) AND (r.propietario_id = auth.uid())))));


--
-- Name: app_config; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

--
-- Name: app_config app_config_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY app_config_select ON public.app_config FOR SELECT TO authenticated, anon USING (true);


--
-- Name: app_config app_config_write; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY app_config_write ON public.app_config TO authenticated USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());


--
-- Name: calificaciones; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.calificaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: camiones; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.camiones ENABLE ROW LEVEL SECURITY;

--
-- Name: camiones camiones_owner_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY camiones_owner_read ON public.camiones FOR SELECT USING (((propietario_id = auth.uid()) OR public.is_superadmin()));


--
-- Name: camiones camiones_public_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY camiones_public_read ON public.camiones FOR SELECT USING ((aprobacion = 'aprobada'::text));


--
-- Name: catalogos; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.catalogos ENABLE ROW LEVEL SECURITY;

--
-- Name: catalogos catalogos_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY catalogos_select ON public.catalogos FOR SELECT TO authenticated USING (true);


--
-- Name: catalogos catalogos_write; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY catalogos_write ON public.catalogos TO authenticated USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());


--
-- Name: documentos_fiscales cliente_ve_sus_docs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cliente_ve_sus_docs ON public.documentos_fiscales FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.reservaciones r
  WHERE ((r.id = documentos_fiscales.reservacion_id) AND (r.cliente_user_id = auth.uid())))));


--
-- Name: pagos cliente_ve_sus_pagos; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cliente_ve_sus_pagos ON public.pagos FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.reservaciones r
  WHERE ((r.id = pagos.reservacion_id) AND (r.cliente_user_id = auth.uid())))));


--
-- Name: custodios; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.custodios ENABLE ROW LEVEL SECURITY;

--
-- Name: custodios custodios_owner_all; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY custodios_owner_all ON public.custodios USING ((auth.uid() = propietario_id));


--
-- Name: custodios custodios_public_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY custodios_public_read ON public.custodios FOR SELECT USING ((aprobacion = 'aprobada'::text));


--
-- Name: custodios custodios_superadmin; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY custodios_superadmin ON public.custodios USING ((EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = 'superadmin'::text)))));


--
-- Name: operadores del_operadores; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY del_operadores ON public.operadores FOR DELETE TO authenticated USING (((auth.uid() = propietario_id) OR (EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = 'superadmin'::text))))));


--
-- Name: documentos_catalogo docs_catalogo_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY docs_catalogo_select ON public.documentos_catalogo FOR SELECT TO authenticated USING (true);


--
-- Name: documentos_catalogo docs_catalogo_write; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY docs_catalogo_write ON public.documentos_catalogo TO authenticated USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());


--
-- Name: documentos_catalogo; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.documentos_catalogo ENABLE ROW LEVEL SECURITY;

--
-- Name: documentos_fiscales; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.documentos_fiscales ENABLE ROW LEVEL SECURITY;

--
-- Name: expediente_documentos expdocs_all; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY expdocs_all ON public.expediente_documentos TO authenticated USING (public.participa_en_expediente(expediente_id)) WITH CHECK (public.participa_en_expediente(expediente_id));


--
-- Name: expediente_documentos; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.expediente_documentos ENABLE ROW LEVEL SECURITY;

--
-- Name: expedientes; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.expedientes ENABLE ROW LEVEL SECURITY;

--
-- Name: expedientes expedientes_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY expedientes_insert ON public.expedientes FOR INSERT TO authenticated WITH CHECK (((EXISTS ( SELECT 1
   FROM public.reservaciones r
  WHERE ((r.id = expedientes.reserva_id) AND ((r.cliente_user_id = auth.uid()) OR (r.propietario_id = auth.uid()))))) OR public.is_superadmin()));


--
-- Name: expedientes expedientes_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY expedientes_select ON public.expedientes FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.reservaciones r
  WHERE ((r.id = expedientes.reserva_id) AND ((r.cliente_user_id = auth.uid()) OR (r.propietario_id = auth.uid()))))) OR public.is_superadmin()));


--
-- Name: expedientes expedientes_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY expedientes_update ON public.expedientes FOR UPDATE TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.reservaciones r
  WHERE ((r.id = expedientes.reserva_id) AND ((r.cliente_user_id = auth.uid()) OR (r.propietario_id = auth.uid()))))) OR public.is_superadmin()));


--
-- Name: operadores ins_operadores; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY ins_operadores ON public.operadores FOR INSERT TO authenticated WITH CHECK (((auth.uid() = propietario_id) OR (EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = 'superadmin'::text))))));


--
-- Name: notificaciones insertar_notificaciones; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY insertar_notificaciones ON public.notificaciones FOR INSERT TO authenticated WITH CHECK (public.puede_notificar(user_id));


--
-- Name: lavados; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.lavados ENABLE ROW LEVEL SECURITY;

--
-- Name: lavados lavados_owner_all; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY lavados_owner_all ON public.lavados USING ((auth.uid() = propietario_id)) WITH CHECK ((auth.uid() = propietario_id));


--
-- Name: lavados lavados_public_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY lavados_public_read ON public.lavados FOR SELECT USING ((aprobacion = 'aprobada'::text));


--
-- Name: lavados lavados_superadmin; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY lavados_superadmin ON public.lavados USING ((EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = 'superadmin'::text)))));


--
-- Name: notificaciones marcar_leida; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY marcar_leida ON public.notificaciones FOR UPDATE TO authenticated USING ((user_id = auth.uid()));


--
-- Name: mensajes; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.mensajes ENABLE ROW LEVEL SECURITY;

--
-- Name: mensajes mensajes_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY mensajes_insert ON public.mensajes FOR INSERT WITH CHECK (((auth.uid() = de_user_id) AND (auth.uid() = ANY (participantes))));


--
-- Name: mensajes mensajes_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY mensajes_select ON public.mensajes FOR SELECT USING ((auth.uid() = ANY (participantes)));


--
-- Name: mensajes mensajes_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY mensajes_update ON public.mensajes FOR UPDATE USING ((auth.uid() = ANY (participantes)));


--
-- Name: mensajes msg_select_superadmin; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY msg_select_superadmin ON public.mensajes FOR SELECT TO authenticated USING (public.is_superadmin());


--
-- Name: notificaciones; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.notificaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: ofertas of_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY of_insert ON public.ofertas FOR INSERT WITH CHECK (((auth.uid() = admin_id) AND (EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = ANY (ARRAY['admin'::text, 'superadmin'::text])))))));


--
-- Name: ofertas of_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY of_select ON public.ofertas FOR SELECT USING (true);


--
-- Name: ofertas of_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY of_update ON public.ofertas FOR UPDATE USING (((auth.uid() = admin_id) OR (auth.uid() IN ( SELECT pedidos.cliente_id
   FROM public.pedidos
  WHERE (pedidos.id = ofertas.pedido_id))) OR (EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = 'superadmin'::text))))));


--
-- Name: ofertas; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.ofertas ENABLE ROW LEVEL SECURITY;

--
-- Name: operadores; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.operadores ENABLE ROW LEVEL SECURITY;

--
-- Name: pagos; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.pagos ENABLE ROW LEVEL SECURITY;

--
-- Name: patios; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.patios ENABLE ROW LEVEL SECURITY;

--
-- Name: patios patios_owner_all; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY patios_owner_all ON public.patios USING ((auth.uid() = propietario_id));


--
-- Name: patios patios_public_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY patios_public_read ON public.patios FOR SELECT USING ((aprobacion = 'aprobada'::text));


--
-- Name: patios patios_superadmin; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY patios_superadmin ON public.patios USING ((EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = 'superadmin'::text)))));


--
-- Name: pedidos ped_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY ped_delete ON public.pedidos FOR DELETE USING (((auth.uid() = cliente_id) OR (EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = 'superadmin'::text))))));


--
-- Name: pedidos ped_insert_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY ped_insert_own ON public.pedidos FOR INSERT WITH CHECK ((auth.uid() = cliente_id));


--
-- Name: pedidos ped_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY ped_select ON public.pedidos FOR SELECT TO authenticated USING ((public.is_superadmin() OR (estado = ANY (ARRAY['abierto'::text, 'en_negociacion'::text])) OR (cliente_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.ofertas o
  WHERE ((o.pedido_id = pedidos.id) AND (o.admin_id = auth.uid()))))));


--
-- Name: pedidos ped_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY ped_update ON public.pedidos FOR UPDATE USING (((auth.uid() = cliente_id) OR (EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = ANY (ARRAY['admin'::text, 'superadmin'::text])))))));


--
-- Name: pedidos; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.pedidos ENABLE ROW LEVEL SECURITY;

--
-- Name: perfiles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;

--
-- Name: plantillas_pedido plantillas_delete_propias; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY plantillas_delete_propias ON public.plantillas_pedido FOR DELETE TO authenticated USING ((cliente_id = auth.uid()));


--
-- Name: plantillas_pedido plantillas_insert_propias; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY plantillas_insert_propias ON public.plantillas_pedido FOR INSERT TO authenticated WITH CHECK ((cliente_id = auth.uid()));


--
-- Name: plantillas_pedido; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.plantillas_pedido ENABLE ROW LEVEL SECURITY;

--
-- Name: plantillas_pedido plantillas_select_propias; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY plantillas_select_propias ON public.plantillas_pedido FOR SELECT TO authenticated USING ((cliente_id = auth.uid()));


--
-- Name: plantillas_pedido plantillas_update_propias; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY plantillas_update_propias ON public.plantillas_pedido FOR UPDATE TO authenticated USING ((cliente_id = auth.uid())) WITH CHECK ((cliente_id = auth.uid()));


--
-- Name: reservaciones; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.reservaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: reservaciones reservaciones_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY reservaciones_delete ON public.reservaciones FOR DELETE USING (public.is_superadmin());


--
-- Name: reservaciones_historico; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.reservaciones_historico ENABLE ROW LEVEL SECURITY;

--
-- Name: reservaciones reservaciones_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY reservaciones_insert ON public.reservaciones FOR INSERT TO authenticated WITH CHECK (((cliente_user_id = auth.uid()) OR (propietario_id = auth.uid()) OR public.is_superadmin()));


--
-- Name: reservaciones reservaciones_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY reservaciones_select ON public.reservaciones FOR SELECT USING (((cliente_user_id = auth.uid()) OR (propietario_id = auth.uid()) OR public.is_superadmin()));


--
-- Name: reservaciones reservaciones_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY reservaciones_update ON public.reservaciones FOR UPDATE USING (((propietario_id = auth.uid()) OR (cliente_user_id = auth.uid()) OR public.is_superadmin()));


--
-- Name: solicitudes_cuenta sc_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY sc_insert ON public.solicitudes_cuenta FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: solicitudes_cuenta sc_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY sc_select ON public.solicitudes_cuenta FOR SELECT USING (((auth.uid() = user_id) OR (( SELECT perfiles.rol
   FROM public.perfiles
  WHERE (perfiles.user_id = auth.uid())) = 'superadmin'::text)));


--
-- Name: solicitudes_cuenta sc_update_own_rejected; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY sc_update_own_rejected ON public.solicitudes_cuenta FOR UPDATE TO authenticated USING (((auth.uid() = user_id) AND (estado = 'rechazada'::text))) WITH CHECK (((auth.uid() = user_id) AND (estado = 'pendiente'::text)));


--
-- Name: solicitudes_cuenta sc_update_super; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY sc_update_super ON public.solicitudes_cuenta FOR UPDATE USING ((( SELECT perfiles.rol
   FROM public.perfiles
  WHERE (perfiles.user_id = auth.uid())) = 'superadmin'::text));


--
-- Name: operadores sel_operadores; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY sel_operadores ON public.operadores FOR SELECT USING (((propietario_id = auth.uid()) OR public.is_superadmin()));


--
-- Name: solicitudes_cuenta; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.solicitudes_cuenta ENABLE ROW LEVEL SECURITY;

--
-- Name: pagos superadmin_gestiona_pagos; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY superadmin_gestiona_pagos ON public.pagos USING ((EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = 'superadmin'::text)))));


--
-- Name: reservaciones_historico superadmin_historico_all; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY superadmin_historico_all ON public.reservaciones_historico USING ((EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = 'superadmin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = 'superadmin'::text)))));


--
-- Name: documentos_fiscales superadmin_ve_todo_docs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY superadmin_ve_todo_docs ON public.documentos_fiscales USING ((EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = 'superadmin'::text)))));


--
-- Name: operadores upd_operadores; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY upd_operadores ON public.operadores FOR UPDATE TO authenticated USING (((auth.uid() = propietario_id) OR (EXISTS ( SELECT 1
   FROM public.perfiles
  WHERE ((perfiles.user_id = auth.uid()) AND (perfiles.rol = 'superadmin'::text))))));


--
-- Name: notificaciones ver_propias; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY ver_propias ON public.notificaciones FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION abrir_expediente(p_reserva_id uuid, p_etapa text, p_solo_si_aplica boolean); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.abrir_expediente(p_reserva_id uuid, p_etapa text, p_solo_si_aplica boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.abrir_expediente(p_reserva_id uuid, p_etapa text, p_solo_si_aplica boolean) TO authenticated;
GRANT ALL ON FUNCTION public.abrir_expediente(p_reserva_id uuid, p_etapa text, p_solo_si_aplica boolean) TO service_role;


--
-- Name: FUNCTION arranque_app(p_plataforma text, p_version text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.arranque_app(p_plataforma text, p_version text) TO anon;
GRANT ALL ON FUNCTION public.arranque_app(p_plataforma text, p_version text) TO authenticated;
GRANT ALL ON FUNCTION public.arranque_app(p_plataforma text, p_version text) TO service_role;


--
-- Name: FUNCTION avanzar_tracking(p_reserva_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.avanzar_tracking(p_reserva_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.avanzar_tracking(p_reserva_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.avanzar_tracking(p_reserva_id uuid) TO service_role;


--
-- Name: FUNCTION calificar_servicio(p_reserva_id uuid, p_rating integer, p_comentario text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.calificar_servicio(p_reserva_id uuid, p_rating integer, p_comentario text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.calificar_servicio(p_reserva_id uuid, p_rating integer, p_comentario text) TO authenticated;
GRANT ALL ON FUNCTION public.calificar_servicio(p_reserva_id uuid, p_rating integer, p_comentario text) TO service_role;


--
-- Name: FUNCTION cancelar_reservacion(p_reserva_id uuid, p_motivo text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.cancelar_reservacion(p_reserva_id uuid, p_motivo text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancelar_reservacion(p_reserva_id uuid, p_motivo text) TO authenticated;
GRANT ALL ON FUNCTION public.cancelar_reservacion(p_reserva_id uuid, p_motivo text) TO service_role;


--
-- Name: FUNCTION cerrar_acuerdo(p_oferta_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.cerrar_acuerdo(p_oferta_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cerrar_acuerdo(p_oferta_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.cerrar_acuerdo(p_oferta_id uuid) TO service_role;


--
-- Name: FUNCTION check_reservacion_disponibilidad(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.check_reservacion_disponibilidad() FROM PUBLIC;
GRANT ALL ON FUNCTION public.check_reservacion_disponibilidad() TO service_role;


--
-- Name: FUNCTION enviar_mensaje(p_texto text, p_participantes uuid[], p_reserva_id uuid, p_pedido_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.enviar_mensaje(p_texto text, p_participantes uuid[], p_reserva_id uuid, p_pedido_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.enviar_mensaje(p_texto text, p_participantes uuid[], p_reserva_id uuid, p_pedido_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.enviar_mensaje(p_texto text, p_participantes uuid[], p_reserva_id uuid, p_pedido_id uuid) TO service_role;


--
-- Name: FUNCTION enviar_oferta(p_pedido_id uuid, p_camion_id text, p_precio numeric, p_operador_id text, p_operador_nombre text, p_mensaje text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.enviar_oferta(p_pedido_id uuid, p_camion_id text, p_precio numeric, p_operador_id text, p_operador_nombre text, p_mensaje text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.enviar_oferta(p_pedido_id uuid, p_camion_id text, p_precio numeric, p_operador_id text, p_operador_nombre text, p_mensaje text) TO authenticated;
GRANT ALL ON FUNCTION public.enviar_oferta(p_pedido_id uuid, p_camion_id text, p_precio numeric, p_operador_id text, p_operador_nombre text, p_mensaje text) TO service_role;


--
-- Name: FUNCTION es_servicio_camion(p_tipo text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.es_servicio_camion(p_tipo text) TO anon;
GRANT ALL ON FUNCTION public.es_servicio_camion(p_tipo text) TO authenticated;
GRANT ALL ON FUNCTION public.es_servicio_camion(p_tipo text) TO service_role;


--
-- Name: FUNCTION expire_stale_offers(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.expire_stale_offers() FROM PUBLIC;
GRANT ALL ON FUNCTION public.expire_stale_offers() TO service_role;


--
-- Name: FUNCTION fn_notificar_nuevo_mensaje(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fn_notificar_nuevo_mensaje() FROM PUBLIC;
GRANT ALL ON FUNCTION public.fn_notificar_nuevo_mensaje() TO service_role;


--
-- Name: FUNCTION guard_expediente_documento(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.guard_expediente_documento() TO anon;
GRANT ALL ON FUNCTION public.guard_expediente_documento() TO authenticated;
GRANT ALL ON FUNCTION public.guard_expediente_documento() TO service_role;


--
-- Name: FUNCTION guard_expediente_update(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.guard_expediente_update() TO anon;
GRANT ALL ON FUNCTION public.guard_expediente_update() TO authenticated;
GRANT ALL ON FUNCTION public.guard_expediente_update() TO service_role;


--
-- Name: FUNCTION guard_fleet_resource_update(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.guard_fleet_resource_update() TO anon;
GRANT ALL ON FUNCTION public.guard_fleet_resource_update() TO authenticated;
GRANT ALL ON FUNCTION public.guard_fleet_resource_update() TO service_role;


--
-- Name: FUNCTION guard_oferta_update(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.guard_oferta_update() TO anon;
GRANT ALL ON FUNCTION public.guard_oferta_update() TO authenticated;
GRANT ALL ON FUNCTION public.guard_oferta_update() TO service_role;


--
-- Name: FUNCTION guard_operador_hazmat(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.guard_operador_hazmat() TO anon;
GRANT ALL ON FUNCTION public.guard_operador_hazmat() TO authenticated;
GRANT ALL ON FUNCTION public.guard_operador_hazmat() TO service_role;


--
-- Name: FUNCTION guard_pedido_update(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.guard_pedido_update() TO anon;
GRANT ALL ON FUNCTION public.guard_pedido_update() TO authenticated;
GRANT ALL ON FUNCTION public.guard_pedido_update() TO service_role;


--
-- Name: FUNCTION guard_perfil_self_update(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.guard_perfil_self_update() TO anon;
GRANT ALL ON FUNCTION public.guard_perfil_self_update() TO authenticated;
GRANT ALL ON FUNCTION public.guard_perfil_self_update() TO service_role;


--
-- Name: FUNCTION guard_reservacion_update(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.guard_reservacion_update() TO anon;
GRANT ALL ON FUNCTION public.guard_reservacion_update() TO authenticated;
GRANT ALL ON FUNCTION public.guard_reservacion_update() TO service_role;


--
-- Name: FUNCTION is_superadmin(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_superadmin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_superadmin() TO authenticated;
GRANT ALL ON FUNCTION public.is_superadmin() TO service_role;


--
-- Name: FUNCTION limitar_plantillas(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.limitar_plantillas() TO anon;
GRANT ALL ON FUNCTION public.limitar_plantillas() TO authenticated;
GRANT ALL ON FUNCTION public.limitar_plantillas() TO service_role;


--
-- Name: FUNCTION mi_nombre(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.mi_nombre() FROM PUBLIC;
GRANT ALL ON FUNCTION public.mi_nombre() TO authenticated;
GRANT ALL ON FUNCTION public.mi_nombre() TO service_role;


--
-- Name: FUNCTION notificar_cambio_reserva(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.notificar_cambio_reserva() FROM PUBLIC;
GRANT ALL ON FUNCTION public.notificar_cambio_reserva() TO service_role;


--
-- Name: FUNCTION notificar_nueva_oferta(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.notificar_nueva_oferta() FROM PUBLIC;
GRANT ALL ON FUNCTION public.notificar_nueva_oferta() TO service_role;


--
-- Name: FUNCTION notificar_nueva_reserva(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.notificar_nueva_reserva() FROM PUBLIC;
GRANT ALL ON FUNCTION public.notificar_nueva_reserva() TO service_role;


--
-- Name: FUNCTION notificar_respuesta_oferta(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.notificar_respuesta_oferta() FROM PUBLIC;
GRANT ALL ON FUNCTION public.notificar_respuesta_oferta() TO service_role;


--
-- Name: FUNCTION notificar_superadmins(p_tipo text, p_titulo text, p_mensaje text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.notificar_superadmins(p_tipo text, p_titulo text, p_mensaje text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notificar_superadmins(p_tipo text, p_titulo text, p_mensaje text) TO service_role;


--
-- Name: FUNCTION participa_en_expediente(exp_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.participa_en_expediente(exp_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.participa_en_expediente(exp_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.participa_en_expediente(exp_id uuid) TO service_role;


--
-- Name: FUNCTION puede_notificar(p_target uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.puede_notificar(p_target uuid) TO anon;
GRANT ALL ON FUNCTION public.puede_notificar(p_target uuid) TO authenticated;
GRANT ALL ON FUNCTION public.puede_notificar(p_target uuid) TO service_role;


--
-- Name: FUNCTION recomendar_unidad(p_categoria text, p_peso_ton numeric, p_num_tarimas integer, p_num_contenedores integer, p_alto_m numeric); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.recomendar_unidad(p_categoria text, p_peso_ton numeric, p_num_tarimas integer, p_num_contenedores integer, p_alto_m numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.recomendar_unidad(p_categoria text, p_peso_ton numeric, p_num_tarimas integer, p_num_contenedores integer, p_alto_m numeric) TO authenticated;
GRANT ALL ON FUNCTION public.recomendar_unidad(p_categoria text, p_peso_ton numeric, p_num_tarimas integer, p_num_contenedores integer, p_alto_m numeric) TO service_role;


--
-- Name: FUNCTION recurso_tipo_de_servicio(p_tipo text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.recurso_tipo_de_servicio(p_tipo text) TO anon;
GRANT ALL ON FUNCTION public.recurso_tipo_de_servicio(p_tipo text) TO authenticated;
GRANT ALL ON FUNCTION public.recurso_tipo_de_servicio(p_tipo text) TO service_role;


--
-- Name: FUNCTION registrar_evidencias(p_reserva_id uuid, p_paths text[]); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.registrar_evidencias(p_reserva_id uuid, p_paths text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.registrar_evidencias(p_reserva_id uuid, p_paths text[]) TO authenticated;
GRANT ALL ON FUNCTION public.registrar_evidencias(p_reserva_id uuid, p_paths text[]) TO service_role;


--
-- Name: FUNCTION responder_contraoferta(p_oferta_id uuid, p_accion text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.responder_contraoferta(p_oferta_id uuid, p_accion text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.responder_contraoferta(p_oferta_id uuid, p_accion text) TO authenticated;
GRANT ALL ON FUNCTION public.responder_contraoferta(p_oferta_id uuid, p_accion text) TO service_role;


--
-- Name: FUNCTION responder_oferta(p_oferta_id uuid, p_accion text, p_contra_precio numeric, p_nota text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.responder_oferta(p_oferta_id uuid, p_accion text, p_contra_precio numeric, p_nota text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.responder_oferta(p_oferta_id uuid, p_accion text, p_contra_precio numeric, p_nota text) TO authenticated;
GRANT ALL ON FUNCTION public.responder_oferta(p_oferta_id uuid, p_accion text, p_contra_precio numeric, p_nota text) TO service_role;


--
-- Name: FUNCTION solicitar_cancelacion(p_reserva_id uuid, p_motivo text, p_detalle text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.solicitar_cancelacion(p_reserva_id uuid, p_motivo text, p_detalle text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.solicitar_cancelacion(p_reserva_id uuid, p_motivo text, p_detalle text) TO authenticated;
GRANT ALL ON FUNCTION public.solicitar_cancelacion(p_reserva_id uuid, p_motivo text, p_detalle text) TO service_role;


--
-- Name: FUNCTION sync_datos_pago(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.sync_datos_pago() TO anon;
GRANT ALL ON FUNCTION public.sync_datos_pago() TO authenticated;
GRANT ALL ON FUNCTION public.sync_datos_pago() TO service_role;


--
-- Name: FUNCTION tabla_recurso(p_recurso_tipo text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.tabla_recurso(p_recurso_tipo text) TO anon;
GRANT ALL ON FUNCTION public.tabla_recurso(p_recurso_tipo text) TO authenticated;
GRANT ALL ON FUNCTION public.tabla_recurso(p_recurso_tipo text) TO service_role;


--
-- Name: FUNCTION tracking_pasos(p_recurso_tipo text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.tracking_pasos(p_recurso_tipo text) TO anon;
GRANT ALL ON FUNCTION public.tracking_pasos(p_recurso_tipo text) TO authenticated;
GRANT ALL ON FUNCTION public.tracking_pasos(p_recurso_tipo text) TO service_role;


--
-- Name: FUNCTION version_al_menos(p_version text, p_minima text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.version_al_menos(p_version text, p_minima text) TO anon;
GRANT ALL ON FUNCTION public.version_al_menos(p_version text, p_minima text) TO authenticated;
GRANT ALL ON FUNCTION public.version_al_menos(p_version text, p_minima text) TO service_role;


--
-- Name: TABLE app_config; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.app_config TO anon;
GRANT ALL ON TABLE public.app_config TO authenticated;
GRANT ALL ON TABLE public.app_config TO service_role;


--
-- Name: TABLE calificaciones; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.calificaciones TO anon;
GRANT ALL ON TABLE public.calificaciones TO authenticated;
GRANT ALL ON TABLE public.calificaciones TO service_role;


--
-- Name: TABLE camiones; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.camiones TO anon;
GRANT ALL ON TABLE public.camiones TO authenticated;
GRANT ALL ON TABLE public.camiones TO service_role;


--
-- Name: TABLE catalogos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.catalogos TO anon;
GRANT ALL ON TABLE public.catalogos TO authenticated;
GRANT ALL ON TABLE public.catalogos TO service_role;


--
-- Name: TABLE custodios; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.custodios TO anon;
GRANT ALL ON TABLE public.custodios TO authenticated;
GRANT ALL ON TABLE public.custodios TO service_role;


--
-- Name: SEQUENCE custodios_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.custodios_seq TO anon;
GRANT ALL ON SEQUENCE public.custodios_seq TO authenticated;
GRANT ALL ON SEQUENCE public.custodios_seq TO service_role;


--
-- Name: TABLE documentos_catalogo; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.documentos_catalogo TO anon;
GRANT ALL ON TABLE public.documentos_catalogo TO authenticated;
GRANT ALL ON TABLE public.documentos_catalogo TO service_role;


--
-- Name: TABLE documentos_fiscales; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.documentos_fiscales TO anon;
GRANT ALL ON TABLE public.documentos_fiscales TO authenticated;
GRANT ALL ON TABLE public.documentos_fiscales TO service_role;


--
-- Name: TABLE expediente_documentos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.expediente_documentos TO anon;
GRANT ALL ON TABLE public.expediente_documentos TO authenticated;
GRANT ALL ON TABLE public.expediente_documentos TO service_role;


--
-- Name: TABLE expedientes; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.expedientes TO anon;
GRANT ALL ON TABLE public.expedientes TO authenticated;
GRANT ALL ON TABLE public.expedientes TO service_role;


--
-- Name: TABLE lavados; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.lavados TO anon;
GRANT ALL ON TABLE public.lavados TO authenticated;
GRANT ALL ON TABLE public.lavados TO service_role;


--
-- Name: TABLE mensajes; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.mensajes TO anon;
GRANT ALL ON TABLE public.mensajes TO authenticated;
GRANT ALL ON TABLE public.mensajes TO service_role;


--
-- Name: TABLE notificaciones; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.notificaciones TO anon;
GRANT ALL ON TABLE public.notificaciones TO authenticated;
GRANT ALL ON TABLE public.notificaciones TO service_role;


--
-- Name: TABLE ofertas; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.ofertas TO anon;
GRANT ALL ON TABLE public.ofertas TO authenticated;
GRANT ALL ON TABLE public.ofertas TO service_role;


--
-- Name: TABLE operadores; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.operadores TO anon;
GRANT ALL ON TABLE public.operadores TO authenticated;
GRANT ALL ON TABLE public.operadores TO service_role;


--
-- Name: TABLE pagos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.pagos TO anon;
GRANT ALL ON TABLE public.pagos TO authenticated;
GRANT ALL ON TABLE public.pagos TO service_role;


--
-- Name: TABLE patios; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.patios TO anon;
GRANT ALL ON TABLE public.patios TO authenticated;
GRANT ALL ON TABLE public.patios TO service_role;


--
-- Name: SEQUENCE patios_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.patios_seq TO anon;
GRANT ALL ON SEQUENCE public.patios_seq TO authenticated;
GRANT ALL ON SEQUENCE public.patios_seq TO service_role;


--
-- Name: TABLE pedidos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.pedidos TO anon;
GRANT ALL ON TABLE public.pedidos TO authenticated;
GRANT ALL ON TABLE public.pedidos TO service_role;


--
-- Name: TABLE perfiles; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.perfiles TO anon;
GRANT ALL ON TABLE public.perfiles TO authenticated;
GRANT ALL ON TABLE public.perfiles TO service_role;


--
-- Name: TABLE plantillas_pedido; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.plantillas_pedido TO anon;
GRANT ALL ON TABLE public.plantillas_pedido TO authenticated;
GRANT ALL ON TABLE public.plantillas_pedido TO service_role;


--
-- Name: TABLE reservaciones; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.reservaciones TO anon;
GRANT ALL ON TABLE public.reservaciones TO authenticated;
GRANT ALL ON TABLE public.reservaciones TO service_role;


--
-- Name: TABLE reservaciones_historico; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.reservaciones_historico TO anon;
GRANT ALL ON TABLE public.reservaciones_historico TO authenticated;
GRANT ALL ON TABLE public.reservaciones_historico TO service_role;


--
-- Name: TABLE solicitudes_cuenta; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.solicitudes_cuenta TO anon;
GRANT ALL ON TABLE public.solicitudes_cuenta TO authenticated;
GRANT ALL ON TABLE public.solicitudes_cuenta TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict qWlui5QX5pF87wBomBlViJXnU2Q9VXko7kfvQrYh4g8tcCWGYhIXVjXbTFxbUqk

