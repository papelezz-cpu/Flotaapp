-- ════════════════════════════════════════════════════════════════════════
-- S-04 · El bucket `custodios` no tenía ninguna política: la licencia SEDENA
--        del custodio armado nunca se guardaba
-- ════════════════════════════════════════════════════════════════════════
--
-- El defecto (6ª auditoría, 2026-10-01). Ninguna de las políticas de
-- storage.objects menciona el bucket `custodios`. Con RLS encendido y sin
-- política que calce, toda subida se rechaza. js/admin.js (alta :1243,
-- edición :1325) hacía `if (!upErr) …` sin avisar, así que el custodio se
-- guardaba SIN su documento. Medido: 2 custodios «Armado» en producción, 0 con
-- doc_licencia_sedena; el bucket está vacío en las dos bases. Es el mismo
-- defecto que 20260930170000 corrigió para `documentos-empresa`.
--
-- Custodios está apagado en la interfaz (css/base.css, FLUJO-OPERATIVO.md
-- §«Custodios, patios y lavados están apagados»): hoy no afecta a nadie. Se
-- deja resuelto para cuando se encienda.
--
-- El arreglo, con el patrón de S-01 y S-05 (regla 44b):
--   · custodios_upload (INSERT): solo en la carpeta propia (`<uid>/…`) o
--     siendo superadmin, que da de alta custodios en nombre de una empresa
--     (_getPropietarioId en js/admin.js sube a la carpeta de esa empresa).
--   · custodios_read (SELECT): igual. El bucket es público y la app abre por
--     URL pública, que no pasa por RLS; esta política solo decide quién LISTA.
-- Sin DELETE ni UPDATE: nada borra estos archivos, y cada subida lleva un
-- timestamp en el nombre (upsert nunca choca con un objeto existente).
--
-- Solo CREA políticas: no había ninguna que reemplazar. Si ya existen (se
-- aplicó antes), no se tocan.
--
-- Reglas de docs/AUDITORIA.md §4: 2, 12, 16, 24, 44b.
-- ════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (select 1 from pg_policy where polrelid = 'storage.objects'::regclass
                  and polname = 'custodios_upload') then
    create policy custodios_upload on storage.objects
      for insert to authenticated
      with check (
        bucket_id = 'custodios'
        and (   (storage.foldername(name))[1] = (select auth.uid())::text
             or (select public.is_superadmin()))
      );
  end if;

  if not exists (select 1 from pg_policy where polrelid = 'storage.objects'::regclass
                  and polname = 'custodios_read') then
    create policy custodios_read on storage.objects
      for select to authenticated
      using (
        bucket_id = 'custodios'
        and (   (storage.foldername(name))[1] = (select auth.uid())::text
             or (select public.is_superadmin()))
      );
  end if;
end $$;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--
-- 1. Catálogo: las políticas del bucket son exactamente custodios_upload y
--    custodios_read, TO authenticated, atadas a la carpeta del dueño.
-- 2. Funcional, aunque el bucket esté vacío: una alta de prueba como
--    `authenticated` DENTRO de una subtransacción que se deshace entera. Solo
--    se escribe la fila de metadatos (nunca un archivo) y no sobrevive: no hay
--    que borrar nada, que es lo que storage.protect_delete impide en
--    producción.
--      a. la empresa sube a SU carpeta            → pasa
--      b. otra cuenta la lista                    → no la ve
--      c. la empresa la lista                     → la ve
--      d. el superadmin la lista                  → la ve
--      e. otra cuenta sube a la carpeta de la empresa → RLS la rechaza (42501)
--      f. el superadmin sube a la carpeta de la empresa → pasa
-- Como sabe fallar: sin las políticas, (a) se rechaza; con una lectura
-- abierta, (b) la ve.

do $$
declare
  v_emp    uuid;
  v_otro   uuid;
  v_sa     uuid;
  v_quien  text := current_user;
  v_fallos text[] := '{}';
  v_pol    record;
  v_n      int := 0;
  v_visto  int;
  v_msg    text;
  v_estado text;
  v_nombre text;
begin
  for v_pol in
    select polname, polcmd, polroles::regrole[]::text[] as roles,
           coalesce(pg_get_expr(polqual, polrelid), '') || ' ' ||
           coalesce(pg_get_expr(polwithcheck, polrelid), '') as expr
      from pg_policy
     where polrelid = 'storage.objects'::regclass
       and (coalesce(pg_get_expr(polqual, polrelid), '') ||
            coalesce(pg_get_expr(polwithcheck, polrelid), '')) like '%''custodios''%'
  loop
    v_n := v_n + 1;
    if v_pol.polname not in ('custodios_upload', 'custodios_read') then
      v_fallos := v_fallos || format('hay otra política sobre el bucket: %s', v_pol.polname);
    end if;
    if v_pol.roles <> array['authenticated'] then
      v_fallos := v_fallos || format('%s no es TO authenticated (%s)', v_pol.polname, v_pol.roles);
    end if;
    if v_pol.expr not like '%foldername%' or v_pol.expr not like '%auth.uid()%' then
      v_fallos := v_fallos || format('%s no está atada a la carpeta del dueño', v_pol.polname);
    end if;
  end loop;
  if v_n <> 2 then
    v_fallos := v_fallos || format('se esperaban 2 políticas sobre el bucket custodios y hay %s', v_n);
  end if;

  select user_id into v_emp  from public.perfiles where rol = 'admin' and aprobacion_cuenta is null order by created_at limit 1;
  select user_id into v_otro from public.perfiles where rol = 'cliente' order by created_at limit 1;
  select user_id into v_sa   from public.perfiles where rol = 'superadmin' order by created_at limit 1;
  if v_emp is null or v_otro is null or v_sa is null then
    raise exception 'S-04: hacen falta una empresa activa, un cliente y un superadmin para la prueba.';
  end if;
  v_nombre := v_emp || '/S04-PRUEBA/licencia_sedena_prueba.pdf';

  begin
    -- a. la empresa sube a su carpeta
    begin
      perform set_config('request.jwt.claim.sub', v_emp::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_emp, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      insert into storage.objects (bucket_id, name) values ('custodios', v_nombre);
      v_msg := 'PASO';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    end;
    perform set_config('role', v_quien, true);
    if v_msg <> 'PASO' then
      v_fallos := v_fallos || format('a. la empresa no pudo subir a su carpeta: %s %s', v_estado, v_msg);
    else
      -- b, c, d. quién la ve al listar
      perform set_config('request.jwt.claim.sub', v_otro::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      select count(*) into v_visto from storage.objects where bucket_id = 'custodios' and name = v_nombre;
      perform set_config('role', v_quien, true);
      if v_visto <> 0 then v_fallos := v_fallos || 'b. otra cuenta ve el archivo de la empresa'::text; end if;

      perform set_config('request.jwt.claim.sub', v_emp::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_emp, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      select count(*) into v_visto from storage.objects where bucket_id = 'custodios' and name = v_nombre;
      perform set_config('role', v_quien, true);
      if v_visto <> 1 then v_fallos := v_fallos || 'c. la empresa no ve su propio archivo'::text; end if;

      perform set_config('request.jwt.claim.sub', v_sa::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      select count(*) into v_visto from storage.objects where bucket_id = 'custodios' and name = v_nombre;
      perform set_config('role', v_quien, true);
      if v_visto <> 1 then v_fallos := v_fallos || 'd. el superadmin no ve el archivo'::text; end if;
    end if;

    -- e. otra cuenta sube a la carpeta de la empresa
    v_estado := null;
    begin
      perform set_config('request.jwt.claim.sub', v_otro::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      insert into storage.objects (bucket_id, name) values ('custodios', v_emp || '/S04-PRUEBA/ajeno.pdf');
      v_msg := 'PASO';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    end;
    perform set_config('role', v_quien, true);
    if v_msg = 'PASO' or v_estado <> '42501' then
      v_fallos := v_fallos || format('e. otra cuenta subió a la carpeta de la empresa o falló por otra causa: %s %s', v_estado, v_msg);
    end if;

    -- f. el superadmin sube a la carpeta de la empresa
    begin
      perform set_config('request.jwt.claim.sub', v_sa::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      insert into storage.objects (bucket_id, name) values ('custodios', v_emp || '/S04-PRUEBA/del_superadmin.pdf');
      v_msg := 'PASO';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    end;
    perform set_config('role', v_quien, true);
    if v_msg <> 'PASO' then
      v_fallos := v_fallos || format('f. el superadmin no pudo subir a la carpeta de la empresa: %s %s', v_estado, v_msg);
    end if;

    raise exception 'S04_FIN';
  exception when others then
    if sqlerrm <> 'S04_FIN' then
      raise exception 'S-04: la comprobación no pudo montar su prueba: %', sqlerrm;
    end if;
  end;

  perform set_config('role', v_quien, true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  if current_user <> v_quien then
    raise exception 'S-04: la comprobación dejó el rol en % (era %).', current_user, v_quien;
  end if;
  if exists (select 1 from storage.objects where bucket_id = 'custodios' and name like '%/S04-PRUEBA/%') then
    raise exception 'S-04: quedaron filas de prueba en storage.objects.';
  end if;
  if cardinality(v_fallos) > 0 then
    raise exception E'S-04: las políticas del bucket custodios no hacen lo que deben:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'S-04: bucket custodios por carpeta; la empresa sube y ve lo suyo, otra cuenta ni lo ve ni sube ahí, el superadmin ve y sube. 6 casos.';
end $$;
