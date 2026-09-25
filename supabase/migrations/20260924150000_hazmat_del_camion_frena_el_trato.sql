-- ============================================================================
-- ⚠⚠⚠ ESTA MIGRACIÓN SALIÓ CON UN DEFECTO. NO LA REAPLIQUES SOLA. ⚠⚠⚠
--
-- Al reescribir el cuerpo de `aceptar_y_cerrar_acuerdo()` se perdió el bloque
-- «Paso 2» —el `UPDATE pedidos SET estado='pendiente_acuerdo', oferta_pendiente_id`
-- que va justo antes de `cerrar_acuerdo()`—. Sin él, `cerrar_acuerdo()` se va por
-- su salida temprana y **no crea la reservación, sin dar error**: la RPC devuelve
-- `{resultado:'cerrado', reserva_id:null}` y la interfaz dice que todo fue bien.
--
-- Roto en producción del 2026-09-24T23:06Z al 2026-09-25. Lo arregla
-- `20260925140000_URGENTE_devuelve_el_paso2_del_cierre.sql`, que hay que aplicar
-- **siempre después** de esta si esta se vuelve a correr.
--
-- La regla del permiso de materiales peligrosos que añade sí es correcta; lo que
-- falló fue teclear el cuerpo en vez de derivarlo de `pg_get_functiondef`.
-- ============================================================================
-- El permiso hazmat del CAMIÓN frena el trato  (hueco 12 de FLUJO-OPERATIVO.md)
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- `admin.js:902` exige el permiso de materiales peligrosos al dar de alta una
-- unidad marcada para carga peligrosa. Se guarda, el espejo de H-04 lo refleja
-- a `vigencias` como `permiso_peligrosa`… **y ahí muere.** Medido el 2026-09-24
-- con grep: todas las apariciones en el cliente son de escritura. No lo lista
-- el panel de Vigencias, no lo mira el aviso de «esta unidad tiene documentos
-- vencidos» al ofertar, y no lo consulta ningún guard.
--
-- El contraste es lo que lo hacía grave: para carga peligrosa el sistema **sí**
-- exige que el chofer tenga licencia HAZMAT vigente —filtra el desplegable y lo
-- vuelve a comprobar al enviar la oferta— pero **no** miraba si el camión tenía
-- su permiso en regla. Se pedía el papel al alta y después se ignoraba.
--
-- ── La decisión ───────────────────────────────────────────────────────────
--
-- **Del usuario, 2026-09-24: «se debe frenar el trato».** No un aviso: el mismo
-- trato que los documentos de la empresa.
--
-- Y por eso esta migración **reutiliza el prefijo `DOCUMENTOS_VENCIDOS`** en vez
-- de inventar un código nuevo: la tubería que lo maneja ya existe y funciona.
-- `aceptar_y_cerrar_acuerdo` lo captura, aparca el pedido en
-- `pendiente_acuerdo`, avisa a los superadmins, y el superadmin puede forzarlo
-- —sale por el `is_superadmin()` del principio del guard—. Eso es «avisa pero no
-- encierra», que es lo que ya se decidió para la empresa y lo que evita que una
-- unidad con un papel caducado deje a nadie atrapado.
--
-- ── Un permiso que NO EXISTE bloquea igual que uno vencido ────────────────
--
-- Es más estricto que la regla de la empresa (donde un documento sin fecha no
-- bloquea, el hueco 6), y es deliberado. Medido en pruebas el 2026-09-24: de 13
-- camiones, **3 están marcados para carga peligrosa** y solo uno no tiene
-- permiso —`C-001`, que además tiene los otros cinco documentos vencidos desde
-- agosto—. Ese camión no debería estar moviendo carga peligrosa de ninguna
-- manera, y el alta ya exige el permiso desde antes, así que la regla solo
-- alcanza a unidades heredadas.
--
-- ── Solo se aplica si el recurso ofertado ES un camión ────────────────────
--
-- `ofertas.camion_id` guarda el id del recurso, que puede ser un custodio, un
-- patio o un lavado. Sin el `EXISTS` contra `camiones`, «no tiene permiso» sería
-- cierto para todos ellos y un pedido de carga peligrosa con custodia quedaría
-- bloqueado sin motivo.
--
-- ── Marcha atrás ──────────────────────────────────────────────────────────
--
-- No hace falta un fichero nuevo: reaplicar
-- `20260924120000_vigencias_etapa5_guard_oferta.sql` devuelve el guard al estado
-- anterior a esta migración, y `20260903120000_rpc_aceptar_y_cerrar_acuerdo.sql`
-- hace lo propio con la RPC.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────
-- 1 · El guard
-- ─────────────────────────────────────────────────────────────────────────
-- Cuerpo copiado de la Etapa 5 (que es lo que hay vivo en producción) más el
-- bloque nuevo. Todo lo demás queda palabra por palabra: el retorno temprano
-- por orfandad, la salida del superadmin, y quién puede aceptar qué.

CREATE OR REPLACE FUNCTION public.guard_oferta_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  es_cliente_pedido boolean;
  v_hazmat          boolean;
BEGIN
  -- orfandad por borrado de cuenta: el titular anterior ya no existe
  IF NEW.admin_id IS NULL AND OLD.admin_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.perfiles WHERE user_id = OLD.admin_id) THEN
    RETURN NEW;
  END IF;

  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado = 'aceptada' THEN
    -- H-04 etapa 5: los documentos acreditados de la empresa se leen de
    -- `vigencias`, en estado 'vigente'. Una propuesta pendiente de revisión no
    -- desbloquea nada, que es justo lo que H-02 quería garantizar.
    IF EXISTS (
      SELECT 1 FROM public.vigencias v
      WHERE v.entidad_tipo   = 'perfil'
        AND v.entidad_id     = OLD.admin_id::text
        AND v.estado         = 'vigente'
        AND v.tipo_documento IN ('permiso_sct', 'seguro_rc', 'seguro_carga')
        AND public.vigencia_vence_el(v.tipo_documento, v.fecha_documento) < current_date
    ) THEN
      RAISE EXCEPTION 'DOCUMENTOS_VENCIDOS: la empresa tiene documentos vencidos (permiso SCT, seguro RC o seguro de carga)';
    END IF;

    -- Carga peligrosa: el permiso del CAMIÓN. Aquí un permiso que no existe
    -- bloquea igual que uno vencido (ver cabecera), y solo se comprueba si el
    -- recurso ofertado es de verdad un camión.
    SELECT p.carga_peligrosa INTO v_hazmat
      FROM public.pedidos p WHERE p.id = OLD.pedido_id;

    IF coalesce(v_hazmat, false)
       AND OLD.camion_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.camiones c WHERE c.id = OLD.camion_id)
       AND NOT EXISTS (
         SELECT 1 FROM public.vigencias v
          WHERE v.entidad_tipo   = 'camion'
            AND v.entidad_id     = OLD.camion_id
            AND v.estado         = 'vigente'
            AND v.tipo_documento = 'permiso_peligrosa'
            AND public.vigencia_vence_el('permiso_peligrosa', v.fecha_documento) >= current_date
       ) THEN
      RAISE EXCEPTION 'DOCUMENTOS_VENCIDOS: la unidad % no tiene permiso de materiales peligrosos vigente, y este pedido es de carga peligrosa', OLD.camion_id;
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


-- ─────────────────────────────────────────────────────────────────────────
-- 2 · La RPC dice POR QUÉ quedó pendiente
-- ─────────────────────────────────────────────────────────────────────────
-- Antes el aviso al superadmin decía «pero la empresa tiene documentos
-- vencidos», fijo. Con la regla del camión eso sería mentira la mitad de las
-- veces, y mandaría al superadmin a revisar los papeles equivocados. Ahora
-- lleva el motivo que trae el guard, sin el prefijo técnico.
--
-- Solo cambian tres cosas de esta función: se declara `v_motivo`, se captura en
-- el EXCEPTION, y se usa en el aviso y en el jsonb de vuelta. El resto es
-- idéntico a 20260903120000.

CREATE OR REPLACE FUNCTION public.aceptar_y_cerrar_acuerdo(
  p_oferta_id uuid,
  p_via       text DEFAULT 'cliente_acepta_oferta'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
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

  SELECT * INTO v_oferta FROM public.ofertas WHERE id = p_oferta_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La oferta ya no existe.';
  END IF;

  SELECT * INTO v_pedido FROM public.pedidos WHERE id = v_oferta.pedido_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El pedido ya no existe.';
  END IF;

  IF NOT public.is_superadmin()
     AND auth.uid() NOT IN (v_pedido.cliente_id, v_oferta.admin_id) THEN
    RAISE EXCEPTION 'No autorizado: no eres parte de este acuerdo.';
  END IF;

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
      -- Sin el prefijo técnico: esto lo lee una persona.
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

  v_reserva_id := public.cerrar_acuerdo(p_oferta_id);
  RETURN jsonb_build_object('resultado', 'cerrado', 'reserva_id', v_reserva_id);
END;
$function$;

revoke all on function public.aceptar_y_cerrar_acuerdo(uuid, text) from public, anon;
grant execute on function public.aceptar_y_cerrar_acuerdo(uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 3 · Comprobación
-- ─────────────────────────────────────────────────────────────────────────

do $$
declare v_src text; v_n int;
begin
  select prosrc into v_src from pg_proc where proname = 'guard_oferta_update';

  -- La regla nueva está.
  if v_src not like '%permiso_peligrosa%' then
    raise exception 'El guard no comprueba el permiso de materiales peligrosos.';
  end if;
  if v_src not like '%carga_peligrosa%' then
    raise exception 'El guard no mira si el pedido es de carga peligrosa: bloquearia todos.';
  end if;
  -- Y solo se aplica a camiones.
  if v_src not like '%FROM public.camiones c WHERE c.id = OLD.camion_id%' then
    raise exception 'Falta el EXISTS contra camiones: un pedido de carga peligrosa con custodio o patio quedaria bloqueado sin motivo.';
  end if;

  -- Lo que NO debía perderse, otra vez (ver 20260924120000: la definicion viva
  -- no coincidia con ninguna migracion y por poco se borra este retorno).
  if v_src not like '%orfandad por borrado de cuenta%' then
    raise exception 'Se perdio el retorno temprano por orfandad (20260827190000).';
  end if;
  if v_src not like '%is_superadmin()%' then
    raise exception 'Se perdio la salida del superadmin: nadie podria forzar un acuerdo y una unidad con el papel caducado dejaria a las dos partes atrapadas.';
  end if;
  if v_src not like '%la empresa tiene documentos vencidos (permiso SCT, seguro RC o seguro de carga)%' then
    raise exception 'Se perdio la regla de los documentos de empresa (etapa 5).';
  end if;
  if v_src not like '%solo puedes aceptar una oferta en estado enviada%' then
    raise exception 'Se perdio alguna regla de quien puede aceptar que.';
  end if;

  -- Los dos mensajes conservan el prefijo, que es lo que la RPC captura.
  select count(*) into v_n from regexp_matches(v_src, 'DOCUMENTOS_VENCIDOS:', 'g');
  if v_n <> 2 then
    raise exception 'Se esperaban 2 mensajes con prefijo DOCUMENTOS_VENCIDOS (empresa y unidad), hay %.', v_n;
  end if;

  -- Y la RPC ya no dice «la empresa» a secas.
  select prosrc into v_src from pg_proc where proname = 'aceptar_y_cerrar_acuerdo';
  if v_src like '%pero la empresa tiene documentos vencidos%' then
    raise exception 'La RPC sigue diciendo "la empresa" fijo; con la regla del camion eso mandaria al superadmin a revisar los papeles equivocados.';
  end if;
  if v_src not like '%v_motivo%' then
    raise exception 'La RPC no lleva el motivo: el superadmin no sabria que mirar.';
  end if;

  raise notice 'El permiso hazmat del camion frena el trato. El superadmin conserva la salida y ahora el aviso dice por que.';
end $$;
