-- ============================================================================
-- Cuando las dos partes aceptan, la reserva se crea. Sin pasar por superadmin.
-- ============================================================================
--
-- SINTOMA. Un cliente acepta una oferta y la app responde:
--
--     No se pudo cerrar el acuerdo: No autorizado: una reserva que tu creas
--     nace Pendiente; la confirma la empresa
--
-- ── De donde sale ─────────────────────────────────────────────────────────
--
-- 20260831200000_cierra_huecos_flujo.sql anadio trg_guard_reservacion_insert
-- para impedir que un cliente se cree por su cuenta una reserva ya confirmada
-- y con precio puesto por el. Eso es correcto y se conserva.
--
-- Lo que no contemplo es cerrar_acuerdo(): ahi el cliente NO se impone nada.
-- Hay una oferta que la empresa emitio y que el cliente acepto —o al reves, en
-- la contraoferta—, y el precio, el propietario y la unidad salen de esa
-- oferta, no de quien llama. El guard veia "el que inserta es el cliente" y
-- cortaba.
--
-- Resultado, desde el 31 de agosto:
--
--     superadmin aprueba el acuerdo   -> is_superadmin()            -> pasa
--     empresa acepta la contraoferta  -> propietario_id = auth.uid() -> pasa
--     CLIENTE acepta la oferta        -> exige 'Pendiente' sin precio -> FALLA
--
-- ── Por que nadie lo vio hasta hoy ────────────────────────────────────────
--
-- El js/pedidos.js de entonces se tragaba el error:
--
--     } else {
--       console.error('Error al cerrar el acuerdo:', errCierre);
--       mensajeFinal = '✓ Acuerdo aceptado — quedó pendiente de revisión.';
--     }
--
-- Un console.error y un mensaje CON PALOMITA que parecia exito. El pedido
-- quedaba en 'pendiente_acuerdo' y el superadmin lo cerraba despues, asi que
-- el flujo terminaba bien y nadie noto que el cierre automatico llevaba dos
-- semanas sin funcionar. El lote B de H-10 (20260903120000) propaga el error
-- en vez de esconderlo, y por eso ahora se ve.
--
-- ── La decision ───────────────────────────────────────────────────────────
--
-- Tomada por el dueno del producto el 2026-09-09: cuando las dos partes
-- aceptan, se va a reservas. El superadmin deja de ser un paso intermedio del
-- acuerdo.
--
-- Lo que NO cambia: si la empresa tiene documentos vencidos, guard_oferta_update
-- sigue bloqueando la aceptacion con DOCUMENTOS_VENCIDOS y el pedido queda a la
-- espera del superadmin. Ese control es de otra naturaleza —no aprueba el
-- trato, impide que trabaje quien no tiene papeles al dia— y se conserva.
--
-- ── Por que la escotilla es estrecha ──────────────────────────────────────
--
-- Se abre SOLO dentro de cerrar_acuerdo(), y esa funcion ya verifica, antes de
-- insertar nada:
--
--   · la oferta existe y esta en estado 'aceptada';
--   · el pedido esta en 'pendiente_acuerdo' y su oferta_pendiente_id apunta a
--     esa oferta —si no, no inserta: devuelve la reserva que ya existiera;
--   · quien llama es superadmin, o el cliente del pedido, o el admin de la
--     oferta. Es decir, PARTE DEL ACUERDO.
--
-- Y todos los campos de la reserva se derivan de la oferta y del pedido:
-- precio_acordado sale de v_oferta.precio_oferta, propietario_id de
-- v_oferta.admin_id, cliente_user_id de v_pedido.cliente_id. Quien llama no
-- inyecta ninguno. Por eso saltarse el guard aqui no le da a un cliente nada
-- que no tuviera ya derecho a obtener.
--
-- El interruptor es un GUC local a la transaccion, mismo patron que
-- portgo.sync en 20260908140000. cerrar_acuerdo es SECURITY DEFINER y esta
-- revocada para anon; set_config vive en pg_catalog, fuera del esquema que
-- PostgREST expone, asi que no hay forma de encenderlo desde fuera.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. El guard, con la excepcion del cierre de acuerdo
-- ─────────────────────────────────────────────────────────────────────────
-- Copia literal de 20260831200000, con las cuatro lineas del primer IF.

CREATE OR REPLACE FUNCTION public.guard_reservacion_insert() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  -- NUEVO: cierre de un acuerdo mutuo. Solo lo enciende cerrar_acuerdo(), que
  -- ya comprobo que hay oferta aceptada y que quien llama es parte del trato.
  if current_setting('portgo.cierre_acuerdo', true) = 'on' then
    return new;
  end if;

  -- El superadmin cierra los acuerdos: js/aprobaciones.js llama a
  -- cerrarAcuerdo(), y ahí la reserva nace 'Activa' con el precio pactado.
  if public.is_superadmin() then
    return new;
  end if;

  -- La empresa dueña del recurso puede crearla como quiera: es la parte que
  -- acepta el trato, no la que se lo impone a otro.
  if new.propietario_id = auth.uid() then
    return new;
  end if;

  -- Un cliente agendando por su cuenta desde el catalogo: la reserva nace
  -- Pendiente y sin precio, y la confirma la empresa. Esto NO cambia.
  if new.cliente_user_id = auth.uid() then
    if new.estado is distinct from 'Pendiente' then
      raise exception 'No autorizado: una reserva que tu creas nace Pendiente; la confirma la empresa';
    end if;
    if new.precio_acordado is not null then
      raise exception 'No autorizado: el precio lo fija la empresa al aceptar, no quien agenda';
    end if;
    if new.pedido_id is not null and not public.es_mi_pedido(new.pedido_id) then
      raise exception 'No autorizado: esa solicitud no es tuya';
    end if;
    return new;
  end if;

  raise exception 'No autorizado: solo puedes crear reservaciones a tu nombre';
end;
$$;

REVOKE ALL ON FUNCTION public.guard_reservacion_insert() FROM PUBLIC, anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. cerrar_acuerdo enciende el interruptor justo antes de insertar
-- ─────────────────────────────────────────────────────────────────────────
-- Cuerpo identico al vigente salvo esa linea. El set_config va DESPUES de
-- todas las comprobaciones de autorizacion, no antes: si alguna falla, la
-- funcion ya salio por excepcion y el interruptor nunca llego a encenderse.
--
-- El tercer argumento en true lo hace local a la transaccion: al terminar
-- —commit o rollback— vuelve solo a su valor anterior.

CREATE OR REPLACE FUNCTION public.cerrar_acuerdo(p_oferta_id uuid) RETURNS uuid
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

  -- A partir de aqui esta confirmado que hay acuerdo mutuo y que quien llama
  -- es parte de el. El guard de INSERT puede apartarse.
  PERFORM set_config('portgo.cierre_acuerdo', 'on', true);

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

REVOKE ALL ON FUNCTION public.cerrar_acuerdo(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cerrar_acuerdo(uuid) TO authenticated;
