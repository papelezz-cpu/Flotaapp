-- ═════════════════════════════════════════════════════════════════════════
-- Q-06 · Nadie borra pedidos
-- ═════════════════════════════════════════════════════════════════════════
--
-- El defecto (quinta auditoria, 2026-09-29; medido de nuevo el 2026-09-30):
--
--   CREATE POLICY ped_delete ON pedidos FOR DELETE TO authenticated
--     USING (auth.uid() = cliente_id OR <es superadmin>);
--   GRANT DELETE ON pedidos TO authenticated;
--
-- El cliente puede borrar su pedido en CUALQUIER estado —tambien `acordado` o
-- `finalizado`— llamando a la API: las ofertas se van en cascada
-- (ofertas.pedido_id ON DELETE CASCADE) y la reservacion se queda sin pedido
-- (reservaciones.pedido_id ON DELETE SET NULL). La interfaz nunca le ofrecio
-- borrar (solo «Cancelar», en `abierto`), pero la base si se lo permite.
--
-- Decision del usuario (2026-09-30): por el momento NO se borra ningun pedido,
-- ni el cliente ni el superadmin. Lo que se quiera quitar de la vista se
-- archivara, con una funcion aparte que todavia no existe. La cancelacion se
-- queda como estaba.
--
-- El arreglo: retirar el privilegio DELETE sobre `pedidos` a `authenticated`
-- (y a anon/PUBLIC, que no lo tienen, por si acaso). Igual que Q-03: la
-- politica `ped_delete` NO se borra —quedaria un DROP (Regla #1)—; queda
-- inerte, porque sin privilegio no hay DELETE que evaluar, y se documenta con
-- COMMENT. `service_role` conserva el suyo: no es un usuario final.
--
-- Quien borraba pedidos, medido el 2026-09-30:
--   · js/pedidos.js eliminarPedido(): el boton «🗑 Eliminar», solo visible al
--     superadmin. Se retira del navegador en el mismo commit que esta
--     migracion. Mientras produccion tenga el codigo viejo, ese boton dara un
--     error de permisos: no borra nada. (Antes intenta borrar las ofertas,
--     pero `ofertas` no tiene politica de DELETE: eso ya hoy afecta 0 filas.)
--   · Ninguna funcion de la base ni ninguna Edge Function borra pedidos.
--   · Android no borra pedidos.
--   · Borrar la cuenta de un cliente no borra sus pedidos: pedidos.cliente_id
--     es ON DELETE SET NULL.
--
-- Reglas de docs/AUDITORIA.md §4: 2 (bloque que sabe fallar), 9 (sin DROP).
-- ═════════════════════════════════════════════════════════════════════════


revoke delete on public.pedidos from authenticated, anon, public;

comment on policy ped_delete on public.pedidos is
  'INERTE desde 20260930130000 (Q-06): authenticated ya no tiene DELETE en '
  'pedidos; no se borra ningun pedido (se archivaran, funcion aparte). Se '
  'conserva para no borrar sin autorizacion (Regla #1).';


-- ─────────────────────────────────────────────────────────────────────────
-- Comprobacion — falla si el objetivo no se cumplio
-- ─────────────────────────────────────────────────────────────────────────
--
-- Como sabe fallar: sin el REVOKE, el DELETE del cliente sobre su propio
-- pedido llega a hacerse (la politica lo admite) y el bloque lo detecta; con
-- el REVOKE da 42501 antes de mirar filas. Se prueba sobre un pedido creado
-- aqui mismo, dentro de una subtransaccion que se deshace entera.

do $$
declare
  v_cliente uuid;
  v_ped     uuid;
  v_estado  text;
  v_msg     text;
  v_quien   text := current_user;
  v_borradas int;
begin
  if has_table_privilege('authenticated', 'public.pedidos', 'DELETE')
  or has_table_privilege('anon',          'public.pedidos', 'DELETE') then
    raise exception 'Q-06: authenticated o anon siguen teniendo DELETE en pedidos.';
  end if;
  if not has_table_privilege('service_role', 'public.pedidos', 'DELETE') then
    raise exception 'Q-06: service_role perdio DELETE en pedidos; no era el objetivo.';
  end if;
  -- El resto de privilegios del cliente sobre pedidos no se toca.
  if not (has_table_privilege('authenticated', 'public.pedidos', 'SELECT')
      and has_table_privilege('authenticated', 'public.pedidos', 'INSERT')
      and has_table_privilege('authenticated', 'public.pedidos', 'UPDATE')) then
    raise exception 'Q-06: authenticated perdio SELECT, INSERT o UPDATE en pedidos.';
  end if;

  select user_id into v_cliente from public.perfiles order by created_at limit 1;
  if v_cliente is null then
    raise exception 'Q-06: no hay ningun perfil para colgar el pedido de prueba.';
  end if;

  begin
    -- Un pedido `finalizado` del cliente: el caso que la politica dejaba borrar.
    insert into public.pedidos (cliente_id, cliente_nombre, cliente_email, estado)
    values (v_cliente, 'q06', 'q06@example.com', 'finalizado')
    returning id into v_ped;

    begin
      perform set_config('request.jwt.claim.sub', v_cliente::text, true);
      perform set_config('request.jwt.claims',
                         json_build_object('sub', v_cliente, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      delete from public.pedidos where id = v_ped;
      get diagnostics v_borradas = row_count;
      raise exception 'Q06_BORRO:%', v_borradas;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    end;

    raise exception 'Q06_FIN';
  exception when others then
    if sqlerrm <> 'Q06_FIN' then
      raise exception 'Q-06: la comprobacion no pudo montar su pedido de prueba: %', sqlerrm;
    end if;
  end;

  if current_user <> v_quien then
    raise exception 'Q-06: la comprobacion dejo el rol en % (era %).', current_user, v_quien;
  end if;
  if exists (select 1 from public.pedidos where cliente_email = 'q06@example.com') then
    raise exception 'Q-06: quedo el pedido de prueba sin deshacer.';
  end if;
  if v_estado <> '42501' then
    raise exception 'Q-06: el cliente sigue pudiendo borrar un pedido finalizado: % %', v_estado, v_msg;
  end if;

  raise notice 'Q-06: DELETE sobre pedidos retirado a authenticated; el cliente ya no borra ni su pedido finalizado.';
end $$;
