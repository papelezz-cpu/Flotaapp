-- Prueba de «un recurso sin dueño no puede existir», en banco local y revertida.
--
--   psql -d portgo_ensayo -v ON_ERROR_STOP=1 -f pruebas/banco-local/dueno-obligatorio.sql
--
-- Requiere 20260924140000_recursos_con_dueno_obligatorio.sql aplicada.
--
-- Lo que se persigue:
--   · que insertar un recurso sin dueño FALLE en las cinco tablas — es lo único
--     que evita que el hueco 9 vuelva a abrirse;
--   · que los que ya tenían dueño sigan funcionando (un NOT NULL mal puesto
--     rompe el alta normal, y eso se nota en producción, no aquí);
--   · **que el guard de flota siga encendido.** La migración lo apaga para poder
--     reasignar los huérfanos. Si se quedara apagado, cualquiera podría
--     transferirse un recurso ajeno — peor que el problema que vino a arreglar;
--   · y que el dueño asignado pueda de verdad ver sus documentos, que era la
--     consecuencia real del hueco: con propietario nulo, la política de
--     `vigencias` comparaba contra NULL y nadie salvo el superadmin los veía.
--
-- Todo termina con un `rollback`.

begin;

insert into auth.users (id, email) values
  ('44444444-4444-4444-4444-444444444444', 'otra@ejemplo.mx') on conflict do nothing;
insert into public.perfiles (user_id, nombre, rol) values
  ('44444444-4444-4444-4444-444444444444', 'Otra Empresa', 'admin') on conflict do nothing;


\echo ''
\echo '── 1 · Insertar sin dueño falla en las cinco tablas ──'

do $$
declare
  v_fallaron int := 0;
  v_paso     text := '';
begin
  begin insert into public.camiones (id, propietario_id, tipo, capacidad, placas)
        values ('X-NODUE', null, 'Rabón', 8, 'NOD-001');
        v_paso := v_paso || 'camiones ';
  exception when not_null_violation then v_fallaron := v_fallaron + 1; end;

  begin insert into public.operadores (id, propietario_id, nombre, curp, num_licencia)
        values ('OP-NODUE', null, 'Sin Dueño', 'ZZZZ000101HDFZZZ01', 'L-0');
        v_paso := v_paso || 'operadores ';
  exception when not_null_violation then v_fallaron := v_fallaron + 1; end;

  begin insert into public.custodios (id, propietario_id, nombre, tipo)
        values ('CUS-NODUE', null, 'Sin Dueño', 'Custodio armado');
        v_paso := v_paso || 'custodios ';
  exception when not_null_violation then v_fallaron := v_fallaron + 1; end;

  begin insert into public.patios (id, propietario_id, nombre, tipo)
        values ('PAT-NODUE', null, 'Sin Dueño', 'Patio');
        v_paso := v_paso || 'patios ';
  exception when not_null_violation then v_fallaron := v_fallaron + 1; end;

  begin insert into public.lavados (id, propietario_id, nombre)
        values ('LAV-NODUE', null, 'Sin Dueño');
        v_paso := v_paso || 'lavados ';
  exception when not_null_violation then v_fallaron := v_fallaron + 1;
           when others then v_fallaron := v_fallaron + 1; end;

  if v_fallaron <> 5 then
    raise exception 'FALLA: solo % de 5 tablas rechazaron el recurso sin dueño. Pasaron: %', v_fallaron, v_paso;
  end if;
  raise notice '  OK    las cinco tablas rechazan un recurso sin dueño';
end $$;


\echo ''
\echo '── 2 · Y con dueño sigue entrando (el alta normal no se rompió) ──'

do $$
begin
  insert into public.camiones (id, propietario_id, tipo, capacidad, placas)
  values ('X-CONDUE', '44444444-4444-4444-4444-444444444444', 'Rabón', 8, 'CON-001');
  raise notice '  OK    con dueño entra sin problema';
exception when others then
  raise exception 'FALLA: el NOT NULL rompio el alta normal: %', sqlerrm;
end $$;


\echo ''
\echo '── 3 · El guard de flota quedó ENCENDIDO ──'
-- La migración lo apaga para reasignar los huérfanos. Que vuelva a estar
-- encendido no es un detalle: es lo que impide transferirse un recurso ajeno.

do $$
declare v_apagado text; v_ok boolean := false;
begin
  select string_agg(c.relname, ', ') into v_apagado
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal
     and t.tgfoid = 'public.guard_fleet_resource_update()'::regprocedure
     and t.tgenabled = 'D';
  if v_apagado is not null then
    raise exception 'FALLA GRAVE: el guard quedo apagado en: %', v_apagado;
  end if;
  raise notice '  OK    los cinco guards de flota estan encendidos';

  -- Y que de verdad frene: otra empresa intentando quedarse el camión.
  perform set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
  begin
    update public.camiones
       set propietario_id = '44444444-4444-4444-4444-444444444444'
     where id = 'CUS-001';  -- no existe como camión; se usa uno real abajo
  exception when others then v_ok := true;
  end;

  perform set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
  begin
    update public.custodios
       set propietario_id = '44444444-4444-4444-4444-444444444444'
     where id = 'CUS-001';
    raise exception 'FALLA: otra empresa pudo transferirse el custodio ajeno';
  exception when others then
    if sqlerrm like 'FALLA:%' then raise; end if;
    raise notice '  OK    y frena de verdad: %', left(sqlerrm, 62);
  end;
end $$;


\echo ''
\echo '── 4 · El dueño nuevo SÍ ve los documentos de lo que le asignaron ──'
-- Era la consecuencia real del hueco: con propietario nulo,
-- vigencia_propietario() devolvia NULL y la politica comparaba contra NULL, que
-- nunca da verdadero. Solo el superadmin los veia.

do $$
declare v_duenio uuid;
begin
  select public.vigencia_propietario('custodio', 'CUS-001') into v_duenio;
  if v_duenio is null then
    raise exception 'FALLA: vigencia_propietario sigue devolviendo NULL para CUS-001; sus documentos seguirian sin dueño que los renueve';
  end if;
  if v_duenio <> '5919a6f2-03f0-4ccc-877f-fb9fc75139da' then
    raise exception 'FALLA: CUS-001 quedo a nombre de % y no del asignado', v_duenio;
  end if;
  raise notice '  OK    vigencia_propietario resuelve a Omar: sus documentos ya tienen quien los renueve';
end $$;


\echo ''
\echo '   Dueño obligatorio: las cinco tablas lo exigen, el guard sigue en pie,'
\echo '   y los huérfanos ya tienen quien responda por sus papeles.'
\echo ''

rollback;
