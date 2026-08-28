-- ============================================================================
-- Realtime: los borrados vuelven a llegar, y la flota se comporta igual
-- ============================================================================
--
-- ── 1. El defecto, comprobado con un cliente conectado ────────────────────
--
-- Las cuatro tablas publicadas estaban en REPLICA IDENTITY DEFAULT, que en la
-- replicacion logica de Postgres significa que de la fila ANTERIOR solo viaja
-- la clave primaria.
--
-- Eso choca de frente con los filtros que usa js/main.js:
--
--     reservaciones  ->  filter: propietario_id=eq.<uid>
--     camiones       ->  filter: propietario_id=eq.<uid>
--     notificaciones ->  filter: user_id=eq.<uid>
--
-- En un DELETE, Realtime solo recibe el id. No puede evaluar el filtro sobre
-- propietario_id ni user_id porque esas columnas no estan en el WAL, asi que
-- descarta el evento.
--
-- Verificado el 2026-08-28 contra portgo-pruebas con un WebSocket real,
-- suscrito con el mismo filtro que la aplicacion:
--
--     >> INSERT de una notificacion   ->  << INSERT recibido (old vacio)
--     >> DELETE de esa misma fila     ->  (nada)
--     RESULTADO: INSERT=1  DELETE=0
--
-- Consecuencia en la aplicacion: la app borra filas de tres de las cuatro
-- tablas publicadas —js/admin.js:818 (camion), js/admin.js:1519 (lavado) y
-- js/reservaciones.js:673 (el archivado de una reservacion)— y ninguna pantalla
-- abierta se entera. Se quedan mostrando algo que ya no existe hasta que
-- alguien recargue.
--
-- ── Lo que cuesta ─────────────────────────────────────────────────────────
--
-- Con FULL, cada UPDATE escribe en el WAL la fila anterior COMPLETA ademas de
-- la nueva. En `reservaciones`, que tiene 50 columnas, no es gratis. Pero
-- medido: 202 updates en cuatro meses sobre 20 filas. A este volumen es
-- irrelevante, y sin ello los filtros no funcionan en borrados.
--
-- Si alguna de estas tablas llegara a tener escritura intensa, la alternativa
-- es REPLICA IDENTITY USING INDEX sobre un indice que incluya la columna del
-- filtro: mas barato que FULL y suficiente para el caso. Hoy no hace falta.
--
-- ── 2. custodios y patios ─────────────────────────────────────────────────
--
-- js/main.js se suscribe a las cuatro tablas de flota, pero solo camiones y
-- lavados estaban publicadas. De cuatro tipos de recurso, dos se actualizaban
-- en vivo y dos no, sin que nadie lo hubiera decidido: quedaron fuera al
-- configurar la publicacion a mano en el panel.
--
-- Son tablas de 6 y 5 filas, con 1 y 0 escrituras al mes. El coste de
-- publicarlas es nulo y deja los cuatro tipos comportandose igual.
--
-- `pedidos` y `ofertas` siguen fuera a proposito: ver la migracion
-- 20260828120000. Requieren antes sacar la maquina de estados del render.
-- ============================================================================

DO $$
DECLARE
  objetivo text[] := ARRAY['camiones', 'custodios', 'lavados',
                           'notificaciones', 'patios', 'reservaciones'];
  t text;
BEGIN
  -- Publicacion: converge al objetivo desde donde este cada base.
  FOR t IN
    SELECT tablename FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
       AND NOT (tablename = ANY (objetivo))
  LOOP
    EXECUTE format('ALTER PUBLICATION supabase_realtime DROP TABLE public.%I', t);
    RAISE NOTICE 'Retirada de la publicacion: %', t;
  END LOOP;

  FOREACH t IN ARRAY objetivo LOOP
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename=t);

    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                    WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename=t) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
      RAISE NOTICE 'Anadida a la publicacion: %', t;
    END IF;

    -- REPLICA IDENTITY FULL. Sin esto los filtros de la suscripcion no pueden
    -- evaluarse en DELETE y el evento se pierde.
    IF (SELECT c.relreplident FROM pg_class c
         WHERE c.relnamespace='public'::regnamespace AND c.relname=t) <> 'f' THEN
      EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);
      RAISE NOTICE 'REPLICA IDENTITY FULL en: %', t;
    END IF;
  END LOOP;
END $$;


-- ─────────────────────────────────────────────────────────────────────────
-- Comprobación
-- ─────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_pub  text;
  v_sinf integer;
BEGIN
  SELECT string_agg(tablename, ', ' ORDER BY tablename) INTO v_pub
    FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public';

  IF v_pub IS DISTINCT FROM 'camiones, custodios, lavados, notificaciones, patios, reservaciones' THEN
    RAISE EXCEPTION 'La publicacion quedo como "%"', v_pub;
  END IF;

  SELECT count(*) INTO v_sinf
    FROM pg_class c
   WHERE c.relnamespace='public'::regnamespace AND c.relreplident <> 'f'
     AND c.relname IN (SELECT tablename FROM pg_publication_tables
                        WHERE pubname='supabase_realtime' AND schemaname='public');

  IF v_sinf > 0 THEN
    RAISE EXCEPTION '% tabla(s) publicadas siguen sin REPLICA IDENTITY FULL', v_sinf;
  END IF;

  RAISE NOTICE 'Verificado: 6 tablas publicadas, todas con REPLICA IDENTITY FULL.';
END $$;
