-- ════════════════════════════════════════════════════════════════════════
-- A2-C5 · Una unidad en uso no se borra, y una oferta no apunta a la nada
-- ════════════════════════════════════════════════════════════════════════
--
-- ofertas.camion_id y reservaciones.unidad son texto sin clave foránea: el id
-- puede ser de camiones, custodios, patios o lavados, y la tabla se deduce del
-- tipo del pedido (recurso_tipo_de_servicio). Nada impedía:
--   · borrar una unidad con un viaje en curso o con una oferta todavía viva
--     —el cliente, al aceptar, recibía «La unidad … no existe» de
--     guard_unidad_existe, y la reservación en curso quedaba sin unidad—;
--   · guardar en una oferta un id que no existe o que es de otra tabla.
-- Medido en el volcado de producción del 28/09: 1 oferta aceptada y 1
-- reservación completada apuntan a una unidad borrada (F-303, el huérfano de
-- la 2ª auditoría). Ninguna oferta apunta a la tabla de otro tipo.
--
-- Decisión del usuario (08/10): proteger sin renombrar —la columna sigue
-- llamándose camion_id; ni Android ni docs/CONTRATO-MOVIL.md cambian— y dejar
-- las dos huérfanas como están: son historia cerrada.
--
--   1. guard_recurso_delete(), BEFORE DELETE en las cuatro tablas de flota:
--      frena el borrado si la unidad tiene una reservación viva (Pendiente,
--      Activa, PorAprobar, CancelacionSolicitada) o una oferta sobre un pedido
--      aún abierto (abierto, en_negociacion, pendiente_acuerdo). Lo cerrado no
--      frena: una oferta se queda 'aceptada' para siempre (21 de 21 en el
--      volcado), así que mirar solo el estado de la oferta bloquearía para
--      siempre cualquier camión que hubiera trabajado. Mismo criterio que
--      guard_operador_delete (S-08): aplica a todos, superadmin incluido.
--   2. guard_oferta_unidad(), BEFORE INSERT OR UPDATE OF camion_id en ofertas:
--      la unidad tiene que existir en la tabla del tipo del pedido. Una oferta
--      que no cambia de unidad no se revisa, así que la huérfana de F-303
--      sigue pudiendo actualizarse.
--
-- No borra nada. Reversible: desactivar los triggers.
-- Reglas de docs/AUDITORIA.md §4: 2, 3, 31, 31c, 32, 33, 47. Hallazgo: A2-C5.
-- ════════════════════════════════════════════════════════════════════════

-- 1 · No se borra una unidad en uso ────────────────────────────────────────
create or replace function public.guard_recurso_delete()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tipo    text := case tg_table_name
                      when 'camiones'  then 'camion'
                      when 'custodios' then 'custodio'
                      when 'patios'    then 'patio'
                      when 'lavados'   then 'lavado'
                    end;
  v_reserva uuid;
  v_pedido  uuid;
begin
  if v_tipo is null then
    raise exception 'guard_recurso_delete: tabla no prevista (%)', tg_table_name;
  end if;

  select r.id into v_reserva
    from public.reservaciones r
   where r.unidad = old.id
     and r.recurso_tipo = v_tipo
     and r.estado in ('Pendiente', 'Activa', 'PorAprobar', 'CancelacionSolicitada')
   limit 1;
  if v_reserva is not null then
    raise exception 'No se puede eliminar %: tiene un servicio en curso (reservación %). Espera a que se cierre o se cancele.', old.id, v_reserva
      using hint = 'A2-C5';
  end if;

  select p.id into v_pedido
    from public.ofertas o
    join public.pedidos p on p.id = o.pedido_id
   where o.camion_id = old.id
     and o.estado in ('enviada', 'contra_oferta', 'aceptada')
     and p.estado in ('abierto', 'en_negociacion', 'pendiente_acuerdo')
     and public.recurso_tipo_de_servicio(p.tipo_camion) = v_tipo
   limit 1;
  if v_pedido is not null then
    raise exception 'No se puede eliminar %: está ofrecida en una solicitud que sigue abierta (%). Retira la oferta o espera a que se resuelva.', old.id, v_pedido
      using hint = 'A2-C5';
  end if;

  return old;
end $$;

revoke all on function public.guard_recurso_delete() from public, anon, authenticated;

-- Sin DROP (Regla #1): cada trigger se crea solo si no existe.
do $$
declare
  t text;
begin
  foreach t in array array['camiones', 'custodios', 'patios', 'lavados'] loop
    if not exists (select 1 from pg_trigger
                    where tgrelid = format('public.%I', t)::regclass
                      and tgname = 'trg_guard_recurso_delete') then
      execute format('create trigger trg_guard_recurso_delete before delete on public.%I
                        for each row execute function public.guard_recurso_delete()', t);
    end if;
  end loop;
end $$;


-- 2 · Una oferta apunta a una unidad que existe, en la tabla de su tipo ─────
create or replace function public.guard_oferta_unidad()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tipo  text;
  v_tabla text;
  v_hay   boolean;
begin
  if new.camion_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.camion_id is not distinct from old.camion_id then
    return new;
  end if;

  select public.recurso_tipo_de_servicio(p.tipo_camion) into v_tipo
    from public.pedidos p where p.id = new.pedido_id;
  v_tabla := case v_tipo
               when 'camion'   then 'camiones'
               when 'custodio' then 'custodios'
               when 'patio'    then 'patios'
               when 'lavado'   then 'lavados'
             end;
  if v_tabla is null then
    raise exception 'La oferta no tiene una solicitud válida a la que asociar la unidad %', new.camion_id
      using hint = 'A2-C5';
  end if;

  execute format('select exists (select 1 from public.%I where id = $1)', v_tabla)
     into v_hay using new.camion_id;
  if not v_hay then
    raise exception 'La unidad % no existe entre tus % (o no es del tipo que pide la solicitud)', new.camion_id, v_tabla
      using hint = 'A2-C5';
  end if;
  return new;
end $$;

revoke all on function public.guard_oferta_unidad() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.ofertas'::regclass
                    and tgname = 'trg_guard_oferta_unidad') then
    create trigger trg_guard_oferta_unidad
      before insert or update of camion_id on public.ofertas
      for each row execute function public.guard_oferta_unidad();
  end if;
end $$;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
-- Estructura: los cinco triggers activos y del tipo correcto; las dos
-- funciones fuera del alcance de anon/authenticated.
-- Comportamiento, deshecho al terminar cada caso:
--   a. el dueño intenta borrar una unidad con reservación viva → A2-C5;
--   b. … una unidad ofrecida en una solicitud abierta → A2-C5;
--   c. … una unidad con solo historia cerrada → se borra;
--   d. una oferta con una unidad inexistente → A2-C5;
--   e. una oferta con una unidad de otra tabla → A2-C5;
--   f. una oferta huérfana se actualiza sin tocar su unidad → pasa.
-- (d–f sobre una tabla temporal con el mismo trigger: sin avisos ni guards
-- de alta de ofertas.) Como sabe fallar: sin los triggers, (a), (b), (d) y
-- (e) pasan.

do $$
declare
  v_quien  text := current_user;
  v_r      record;
  v_id     text;
  v_dueno  uuid;
  v_tabla  text;
  v_otro   text;
  v_oferta public.ofertas;
  v_fallos text[] := '{}';
  v_casos  text := '';
  v_msg    text;
  v_hint   text;
  t        text;
begin
  -- Estructura ───────────────────────────────────────────────────────────
  foreach t in array array['camiones', 'custodios', 'patios', 'lavados'] loop
    select tg.tgenabled, tg.tgtype, p.proname into v_r
      from pg_trigger tg join pg_proc p on p.oid = tg.tgfoid
     where tg.tgrelid = format('public.%I', t)::regclass and tg.tgname = 'trg_guard_recurso_delete';
    -- 1 ROW + 2 BEFORE + 8 DELETE = 11
    if not found or v_r.tgenabled = 'D' or (v_r.tgtype & 11) <> 11 or v_r.proname <> 'guard_recurso_delete' then
      v_fallos := v_fallos || format('%s: falta trg_guard_recurso_delete BEFORE DELETE FOR EACH ROW activo', t);
    end if;
  end loop;
  select tg.tgenabled, tg.tgtype, p.proname into v_r
    from pg_trigger tg join pg_proc p on p.oid = tg.tgfoid
   where tg.tgrelid = 'public.ofertas'::regclass and tg.tgname = 'trg_guard_oferta_unidad';
  -- 1 ROW + 2 BEFORE + 4 INSERT + 16 UPDATE = 23
  if not found or v_r.tgenabled = 'D' or (v_r.tgtype & 23) <> 23 or v_r.proname <> 'guard_oferta_unidad' then
    v_fallos := v_fallos || 'ofertas: falta trg_guard_oferta_unidad BEFORE INSERT OR UPDATE activo'::text;
  end if;
  if has_function_privilege('authenticated', 'public.guard_recurso_delete()', 'EXECUTE')
  or has_function_privilege('anon', 'public.guard_recurso_delete()', 'EXECUTE')
  or has_function_privilege('authenticated', 'public.guard_oferta_unidad()', 'EXECUTE')
  or has_function_privilege('anon', 'public.guard_oferta_unidad()', 'EXECUTE') then
    v_fallos := v_fallos || 'alguna de las dos funciones es ejecutable por anon o authenticated'::text;
  end if;

  -- a. reservación viva ─────────────────────────────────────────────────
  select r.unidad, r.propietario_id, case r.recurso_tipo when 'camion' then 'camiones'
           when 'custodio' then 'custodios' when 'patio' then 'patios' else 'lavados' end
    into v_id, v_dueno, v_tabla
    from public.reservaciones r
   where r.estado in ('Pendiente', 'Activa', 'PorAprobar', 'CancelacionSolicitada')
     and r.propietario_id is not null
     and exists (select 1 from public.camiones c where c.id = r.unidad and r.recurso_tipo = 'camion'
                 union all select 1 from public.custodios c where c.id = r.unidad and r.recurso_tipo = 'custodio'
                 union all select 1 from public.patios c where c.id = r.unidad and r.recurso_tipo = 'patio'
                 union all select 1 from public.lavados c where c.id = r.unidad and r.recurso_tipo = 'lavado')
   order by r.created_at limit 1;
  if v_id is null then
    v_casos := v_casos || ' (a) sin datos;';
  else
    v_hint := null;
    begin
      perform set_config('request.jwt.claim.sub', v_dueno::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_dueno, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      execute format('delete from public.%I where id = $1', v_tabla) using v_id;
      raise exception 'A2C5_PASO';
    exception when others then
      get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    end;
    perform set_config('role', v_quien, true);
    if v_hint is distinct from 'A2-C5' then
      v_fallos := v_fallos || format('a. borrar una unidad con viaje vivo no lo frenó A2-C5: %s', v_msg);
    end if;
    v_casos := v_casos || ' (a) ejercido;';
  end if;

  -- b. oferta sobre solicitud abierta, sin reservación viva ─────────────
  v_id := null;
  select o.camion_id, x.propietario_id, x.tabla into v_id, v_dueno, v_tabla
    from public.ofertas o
    join public.pedidos p on p.id = o.pedido_id
    join lateral (
      select c.propietario_id, 'camiones' as tabla from public.camiones c
       where c.id = o.camion_id and public.recurso_tipo_de_servicio(p.tipo_camion) = 'camion'
      union all select c.propietario_id, 'custodios' from public.custodios c
       where c.id = o.camion_id and public.recurso_tipo_de_servicio(p.tipo_camion) = 'custodio'
      union all select c.propietario_id, 'patios' from public.patios c
       where c.id = o.camion_id and public.recurso_tipo_de_servicio(p.tipo_camion) = 'patio'
      union all select c.propietario_id, 'lavados' from public.lavados c
       where c.id = o.camion_id and public.recurso_tipo_de_servicio(p.tipo_camion) = 'lavado') x on true
   where o.estado in ('enviada', 'contra_oferta', 'aceptada')
     and p.estado in ('abierto', 'en_negociacion', 'pendiente_acuerdo')
     and not exists (select 1 from public.reservaciones r
                      where r.unidad = o.camion_id
                        and r.estado in ('Pendiente', 'Activa', 'PorAprobar', 'CancelacionSolicitada'))
   limit 1;
  if v_id is null then
    v_casos := v_casos || ' (b) sin datos;';
  else
    v_hint := null;
    begin
      perform set_config('request.jwt.claim.sub', v_dueno::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_dueno, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      execute format('delete from public.%I where id = $1', v_tabla) using v_id;
      raise exception 'A2C5_PASO';
    exception when others then
      get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    end;
    perform set_config('role', v_quien, true);
    if v_hint is distinct from 'A2-C5' then
      v_fallos := v_fallos || format('b. borrar una unidad ofrecida en una solicitud abierta no lo frenó A2-C5: %s', v_msg);
    end if;
    v_casos := v_casos || ' (b) ejercido;';
  end if;

  -- c. solo historia cerrada → se puede borrar ──────────────────────────
  v_id := null;
  select c.id, c.propietario_id into v_id, v_dueno
    from public.camiones c
   where c.propietario_id is not null
     and not exists (select 1 from public.reservaciones r
                      where r.unidad = c.id and r.recurso_tipo = 'camion'
                        and r.estado in ('Pendiente', 'Activa', 'PorAprobar', 'CancelacionSolicitada'))
     and not exists (select 1 from public.ofertas o join public.pedidos p on p.id = o.pedido_id
                      where o.camion_id = c.id
                        and o.estado in ('enviada', 'contra_oferta', 'aceptada')
                        and p.estado in ('abierto', 'en_negociacion', 'pendiente_acuerdo'))
   order by (exists (select 1 from public.ofertas o where o.camion_id = c.id)) desc, c.created_at
   limit 1;
  if v_id is null then
    v_casos := v_casos || ' (c) sin datos;';
  else
    begin
      perform set_config('request.jwt.claim.sub', v_dueno::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_dueno, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      delete from public.camiones where id = v_id;
      raise exception 'A2C5_FIN_C';
    exception when others then
      perform set_config('role', v_quien, true);
      if sqlerrm <> 'A2C5_FIN_C' then
        v_fallos := v_fallos || format('c. el dueño no pudo borrar una unidad sin uso vivo (%s): %s', v_id, sqlerrm);
      end if;
    end;
    v_casos := v_casos || ' (c) ejercido;';
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  -- d, e, f: tabla temporal con el mismo trigger ────────────────────────
  select o.* into v_oferta
    from public.ofertas o join public.pedidos p on p.id = o.pedido_id
   where o.camion_id is not null and public.recurso_tipo_de_servicio(p.tipo_camion) = 'camion'
     and exists (select 1 from public.camiones c where c.id = o.camion_id)
   order by o.created_at limit 1;
  if v_oferta.id is null then
    v_casos := v_casos || ' (d,e,f) sin datos;';
  else
    create temp table a2c5_ofertas (like public.ofertas including defaults) on commit drop;
    -- f: la huérfana entra ANTES del trigger, como una fila vieja
    insert into a2c5_ofertas
      select (jsonb_populate_record(null::a2c5_ofertas,
                to_jsonb(v_oferta) || jsonb_build_object('id', gen_random_uuid(), 'camion_id', 'A2C5-NO-EXISTE'))).*;
    create trigger a2c5_unidad before insert or update of camion_id on a2c5_ofertas
      for each row execute function public.guard_oferta_unidad();

    -- d.
    v_hint := null;
    begin
      insert into a2c5_ofertas
        select (jsonb_populate_record(null::a2c5_ofertas,
                  to_jsonb(v_oferta) || jsonb_build_object('id', gen_random_uuid(), 'camion_id', 'A2C5-NO-EXISTE-2'))).*;
      raise exception 'A2C5_PASO';
    exception when others then
      get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    end;
    if v_hint is distinct from 'A2-C5' then
      v_fallos := v_fallos || format('d. una oferta con unidad inexistente entró: %s', v_msg);
    end if;

    -- e. un id real, pero de otra tabla
    select id into v_otro from (select id from public.custodios union all select id from public.patios
                                union all select id from public.lavados) x
     where not exists (select 1 from public.camiones c where c.id = x.id) limit 1;
    if v_otro is null then
      v_casos := v_casos || ' (e) sin datos;';
    else
      v_hint := null;
      begin
        insert into a2c5_ofertas
          select (jsonb_populate_record(null::a2c5_ofertas,
                    to_jsonb(v_oferta) || jsonb_build_object('id', gen_random_uuid(), 'camion_id', v_otro))).*;
        raise exception 'A2C5_PASO';
      exception when others then
        get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
      end;
      if v_hint is distinct from 'A2-C5' then
        v_fallos := v_fallos || format('e. una oferta de camión con la unidad %s de otra tabla entró: %s', v_otro, v_msg);
      end if;
      v_casos := v_casos || ' (e) ejercido;';
    end if;

    -- la unidad correcta sí entra (si no, d y e «pasarían» por el motivo equivocado)
    begin
      insert into a2c5_ofertas
        select (jsonb_populate_record(null::a2c5_ofertas,
                  to_jsonb(v_oferta) || jsonb_build_object('id', gen_random_uuid()))).*;
    exception when others then
      v_fallos := v_fallos || format('d. una oferta con su unidad real no entró: %s', sqlerrm);
    end;

    -- f.
    begin
      update a2c5_ofertas set estado = 'rechazada' where camion_id = 'A2C5-NO-EXISTE';
    exception when others then
      v_fallos := v_fallos || format('f. una oferta huérfana no se pudo actualizar sin tocar su unidad: %s', sqlerrm);
    end;
    v_casos := v_casos || ' (d,f) ejercidos;';
  end if;

  if current_user <> v_quien then
    raise exception 'A2-C5: la comprobación dejó el rol en % (era %).', current_user, v_quien;
  end if;
  if cardinality(v_fallos) > 0 then
    raise exception E'A2-C5: no quedó como debe:\n  %\nCasos:%', array_to_string(v_fallos, E'\n  '), v_casos;
  end if;
  raise notice 'A2-C5: una unidad en uso no se borra y una oferta solo apunta a una unidad de su tipo. Casos:%', v_casos;
end $$;
