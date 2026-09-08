-- ============================================================================
-- cancelar_reservacion: permite también al superadmin, no solo al propietario
-- ============================================================================
--
-- H-10 (auditoría): cancelarReserva() en js/reservaciones.js hace 7 escrituras
-- sueltas sin transacción. La RPC cancelar_reservacion (20260810120000) ya
-- hace lo mismo de forma atómica y no se llamaba desde el cliente.
--
-- Al conectarla se encontró una diferencia de comportamiento: el botón
-- "Cancelar" de hoy lo ve y lo puede usar cualquier superadmin sobre
-- cualquier reservación (esDueno en js/reservaciones.js incluye
-- currentUser.rol === 'superadmin' sin condición), pero la RPC solo
-- autorizaba al propietario_id exacto:
--
--   IF v_r.propietario_id IS DISTINCT FROM auth.uid() THEN
--     RAISE EXCEPTION 'No autorizado: esta reservación no es tuya.';
--   END IF;
--
-- Se agrega el mismo bypass is_superadmin() que ya usan todos los demás
-- guard triggers del proyecto (ver guard_reservacion_update, línea 57-59 de
-- 20260818090000_documentos_carga_entrega_fisica_gps.sql), para no cambiar
-- el comportamiento actual del superadmin al conectar la RPC en el cliente.
--
-- El resto del cuerpo es idéntico a 20260810120000_rpc_transacciones.sql:430-508.
-- ============================================================================

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
  IF NOT public.is_superadmin() AND v_r.propietario_id IS DISTINCT FROM auth.uid() THEN
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
