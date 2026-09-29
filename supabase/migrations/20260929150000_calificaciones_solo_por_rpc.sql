-- ═════════════════════════════════════════════════════════════════════════
-- Q-03 · Una calificacion se podia insertar sin pasar por calificar_servicio
-- ═════════════════════════════════════════════════════════════════════════
--
-- El defecto (quinta auditoria, 2026-09-29, volcado de produccion del 28/09):
--
--   CREATE POLICY "Clientes pueden insertar calificaciones" ON calificaciones
--     FOR INSERT TO authenticated WITH CHECK (cliente_id = auth.uid());
--   GRANT INSERT ON calificaciones TO authenticated;
--
-- La politica solo mira quien firma. Todo lo que `calificar_servicio()`
-- comprueba —que la reservacion sea del cliente, que este Completada, que no
-- este calificada, que `admin_id` sea su propietario— se salta con un INSERT
-- directo. Y el unico freno a repetir, `uq_calificaciones_reservacion`, es
-- PARCIAL (`WHERE reservacion_id IS NOT NULL`): con `reservacion_id` NULL
-- cualquier cuenta puede dejar tantas calificaciones de 1 estrella como
-- quiera a cualquier empresa. El catalogo y «Mi desempeño» las promedian.
--
-- Las 4 calificaciones de produccion del 28/09 son legitimas: cada una
-- corresponde a una reservacion Completada del mismo cliente y la misma
-- empresa. No hay nada que limpiar.
--
-- El arreglo: retirar el privilegio de INSERT a `authenticated`. Calificar ya
-- solo ocurre por la RPC:
--
--   · js/reservaciones.js:1523 llama a `calificar_servicio` (una de las 6 RPC
--     en uso, CLAUDE.md). Ningun otro sitio del navegador inserta en la tabla
--     (grep: catalogo.js y pedidos.js solo leen).
--   · Android no inserta calificaciones.
--   · `calificar_servicio` es SECURITY DEFINER: inserta con los privilegios de
--     su dueño, no del cliente. El bloque 3 comprueba que ese dueño conserve
--     INSERT.
--
-- Por que REVOKE y no un guard: un guard tendria que repetir las cinco
-- comprobaciones de la RPC, y dos objetos que expresan la misma regla acaban
-- diciendo cosas distintas (regla 5). Con el REVOKE la regla vive en un solo
-- sitio.
--
-- Lo que NO se hace: borrar la politica. Queda inerte (sin privilegio no hay
-- INSERT que evaluar) y se documenta con COMMENT. Borrarla es un DROP, y eso
-- pasa por la Regla #1 si algun dia se quiere.
--
-- Reglas de docs/AUDITORIA.md §4: 2 (bloque que sabe fallar), 5 (una regla,
-- un sitio), 9 (sin DROP), 13 (la RPC ya es DEFINER y reverifica al autor).
-- ═════════════════════════════════════════════════════════════════════════


revoke insert on public.calificaciones from authenticated, anon, public;

comment on policy "Clientes pueden insertar calificaciones" on public.calificaciones is
  'INERTE desde 20260929150000 (Q-03): authenticated ya no tiene INSERT en '
  'calificaciones; se califica solo por calificar_servicio(). Se conserva '
  'para no borrar sin autorizacion (Regla #1).';


-- ─────────────────────────────────────────────────────────────────────────
-- Comprobacion — falla si el objetivo no se cumplio
-- ─────────────────────────────────────────────────────────────────────────
--
-- Como sabe fallar: sin el REVOKE, el INSERT del cliente llega a la FK de
-- admin_id (uuid inventado → 23503) en vez de 42501, y el bloque aborta.

do $$
declare
  v_uid     uuid := gen_random_uuid();
  v_estado  text;
  v_msg     text;
  v_quien   text := current_user;
  v_dueno   name;
  v_definer boolean;
begin
  if has_table_privilege('authenticated', 'public.calificaciones', 'INSERT')
  or has_table_privilege('anon',          'public.calificaciones', 'INSERT') then
    raise exception 'Q-03: authenticated o anon siguen teniendo INSERT en calificaciones.';
  end if;

  -- La RPC sigue pudiendo insertar.
  select pg_get_userbyid(p.proowner), p.prosecdef into v_dueno, v_definer
    from pg_proc p
   where p.oid = 'public.calificar_servicio(uuid, integer, text)'::regprocedure;
  if not v_definer then
    raise exception 'Q-03: calificar_servicio ya no es SECURITY DEFINER; sin INSERT, calificar dejaria de funcionar.';
  end if;
  if not has_table_privilege(v_dueno, 'public.calificaciones', 'INSERT') then
    raise exception 'Q-03: el dueño de calificar_servicio (%) no tiene INSERT en calificaciones.', v_dueno;
  end if;
  if not has_function_privilege('authenticated', 'public.calificar_servicio(uuid, integer, text)', 'EXECUTE') then
    raise exception 'Q-03: authenticated no puede ejecutar calificar_servicio.';
  end if;

  -- El ataque: calificacion sin reservacion, a nombre propio, como cliente.
  begin
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    insert into public.calificaciones (reservacion_id, admin_id, cliente_id, rating)
    values (null, gen_random_uuid(), v_uid, 1);
    raise exception 'Q03_SENTINELA';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  end;

  if current_user <> v_quien then
    raise exception 'Q-03: la comprobacion dejo el rol en % (era %).', current_user, v_quien;
  end if;

  if v_estado <> '42501' then
    raise exception 'Q-03: el INSERT directo de un cliente no se rechazo por permisos: % %', v_estado, v_msg;
  end if;

  raise notice 'Q-03: INSERT directo en calificaciones retirado; calificar_servicio (dueño %) conserva el suyo.', v_dueno;
end $$;
