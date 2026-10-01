-- ═════════════════════════════════════════════════════════════════════════
-- Q-05 · La empresa podia crear una reservacion "como quisiera"
-- ═════════════════════════════════════════════════════════════════════════
--
-- El defecto (quinta auditoria, 2026-09-29; medido de nuevo el 2026-09-30):
-- `guard_reservacion_insert()` tiene una rama
--
--     -- La empresa dueña del recurso puede crearla como quiera: es la parte que
--     -- acepta el trato, no la que se lo impone a otro.
--     if new.propietario_id = auth.uid() then return new; end if;
--
-- y la politica `reservaciones_insert` admite al propietario. Juntas dejan a
-- cualquier empresa crear una reservacion en CUALQUIER estado (`Activa`,
-- `Completada`...), con CUALQUIER precio y a nombre de CUALQUIER cliente: un
-- servicio que nunca ocurrio, con un cobro pendiente contra un cliente que no
-- lo pidio, sumado a sus numeros en reportes y «Mi desempeño».
--
-- Por que el motivo de esa rama es obsoleto: desde el 2026-09-09 las dos
-- partes aceptan y la reserva la crea `cerrar_acuerdo()`, que enciende la
-- marca `portgo.cierre_acuerdo` y sale por la primera rama del guard —
-- tambien cuando la que acepta es la empresa (`aceptar_y_cerrar_acuerdo` →
-- `cerrar_acuerdo`). Medido el 2026-09-30, las vias que crean reservaciones:
--
--   · cerrar_acuerdo()          → marca portgo.cierre_acuerdo   (sigue igual)
--   · superadmin                → is_superadmin()               (sigue igual)
--   · js/modal.js:106, cliente  → rama del cliente, Pendiente   (sigue igual)
--   · js/pedidos.js:2637        → dentro de cerrarAcuerdo(), que NO se llama
--                                 desde ningun sitio, ni en dev ni en main:
--                                 el superadmin cierra por la RPC desde el
--                                 2026-09-25 (js/aprobaciones.js)
--   · Android                   → no inserta reservaciones
--
-- Nadie legitimo pasa por la rama del propietario.
--
-- El arreglo: esa rama pasa de `return new` a un rechazo con mensaje propio.
-- La funcion NO se reescribe a mano (regla 3; R-11): se lee su definicion
-- viva, se sustituye ese unico bloque y el bloque de verificacion comprueba
-- que es lo unico que cambio. No hay DROP de nada. La politica
-- `reservaciones_insert` no se toca: el guard es la capa de transiciones
-- (regla 15) y basta con que rechace.
--
-- Lo que NO hace: revisar reservaciones ya creadas por esa via. Desde la base
-- no se distingue quien inserto una fila.
-- ═════════════════════════════════════════════════════════════════════════


create temporary table q05_antes on commit drop as
  select pg_get_functiondef('public.guard_reservacion_insert()'::regprocedure) as def,
         false as ya_estaba;

do $$
declare
  v_def   text;
  v_nuevo text;
  v_n     int;
  v_patron constant text :=
    '-- La empresa due.a del recurso puede crearla como quiera:.*?'
    'if new\.propietario_id = auth\.uid\(\) then\s+return new;\s+end if;';
  v_bloque constant text :=
    '-- Q-05 (20260930120000): la empresa no crea reservaciones directamente.' || E'\n'
 || '  -- Desde el 2026-09-09 el acuerdo lo cierra cerrar_acuerdo() (marca de' || E'\n'
 || '  -- arriba), tambien cuando acepta la empresa. Esta rama la dejaba crear' || E'\n'
 || '  -- una reserva en cualquier estado, con cualquier precio y a nombre de' || E'\n'
 || '  -- cualquier cliente.' || E'\n'
 || '  if new.propietario_id = auth.uid() then' || E'\n'
 || '    raise exception ''No autorizado: una empresa no crea reservaciones; nacen al cerrar el acuerdo con el cliente''' || E'\n'
 || '      using hint = ''Q-05'';' || E'\n'
 || '  end if;';
begin
  select def into v_def from q05_antes;

  -- Reaplicar no rompe: si el bloque nuevo ya esta y el viejo no, se anota.
  if position('using hint = ''Q-05''' in v_def) > 0
     and regexp_count(v_def, v_patron) = 0 then
    update q05_antes set ya_estaba = true;
    return;
  end if;

  v_n := regexp_count(v_def, v_patron);
  if v_n <> 1 then
    raise exception 'Q-05: guard_reservacion_insert() tiene % apariciones de la rama del propietario (se esperaba 1). La funcion viva no es la que se midio: no se toca.', v_n;
  end if;

  v_nuevo := regexp_replace(v_def, v_patron, v_bloque);
  execute v_nuevo;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- Comprobacion — falla si el objetivo no se cumplio
-- ─────────────────────────────────────────────────────────────────────────
--
-- Cada alta va en su subtransaccion como `authenticated` con uids inventados;
-- todas terminan en excepcion y no queda nada. `unidad` va NULL, asi que
-- check_reservacion_disponibilidad y guard_unidad_existe no intervienen.
--
-- Como sabe fallar:
--   · Sin el cambio, el alta de la empresa pasa el guard y la RLS y llega a la
--     FK de las partes (23503), en vez de rechazarse con HINT 'Q-05'.
--   · Un camino legitimo (cliente Pendiente, cierre con la marca,
--     superadmin) tiene que llegar a esa misma FK: si el guard lo frenara,
--     daria P0001.
--   · La funcion nueva tiene que ser la vieja con esa unica sustitucion.

do $$
declare
  v_antes   text;
  v_ahora   text;
  v_ya      boolean;
  v_def     boolean;
  v_caso    jsonb;
  v_debe    text;
  v_marca   boolean;
  v_quien_e text;
  v_u       uuid;
  v_otro    uuid;
  v_sa      uuid;
  v_cols    text;
  v_estado  text;
  v_hint    text;
  v_msg     text;
  v_quien   text := current_user;
  v_fallos  text[] := '{}';
  v_n       int := 0;
  v_patron constant text :=
    '-- La empresa due.a del recurso puede crearla como quiera:.*?'
    'if new\.propietario_id = auth\.uid\(\) then\s+return new;\s+end if;';
begin
  -- La funcion: solo esa sustitucion, y sigue siendo lo que era.
  select def, ya_estaba into v_antes, v_ya from q05_antes;
  v_ahora := pg_get_functiondef('public.guard_reservacion_insert()'::regprocedure);
  if not v_ya then
    if v_ahora = v_antes then
      raise exception 'Q-05: guard_reservacion_insert() no cambio.';
    end if;
    if regexp_replace(v_ahora, '-- Q-05 \(20260930120000\).*?using hint = ''Q-05'';\s+end if;', 'X')
       is distinct from regexp_replace(v_antes, v_patron, 'X') then
      raise exception 'Q-05: guard_reservacion_insert() cambio en algo mas que la rama del propietario.';
    end if;
  end if;
  if regexp_count(v_ahora, v_patron) > 0 or position('using hint = ''Q-05''' in v_ahora) = 0 then
    raise exception 'Q-05: la rama del propietario sigue devolviendo NEW.';
  end if;
  select prosecdef into v_def from pg_proc where oid = 'public.guard_reservacion_insert()'::regprocedure;
  if not v_def then
    raise exception 'Q-05: guard_reservacion_insert() dejo de ser SECURITY DEFINER.';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.reservaciones'::regclass
                  and tgname = 'trg_guard_reservacion_insert' and tgenabled <> 'D') then
    raise exception 'Q-05: trg_guard_reservacion_insert no esta activo.';
  end if;

  -- Un superadmin real, si lo hay, para probar su camino.
  select user_id into v_sa from public.perfiles where rol = 'superadmin' order by created_at limit 1;

  -- quien_e: 'empresa' (uid = propietario), 'cliente' (uid = cliente), 'sa'.
  for v_quien_e, v_caso, v_marca, v_debe in
    select * from (values
      ('empresa', '{"estado":"Activa","precio_acordado":100}'::jsonb,     false, 'rechazo'),
      ('empresa', '{"estado":"Completada","precio_acordado":100}'::jsonb, false, 'rechazo'),
      ('empresa', '{"estado":"Pendiente"}'::jsonb,                         false, 'rechazo'),
      ('empresa', '{"estado":"Activa","precio_acordado":100}'::jsonb,     true,  'pasa'),   -- cerrar_acuerdo()
      ('cliente', '{"estado":"Pendiente"}'::jsonb,                         false, 'pasa'),   -- js/modal.js
      ('cliente', '{"estado":"Activa"}'::jsonb,                            false, 'rechazo_cliente'),
      ('sa',      '{"estado":"Activa","precio_acordado":100}'::jsonb,     false, 'pasa')
    ) as t(q, c, m, d)
  loop
    if v_quien_e = 'sa' and v_sa is null then
      raise notice 'Q-05: no hay superadmin; se omite su caso.';
      continue;
    end if;
    v_n    := v_n + 1;
    v_u    := case when v_quien_e = 'sa' then v_sa else gen_random_uuid() end;
    v_otro := gen_random_uuid();
    v_caso := v_caso || jsonb_build_object(
                'cliente', 'q05', 'recurso_tipo', 'camion',
                'fecha_ini', '2099-01-01', 'fecha_fin', '2099-01-02',
                'propietario_id',  case when v_quien_e = 'empresa' then v_u else v_otro end,
                'cliente_user_id', case when v_quien_e = 'cliente' then v_u else gen_random_uuid() end);
    select string_agg(quote_ident(k), ', ') into v_cols from jsonb_object_keys(v_caso) k;
    v_hint := null;

    begin
      perform set_config('request.jwt.claim.sub', v_u::text, true);
      perform set_config('request.jwt.claims',
                         json_build_object('sub', v_u, 'role', 'authenticated')::text, true);
      perform set_config('portgo.cierre_acuerdo', case when v_marca then 'on' else 'off' end, true);
      perform set_config('role', 'authenticated', true);
      execute format(
        'insert into public.reservaciones (%1$s) select %1$s from jsonb_populate_record(null::public.reservaciones, $1)',
        v_cols) using v_caso;
      raise exception 'Q05_SENTINELA';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate,
                              v_msg    = message_text,
                              v_hint   = pg_exception_hint;
    end;

    if v_debe = 'rechazo' and v_hint is distinct from 'Q-05' then
      v_fallos := v_fallos || format('caso %s (%s%s, %s) NO se rechazo: %s %s', v_n, v_quien_e,
                    case when v_marca then ' con marca' else '' end, v_caso ->> 'estado', v_estado, v_msg);
    elsif v_debe = 'rechazo_cliente' and not (v_estado = 'P0001' and v_msg like 'No autorizado:%') then
      v_fallos := v_fallos || format('caso %s (cliente, %s) NO se rechazo: %s %s', v_n, v_caso ->> 'estado', v_estado, v_msg);
    elsif v_debe = 'pasa' and v_estado <> '23503' then
      v_fallos := v_fallos || format('caso %s (%s%s, %s) legitimo NO paso: %s %s', v_n, v_quien_e,
                    case when v_marca then ' con marca' else '' end, v_caso ->> 'estado', v_estado, v_msg);
    end if;
  end loop;

  if current_user <> v_quien then
    raise exception 'Q-05: la comprobacion dejo el rol en % (era %).', current_user, v_quien;
  end if;

  if cardinality(v_fallos) > 0 then
    raise exception E'Q-05: el guard no hace lo que debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'Q-05: la empresa ya no crea reservaciones directamente; % casos, todos como se esperaba.', v_n;
end $$;
