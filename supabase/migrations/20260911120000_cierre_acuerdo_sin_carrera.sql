-- ============================================================================
-- C2: el cierre del acuerdo no puede producir dos reservaciones para un pedido
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- aceptar_y_cerrar_acuerdo() lee el pedido y comprueba su estado SIN bloquear
-- la fila:
--
--     SELECT * INTO v_pedido FROM public.pedidos WHERE id = v_oferta.pedido_id;
--     ...
--     IF v_pedido.estado NOT IN ('abierto', 'en_negociacion') THEN
--       RAISE EXCEPTION 'Esta solicitud ya no esta en negociacion.';
--
-- Hay DOS vias legitimas y simultaneas de llegar ahi sobre el mismo pedido, y
-- el propio parametro p_via las nombra:
--
--   · el CLIENTE acepta la oferta A de la empresa X    (cliente_acepta_oferta)
--   · la EMPRESA Y acepta la contraoferta de su oferta B (empresa_acepta_contra)
--
-- Son dos personas distintas, en dos sesiones distintas, ambas haciendo algo
-- que el sistema les permite. En READ COMMITTED las dos leen el pedido en
-- 'en_negociacion', las dos pasan la comprobacion, y las dos siguen hasta
-- cerrar_acuerdo(), que inserta una reservacion.
--
-- Nada lo detiene aguas abajo:
--
--   · No hay UNIQUE sobre reservaciones.pedido_id. Verificado contra el volcado
--     de produccion: las unicas restricciones de unicidad del esquema son
--     expedientes(reserva_id, etapa) y uq_calificaciones_reservacion.
--
--   · reservaciones_sin_solape NO cubre este caso. Es un EXCLUDE sobre
--     (unidad, daterange): impide reservar LA MISMA unidad dos veces. Aqui son
--     dos unidades distintas, de dos empresas distintas.
--
-- Resultado: un pedido 'acordado' con dos reservaciones 'Activa', dos empresas
-- que creen tener el trabajo, dos unidades comprometidas y un cliente que
-- pagara una. Ademas la segunda transaccion marca 'rechazada' la oferta de la
-- primera, asi que su reservacion viva queda colgando de una oferta rechazada.
--
-- cerrar_acuerdo() tiene la misma carrera por su cuenta: dos llamadas
-- simultaneas —el superadmin forzando un 'pendiente_acuerdo' desde dos
-- pestanas— leen ambas 'pendiente_acuerdo' y ambas insertan.
--
-- ── El arreglo, en dos capas ──────────────────────────────────────────────
--
-- 1. FOR UPDATE sobre la fila del pedido, en las DOS funciones. Serializa las
--    transacciones que compiten por el mismo pedido: la segunda espera, y al
--    entrar re-lee la fila ya en 'acordado' y sale por el RAISE EXCEPTION que
--    ya estaba escrito. No hace falta logica nueva, solo que la comprobacion
--    existente mire datos frescos.
--
--    Se bloquea el PEDIDO y no la oferta a proposito: las dos vias entran por
--    ofertas DISTINTAS del mismo pedido, asi que bloquear la oferta no las
--    serializa. El pedido es el unico punto comun de las dos.
--
--    Solo se toma un lock por transaccion, asi que no hay pareja de bloqueos
--    que pueda cruzarse. cerrar_acuerdo() llamada desde
--    aceptar_y_cerrar_acuerdo() re-pide un lock que la transaccion ya tiene:
--    es gratis.
--
-- 2. Un indice unico PARCIAL como red declarativa, porque el lock protege este
--    camino y no los que se escriban manana.
--
--    Parcial y no a secas: cancelar una reserva reabre el pedido y una segunda
--    empresa puede ganarlo despues. Un UNIQUE sobre pedido_id romperia el
--    flujo de cancelar-reabrir que describe la seccion 9 del flujo operativo.
--
--    Sin CONCURRENTLY: el guion de produccion lo rechaza —no puede ir dentro
--    de una transaccion— y con el volumen actual el bloqueo es instantaneo.
--
-- ── Reversion ─────────────────────────────────────────────────────────────
--
--   drop index if exists public.uq_reservaciones_pedido_vivo;
--   -- y volver a aplicar 20260903120000 y 20260909120000 para los cuerpos.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. Antes de nada: comprobar si la carrera YA ocurrio
-- ─────────────────────────────────────────────────────────────────────────
-- Si hay duplicados, el indice de abajo falla al crearse con un mensaje de
-- Postgres que no dice cuales son. Mejor pararlo aqui, nombrando los pedidos,
-- porque esas filas hay que resolverlas A MANO: decidir cual reservacion vale
-- es una decision de negocio —que empresa se queda el viaje— y no algo que
-- esta migracion pueda tomar por su cuenta.

do $$
declare
  v_dups text;
begin
  select string_agg(pedido_id::text, ', ')
    into v_dups
    from (
      select pedido_id
        from public.reservaciones
       where pedido_id is not null
         and estado not in ('Cancelada', 'Rechazada')
       group by pedido_id
      having count(*) > 1
    ) d;

  if v_dups is not null then
    raise exception
      'C2: hay pedidos con mas de una reservacion viva: %. Resuelvelos antes de '
      'aplicar esta migracion; decidir cual vale es decision de negocio. Para '
      'verlas: select pedido_id, id, estado, propietario_id, unidad, '
      'precio_acordado, created_at from public.reservaciones where estado not in '
      '(''Cancelada'',''Rechazada'') order by pedido_id, created_at;', v_dups;
  end if;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. La red declarativa
-- ─────────────────────────────────────────────────────────────────────────
-- 'Rechazada' entra en la exclusion junto a 'Cancelada': una reserva rechazada
-- por la empresa tampoco ocupa el pedido, y el flujo permite que otra empresa
-- lo gane despues.

create unique index if not exists uq_reservaciones_pedido_vivo
  on public.reservaciones (pedido_id)
  where pedido_id is not null
    and estado not in ('Cancelada', 'Rechazada');

comment on index public.uq_reservaciones_pedido_vivo is
  'Un pedido no puede tener dos reservaciones vivas a la vez. Parcial a proposito: '
  'cancelar reabre el pedido y otra empresa puede ganarlo despues. Ver C2.';


-- ─────────────────────────────────────────────────────────────────────────
-- 3. aceptar_y_cerrar_acuerdo() — cuerpo identico salvo el FOR UPDATE
-- ─────────────────────────────────────────────────────────────────────────

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

  SELECT * INTO v_pedido FROM public.pedidos WHERE id = v_oferta.pedido_id
    FOR UPDATE;   -- C2: serializa el cierre sobre el mismo pedido
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

-- ─────────────────────────────────────────────────────────────────────────
-- 4. cerrar_acuerdo() — mismo cambio, por la carrera que tiene por su cuenta
-- ─────────────────────────────────────────────────────────────────────────

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

  SELECT * INTO v_pedido FROM public.pedidos WHERE id = v_oferta.pedido_id
    FOR UPDATE;   -- C2: serializa el cierre sobre el mismo pedido
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

-- ─────────────────────────────────────────────────────────────────────────
-- 5. Lo que NO cambia, para que no se busque
-- ─────────────────────────────────────────────────────────────────────────
--   · Los permisos de las dos funciones quedan como estaban: las sentencias
--     GRANT/REVOKE de 20260903120000 y 20260909120000 siguen vigentes, y
--     CREATE OR REPLACE no las toca.
--   · Los guard triggers siguen aplicando dentro de las dos: leen auth.uid(),
--     y CREATE OR REPLACE no altera SECURITY DEFINER ni el search_path fijado.
--   · reservaciones_sin_solape se queda. Cubre otra cosa —la misma unidad en
--     fechas solapadas— y la cubre bien.
