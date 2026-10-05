-- ════════════════════════════════════════════════════════════════════════
-- S-09 · camiones.configuracion_vehicular aceptaba cualquier texto
-- ════════════════════════════════════════════════════════════════════════
--
-- El hallazgo (6ª auditoría, 2026-10-01). Carta Porte (20260929170000)
-- añadió camiones.configuracion_vehicular para la clave SAT de configuración
-- vehicular (C2, T3S2…), con su catálogo en catalogos (clave =
-- 'config_vehicular_sat'), pero sin nada que obligue a que el valor salga de
-- ahí. La web usa un desplegable del catálogo (js/admin.js:227) y Android no
-- escribe la columna, así que un valor inválido solo entra por la API — y
-- acabaría impreso en la Carta Porte. Medido el 05/10: 0 de 12 camiones con
-- valor en el volcado del 28/09.
--
-- Por qué un trigger y no la FK compuesta que usa `vigencias` (columna
-- generada constante + FK a catalogos): medido el 05/10, revertirRecurso-
-- Rechazado() (js/admin.js:850) restaura un camión reenviando TODAS las
-- columnas de su snapshot_anterior, que es la fila completa (select('*'),
-- js/admin.js:586). Una columna generada nueva entraría en las copias y
-- «Revertir» fallaría al intentar escribirla. El trigger no cambia el
-- esquema ni el cliente. Lo que no da, y la FK sí: impedir que el superadmin
-- borre del catálogo una clave en uso — el catálogo se edita a mano y se
-- desactiva, no se borra.
--
-- El trigger valida SOLO cuando el valor cambia (y en el alta): si el
-- superadmin desactiva una clave, los camiones que ya la tienen se siguen
-- pudiendo editar sin tocarla. Por eso no exige `activo`: el desplegable ya
-- solo ofrece las activas.
--
-- Nombre: trg_guard_* corre antes que trg_updated_at (orden alfabético de los
-- BEFORE, regla 6 de docs/AUDITORIA.md).
--
-- Reglas de docs/AUDITORIA.md §4: 1, 2, 6, 13, 16.
-- ════════════════════════════════════════════════════════════════════════

do $$
declare
  v_malos int;
begin
  select count(*) into v_malos from public.camiones c
   where c.configuracion_vehicular is not null
     and not exists (select 1 from public.catalogos k
                      where k.clave = 'config_vehicular_sat' and k.valor = c.configuracion_vehicular);
  if v_malos > 0 then
    raise exception 'S-09: hay % camiones con una configuración vehicular que no está en el catálogo. Decidir antes qué hacer con ellos.', v_malos;
  end if;
end $$;

create or replace function public.guard_camion_config_vehicular()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  -- S-09 (20261005160000): la clave SAT tiene que salir del catálogo.
  if new.configuracion_vehicular is not null
     and (tg_op = 'INSERT' or new.configuracion_vehicular is distinct from old.configuracion_vehicular)
     and not exists (select 1 from public.catalogos k
                      where k.clave = 'config_vehicular_sat'
                        and k.valor = new.configuracion_vehicular) then
    raise exception 'La configuración vehicular «%» no está en el catálogo SAT. Elige una de la lista.', new.configuracion_vehicular
      using hint = 'S-09';
  end if;
  return new;
end $$;

revoke all on function public.guard_camion_config_vehicular() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.camiones'::regclass
                    and tgname = 'trg_guard_camion_config_vehicular') then
    create trigger trg_guard_camion_config_vehicular
      before insert or update of configuracion_vehicular on public.camiones
      for each row execute function public.guard_camion_config_vehicular();
  end if;
end $$;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--   · el trigger es BEFORE, FOR EACH ROW, sobre la función; la función no es
--     ejecutable por anon ni authenticated;
--   · como el DUEÑO de un camión real, cada caso en una subtransacción que se
--     deshace entera:
--       1. una clave del catálogo        → pasa
--       2. una clave inventada           → rechazo (S-09)
--       3. dejarla vacía (NULL)          → pasa
--       4. con una clave puesta, editar otra columna enviando también la
--          misma clave, después de desactivarla en el catálogo → pasa
-- Como sabe fallar: sin el trigger, (2) pasa.

do $$
declare
  v_quien  text := current_user;
  v_fallos text[] := '{}';
  v_t      record;
  v_cam    text;
  v_dueno  uuid;
  v_valida text;
  v_msg    text;
  v_hint   text;
  v_i      int;
  v_set    text[];
  v_debe   text[] := array['pasa', 'S-09', 'pasa', 'pasa'];
begin
  select t.tgenabled, t.tgtype, p.proname into v_t
    from pg_trigger t join pg_proc p on p.oid = t.tgfoid
   where t.tgrelid = 'public.camiones'::regclass and t.tgname = 'trg_guard_camion_config_vehicular';
  if not found or v_t.tgenabled = 'D' or (v_t.tgtype & 3) <> 3 or v_t.proname <> 'guard_camion_config_vehicular' then
    raise exception 'S-09: trg_guard_camion_config_vehicular no es un BEFORE FOR EACH ROW activo sobre su función.';
  end if;
  if has_function_privilege('authenticated', 'public.guard_camion_config_vehicular()', 'EXECUTE')
  or has_function_privilege('anon', 'public.guard_camion_config_vehicular()', 'EXECUTE') then
    raise exception 'S-09: guard_camion_config_vehicular() quedó ejecutable por anon o authenticated.';
  end if;

  select valor into v_valida from public.catalogos
   where clave = 'config_vehicular_sat' order by orden limit 1;
  select c.id, c.propietario_id into v_cam, v_dueno
    from public.camiones c join public.perfiles p on p.user_id = c.propietario_id
   where p.rol = 'admin' order by c.created_at limit 1;
  if v_valida is null or v_cam is null then
    raise exception 'S-09: hacen falta una clave en el catálogo config_vehicular_sat y un camión de una empresa para la prueba.';
  end if;

  v_set := array[
    format('configuracion_vehicular = %L', v_valida),
    'configuracion_vehicular = ''S09-INVENTADA''',
    'configuracion_vehicular = null',
    format('configuracion_vehicular = %L, placas = placas', v_valida)];

  for v_i in 1 .. 4 loop
    v_hint := null;
    begin
      if v_i = 4 then
        -- La clave ya puesta en el camión, y luego desactivada en el catálogo.
        update public.camiones set configuracion_vehicular = v_valida where id = v_cam;
        update public.catalogos set activo = false where clave = 'config_vehicular_sat' and valor = v_valida;
      end if;
      perform set_config('request.jwt.claim.sub', v_dueno::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_dueno, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      execute format('update public.camiones set %s where id = %L', v_set[v_i], v_cam);
      raise exception 'S09_PASO';
    exception when others then
      get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    end;
    perform set_config('role', v_quien, true);

    if v_debe[v_i] = 'pasa' and v_msg <> 'S09_PASO' then
      v_fallos := v_fallos || format('caso %s (%s) debía pasar: %s', v_i, v_set[v_i], v_msg);
    elsif v_debe[v_i] = 'S-09' and v_hint is distinct from 'S-09' then
      v_fallos := v_fallos || format('caso %s (%s) no lo frenó S-09: %s', v_i, v_set[v_i], v_msg);
    end if;
  end loop;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  if current_user <> v_quien then
    raise exception 'S-09: la comprobación dejó el rol en % (era %).', current_user, v_quien;
  end if;
  if exists (select 1 from public.camiones where configuracion_vehicular = 'S09-INVENTADA')
  or exists (select 1 from public.catalogos where clave = 'config_vehicular_sat' and valor = v_valida and not activo) then
    raise exception 'S-09: quedaron datos de prueba sin deshacer.';
  end if;
  if cardinality(v_fallos) > 0 then
    raise exception E'S-09: el guard no hace lo que debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'S-09: configuracion_vehicular solo acepta claves del catálogo SAT; 4 casos, todos como se esperaba.';
end $$;
