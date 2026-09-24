-- ============================================================================
-- MARCHA ATRÁS de la Etapa 5 de H-04 — NO se aplica en el camino normal
-- ============================================================================
--
-- Devuelve `guard_oferta_update` a leer las tres columnas de `perfiles`, o sea
-- al estado exacto en que estaba producción antes del 2026-09-24.
--
-- ── Por qué existe este fichero ───────────────────────────────────────────
--
-- Porque no había ninguno. La definición VIVA de producción no la produce
-- ninguna migración del repositorio: 20260817150000 la dejó sin el retorno
-- temprano por orfandad, que añadió después 20260827190000 con un
-- `CREATE OR REPLACE` que no quedó guardado como cuerpo completo. Resultado:
-- para revertir la Etapa 5 había que reconstruir la función leyendo
-- `pg_get_functiondef` del volcado, a mano y bajo presión.
--
-- El cuerpo de abajo ES ese volcado, copiado literal antes de tocar nada.
--
-- ── Cuándo aplicarlo ──────────────────────────────────────────────────────
--
-- Si tras promover la Etapa 5 el guard se comporta distinto de lo esperado.
-- Los dos modos de fallo, por orden de gravedad:
--
--   · **Falla abierto** (el grave, y silencioso): deja cerrar tratos a empresas
--     con papeles vencidos. Se vería como un acuerdo que no debió cerrarse, no
--     como un error. Si se sospecha esto, revertir primero y averiguar después.
--   · **Falla cerrado**: bloquea a empresas que están al día. Se ve al momento
--     y el superadmin puede forzar el acuerdo mientras se resuelve, así que
--     corre menos prisa.
--
-- Revertir NO retira la tabla `vigencias` ni las vistas: solo devuelve este
-- guard a su fuente anterior. El resto de H-04 sigue en pie, y la doble
-- escritura mantiene las dos fuentes sincronizadas, así que el veredicto sería
-- el mismo por los dos caminos.
--
-- Uso:
--   bash supabase/aplicar-a-produccion.sh \
--     supabase/migrations/20260924130000_REVERTIR_etapa5_guard_oferta.sql
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
$function$;


do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc where proname = 'guard_oferta_update';
  if v_src not like '%fecha_vencimiento_permiso_sct%' then
    raise exception 'REVERSION: el guard no volvio a leer las columnas de perfiles.';
  end if;
  if v_src not like '%orfandad por borrado de cuenta%' then
    raise exception 'REVERSION: se perdio el retorno por orfandad.';
  end if;
  raise notice 'REVERSION aplicada: guard_oferta_update vuelve a leer perfiles. El resto de H-04 sigue en pie.';
end $$;
