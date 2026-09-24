-- Prueba de la Etapa 3 de H-04 (doble escritura) en banco local, revertida.
--
--   psql -d portgo_h04 -v ON_ERROR_STOP=1 -f pruebas/banco-local/h04-etapa3.sql
--
-- Requiere las Etapas 1, 2 y 3 aplicadas al banco.
--
-- Lo que se persigue no es «que copie». Es:
--   · que copie cuando escribe LA EMPRESA, no solo el superadmin
--   · que la empresa NO pueda acreditarse sola por la puerta de atrás
--   · que el perfil siga siendo cosa del superadmin — H-02 no se reabre
--   · que quitar un papel BORRE su fila, y no deje un documento fantasma
--
-- Todo termina con un `rollback`: el banco queda intacto.

begin;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'empresa@ejemplo.mx'),
  ('99999999-9999-9999-9999-999999999999', 'sa@ejemplo.mx');

insert into public.perfiles (user_id, nombre, rol)
values ('99999999-9999-9999-9999-999999999999', 'Super', 'superadmin');

-- El perfil de la empresa entra SIN documentos: los pone el superadmin.
insert into public.perfiles (user_id, nombre, rol)
values ('11111111-1111-1111-1111-111111111111', 'Transportes Ejemplo', 'admin');

insert into public.camiones (id, propietario_id, tipo, capacidad, placas)
values ('C-001', '11111111-1111-1111-1111-111111111111', 'Rabón', 8, 'ABC-123');

\echo ''
\echo '── 1 · La empresa mantiene los papeles de su camión ──'

do $$
declare n int; a text; d date;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);

  update public.camiones
     set doc_seguro = 'u/seg.pdf', fecha_vencimiento_seguro = '2027-02-01'
   where id = 'C-001';

  select count(*) into n from public.vigencias
   where entidad_id='C-001' and tipo_documento='seguro_unidad';
  if n <> 1 then raise exception 'FALLA: la empresa escribió y el espejo no copió (% filas)', n; end if;

  select archivo_path, fecha_documento into a, d from public.vigencias
   where entidad_id='C-001' and tipo_documento='seguro_unidad';
  if a <> 'u/seg.pdf' or d <> '2027-02-01' then
    raise exception 'FALLA: el espejo copió mal: % %', a, d; end if;
  raise notice '  OK    la empresa escribe su camión y el espejo la sigue';

  -- Y al cambiarla, el espejo se actualiza en vez de duplicar.
  update public.camiones set fecha_vencimiento_seguro = '2028-02-01' where id = 'C-001';
  select count(*) into n from public.vigencias
   where entidad_id='C-001' and tipo_documento='seguro_unidad';
  if n <> 1 then raise exception 'FALLA: al cambiar la fecha se duplicó (% filas)', n; end if;
  select fecha_documento into d from public.vigencias
   where entidad_id='C-001' and tipo_documento='seguro_unidad';
  if d <> '2028-02-01' then raise exception 'FALLA: el espejo no siguió el cambio: %', d; end if;
  raise notice '  OK    cambiar la fecha actualiza, no duplica';
end $$;

\echo ''
\echo '── 2 · Quitar el papel borra su fila ──'

do $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  update public.camiones
     set doc_seguro = null, fecha_vencimiento_seguro = null
   where id = 'C-001';

  select count(*) into n from public.vigencias
   where entidad_id='C-001' and tipo_documento='seguro_unidad';
  if n <> 0 then raise exception 'FALLA: se quitó el papel y quedó un documento fantasma'; end if;
  raise notice '  OK    quitar el papel borra su fila, sin dejar fantasmas';

  -- Se vuelve a poner para las pruebas siguientes.
  update public.camiones
     set doc_seguro = 'u/seg.pdf', fecha_vencimiento_seguro = '2027-02-01'
   where id = 'C-001';
end $$;

\echo ''
\echo '── 3 · Pero NO puede acreditarse sola ──'

do $$
declare v_id uuid;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);

  -- Propone una renovación: eso sí puede.
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, archivo_path, fecha_documento, estado)
  values ('camion','C-001','verificacion','u/ver.pdf','2027-08-01','pendiente');
  raise notice '  OK    la empresa puede PROPONER un documento pendiente';

  select id into v_id from public.vigencias
   where entidad_id='C-001' and tipo_documento='verificacion' and estado='pendiente';
  begin
    update public.vigencias set estado='vigente' where id = v_id;
    raise exception 'FALLA: la empresa se acreditó sola su propia propuesta';
  exception when others then
    if sqlerrm like 'FALLA:%' then raise; end if;
    raise notice '  OK    no puede pasar su propuesta a vigente  (%)', split_part(sqlerrm, ':', 1);
  end;
end $$;

\echo ''
\echo '── 4 · H-02 no se reabre: el perfil sigue siendo del superadmin ──'

do $$
declare v_id uuid; n int;
begin
  -- El superadmin acredita el seguro de la empresa.
  perform set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
  update public.perfiles
     set doc_seguro_rc = 'e/rc.pdf', fecha_vencimiento_seguro_rc = '2027-04-01'
   where user_id = '11111111-1111-1111-1111-111111111111';

  select count(*) into n from public.vigencias
   where entidad_tipo='perfil' and tipo_documento='seguro_rc' and estado='vigente';
  if n <> 1 then raise exception 'FALLA: el superadmin acreditó y el espejo no copió'; end if;
  raise notice '  OK    el superadmin acredita y el espejo lo sigue';

  -- Ahora la empresa intenta tocarlo.
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  select id into v_id from public.vigencias
   where entidad_tipo='perfil' and tipo_documento='seguro_rc' and estado='vigente';
  begin
    update public.vigencias set fecha_documento = '2099-01-01' where id = v_id;
    raise exception 'FALLA: la empresa movió la fecha de su seguro acreditado — H-02 REABIERTO';
  exception when others then
    if sqlerrm like 'FALLA:%' then raise; end if;
    raise notice '  OK    no puede tocar el documento acreditado de su perfil  (%)', split_part(sqlerrm, ':', 1);
  end;
end $$;

\echo ''
\echo '── 5 · Nadie muda un documento a otra entidad ──'

do $$
declare v_id uuid;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  select id into v_id from public.vigencias where entidad_id='C-001' limit 1;
  begin
    update public.vigencias set entidad_id = 'C-999' where id = v_id;
    raise exception 'FALLA: un documento cambió de dueño';
  exception when others then
    if sqlerrm like 'FALLA:%' then raise; end if;
    raise notice '  OK    un documento no cambia de dueño  (%)', split_part(sqlerrm, ':', 1);
  end;
end $$;

\echo ''
\echo '── 6 · El alta también se refleja, no solo la edición ──'

do $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  insert into public.operadores (id, propietario_id, nombre, doc_examen_medico, fecha_examen_medico)
  values ('OP-009', '11111111-1111-1111-1111-111111111111', 'Nuevo', 'o/med.pdf', '2026-06-01');

  select count(*) into n from public.vigencias
   where entidad_id='OP-009' and tipo_documento='examen_medico';
  if n <> 1 then raise exception 'FALLA: un alta no generó su fila (% filas)', n; end if;

  if public.vigencia_vence_el('examen_medico', '2026-06-01') <> '2027-06-01' then
    raise exception 'FALLA: la caducidad derivada del examen es incorrecta'; end if;
  raise notice '  OK    un INSERT también se refleja, y la caducidad se sigue derivando';
end $$;

\echo ''
\echo 'Todas las afirmaciones pasaron. Se revierte.'
rollback;
