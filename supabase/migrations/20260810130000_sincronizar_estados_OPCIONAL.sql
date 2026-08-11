-- ──────────────────────────────────────────────────────────────────────────
-- ⚠ MIGRACIÓN OPCIONAL — LEE ESTO ANTES DE APLICARLA
--
-- Resuelve el gap G9 del análisis móvil: hoy la máquina de estados de los
-- pedidos avanza como EFECTO SECUNDARIO de dibujar la lista en el navegador
-- (js/pedidos.js:239-292). Si nadie abre "Solicitudes" en la web, las ofertas
-- vencidas no se marcan, los pedidos sin ofertas vivas no se reabren y los
-- acuerdos con fecha pasada siguen diciendo 'acordado'. Una app móvil que solo
-- lea verá estados rancios; una que los replique duplica la regla en Swift y
-- en Kotlin, que es justo lo que se quiere evitar.
--
-- ── Por qué es opcional y no va en la migración principal ─────────────────
--
-- Para correr desde pg_cron hace falta una excepción en guard_pedido_update.
-- Ese trigger decide con auth.uid(), y un cron no tiene sesión: auth.uid() es
-- NULL, ninguna rama del guard aplica y termina en RAISE 'No autorizado'.
--
-- La excepción es un GUC local a la transacción (portgo.sync) que solo se
-- activa desde dentro de sincronizar_estados_pedidos(), que es SECURITY
-- DEFINER y está REVOCADA para anon y authenticated. Un cliente de PostgREST
-- no puede ejecutar SET ni llamar set_config (vive en pg_catalog, fuera del
-- esquema expuesto), así que no hay vía para encenderlo desde fuera.
--
-- Aun así: **es tocar un guard de seguridad**, y dijiste que G4 y G5 quedaban
-- fuera por ahora. Por eso va suelta y la decides tú. Si prefieres no
-- aplicarla, no pasa nada grave: la web sigue avanzando los estados igual que
-- hoy y el móvil los lee como estén. La única consecuencia es que un acuerdo
-- vencido puede tardar en aparecer como 'expirado' hasta que alguien abra la
-- lista en la web.
-- ──────────────────────────────────────────────────────────────────────────


-- ── 1) Excepción en el guard ──────────────────────────────────────────────
-- Idéntico a la versión de 20260728120000, con la primera condición añadida.
CREATE OR REPLACE FUNCTION public.guard_pedido_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  es_admin boolean;
BEGIN
  -- Mantenimiento programado (sincronizar_estados_pedidos). El GUC es local a
  -- la transacción y solo lo enciende esa función, que no es ejecutable por
  -- anon ni por authenticated.
  IF current_setting('portgo.sync', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  -- Cliente dueno del pedido: puede tocarlo, pero 'acordado'/'rechazado' son
  -- transiciones exclusivas de superadmin.
  IF OLD.cliente_id = auth.uid() THEN
    IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado IN ('acordado', 'rechazado') THEN
      RAISE EXCEPTION 'No autorizado: esa transicion de estado requiere aprobacion del superadmin';
    END IF;
    RETURN NEW;
  END IF;

  SELECT (rol = 'admin') INTO es_admin FROM public.perfiles WHERE user_id = auth.uid();

  IF es_admin THEN
    IF OLD.estado IN ('abierto', 'en_negociacion') THEN
      IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado IN ('acordado', 'rechazado', 'cancelado') THEN
        RAISE EXCEPTION 'No autorizado: esa transicion de estado no la puede hacer un admin';
      END IF;
      RETURN NEW;
    END IF;

    -- Reabrir un pedido ya acordado porque el admin cuya oferta fue aceptada
    -- cancelo la reservacion (ver cancelar_reservacion()).
    IF OLD.estado = 'acordado' AND NEW.estado = 'abierto' THEN
      IF EXISTS (
        SELECT 1 FROM public.ofertas o
        WHERE o.pedido_id = OLD.id AND o.admin_id = auth.uid() AND o.estado = 'aceptada'
      ) THEN
        RETURN NEW;
      END IF;
    END IF;

    RAISE EXCEPTION 'No autorizado: este pedido ya no esta en fase de negociacion';
  END IF;

  RAISE EXCEPTION 'No autorizado';
END;
$$;


-- ── 2) La sincronización ──────────────────────────────────────────────────
-- Las cuatro reglas son copia literal de las que hoy corren en el navegador.
CREATE OR REPLACE FUNCTION public.sincronizar_estados_pedidos()
RETURNS TABLE (
  ofertas_expiradas   int,
  pedidos_reabiertos  int,
  acuerdos_pendientes int,
  acuerdos_expirados  int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  n1 int := 0; n2 int := 0; n3 int := 0; n4 int := 0;
BEGIN
  PERFORM set_config('portgo.sync', 'on', true);  -- true = solo esta transacción

  -- a) Ofertas vencidas → rechazada
  WITH x AS (
    UPDATE public.ofertas SET estado = 'rechazada'
     WHERE estado = 'enviada' AND expira_en IS NOT NULL AND expira_en < now()
    RETURNING 1)
  SELECT count(*) INTO n1 FROM x;

  -- b) Pedido en negociación sin ninguna oferta viva → abierto
  WITH x AS (
    UPDATE public.pedidos p SET estado = 'abierto'
     WHERE p.estado = 'en_negociacion'
       AND EXISTS (SELECT 1 FROM public.ofertas o WHERE o.pedido_id = p.id)
       AND NOT EXISTS (
         SELECT 1 FROM public.ofertas o
          WHERE o.pedido_id = p.id
            AND (o.estado IN ('enviada', 'contra_oferta'))
            AND (o.expira_en IS NULL OR o.expira_en >= now()))
    RETURNING 1)
  SELECT count(*) INTO n2 FROM x;

  -- c) Pedido en negociación con una oferta aceptada → pendiente_acuerdo
  --    (pasa si la segunda escritura falló al cerrar la aceptación)
  WITH x AS (
    UPDATE public.pedidos p
       SET estado = 'pendiente_acuerdo',
           oferta_pendiente_id = (
             SELECT o.id FROM public.ofertas o
              WHERE o.pedido_id = p.id AND o.estado = 'aceptada'
              ORDER BY o.created_at DESC LIMIT 1)
     WHERE p.estado = 'en_negociacion'
       AND EXISTS (SELECT 1 FROM public.ofertas o WHERE o.pedido_id = p.id AND o.estado = 'aceptada')
    RETURNING 1)
  SELECT count(*) INTO n3 FROM x;

  -- d) Acuerdo cuya fecha_fin ya pasó y nunca se completó → expirado
  --    (los completados pasan a 'finalizado' al aprobar la finalización)
  WITH x AS (
    UPDATE public.pedidos SET estado = 'expirado'
     WHERE estado = 'acordado' AND fecha_fin IS NOT NULL AND fecha_fin < current_date
    RETURNING 1)
  SELECT count(*) INTO n4 FROM x;

  RETURN QUERY SELECT n1, n2, n3, n4;
END;
$$;

-- Nadie la llama desde la app: es mantenimiento programado.
REVOKE ALL ON FUNCTION public.sincronizar_estados_pedidos() FROM PUBLIC, anon, authenticated;


-- ── 3) Programarla ────────────────────────────────────────────────────────
-- Requiere la extensión pg_cron (Supabase → Database → Extensions).
-- Cada 15 minutos es de sobra: ninguna de las cuatro reglas es urgente al
-- minuto, y así el trabajo es imperceptible.
--
--   CREATE EXTENSION IF NOT EXISTS pg_cron;
--   SELECT cron.schedule(
--     'portgo-sincronizar-estados', '*/15 * * * *',
--     $$SELECT public.sincronizar_estados_pedidos()$$);
--
-- Se deja comentado a propósito: habilitar pg_cron es una decisión de
-- infraestructura del proyecto, no de esta migración.
