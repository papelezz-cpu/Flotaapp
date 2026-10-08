-- ════════════════════════════════════════════════════════════════════════
-- A2-C2 · Archivar una reservación es una marca, no un traslado
-- ════════════════════════════════════════════════════════════════════════
--
-- Hasta hoy, «archivar» (eliminarReserva() en js/reservaciones.js) hacía tres
-- viajes desde el navegador, sin transacción: leer la fila, copiar 14 de sus
-- 55 columnas a reservaciones_historico, y BORRAR la original. Eso:
--   · perdía el precio, el dueño, el pedido, el pago, las evidencias y la
--     cancelación —el registro económico y probatorio del servicio—;
--   · arrastraba en cascada expedientes, sus documentos y mensajes;
--   · fallaba a medias con pagos o facturas detrás (FK NO ACTION): la copia
--     quedaba hecha, el borrado no, y el reintento chocaba con la PK;
--   · sacaba el servicio de reporte_kpis() y desempeno_empresa(), que leen
--     reservaciones: archivar borraba ingresos de los reportes;
--   · se ofrecía en cualquier estado, también en un viaje Activa.
--
-- Decisión del usuario (07/10): la reservación se queda donde está y lleva
-- una marca; solo se archiva lo cerrado; lo archivado sigue contando en los
-- reportes; y se puede restaurar. Esta migración:
--   1. añade archivada_en / archivada_por a reservaciones;
--   2. un guard propio (guard_reservacion_archivo) que decide quién y cuándo:
--        · solo el superadmin pone o quita la marca;
--        · solo sobre una reservación cerrada: Cancelada, Rechazada, o
--          Completada CON EL PAGO REGISTRADO —una Completada sin cobrar no
--          está cerrada: archivarla la escondería de «Por cobrar»—;
--        · la fecha y el autor los pone la base, no el navegador;
--        · nadie nace archivado, el autor no se reescribe por separado, y una
--          archivada no puede dejar de ser archivable (p. ej. revertir su
--          cobro) sin restaurarla antes.
--      Hace falta un guard aparte: guard_reservacion_update deja a la empresa
--      y al cliente cambiar las columnas que no enumera, y estas son nuevas.
--   3. deja reservaciones_historico como archivo antiguo de SOLO LECTURA: su
--      único escritor era eliminarReserva(). No se borra (Regla #1): conserva
--      lo que se archivó antes de hoy, con sus 14 columnas.
--
-- Depende de 20261007120000 (S-14): sin ella, actualizar una Completada cuya
-- unidad tiene un viaje posterior que empieza ese día falla, y archivarla
-- también. La comprobación lo exige.
--
-- No borra nada. Reversible: las columnas nuevas se pueden ignorar, el guard
-- desactivar, y el GRANT del histórico volver a darse.
--
-- Reglas de docs/AUDITORIA.md §4: 2, 3 (revoke en la misma migración), 13
-- (FK con índice), 32, 33, 47. Hallazgos: A2-C2, A2-B4.
-- ════════════════════════════════════════════════════════════════════════

-- 1 · La marca ─────────────────────────────────────────────────────────────
alter table public.reservaciones
  add column if not exists archivada_en  timestamptz,
  add column if not exists archivada_por uuid references auth.users(id) on delete set null;

comment on column public.reservaciones.archivada_en is
  'A2-C2: cuándo el superadmin la archivó (now() del servidor). NULL = en la lista. Archivar solo la oculta de Reservaciones: sigue en reportes, cobros y desempeño. La pone y la quita guard_reservacion_archivo.';
comment on column public.reservaciones.archivada_por is
  'A2-C2: el superadmin que la archivó. Lo pone guard_reservacion_archivo; no se escribe a mano.';

-- Índice de apoyo de la FK (regla 13, S-11): borrar una cuenta no recorre la tabla.
create index if not exists idx_reservaciones_archivada_por
  on public.reservaciones (archivada_por) where archivada_por is not null;


-- 2 · El guard ─────────────────────────────────────────────────────────────
create or replace function public.guard_reservacion_archivo()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    -- Nadie nace archivado: una reserva oculta desde el primer segundo no la
    -- vería ni quien la creó.
    new.archivada_en  := null;
    new.archivada_por := null;
    return new;
  end if;

  if new.archivada_en is distinct from old.archivada_en then
    if not public.is_superadmin() then
      raise exception 'No autorizado: solo el superadmin archiva o restaura una reservacion'
        using hint = 'A2-C2';
    end if;
    if new.archivada_en is null then          -- restaurar
      new.archivada_por := null;
      return new;
    end if;
    if old.archivada_en is null then          -- archivar: fecha y autor, del servidor
      new.archivada_en  := now();
      new.archivada_por := auth.uid();
    else                                      -- ya archivada: no se vuelve a sellar
      new.archivada_en  := old.archivada_en;
      new.archivada_por := old.archivada_por;
    end if;
  else
    new.archivada_por := old.archivada_por;   -- el autor no se toca por separado
  end if;

  if new.archivada_en is not null
     and not (new.estado in ('Cancelada', 'Rechazada')
              or (new.estado = 'Completada' and coalesce(new.pagado, false))) then
    raise exception 'Solo se archiva una reservacion cerrada: cancelada, rechazada, o completada con el pago registrado. Si esta archivada, restaurala antes de cambiarla.'
      using hint = 'A2-C2';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_reservacion_archivo() from public, anon, authenticated;

-- Sin DROP (Regla #1): se crea solo si no existe. El nombre importa: los
-- BEFORE corren en orden alfabético y este va antes de trg_guard_reservacion_update
-- y de trg_updated_at (H-19), así que su rechazo llega primero.
do $$
begin
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.reservaciones'::regclass
                    and tgname = 'trg_guard_reservacion_archivo') then
    create trigger trg_guard_reservacion_archivo
      before insert or update on public.reservaciones
      for each row execute function public.guard_reservacion_archivo();
  end if;
end $$;


-- 3 · El histórico antiguo, de solo lectura ─────────────────────────────────
revoke insert, update, delete, maintain on table public.reservaciones_historico from authenticated;

comment on table public.reservaciones_historico is
  'ARCHIVO ANTIGUO, solo lectura desde el 07/10 (A2-C2). Lo archivado antes de esa fecha, con 14 de sus columnas: el resto se perdió al borrar la original. Lo nuevo se archiva con reservaciones.archivada_en y no pasa por aquí.';


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
-- Estructura: columnas, FK SET NULL, índice, trigger BEFORE INSERT OR UPDATE
-- activo, función no ejecutable por anon/authenticated, histórico sin
-- escritura para authenticated, y S-14 aplicada.
-- Comportamiento, sobre filas reales y deshecho al terminar cada caso:
--   a. el superadmin archiva una cerrada → fecha del servidor y él como autor;
--   b. el superadmin restaura → las dos columnas a NULL;
--   c. el superadmin intenta archivar una viva → A2-C2;
--   d. la empresa dueña intenta archivar su reservación cerrada → A2-C2;
--   e. revertir el cobro de una Completada archivada → A2-C2;
--   f. una fila que se inserta archivada nace sin marca (tabla temporal con
--      este trigger, para no disparar avisos de alta).
-- Como sabe fallar: sin el guard, (c), (d) y (e) pasan y (a) deja la fecha
-- que mande el navegador.

do $$
declare
  v_quien   text := current_user;
  v_sa      uuid;
  v_cerrada public.reservaciones;
  v_viva    uuid;
  v_pagada  uuid;
  v_r       record;
  v_fallos  text[] := '{}';
  v_casos   text := '';
  v_msg     text;
  v_hint    text;
begin
  -- Estructura ───────────────────────────────────────────────────────────
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'reservaciones'
         and column_name in ('archivada_en', 'archivada_por')) <> 2 then
    v_fallos := v_fallos || 'faltan las columnas archivada_en / archivada_por'::text;
  end if;
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'public.reservaciones'::regclass and c.contype = 'f'
                    and c.confrelid = 'auth.users'::regclass and c.confdeltype = 'n'
                    and c.conkey = array[(select attnum from pg_attribute
                                           where attrelid = 'public.reservaciones'::regclass
                                             and attname = 'archivada_por')]) then
    v_fallos := v_fallos || 'archivada_por no tiene FK ON DELETE SET NULL a auth.users'::text;
  end if;
  if to_regclass('public.idx_reservaciones_archivada_por') is null then
    v_fallos := v_fallos || 'falta idx_reservaciones_archivada_por'::text;
  end if;
  select t.tgenabled, t.tgtype, p.proname into v_r
    from pg_trigger t join pg_proc p on p.oid = t.tgfoid
   where t.tgrelid = 'public.reservaciones'::regclass and t.tgname = 'trg_guard_reservacion_archivo';
  -- tgtype: 1 ROW + 2 BEFORE + 4 INSERT + 16 UPDATE = 23
  if not found or v_r.tgenabled = 'D' or (v_r.tgtype & 23) <> 23 or v_r.proname <> 'guard_reservacion_archivo' then
    v_fallos := v_fallos || 'trg_guard_reservacion_archivo no es un BEFORE INSERT OR UPDATE FOR EACH ROW activo'::text;
  end if;
  if has_function_privilege('authenticated', 'public.guard_reservacion_archivo()', 'EXECUTE')
  or has_function_privilege('anon', 'public.guard_reservacion_archivo()', 'EXECUTE') then
    v_fallos := v_fallos || 'guard_reservacion_archivo() es ejecutable por anon o authenticated'::text;
  end if;
  if has_table_privilege('authenticated', 'public.reservaciones_historico', 'INSERT')
  or has_table_privilege('authenticated', 'public.reservaciones_historico', 'UPDATE')
  or has_table_privilege('authenticated', 'public.reservaciones_historico', 'DELETE') then
    v_fallos := v_fallos || 'authenticated aún puede escribir en reservaciones_historico'::text;
  end if;
  if not has_table_privilege('authenticated', 'public.reservaciones_historico', 'SELECT') then
    v_fallos := v_fallos || 'authenticated perdió la lectura de reservaciones_historico (el historial la usa)'::text;
  end if;
  if position('S-14' in pg_get_functiondef('public.check_reservacion_disponibilidad()'::regprocedure)) = 0 then
    v_fallos := v_fallos || 'falta 20261007120000 (S-14): aplicarla antes que esta'::text;
  end if;

  -- Comportamiento ───────────────────────────────────────────────────────
  select user_id into v_sa from public.perfiles where rol = 'superadmin' order by created_at limit 1;
  select * into v_cerrada from public.reservaciones
   where archivada_en is null
     and (estado in ('Cancelada', 'Rechazada') or (estado = 'Completada' and pagado))
   order by created_at limit 1;
  select id into v_viva from public.reservaciones
   where archivada_en is null and estado in ('Pendiente', 'Activa', 'PorAprobar', 'CancelacionSolicitada')
   order by created_at limit 1;
  select id into v_pagada from public.reservaciones
   where archivada_en is null and estado = 'Completada' and pagado
   order by created_at limit 1;

  if v_sa is null or v_cerrada.id is null then
    v_casos := v_casos || ' (a,b) sin datos;';
  else
    -- a + b, en una subtransacción que se deshace al final
    begin
      perform set_config('request.jwt.claim.sub', v_sa::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);

      update public.reservaciones set archivada_en = '2000-01-01', archivada_por = gen_random_uuid()
       where id = v_cerrada.id;
      select archivada_en, archivada_por into v_r from public.reservaciones where id = v_cerrada.id;
      if v_r.archivada_en is null or v_r.archivada_en < now() - interval '1 minute' then
        v_fallos := v_fallos || format('a. la fecha de archivado no es la del servidor (%s)', v_r.archivada_en);
      end if;
      if v_r.archivada_por is distinct from v_sa then
        v_fallos := v_fallos || format('a. el autor no es el superadmin (%s)', v_r.archivada_por);
      end if;

      update public.reservaciones set archivada_en = null where id = v_cerrada.id;
      select archivada_en, archivada_por into v_r from public.reservaciones where id = v_cerrada.id;
      if v_r.archivada_en is not null or v_r.archivada_por is not null then
        v_fallos := v_fallos || 'b. restaurar no dejó las dos columnas en NULL'::text;
      end if;
      raise exception 'A2C2_FIN_AB';
    exception when others then
      perform set_config('role', v_quien, true);
      if sqlerrm <> 'A2C2_FIN_AB' then
        v_fallos := v_fallos || format('a/b. el superadmin no pudo archivar/restaurar una cerrada: %s', sqlerrm);
      end if;
    end;
    v_casos := v_casos || ' (a,b) ejercidos;';
  end if;

  -- c.
  if v_sa is null or v_viva is null then
    v_casos := v_casos || ' (c) sin datos;';
  else
    v_hint := null;
    begin
      perform set_config('request.jwt.claim.sub', v_sa::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      update public.reservaciones set archivada_en = now() where id = v_viva;
      raise exception 'A2C2_PASO';
    exception when others then
      get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    end;
    perform set_config('role', v_quien, true);
    if v_hint is distinct from 'A2-C2' then
      v_fallos := v_fallos || format('c. archivar una reservación viva no lo frenó A2-C2: %s', v_msg);
    end if;
    v_casos := v_casos || ' (c) ejercido;';
  end if;

  -- d.
  if v_cerrada.id is null or v_cerrada.propietario_id is null then
    v_casos := v_casos || ' (d) sin datos;';
  else
    v_hint := null;
    begin
      perform set_config('request.jwt.claim.sub', v_cerrada.propietario_id::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_cerrada.propietario_id, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      update public.reservaciones set archivada_en = now() where id = v_cerrada.id;
      raise exception 'A2C2_PASO';
    exception when others then
      get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    end;
    perform set_config('role', v_quien, true);
    if v_hint is distinct from 'A2-C2' then
      v_fallos := v_fallos || format('d. la empresa pudo archivar (o la frenó otra cosa): %s', v_msg);
    end if;
    v_casos := v_casos || ' (d) ejercido;';
  end if;

  -- e.
  if v_sa is null or v_pagada is null then
    v_casos := v_casos || ' (e) sin datos;';
  else
    v_hint := null;
    begin
      perform set_config('request.jwt.claim.sub', v_sa::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      update public.reservaciones set archivada_en = now() where id = v_pagada;
      update public.reservaciones set pagado = false where id = v_pagada;
      raise exception 'A2C2_PASO';
    exception when others then
      get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    end;
    perform set_config('role', v_quien, true);
    if v_hint is distinct from 'A2-C2' then
      v_fallos := v_fallos || format('e. se revirtió el cobro de una archivada: %s', v_msg);
    end if;
    v_casos := v_casos || ' (e) ejercido;';
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  -- f.
  if v_cerrada.id is null then
    v_casos := v_casos || ' (f) sin datos;';
  else
    create temp table a2c2_alta (like public.reservaciones including defaults) on commit drop;
    create trigger a2c2_archivo before insert on a2c2_alta
      for each row execute function public.guard_reservacion_archivo();
    insert into a2c2_alta
      select (jsonb_populate_record(null::a2c2_alta,
                to_jsonb(v_cerrada) || jsonb_build_object('archivada_en', now(), 'archivada_por', v_sa))).*;
    if exists (select 1 from a2c2_alta where archivada_en is not null or archivada_por is not null) then
      v_fallos := v_fallos || 'f. una fila insertada con marca conservó la marca'::text;
    end if;
    v_casos := v_casos || ' (f) ejercido;';
  end if;

  if current_user <> v_quien then
    raise exception 'A2-C2: la comprobación dejó el rol en % (era %).', current_user, v_quien;
  end if;
  if cardinality(v_fallos) > 0 then
    raise exception E'A2-C2: no quedó como debe:\n  %\nCasos:%', array_to_string(v_fallos, E'\n  '), v_casos;
  end if;
  raise notice 'A2-C2: archivar es una marca del superadmin sobre lo cerrado; el histórico antiguo queda de solo lectura. Casos:%', v_casos;
end $$;
