-- ═════════════════════════════════════════════════════════════════════════
-- Q-12 · Una empresa, una oferta viva por solicitud
-- Q-13 · Los importes no pueden ser cero ni negativos
-- ═════════════════════════════════════════════════════════════════════════
--
-- Q-12 (quinta auditoria, 2026-09-29): nada en la base impide que una
-- empresa tenga dos ofertas vivas en la misma solicitud. Solo lo frena la
-- interfaz: `openHacerOferta` y `_enviarOfertaCore` (js/pedidos.js) buscan
-- una oferta propia en `enviada`, `contra_oferta` o `aceptada` y, si la hay,
-- no dejan ofertar. Dos pestanas, o una llamada directa a la API, lo saltan.
--   Arreglo: indice UNICO PARCIAL sobre (pedido_id, admin_id) para esos tres
--   estados — exactamente los que la interfaz ya trata como «oferta activa».
--   Volver a ofertar tras un rechazo sigue funcionando: la anterior queda
--   `rechazada`. Al cancelar una reservacion, `cancelar_reservacion()` pasa
--   la oferta aceptada a `rechazada` antes de reabrir el pedido (medido el
--   2026-09-30), asi que tampoco se bloquea esa via.
--
-- Q-13 (quinta auditoria, 2026-09-29): los importes del flujo admiten 0 o
-- negativos. La interfaz exige precio > 0 en oferta y contraoferta, pero la
-- base no. Arreglo: CHECK en cada importe — `> 0`, o NULL donde el campo es
-- opcional:
--   · ofertas.precio_oferta   (NOT NULL)  > 0
--   · ofertas.contra_precio   (opcional)  NULL o > 0
--   · pedidos.precio_cliente  (opcional)  NULL o > 0
--   · reservaciones.precio_acordado (opcional) NULL o > 0
--   FUERA A PROPOSITO: `pagos.monto`. La tabla tiene 0 filas y la esta
--   preparando Salvador para Stripe; como se registren reembolsos u otros
--   movimientos lo decide ese diseño, no esta migracion.
--
-- Violaciones existentes, medidas en el volcado de produccion del 28/09 (sus
-- conteos de filas no han cambiado desde entonces): 0 en las dos. Las
-- restricciones se crean VALIDADAS: si una base tuviera una fila que las
-- incumple, la migracion aborta entera y la fila se ve, no se corrige sola.
--
-- Reglas de docs/AUDITORIA.md §4: 2 (bloque que sabe fallar), 9 (sin DROP:
-- todo se crea solo si no existe), 16 (nada de reglas solo en el cliente).
-- ═════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- 1. Q-12: el indice unico parcial
-- ─────────────────────────────────────────────────────────────────────────

create unique index if not exists uq_ofertas_viva_por_empresa
  on public.ofertas (pedido_id, admin_id)
  where estado in ('enviada', 'contra_oferta', 'aceptada');

comment on index public.uq_ofertas_viva_por_empresa is
  'Q-12: una empresa solo puede tener una oferta viva (enviada, contra_oferta '
  'o aceptada) por solicitud. Mismos estados que la interfaz trata como '
  '«oferta activa». Ver 20260930170000.';


-- ─────────────────────────────────────────────────────────────────────────
-- 2. Q-13: los CHECK de importes (sin DROP: solo si no existen)
-- ─────────────────────────────────────────────────────────────────────────

do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('ofertas',       'ofertas_precio_oferta_positivo',        'precio_oferta > 0'),
      ('ofertas',       'ofertas_contra_precio_positivo',        'contra_precio is null or contra_precio > 0'),
      ('pedidos',       'pedidos_precio_cliente_positivo',       'precio_cliente is null or precio_cliente > 0'),
      ('reservaciones', 'reservaciones_precio_acordado_positivo','precio_acordado is null or precio_acordado > 0')
    ) as t(tabla, nombre, expr)
  loop
    if not exists (select 1 from pg_constraint
                    where conrelid = format('public.%I', r.tabla)::regclass and conname = r.nombre) then
      execute format('alter table public.%I add constraint %I check (%s)', r.tabla, r.nombre, r.expr);
    end if;
  end loop;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion — falla si el objetivo no se cumplio
-- ─────────────────────────────────────────────────────────────────────────
--
-- Se monta un pedido y una empresa de prueba (perfiles existentes) dentro de
-- una subtransaccion que se deshace entera, y se intenta:
--   · una segunda oferta viva de la misma empresa  → 23505 (indice unico);
--   · una nueva oferta tras rechazar la anterior    → tiene que entrar;
--   · importes en 0 y negativos                     → 23514 (CHECK).
-- Como sabe fallar: sin el indice la segunda oferta entra; sin los CHECK los
-- importes en 0 entran. Todo como postgres, sin JWT (auth.uid() NULL), asi
-- que los guards de INSERT dejan pasar y lo que se prueba es la restriccion.

do $$
declare
  v_cli    uuid;
  v_emp    uuid;
  v_ped    uuid;
  v_of     uuid;
  v_estado text;
  v_fallos text[] := '{}';
  v_caso   text;
  v_msg    text;
begin
  -- El catalogo.
  if not exists (select 1 from pg_indexes where schemaname = 'public'
                  and indexname = 'uq_ofertas_viva_por_empresa'
                  and indexdef like 'CREATE UNIQUE INDEX%(pedido_id, admin_id)%enviada%contra_oferta%aceptada%') then
    raise exception 'Q-12: falta el indice unico parcial uq_ofertas_viva_por_empresa, o no es el esperado.';
  end if;
  if (select count(*) from pg_constraint where conname in (
        'ofertas_precio_oferta_positivo', 'ofertas_contra_precio_positivo',
        'pedidos_precio_cliente_positivo', 'reservaciones_precio_acordado_positivo')
        and convalidated) <> 4 then
    raise exception 'Q-13: no estan los cuatro CHECK de importes, o alguno no esta validado.';
  end if;

  select user_id into v_cli from public.perfiles order by created_at limit 1;
  select user_id into v_emp from public.perfiles where user_id <> v_cli order by created_at limit 1;
  if v_cli is null or v_emp is null then
    raise exception 'Q-12/13: hacen falta dos perfiles para la prueba.';
  end if;

  begin
    -- Las marcas de servidor que usan el cron y cerrar_acuerdo(): sin ellas
    -- guard_pedido_update y guard_reservacion_insert rechazarian a postgres
    -- ANTES de llegar al CHECK, y la prueba fallaria por el motivo
    -- equivocado. Son locales a esta subtransaccion, que se deshace entera.
    perform set_config('portgo.sync', 'on', true);
    perform set_config('portgo.cierre_acuerdo', 'on', true);

    insert into public.pedidos (cliente_id, cliente_nombre, cliente_email, estado)
    values (v_cli, 'q12', 'q12@example.com', 'abierto') returning id into v_ped;

    insert into public.ofertas (pedido_id, admin_id, admin_nombre, precio_oferta)
    values (v_ped, v_emp, 'q12', 100) returning id into v_of;

    for v_caso in select unnest(array[
        'segunda_viva', 'reoferta_tras_rechazo',
        'oferta_cero', 'oferta_negativa', 'contra_cero',
        'pedido_cero', 'reserva_cero'])
    loop
      begin
        if v_caso = 'segunda_viva' then
          insert into public.ofertas (pedido_id, admin_id, admin_nombre, precio_oferta)
          values (v_ped, v_emp, 'q12', 90);
        elsif v_caso = 'reoferta_tras_rechazo' then
          update public.ofertas set estado = 'rechazada' where id = v_of;
          insert into public.ofertas (pedido_id, admin_id, admin_nombre, precio_oferta)
          values (v_ped, v_emp, 'q12', 80);
        elsif v_caso = 'oferta_cero' then
          update public.ofertas set precio_oferta = 0 where id = v_of;
        elsif v_caso = 'oferta_negativa' then
          update public.ofertas set precio_oferta = -1 where id = v_of;
        elsif v_caso = 'contra_cero' then
          update public.ofertas set contra_precio = 0 where id = v_of;
        elsif v_caso = 'pedido_cero' then
          update public.pedidos set precio_cliente = 0 where id = v_ped;
        elsif v_caso = 'reserva_cero' then
          insert into public.reservaciones (cliente, recurso_tipo, fecha_ini, fecha_fin, estado,
                                            cliente_user_id, propietario_id, precio_acordado)
          values ('q13', 'camion', '2099-01-01', '2099-01-02', 'Completada', v_cli, v_emp, 0);
        end if;
        raise exception 'Q12_ENTRO';
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      end;

      if v_caso = 'segunda_viva' and v_estado <> '23505' then
        v_fallos := v_fallos || format('%s: entro o fallo por otra cosa (%s %s)', v_caso, v_estado, v_msg);
      elsif v_caso = 'reoferta_tras_rechazo' and v_msg <> 'Q12_ENTRO' then
        v_fallos := v_fallos || format('%s: una reoferta legitima no entro (%s %s)', v_caso, v_estado, v_msg);
      elsif v_caso not in ('segunda_viva', 'reoferta_tras_rechazo') and v_estado <> '23514' then
        v_fallos := v_fallos || format('%s: el importe no lo freno un CHECK (%s %s)', v_caso, v_estado, v_msg);
      end if;
    end loop;

    raise exception 'Q12_FIN';
  exception when others then
    if sqlerrm <> 'Q12_FIN' then
      raise exception 'Q-12/13: la comprobacion no pudo montar sus datos de prueba: %', sqlerrm;
    end if;
  end;

  if exists (select 1 from public.pedidos where cliente_email = 'q12@example.com') then
    raise exception 'Q-12/13: quedaron datos de prueba sin deshacer.';
  end if;

  if cardinality(v_fallos) > 0 then
    raise exception E'Q-12/13: las restricciones no hacen lo que deben:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'Q-12/13: una oferta viva por empresa y solicitud, e importes > 0; 7 casos, todos como se esperaba.';
end $$;
