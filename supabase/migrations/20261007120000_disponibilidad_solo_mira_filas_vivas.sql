-- ════════════════════════════════════════════════════════════════════════
-- S-14 · El chequeo de disponibilidad frenaba cambios en reservaciones cerradas
-- ════════════════════════════════════════════════════════════════════════
--
-- check_reservacion_disponibilidad() corre BEFORE INSERT OR UPDATE y busca
-- OTRAS reservaciones Pendiente/Activa de la misma unidad cuyas fechas se
-- solapen con las de la fila. Pero no miraba el estado de LA PROPIA fila.
--
-- Consecuencia, reproducida el 07/10 en banco local: un camión termina un
-- viaje (Completada, del 1 al 5) y empieza otro el mismo día (Activa, del 5
-- al 8). Ese segundo se crea sin problema —el chequeo solo compara contra
-- filas vivas, y la Completada no lo es—. Después, CUALQUIER UPDATE de la
-- Completada falla con RECURSO_NO_DISPONIBLE: registrar el pago, subir
-- evidencias, archivarla. La fila cerrada «choca» con un viaje que nunca
-- podría bloquear.
--
-- El arreglo es el que pide la nota de CLAUDE.md sobre este trigger y
-- reservaciones_sin_solape: las dos capas tienen que mirar lo mismo, y la
-- EXCLUDE solo cuenta filas WHERE estado IN ('Pendiente','Activa'). Ahora el
-- trigger también: si la fila no está viva, no hay solape que comprobar.
-- Reactivar una fila cerrada (pasarla a Activa) sigue comprobándose, porque
-- entonces NEW.estado sí es vivo.
--
-- Se sustituye sobre la definición VIVA y se aborta si no es la esperada
-- (CLAUDE.md, trabajo simultáneo: nunca se reescribe a mano una función).
-- No borra nada. Reversible: volver a crear la función sin la línea añadida.
--
-- Reglas de docs/AUDITORIA.md §4: 2, 32, 33. Hallazgo: S-14.
-- ════════════════════════════════════════════════════════════════════════

do $$
declare
  v_def    text;
  -- \r? porque el cuerpo vivo puede traer saltos de línea Windows: la versión
  -- H-06 se aplicó desde un archivo CRLF en al menos un proyecto (medido en el
  -- banco local el 07/10). El texto nuevo va con \n; a plpgsql le da igual.
  v_patron constant text := 'BEGIN\r?\n  IF EXISTS \(\r?\n    SELECT 1 FROM reservaciones';
  v_n      int;
  v_nuevo  constant text := E'BEGIN\n'
    || E'  -- S-14: solo una fila viva puede solaparse, igual que en\n'
    || E'  -- reservaciones_sin_solape (WHERE estado IN (''Pendiente'',''Activa'')).\n'
    || E'  -- Sin esto, una reservacion cerrada no se podia ni marcar pagada si la\n'
    || E'  -- unidad ya tenia otro viaje que empezaba el dia en que esta terminaba.\n'
    || E'  IF NEW.estado NOT IN (''Pendiente'', ''Activa'') THEN\n'
    || E'    RETURN NEW;\n'
    || E'  END IF;\n'
    || E'  IF EXISTS (\n    SELECT 1 FROM reservaciones';
begin
  v_def := pg_get_functiondef('public.check_reservacion_disponibilidad()'::regprocedure);

  if position('S-14' in v_def) > 0 then
    raise notice 'S-14: check_reservacion_disponibilidad() ya lleva el arreglo; no se toca.';
    return;
  end if;

  select count(*) into v_n from regexp_matches(v_def, v_patron, 'g');
  if v_n <> 1
     or position('estado IN (''Pendiente'', ''Activa'')' in v_def) = 0
     or position('RECURSO_NO_DISPONIBLE' in v_def) = 0 then
    raise exception E'S-14: check_reservacion_disponibilidad() no es la versión esperada (H-06). '
      'Alguien la cambió: revisar a mano antes de aplicar.\n%', v_def;
  end if;

  execute regexp_replace(v_def, v_patron, v_nuevo);
end $$;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
-- Se ejerce la función de verdad, sin tocar public.reservaciones: una tabla
-- temporal con la misma forma lleva el mismo trigger, y la función busca los
-- solapes en public.reservaciones (su search_path es public primero). Se usa
-- una reservación viva real como «el otro viaje». No dispara avisos, guards
-- ni correos: en la tabla temporal solo está este trigger.
--
--   a. una copia de esa fila pasada a Completada y con id nuevo se puede
--      actualizar (registrar pago) → el defecto: ANTES fallaba;
--   b. reactivarla (Completada → Activa) sobre las mismas fechas → debe
--      seguir fallando con RECURSO_NO_DISPONIBLE;
--   c. insertar otra Activa solapada → debe seguir fallando.
-- Como sabe fallar: sin el arreglo, (a) da RECURSO_NO_DISPONIBLE.

do $$
declare
  v_viva    public.reservaciones;
  v_def     text;
  v_fallos  text[] := '{}';
  v_msg     text;
begin
  v_def := pg_get_functiondef('public.check_reservacion_disponibilidad()'::regprocedure);
  if position('IF NEW.estado NOT IN (''Pendiente'', ''Activa'') THEN' in v_def) = 0 then
    v_fallos := v_fallos || 'la función no lleva la salida temprana de S-14'::text;
  end if;
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.reservaciones'::regclass
                    and tgname = 'trg_check_reservacion_disponibilidad' and tgenabled <> 'D') then
    v_fallos := v_fallos || 'trg_check_reservacion_disponibilidad no está activo'::text;
  end if;

  select * into v_viva from public.reservaciones
   where estado in ('Pendiente', 'Activa') and fecha_ini is not null and fecha_fin is not null
   order by created_at limit 1;

  if v_viva.id is null then
    raise notice 'S-14: no hay reservaciones vivas; se comprobó solo la definición.';
  else
    create temp table s14_prueba (like public.reservaciones including defaults) on commit drop;
    create trigger s14_disponibilidad before insert or update on s14_prueba
      for each row execute function public.check_reservacion_disponibilidad();

    -- La copia con el MISMO id no se solapa consigo misma: entra.
    insert into s14_prueba select (v_viva).*;

    -- a.
    begin
      update s14_prueba set id = gen_random_uuid(), estado = 'Completada', pagado = true;
    exception when others then
      v_fallos := v_fallos || format('a. una reservación Completada no se pudo actualizar: %s', sqlerrm);
    end;

    -- b. id nuevo también aquí: así no depende de que (a) haya pasado.
    v_msg := null;
    begin
      update s14_prueba set id = gen_random_uuid(), estado = 'Activa';
    exception when others then
      v_msg := sqlerrm;
    end;
    if v_msg is null or position('RECURSO_NO_DISPONIBLE' in v_msg) = 0 then
      v_fallos := v_fallos || format('b. reactivar una reservación solapada no lo frenó (%s)', coalesce(v_msg, 'pasó'));
    end if;

    -- c.
    v_msg := null;
    begin
      insert into s14_prueba
        select (jsonb_populate_record(null::s14_prueba,
                  to_jsonb(v_viva) || jsonb_build_object('id', gen_random_uuid()))).*;
    exception when others then
      v_msg := sqlerrm;
    end;
    if v_msg is null or position('RECURSO_NO_DISPONIBLE' in v_msg) = 0 then
      v_fallos := v_fallos || format('c. una reservación Activa solapada entró (%s)', coalesce(v_msg, 'pasó'));
    end if;
  end if;

  if cardinality(v_fallos) > 0 then
    raise exception E'S-14: no quedó como debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;
  raise notice 'S-14: una reservación cerrada ya no choca con viajes posteriores; los solapes vivos se siguen frenando.';
end $$;
