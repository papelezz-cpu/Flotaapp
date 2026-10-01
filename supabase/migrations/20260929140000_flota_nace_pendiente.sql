-- ═════════════════════════════════════════════════════════════════════════
-- Q-02 · Un recurso de flota nace aprobado si quien lo da de alta lo dice
-- ═════════════════════════════════════════════════════════════════════════
--
-- El defecto (quinta auditoria, 2026-09-29, medido contra el volcado de
-- produccion del 28/09; la paridad de dependencias del 29/09 no muestra
-- cambios de esquema desde entonces):
--
--   · `camiones`, `custodios` y `patios` tienen `aprobacion DEFAULT 'aprobada'`.
--   · Ninguna de las cinco tablas de flota tiene guard de INSERT. El de UPDATE
--     (`guard_fleet_resource_update`) impide auto-aprobarse... un recurso que
--     ya existe. Al crearlo no hay nada.
--   · Quien decide hoy es el navegador: js/admin.js manda
--     `aprobacion: esSuperAdmin ? 'aprobada' : 'pendiente'` (y operadores.js,
--     `'pendiente'`). Una empresa que inserte directamente con
--     `aprobacion = 'aprobada'` —o que omita la columna en esas tres tablas—
--     publica un camion, custodio o patio sin revision del superadmin, y
--     `enviar_oferta`/el catalogo lo tratan como aprobado.
--
-- El arreglo:
--   1. Guard BEFORE INSERT en las cinco tablas: un usuario final que no es
--      superadmin solo puede crear el recurso en `pendiente`. Es la misma
--      columna que protege el guard de UPDATE, ni una mas.
--   2. DEFAULT 'pendiente' en las tres que nacian aprobadas, para que omitir
--      la columna tampoco apruebe.
--
-- ─── Quien inserta flota hoy, y por que sigue funcionando ────────────────
--
--   · js/admin.js (camiones 1070, custodios 1190, patios 1375, lavados 1519)
--     y js/operadores.js:490: la empresa manda 'pendiente', el superadmin
--     'aprobada'. Pasan los dos: el superadmin sale por is_superadmin().
--   · Ninguna funcion de la base inserta flota (medido en el volcado).
--   · Android: no inserta flota; su alta apunta a RPC que produccion no tiene
--     (hueco 13 de FLUJO-OPERATIVO).
--   · Con la clave de servicio o como postgres (auth.uid() NULL) pasa, igual
--     que en Q-01 (20260929130000). El bloque 3 comprueba el supuesto: que
--     `anon` no tiene INSERT en ninguna de las cinco y que toda politica de
--     INSERT es `TO authenticated`.
--
-- ─── Reglas de docs/AUDITORIA.md §4 que aplican ──────────────────────────
--
--   1  La funcion nace ejecutable por PUBLIC/anon/authenticated: se revoca.
--   2  Bloque de verificacion que ejecuta altas reales y sabe fallar.
--   6  `trg_guard_<tabla>_insert` es el unico BEFORE INSERT de estas tablas.
--   9  Sin DROP: triggers creados solo si no existen.
--   13 SECURITY INVOKER: no lee tablas; is_superadmin() ya es DEFINER.
--   15 `guard_fleet_resource_update` no se toca.
--
-- No se revisan las filas existentes: el guard solo mira filas nuevas, y
-- desde la base no se distingue un recurso aprobado por el superadmin de uno
-- que nacio aprobado.
-- ═════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- 1. El guard, uno para las cinco tablas
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.guard_fleet_resource_insert()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  -- Sin usuario final: clave de servicio o postgres. Ver cabecera y bloque 3.
  if auth.uid() is null then
    return new;
  end if;

  if public.is_superadmin() then
    return new;
  end if;

  if new.aprobacion is distinct from 'pendiente' then
    raise exception 'No autorizado: un recurso nuevo nace pendiente de aprobacion; solo un superadmin puede aprobarlo'
      using hint = 'Q-02';
  end if;

  return new;
end;
$$;

comment on function public.guard_fleet_resource_insert() is
  'Q-02: un usuario final que no es superadmin solo puede crear recursos de '
  'flota en aprobacion = pendiente. Pareja de guard_fleet_resource_update. '
  'auth.uid() NULL pasa: ver 20260929140000.';

revoke all on function public.guard_fleet_resource_insert() from public, anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. Triggers (sin DROP) y el DEFAULT
-- ─────────────────────────────────────────────────────────────────────────

do $$
declare
  t text;
begin
  foreach t in array array['camiones', 'custodios', 'patios', 'lavados', 'operadores'] loop
    if not exists (
      select 1 from pg_trigger
       where tgrelid = format('public.%I', t)::regclass
         and tgname  = format('trg_guard_%s_insert', t)
         and not tgisinternal
    ) then
      execute format(
        'create trigger %I before insert on public.%I '
        'for each row execute function public.guard_fleet_resource_insert()',
        format('trg_guard_%s_insert', t), t);
    end if;
  end loop;
end $$;

alter table public.camiones  alter column aprobacion set default 'pendiente';
alter table public.custodios alter column aprobacion set default 'pendiente';
alter table public.patios    alter column aprobacion set default 'pendiente';


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion — falla si el objetivo no se cumplio
-- ─────────────────────────────────────────────────────────────────────────
--
-- Cada alta va en su subtransaccion, como `authenticated` con un uid
-- inventado que es tambien el propietario (asi la politica de INSERT pasa).
-- Todas las ramas terminan en excepcion: ninguna fila sobrevive y el rol y
-- los claims se revierten con la subtransaccion.
--
-- Como sabe fallar:
--   · Un rechazo se reconoce por el HINT 'Q-02', no por el texto: si el guard
--     no estuviera, el alta llegaria a la FK de propietario_id (23503).
--   · Un alta legitima tiene que llegar a esa FK (23503), que se comprueba
--     DESPUES de los BEFORE triggers, la RLS, los NOT NULL y los CHECK. Si el
--     guard la frenara, daria el HINT 'Q-02'.
--   · Los DEFAULT se leen del catalogo.

do $$
declare
  v_tabla   text;
  v_extra   jsonb;
  v_caso    jsonb;
  v_debe    text;
  v_uid     uuid;
  v_cols    text;
  v_estado  text;
  v_hint    text;
  v_msg     text;
  v_quien   text := current_user;
  v_fallos  text[] := '{}';
  v_n       int := 0;
  v_pol     int;
  v_def     text;
  t         text;
begin
  -- 3a. Triggers presentes, encendidos, BEFORE INSERT FOR EACH ROW.
  foreach t in array array['camiones', 'custodios', 'patios', 'lavados', 'operadores'] loop
    if not exists (
      select 1 from pg_trigger tg join pg_proc p on p.oid = tg.tgfoid
       where tg.tgrelid = format('public.%I', t)::regclass
         and tg.tgname  = format('trg_guard_%s_insert', t)
         and tg.tgenabled <> 'D'
         and (tg.tgtype & 7) = 7
         and p.proname = 'guard_fleet_resource_insert'
    ) then
      raise exception 'Q-02: falta o esta apagado trg_guard_%_insert.', t;
    end if;

    -- 3b. Supuestos del paso auth.uid() NULL.
    if has_table_privilege('anon', format('public.%I', t), 'INSERT') then
      raise exception 'Q-02: anon tiene INSERT en %.', t;
    end if;
    select count(*) into v_pol from pg_policies
     where schemaname = 'public' and tablename = t
       and cmd in ('INSERT', 'ALL') and roles <> '{authenticated}'::name[];
    if v_pol > 0 then
      raise exception 'Q-02: % tiene % politica(s) de INSERT que no son TO authenticated.', t, v_pol;
    end if;
  end loop;

  -- 3c. La funcion no la ejecuta nadie de fuera.
  if has_function_privilege('anon',          'public.guard_fleet_resource_insert()', 'EXECUTE')
  or has_function_privilege('authenticated', 'public.guard_fleet_resource_insert()', 'EXECUTE') then
    raise exception 'Q-02: guard_fleet_resource_insert() sigue ejecutable por anon o authenticated.';
  end if;

  -- 3d. Ningun recurso de flota nace aprobado por omision.
  select string_agg(format('%s=%s', c.table_name, c.column_default), ', ') into v_def
    from information_schema.columns c
   where c.table_schema = 'public'
     and c.table_name in ('camiones', 'custodios', 'patios', 'lavados', 'operadores')
     and c.column_name = 'aprobacion'
     and coalesce(c.column_default, '') not like '''pendiente''%';
  if v_def is not null then
    raise exception 'Q-02: aprobacion no nace pendiente en: %', v_def;
  end if;

  -- 3e. Las altas. v_extra lleva los NOT NULL sin DEFAULT de cada tabla.
  for v_tabla, v_extra in
    select * from (values
      ('camiones',   '{"tipo":"q02","capacidad":1}'::jsonb),
      ('custodios',  '{"nombre":"q02","tipo":"q02"}'::jsonb),
      ('patios',     '{"nombre":"q02","tipo":"q02"}'::jsonb),
      ('lavados',    '{"nombre":"q02"}'::jsonb),
      ('operadores', '{"nombre":"q02"}'::jsonb)
    ) as x(a, b)
  loop
    for v_caso, v_debe in
      select * from (values
        ('{"aprobacion":"pendiente"}'::jsonb, 'pasa'),
        ('{"aprobacion":"aprobada"}'::jsonb,  'rechazo'),
        ('{"aprobacion":"rechazada"}'::jsonb, 'rechazo'),
        ('{}'::jsonb,                         'pasa')     -- omitida: el DEFAULT ya es pendiente
      ) as y(c, d)
    loop
      v_n   := v_n + 1;
      v_uid := gen_random_uuid();
      v_caso := v_extra || v_caso
                || jsonb_build_object('id', 'q02-' || v_uid, 'propietario_id', v_uid);
      select string_agg(quote_ident(k), ', ') into v_cols from jsonb_object_keys(v_caso) k;
      v_hint := null;

      begin
        perform set_config('request.jwt.claim.sub', v_uid::text, true);
        perform set_config('request.jwt.claims',
                           json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
        perform set_config('role', 'authenticated', true);

        execute format(
          'insert into public.%2$I (%1$s) select %1$s from jsonb_populate_record(null::public.%2$I, $1)',
          v_cols, v_tabla) using v_caso;

        raise exception 'Q02_SENTINELA';
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate,
                                v_msg    = message_text,
                                v_hint   = pg_exception_hint;
      end;

      if v_debe = 'rechazo' and v_hint is distinct from 'Q-02' then
        v_fallos := v_fallos || format('%s %s NO se rechazo: %s %s', v_tabla, v_caso - 'id' - 'propietario_id', v_estado, v_msg);
      elsif v_debe = 'pasa' and v_estado <> '23503' then
        v_fallos := v_fallos || format('%s %s legitimo NO paso: %s %s', v_tabla, v_caso - 'id' - 'propietario_id', v_estado, v_msg);
      end if;
    end loop;

    -- La clave de servicio sigue pudiendo crear aprobado (auth.uid() NULL).
    v_n   := v_n + 1;
    v_uid := gen_random_uuid();
    v_caso := v_extra || jsonb_build_object('aprobacion', 'aprobada', 'id', 'q02-' || v_uid, 'propietario_id', v_uid);
    select string_agg(quote_ident(k), ', ') into v_cols from jsonb_object_keys(v_caso) k;
    begin
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claims', '', true);
      perform set_config('role', 'service_role', true);
      execute format(
        'insert into public.%2$I (%1$s) select %1$s from jsonb_populate_record(null::public.%2$I, $1)',
        v_cols, v_tabla) using v_caso;
      raise exception 'Q02_SENTINELA';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    end;
    if v_estado <> '23503' then
      v_fallos := v_fallos || format('%s: service_role no pudo crear aprobado: %s %s', v_tabla, v_estado, v_msg);
    end if;
  end loop;

  if current_user <> v_quien then
    raise exception 'Q-02: la comprobacion dejo el rol en % (era %).', current_user, v_quien;
  end if;

  if cardinality(v_fallos) > 0 then
    raise exception E'Q-02: el guard no hace lo que debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'Q-02: guard de INSERT en las 5 tablas de flota y DEFAULT pendiente; % altas, todas como se esperaba.', v_n;
end $$;
