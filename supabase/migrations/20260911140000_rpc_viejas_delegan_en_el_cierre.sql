-- ============================================================================
-- M8: las RPC del flujo viejo dejan de ser una segunda maquina de estados
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- La decision del 2026-09-09 dice que cuando las dos partes aceptan, la reserva
-- se crea y el superadmin no interviene. La web lo implementa llamando a
-- aceptar_y_cerrar_acuerdo().
--
-- Pero responder_oferta() y responder_contraoferta() no se retiraron, y su rama
-- 'aceptar' seguia escribiendo el flujo ANTERIOR:
--
--     UPDATE public.ofertas SET estado = 'aceptada' ...
--     UPDATE public.pedidos SET estado = 'pendiente_acuerdo' ...
--     -- y ninguna reservacion
--
-- Las dos siguen concedidas a authenticated —verificado en el volcado de
-- produccion del 2026-09-08— asi que son endpoints de PostgREST alcanzables por
-- cualquier sesion valida. No hace falta la interfaz para invocarlas.
--
-- No es un agujero de seguridad: quien las llama solo puede aceptar ofertas que
-- ya podia aceptar. El problema es que el estado que producen es
-- INDISTINGUIBLE del legitimo. 'pendiente_acuerdo' tiene un unico significado
-- segun docs/FLUJO-OPERATIVO.md —la empresa tiene documentos vencidos— asi que
-- una fila llegada por esta via aparece en la cola del superadmin marcada como
-- bloqueada, con todos los papeles en regla y sin nada que explique por que
-- esta ahi.
--
-- ── Por que delegar y no revocar ──────────────────────────────────────────
--
-- Revocar el permiso las dejaria inertes, pero el problema volveria cuando
-- arranque el trabajo movil: alguien encontraria dos RPC revocadas sin saber
-- por que, y la tentacion seria volver a concederlas tal cual estaban.
--
-- Delegar arregla en vez de desactivar. La rama 'aceptar' llama a la unica
-- implementacion que existe, y las otras ramas —contraofertar, rechazar— se
-- quedan EXACTAMENTE como estaban, porque no contradicen nada.
--
-- Efecto lateral que conviene saber: aceptar_y_cerrar_acuerdo comprueba cosas
-- que estas dos no comprobaban. La mas importante es el desvio por documentos
-- vencidos (DOCUMENTOS_VENCIDOS en guard_oferta_update): por esta via, una
-- empresa con el permiso SCT o los seguros vencidos cerraba el trato sin que
-- nadie lo mirara. Ahora cae en 'pendiente_acuerdo' de verdad, por el motivo
-- que ese estado significa, y avisa al superadmin.
--
-- Tambien hereda el FOR UPDATE sobre el pedido que introduce la migracion de
-- C2, asi que estas dos vias dejan de poder crear una reservacion duplicada.
--
-- ── Lo que cambia para quien las llama ────────────────────────────────────
--
-- Antes: aceptar dejaba el pedido en 'pendiente_acuerdo' y no devolvia nada.
-- Ahora: aceptar cierra el acuerdo y crea la reservacion, salvo que la empresa
-- tenga documentos vencidos. La firma no cambia (las dos siguen devolviendo
-- void), asi que ningun llamante se rompe por el tipo; cambia el estado en que
-- queda el pedido, que es justo lo que se venia a corregir.
--
-- Ningun cliente las usa hoy: la web llama a aceptar_y_cerrar_acuerdo
-- directamente y el cliente movil todavia no esta en manos de nadie.
--
-- ── Reversion ─────────────────────────────────────────────────────────────
--
-- Volver a aplicar los cuerpos del volcado 01-esquema-public.sql. No se borra
-- nada ni se cambia ningun permiso.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. responder_oferta() — el cliente acepta la oferta
-- ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.responder_oferta(p_oferta_id uuid, p_accion text, p_contra_precio numeric DEFAULT NULL::numeric, p_nota text DEFAULT NULL::text) RETURNS void
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
    -- Desde el 2026-09-09 aceptar CIERRA el acuerdo: las dos partes aceptan y
    -- la reserva se crea, sin superadmin. Esta rama escribia el flujo anterior
    -- —dejar el pedido en 'pendiente_acuerdo' sin reservacion— y era una
    -- segunda maquina de estados viva que contradecia la regla vigente.
    --
    -- Delega en la unica implementacion, en vez de repetirla. Ahi dentro se
    -- vuelve a comprobar quien llama, se bloquea el pedido (FOR UPDATE) y se
    -- trata el desvio por documentos vencidos, que aqui no existia: una empresa
    -- con el permiso SCT vencido cerraba por esta via sin que nadie lo mirara.
    PERFORM public.aceptar_y_cerrar_acuerdo(p_oferta_id, 'cliente_acepta_oferta');

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

-- ─────────────────────────────────────────────────────────────────────────
-- 2. responder_contraoferta() — la empresa acepta la contraoferta
-- ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.responder_contraoferta(p_oferta_id uuid, p_accion text) RETURNS void
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
    -- Misma razon que en responder_oferta: aceptar cierra el acuerdo desde el
    -- 2026-09-09. aceptar_y_cerrar_acuerdo se encarga tambien de copiar el
    -- contra_precio a precio_oferta, que es lo que hacia el UPDATE de aqui.
    PERFORM public.aceptar_y_cerrar_acuerdo(p_oferta_id, 'empresa_acepta_contra');

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

-- ─────────────────────────────────────────────────────────────────────────
-- 3. Los permisos NO se tocan
-- ─────────────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE conserva los GRANT existentes. Las dos siguen concedidas a
-- authenticated, y ahora eso ya no es un problema: hacen lo mismo que la web.
