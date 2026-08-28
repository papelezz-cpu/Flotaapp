-- ============================================================================
-- La publicación de Realtime pasa a estar en el repositorio
-- ============================================================================
--
-- ── Por qué existe esta migración ─────────────────────────────────────────
--
-- La publicación `supabase_realtime` decide qué tablas replica Supabase por
-- WAL para el tiempo real. Hasta hoy se configuró A MANO desde el panel:
-- `grep -rn "ALTER PUBLICATION" supabase/migrations/` no devuelve nada.
--
-- Consecuencia de configurarla fuera del código: derivó sin que nadie pudiera
-- notarlo leyendo el repositorio. Y volcar-esquema.sh pasa --no-publications a
-- pg_dump, así que tampoco aparece en supabase/esquema/01-esquema-public.sql.
-- Era invisible por partida doble.
--
-- Estado medido el 2026-08-28:
--   PRODUCCION: calificaciones, camiones, lavados, mensajes, notificaciones,
--               reservaciones
--   PRUEBAS:    vacía — realtime nunca funcionó ahí para ninguna tabla
--
-- Por eso la migración es DECLARATIVA y no un par de DROP: las dos bases
-- parten de sitios distintos y tienen que acabar en el mismo.
--
-- ── Qué se retira, y qué NO se gana ───────────────────────────────────────
--
--   · mensajes      — ningún cliente la consulta. Verificado en js/, en los
--                     60 .kt de android/ y en supabase/functions/. Último
--                     mensaje: 2026-07-29. Contiene texto de conversaciones
--                     entre clientes y empresas: dejar de replicarlo reduce
--                     superficie sin coste.
--   · calificaciones — publicada sin un solo suscriptor.
--
-- OJO CON LA EXPECTATIVA. Se midió antes de hacerlo: el decodificador acumula
-- 680 007 llamadas contra 2 841 escrituras en las seis tablas publicadas, o
-- sea 239 llamadas por escritura. NO se dispara por cambios: SONDEA por reloj,
-- cada ~17 segundos, haya o no algo que decodificar.
--
-- Esas dos tablas son 111 de esas 2 841 escrituras — el 3,9 % del contenido
-- decodificado, y prácticamente 0 % del coste real, que es el sondeo. El
-- "84 % del tiempo de la base" que se atribuye a Realtime es el coste de
-- TENERLO ENCENDIDO, casi fijo e independiente del número de tablas.
--
-- En absoluto son 28 segundos de CPU al día sobre un total de 34. La base
-- está ociosa. Esto se hace por higiene y por dejar la configuración en el
-- repositorio, NO por rendimiento.
--
-- ── Lo que deliberadamente NO se añade ────────────────────────────────────
--
-- js/main.js se suscribe a `pedidos` y `ofertas`, que no están publicadas: esas
-- dos suscripciones nunca han disparado, y por eso la lista de Solicitudes no
-- se actualiza en vivo. Decidido el 2026-08-28: se queda así.
--
-- Publicarlas hoy sería PEOR que no hacerlo. renderPedidos() ejecuta hasta
-- cuatro UPDATE sobre `pedidos` como efecto secundario de dibujar la lista
-- (js/pedidos.js:239-334). Publicarla haría que cada cambio despertara a todos
-- los navegadores conectados, cada uno escribiría, y cada escritura generaría
-- más eventos. Es un bucle de realimentación.
--
-- Requisito previo para poder publicarlas algún día: sacar la máquina de
-- estados del render (migración 20260810130000_sincronizar_estados_OPCIONAL,
-- sin aplicar).
--
-- `custodios` y `patios` también se suscriben sin estar publicadas. Se dejan
-- fuera por ahora: es una decisión pendiente, no un olvido.
-- ============================================================================

DO $$
DECLARE
  objetivo text[] := ARRAY['camiones', 'lavados', 'notificaciones', 'reservaciones'];
  t        text;
  n_add    integer := 0;
  n_drop   integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE EXCEPTION 'No existe la publicacion supabase_realtime. Revisar antes de continuar.';
  END IF;

  -- Retira lo que sobra respecto al objetivo.
  FOR t IN
    SELECT tablename FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
       AND NOT (tablename = ANY (objetivo))
  LOOP
    EXECUTE format('ALTER PUBLICATION supabase_realtime DROP TABLE public.%I', t);
    RAISE NOTICE 'Retirada de la publicacion: %', t;
    n_drop := n_drop + 1;
  END LOOP;

  -- Añade lo que falta. En pruebas la publicacion esta vacia, asi que aqui es
  -- donde converge con produccion.
  FOREACH t IN ARRAY objetivo LOOP
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t);
    CONTINUE WHEN NOT EXISTS (
      SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = t);
    EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    RAISE NOTICE 'Anadida a la publicacion: %', t;
    n_add := n_add + 1;
  END LOOP;

  RAISE NOTICE 'Publicacion alineada: % anadidas, % retiradas.', n_add, n_drop;
END $$;


-- ─────────────────────────────────────────────────────────────────────────
-- Comprobación
-- ─────────────────────────────────────────────────────────────────────────
DO $$
DECLARE actual text; esperado text := 'camiones, lavados, notificaciones, reservaciones';
BEGIN
  SELECT coalesce(string_agg(tablename, ', ' ORDER BY tablename), '(vacia)')
    INTO actual
    FROM pg_publication_tables
   WHERE pubname = 'supabase_realtime' AND schemaname = 'public';

  IF actual IS DISTINCT FROM esperado THEN
    RAISE EXCEPTION 'La publicacion quedo como "%" y se esperaba "%"', actual, esperado;
  END IF;
  RAISE NOTICE 'Verificado: la publicacion contiene exactamente %', actual;
END $$;
