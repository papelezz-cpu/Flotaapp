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
