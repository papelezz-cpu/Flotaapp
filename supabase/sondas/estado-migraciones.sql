-- Que migraciones de la ronda 2 estan aplicadas en ESTA base.
-- Solo lee. Correr igual contra pruebas y contra produccion para comparar.
--
-- Las funciones se buscan POR NOMBRE, no por firma: la primera version de esta
-- sonda preguntaba por aceptar_y_cerrar_acuerdo(uuid) cuando la real es
-- (uuid, text), y daba un falso negativo en las dos bases.

WITH fn AS (
  SELECT p.proname, pg_get_functiondef(p.oid) AS def
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
)
SELECT
  EXISTS (SELECT 1 FROM fn WHERE proname = 'aceptar_y_cerrar_acuerdo')
    AS "03_rpc_acuerdo",
  to_regclass('public.uq_operadores_curp') IS NOT NULL
    AS "08a_restricciones",
  to_regclass('public.uq_camiones_placas') IS NOT NULL
    AS "08b_placa_unica",
  EXISTS (SELECT 1 FROM fn WHERE proname = 'sincronizar_estados_pedidos')
    AS "08c_cron_estados",
  to_regclass('public.perfiles_roles_interno') IS NOT NULL
    AS "08d_fin_recursion",
  EXISTS (SELECT 1 FROM fn WHERE proname = 'cerrar_acuerdo'
            AND def LIKE '%portgo.cierre_acuerdo%')
    AS "09_acuerdo_mutuo",

  -- Migracion de datos: no crea objetos, asi que se mide por su efecto.
  -- "candidatos" son las cuentas aprobadas cuya solicitud trae razon social.
  -- Si candidatos > 0 y pendientes = 0, la copia ya se hizo.
  (SELECT count(*) FROM public.perfiles p
     JOIN public.solicitudes_cuenta s ON s.user_id = p.user_id
    WHERE s.estado = 'aprobada'
      AND nullif(btrim(s.razon_social), '') IS NOT NULL)
    AS "10_candidatos",
  (SELECT count(*) FROM public.perfiles p
     JOIN public.solicitudes_cuenta s ON s.user_id = p.user_id
    WHERE s.estado = 'aprobada'
      AND nullif(btrim(s.razon_social), '') IS NOT NULL
      AND nullif(btrim(p.razon_social), '') IS NULL)
    AS "10_pendientes",

  (SELECT count(*) FROM cron.job WHERE jobname = 'portgo-sincronizar-estados')
    AS "cron_activo";


-- ── Ronda 3 (auditoría del 2026-09-11) ────────────────────────────────────
-- Añadido el 2026-09-14, antes de promover. Sigue siendo de solo lectura.
-- Contra PRODUCCIÓN, todo esto debe salir false / 0 antes de aplicar nada; si
-- algo sale true, esa migración ya está y no hay que reaplicarla.

WITH fn AS (
  SELECT p.proname, pg_get_functiondef(p.oid) AS def
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
)
SELECT
  to_regclass('public.uq_reservaciones_pedido_vivo') IS NOT NULL
    AS "11a_cierre_sin_carrera",
  EXISTS (SELECT 1 FROM fn WHERE proname = 'aceptar_y_cerrar_acuerdo'
            AND def LIKE '%FOR UPDATE%')
    AS "11a_for_update",
  NOT has_table_privilege('authenticated', 'public.pedidos', 'TRUNCATE')
    AS "11b_sin_truncate",
  EXISTS (SELECT 1 FROM fn WHERE proname = 'responder_oferta'
            AND def LIKE '%aceptar_y_cerrar_acuerdo%')
    AS "11d_rpc_delegan",
  EXISTS (SELECT 1 FROM fn WHERE proname = 'cambiar_rol')
    AS "14_cambiar_rol",

  -- Lo que TUMBA 20260911120000 si ya ocurrió la carrera. Debe ser 0.
  (SELECT count(*) FROM (
     SELECT pedido_id FROM public.reservaciones
      WHERE pedido_id IS NOT NULL
        AND estado NOT IN ('Cancelada','Rechazada')
      GROUP BY pedido_id HAVING count(*) > 1) d)
    AS "bloqueante_pedidos_duplicados",

  -- Contexto para decidir: cuántas políticas siguen sin declarar destinatario,
  -- y cuántas relaciones conservan TRUNCATE para authenticated.
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND roles = '{public}')
    AS "politicas_sin_TO",
  (SELECT count(*) FROM pg_class c
     JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','f')
      AND has_table_privilege('authenticated', c.oid, 'TRUNCATE'))
    AS "relaciones_con_truncate";
