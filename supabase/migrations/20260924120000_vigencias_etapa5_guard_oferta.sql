-- ============================================================================
-- H-04 · Etapa 5 — El guard que frena el trato lee `vigencias`
-- ============================================================================
--
-- ── Qué cambia, y qué NO ──────────────────────────────────────────────────
--
-- `guard_oferta_update` bloquea aceptar una oferta si la empresa que la emitió
-- tiene vencido el permiso SCT, el seguro RC o el seguro de carga. Ese bloqueo
-- deja de leer las tres columnas de `perfiles` y pasa a leer `vigencias`.
--
-- **Todo lo demás de la función se conserva palabra por palabra**, y eso no es
-- retórica: el cuerpo se copió de la definición VIVA (`pg_get_functiondef`
-- sobre el volcado de producción), no de la última migración que la tocaba. No
-- coincidían. La viva tiene un retorno temprano por orfandad que añadió
-- 20260827190000_desbloquea_el_borrado_de_cuenta.sql, y una migración escrita
-- desde el fichero anterior lo habría borrado sin que nada fallara: el borrado
-- de cuenta volvería a quedar bloqueado.
--
-- Lo que se conserva, y el bloque de comprobación de abajo lo exige:
--   · el retorno temprano por orfandad (cuenta borrada, oferta sin titular),
--   · la salida por `is_superadmin()`,
--   · quién puede aceptar qué (la empresa solo respondiendo una contraoferta;
--     el cliente solo su propio pedido y solo una oferta `enviada`),
--   · **el texto exacto del error**. La RPC `aceptar_y_cerrar_acuerdo` hace
--     `IF SQLERRM LIKE 'DOCUMENTOS_VENCIDOS%'` (20260903120000) para mandar el
--     pedido a `pendiente_acuerdo` en vez de reventar. Cambiar una letra de ese
--     mensaje convierte un aviso manejado en un error crudo en pantalla.
--
-- ── Por qué SECURITY DEFINER es imprescindible aquí ──────────────────────
--
-- Quien acepta la oferta es normalmente **el cliente**, y un cliente no tiene
-- permiso de RLS para leer los documentos de la empresa: la política
-- `vigencias_lee_dueno_o_sa` solo deja al dueño y al superadmin. Si esta
-- función no fuera SECURITY DEFINER, el `EXISTS` no vería ninguna fila y el
-- guard **dejaría pasar todo** — fallaría abierto, en silencio, y solo se
-- notaría el día que alguien cerrara un trato con papeles vencidos.
--
-- Ya era SECURITY DEFINER; se deja constancia porque el motivo cambia con esta
-- etapa. Antes leía `perfiles`, que cualquier autenticado puede leer; ahora lee
-- una tabla con RLS restrictiva.
--
-- ── Y una regla que ahora sale del catálogo ───────────────────────────────
--
-- La caducidad se calcula con `vigencia_vence_el()`. Para estos tres tipos el
-- catálogo no define `vigencia_meses`, así que devuelve la fecha capturada tal
-- cual y el resultado es idéntico al de antes. Se usa la función igualmente:
-- el día que un seguro se capture por fecha de emisión con vigencia de N meses,
-- este guard se enterará sin que haya que tocarlo.
--
-- `fecha_documento` nulo (papel subido sin fecha) da `vence_el` nulo, y
-- `null < current_date` no es verdadero: no bloquea. Es la misma semántica que
-- el `IS NOT NULL AND <` de antes, y sigue siendo el hueco conocido de los 14
-- documentos que nadie vigila.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.guard_oferta_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  es_cliente_pedido boolean;
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


-- ── Comprobación ───────────────────────────────────────────────────────────

do $$
declare
  v_src       text;
  v_divergen  int;
  v_n         int;
begin
  select prosrc into v_src from pg_proc where proname = 'guard_oferta_update';

  -- 1. Ya no lee las columnas viejas.
  if v_src like '%fecha_vencimiento_permiso_sct%'
  or v_src like '%fecha_vencimiento_seguro_rc%'
  or v_src like '%fecha_vencimiento_seguro_carga%' then
    raise exception 'H-04 etapa 5: el guard sigue leyendo las columnas de perfiles.';
  end if;

  -- 2. Lee la tabla nueva.
  if v_src not like '%public.vigencias%' then
    raise exception 'H-04 etapa 5: el guard no lee public.vigencias.';
  end if;

  -- 3. Lo que NO debía perderse. Estas tres son las que una migración escrita
  --    desde el fichero viejo habría borrado sin avisar.
  if v_src not like '%orfandad por borrado de cuenta%' then
    raise exception 'H-04 etapa 5: se perdio el retorno temprano por orfandad. El borrado de cuenta volveria a bloquearse (20260827190000).';
  end if;
  if v_src not like '%is_superadmin()%' then
    raise exception 'H-04 etapa 5: se perdio la salida por is_superadmin. El superadmin no podria forzar un acuerdo.';
  end if;
  if v_src not like '%solo puedes aceptar tu propia oferta al responder una contraoferta%'
  or v_src not like '%solo puedes aceptar una oferta en estado enviada%' then
    raise exception 'H-04 etapa 5: se perdio alguna regla de quien puede aceptar que.';
  end if;

  -- 4. El texto del error, intacto: la RPC aceptar_y_cerrar_acuerdo lo captura
  --    por prefijo para mandar el pedido a pendiente_acuerdo.
  if v_src not like '%DOCUMENTOS_VENCIDOS: la empresa tiene documentos vencidos (permiso SCT, seguro RC o seguro de carga)%' then
    raise exception 'H-04 etapa 5: cambio el texto de DOCUMENTOS_VENCIDOS. La RPC que lo captura dejaria de reconocerlo.';
  end if;

  -- 5. El trigger sigue colgado de ofertas.
  select count(*) into v_n from pg_trigger
   where tgrelid = 'public.ofertas'::regclass
     and not tgisinternal
     and tgfoid = 'public.guard_oferta_update()'::regprocedure;
  if v_n < 1 then
    raise exception 'H-04 etapa 5: guard_oferta_update ya no esta colgado de ofertas.';
  end if;

  -- 6. Y la red de seguridad del corte: la condición nueva tiene que bloquear
  --    exactamente a las mismas empresas que la vieja. Si no, esta migración
  --    cambiaría quién puede cerrar un trato, que no es lo que viene a hacer.
  select count(*) into v_divergen
    from public.perfiles p
   where p.rol = 'admin'
     and ( ( (p.fecha_vencimiento_permiso_sct  is not null and p.fecha_vencimiento_permiso_sct  < current_date)
          or (p.fecha_vencimiento_seguro_rc    is not null and p.fecha_vencimiento_seguro_rc    < current_date)
          or (p.fecha_vencimiento_seguro_carga is not null and p.fecha_vencimiento_seguro_carga < current_date) )
           is distinct from
           exists ( select 1 from public.vigencias v
                     where v.entidad_tipo   = 'perfil'
                       and v.entidad_id     = p.user_id::text
                       and v.estado         = 'vigente'
                       and v.tipo_documento in ('permiso_sct','seguro_rc','seguro_carga')
                       and public.vigencia_vence_el(v.tipo_documento, v.fecha_documento) < current_date ) );
  if v_divergen > 0 then
    raise exception 'H-04 etapa 5: en % empresa(s) el guard nuevo decidiria distinto que el viejo. Correr 14-sonda-espejo-vigencias.mjs antes de reintentar.', v_divergen;
  end if;

  raise notice 'H-04 etapa 5: el guard lee vigencias. % empresas comprobadas, ninguna cambia de veredicto.',
    (select count(*) from public.perfiles where rol = 'admin');
end $$;
