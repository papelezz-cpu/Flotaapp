-- ============================================================================
-- Iguala `pg_default_acl` de pruebas al de producción (sin re-replicar)
-- ============================================================================
--
-- Producción tiene, en las tres filas de privilegios por omisión, una entrada
-- que pruebas no tenía: **`postgres` a sí mismo**.
--
--     produccion  f  {postgres=X/postgres, anon=X, authenticated=X, service_role=X}
--     pruebas     f  {                     anon=X, authenticated=X, service_role=X}
--
-- Es REDUNDANTE —el dueño ya tiene todo sobre lo que crea— pero
-- `verificar-paridad.sh` compara la fila entera, así que sin ella la dimensión
-- `acl_por_defecto` divergía **para siempre**: 3 filas × 2 lados = 6 de las 10
-- diferencias que quedaron tras la réplica del 2026-09-28. Y un sello que nunca
-- puede ponerse verde es un candado que la gente aprende a ignorar.
--
-- Esto NO hace falta en producción: allí ya están. Aplicarlo sería un no-op.
-- El paso 4b de `replicar-produccion-a-pruebas.sh` ya las fija, así que a partir
-- de la próxima réplica esto no se necesita.
--
-- Uso:  bash supabase/aplicar-a-pruebas.sh supabase/igualar-acl-por-defecto-pruebas.sql
-- ============================================================================

alter default privileges for role postgres in schema public grant all on tables    to postgres;
alter default privileges for role postgres in schema public grant all on sequences to postgres;
alter default privileges for role postgres in schema public grant all on functions to postgres;

do $$
declare
  v_falta text := '';
  r       record;
begin
  for r in select defaclobjtype::text as tipo, defaclacl::text as acl
             from pg_default_acl
            where defaclrole = 'postgres'::regrole
              and defaclnamespace = 'public'::regnamespace
  loop
    if position('postgres=' in r.acl) = 0 then
      v_falta := v_falta || r.tipo || ' ';
    end if;
  end loop;

  if v_falta <> '' then
    raise exception 'No quedo la entrada de postgres en: %. Sin ella acl_por_defecto sigue divergiendo.', v_falta;
  end if;


  raise notice 'acl_por_defecto: las tres filas de postgres llevan su propia entrada. Vuelve a correr verificar-paridad.sh.';
end $$;
