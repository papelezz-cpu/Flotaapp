-- ════════════════════════════════════════════════════════════════════════
-- A2-C3 · Una empresa podía reescribir la solicitud de otro cliente
-- ════════════════════════════════════════════════════════════════════════
--
-- El defecto (2ª auditoría, 28/08; dado por cerrado en la 3ª sin estarlo;
-- EJECUTADO por primera vez en la 6ª, 2026-10-01, en banco local con el
-- esquema de producción). `ped_update` deja a cualquier `admin` actualizar
-- pedidos, sin WITH CHECK, y `guard_pedido_update()` en su rama de empresa
-- solo mira `estado`: con la solicitud en `abierto`/`en_negociacion` hace
-- RETURN NEW para todo lo demás. Resultado medido: una empresa cambió origen,
-- destino, precio_cliente = 1, fechas y cliente_email de la solicitud abierta
-- de un cliente ajeno. Solo el cambio de estado a cancelado se rechazó.
--
-- Lo que la empresa escribe en pedidos de forma legítima, inventariado el
-- 01/10 en la web, Android y todas las funciones que hacen UPDATE pedidos:
--   · estado → en_negociacion al ofertar (js/pedidos.js:2031, :2448;
--     enviar_oferta, responder_oferta, responder_contraoferta);
--   · estado pendiente_acuerdo → acordado (cerrar_acuerdo);
--   · estado acordado → abierto y oferta_pendiente_id → NULL cuando cancela
--     (cancelar_reservacion).
-- updated_at lo pone trg_updated_at, que corre DESPUÉS de este guard.
-- Detalles de lugar/hora, edición y reenvío de la solicitud son del cliente o
-- del superadmin, que salen antes por sus propias ramas.
--
-- El arreglo: al entrar en la rama de empresa, todo lo que no sea `estado`
-- (ni `updated_at`) tiene que quedar igual, y `oferta_pendiente_id` solo
-- puede quedarse o pasar a NULL. Las transiciones de estado no cambian.
-- Se elige el guard y no la política (`ped_update`) porque la política no
-- puede comparar OLD con NEW, y porque la empresa sí necesita escribir
-- `estado` en solicitudes ajenas.
--
-- Lo que NO toca: la rama del cliente (Q-15 queda abierto por decisión del
-- usuario, 30/09), la del superadmin, la del cron (portgo.sync) ni la de
-- orfandad por borrado de cuenta.
--
-- La función NO se reescribe a mano (regla 3; R-11): se inserta el bloque
-- sobre la definición viva, justo después de `IF es_admin THEN`, y la
-- comprobación verifica que es lo único que cambió.
--
-- Reglas de docs/AUDITORIA.md §4: 2, 3, 15, 16, 31.
-- ════════════════════════════════════════════════════════════════════════


create temporary table a2c3_antes on commit drop as
  select pg_get_functiondef('public.guard_pedido_update()'::regprocedure) as def,
         false as ya_estaba,
         null::text as esperado;

do $$
declare
  v_def    text;
  v_n      int;
  v_ancla  constant text := 'IF es_admin THEN';
  v_bloque constant text :=
       'IF es_admin THEN' || E'\n'
    || '    -- A2-C3 (20261001150000): una empresa solo cambia el estado de una solicitud' || E'\n'
    || '    -- ajena (y suelta oferta_pendiente_id al cancelar). Todo lo demas, igual.' || E'\n'
    || '    IF (to_jsonb(NEW) - ''estado'' - ''oferta_pendiente_id'' - ''updated_at'')' || E'\n'
    || '       IS DISTINCT FROM (to_jsonb(OLD) - ''estado'' - ''oferta_pendiente_id'' - ''updated_at'')' || E'\n'
    || '       OR (NEW.oferta_pendiente_id IS DISTINCT FROM OLD.oferta_pendiente_id' || E'\n'
    || '           AND NEW.oferta_pendiente_id IS NOT NULL) THEN' || E'\n'
    || '      RAISE EXCEPTION ''No autorizado: una empresa solo puede cambiar el estado de una solicitud''' || E'\n'
    || '        USING HINT = ''A2-C3'';' || E'\n'
    || '    END IF;' || E'\n';
begin
  select def into v_def from a2c3_antes;

  if position('USING HINT = ''A2-C3''' in v_def) > 0 then
    update a2c3_antes set ya_estaba = true;
    return;
  end if;

  v_n := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_n <> 1 then
    raise exception 'A2-C3: guard_pedido_update() tiene % veces «%» (se esperaba 1). La función viva no es la que se midió: no se toca.', v_n, v_ancla;
  end if;

  v_def := replace(v_def, v_ancla, v_bloque);
  update a2c3_antes set esperado = v_def;
  execute v_def;
end $$;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--
-- Con una solicitud `abierto` de prueba de un cliente real y una empresa
-- real ajena a ella, dentro de una subtransacción que se deshace entera:
--
--   como la EMPRESA                                         debe
--   1. origen, destino                                      rechazarse (A2-C3)
--   2. precio_cliente                                       rechazarse (A2-C3)
--   3. cliente_email                                        rechazarse (A2-C3)
--   4. estado → en_negociacion y otra columna a la vez      rechazarse (A2-C3)
--   5. oferta_pendiente_id → una oferta real                rechazarse (A2-C3)
--   6. estado → en_negociacion (ofertar)                    pasar
--   7. estado → cancelado                                   rechazarse (la regla de siempre)
--   como el CLIENTE
--   8. descripcion                                          pasar (su rama no cambia)
--
-- Como sabe fallar: sin el bloque, 1–5 pasan.

do $$
declare
  v_antes  text;
  v_ahora  text;
  v_esp    text;
  v_ya     boolean;
  v_cli    uuid;
  v_emp    uuid;
  v_ped    uuid;
  v_of     uuid;
  v_quien  text := current_user;
  v_fallos text[] := '{}';
  v_set    text[];
  v_quien_caso text[];
  v_debe   text[];          -- 'pasa' | 'A2-C3' | 'otro'
  v_i      int;
  v_msg    text;
  v_hint   text;
  v_uid    uuid;
begin
  select def, ya_estaba, esperado into v_antes, v_ya, v_esp from a2c3_antes;
  v_ahora := pg_get_functiondef('public.guard_pedido_update()'::regprocedure);
  if not v_ya and v_ahora is distinct from v_esp then
    raise exception 'A2-C3: guard_pedido_update() no quedó como se construyó (cambió en algo más que el bloque nuevo).';
  end if;
  if position('USING HINT = ''A2-C3''' in v_ahora) = 0 then
    raise exception 'A2-C3: el bloque nuevo no está en guard_pedido_update().';
  end if;
  if has_function_privilege('authenticated', 'public.guard_pedido_update()', 'EXECUTE')
  or has_function_privilege('anon',          'public.guard_pedido_update()', 'EXECUTE') then
    raise exception 'A2-C3: guard_pedido_update() quedó ejecutable por anon o authenticated.';
  end if;

  select user_id into v_cli from public.perfiles
   where rol = 'cliente' order by created_at limit 1;
  select user_id into v_emp from public.perfiles
   where rol = 'admin' and aprobacion_cuenta is null order by created_at limit 1;
  select id into v_of from public.ofertas order by created_at limit 1;
  if v_cli is null or v_emp is null or v_of is null then
    raise exception 'A2-C3: hacen falta un cliente, una empresa activa y una oferta cualquiera para la prueba.';
  end if;

  v_set := array[
    'origen = ''A2C3 alterado'', destino = ''A2C3 alterado''',
    'precio_cliente = 1',
    'cliente_email = ''a2c3-otro@example.com''',
    'estado = ''en_negociacion'', precio_cliente = 1',
    format('oferta_pendiente_id = %L', v_of),
    'estado = ''en_negociacion''',
    'estado = ''cancelado''',
    'descripcion = ''a2c3 descripcion del cliente'''];
  v_quien_caso := array['emp','emp','emp','emp','emp','emp','emp','cli'];
  v_debe       := array['A2-C3','A2-C3','A2-C3','A2-C3','A2-C3','pasa','otro','pasa'];

  begin
    insert into public.pedidos (cliente_id, cliente_nombre, cliente_email, estado, origen, destino, precio_cliente)
    values (v_cli, 'a2c3', 'a2c3@example.com', 'abierto', 'A2C3 origen', 'A2C3 destino', 1000)
    returning id into v_ped;

    for v_i in 1 .. array_length(v_set, 1) loop
      v_uid := case v_quien_caso[v_i] when 'emp' then v_emp else v_cli end;
      v_hint := null;
      begin
        perform set_config('request.jwt.claim.sub', v_uid::text, true);
        perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
        perform set_config('role', 'authenticated', true);
        execute format('update public.pedidos set %s where id = %L', v_set[v_i], v_ped);
        raise exception 'A2C3_PASO';
      exception when others then
        get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
      end;
      perform set_config('role', v_quien, true);

      if v_debe[v_i] = 'pasa' and v_msg <> 'A2C3_PASO' then
        v_fallos := v_fallos || format('caso %s (%s, %s) debía pasar: %s', v_i, v_quien_caso[v_i], v_set[v_i], v_msg);
      elsif v_debe[v_i] = 'A2-C3' and v_hint is distinct from 'A2-C3' then
        v_fallos := v_fallos || format('caso %s (%s, %s) no lo frenó A2-C3: %s', v_i, v_quien_caso[v_i], v_set[v_i], v_msg);
      elsif v_debe[v_i] = 'otro' and (v_msg = 'A2C3_PASO' or v_hint = 'A2-C3') then
        v_fallos := v_fallos || format('caso %s (%s, %s) debía rechazarlo la regla de estados: %s', v_i, v_quien_caso[v_i], v_set[v_i], v_msg);
      end if;
    end loop;

    raise exception 'A2C3_FIN';
  exception when others then
    if sqlerrm <> 'A2C3_FIN' then
      raise exception 'A2-C3: la comprobación no pudo montar sus datos de prueba: %', sqlerrm;
    end if;
  end;

  perform set_config('role', v_quien, true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  if current_user <> v_quien then
    raise exception 'A2-C3: la comprobación dejó el rol en % (era %).', current_user, v_quien;
  end if;
  if exists (select 1 from public.pedidos where cliente_email in ('a2c3@example.com', 'a2c3-otro@example.com')) then
    raise exception 'A2-C3: quedaron datos de prueba sin deshacer.';
  end if;
  if cardinality(v_fallos) > 0 then
    raise exception E'A2-C3: el guard no hace lo que debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'A2-C3: una empresa solo cambia el estado de una solicitud ajena; 8 casos, todos como se esperaba.';
end $$;
