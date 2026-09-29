-- ═════════════════════════════════════════════════════════════════════════
-- Q-04 · Una oferta nueva podia nacer aceptada, en ronda 2, sin caducidad,
--        o sobre una solicitud que ya no admite ofertas
-- ═════════════════════════════════════════════════════════════════════════
--
-- El defecto (quinta auditoria, 2026-09-29, volcado de produccion del 28/09):
--
--   CREATE POLICY of_insert ON ofertas FOR INSERT TO authenticated
--     WITH CHECK (auth.uid() = admin_id AND <el autor es admin o superadmin>);
--
-- es todo lo que vigila el alta de una oferta. `guard_oferta_update` vigila
-- las transiciones... de una oferta que ya existe. Al crearla, una empresa
-- puede escribir directamente:
--
--   · `estado = 'aceptada'` (o 'contra_oferta', 'rechazada'),
--   · `ronda = 2`, `contra_precio`/`contra_mensaje` como si el cliente ya
--     hubiera contraofertado,
--   · `expira_en` en el año 3000 — la oferta no caduca nunca y
--     `sincronizar_estados_pedidos()` no la vence,
--   · sobre un pedido `pendiente_revision` (antes de que el superadmin lo
--     publique), `acordado`, `cancelado`, `finalizado`...
--
-- `enviar_oferta()` comprueba el estado del pedido, pero el navegador no la
-- usa (es una de las 5 RPC sin llamar, CLAUDE.md), y ademas esta desfasada:
-- exige chofer, que la web dejo de pedir.
--
-- El arreglo: guard BEFORE INSERT. Para un usuario final que no es
-- superadmin, la oferta nace como la crea hoy js/pedidos.js:2410 —que deja
-- `estado`, `ronda`, `contra_*` y `expira_en` a sus DEFAULT— y solo sobre un
-- pedido `abierto` o `en_negociacion`.
--
-- ─── Quien inserta ofertas hoy, y por que sigue funcionando ──────────────
--
--   · js/pedidos.js:2410 (_enviarOfertaCore): solo manda pedido, autor,
--     recurso, chofer, precio y mensaje. El resto sale de los DEFAULT:
--     'enviada', 1, NULL, now() + 2 dias. Pasa.
--   · La ronda 2 y la contraoferta NO son INSERT: pedidos.js:1998 y :2525
--     hacen UPDATE sobre la oferta existente. Las vigila guard_oferta_update.
--   · Volver a ofertar tras un rechazo es un INSERT nuevo con los DEFAULT.
--   · enviar_oferta(): inserta con los DEFAULT y ya exige el estado. Pasa.
--   · Android no inserta ofertas.
--   · Clave de servicio / postgres (auth.uid() NULL): pasa. Bloque 3.
--
-- ─── Por que SECURITY DEFINER ────────────────────────────────────────────
--
-- El guard lee `pedidos.estado`. Como INVOKER lo leeria a traves de la RLS de
-- la empresa, y la regla es sobre el estado del pedido, no sobre si la
-- empresa lo ve. Lee una sola columna de una sola fila, la de NEW.pedido_id,
-- y no devuelve nada salvo el rechazo. search_path fijado; EXECUTE revocado.
-- (Regla 13: DEFINER cuando hace falta, y aqui hace falta.)
--
-- Lo que NO cubre, a proposito (fuera de lo verificado como Q-04):
--   · que el recurso ofertado sea de la empresa y este aprobado;
--   · volver a ofertar cuando el cliente rechazo con `permite_reoferta =
--     false` — hoy solo lo frena la interfaz (pedidos.js:578);
--   · dos ofertas vivas de la misma empresa en el mismo pedido (Q-12);
--   · `precio_oferta > 0` (Q-13).
--
-- Reglas de docs/AUDITORIA.md §4: 1, 2, 6 (`trg_guard_oferta_insert` corre
-- antes que `trg_guard_operador_hazmat_ofertas`; los dos solo rechazan),
-- 9 (sin DROP), 13, 15 (guard_oferta_update no se toca), 29 (estados de los
-- CHECK: ofertas_estado_check, pedidos_estado_check).
-- ═════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- 1. El guard
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.guard_oferta_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_estado_pedido text;
begin
  -- Sin usuario final: clave de servicio o postgres. Ver cabecera y bloque 3.
  if auth.uid() is null then
    return new;
  end if;

  if public.is_superadmin() then
    return new;
  end if;

  if new.estado is distinct from 'enviada' then
    raise exception 'No autorizado: una oferta nueva nace enviada'
      using hint = 'Q-04';
  end if;

  if new.ronda is distinct from 1
     or new.contra_precio  is not null
     or new.contra_mensaje is not null then
    raise exception 'No autorizado: la ronda 2 y la contraoferta se hacen sobre la oferta existente, no creando otra'
      using hint = 'Q-04';
  end if;

  -- El DEFAULT es now() + 2 dias, con el mismo now() de esta transaccion.
  if new.expira_en is null or new.expira_en > now() + interval '2 days' then
    raise exception 'No autorizado: una oferta caduca a los 2 dias como maximo'
      using hint = 'Q-04';
  end if;

  select estado into v_estado_pedido from public.pedidos where id = new.pedido_id;
  if v_estado_pedido is null or v_estado_pedido not in ('abierto', 'en_negociacion') then
    raise exception 'Esta solicitud ya no admite ofertas.'
      using hint = 'Q-04';
  end if;

  return new;
end;
$$;

comment on function public.guard_oferta_insert() is
  'Q-04: un usuario final que no es superadmin solo puede crear ofertas '
  'enviadas, en ronda 1, sin contraoferta, con caducidad <= 2 dias y sobre un '
  'pedido abierto o en_negociacion. auth.uid() NULL pasa: ver 20260929160000.';

revoke all on function public.guard_oferta_insert() from public, anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. El trigger (sin DROP)
-- ─────────────────────────────────────────────────────────────────────────

do $$
begin
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.ofertas'::regclass
       and tgname  = 'trg_guard_oferta_insert'
       and not tgisinternal
  ) then
    create trigger trg_guard_oferta_insert
      before insert on public.ofertas
      for each row execute function public.guard_oferta_insert();
  end if;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion — falla si el objetivo no se cumplio
-- ─────────────────────────────────────────────────────────────────────────
--
-- Hacen falta pedidos en distintos estados. Se crean aqui, como postgres,
-- dentro de una subtransaccion que se deshace al final: se clona el cliente
-- de un perfil existente (la FK de pedidos.cliente_id lo exige) y nada mas.
--
-- Cada oferta se intenta como `authenticated` con un uid inventado:
--   · rechazo → HINT 'Q-04' (sin el guard llegaria a la RLS: 42501);
--   · legitima → 42501 de of_insert, que se evalua DESPUES del guard (el uid
--     inventado no tiene perfil de empresa). Si el guard la frenara, HINT.

do $$
declare
  v_cliente  uuid;
  v_ped      jsonb := '{}';
  v_est      text;
  v_id       uuid;
  v_caso     jsonb;
  v_debe     text;
  v_uid      uuid;
  v_cols     text;
  v_estado   text;
  v_hint     text;
  v_msg      text;
  v_quien    text := current_user;
  v_fallos   text[] := '{}';
  v_n        int := 0;
  v_pol      int;
begin
  -- 3a. Trigger, privilegios y supuestos del paso auth.uid() NULL.
  if not exists (
    select 1 from pg_trigger tg join pg_proc p on p.oid = tg.tgfoid
     where tg.tgrelid = 'public.ofertas'::regclass
       and tg.tgname  = 'trg_guard_oferta_insert'
       and tg.tgenabled <> 'D'
       and (tg.tgtype & 7) = 7
       and p.proname = 'guard_oferta_insert'
  ) then
    raise exception 'Q-04: falta o esta apagado trg_guard_oferta_insert.';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.ofertas'::regclass
                  and tgname = 'trg_guard_oferta_update' and tgenabled <> 'D') then
    raise exception 'Q-04: trg_guard_oferta_update no esta activo.';
  end if;
  if has_function_privilege('anon',          'public.guard_oferta_insert()', 'EXECUTE')
  or has_function_privilege('authenticated', 'public.guard_oferta_insert()', 'EXECUTE') then
    raise exception 'Q-04: guard_oferta_insert() sigue ejecutable por anon o authenticated.';
  end if;
  if has_table_privilege('anon', 'public.ofertas', 'INSERT') then
    raise exception 'Q-04: anon tiene INSERT en ofertas.';
  end if;
  select count(*) into v_pol from pg_policies
   where schemaname = 'public' and tablename = 'ofertas'
     and cmd in ('INSERT', 'ALL') and roles <> '{authenticated}'::name[];
  if v_pol > 0 then
    raise exception 'Q-04: ofertas tiene % politica(s) de INSERT que no son TO authenticated.', v_pol;
  end if;

  select user_id into v_cliente from public.perfiles order by created_at limit 1;
  if v_cliente is null then
    raise exception 'Q-04: no hay ningun perfil para colgar los pedidos de prueba.';
  end if;

  begin
    -- 3b. Pedidos de prueba, uno por estado que importa.
    foreach v_est in array array['abierto', 'en_negociacion', 'pendiente_revision', 'acordado', 'cancelado'] loop
      insert into public.pedidos (cliente_id, cliente_nombre, cliente_email, estado)
      values (v_cliente, 'q04', 'q04@example.com', v_est)
      returning id into v_id;
      v_ped := v_ped || jsonb_build_object(v_est, v_id);
    end loop;

    -- 3c. Los casos: (estado del pedido, columnas de la oferta, esperado).
    for v_est, v_caso, v_debe in
      select * from (values
        ('abierto',            '{}'::jsonb,                                  'pasa'),
        ('en_negociacion',     '{}'::jsonb,                                  'pasa'),
        ('abierto',            '{"estado":"aceptada"}'::jsonb,               'rechazo'),
        ('abierto',            '{"estado":"contra_oferta"}'::jsonb,          'rechazo'),
        ('abierto',            '{"estado":"rechazada"}'::jsonb,              'rechazo'),
        ('abierto',            '{"ronda":2}'::jsonb,                         'rechazo'),
        ('abierto',            '{"contra_precio":1}'::jsonb,                 'rechazo'),
        ('abierto',            '{"contra_mensaje":"x"}'::jsonb,              'rechazo'),
        ('abierto',            '{"expira_en":"3000-01-01T00:00:00Z"}'::jsonb,'rechazo'),
        ('abierto',            '{"expira_en":null}'::jsonb,                  'rechazo'),
        ('pendiente_revision', '{}'::jsonb,                                  'rechazo'),
        ('acordado',           '{}'::jsonb,                                  'rechazo'),
        ('cancelado',          '{}'::jsonb,                                  'rechazo')
      ) as t(e, c, d)
    loop
      v_n   := v_n + 1;
      v_uid := gen_random_uuid();
      v_caso := jsonb_build_object('pedido_id', v_ped ->> v_est, 'admin_id', v_uid,
                                   'admin_nombre', 'q04', 'precio_oferta', 100) || v_caso;
      select string_agg(quote_ident(k), ', ') into v_cols from jsonb_object_keys(v_caso) k;
      v_hint := null;

      begin
        perform set_config('request.jwt.claim.sub', v_uid::text, true);
        perform set_config('request.jwt.claims',
                           json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
        perform set_config('role', 'authenticated', true);
        execute format(
          'insert into public.ofertas (%1$s) select %1$s from jsonb_populate_record(null::public.ofertas, $1)',
          v_cols) using v_caso;
        raise exception 'Q04_SENTINELA';
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate,
                                v_msg    = message_text,
                                v_hint   = pg_exception_hint;
      end;

      if v_debe = 'rechazo' and v_hint is distinct from 'Q-04' then
        v_fallos := v_fallos || format('caso %s (pedido %s, %s) NO se rechazo: %s %s',
                                       v_n, v_est, v_caso - 'pedido_id' - 'admin_id', v_estado, v_msg);
      elsif v_debe = 'pasa' and v_estado <> '42501' then
        v_fallos := v_fallos || format('caso %s (pedido %s, %s) legitimo NO paso: %s %s',
                                       v_n, v_est, v_caso - 'pedido_id' - 'admin_id', v_estado, v_msg);
      end if;
    end loop;

    -- 3d. La clave de servicio no pasa por el guard (llega a la FK de admin_id).
    v_n := v_n + 1;
    begin
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claims', '', true);
      perform set_config('role', 'service_role', true);
      insert into public.ofertas (pedido_id, admin_id, admin_nombre, precio_oferta, estado)
      values ((v_ped ->> 'acordado')::uuid, gen_random_uuid(), 'q04', 100, 'aceptada');
      raise exception 'Q04_SENTINELA';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    end;
    if v_estado <> '23503' then
      v_fallos := v_fallos || format('service_role no paso el guard: %s %s', v_estado, v_msg);
    end if;

    -- Deshace los pedidos de prueba.
    raise exception 'Q04_FIN';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'Q04_FIN' then
      raise exception 'Q-04: la comprobacion no pudo montar sus pedidos de prueba: %', v_msg;
    end if;
  end;

  if current_user <> v_quien then
    raise exception 'Q-04: la comprobacion dejo el rol en % (era %).', current_user, v_quien;
  end if;

  if exists (select 1 from public.pedidos where cliente_email = 'q04@example.com') then
    raise exception 'Q-04: quedaron pedidos de prueba sin deshacer.';
  end if;

  if cardinality(v_fallos) > 0 then
    raise exception E'Q-04: el guard no hace lo que debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'Q-04: guard de INSERT en ofertas activo; % casos, todos como se esperaba.', v_n;
end $$;
