-- ============================================================================
-- RLS: auth.uid() se evalua UNA VEZ por consulta, no una vez por fila
-- ============================================================================
-- auth.uid() no es una funcion barata: expande a
--
--   COALESCE(NULLIF(current_setting('request.jwt.claim.sub', true), ''),
--            (NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb ->> 'sub')::uuid
--
-- es decir, leer un GUC y parsear JSONB. Escrito suelto dentro de una politica,
-- Postgres lo mete en el Filter y lo ejecuta POR CADA FILA que evalua.
--
-- Envuelto como (SELECT auth.uid()) pasa a ser una subconsulta escalar sin
-- correlacion, que el planificador resuelve como InitPlan: se calcula una sola
-- vez y se reutiliza. Es la optimizacion de RLS que Supabase documenta.
--
-- Medido antes de aplicarlo, misma consulta sobre reservaciones:
--   sin envolver:  Seq Scan + Filter con el COALESCE completo por fila
--   envuelto:      InitPlan 1 / InitPlan 2, calculado una vez
-- El beneficio crece con el numero de filas evaluadas, asi que es mayor
-- cuanto mas crezcan las tablas.
--
-- ── NO cambia quien ve que ─────────────────────────────────────────────────
-- La transformacion es puramente sintactica: el valor devuelto es el mismo.
-- Verificado en portgo-pruebas comparando, antes y despues, el conjunto exacto
-- de filas visibles (md5 del agregado ordenado) para un usuario de cada rol
-- —cliente, admin, superadmin y anon— sobre las 24 tablas: huella identica.
--
-- ── Idempotente ───────────────────────────────────────────────────────────
-- Solo toca politicas que tengan auth.uid() sin envolver. Al reejecutarse no
-- encuentra ninguna y no hace nada. Se hace con un bloque dinamico en vez de
-- 57 ALTER POLICY escritos a mano para que funcione igual en las dos bases,
-- que no tienen exactamente el mismo juego de politicas.
-- ============================================================================

DO $$
DECLARE
  r   record;
  sql text;
  n   integer := 0;
BEGIN
  FOR r IN
    SELECT policyname, tablename, qual, with_check
      FROM pg_policies
     WHERE schemaname = 'public'
       AND (coalesce(qual,'') || coalesce(with_check,'')) ~ 'auth\.uid\(\)'
       AND (coalesce(qual,'') || coalesce(with_check,'')) !~ 'SELECT auth\.uid\(\)'
     ORDER BY tablename, policyname
  LOOP
    sql := format('ALTER POLICY %I ON public.%I', r.policyname, r.tablename);

    -- USING y WITH CHECK son independientes: una politica puede traer solo
    -- uno de los dos, y ALTER POLICY exige repetir el que se conserva.
    IF r.qual IS NOT NULL THEN
      sql := sql || format(' USING (%s)',
                           replace(r.qual, 'auth.uid()', '( SELECT auth.uid() )'));
    END IF;
    IF r.with_check IS NOT NULL THEN
      sql := sql || format(' WITH CHECK (%s)',
                           replace(r.with_check, 'auth.uid()', '( SELECT auth.uid() )'));
    END IF;

    EXECUTE sql;
    n := n + 1;
  END LOOP;

  RAISE NOTICE 'Politicas reescritas: %', n;
END $$;

-- Comprobacion: despues de esto no debe quedar ninguna politica de public con
-- auth.uid() suelto. Si la cuenta no es cero, algo no se aplico.
DO $$
DECLARE pendientes integer;
BEGIN
  SELECT count(*) INTO pendientes
    FROM pg_policies
   WHERE schemaname = 'public'
     AND (coalesce(qual,'') || coalesce(with_check,'')) ~ 'auth\.uid\(\)'
     AND (coalesce(qual,'') || coalesce(with_check,'')) !~ 'SELECT auth\.uid\(\)';
  IF pendientes > 0 THEN
    RAISE EXCEPTION 'Quedaron % politicas con auth.uid() sin envolver', pendientes;
  END IF;
  RAISE NOTICE 'Verificado: 0 politicas con auth.uid() suelto.';
END $$;

-- ── PENDIENTE, NO SE TOCA AQUI ─────────────────────────────────────────────
-- 20 politicas llaman ademas a is_superadmin(), que es STABLE pero hace una
-- lectura de perfiles. Envolverla como (SELECT is_superadmin()) daria el mismo
-- ahorro por fila. No se incluye porque no se ha medido y porque conviene
-- cambiar una cosa a la vez en algo que decide el control de acceso.
-- ============================================================================
