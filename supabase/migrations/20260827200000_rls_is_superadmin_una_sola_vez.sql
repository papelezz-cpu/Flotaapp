-- ============================================================================
-- RLS: is_superadmin() se evalua UNA VEZ por consulta, no una vez por fila
-- ============================================================================
-- Continuacion de 20260827120000, que hizo lo mismo con auth.uid().
--
-- is_superadmin() es mas cara que auth.uid(): no solo lee el JWT, ademas
-- consulta perfiles. Escrita suelta dentro de una politica, Postgres la mete
-- en el Filter y la ejecuta por cada fila que evalua. Envuelta como
-- (SELECT is_superadmin()) pasa a ser una subconsulta escalar sin correlacion
-- que el planificador resuelve como InitPlan: una sola vez.
--
-- Se dejo fuera de aquella migracion a proposito, para cambiar una cosa a la
-- vez en algo que decide el control de acceso. Ya verificado el metodo alli,
-- se aplica el mismo.
--
-- Medido antes de aplicar: 20 politicas la llaman desnuda. La numero 21,
-- of_select, ya la lleva envuelta porque se escribio asi en la Fase 4.
--
-- ── No cambia quien ve que ────────────────────────────────────────────────
-- La transformacion es sintactica y el valor devuelto es el mismo. Se verifica
-- comparando, antes y despues, el conjunto exacto de filas visibles para un
-- usuario de cada rol sobre las 24 tablas.
--
-- ── Idempotente ───────────────────────────────────────────────────────────
-- Solo toca politicas con la llamada desnuda. Al reejecutarse no encuentra
-- ninguna y no hace nada.
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
       AND (coalesce(qual,'') || coalesce(with_check,'')) ~ 'is_superadmin\(\)'
       -- Ya envuelta: se salta. Sin esto, un replace ciego convertiria
       -- (SELECT public.is_superadmin()) en (SELECT public.(SELECT ...)).
       AND (coalesce(qual,'') || coalesce(with_check,'')) !~ 'SELECT\s+(public\.)?is_superadmin'
     ORDER BY tablename, policyname
  LOOP
    sql := format('ALTER POLICY %I ON public.%I', r.policyname, r.tablename);

    IF r.qual IS NOT NULL THEN
      sql := sql || format(' USING (%s)',
                           replace(r.qual, 'is_superadmin()', '(SELECT is_superadmin())'));
    END IF;
    IF r.with_check IS NOT NULL THEN
      sql := sql || format(' WITH CHECK (%s)',
                           replace(r.with_check, 'is_superadmin()', '(SELECT is_superadmin())'));
    END IF;

    EXECUTE sql;
    n := n + 1;
  END LOOP;

  RAISE NOTICE 'Politicas reescritas: %', n;
END $$;

DO $$
DECLARE pendientes integer;
BEGIN
  SELECT count(*) INTO pendientes
    FROM pg_policies
   WHERE schemaname = 'public'
     AND (coalesce(qual,'') || coalesce(with_check,'')) ~ 'is_superadmin\(\)'
     AND (coalesce(qual,'') || coalesce(with_check,'')) !~ 'SELECT\s+(public\.)?is_superadmin';
  IF pendientes > 0 THEN
    RAISE EXCEPTION 'Quedaron % politicas con is_superadmin() sin envolver', pendientes;
  END IF;
  RAISE NOTICE 'Verificado: 0 politicas con is_superadmin() suelta.';
END $$;
