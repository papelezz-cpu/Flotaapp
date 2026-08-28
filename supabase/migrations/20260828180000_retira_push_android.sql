-- ============================================================================
-- ⚠️ CAMBIO DESTRUCTIVO — retira el push de Android
-- ============================================================================
-- Autorizado expresamente el 2026-08-28, para produccion y pruebas.
--
-- ── Por que se retira ─────────────────────────────────────────────────────
--
-- El push se preparo para cubrir el caso "app cerrada". Se decide no seguir:
-- la campana ya cubre bien el caso real —notificaciones esta publicada por
-- Realtime y los dos clientes se suscriben con filtro por usuario— y el push
-- no aporta nada mientras no exista un proyecto de Firebase, que es una
-- dependencia externa que no se va a montar ahora.
--
-- Dejar objetos dormidos en produccion es deuda: quien lea el esquema despues
-- encuentra una tabla y un trigger de una funcionalidad que no existe.
--
-- ── Que se borra, y que NO se pierde ──────────────────────────────────────
--
--   dispositivos_push          tabla, 0 filas en ambas bases
--   trg_enviar_push            trigger sobre notificaciones, nunca disparo
--   enviar_push_de_notificaciones
--   purgar_dispositivos_inactivos
--   purgar-dispositivos        tarea de cron, mensual sobre tabla vacia
--   catalogos push_tipos       10 filas de configuracion
--   pg_net                     extension instalada solo para esto
--
-- Ningun dato de negocio. Cero dispositivos registrados y cero secretos en el
-- vault: el trigger comprobaba su existencia y salia sin hacer nada, asi que
-- nunca llego a enviar una sola notificacion.
--
-- ── Como reponerlo ────────────────────────────────────────────────────────
-- Reaplicando 20260828140000_push_android.sql, que se conserva en el historial
-- de git aunque su commit se revierta. El codigo de Android y la Edge Function
-- estan en ese mismo commit.
-- ============================================================================

-- El trigger primero: mientras exista, la funcion no se puede borrar.
DROP TRIGGER IF EXISTS trg_enviar_push ON public.notificaciones;

DROP FUNCTION IF EXISTS public.enviar_push_de_notificaciones();
DROP FUNCTION IF EXISTS public.purgar_dispositivos_inactivos(integer);

-- La tarea de cron, antes de que quede apuntando a una funcion inexistente.
DO $$
BEGIN
  PERFORM cron.unschedule('purgar-dispositivos')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purgar-dispositivos');
END $$;

-- La tabla. Se comprueba que sigue vacia antes de tirarla: si alguien hubiera
-- alcanzado a registrar un telefono, esto se detiene en vez de borrarlo.
DO $$
DECLARE n integer;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='dispositivos_push') THEN
    EXECUTE 'SELECT count(*) FROM public.dispositivos_push' INTO n;
    IF n > 0 THEN
      RAISE EXCEPTION 'dispositivos_push tiene % fila(s). Se detiene: revisar antes de borrar.', n;
    END IF;
    DROP TABLE public.dispositivos_push;
    RAISE NOTICE 'Tabla dispositivos_push eliminada (estaba vacia).';
  END IF;
END $$;

DELETE FROM public.catalogos WHERE clave = 'push_tipos';

-- pg_net: se instalo unicamente para el trigger de push. Sin el, nada la usa,
-- y dejar instalada una extension que permite hacer peticiones HTTP desde la
-- base es superficie sin contrapartida. Reinstalarla es una sentencia.
DROP EXTENSION IF EXISTS pg_net;


-- ─────────────────────────────────────────────────────────────────────────
-- Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_resto integer := 0;
BEGIN
  v_resto := v_resto + (SELECT count(*) FROM pg_tables
                         WHERE schemaname='public' AND tablename='dispositivos_push');
  v_resto := v_resto + (SELECT count(*) FROM pg_trigger WHERE tgname='trg_enviar_push');
  v_resto := v_resto + (SELECT count(*) FROM pg_proc
                         WHERE pronamespace='public'::regnamespace
                           AND proname IN ('enviar_push_de_notificaciones','purgar_dispositivos_inactivos'));
  v_resto := v_resto + (SELECT count(*) FROM cron.job WHERE jobname='purgar-dispositivos');
  v_resto := v_resto + (SELECT count(*) FROM public.catalogos WHERE clave='push_tipos');
  v_resto := v_resto + (SELECT count(*) FROM pg_extension WHERE extname='pg_net');

  IF v_resto > 0 THEN
    RAISE EXCEPTION 'Quedaron % objeto(s) del push sin retirar', v_resto;
  END IF;

  -- Lo que NO debe haberse tocado.
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname='purgar-notificaciones') THEN
    RAISE EXCEPTION 'Se perdio la tarea de retencion de notificaciones';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                  WHERE pubname='supabase_realtime' AND tablename='notificaciones') THEN
    RAISE EXCEPTION 'Se perdio notificaciones de la publicacion de Realtime';
  END IF;

  RAISE NOTICE 'Verificado: push retirado por completo; retencion y Realtime intactos.';
END $$;
