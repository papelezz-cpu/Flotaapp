-- ──────────────────────────────────────────────────────────────────────────
-- ACEPTAR OFERTA/CONTRAOFERTA + CERRAR EL ACUERDO, EN UNA SOLA TRANSACCIÓN
--
-- H-10 (lote B). De los subflujos de oferta, los únicos con un problema real
-- de atomicidad son los dos que encadenan con cerrar_acuerdo:
--
--   · el cliente acepta una oferta            (js/pedidos.js:confirmarDetallesServicio)
--   · la empresa acepta la contraoferta       (js/pedidos.js:responderContra 'aceptar')
--
-- Hoy cada uno son ~3 escrituras sueltas desde el navegador (UPDATE ofertas,
-- UPDATE pedidos, y luego sb.rpc('cerrar_acuerdo'), que a su vez toca 6 tablas).
-- Si la pestaña se cierra o la red cae entre medias, queda la oferta en
-- 'aceptada' y el pedido en 'pendiente_acuerdo' SIN reservación: el recurso no
-- se ocupa, nadie puede reservarlo y solo un superadmin lo destraba a mano.
--
-- Esta función mete los tres pasos en la misma transacción. Los demás
-- subflujos (enviar oferta, rechazar, contraofertar, re-contraofertar) son de
-- 1-2 escrituras y su estado a medias se autocorrige — se quedan en JS.
--
-- ── Cómo se comporta ──────────────────────────────────────────────────────
-- SECURITY DEFINER, pero NO es superusuario del negocio: auth.uid() sale del
-- JWT, así que guard_oferta_update y guard_pedido_update SIGUEN aplicando
-- dentro. En particular, guard_oferta_update bloquea la aceptación si la
-- empresa tiene documentos vencidos (DOCUMENTOS_VENCIDOS); en ese caso no se
-- puede cerrar solo y se deja el pedido esperando al superadmin — mismo
-- comportamiento que hoy, solo que sin el estado a medias.
--
-- Las notificaciones de "oferta aceptada" / "contraoferta aceptada" las
-- disparan solos los triggers tr_oferta_respuesta; aquí NO se insertan a mano
-- para no duplicarlas. cerrar_acuerdo sí manda las suyas ('acuerdo_aprobado',
-- 'oferta_no_seleccionada') y eso no cambia.
--
-- El correo sigue siendo fire-and-forget del cliente (no se mete SMTP en una
-- transacción), igual que en el resto de la app.
-- ──────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.aceptar_y_cerrar_acuerdo(
  p_oferta_id uuid,
  p_via       text                       -- 'cliente_acepta_oferta' | 'empresa_acepta_contra'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_oferta     public.ofertas%ROWTYPE;
  v_pedido     public.pedidos%ROWTYPE;
  v_reserva_id uuid;
  v_docs_venc  boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF p_via NOT IN ('cliente_acepta_oferta', 'empresa_acepta_contra') THEN
    RAISE EXCEPTION 'Vía no reconocida: %', p_via;
  END IF;

  SELECT * INTO v_oferta FROM public.ofertas WHERE id = p_oferta_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La oferta ya no existe.';
  END IF;

  SELECT * INTO v_pedido FROM public.pedidos WHERE id = v_oferta.pedido_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La solicitud ya no existe.';
  END IF;

  -- Autorización según la vía. SECURITY DEFINER salta la RLS de SELECT/UPDATE,
  -- así que quién llama se verifica a mano; los guard triggers rematan.
  IF p_via = 'cliente_acepta_oferta' THEN
    IF v_pedido.cliente_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'No autorizado: esta solicitud no es tuya.';
    END IF;
    IF v_oferta.estado <> 'enviada' THEN
      RAISE EXCEPTION 'Esta oferta ya fue respondida.';
    END IF;
  ELSE  -- empresa_acepta_contra
    IF v_oferta.admin_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'No autorizado: esta oferta no es tuya.';
    END IF;
    IF v_oferta.estado <> 'contra_oferta' THEN
      RAISE EXCEPTION 'Esta oferta no tiene una contraoferta pendiente.';
    END IF;
  END IF;

  IF v_oferta.expira_en IS NOT NULL AND v_oferta.expira_en < now() THEN
    RAISE EXCEPTION 'Esta oferta ya venció.';
  END IF;
  IF v_pedido.estado NOT IN ('abierto', 'en_negociacion') THEN
    RAISE EXCEPTION 'Esta solicitud ya no está en negociación.';
  END IF;

  -- ── Paso 1: aceptar la oferta ──────────────────────────────────────────
  -- guard_oferta_update revalida la transición y bloquea con DOCUMENTOS_VENCIDOS
  -- si la empresa tiene permiso SCT / seguro RC / seguro de carga vencidos. Si
  -- eso ocurre, el subbloque revierte solo el UPDATE y seguimos por la rama de
  -- "esperar al superadmin".
  BEGIN
    IF p_via = 'empresa_acepta_contra' THEN
      UPDATE public.ofertas
         SET estado        = 'aceptada',
             precio_oferta  = COALESCE(v_oferta.contra_precio, v_oferta.precio_oferta)
       WHERE id = p_oferta_id;
    ELSE
      UPDATE public.ofertas SET estado = 'aceptada' WHERE id = p_oferta_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'DOCUMENTOS_VENCIDOS%' THEN
      v_docs_venc := true;
    ELSE
      RAISE;   -- cualquier otro error: propagar y revertir todo
    END IF;
  END;

  IF v_docs_venc THEN
    -- No se puede cerrar solo: el pedido queda a la espera del superadmin, que
    -- es el único que puede forzar el acuerdo con documentos vencidos.
    UPDATE public.pedidos
       SET estado = 'pendiente_acuerdo', oferta_pendiente_id = p_oferta_id
     WHERE id = v_pedido.id;

    PERFORM public.notificar_superadmins(
      'revision_acuerdo', 'Acuerdo pendiente — documentos vencidos',
      public.mi_nombre() || ' aceptó ' ||
      CASE p_via WHEN 'empresa_acepta_contra' THEN 'una contraoferta' ELSE 'una oferta' END
      || ' de ' || COALESCE(v_pedido.tipo_camion, 'servicio')
      || ', pero la empresa tiene documentos vencidos. Revísalo en Pendientes de aprobación.');

    RETURN jsonb_build_object('resultado', 'pendiente_docs', 'reserva_id', NULL);
  END IF;

  -- ── Paso 2: marcar el pedido y cerrar, en la misma transacción ─────────
  UPDATE public.pedidos
     SET estado = 'pendiente_acuerdo', oferta_pendiente_id = p_oferta_id
   WHERE id = v_pedido.id;

  -- cerrar_acuerdo rechaza las demás ofertas, marca el pedido 'acordado', crea
  -- la reservación y ocupa el recurso. Si algo revienta acá (típico:
  -- RECURSO_NO_DISPONIBLE por un solape de fechas que apareció entre la oferta
  -- y la aceptación), la excepción sube y revierte TODO, incluida la
  -- aceptación del paso 1 — que es justo lo que hoy no ocurre.
  v_reserva_id := public.cerrar_acuerdo(p_oferta_id);

  RETURN jsonb_build_object('resultado', 'cerrado', 'reserva_id', v_reserva_id);
END;
$$;

REVOKE ALL ON FUNCTION public.aceptar_y_cerrar_acuerdo(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.aceptar_y_cerrar_acuerdo(uuid, text) TO authenticated;
