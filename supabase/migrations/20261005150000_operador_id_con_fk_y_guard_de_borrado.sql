-- ════════════════════════════════════════════════════════════════════════
-- S-08 · reservaciones.operador_id y ofertas.operador_id sin clave foránea
-- ════════════════════════════════════════════════════════════════════════
--
-- El hallazgo (6ª auditoría, 2026-10-01). Las dos columnas guardan el id de
-- un chofer (`operadores.id`, text) sin FK: nada impedía borrar un chofer
-- referenciado ni dejar ids que no existen. Las leen cerrar_acuerdo,
-- enviar_oferta, guard_operador_hazmat, guard_reservacion_update y
-- datos_carta_porte (la Carta Porte toma de ahí el CURP y la licencia).
-- Medido el 05/10 en el volcado: reservaciones 2 con chofer (las 2 vivas),
-- ofertas 27 (16 vivas), 0 huérfanas.
--
-- Medido también, en banco local: con una FK `ON DELETE SET NULL`, el dueño
-- pudo borrar a un chofer asignado a una reservación EN CURSO — el viaje se
-- quedaba sin chofer, y un servicio de camión no puede avanzar el
-- seguimiento sin él (FLUJO-OPERATIVO.md, «chofer antes de avanzar»).
--
-- Decisión del usuario (05/10): bloquear el borrado si el chofer tiene un
-- viaje vivo; en lo demás, SET NULL.
--   1. FK reservaciones.operador_id → operadores(id) ON DELETE SET NULL.
--   2. FK ofertas.operador_id       → operadores(id) ON DELETE SET NULL.
--      Cada una con su índice parcial `WHERE operador_id IS NOT NULL`, como
--      H-13: que borrar un chofer no recorra las tablas.
--      El nombre del chofer se conserva en reservaciones.operador_nombre y
--      ofertas.operador_nombre; lo que se pierde en un viaje terminado es el
--      enlace (la Carta Porte de ese viaje ya no trae su CURP ni licencia).
--   3. guard_operador_delete (BEFORE DELETE en operadores): rechaza el borrado
--      si el chofer está en una reservación Pendiente, Activa, PorAprobar o
--      CancelacionSolicitada, y dice cuál. Corre antes que el SET NULL de la
--      FK (las acciones referenciales son AFTER). Vale para todos los roles,
--      superadmin incluido: el camino es reasignar el viaje primero.
--
-- Si hubiera referencias huérfanas, la migración aborta antes de crear nada:
-- una FK no se crea sobre datos que la violan, y elegir qué hacer con ellas
-- es una decisión aparte.
--
-- Del lado del cliente: js/operadores.js eliminarOperador() no miraba el
-- error y decía «eliminado» siempre; se corrige en el mismo cambio (regla 24).
-- Android define eliminarOperador pero ninguna pantalla lo llama.
--
-- Reglas de docs/AUDITORIA.md §4: 1, 2, 5, 13, 15, 24.
-- ════════════════════════════════════════════════════════════════════════

do $$
declare
  v_res int;
  v_ofe int;
begin
  select count(*) into v_res from public.reservaciones r
   where r.operador_id is not null and not exists (select 1 from public.operadores o where o.id = r.operador_id);
  select count(*) into v_ofe from public.ofertas f
   where f.operador_id is not null and not exists (select 1 from public.operadores o where o.id = f.operador_id);
  if v_res + v_ofe > 0 then
    raise exception 'S-08: hay referencias a choferes que no existen (reservaciones %, ofertas %). No se crea la FK: decidir antes qué hacer con ellas.', v_res, v_ofe;
  end if;
end $$;

create index if not exists idx_reservaciones_operador
  on public.reservaciones (operador_id) where operador_id is not null;
create index if not exists idx_ofertas_operador
  on public.ofertas (operador_id) where operador_id is not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'reservaciones_operador_id_fkey') then
    alter table public.reservaciones
      add constraint reservaciones_operador_id_fkey
      foreign key (operador_id) references public.operadores(id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ofertas_operador_id_fkey') then
    alter table public.ofertas
      add constraint ofertas_operador_id_fkey
      foreign key (operador_id) references public.operadores(id) on delete set null;
  end if;
end $$;

create or replace function public.guard_operador_delete()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_reserva uuid;
begin
  -- S-08 (20261005150000): el chofer de un viaje vivo no se borra.
  select r.id into v_reserva
    from public.reservaciones r
   where r.operador_id = old.id
     and r.estado in ('Pendiente', 'Activa', 'PorAprobar', 'CancelacionSolicitada')
   limit 1;

  if v_reserva is not null then
    raise exception 'No se puede eliminar al operador %: está asignado a un servicio en curso (reservación %). Asigna otro chofer a ese servicio y vuelve a intentarlo.', old.id, v_reserva
      using hint = 'S-08';
  end if;

  return old;
end $$;

revoke all on function public.guard_operador_delete() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.operadores'::regclass
                    and tgname = 'trg_guard_operador_delete') then
    create trigger trg_guard_operador_delete
      before delete on public.operadores
      for each row execute function public.guard_operador_delete();
  end if;
end $$;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--   · Catálogo: las dos FK existen, validadas y ON DELETE SET NULL; sus dos
--     índices existen; el trigger es BEFORE DELETE FOR EACH ROW sobre la
--     función; la función no es ejecutable por anon ni authenticated.
--   · Funcional, con choferes reales, cada caso en una subtransacción que se
--     deshace entera (no se borra nada):
--       a. el dueño borra un chofer con reservación viva → rechazo (S-08)
--       b. el dueño borra un chofer sin reservación viva → pasa, sus
--          reservaciones y ofertas quedan con operador_id NULL, y las ofertas
--          conservan operador_nombre
--     Si en esta base no hay choferes de alguno de los dos tipos, ese caso no
--     se puede ejercer y el aviso final lo dice.
-- Como sabe fallar: sin el trigger, (a) pasa; sin la FK, (b) deja el id
-- colgando.

do $$
declare
  v_quien  text := current_user;
  v_fallos text[] := '{}';
  v_fk     record;
  v_t      record;
  v_op     text;
  v_dueno  uuid;
  v_msg    text;
  v_hint   text;
  v_casos  text := '';
  v_quedan int;
  v_nombres int;
  v_ofertas uuid[];
begin
  for v_fk in
    select c.conname, c.confdeltype, c.convalidated
      from pg_constraint c
     where c.conname in ('reservaciones_operador_id_fkey', 'ofertas_operador_id_fkey')
  loop
    if v_fk.confdeltype <> 'n' then
      v_fallos := v_fallos || format('%s no es ON DELETE SET NULL', v_fk.conname);
    end if;
    if not v_fk.convalidated then
      v_fallos := v_fallos || format('%s no está validada', v_fk.conname);
    end if;
  end loop;
  if (select count(*) from pg_constraint
       where conname in ('reservaciones_operador_id_fkey', 'ofertas_operador_id_fkey')) <> 2 then
    v_fallos := v_fallos || 'falta alguna de las dos FK'::text;
  end if;
  if (select count(*) from pg_class
       where relname in ('idx_reservaciones_operador', 'idx_ofertas_operador') and relkind = 'i') <> 2 then
    v_fallos := v_fallos || 'falta alguno de los dos índices'::text;
  end if;

  select t.tgenabled, t.tgtype, p.proname into v_t
    from pg_trigger t join pg_proc p on p.oid = t.tgfoid
   where t.tgrelid = 'public.operadores'::regclass and t.tgname = 'trg_guard_operador_delete';
  if not found or v_t.tgenabled = 'D' or (v_t.tgtype & 11) <> 11 or v_t.proname <> 'guard_operador_delete' then
    v_fallos := v_fallos || 'trg_guard_operador_delete no es un BEFORE DELETE FOR EACH ROW activo sobre guard_operador_delete'::text;
  end if;
  if has_function_privilege('authenticated', 'public.guard_operador_delete()', 'EXECUTE')
  or has_function_privilege('anon', 'public.guard_operador_delete()', 'EXECUTE') then
    v_fallos := v_fallos || 'guard_operador_delete() es ejecutable por anon o authenticated'::text;
  end if;

  -- a. chofer con reservación viva
  select o.id, o.propietario_id into v_op, v_dueno
    from public.operadores o
   where exists (select 1 from public.reservaciones r
                  where r.operador_id = o.id
                    and r.estado in ('Pendiente', 'Activa', 'PorAprobar', 'CancelacionSolicitada'))
   order by o.created_at limit 1;
  if v_op is null then
    v_casos := v_casos || ' (a) sin datos;';
  else
    v_hint := null;
    begin
      perform set_config('request.jwt.claim.sub', v_dueno::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_dueno, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      delete from public.operadores where id = v_op;
      raise exception 'S08_PASO';
    exception when others then
      get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    end;
    perform set_config('role', v_quien, true);
    if v_hint is distinct from 'S-08' then
      v_fallos := v_fallos || format('a. borrar un chofer con viaje vivo no lo frenó S-08: %s', v_msg);
    end if;
    v_casos := v_casos || ' (a) ejercido;';
  end if;

  -- b. chofer sin reservación viva
  v_op := null;
  select o.id, o.propietario_id into v_op, v_dueno
    from public.operadores o
   where not exists (select 1 from public.reservaciones r
                      where r.operador_id = o.id
                        and r.estado in ('Pendiente', 'Activa', 'PorAprobar', 'CancelacionSolicitada'))
   order by (exists (select 1 from public.ofertas f where f.operador_id = o.id)) desc, o.created_at
   limit 1;
  if v_op is null then
    v_casos := v_casos || ' (b) sin datos;';
  else
    select coalesce(array_agg(id), '{}'), count(*) filter (where operador_nombre is not null)
      into v_ofertas, v_nombres
      from public.ofertas where operador_id = v_op;
    begin
      perform set_config('request.jwt.claim.sub', v_dueno::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_dueno, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      delete from public.operadores where id = v_op;
      perform set_config('role', v_quien, true);

      select count(*) into v_quedan from (
        select 1 from public.reservaciones where operador_id = v_op
        union all select 1 from public.ofertas where operador_id = v_op) x;
      if v_quedan > 0 then
        v_fallos := v_fallos || format('b. tras borrar %s quedan %s referencias a él (sin SET NULL)', v_op, v_quedan);
      end if;
      if v_quedan = 0 and v_nombres > 0 and (select count(*) from public.ofertas
                              where operador_id is null and operador_nombre is not null
                                and id = any (v_ofertas)) <> v_nombres then
        v_fallos := v_fallos || 'b. las ofertas del chofer borrado perdieron operador_nombre'::text;
      end if;
      raise exception 'S08_FIN_B';
    exception when others then
      perform set_config('role', v_quien, true);
      if sqlerrm <> 'S08_FIN_B' then
        v_fallos := v_fallos || format('b. el dueño no pudo borrar un chofer sin viaje vivo: %s', sqlerrm);
      end if;
    end;
    v_casos := v_casos || ' (b) ejercido;';
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  if current_user <> v_quien then
    raise exception 'S-08: la comprobación dejó el rol en % (era %).', current_user, v_quien;
  end if;
  if cardinality(v_fallos) > 0 then
    raise exception E'S-08: no quedó como debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'S-08: operador_id con FK (SET NULL) en reservaciones y ofertas, y el chofer de un viaje vivo no se borra. Casos:%', v_casos;
end $$;
