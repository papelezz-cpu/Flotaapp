-- ════════════════════════════════════════════════════════════════════════
-- S-01 · Los documentos de los choferes se listaban y se borraban con
--        cualquier cuenta
-- ════════════════════════════════════════════════════════════════════════
--
-- El defecto (6ª auditoría, 2026-10-01). Las tres políticas del bucket
-- `operadores` miraban solo el bucket, nunca la carpeta del dueño:
--
--   operadores_read    FOR SELECT  (sin TO → public)  bucket_id = 'operadores'
--   operadores_upload  FOR INSERT  TO authenticated   bucket_id = 'operadores'
--   operadores_delete  FOR DELETE  TO authenticated   bucket_id = 'operadores'
--
-- Medido en portgo-pruebas el 01/10 con la cuenta de cliente de pruebas: el
-- listado devolvió 98 archivos de 4 empresas — fotos, licencias, examen
-- toxicológico, examen médico y carta de antecedentes de cada chofer. Son
-- datos personales SENSIBLES (LFPDPPP); la constancia `datos_sensibles_
-- operador` existe por eso. Y cualquier cuenta con sesión podía BORRARLOS.
-- Sin sesión no: anon no tiene privilegio sobre storage.objects (403, medido).
--
-- El arreglo: las tres operaciones, solo sobre la carpeta propia
-- (`<uid>/…`, que es el prefijo con el que suben la web —js/operadores.js—
-- y Android —StorageRepository.subirArchivoOperador—) o siendo superadmin,
-- que da de alta operadores en nombre de una empresa (js/operadores.js:57).
--
-- Lo que NO cambia, y por qué no rompe nada:
--   · Las URL públicas que guarda `operadores` siguen funcionando: el bucket
--     sigue siendo público, y /object/public/ se sirve sin pasar por RLS.
--     Ninguna pantalla (web ni Android) LISTA este bucket; solo sube y abre.
--   · Cerrar la lectura por URL (bucket privado + URL firmada + guardar rutas)
--     es el paso 2 de S-01: exige cambiar web y Android y migrar las URL
--     guardadas. No va aquí.
--
-- ⚠ Reescribir una política es DROP + CREATE: Regla #1 de CLAUDE.md. Va en
--   la misma transacción, así que no hay un instante sin política.
--
-- Reglas de docs/AUDITORIA.md §4: 2 (bloque que sabe fallar), 12 (toda
-- política lleva TO), 16 (autorización en el servidor), 44 (buckets).
-- ════════════════════════════════════════════════════════════════════════

drop policy if exists operadores_read   on storage.objects;
drop policy if exists operadores_upload on storage.objects;
drop policy if exists operadores_delete on storage.objects;

create policy operadores_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'operadores'
    and (   (storage.foldername(name))[1] = (select auth.uid())::text
         or (select public.is_superadmin()))
  );

create policy operadores_upload on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'operadores'
    and (   (storage.foldername(name))[1] = (select auth.uid())::text
         or (select public.is_superadmin()))
  );

create policy operadores_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'operadores'
    and (   (storage.foldername(name))[1] = (select auth.uid())::text
         or (select public.is_superadmin()))
  );


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--
-- Solo lectura sobre los archivos que ya hay: en producción un trigger
-- (storage.protect_delete) impide borrar filas de storage.objects por SQL, y
-- esta comprobación no escribe ninguna. Como `authenticated`, con RLS:
--   · un perfil SIN archivos en el bucket (ni superadmin) ve 0;
--   · el dueño de la carpeta con más archivos ve exactamente los suyos;
--   · un superadmin los ve todos.
-- Como sabe fallar: con las políticas viejas, el primer caso ve todos.
-- Si el bucket está vacío no hay nada que probar, y eso se dice abortando:
-- un verde sin archivos no demostraría nada.

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
begin
  -- Catálogo: exactamente las tres políticas del bucket, todas TO authenticated
  -- y todas atadas a la carpeta.
  for v_pol in
    select polname, polroles::regrole[]::text[] as roles,
           coalesce(pg_get_expr(polqual, polrelid), '') || ' ' ||
           coalesce(pg_get_expr(polwithcheck, polrelid), '') as expr
      from pg_policy
     where polrelid = 'storage.objects'::regclass
       and (coalesce(pg_get_expr(polqual, polrelid), '') ||
            coalesce(pg_get_expr(polwithcheck, polrelid), '')) like '%''operadores''%'
  loop
    if v_pol.roles <> array['authenticated'] then
      v_fallos := v_fallos || format('%s no es TO authenticated (%s)', v_pol.polname, v_pol.roles);
    end if;
    if v_pol.expr not like '%foldername%' or v_pol.expr not like '%auth.uid()%' then
      v_fallos := v_fallos || format('%s no está atada a la carpeta del dueño', v_pol.polname);
    end if;
  end loop;
  if (select count(*) from pg_policy
       where polrelid = 'storage.objects'::regclass
         and polname in ('operadores_read','operadores_upload','operadores_delete')) <> 3 then
    v_fallos := v_fallos || 'no están las tres políticas operadores_read/_upload/_delete'::text;
  end if;

  -- Datos para la prueba funcional.
  select count(*) into v_total from storage.objects where bucket_id = 'operadores';
  if v_total = 0 then
    raise exception 'S-01: el bucket operadores está vacío; la comprobación funcional no puede demostrar nada aquí.';
  end if;

  select p.user_id, count(*) into v_dueno, v_suyos
    from storage.objects o
    join public.perfiles p on p.user_id::text = (storage.foldername(o.name))[1]
   where o.bucket_id = 'operadores' and p.rol <> 'superadmin'
   group by p.user_id order by count(*) desc limit 1;

  select p.user_id into v_ajeno
    from public.perfiles p
   where p.rol <> 'superadmin'
     and not exists (select 1 from storage.objects o
                      where o.bucket_id = 'operadores'
                        and (storage.foldername(o.name))[1] = p.user_id::text)
   order by p.created_at limit 1;

  select user_id into v_sa from public.perfiles where rol = 'superadmin' order by created_at limit 1;

  if v_dueno is null or v_ajeno is null or v_sa is null then
    raise exception 'S-01: faltan perfiles para la prueba (dueño con archivos %, perfil sin archivos %, superadmin %).',
      v_dueno, v_ajeno, v_sa;
  end if;

  -- Caso 1: sin archivos propios → 0.
  perform set_config('request.jwt.claim.sub', v_ajeno::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_ajeno, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_visto from storage.objects where bucket_id = 'operadores';
  perform set_config('role', v_quien, true);
  if v_visto <> 0 then
    v_fallos := v_fallos || format('un perfil sin archivos ve %s de %s', v_visto, v_total);
  end if;

  -- Caso 2: el dueño ve exactamente los suyos.
  perform set_config('request.jwt.claim.sub', v_dueno::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_dueno, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_visto from storage.objects where bucket_id = 'operadores';
  perform set_config('role', v_quien, true);
  if v_visto <> v_suyos then
    v_fallos := v_fallos || format('el dueño ve %s, tiene %s', v_visto, v_suyos);
  end if;

  -- Caso 3: el superadmin ve todos.
  perform set_config('request.jwt.claim.sub', v_sa::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_visto from storage.objects where bucket_id = 'operadores';
  perform set_config('role', v_quien, true);
  if v_visto <> v_total then
    v_fallos := v_fallos || format('el superadmin ve %s de %s', v_visto, v_total);
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  if current_user <> v_quien then
    raise exception 'S-01: la comprobación dejó el rol en % (era %).', current_user, v_quien;
  end if;
  if cardinality(v_fallos) > 0 then
    raise exception E'S-01: las políticas no hacen lo que deben:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'S-01: bucket operadores por carpeta; % archivos, el perfil sin archivos ve 0, el dueño ve sus %, el superadmin ve todos.',
    v_total, v_suyos;
end $$;
