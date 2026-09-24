-- Prueba de la Etapa 4 de H-04 (primer fichero: catalogo.js vía
-- empresas_publico, y el espejo devuelto a estricto), en banco local y
-- revertida.
--
--   psql -d portgo_h04 -v ON_ERROR_STOP=1 -f pruebas/banco-local/h04-etapa4.sql
--
-- Requiere las Etapas 1, 2, 3, 3b, 3c y 4 aplicadas al banco.
--
-- Lo que se persigue:
--   · que empresas_publico lea DE VERDAD vigencias y no perfiles — la prueba
--     decisiva es divergirlas a propósito y ver a cuál hace caso
--   · que una fila 'pendiente' NO se vea en el catálogo (la empresa propone;
--     hasta que no se acredita, el cliente no ve distintivo)
--   · que el corte no cambie lo que hoy se ve: mismas fechas antes y después
--   · que el espejo YA NO sea tolerante — un fallo suyo tumba la escritura de
--     origen, que es justo lo contrario de lo que probaba la 3b
--   · que anon siga sin poder leer la vista
--
-- Todo termina con un `rollback`: el banco queda intacto.

begin;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'empresa@ejemplo.mx'),
  ('99999999-9999-9999-9999-999999999999', 'sa@ejemplo.mx');

insert into public.perfiles (user_id, nombre, rol) values
  ('99999999-9999-9999-9999-999999999999', 'Super', 'superadmin'),
  ('11111111-1111-1111-1111-111111111111', 'Transportes Ejemplo', 'admin');


\echo ''
\echo '── 1 · El superadmin acredita y el catálogo lo ve ──'
-- Camino normal: aprobarDocsEmpresa() escribe las columnas reales de perfiles,
-- el espejo crea las filas 'vigente', y la vista las sirve.

do $$
declare v_sct date; v_rc date; n int;
begin
  perform set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
  update public.perfiles
     set doc_permiso_sct = 'u/sct.pdf',  fecha_vencimiento_permiso_sct = '2027-10-20',
         doc_seguro_rc   = 'u/rc.pdf',   fecha_vencimiento_seguro_rc   = '2027-11-21',
         doc_seguro_carga= 'u/carga.pdf',fecha_vencimiento_seguro_carga= '2027-12-22'
   where user_id = '11111111-1111-1111-1111-111111111111';

  select count(*) into n from public.vigencias
   where entidad_tipo = 'perfil' and estado = 'vigente';
  if n <> 3 then raise exception 'PREPARACION MAL: esperaba 3 filas vigentes, hay %', n; end if;

  select fecha_vencimiento_permiso_sct, fecha_vencimiento_seguro_rc
    into v_sct, v_rc
    from public.empresas_publico
   where user_id = '11111111-1111-1111-1111-111111111111';

  if v_sct <> '2027-10-20' or v_rc <> '2027-11-21' then
    raise exception 'FALLA: la vista no sirve las fechas acreditadas (sct=%, rc=%)', v_sct, v_rc;
  end if;
  raise notice '  OK    el catálogo ve las tres fechas acreditadas';
end $$;


\echo ''
\echo '── 2 · LA PRUEBA QUE IMPORTA: ¿a quién le hace caso la vista? ──'
-- Se divergen a propósito las dos fuentes: se borra la fila del espejo sin
-- tocar la columna de perfiles. Si la vista siguiera leyendo perfiles, aquí
-- seguiría enseñando la fecha y el cambio de esta etapa sería decorativo.

do $$
declare v_sct date; v_col date;
begin
  delete from public.vigencias
   where entidad_tipo = 'perfil' and tipo_documento = 'permiso_sct' and estado = 'vigente';

  select fecha_vencimiento_permiso_sct into v_col
    from public.perfiles where user_id = '11111111-1111-1111-1111-111111111111';
  if v_col is null then
    raise exception 'PREPARACION MAL: la columna vieja de perfiles debería seguir llena';
  end if;

  select fecha_vencimiento_permiso_sct into v_sct
    from public.empresas_publico
   where user_id = '11111111-1111-1111-1111-111111111111';

  if v_sct is not null then
    raise exception 'FALLA: la vista sigue leyendo perfiles (devolvió %) — la Etapa 4 no movió nada', v_sct;
  end if;
  raise notice '  OK    sin fila en vigencias la vista dice NULL, aunque perfiles conserve % — lee la tabla nueva', v_col;
end $$;


\echo ''
\echo '── 3 · Una propuesta (pendiente) no se ve en el catálogo ──'
-- La empresa propone; hasta que el superadmin no acredita, el cliente no debe
-- ver distintivo. Si la vista se olvidara del filtro estado='vigente', una
-- empresa se pondría la palomita sola, que es H-02 por la puerta de atrás.

do $$
declare v_sct date;
begin
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, archivo_path, fecha_documento, estado)
  values ('perfil', '11111111-1111-1111-1111-111111111111', 'permiso_sct', 'u/propuesta.pdf', '2099-01-01', 'pendiente');

  select fecha_vencimiento_permiso_sct into v_sct
    from public.empresas_publico
   where user_id = '11111111-1111-1111-1111-111111111111';

  if v_sct is not null then
    raise exception 'FALLA: una fila pendiente se ve en el catálogo (devolvió %) — la empresa se acreditaría sola', v_sct;
  end if;
  raise notice '  OK    la fila pendiente no asoma en el catálogo';
end $$;


\echo ''
\echo '── 4 · El espejo YA NO es tolerante ──'
-- En la 3b esto mismo terminaba con la escritura de origen guardada y una
-- divergencia anotada. Ahora tiene que fallar entera: el catálogo depende de
-- lo que el espejo escriba, así que un fallo callado sería un dato mal
-- mostrado a un cliente.

do $$
declare n int; v_msg text;
begin
  execute $f$
    create or replace function public.pruebas_romper_espejo() returns trigger
    language plpgsql as $b$
    begin
      if coalesce(new.tipo_documento, old.tipo_documento) = 'seguro_rc' then
        raise exception 'espejo roto a proposito';
      end if;
      return coalesce(new, old);
    end $b$ $f$;
  create trigger trg_pruebas_romper before insert or update or delete on public.vigencias
    for each row execute function public.pruebas_romper_espejo();

  begin
    perform set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
    update public.perfiles
       set fecha_vencimiento_seguro_rc = '2028-01-01'
     where user_id = '11111111-1111-1111-1111-111111111111';
    raise exception 'FALLA: la escritura de origen pasó pese al espejo roto — sigue siendo tolerante';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FALLA:%' then raise; end if;
    raise notice '  OK    el espejo tumbó la escritura de origen: %', v_msg;
  end;

  drop trigger trg_pruebas_romper on public.vigencias;

  -- Y la escritura no quedó a medias.
  select count(*) into n from public.perfiles
   where user_id = '11111111-1111-1111-1111-111111111111'
     and fecha_vencimiento_seguro_rc = '2028-01-01';
  if n <> 0 then
    raise exception 'FALLA: la fecha de origen se guardó igual — la transacción no revirtió';
  end if;
  raise notice '  OK    y la fecha de origen no se guardó: la transacción revirtió entera';
end $$;


\echo ''
\echo '── 5 · La vista sigue cerrada a anon ──'

do $$
begin
  if has_table_privilege('anon', 'public.empresas_publico', 'SELECT') then
    raise exception 'FALLA: anon puede leer empresas_publico';
  end if;
  if not has_table_privilege('authenticated', 'public.empresas_publico', 'SELECT') then
    raise exception 'FALLA: authenticated dejó de poder leer empresas_publico — el catálogo quedaría en blanco';
  end if;
  raise notice '  OK    anon fuera, authenticated dentro';
end $$;


\echo ''
\echo '   Etapa 4 (catalogo.js): la vista lee vigencias, ignora lo pendiente,'
\echo '   y el espejo volvió a ser estricto.'
\echo ''

rollback;
