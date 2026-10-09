-- ════════════════════════════════════════════════════════════════════════
-- A2-M14 · Una solicitud de cuenta por usuario
-- ════════════════════════════════════════════════════════════════════════
--
-- El código trata solicitudes_cuenta.user_id como único: el login, el
-- registro y la ficha del superadmin la leen con .maybeSingle()
-- (js/auth.js:71, :150, :682; js/aprobaciones.js:947), y el re-registro la
-- actualiza por user_id. Pero la base solo tenía un índice normal. Con dos
-- filas —basta un doble clic en «Registrarse», que hace dos INSERT—,
-- .maybeSingle() devuelve error y data vacío: el login lo lee como «no tiene
-- solicitud» y la persona queda atascada.
--
-- Medido en el volcado de producción del 28/09: 7 filas, 7 usuarios. Aun así
-- la migración lo comprueba otra vez y, si encuentra duplicados, no toca nada.
--
-- El UNIQUE crea su propio índice sobre user_id, que sirve también a la FK
-- (ON DELETE CASCADE desde auth.users). idx_solicitudes_cuenta_user queda
-- repetido y se borra: autorizado por el usuario el 09/10 (Regla #1).
-- Para recrearlo:
--   create index idx_solicitudes_cuenta_user on public.solicitudes_cuenta (user_id);
--
-- No toca datos. Reglas de docs/AUDITORIA.md §4: 2, 9, 13, 32, 33.
-- ════════════════════════════════════════════════════════════════════════

do $$
declare
  v_dup text;
begin
  select string_agg(format('%s (%s filas)', user_id, n), ', ') into v_dup
    from (select user_id, count(*) n from public.solicitudes_cuenta
           group by user_id having count(*) > 1) d;
  if v_dup is not null then
    raise exception 'A2-M14: hay usuarios con más de una solicitud; no se toca nada. Resolver a mano antes: %', v_dup;
  end if;

  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.solicitudes_cuenta'::regclass
                    and conname = 'solicitudes_cuenta_user_id_key') then
    alter table public.solicitudes_cuenta
      add constraint solicitudes_cuenta_user_id_key unique (user_id);
  end if;
end $$;

drop index if exists public.idx_solicitudes_cuenta_user;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--   · hay un UNIQUE exactamente sobre (user_id) y el índice viejo no está;
--   · una segunda solicitud para un usuario que ya tiene una → 23505.
-- Como sabe fallar: sin el ALTER, la segunda solicitud entra.
do $$
declare
  v_fallos text[] := '{}';
  v_fila   public.solicitudes_cuenta;
  v_estado text;
begin
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'public.solicitudes_cuenta'::regclass and c.contype = 'u'
                    and c.conkey = array[(select attnum from pg_attribute
                                           where attrelid = 'public.solicitudes_cuenta'::regclass
                                             and attname = 'user_id')]) then
    v_fallos := v_fallos || 'no hay un UNIQUE sobre solicitudes_cuenta(user_id)'::text;
  end if;
  if to_regclass('public.idx_solicitudes_cuenta_user') is not null then
    v_fallos := v_fallos || 'idx_solicitudes_cuenta_user sigue existiendo'::text;
  end if;

  select * into v_fila from public.solicitudes_cuenta order by created_at limit 1;
  if v_fila.id is null then
    raise notice 'A2-M14: no hay solicitudes; se comprobó solo la estructura.';
  else
    v_estado := null;
    begin
      insert into public.solicitudes_cuenta
        select (jsonb_populate_record(null::public.solicitudes_cuenta,
                  to_jsonb(v_fila) || jsonb_build_object('id', gen_random_uuid()))).*;
      raise exception 'A2M14_PASO';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate;
    end;
    if v_estado is distinct from '23505' then
      v_fallos := v_fallos || format('una segunda solicitud del mismo usuario no la frenó el UNIQUE (sqlstate %s)', v_estado);
    end if;
  end if;

  if cardinality(v_fallos) > 0 then
    raise exception E'A2-M14: no quedó como debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;
  raise notice 'A2-M14: una solicitud de cuenta por usuario; el índice repetido, fuera.';
end $$;
