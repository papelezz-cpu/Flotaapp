-- ============================================================================
-- H-17: la maquina de estados deja de depender de que alguien abra el navegador
-- ============================================================================
--
-- Hoy js/pedidos.js:264-335 hace avanzar cinco transiciones como EFECTO
-- SECUNDARIO de dibujar la lista de solicitudes. Si nadie abre "Solicitudes"
-- en la web, no ocurren: un pedido puede quedarse en 'en_negociacion' sin
-- ninguna oferta viva —invisible para las empresas— hasta que un superadmin
-- entre a esa pantalla.
--
-- La cobertura actual es PARCIAL, y conviene decirlo con precision porque la
-- auditoria original lo dijo peor: el cron `expire-stale-offers` ya corre cada
-- hora en produccion y cubre la expiracion de ofertas. Lo que sigue colgando
-- del navegador son las otras cuatro reglas.
--
-- ── Por que esta migracion y no 20260810130000_sincronizar_estados_OPCIONAL ──
--
-- Aquella se escribio el 10 de agosto y NO se puede aplicar hoy: haria un
-- CREATE OR REPLACE del guard con una version de agosto, y le borraria tres
-- ramas anadidas despues.
--
--   1. La rama de orfandad por borrado de cuenta (NEW.cliente_id IS NULL y el
--      titular anterior ya no existe). Sin ella, dar de baja una cuenta
--      vuelve a fallar — que es justo lo que arreglo 20260827190000.
--   2. El permiso del CLIENTE para pasar de 'pendiente_acuerdo' a 'acordado'
--      cuando hay una oferta aceptada. La version vieja bloquea 'acordado'
--      sin condicion.
--   3. La rama del ADMIN para 'pendiente_acuerdo' -> 'acordado'.
--
-- Las dos ultimas son precisamente de las que depende aceptar_y_cerrar_acuerdo
-- (20260903120000, lote B de H-10). Aplicar la migracion vieja romperia la RPC
-- que se acaba de escribir.
--
-- Ademas su funcion de sincronizacion tiene dos problemas propios:
--
--   · Le falta una regla entera, la de "solicitud sin ofertas vivas cuya fecha
--     de carga ya llego" -> expirado. Se anadio al navegador despues.
--   · Su regla (b) reabre un pedido 'en_negociacion' mirando solo si quedan
--     ofertas 'enviada' o 'contra_oferta' vivas, sin excluir las 'aceptada'.
--     Un pedido con una oferta aceptada pasaria a 'abierto', y entonces la
--     regla (c) —que busca 'en_negociacion'— ya no lo encontraria para
--     llevarlo a 'pendiente_acuerdo'. El JS no tiene ese fallo porque su
--     comprobacion exige que TODAS las ofertas esten rechazadas.
--
-- Esta migracion parte del guard VIGENTE (leido del volcado de produccion del
-- 2026-08-31) y le anade unicamente la escotilla. 20260810130000 queda
-- obsoleta; no se borra, pero no debe aplicarse.
--
-- ── La escotilla ──────────────────────────────────────────────────────────
--
-- El cron no tiene sesion: auth.uid() es NULL, ninguna rama del guard aplica y
-- termina en RAISE 'No autorizado'. Es el mismo muro con el que choco la
-- correccion de datos de H-03 el 2026-09-08.
--
-- Se resuelve con un GUC local a la transaccion (portgo.sync) que solo
-- enciende sincronizar_estados_pedidos(), que es SECURITY DEFINER y esta
-- REVOCADA para anon y authenticated. Un cliente de PostgREST no puede
-- ejecutar SET ni llamar a set_config —vive en pg_catalog, fuera del esquema
-- expuesto— asi que no hay via para encenderlo desde fuera.
--
-- Aun asi hay que decirlo claro: **esto abre un camino que se salta el guard**.
-- Es estrecho y esta cerrado por permisos, pero existe. La alternativa
-- —dejar las transiciones colgando del navegador— tiene su propio coste, y
-- es el que la auditoria marco.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. El guard vigente, con la escotilla anadida
-- ─────────────────────────────────────────────────────────────────────────
-- Copia literal del que corre hoy. Lo unico nuevo son las cuatro lineas del
-- primer IF. Si el guard cambia en el futuro, esta funcion hay que
-- reescribirla desde la nueva version, no desde esta.

CREATE OR REPLACE FUNCTION public.guard_pedido_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  es_admin boolean;
BEGIN
  -- NUEVO: mantenimiento programado. El GUC es local a la transaccion y solo
  -- lo enciende sincronizar_estados_pedidos(), no ejecutable por anon ni por
  -- authenticated.
  IF current_setting('portgo.sync', true) = 'on' THEN
    RETURN NEW;
  END IF;

  -- orfandad por borrado de cuenta: el titular anterior ya no existe
  IF NEW.cliente_id IS NULL AND OLD.cliente_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.perfiles WHERE user_id = OLD.cliente_id) THEN
    RETURN NEW;
  END IF;

  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  IF OLD.cliente_id = auth.uid() THEN
    IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado = 'rechazado' THEN
      RAISE EXCEPTION 'No autorizado: esa transicion de estado requiere aprobacion del superadmin';
    END IF;
    IF NEW.estado IS DISTINCT FROM OLD.estado AND NEW.estado = 'acordado' THEN
      IF OLD.estado <> 'pendiente_acuerdo' OR NOT EXISTS (
        SELECT 1 FROM public.ofertas o WHERE o.id = OLD.oferta_pendiente_id AND o.estado = 'aceptada'
      ) THEN
        RAISE EXCEPTION 'No autorizado: esa transicion de estado requiere aprobacion del superadmin';
      END IF;
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

    IF OLD.estado = 'acordado' AND NEW.estado = 'abierto' THEN
      IF EXISTS (
        SELECT 1 FROM public.ofertas o
        WHERE o.pedido_id = OLD.id AND o.admin_id = auth.uid() AND o.estado = 'aceptada'
      ) THEN
        RETURN NEW;
      END IF;
    END IF;

    IF OLD.estado = 'pendiente_acuerdo' AND NEW.estado = 'acordado' THEN
      IF EXISTS (
        SELECT 1 FROM public.ofertas o
        WHERE o.id = OLD.oferta_pendiente_id AND o.admin_id = auth.uid() AND o.estado = 'aceptada'
      ) THEN
        RETURN NEW;
      END IF;
    END IF;

    RAISE EXCEPTION 'No autorizado: este pedido ya no esta en fase de negociacion';
  END IF;

  RAISE EXCEPTION 'No autorizado';
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. Las cinco reglas, copiadas del navegador
-- ─────────────────────────────────────────────────────────────────────────
-- Orden importante: (a) va primero para que (b), (c) y (e) vean las ofertas
-- vencidas ya marcadas como rechazadas dentro de la MISMA transaccion. Asi
-- "no queda ninguna oferta viva" se puede escribir como "todas estan
-- rechazadas", que es literalmente lo que comprueba el JS.

CREATE OR REPLACE FUNCTION public.sincronizar_estados_pedidos()
RETURNS TABLE (
  ofertas_expiradas    int,
  pedidos_reabiertos   int,
  acuerdos_pendientes  int,
  acuerdos_expirados   int,
  solicitudes_vencidas int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  n1 int := 0; n2 int := 0; n3 int := 0; n4 int := 0; n5 int := 0;
BEGIN
  PERFORM set_config('portgo.sync', 'on', true);  -- true = solo esta transaccion

  -- (a) Ofertas vencidas -> rechazada.
  -- Duplica lo que ya hace el cron expire-stale-offers cada hora, y esta bien
  -- que lo duplique: es idempotente, y hace falta AQUI para que las reglas
  -- siguientes vean el estado ya normalizado sin esperar a la hora en punto.
  WITH x AS (
    UPDATE public.ofertas SET estado = 'rechazada'
     WHERE estado = 'enviada' AND expira_en IS NOT NULL AND expira_en < now()
    RETURNING 1)
  SELECT count(*) INTO n1 FROM x;

  -- (b) Pedido en negociacion cuyas ofertas estan TODAS rechazadas -> abierto.
  -- "Todas rechazadas" y no "sin ofertas vivas": asi un pedido con una oferta
  -- aceptada no se reabre por error y queda para la regla (c). El JS hace
  -- exactamente esta comprobacion.
  WITH x AS (
    UPDATE public.pedidos p SET estado = 'abierto'
     WHERE p.estado = 'en_negociacion'
       AND EXISTS (SELECT 1 FROM public.ofertas o WHERE o.pedido_id = p.id)
       AND NOT EXISTS (
         SELECT 1 FROM public.ofertas o
          WHERE o.pedido_id = p.id AND o.estado <> 'rechazada')
    RETURNING 1)
  SELECT count(*) INTO n2 FROM x;

  -- (c) Pedido en negociacion con una oferta aceptada -> pendiente_acuerdo.
  -- Restos de cuando aceptar una oferta eran tres escrituras sueltas. Desde
  -- aceptar_y_cerrar_acuerdo (20260903120000) ya no deberia producirse, pero
  -- se conserva para el historico que quedo a medias.
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

  -- (d) Acuerdo cuya fecha_fin ya paso y nunca se completo -> expirado.
  -- Los completados pasan a 'finalizado' al aprobarse la finalizacion.
  WITH x AS (
    UPDATE public.pedidos SET estado = 'expirado'
     WHERE estado = 'acordado' AND fecha_fin IS NOT NULL AND fecha_fin < current_date
    RETURNING 1)
  SELECT count(*) INTO n4 FROM x;

  -- (e) Solicitud cuya fecha de carga ya llego y no tiene ninguna oferta viva
  --     -> expirado. Nadie va a poder atenderla a tiempo.
  -- FALTABA en 20260810130000: esta regla se anadio al navegador despues.
  -- Incluye las que no tienen NINGUNA fila en ofertas: en JS eso sale de que
  -- .every() sobre un array vacio devuelve true.
  WITH x AS (
    UPDATE public.pedidos p SET estado = 'expirado'
     WHERE p.estado IN ('abierto', 'pendiente_revision')
       AND p.fecha_ini IS NOT NULL
       AND p.fecha_ini <= current_date
       AND NOT EXISTS (
         SELECT 1 FROM public.ofertas o
          WHERE o.pedido_id = p.id AND o.estado <> 'rechazada')
    RETURNING 1)
  SELECT count(*) INTO n5 FROM x;

  RETURN QUERY SELECT n1, n2, n3, n4, n5;
END;
$$;

-- Nadie la llama desde la app: es mantenimiento programado. Esta revocacion
-- es la que cierra la escotilla del guard.
REVOKE ALL ON FUNCTION public.sincronizar_estados_pedidos() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.sincronizar_estados_pedidos() IS
  'Mantenimiento programado: replica en el servidor las cinco transiciones que js/pedidos.js hacia al dibujar la lista. Ver H-17.';


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Programarla
-- ─────────────────────────────────────────────────────────────────────────
-- pg_cron ya esta instalada y en uso en produccion (expire-stale-offers cada
-- hora, purgar-notificaciones el dia 1 de cada mes), asi que aqui no hay que
-- decidir nada de infraestructura: solo anadir un trabajo mas.
--
-- Cada 15 minutos es de sobra. Ninguna de las cinco reglas es urgente al
-- minuto, y a estos volumenes el trabajo es imperceptible.
--
-- ⚠ ESTO EMPIEZA A ESCRIBIR SOLO. A partir de aqui hay dos actores tocando
--   los mismos estados: el cron y el navegador. Las cinco reglas son
--   idempotentes y coinciden literalmente, asi que el resultado es el mismo
--   las corra quien las corra. Retirar las del navegador es una decision
--   aparte, y conviene dejarlas un tiempo: mientras esten las dos, un fallo
--   del cron no deja los estados congelados.

SELECT cron.schedule(
  'portgo-sincronizar-estados',
  '*/15 * * * *',
  $$SELECT public.sincronizar_estados_pedidos()$$
);
