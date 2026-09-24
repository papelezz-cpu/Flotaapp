-- Prueba de la Etapa 1 de H-04 contra un banco local, en una transacción que
-- se revierte. No toca ninguna base real.
--
-- Cada afirmación se escribe como «esto DEBE pasar» y la prueba falla si no
-- pasa — incluidas las que deben ser rechazadas, que son las que importan:
-- una restricción que no se prueba por el lado que rechaza no está probada.
--
--   psql -d portgo_h04 -v ON_ERROR_STOP=1 -f pruebas/banco-local/h04-etapa1.sql

begin;

create or replace function pg_temp.debe_fallar(p_sql text, p_que text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice '  OK    %  (%)', p_que, split_part(sqlerrm, ':', 1);
    return;
  end;
  raise exception 'FALLA: % — se aceptó y debía rechazarse', p_que;
end $$;

create or replace function pg_temp.debe_pasar(p_sql text, p_que text)
returns void language plpgsql as $$
begin
  execute p_sql;
  raise notice '  OK    %', p_que;
end $$;

\echo ''
\echo '── 1 · Lo que debe entrar ──'

select pg_temp.debe_pasar($$
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, archivo_path, fecha_documento)
  values ('perfil','11111111-1111-1111-1111-111111111111','seguro_rc','p/x.pdf','2027-01-01')
$$, 'un seguro de perfil, con papel y fecha');

select pg_temp.debe_pasar($$
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, fecha_documento)
  values ('operador','OP-001','examen_medico','2026-03-01')
$$, 'un examen médico SIN papel (solo fecha)');

select pg_temp.debe_pasar($$
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, archivo_path, estado)
  values ('camion','C-001','verificacion','u/v.pdf','pendiente')
$$, 'una propuesta SIN fecha (solo papel)');

\echo ''
\echo '── 2 · Lo que NO debe entrar ──'

select pg_temp.debe_fallar($$
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, fecha_documento)
  values ('camion','C-002','seguro_rc','2027-01-01')
$$, 'un tipo de perfil colgado de un camión');

select pg_temp.debe_fallar($$
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, fecha_documento)
  values ('camion','C-003','documento_inventado','2027-01-01')
$$, 'un tipo que no está en el catálogo');

select pg_temp.debe_fallar($$
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento)
  values ('patio','PAT-001','permiso_patio')
$$, 'una fila sin papel y sin fecha');

select pg_temp.debe_fallar($$
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, fecha_documento, estado)
  values ('patio','PAT-002','permiso_patio','2027-01-01','rechazado')
$$, 'un rechazo sin motivo');

select pg_temp.debe_fallar($$
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, fecha_documento, estado)
  values ('patio','PAT-003','permiso_patio','2027-01-01','archivado')
$$, 'un estado que no existe');

select pg_temp.debe_fallar($$
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, fecha_documento)
  values ('almacen','X-1','permiso_patio','2027-01-01')
$$, 'una entidad que no existe');

\echo ''
\echo '── 3 · Uno vigente y uno pendiente, no dos de lo mismo ──'

select pg_temp.debe_fallar($$
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, fecha_documento)
  values ('perfil','11111111-1111-1111-1111-111111111111','seguro_rc','2028-01-01')
$$, 'un segundo seguro VIGENTE del mismo perfil');

select pg_temp.debe_pasar($$
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, fecha_documento, estado)
  values ('perfil','11111111-1111-1111-1111-111111111111','seguro_rc','2028-01-01','pendiente')
$$, 'una renovación PENDIENTE junto a la vigente');

select pg_temp.debe_fallar($$
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, fecha_documento, estado)
  values ('perfil','11111111-1111-1111-1111-111111111111','seguro_rc','2029-01-01','pendiente')
$$, 'una SEGUNDA pendiente del mismo documento');

select pg_temp.debe_pasar($$
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, fecha_documento, estado, nota_rechazo)
  values ('perfil','11111111-1111-1111-1111-111111111111','seguro_rc','2025-01-01','rechazado','ilegible')
$$, 'varios rechazados, que son historial');

\echo ''
\echo '── 4 · La regla de vigencia vive en el catálogo ──'

do $$
declare v date;
begin
  v := public.vigencia_vence_el('seguro_rc', '2027-01-01');
  if v <> '2027-01-01' then raise exception 'FALLA: seguro_rc debía vencer el día capturado, dio %', v; end if;
  raise notice '  OK    seguro_rc: la fecha capturada ES la caducidad (%)', v;

  v := public.vigencia_vence_el('examen_medico', '2026-03-01');
  if v <> '2027-03-01' then raise exception 'FALLA: examen_medico debía vencer a los 12 meses, dio %', v; end if;
  raise notice '  OK    examen_medico: 12 meses desde la captura (%)', v;

  -- Y lo que de verdad justifica el diseño: cambiar la regla es un UPDATE.
  update public.catalogos set meta = jsonb_set(meta, '{vigencia_meses}', '24')
   where clave = 'vigencia_tipo' and valor = 'examen_medico';
  v := public.vigencia_vence_el('examen_medico', '2026-03-01');
  if v <> '2028-03-01' then raise exception 'FALLA: tras subir la regla a 24 meses dio %', v; end if;
  raise notice '  OK    subir la vigencia a 24 meses NO fue una migración (%)', v;
end $$;

\echo ''
\echo '── 5 · El guard: una empresa no se acredita sola ──'

do $$
declare v_id uuid;
begin
  select id into v_id from public.vigencias
   where estado = 'pendiente' and tipo_documento = 'verificacion';

  -- Sin sesión de superadmin, is_superadmin() es falso en este banco.
  begin
    update public.vigencias set estado = 'vigente' where id = v_id;
    raise exception 'FALLA: una empresa pudo acreditarse sola';
  exception when others then
    if sqlerrm like 'FALLA:%' then raise; end if;
    raise notice '  OK    no puede pasar su propia propuesta a vigente  (%)', split_part(sqlerrm, ':', 1);
  end;

  begin
    update public.vigencias set revisado_por = '22222222-2222-2222-2222-222222222222' where id = v_id;
    raise exception 'FALLA: una empresa pudo firmar la revisión';
  exception when others then
    if sqlerrm like 'FALLA:%' then raise; end if;
    raise notice '  OK    no puede firmar la revisión  (%)', split_part(sqlerrm, ':', 1);
  end;

  select id into v_id from public.vigencias
   where estado = 'vigente' and tipo_documento = 'seguro_rc';
  begin
    update public.vigencias set fecha_documento = '2099-01-01' where id = v_id;
    raise exception 'FALLA: una empresa pudo mover la fecha de un documento acreditado';
  exception when others then
    if sqlerrm like 'FALLA:%' then raise; end if;
    raise notice '  OK    no puede tocar un documento ya acreditado  (%)', split_part(sqlerrm, ':', 1);
  end;

  -- Y lo que SÍ debe poder: corregir su propia propuesta pendiente.
  select id into v_id from public.vigencias
   where estado = 'pendiente' and tipo_documento = 'verificacion';
  update public.vigencias set archivo_path = 'u/v2.pdf' where id = v_id;
  raise notice '  OK    SÍ puede corregir el papel de su propuesta pendiente';
end $$;

\echo ''
\echo '── 6 · anon no entra ──'

do $$
begin
  if has_table_privilege('anon', 'public.vigencias', 'SELECT') then
    raise exception 'FALLA: anon puede leer vigencias';
  end if;
  raise notice '  OK    anon no tiene SELECT sobre vigencias';
end $$;

\echo ''
\echo 'Todas las afirmaciones pasaron. Se revierte: el banco queda como estaba.'
rollback;
