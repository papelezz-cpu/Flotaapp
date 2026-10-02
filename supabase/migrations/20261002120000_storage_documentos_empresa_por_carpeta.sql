-- ════════════════════════════════════════════════════════════════════════
-- S-05 · Las pólizas y permisos de las empresas se listaban con cualquier
--        cuenta
-- ════════════════════════════════════════════════════════════════════════
--
-- El defecto (6ª auditoría, 2026-10-01). `20260930170000` arregló la subida
-- al bucket `documentos-empresa`, que estaba rota, y de paso abrió el listado:
--
--   docempresa_read   FOR SELECT TO public   USING (bucket_id = 'documentos-empresa')
--
-- Un bucket público sirve sus URL sin pasar por RLS, así que esta política no
-- hace falta para abrir un archivo: solo decide quién puede LISTAR el bucket
-- entero (regla 44b). Medido en pruebas el 01/10 con la cuenta de cliente: el
-- listado devolvía las pólizas subidas por las empresas. Es S-01 en otro
-- bucket. En producción el bucket estaba vacío el 02/10: no se ha expuesto
-- nada todavía, pero la primera póliza que suba una empresa lo estaría.
--
-- El arreglo: listar solo la carpeta propia (`<uid>/…`, el prefijo con el que
-- sube solicitarActualizacionDocs() en js/admin.js) o siendo superadmin.
-- `docempresa_upload` ya estaba atada a la carpeta propia y NO se toca.
--
-- Lo que no cambia: las URL públicas que guarda `perfiles.doc_*` siguen
-- abriendo (el bucket sigue siendo público). Ni la web ni Android listan este
-- bucket; Android ni siquiera lo usa (BUCKET_EMPRESA declarada, sin llamadas).
--
-- ⚠ Reescribir una política es DROP + CREATE: Regla #1 de CLAUDE.md. Va en la
--   misma transacción, así que no hay un instante sin política.
--
-- Reglas de docs/AUDITORIA.md §4: 2, 12, 16, 44, 44b.
-- ════════════════════════════════════════════════════════════════════════

drop policy if exists docempresa_read on storage.objects;

create policy docempresa_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documentos-empresa'
    and (   (storage.foldername(name))[1] = (select auth.uid())::text
         or (select public.is_superadmin()))
  );


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--
-- 1. Catálogo, siempre: las dos políticas del bucket son TO authenticated y
--    están atadas a la carpeta del dueño. Con la política vieja, falla.
-- 2. Prueba funcional, solo si el bucket tiene archivos (solo lectura: en
--    producción storage.protect_delete impide borrar filas por SQL):
--    un perfil sin archivos ve 0, el dueño con más archivos ve los suyos,
--    un superadmin ve todos. Si el bucket está vacío no hay nada que contar,
--    y el aviso final lo dice en vez de presumir una prueba que no corrió.

do $$
declare
  v_total    int;
  v_dueno    uuid;
  v_suyos    int;
  v_ajeno    uuid;
  v_sa       uuid;
  v_visto    int;
  v_quien    text := current_user;
  v_fallos   text[] := '{}';
  v_pol      record;
  v_n        int := 0;
begin
  for v_pol in
    select polname, polroles::regrole[]::text[] as roles,
           coalesce(pg_get_expr(polqual, polrelid), '') || ' ' ||
           coalesce(pg_get_expr(polwithcheck, polrelid), '') as expr
      from pg_policy
     where polrelid = 'storage.objects'::regclass
       and (coalesce(pg_get_expr(polqual, polrelid), '') ||
            coalesce(pg_get_expr(polwithcheck, polrelid), '')) like '%''documentos-empresa''%'
  loop
    v_n := v_n + 1;
    if v_pol.roles <> array['authenticated'] then
      v_fallos := v_fallos || format('%s no es TO authenticated (%s)', v_pol.polname, v_pol.roles);
    end if;
    if v_pol.expr not like '%foldername%' or v_pol.expr not like '%auth.uid()%' then
      v_fallos := v_fallos || format('%s no está atada a la carpeta del dueño', v_pol.polname);
    end if;
  end loop;
  if v_n = 0 or not exists (select 1 from pg_policy
                             where polrelid = 'storage.objects'::regclass
                               and polname = 'docempresa_read' and polcmd = 'r') then
    v_fallos := v_fallos || 'no está la política docempresa_read (SELECT)'::text;
  end if;

  select count(*) into v_total from storage.objects where bucket_id = 'documentos-empresa';

  if v_total > 0 then
    select p.user_id, count(*) into v_dueno, v_suyos
      from storage.objects o
      join public.perfiles p on p.user_id::text = (storage.foldername(o.name))[1]
     where o.bucket_id = 'documentos-empresa' and p.rol <> 'superadmin'
     group by p.user_id order by count(*) desc limit 1;
    select p.user_id into v_ajeno
      from public.perfiles p
     where p.rol <> 'superadmin'
       and not exists (select 1 from storage.objects o
                        where o.bucket_id = 'documentos-empresa'
                          and (storage.foldername(o.name))[1] = p.user_id::text)
     order by p.created_at limit 1;
    select user_id into v_sa from public.perfiles where rol = 'superadmin' order by created_at limit 1;
    if v_ajeno is null or v_sa is null then
      raise exception 'S-05: faltan perfiles para la prueba (perfil sin archivos %, superadmin %).', v_ajeno, v_sa;
    end if;

    perform set_config('request.jwt.claim.sub', v_ajeno::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ajeno, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    select count(*) into v_visto from storage.objects where bucket_id = 'documentos-empresa';
    perform set_config('role', v_quien, true);
    if v_visto <> 0 then
      v_fallos := v_fallos || format('un perfil sin archivos ve %s de %s', v_visto, v_total);
    end if;

    if v_dueno is not null then
      perform set_config('request.jwt.claim.sub', v_dueno::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_dueno, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      select count(*) into v_visto from storage.objects where bucket_id = 'documentos-empresa';
      perform set_config('role', v_quien, true);
      if v_visto <> v_suyos then
        v_fallos := v_fallos || format('el dueño ve %s, tiene %s', v_visto, v_suyos);
      end if;
    end if;

    perform set_config('request.jwt.claim.sub', v_sa::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    select count(*) into v_visto from storage.objects where bucket_id = 'documentos-empresa';
    perform set_config('role', v_quien, true);
    if v_visto <> v_total then
      v_fallos := v_fallos || format('el superadmin ve %s de %s', v_visto, v_total);
    end if;

    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
  end if;

  if current_user <> v_quien then
    raise exception 'S-05: la comprobación dejó el rol en % (era %).', current_user, v_quien;
  end if;
  if cardinality(v_fallos) > 0 then
    raise exception E'S-05: las políticas no hacen lo que deben:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  if v_total > 0 then
    raise notice 'S-05: documentos-empresa por carpeta; % archivos, el perfil sin archivos ve 0, el dueño ve sus %, el superadmin ve todos.',
      v_total, coalesce(v_suyos, 0);
  else
    raise notice 'S-05: documentos-empresa por carpeta (catálogo comprobado). El bucket está VACÍO: la prueba funcional no corrió aquí.';
  end if;
end $$;
