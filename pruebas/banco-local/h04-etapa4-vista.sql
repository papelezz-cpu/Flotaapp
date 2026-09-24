-- Prueba de la vista `vigencias_caducidad` (H-04, etapa 4.7) en banco local,
-- revertida.
--
--   psql -d portgo_h04 -v ON_ERROR_STOP=1 -f pruebas/banco-local/h04-etapa4-vista.sql
--
-- Requiere las etapas 1, 2, 3, 3b, 3c, 4 y 4.7 aplicadas al banco.
--
-- Lo que se persigue, y por qué cada cosa:
--
--   · que `vence_el` aplique la regla del catálogo: los tipos sin
--     `vigencia_meses` devuelven la fecha capturada, y los de 12 meses le
--     suman un año. Es lo que permite dejar de restar 335 días en JavaScript.
--   · que cambiar el catálogo cambie la caducidad SIN migración — el beneficio
--     que justifica H-04 entero.
--   · **que la RLS siga aplicándose a través de la vista.** Esto es lo que no
--     se puede probar con `postgres`, que se la salta: hace falta un rol de
--     verdad. Si esta vista se hubiera creado con security_invoker=false,
--     cualquier empresa vería los documentos de las demás.
--
-- Todo termina con un `rollback`.

begin;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'una@ejemplo.mx'),
  ('22222222-2222-2222-2222-222222222222', 'otra@ejemplo.mx'),
  ('99999999-9999-9999-9999-999999999999', 'sa@ejemplo.mx');

insert into public.perfiles (user_id, nombre, rol) values
  ('99999999-9999-9999-9999-999999999999', 'Super', 'superadmin'),
  ('11111111-1111-1111-1111-111111111111', 'Transportes Una', 'admin'),
  ('22222222-2222-2222-2222-222222222222', 'Transportes Otra', 'admin');

insert into public.operadores (id, propietario_id, nombre, curp, num_licencia) values
  ('OP-UNA', '11111111-1111-1111-1111-111111111111', 'Chofer Una', 'AAAA000101HDFAAA01', 'L-1'),
  ('OP-OTRA','22222222-2222-2222-2222-222222222222', 'Chofer Otra','BBBB000101HDFBBB02', 'L-2');

-- El dueño de cada operador le pone licencia (caducidad directa) y examen
-- médico (caducidad derivada, +12 meses).
do $$
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  update public.operadores
     set foto_licencia = 'u/l1.pdf',      fecha_vencimiento   = '2027-05-10',
         doc_examen_medico = 'u/m1.pdf',  fecha_examen_medico = '2026-03-01'
   where id = 'OP-UNA';

  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  update public.operadores
     set foto_licencia = 'u/l2.pdf',      fecha_vencimiento   = '2028-09-09'
   where id = 'OP-OTRA';
end $$;


\echo ''
\echo '── 1 · vence_el aplica la regla del catálogo ──'

do $$
declare v_lic date; v_med date;
begin
  select vence_el into v_lic from public.vigencias_caducidad
   where entidad_id = 'OP-UNA' and tipo_documento = 'licencia';
  select vence_el into v_med from public.vigencias_caducidad
   where entidad_id = 'OP-UNA' and tipo_documento = 'examen_medico';

  -- licencia: vigencia_meses null -> la fecha capturada ES la caducidad
  if v_lic <> '2027-05-10' then
    raise exception 'FALLA: licencia capturada 2027-05-10 deberia vencer ese mismo dia, dice %', v_lic;
  end if;
  raise notice '  OK    licencia: capturada 2027-05-10 -> vence 2027-05-10 (sin derivar)';

  -- examen médico: vigencia_meses 12 -> +1 año
  if v_med <> '2027-03-01' then
    raise exception 'FALLA: examen del 2026-03-01 con regla de 12 meses deberia vencer 2027-03-01, dice %', v_med;
  end if;
  raise notice '  OK    examen medico: capturado 2026-03-01 -> vence 2027-03-01 (+12 meses)';
end $$;


\echo ''
\echo '── 2 · Cambiar el catálogo cambia la caducidad, sin migración ──'
-- Es el beneficio que justifica H-04: «subir el examen médico de 12 a 24 meses
-- es un UPDATE a una fila de catálogo, no una migración».

do $$
declare v_med date;
begin
  update public.catalogos set meta = jsonb_set(meta, '{vigencia_meses}', '24')
   where clave = 'vigencia_tipo' and valor = 'examen_medico';

  select vence_el into v_med from public.vigencias_caducidad
   where entidad_id = 'OP-UNA' and tipo_documento = 'examen_medico';
  if v_med <> '2028-03-01' then
    raise exception 'FALLA: con la regla a 24 meses deberia vencer 2028-03-01, dice %', v_med;
  end if;
  raise notice '  OK    catalogo a 24 meses -> el mismo examen vence 2028-03-01, sin tocar datos ni codigo';

  update public.catalogos set meta = jsonb_set(meta, '{vigencia_meses}', '12')
   where clave = 'vigencia_tipo' and valor = 'examen_medico';
end $$;


\echo ''
\echo '── 3 · LA PRUEBA QUE IMPORTA: la RLS sigue aplicándose por la vista ──'
-- `postgres` se salta RLS, así que aquí se cambia a un rol de verdad. Sin esto
-- la vista podría estar con security_invoker=false y nadie se enteraría hasta
-- que una empresa viera los papeles de otra en producción.

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$
declare n_propias int; n_ajenas int;
begin
  select count(*) into n_propias from public.vigencias_caducidad where entidad_id = 'OP-UNA';
  select count(*) into n_ajenas  from public.vigencias_caducidad where entidad_id = 'OP-OTRA';

  if n_propias = 0 then
    raise exception 'FALLA: la empresa no ve sus PROPIOS documentos por la vista; el panel saldria vacio';
  end if;
  raise notice '  OK    ve sus % documentos propios', n_propias;

  if n_ajenas <> 0 then
    raise exception 'FALLA GRAVE: la empresa ve % documentos de OTRA empresa por la vista. security_invoker esta en false.', n_ajenas;
  end if;
  raise notice '  OK    y 0 de la otra empresa: la RLS de vigencias sigue mandando';
end $$;

-- Y que tampoco pueda escribir por la vista.
do $$
begin
  begin
    update public.vigencias_caducidad set fecha_documento = '2099-01-01' where entidad_id = 'OP-UNA';
    raise exception 'FALLA: se pudo ESCRIBIR por la vista';
  exception when insufficient_privilege then
    raise notice '  OK    escribir por la vista: denegado por privilegios';
  when others then
    if sqlerrm like 'FALLA:%' then raise; end if;
    raise notice '  OK    escribir por la vista: rechazado (%)', sqlerrm;
  end;
end $$;

reset role;


\echo ''
\echo '── 4 · El superadmin sí ve las dos empresas ──'

set local role authenticated;
set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';

do $$
declare n int;
begin
  select count(*) into n from public.vigencias_caducidad
   where entidad_id in ('OP-UNA', 'OP-OTRA');
  if n < 3 then
    raise exception 'FALLA: el superadmin solo ve % filas de las 3 sembradas; el panel global quedaria incompleto', n;
  end if;
  raise notice '  OK    el superadmin ve las % filas de las dos empresas', n;
end $$;

reset role;

\echo ''
\echo '   Vista 4.7: la caducidad sale del catalogo y la RLS sigue en pie.'
\echo ''

rollback;
