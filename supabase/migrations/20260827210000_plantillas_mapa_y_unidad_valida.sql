-- ============================================================================
-- Dos pendientes de la auditoria: el mapa en plantillas y la unidad polimorfica
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. plantillas_pedido recupera el punto del mapa
-- ─────────────────────────────────────────────────────────────────────────
-- plantillas_pedido es una copia columna a columna de pedidos: 45 de sus 48
-- columnas son identicas. Esa duplicacion tiene un costo, y ya se materializo:
-- pedidos gano origen_lat/lng y destino_lat/lng para el selector de mapa, y
-- plantillas_pedido no. Resultado: una plantilla NO puede guardar el punto del
-- mapa, aunque el pedido del que sale si lo tenga.
--
-- Las fechas se omiten a proposito y esta documentado. Las coordenadas no:
-- es deriva, no diseño.
ALTER TABLE public.plantillas_pedido
  ADD COLUMN IF NOT EXISTS origen_lat   numeric,
  ADD COLUMN IF NOT EXISTS origen_lng   numeric,
  ADD COLUMN IF NOT EXISTS destino_lat  numeric,
  ADD COLUMN IF NOT EXISTS destino_lng  numeric;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. reservaciones.unidad tiene que existir de verdad
-- ─────────────────────────────────────────────────────────────────────────
-- `unidad` guarda el id de un camion, custodio, patio o lavado segun
-- recurso_tipo. Al ser polimorfica NO admite clave foranea, asi que nada
-- impedia apuntar a un recurso inexistente. Y ya paso: la reservacion
-- 5e261f66 apunta a F-303, un camion borrado. Es una reservacion completada
-- que ya no puede decir que unidad hizo el viaje.
--
-- Un trigger es lo unico que cabe aqui. Se valida SOLO cuando unidad o
-- recurso_tipo cambian, por dos razones:
--   · no encarece los UPDATE que no los tocan (avanzar tracking, marcar
--     pagado, subir evidencia), que son la mayoria;
--   · no rompe las filas historicas que ya estan mal, como F-303. Esa se
--     queda como esta: corregirla exigiria inventar un camion que no existe
--     o perder el dato de que fue F-303, y ninguna de las dos ayuda.
CREATE OR REPLACE FUNCTION public.guard_unidad_existe() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
  v_tabla text;
  v_hay   boolean;
BEGIN
  IF NEW.unidad IS NULL THEN
    RETURN NEW;
  END IF;

  -- Solo cuando cambia la referencia. En INSERT, OLD es NULL y siempre entra.
  IF TG_OP = 'UPDATE'
     AND NEW.unidad IS NOT DISTINCT FROM OLD.unidad
     AND NEW.recurso_tipo IS NOT DISTINCT FROM OLD.recurso_tipo THEN
    RETURN NEW;
  END IF;

  v_tabla := CASE COALESCE(NEW.recurso_tipo, 'camion')
               WHEN 'camion'   THEN 'camiones'
               WHEN 'custodio' THEN 'custodios'
               WHEN 'patio'    THEN 'patios'
               WHEN 'lavado'   THEN 'lavados'
             END;

  IF v_tabla IS NULL THEN
    RAISE EXCEPTION 'recurso_tipo invalido: %', NEW.recurso_tipo;
  END IF;

  EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE id = $1)', v_tabla)
     INTO v_hay USING NEW.unidad;

  IF NOT v_hay THEN
    RAISE EXCEPTION 'La unidad % no existe en %', NEW.unidad, v_tabla;
  END IF;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION public.guard_unidad_existe() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_guard_unidad_existe ON public.reservaciones;
CREATE TRIGGER trg_guard_unidad_existe
  BEFORE INSERT OR UPDATE ON public.reservaciones
  FOR EACH ROW EXECUTE FUNCTION public.guard_unidad_existe();


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
DO $$
DECLARE faltan integer; huerfanas integer;
BEGIN
  SELECT count(*) INTO faltan FROM information_schema.columns
   WHERE table_schema='public' AND table_name='plantillas_pedido'
     AND column_name IN ('origen_lat','origen_lng','destino_lat','destino_lng');
  IF faltan <> 4 THEN
    RAISE EXCEPTION 'plantillas_pedido quedo con % de 4 columnas de mapa', faltan;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_guard_unidad_existe'
                   AND tgrelid='public.reservaciones'::regclass) THEN
    RAISE EXCEPTION 'El trigger de validacion de unidad no quedo instalado';
  END IF;

  SELECT count(*) INTO huerfanas FROM reservaciones r
   WHERE r.unidad IS NOT NULL AND NOT EXISTS (
     SELECT 1 FROM camiones WHERE id=r.unidad UNION ALL SELECT 1 FROM custodios WHERE id=r.unidad
     UNION ALL SELECT 1 FROM patios WHERE id=r.unidad UNION ALL SELECT 1 FROM lavados WHERE id=r.unidad);

  RAISE NOTICE 'Verificado. Reservaciones historicas con unidad inexistente: % (se conservan a proposito)', huerfanas;
END $$;
