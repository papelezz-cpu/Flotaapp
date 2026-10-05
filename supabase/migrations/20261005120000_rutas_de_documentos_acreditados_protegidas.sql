-- ════════════════════════════════════════════════════════════════════════
-- S-12 · Una empresa sin acreditar podía crearse una fila «vigente» en
--        vigencias escribiendo la ruta de un documento
-- ════════════════════════════════════════════════════════════════════════
--
-- El defecto (6ª auditoría, ejecutado en banco local el 2026-10-01). Los dos
-- guards de perfiles protegen la acreditación de la empresa (H-02, Q-01):
-- fechas de vigencia, booleanos y número de permiso. Pero NO las rutas de los
-- tres documentos acreditados: doc_permiso_sct, doc_seguro_rc,
-- doc_seguro_carga. Al escribir una, vigencias_espejo() inserta la fila como
-- `vigente`, y el guard de vigencias solo vigila UPDATE. Medido: una empresa
-- sin acreditar escribió doc_seguro_rc y obtuvo una fila `vigente` sin fecha.
-- Sin fecha no pinta distintivo en el catálogo (empresas_publico mira la
-- fecha), pero sí aparece en vigencias_caducidad, que lee el superadmin.
--
-- Los dos huecos:
--   · guard_perfil_self_update (UPDATE): no compara las tres rutas.
--   · guard_perfil_insert (Q-01, alta): tampoco; una cuenta nueva podía nacer
--     con la ruta puesta y el espejo le creaba la fila al insertarse.
--
-- Quién escribe esas tres columnas de forma legítima, inventariado el 05/10:
-- solo aprobarDocsEmpresa() (js/aprobaciones.js), que corre como superadmin y
-- sale de los dos guards antes de llegar aquí. La empresa propone en las
-- columnas *_pendiente, que siguen abiertas. Ni Android, ni las Edge
-- Functions, ni el registro (auth.js) escriben las rutas acreditadas.
-- En el volcado de producción del 28/09 no hay ninguna ruta acreditada
-- autodeclarada: no hay datos que limpiar.
--
-- El arreglo: las tres rutas se suman a la condición que ya protege las
-- fechas, en los dos guards. Mismo mensaje de error.
--
-- Ninguna función se reescribe a mano (regla 3; R-11): se inserta sobre la
-- definición viva de cada una, y la comprobación verifica que solo cambió eso.
-- Si un punto de anclaje no aparece exactamente una vez, no se toca nada.
--
-- Reglas de docs/AUDITORIA.md §4: 2, 3, 15, 16.
-- ════════════════════════════════════════════════════════════════════════


create temporary table s12_antes on commit drop as
  select 'upd'::text as cual,
         pg_get_functiondef('public.guard_perfil_self_update()'::regprocedure) as def,
         false as ya_estaba, null::text as esperado
  union all
  select 'ins',
         pg_get_functiondef('public.guard_perfil_insert()'::regprocedure),
         false, null;

do $$
declare
  v_def   text;
  v_n     int;
  v_upd_ancla constant text :=
    'OR NEW.fecha_vencimiento_seguro_carga IS DISTINCT FROM OLD.fecha_vencimiento_seguro_carga THEN';
  v_upd_nuevo constant text :=
       'OR NEW.fecha_vencimiento_seguro_carga IS DISTINCT FROM OLD.fecha_vencimiento_seguro_carga' || E'\n'
    || '     -- S-12 (20261005120000): tampoco la ruta del documento acreditado.' || E'\n'
    || '     OR NEW.doc_permiso_sct  IS DISTINCT FROM OLD.doc_permiso_sct' || E'\n'
    || '     OR NEW.doc_seguro_rc    IS DISTINCT FROM OLD.doc_seguro_rc' || E'\n'
    || '     OR NEW.doc_seguro_carga IS DISTINCT FROM OLD.doc_seguro_carga THEN';
  v_ins_ancla constant text :=
    'or new.fecha_vencimiento_seguro_carga is not null then';
  v_ins_nuevo constant text :=
       'or new.fecha_vencimiento_seguro_carga is not null' || E'\n'
    || '     -- S-12 (20261005120000): tampoco la ruta del documento acreditado.' || E'\n'
    || '     or new.doc_permiso_sct  is not null' || E'\n'
    || '     or new.doc_seguro_rc    is not null' || E'\n'
    || '     or new.doc_seguro_carga is not null then';
begin
  -- guard_perfil_self_update
  select def into v_def from s12_antes where cual = 'upd';
  if position('S-12 (20261005120000)' in v_def) > 0 then
    update s12_antes set ya_estaba = true where cual = 'upd';
  else
    v_n := (length(v_def) - length(replace(v_def, v_upd_ancla, ''))) / length(v_upd_ancla);
    if v_n <> 1 then
      raise exception 'S-12: guard_perfil_self_update() tiene % veces el punto de anclaje (se esperaba 1). No se toca.', v_n;
    end if;
    v_def := replace(v_def, v_upd_ancla, v_upd_nuevo);
    update s12_antes set esperado = v_def where cual = 'upd';
    execute v_def;
  end if;

  -- guard_perfil_insert
  select def into v_def from s12_antes where cual = 'ins';
  if position('S-12 (20261005120000)' in v_def) > 0 then
    update s12_antes set ya_estaba = true where cual = 'ins';
  else
    v_n := (length(v_def) - length(replace(v_def, v_ins_ancla, ''))) / length(v_ins_ancla);
    if v_n <> 1 then
      raise exception 'S-12: guard_perfil_insert() tiene % veces el punto de anclaje (se esperaba 1). No se toca.', v_n;
    end if;
    v_def := replace(v_def, v_ins_ancla, v_ins_nuevo);
    update s12_antes set esperado = v_def where cual = 'ins';
    execute v_def;
  end if;
end $$;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--
-- Cada caso en su propia subtransacción que termina en excepción: ninguna
-- fila sobrevive.
--
--   UPDATE, como una empresa activa SIN acreditar:
--     1. doc_seguro_rc                     → rechazo (S-12)
--     2. doc_permiso_sct                   → rechazo (S-12)
--     3. doc_seguro_rc_pendiente + fecha   → pasa (es donde propone)
--   UPDATE, como superadmin:
--     4. doc_seguro_rc                     → pasa (aprobarDocsEmpresa)
--   INSERT de un perfil con uid inventado (método de Q-01: si el guard deja
--   pasar, la FK hacia auth.users da 23503; si lo frena, P0001):
--     5. admin pendiente con doc_seguro_rc → rechazo (P0001)
--     6. admin pendiente sin rutas         → pasa (llega a la FK, 23503)
--
-- Como sabe fallar: sin el cambio, 1, 2 y 5 pasan.

do $$
declare
  v_quien  text := current_user;
  v_fallos text[] := '{}';
  v_emp    uuid;
  v_sa     uuid;
  v_uid    uuid;
  v_r      record;
  v_casos  text[];
  v_quienc text[];
  v_debe   text[];
  v_i      int;
  v_msg    text;
  v_estado text;
begin
  -- Solo cambió lo insertado, en las dos funciones.
  for v_r in select * from s12_antes loop
    if not v_r.ya_estaba and pg_get_functiondef(
         case v_r.cual when 'upd' then 'public.guard_perfil_self_update()'::regprocedure
                       else 'public.guard_perfil_insert()'::regprocedure end)
       is distinct from v_r.esperado then
      raise exception 'S-12: % no quedó como se construyó (cambió en algo más que el bloque nuevo).', v_r.cual;
    end if;
  end loop;
  if position('S-12 (20261005120000)' in pg_get_functiondef('public.guard_perfil_self_update()'::regprocedure)) = 0
  or position('S-12 (20261005120000)' in pg_get_functiondef('public.guard_perfil_insert()'::regprocedure)) = 0 then
    raise exception 'S-12: falta el bloque nuevo en alguno de los dos guards.';
  end if;
  if has_function_privilege('authenticated', 'public.guard_perfil_self_update()', 'EXECUTE')
  or has_function_privilege('authenticated', 'public.guard_perfil_insert()', 'EXECUTE')
  or has_function_privilege('anon', 'public.guard_perfil_self_update()', 'EXECUTE')
  or has_function_privilege('anon', 'public.guard_perfil_insert()', 'EXECUTE') then
    raise exception 'S-12: algún guard quedó ejecutable por anon o authenticated.';
  end if;

  -- Una empresa activa sin documentos acreditados, y un superadmin.
  select user_id into v_emp from public.perfiles
   where rol = 'admin' and aprobacion_cuenta is null
     and docs_aprobados_en is null
     and doc_permiso_sct is null and doc_seguro_rc is null and doc_seguro_carga is null
   order by created_at limit 1;
  select user_id into v_sa from public.perfiles where rol = 'superadmin' order by created_at limit 1;
  if v_emp is null or v_sa is null then
    raise exception 'S-12: hace falta una empresa activa sin documentos acreditados y un superadmin para la prueba.';
  end if;

  -- 1..4: UPDATE
  v_casos  := array[
    'doc_seguro_rc = user_id || ''/s12_autodeclarado.pdf''',
    'doc_permiso_sct = user_id || ''/s12_autodeclarado.pdf''',
    'doc_seguro_rc_pendiente = user_id || ''/s12_propuesta.pdf'', fecha_vencimiento_seguro_rc_pendiente = current_date + 300',
    'doc_seguro_rc = user_id || ''/s12_aprobado.pdf'''];
  v_quienc := array['emp', 'emp', 'emp', 'sa'];
  v_debe   := array['rechazo', 'rechazo', 'pasa', 'pasa'];

  for v_i in 1 .. 4 loop
    v_uid := case v_quienc[v_i] when 'emp' then v_emp else v_sa end;
    begin
      perform set_config('request.jwt.claim.sub', v_uid::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      execute format('update public.perfiles set %s where user_id = %L', v_casos[v_i], v_emp);
      raise exception 'S12_PASO';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    end;
    perform set_config('role', v_quien, true);

    if v_debe[v_i] = 'rechazo' and not (v_estado = 'P0001' and v_msg like 'No autorizado:%') then
      v_fallos := v_fallos || format('caso %s (%s, %s) debía rechazarse: %s %s', v_i, v_quienc[v_i], v_casos[v_i], v_estado, v_msg);
    elsif v_debe[v_i] = 'pasa' and v_msg <> 'S12_PASO' then
      v_fallos := v_fallos || format('caso %s (%s, %s) debía pasar: %s %s', v_i, v_quienc[v_i], v_casos[v_i], v_estado, v_msg);
    end if;
  end loop;

  -- 5..6: INSERT con uid inventado
  for v_i in 5 .. 6 loop
    v_uid := gen_random_uuid();
    begin
      perform set_config('request.jwt.claim.sub', v_uid::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      if v_i = 5 then
        insert into public.perfiles (user_id, nombre, rol, aprobacion_cuenta, doc_seguro_rc)
        values (v_uid, 's12', 'admin', 'pendiente', v_uid || '/s12_alta.pdf');
      else
        insert into public.perfiles (user_id, nombre, rol, aprobacion_cuenta)
        values (v_uid, 's12', 'admin', 'pendiente');
      end if;
      raise exception 'S12_SENTINELA';   -- no debería llegar: la FK tendría que saltar
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    end;
    perform set_config('role', v_quien, true);

    if v_i = 5 and not (v_estado = 'P0001' and v_msg like 'No autorizado:%') then
      v_fallos := v_fallos || format('caso 5 (alta con doc_seguro_rc) debía rechazarse: %s %s', v_estado, v_msg);
    elsif v_i = 6 and v_estado <> '23503' then
      v_fallos := v_fallos || format('caso 6 (alta sin rutas) debía llegar a la FK: %s %s', v_estado, v_msg);
    end if;
  end loop;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  if current_user <> v_quien then
    raise exception 'S-12: la comprobación dejó el rol en % (era %).', current_user, v_quien;
  end if;
  if exists (select 1 from public.perfiles where doc_seguro_rc like '%/s12\_%' escape '\'
                                             or doc_permiso_sct like '%/s12\_%' escape '\'
                                             or doc_seguro_rc_pendiente like '%/s12\_%' escape '\')
  or exists (select 1 from public.vigencias where archivo_path like '%/s12\_%' escape '\') then
    raise exception 'S-12: quedaron datos de prueba sin deshacer.';
  end if;
  if cardinality(v_fallos) > 0 then
    raise exception E'S-12: los guards no hacen lo que deben:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'S-12: las rutas de los documentos acreditados solo las escribe el superadmin, al alta y al actualizar; 6 casos, todos como se esperaba.';
end $$;
