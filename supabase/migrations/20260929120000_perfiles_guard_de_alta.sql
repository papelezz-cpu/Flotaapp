-- ═════════════════════════════════════════════════════════════════════════
-- Q-01 · `perfiles` no tenia guard de INSERT
-- ═════════════════════════════════════════════════════════════════════════
--
-- El defecto (quinta auditoria, 2026-09-29, medido contra el volcado de
-- produccion del 28/09):
--
--   CREATE POLICY "Insert own profile" ON public.perfiles FOR INSERT
--     TO authenticated WITH CHECK (auth.uid() = user_id);
--
-- es lo unico que vigila el alta de un perfil, y solo mira DE QUIEN es la fila.
-- `trg_guard_perfil_self_update` protege rol, aprobacion, verificacion y
-- acreditacion... en UPDATE. En INSERT no hay nada. Una cuenta recien creada en
-- auth —sin perfil todavia, que es justo el hueco entre `signUp` y el `upsert`
-- de js/auth.js— puede escribir su propia fila con `rol = 'superadmin'`, o con
-- `aprobacion_cuenta = NULL` (cuenta activa sin pasar por el superadmin), o
-- verificada, o con seguros y permiso SCT acreditados.
--
-- El arreglo: un trigger BEFORE INSERT que exige, para un usuario final, que la
-- fila nazca como la crea el registro — rol cliente o admin, `pendiente`, y las
-- mismas columnas que protege el guard de UPDATE en su valor de nacimiento.
-- Lo mismo que el guard de UPDATE, ni una columna mas (acordado 2026-09-29).
--
-- ─── Quien inserta en perfiles hoy, y por que sigue funcionando ──────────
--
--   · js/auth.js:805, alta nueva: `upsert({user_id, nombre, rol: cliente|admin,
--     aprobacion_cuenta: 'pendiente'})`. Pasa: es exactamente la forma exigida.
--     Un upsert dispara el BEFORE INSERT antes de detectar el conflicto; la fila
--     propuesta tiene esa misma forma, asi que tambien pasa.
--   · js/auth.js:795, re-registro: va por UPDATE. No lo toca este trigger.
--   · gestionar-usuario `crear`: `insert({user_id, nombre, rol})` con la clave
--     de servicio — cualquier rol, aprobacion NULL. `auth.uid()` es NULL: pasa.
--   · replicar-produccion-a-pruebas.sh: carga con los triggers de usuario
--     apagados, y ademas corre como postgres (`auth.uid()` NULL).
--   · Android: no inserta perfiles.
--
-- ─── Por que `auth.uid() IS NULL` pasa, y no contradice A3-N1 ────────────
--
-- La leccion de A3-N1 (docs/AUDITORIA.md §3.3, regla 15) es no ABRIR un guard
-- existente a service_role para resolver un caso. Aqui no se abre nada: el alta
-- con la clave de servicio es un camino legitimo que ya existe y que hoy no
-- tiene guard; rechazarla romperia el alta de usuarios del superadmin.
--
-- Lo que hace seguro ese paso es que un usuario final no puede llegar a el con
-- `auth.uid()` NULL: la unica politica de INSERT exige `auth.uid() = user_id` y
-- `user_id` es NOT NULL, y `anon` no tiene privilegio de INSERT. Las dos cosas
-- son supuestos, asi que el bloque 3 las COMPRUEBA y falla si dejan de ser
-- ciertas: una politica de INSERT nueva para otro rol, o un GRANT a anon,
-- convertirian este paso en una puerta.
--
-- ─── Reglas de docs/AUDITORIA.md §4 que aplican ──────────────────────────
--
--   1  La funcion nace con EXECUTE para PUBLIC/anon/authenticated por los
--      privilegios por omision: se revoca aqui (y a PUBLIC explicito, H-21).
--   2  Bloque de verificacion que sabe fallar: ejecuta ataques reales.
--   6  Nombre del trigger: `trg_guard_perfil_insert` corre antes que cualquier
--      BEFORE que toque NEW. Hoy perfiles no tiene otro BEFORE INSERT.
--   9  Ningun DROP en este archivo: el trigger se crea solo si no existe.
--   13 SECURITY INVOKER: el guard no lee tablas; `is_superadmin()` ya es
--      DEFINER y esta concedida a authenticated.
--   15 No se relaja `guard_perfil_self_update`: no se toca.
--
-- Nada que migrar: el guard solo mira filas nuevas. Si alguien ya exploto el
-- hueco, esta migracion no lo detecta — eso es otra consulta, de auditoria.
-- ═════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- 1. El guard
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.guard_perfil_insert()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  -- Sin usuario final: clave de servicio (gestionar-usuario) o postgres
  -- (migraciones, replica). Ver la cabecera: el bloque 3 vigila que un
  -- usuario final no pueda llegar aqui con auth.uid() NULL.
  if auth.uid() is null then
    return new;
  end if;

  if public.is_superadmin() then
    return new;
  end if;

  if new.rol is distinct from 'cliente' and new.rol is distinct from 'admin' then
    raise exception 'No autorizado: una cuenta nueva solo puede ser cliente o empresa';
  end if;

  if new.aprobacion_cuenta is distinct from 'pendiente' then
    raise exception 'No autorizado: una cuenta nueva nace pendiente de aprobacion';
  end if;

  if new.verificado          is true
     or new.docs_aprobados_en   is not null
     or new.docs_aprobados_por  is not null
     or new.metodo_verificacion is not null then
    raise exception 'No autorizado: campos de verificacion solo modificables por superadmin';
  end if;

  -- H-02: la acreditacion no se autodeclara, tampoco al nacer.
  if new.permiso_sct  is not null
     or new.seguro_rc    is true
     or new.seguro_carga is true
     or new.fecha_vencimiento_permiso_sct  is not null
     or new.fecha_vencimiento_seguro_rc    is not null
     or new.fecha_vencimiento_seguro_carga is not null then
    raise exception 'No autorizado: los seguros y el permiso SCT se acreditan con documento aprobado, no se declaran. Subelos en Perfil de empresa -> Documentos legales.';
  end if;

  return new;
end;
$$;

comment on function public.guard_perfil_insert() is
  'Q-01: un usuario final solo puede crear su perfil como cliente/admin, '
  'pendiente, sin verificacion ni acreditacion. Protege al nacer las mismas '
  'columnas que guard_perfil_self_update en UPDATE. auth.uid() NULL (clave de '
  'servicio, postgres) pasa: ver 20260929120000.';

-- Regla 1: nace abierta. PUBLIC explicito, porque es donde PostgreSQL concede
-- (H-21: el revoke a anon/authenticated solo no retiraba nada).
revoke all on function public.guard_perfil_insert() from public, anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. El trigger — sin DROP: se crea solo si no esta
-- ─────────────────────────────────────────────────────────────────────────

do $$
begin
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.perfiles'::regclass
       and tgname  = 'trg_guard_perfil_insert'
       and not tgisinternal
  ) then
    create trigger trg_guard_perfil_insert
      before insert on public.perfiles
      for each row execute function public.guard_perfil_insert();
  end if;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion — falla si el objetivo no se cumplio
-- ─────────────────────────────────────────────────────────────────────────
--
-- Cada caso se ejecuta en su propia subtransaccion (BEGIN ... EXCEPTION), como
-- `authenticated` con un uid inventado. Todas las ramas terminan en excepcion,
-- asi que ninguna fila sobrevive y el rol y los claims se revierten solos
-- (set_config local dentro de una subtransaccion deshecha se deshace con ella).
--
-- Como sabe fallar:
--   · Ataque que el guard NO para: el uid inventado no existe en auth.users,
--     asi que el INSERT acaba en 23503 (FK) en vez de P0001 'No autorizado'.
--     Sin el trigger, TODOS los ataques darian 23503 y el bloque abortaria.
--   · Alta legitima que el guard SI para: da P0001 en vez de 23503.
--   · Los supuestos del paso `auth.uid() IS NULL`, leidos del catalogo.

do $$
declare
  v_uid     uuid;
  v_caso    jsonb;
  v_debe    text;   -- 'rechazo' | 'pasa'
  v_cols    text;
  v_estado  text;
  v_msg     text;
  v_quien   text := current_user;
  v_fallos  text[] := '{}';
  v_n       int := 0;
  v_pol     int;
  v_trg     record;
begin
  -- 3a. El trigger existe, encendido, BEFORE INSERT FOR EACH ROW, sobre el guard.
  select t.tgenabled, t.tgtype, p.proname
    into v_trg
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
   where t.tgrelid = 'public.perfiles'::regclass
     and t.tgname  = 'trg_guard_perfil_insert';

  if not found then
    raise exception 'Q-01: trg_guard_perfil_insert no existe.';
  end if;
  if v_trg.tgenabled = 'D' then
    raise exception 'Q-01: trg_guard_perfil_insert esta DESHABILITADO.';
  end if;
  -- tgtype: bit 0 ROW, bit 1 BEFORE, bit 2 INSERT
  if (v_trg.tgtype & 7) <> 7 then
    raise exception 'Q-01: trg_guard_perfil_insert no es BEFORE INSERT FOR EACH ROW (tgtype=%).', v_trg.tgtype;
  end if;
  if v_trg.proname <> 'guard_perfil_insert' then
    raise exception 'Q-01: el trigger llama a % en vez de guard_perfil_insert.', v_trg.proname;
  end if;

  -- El guard de UPDATE sigue encendido (no se toca, pero se comprueba).
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.perfiles'::regclass
                    and tgname  = 'trg_guard_perfil_self_update'
                    and tgenabled <> 'D') then
    raise exception 'Q-01: trg_guard_perfil_self_update no esta activo.';
  end if;

  -- 3b. Regla 1: nadie mas que los de siempre ejecuta la funcion.
  if has_function_privilege('anon',          'public.guard_perfil_insert()', 'EXECUTE')
  or has_function_privilege('authenticated', 'public.guard_perfil_insert()', 'EXECUTE') then
    raise exception 'Q-01: guard_perfil_insert() sigue ejecutable por anon o authenticated.';
  end if;

  -- 3c. Los supuestos del paso auth.uid() IS NULL.
  if has_table_privilege('anon', 'public.perfiles', 'INSERT') then
    raise exception 'Q-01: anon tiene INSERT en perfiles; el paso auth.uid() NULL seria una puerta.';
  end if;

  select count(*) into v_pol
    from pg_policies
   where schemaname = 'public' and tablename = 'perfiles'
     and cmd in ('INSERT', 'ALL')
     and (roles <> '{authenticated}'::name[]
          or coalesce(with_check, '') not like '%auth.uid()%user_id%');
  if v_pol > 0 then
    raise exception 'Q-01: hay % politica(s) de INSERT en perfiles que no son "authenticated + auth.uid() = user_id". Revisar el paso auth.uid() NULL del guard.', v_pol;
  end if;

  -- 3d. Los casos. Cada uno lleva solo las columnas que nombra; el resto
  -- toma su DEFAULT, como en un INSERT real.
  for v_caso, v_debe in
    select c, d from (values
      -- Lo que hace el registro web: tiene que pasar.
      ('{"nombre":"q01","rol":"cliente","aprobacion_cuenta":"pendiente"}'::jsonb, 'pasa'),
      ('{"nombre":"q01","rol":"admin","aprobacion_cuenta":"pendiente"}'::jsonb,   'pasa'),
      -- Ataques: tienen que rechazarse.
      ('{"nombre":"q01","rol":"superadmin","aprobacion_cuenta":"pendiente"}'::jsonb,                          'rechazo'),
      ('{"nombre":"q01","rol":"cliente"}'::jsonb,                                                            'rechazo'),
      ('{"nombre":"q01","rol":"admin","aprobacion_cuenta":null}'::jsonb,                                     'rechazo'),
      ('{"nombre":"q01","rol":"cliente","aprobacion_cuenta":"pendiente","verificado":true}'::jsonb,          'rechazo'),
      ('{"nombre":"q01","rol":"cliente","aprobacion_cuenta":"pendiente","metodo_verificacion":"fisica"}'::jsonb, 'rechazo'),
      ('{"nombre":"q01","rol":"cliente","aprobacion_cuenta":"pendiente","docs_aprobados_en":"2026-09-29T00:00:00Z"}'::jsonb, 'rechazo'),
      ('{"nombre":"q01","rol":"admin","aprobacion_cuenta":"pendiente","seguro_rc":true}'::jsonb,             'rechazo'),
      ('{"nombre":"q01","rol":"admin","aprobacion_cuenta":"pendiente","seguro_carga":true}'::jsonb,          'rechazo'),
      ('{"nombre":"q01","rol":"admin","aprobacion_cuenta":"pendiente","permiso_sct":"X"}'::jsonb,            'rechazo'),
      ('{"nombre":"q01","rol":"admin","aprobacion_cuenta":"pendiente","fecha_vencimiento_seguro_rc":"2030-01-01"}'::jsonb, 'rechazo')
    ) as t(c, d)
  loop
    v_n   := v_n + 1;
    v_uid := gen_random_uuid();
    v_caso := v_caso || jsonb_build_object('user_id', v_uid);
    select string_agg(quote_ident(k), ', ') into v_cols from jsonb_object_keys(v_caso) k;

    begin
      perform set_config('request.jwt.claim.sub', v_uid::text, true);
      perform set_config('request.jwt.claims',
                         json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);

      execute format(
        'insert into public.perfiles (%1$s) select %1$s from jsonb_populate_record(null::public.perfiles, $1)',
        v_cols) using v_caso;

      raise exception 'Q01_SENTINELA';   -- no deberia llegar: la FK tendria que saltar
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    end;

    if v_debe = 'rechazo' and not (v_estado = 'P0001' and v_msg like 'No autorizado:%') then
      v_fallos := v_fallos || format('caso %s (%s) NO se rechazo: %s %s', v_n, v_caso - 'user_id', v_estado, v_msg);
    elsif v_debe = 'pasa' and v_estado not in ('23503') then
      v_fallos := v_fallos || format('caso %s (%s) legitimo NO paso: %s %s', v_n, v_caso - 'user_id', v_estado, v_msg);
    end if;
  end loop;

  -- 3e. La clave de servicio sigue pudiendo dar de alta cualquier rol
  -- (gestionar-usuario `crear`). Sin claims: auth.uid() NULL.
  v_uid := gen_random_uuid();
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'service_role', true);
    insert into public.perfiles (user_id, nombre, rol) values (v_uid, 'q01', 'superadmin');
    raise exception 'Q01_SENTINELA';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  end;
  if v_estado <> '23503' then
    v_fallos := v_fallos || format('service_role no pudo dar de alta un superadmin: %s %s', v_estado, v_msg);
  end if;

  -- El rol volvio: si no, lo que siga en esta transaccion correria como otro.
  if current_user <> v_quien then
    raise exception 'Q-01: la comprobacion dejo el rol en % (era %).', current_user, v_quien;
  end if;

  if cardinality(v_fallos) > 0 then
    raise exception E'Q-01: el guard no hace lo que debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'Q-01: guard de INSERT activo; % casos como authenticated + 1 como service_role, todos como se esperaba.', v_n;
end $$;
