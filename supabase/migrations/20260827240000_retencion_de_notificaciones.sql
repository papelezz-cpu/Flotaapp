-- ============================================================================
-- Retencion de notificaciones: se purgan las LEIDAS de mas de 180 dias
-- ============================================================================
--
-- ⚠ ESTA MIGRACION PROGRAMA UN BORRADO RECURRENTE. Autorizada expresamente
--   el 2026-08-27. Lo que borra, y solo eso:
--
--     filas de public.notificaciones  con leido = true
--                                     y created_at anterior a 180 dias
--
--   Nunca toca una notificacion sin leer, por antigua que sea.
--
-- ── Por que, y por que NO por rendimiento ─────────────────────────────────
--
-- La auditoria marco esta tabla como de crecimiento sin techo, y lo es. Pero
-- eso era grave cuando no tenia ni un indice. Con idx_notificaciones_user_fecha
-- la campanita pide 20 filas por indice y para: da igual que la tabla tenga
-- mil o dos millones. Purgar NO hace la aplicacion mas rapida.
--
-- Las razones reales son otras dos:
--
--   · Almacenamiento. Medido: 866 filas en 128 dias con 12 usuarios, es decir
--     0.56 por usuario y dia. A 10.000 usuarios son ~2 millones de filas al
--     año, alrededor de 1 GB, de los que el 96% ya estan leidos.
--
--   · Proteccion de datos, que pesa mas. Los titulos y mensajes llevan nombres
--     de clientes y empresas, unidades y montos. La LFPDPPP pide tratar datos
--     personales solo mientras exista una finalidad, y un aviso leido hace dos
--     años no la tiene. Ademas engorda cualquier solicitud ARCO de acceso.
--
-- ── Por que 180 dias ──────────────────────────────────────────────────────
-- La notificacion mas antigua en produccion tiene 130 dias, asi que HOY esta
-- tarea borra CERO filas. Entra en vigor sin tocar nada y empieza a actuar
-- cuando de verdad haga falta. Eso da margen para cambiar de opinion antes de
-- que borre su primera fila.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. La funcion
-- ─────────────────────────────────────────────────────────────────────────
-- Devuelve cuantas borro, para poder llamarla a mano y ver el efecto.
--
-- El tope por ejecucion no es decorativo: si esto llegara a correr por primera
-- vez sobre una tabla de millones de filas, un DELETE sin limite tomaria
-- bloqueos durante minutos y haria crecer el WAL de golpe. Con el tope, cada
-- pasada es acotada y la siguiente sigue donde quedo.
CREATE OR REPLACE FUNCTION public.purgar_notificaciones_leidas(
  p_dias  integer DEFAULT 180,
  p_tope  integer DEFAULT 50000
) RETURNS integer
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
DECLARE
  v_borradas integer;
BEGIN
  IF p_dias < 30 THEN
    RAISE EXCEPTION 'Retencion demasiado corta (% dias). El minimo son 30.', p_dias;
  END IF;

  WITH candidatas AS (
    SELECT id FROM public.notificaciones
     WHERE leido = true
       AND created_at < now() - make_interval(days => p_dias)
     ORDER BY created_at
     LIMIT p_tope
  )
  DELETE FROM public.notificaciones n
   USING candidatas c
   WHERE n.id = c.id;

  GET DIAGNOSTICS v_borradas = ROW_COUNT;
  RETURN v_borradas;
END;
$fn$;

-- Nadie la llama desde la aplicacion: solo el planificador. Sin este REVOKE
-- nace ejecutable por anon, por el ALTER DEFAULT PRIVILEGES de Supabase.
REVOKE ALL ON FUNCTION public.purgar_notificaciones_leidas(integer, integer)
  FROM PUBLIC, anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. La tarea mensual
-- ─────────────────────────────────────────────────────────────────────────
-- Dia 1 de cada mes a las 03:00 UTC. Mensual y no diaria a proposito: el
-- volumen no lo justifica y una tarea que corre poco es una que se revisa
-- cuando falla, en vez de pasar inadvertida.
DO $$
BEGIN
  PERFORM cron.unschedule('purgar-notificaciones')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purgar-notificaciones');

  PERFORM cron.schedule(
    'purgar-notificaciones',
    '0 3 1 * *',
    'SELECT public.purgar_notificaciones_leidas()'
  );
  RAISE NOTICE 'Tarea programada: dia 1 de cada mes a las 03:00 UTC.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_afectaria integer;
  v_sin_leer  integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purgar-notificaciones') THEN
    RAISE EXCEPTION 'La tarea de purga no quedo programada';
  END IF;

  SELECT count(*) INTO v_afectaria FROM public.notificaciones
   WHERE leido = true AND created_at < now() - interval '180 days';
  SELECT count(*) INTO v_sin_leer FROM public.notificaciones WHERE NOT leido;

  RAISE NOTICE 'Verificado. Borraria ahora mismo: % filas. Sin leer (nunca se tocan): %.',
               v_afectaria, v_sin_leer;
END $$;
