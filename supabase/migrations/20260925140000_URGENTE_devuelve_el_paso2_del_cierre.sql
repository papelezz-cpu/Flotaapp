-- ============================================================================
-- URGENTE — devuelve el Paso 2 a aceptar_y_cerrar_acuerdo()
-- ============================================================================
--
-- ── Qué rompí, y desde cuándo ─────────────────────────────────────────────
--
-- `20260924150000_hazmat_del_camion_frena_el_trato.sql` redefinió
-- `aceptar_y_cerrar_acuerdo()` para que el guard del permiso de materiales
-- peligrosos frenara el trato. Su cabecera decía «solo cambian tres cosas de
-- esta función». Cambió una cuarta, sin querer: **perdió el bloque «Paso 2»**,
-- que es el que marca el pedido antes de cerrar.
--
--     -- ── Paso 2: marcar el pedido y cerrar, en la misma transacción ──
--     UPDATE public.pedidos
--        SET estado = 'pendiente_acuerdo', oferta_pendiente_id = p_oferta_id
--      WHERE id = v_pedido.id;
--
--     v_reserva_id := public.cerrar_acuerdo(p_oferta_id);
--
-- Sin ese UPDATE, `cerrar_acuerdo()` se va por su **salida temprana**:
--
--     IF v_pedido.estado <> 'pendiente_acuerdo'
--        OR v_pedido.oferta_pendiente_id IS DISTINCT FROM p_oferta_id THEN
--       SELECT id INTO v_reserva_id FROM public.reservaciones ...;
--       RETURN v_reserva_id;         -- NULL: no crea nada y NO lanza
--     END IF;
--
-- Esa salida existe por idempotencia (20260827190000, el caso de la oferta
-- huérfana) y está bien. Lo que estaba mal era llamarla sin cumplir su
-- precondición.
--
-- **Consecuencia: el cliente acepta una oferta, la interfaz le dice que todo
-- fue bien, y no se crea ninguna reservación.** La RPC devuelve
-- `{resultado: 'cerrado', reserva_id: null}` — «cerrado» y nada cerrado. Un
-- fallo callado en el paso central del negocio.
--
-- Aplicada a pruebas el 2026-09-24T22:13Z y a **PRODUCCIÓN el
-- 2026-09-24T23:06Z**, así que el camino estuvo roto ahí unas 22 horas.
--
-- ── Por qué no lo vio nadie ───────────────────────────────────────────────
--
-- Porque el sistema lo disimula: `sincronizar_estados_pedidos()` tiene la regla
-- (c) —«pedido en negociación con una oferta aceptada → pendiente_acuerdo»—, así
-- que en los 15 minutos siguientes el pedido aparece en la cola del superadmin y
-- él lo cierra con «✓ Aprobar acuerdo». El acuerdo acaba cerrándose; solo que
-- **con el superadmin de por medio en cada trato**, cuando el flujo dice
-- explícitamente que las dos partes aceptan y la reservación se crea sin él.
--
-- Hasta hoy el disimulo era además instantáneo: `renderPedidos()` aplicaba esa
-- misma regla al dibujar la lista. Se retiró el 2026-09-25 (ahora la aplica solo
-- el cron), y por eso el síntoma se hizo visible: el usuario vio «⏳ Acuerdo en
-- revisión» y avisó. **El cambio del render no causó el defecto; le quitó la
-- venda.**
--
-- ── Cómo se cometió, que es lo que hay que no repetir ─────────────────────
--
-- Teclee el cuerpo de la función en la migración en vez de derivarlo de la
-- definición VIVA. Este mismo repositorio ya tenía escrita la regla —«si hay que
-- verificarlo, se lee `pg_get_functiondef`, no el `.sql`»— por el mismo tropiezo
-- con `sincronizar_estados_pedidos()`. Esta vez el cuerpo de abajo se extrajo del
-- volcado de producción y se le reaplicaron los tres cambios del hazmat uno a
-- uno, comprobando cada sustitución.
--
-- Y el bloque de comprobación de aquella migración no lo cazó porque **solo
-- afirmaba cosas sobre el texto** (`prosrc LIKE '%…%'`) del guard y del motivo.
-- Ninguna ejercitaba el cierre. El de aquí sí: acepta una oferta de verdad y
-- exige que aparezca la reservación.
-- ============================================================================

-- La firma conserva el valor por omision de `p_via`: el volcado de pg_dump no lo
-- imprime en la linea del CREATE, pero la funcion viva lo tiene, y CREATE OR
-- REPLACE se niega a quitarlo. Verificado con pg_get_function_arguments().
CREATE OR REPLACE FUNCTION public.aceptar_y_cerrar_acuerdo(
  p_oferta_id uuid,
  p_via       text DEFAULT 'cliente_acepta_oferta'
) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_oferta     public.ofertas%ROWTYPE;
  v_pedido     public.pedidos%ROWTYPE;
  v_reserva_id uuid;
  v_docs_venc  boolean := false;
  v_motivo     text;
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
      -- Sin el prefijo tecnico: esto lo lee una persona.
      v_motivo := regexp_replace(SQLERRM, '^DOCUMENTOS_VENCIDOS:\s*', '');
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
      || ', pero ' || COALESCE(v_motivo, 'hay documentos vencidos')
      || '. Revísalo en Pendientes de aprobación.');

    RETURN jsonb_build_object('resultado', 'pendiente_docs',
                              'reserva_id', NULL,
                              'motivo', v_motivo);
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

comment on function public.aceptar_y_cerrar_acuerdo(uuid, text) is
  'Acepta una oferta y cierra el acuerdo en una transaccion. El Paso 2 —marcar el pedido pendiente_acuerdo con su oferta_pendiente_id— NO es opcional: cerrar_acuerdo() tiene una salida temprana que devuelve NULL sin crear nada si el pedido no llega en ese estado. Se perdio en 20260924150000 y estuvo roto en produccion del 2026-09-24T23:06Z al 2026-09-25. Si hay que reescribir este cuerpo, se deriva de pg_get_functiondef, nunca se teclea.';


-- ── Comprobación ───────────────────────────────────────────────────────────
--
-- Lo estático primero, pero **lo que de verdad protege es la parte de
-- comportamiento**: acepta una oferta de verdad y exige que aparezca la
-- reservación. La migración que rompió esto pasó todas sus comprobaciones
-- porque todas eran `prosrc LIKE '%…%'` — afirmaban cosas sobre el TEXTO de la
-- función y ninguna la ejecutaba.
--
-- Todo dentro de una subtransacción que se descarta: no se borra nada.

do $$
declare
  v_cli    uuid;
  v_emp    uuid;
  v_cam    text;
  v_ped    uuid := gen_random_uuid();
  v_of     uuid := gen_random_uuid();
  v_d      date := current_date + 3700;   -- diez años fuera: no roza dato real
  v_res    jsonb;
  v_n      int;
  v_estado text;
begin
  -- ── Estático: el Paso 2 tiene que estar en el cuerpo ───────────────────
  if not exists (
    select 1 from pg_proc
     where proname = 'aceptar_y_cerrar_acuerdo'
       and pronamespace = 'public'::regnamespace
       and prosrc like '%pendiente_acuerdo%oferta_pendiente_id = p_oferta_id%cerrar_acuerdo(p_oferta_id)%'
  ) then
    raise exception 'URGENTE: falta el Paso 2 antes de cerrar_acuerdo(). Sin el, aceptar una oferta NO crea reservacion y la interfaz dice que si.';
  end if;

  -- Debe aparecer DOS veces: una en la rama de documentos vencidos y otra en el
  -- Paso 2. Con una sola, es la de documentos vencidos y el Paso 2 falta.
  select count(*) into v_n
    from regexp_matches(
           (select prosrc from pg_proc where proname = 'aceptar_y_cerrar_acuerdo'
             and pronamespace = 'public'::regnamespace),
           'estado = ''pendiente_acuerdo''', 'g');
  if v_n <> 2 then
    raise exception 'URGENTE: se esperaban 2 asignaciones de pendiente_acuerdo (documentos vencidos + Paso 2), hay %.', v_n;
  end if;

  -- ── Comportamiento: cerrar un acuerdo de verdad ────────────────────────
  select user_id into v_cli from public.perfiles where rol = 'cliente' limit 1;
  select user_id into v_emp from public.perfiles where rol = 'admin'   limit 1;
  select id      into v_cam from public.camiones
   where propietario_id = v_emp and aprobacion = 'aprobada' limit 1;
  if v_cli is null or v_emp is null or v_cam is null then
    raise exception 'URGENTE: falta cliente, empresa o camion aprobado de esa empresa para la prueba. NO se da por buena.';
  end if;

  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_cli)::text, true);
    if auth.uid() is distinct from v_cli then
      perform set_config('request.jwt.claim.sub', v_cli::text, true);
    end if;
    if auth.uid() is distinct from v_cli then
      raise exception 'PASO2-NOSIMULA';
    end if;

    insert into public.pedidos (id, cliente_id, cliente_nombre, cliente_email,
                                tipo_camion, origen, destino, fecha_ini, fecha_fin, estado)
    select v_ped, v_cli, 'PRUEBA PASO2', 'prueba@paso2.local',
           c.tipo, 'A', 'B', v_d, v_d + 2, 'en_negociacion'
      from public.camiones c where c.id = v_cam;

    insert into public.ofertas (id, pedido_id, admin_id, admin_nombre, precio_oferta,
                                camion_id, estado, expira_en)
    values (v_of, v_ped, v_emp, 'PRUEBA PASO2', 1000, v_cam, 'enviada', now() + interval '2 days');

    v_res := public.aceptar_y_cerrar_acuerdo(v_of, 'cliente_acepta_oferta');

    -- Si la empresa tiene papeles vencidos, la RPC desvia a pendiente_docs y
    -- esta prueba no puede demostrar nada. Se dice, no se da por buena.
    if v_res->>'resultado' = 'pendiente_docs' then
      raise exception 'URGENTE: la prueba NO pudo ejercitar el cierre: la empresa % tiene documentos vencidos y la RPC desvio a pendiente_docs (%). Arregla las vigencias o elige otra empresa.',
        v_emp, v_res->>'motivo';
    end if;

    if v_res->>'resultado' <> 'cerrado' then
      raise exception 'URGENTE: la RPC devolvio resultado=% en vez de "cerrado". %', v_res->>'resultado', v_res;
    end if;

    -- Y aqui esta el fallo que se colo: "cerrado" con reserva_id NULL.
    if v_res->>'reserva_id' is null then
      raise exception 'URGENTE: la RPC dice "cerrado" pero reserva_id es NULL. Es EXACTAMENTE el defecto de 20260924150000: cerrar_acuerdo() se fue por la salida temprana.';
    end if;

    select count(*) into v_n from public.reservaciones where pedido_id = v_ped;
    if v_n <> 1 then
      raise exception 'URGENTE: se esperaba 1 reservacion para el pedido, hay %.', v_n;
    end if;

    select estado into v_estado from public.pedidos where id = v_ped;
    if v_estado <> 'acordado' then
      raise exception 'URGENTE: el pedido quedo en "%" en vez de "acordado".', v_estado;
    end if;

    select estado into v_estado from public.ofertas where id = v_of;
    if v_estado <> 'aceptada' then
      raise exception 'URGENTE: la oferta quedo en "%" en vez de "aceptada".', v_estado;
    end if;

    raise exception 'PASO2-DESCARTAR';
  exception
    when others then
      if sqlerrm = 'PASO2-NOSIMULA' then
        raise exception 'URGENTE: no se pudo simular auth.uid() desde psql, asi que el cierre NO se ejercito. No se da por bueno.';
      elsif sqlerrm <> 'PASO2-DESCARTAR' then
        raise;
      end if;
  end;

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  raise notice 'Paso 2 devuelto. Ejercitado de verdad: un cliente acepta una oferta y la RPC crea la reservacion, deja el pedido "acordado" y la oferta "aceptada".';
end $$;
