-- ============================================================================
-- Las vistas tampoco se escriben con la clave de servicio
-- ============================================================================
--
-- ── Como aparecio ─────────────────────────────────────────────────────────
--
-- La verificacion de paridad del 2026-09-18, despues de reaplicar H-10 a
-- pruebas, bajo de 72 diferencias a 24. Las 24 son una sola cosa: 4 vistas x 3
-- escrituras (INSERT, UPDATE, DELETE) para service_role, con el valor puesto
-- en produccion y quitado en pruebas.
--
-- Comprobado por comportamiento, no leyendo catalogos — con la clave de
-- servicio de cada proyecto y un PATCH cuyo filtro no casa con ninguna fila:
--
--   PRODUCCION  camiones/custodios/patios/lavados_publico → 204 ESCRIBIBLE
--   PRUEBAS     las mismas cuatro                         → 403
--   empresas_publico, en LOS DOS proyectos                → 204 ESCRIBIBLE
--
-- ── El defecto de fondo, que es mas viejo que H-10 ────────────────────────
--
-- Es H-01 otra vez, con el rol que nadie miro. El esquema lleva
-- `ALTER DEFAULT PRIVILEGES ... GRANT ALL ON TABLES`, y en PostgreSQL "TABLES"
-- incluye las vistas: cada vista nueva NACE ESCRIBIBLE. La migracion de H-01
-- (20260914130000) barrio eso para anon y authenticated, y las de H-10
-- retiraron lo mismo antes de conceder — pero ninguna toco service_role, asi
-- que empresas_publico lleva aceptando INSERT, UPDATE y DELETE de la clave de
-- servicio desde que se creo, en los dos proyectos.
--
-- Y la sonda que deberia haberlo cazado tampoco lo miraba:
-- supabase/sondas/escritura-en-vistas.sql recorre
-- `(VALUES ('anon'), ('authenticated'))` y ahi se acaba.
--
-- ── Cuanto importa, dicho sin inflarlo ────────────────────────────────────
--
-- Poco, en privilegio: la clave de servicio ya se salta el RLS y tiene ALL
-- sobre las tablas base, asi que escribir por la vista no le concede nada que
-- no pudiera hacer por la tabla. Quien tenga esa clave ya lo tiene todo.
--
-- Importa por otras dos razones, y son suficientes:
--
--   1. Una vista declarada de solo lectura tiene que serlo para todos los
--      roles, o la declaracion no significa nada y hay que ir a comprobarla
--      caso por caso.
--   2. La paridad seguira fallando mientras los dos proyectos no coincidan, y
--      una paridad que falla por algo conocido acaba siendo una paridad que
--      nadie lee.
--
-- ── Por que se revoca y no se concede ─────────────────────────────────────
--
-- Igualar pruebas a produccion seria conceder la escritura a service_role en
-- las cuatro vistas. Cierra la paridad igual de rapido y deja el defecto en
-- los dos lados. Se revoca en los dos.
--
-- ── Por que no aparece en pg_default_acl comparado ────────────────────────
--
-- verificar-paridad.sh compara 18 dimensiones y NINGUNA es pg_default_acl. Una
-- diferencia en los privilegios por omision es invisible hasta que alguien crea
-- un objeto nuevo, y entonces se manifiesta como diferencia de ese objeto — que
-- es exactamente como se vio esto. Anotarlo aqui porque la proxima vez que una
-- vista nueva salga con permisos distintos entre proyectos, la causa sera esta
-- y no la migracion que la creo.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. El barrido
-- ─────────────────────────────────────────────────────────────────────────
-- Recorre el catalogo en vez de nombrar las vistas una a una, por lo mismo que
-- lo hizo H-01: una lista escrita a mano se queda corta en cuanto alguien crea
-- la siguiente vista, y esa es precisamente la vista que nadie revisara.
--
-- MAINTAIN entra tambien (PG 17+): permite REFRESH y VACUUM sobre la relacion,
-- no es lectura, y H-01 ya lo retiraba para los otros dos roles.

do $$
declare
  r        record;
  v_tocadas text := '';
begin
  for r in
    select c.oid::regclass::text as vista
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
     where c.relkind in ('v','m')
       and (has_table_privilege('service_role', c.oid, 'INSERT')
         or has_table_privilege('service_role', c.oid, 'UPDATE')
         or has_table_privilege('service_role', c.oid, 'DELETE')
         or has_table_privilege('service_role', c.oid, 'MAINTAIN'))
     order by 1
  loop
    execute format('revoke insert, update, delete, maintain on %s from service_role', r.vista);
    v_tocadas := v_tocadas || '  ' || r.vista;
  end loop;

  if v_tocadas = '' then
    raise notice 'Vistas: ninguna aceptaba escrituras de service_role. Nada que hacer.';
  else
    raise notice 'Vistas con la escritura retirada a service_role:%', v_tocadas;
  end if;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
-- Las dos mitades: que ya no se escriba, y que SI se siga leyendo. Lo segundo
-- no es de adorno — revocar de mas aqui dejaria a las Edge Functions sin poder
-- leer, y eso se manifiesta como un 403 en una pantalla, lejos de este archivo.

do $$
declare
  v_escriben text;
  v_ciegas   text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into v_escriben
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
   where c.relkind in ('v','m')
     and (has_table_privilege('service_role', c.oid, 'INSERT')
       or has_table_privilege('service_role', c.oid, 'UPDATE')
       or has_table_privilege('service_role', c.oid, 'DELETE')
       or has_table_privilege('service_role', c.oid, 'MAINTAIN'));

  if v_escriben is not null then
    raise exception 'Todavia aceptan escrituras de service_role: %', v_escriben;
  end if;

  -- Las vistas que el codigo lee con la clave de servicio tienen que seguir
  -- legibles. Se nombran porque son las que existen y se usan; si manana hay
  -- otra, este bloque no la cubre y no pasa nada: el barrido de arriba si.
  select string_agg(v, ', ') into v_ciegas
    from unnest(array['empresas_publico','camiones_publico','custodios_publico',
                      'patios_publico','lavados_publico']) v
   where to_regclass('public.'||v) is not null
     and not has_table_privilege('service_role', 'public.'||v, 'SELECT');

  if v_ciegas is not null then
    raise exception 'service_role se quedo sin LEER: %. Eso rompe las Edge Functions.', v_ciegas;
  end if;

  raise notice 'Ninguna vista de public acepta escrituras de service_role, y todas se siguen leyendo.';
end $$;
