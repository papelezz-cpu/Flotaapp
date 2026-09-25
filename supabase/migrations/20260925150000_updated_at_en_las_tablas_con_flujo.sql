-- ============================================================================
-- `updated_at` en las diez tablas con flujo de estados (H-19)
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- Las 24 tablas tienen `created_at` y **ninguna tiene `updated_at`**. Hay marcas
-- de momentos puntuales —`completado_en`, `pagado_en`, `atendida_en`,
-- `docs_aprobados_en`— pero ninguna responde «¿cuándo cambió esta fila por
-- última vez?».
--
-- En un sistema cuyo trabajo central es revisar cosas que cambian de estado, eso
-- tiene una consecuencia concreta y molesta: **la cola del superadmin se ordena
-- por `created_at`, que es cuándo se creó el recurso, no cuándo entró a
-- revisión.** Editar un recurso ya aprobado lo devuelve a revisión sin tocar su
-- `created_at`, así que **una edición de hoy aparece al fondo de la cola**, detrás
-- de altas de hace meses. Y no se puede medir cuánto tarda una aprobación.
--
-- ── Qué se añade, y dónde ─────────────────────────────────────────────────
--
-- `updated_at timestamptz NOT NULL DEFAULT now()` más un trigger compartido, en
-- las diez tablas con flujo de estados. Las otras catorce no lo llevan: un
-- `updated_at` en `catalogos` o en `consentimientos` sería ruido.
--
-- ── El nombre del trigger NO es decorativo ────────────────────────────────
--
-- El orden de disparo de los triggers `BEFORE` es **alfabético por nombre**. Este
-- tiene que correr **después** de los `trg_guard_*`, porque un guard puede
-- rechazar la actualización o revertir campos de `NEW`, y sellar la fila como
-- «modificada» antes de saber si el cambio es legal es sellar una mentira.
--
-- `trg_updated_at` cumple: los BEFORE que ya existen empiezan por `trg_c`
-- (check_reservacion_disponibilidad), `trg_g` (los once guards), `trg_l`
-- (limitar_plantillas) y `trg_s` (sync_datos_pago). `s` < `u`, así que este va
-- último. **Si algún día se añade un BEFORE que empiece por `v`…`z`, correrá
-- después de este** — la comprobación de abajo lo vigila y falla si ocurre.
--
-- ── Sobre el relleno de las filas que ya existen ──────────────────────────
--
-- `ADD COLUMN ... DEFAULT now()` no reescribe la tabla (el default es STABLE, no
-- volátil, así que PostgreSQL guarda un solo valor), pero deja **todas** las
-- filas viejas con la marca del momento de la migración — que no es cuándo
-- cambiaron. Peor aún para el propósito: todas iguales, así que ordenar por
-- antigüedad daría un empate gigante.
--
-- Se rellenan con `created_at`, que es lo más honesto que se sabe de una fila que
-- nunca registró sus cambios. Y ese `UPDATE` **tiene que correr con los triggers
-- apagados**: los guards leen `auth.uid()`, que en `psql` es NULL, así que
-- rechazarían un cambio administrativo legítimo. Es el mismo obstáculo que ya
-- apareció en `20260924140000`. Se apagan con `DISABLE TRIGGER USER` —que no toca
-- los de clave foránea— y **la comprobación exige que estén todos encendidos al
-- final**: dejar un guard apagado en producción sería mucho peor que no tener
-- `updated_at`.
--
-- ── Lo que rellenó en la primera aplicación real (pruebas, 2026-09-25) ────
--
--     pedidos 49 · ofertas 39 · reservaciones 23 · perfiles 13 · camiones 14
--     custodios 6 · patios 5 · lavados 1 · operadores 4 · expedientes 8
--
-- Y `expedientes` se rellenó desde `solicitado_en`, no desde `created_at`: el
-- arreglo dirigido por el esquema —que la primera versión de esta migración no
-- tenía, y por eso fallaba— se ganó el sueldo en la primera aplicación real.
--
-- ── Una actualización que no cambia nada no cuenta ────────────────────────
--
-- El trigger solo sella si `NEW IS DISTINCT FROM OLD`. Sin eso, cualquier
-- `UPDATE` que reescriba los mismos valores —y en este cliente hay varios:
-- `actualizarConfirmado()` reenvía payloads completos— subiría la fila en la cola
-- sin que nada haya cambiado, que es justo el ruido que este campo viene a
-- quitar.
--
-- ── Lo que NO hace esta migración ─────────────────────────────────────────
--
-- **No cambia el orden de ninguna cola.** El código sigue ordenando por
-- `created_at`. Cambiarlo es un cambio de cliente aparte, con su propia prueba:
-- mover la cola del superadmin a `updated_at` altera lo que ve en pantalla, y eso
-- se decide mirándolo, no de paso en una migración de esquema.
-- ============================================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
  -- Solo si la fila cambió de verdad. `IS DISTINCT FROM` sobre el registro
  -- entero compara columna a columna tratando NULL como un valor, que es lo que
  -- hace falta aquí: dos NULL son «lo mismo».
  if new is distinct from old then
    new.updated_at := now();
  end if;
  return new;
end $$;

comment on function public.set_updated_at() is
  'H-19: sella updated_at en un BEFORE UPDATE, solo si la fila cambio de verdad (NEW IS DISTINCT FROM OLD). El trigger se llama trg_updated_at para que el orden alfabetico lo deje correr DESPUES de los trg_guard_*: sellar antes de saber si el cambio es legal es sellar una mentira.';

-- No se concede a nadie: es una funcion de trigger, no se llama desde el API.
-- (H-21 fue exactamente esto: diez funciones de trigger con EXECUTE para anon y
-- authenticated, que nadie puede invocar de todos modos.)
revoke all on function public.set_updated_at() from public, anon, authenticated;


do $$
declare
  t         text;
  tablas    text[] := array['pedidos','ofertas','reservaciones','perfiles',
                            'camiones','custodios','patios','lavados',
                            'operadores','expedientes'];
  v_filas   bigint;
  v_origen  text;
begin
  foreach t in array tablas loop
    execute format('alter table public.%I add column if not exists updated_at timestamptz not null default now()', t);

    -- De donde se rellena: `created_at` en nueve de las diez. `expedientes` NO
    -- LA TIENE —su marca de creacion es `solicitado_en`— y eso hizo fallar la
    -- primera version de esta migracion. Se resuelve contra el esquema, no de
    -- memoria, y si una tabla futura no tiene ninguna de las dos **se para**:
    -- dejarla con `now()` en silencio seria el empate gigante que este campo
    -- viene a evitar.
    select c.column_name into v_origen
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = t
       and c.column_name in ('created_at','solicitado_en')
     order by case c.column_name when 'created_at' then 0 else 1 end
     limit 1;
    if v_origen is null then
      raise exception 'H-19: % no tiene created_at ni solicitado_en: no hay de donde rellenar updated_at.', t;
    end if;

    -- El UPDATE va con los triggers de usuario apagados: los guards leen
    -- auth.uid(), que en psql es NULL, y rechazarian un cambio administrativo
    -- legitimo. Se vuelven a encender aqui mismo, y la comprobacion de abajo se
    -- niega a pasar si alguno quedo apagado.
    execute format('alter table public.%I disable trigger user', t);
    execute format('update public.%I set updated_at = %I where updated_at <> %I', t, v_origen, v_origen);
    get diagnostics v_filas = row_count;
    execute format('alter table public.%I enable trigger user', t);

    execute format('drop trigger if exists trg_updated_at on public.%I', t);
    execute format('create trigger trg_updated_at before update on public.%I for each row execute function public.set_updated_at()', t);

    raise notice '  % : updated_at anadido, % filas rellenadas desde %', rpad(t, 15), v_filas, v_origen;
  end loop;
end $$;


-- ── Comprobación ───────────────────────────────────────────────────────────
--
-- Cuatro cosas, y las dos últimas son las que de verdad protegen: que el sello
-- funcione, y que **no** se dispare cuando la fila no cambia. Todo en una
-- subtransacción que se descarta.

do $$
declare
  t        text;
  tablas   text[] := array['pedidos','ofertas','reservaciones','perfiles',
                           'camiones','custodios','patios','lavados',
                           'operadores','expedientes'];
  v_n      int;
  v_falta  text := '';
  v_apag   text := '';
  v_tarde  text := '';
  v_id     uuid;
  v_dsp    timestamptz;
begin
  foreach t in array tablas loop
    -- (a) la columna existe, es NOT NULL y no quedó ninguna fila sin sello
    if not exists (select 1 from information_schema.columns
                    where table_schema='public' and table_name=t
                      and column_name='updated_at' and is_nullable='NO') then
      v_falta := v_falta || t || ' ';
    end if;
    execute format('select count(*) from public.%I where updated_at is null', t) into v_n;
    if v_n > 0 then
      raise exception 'H-19: % tiene % filas con updated_at NULL.', t, v_n;
    end if;

    -- (b) el trigger existe
    if not exists (select 1 from pg_trigger g join pg_class c on c.oid = g.tgrelid
                    where c.relname = t and g.tgname = 'trg_updated_at' and not g.tgisinternal) then
      raise exception 'H-19: falta trg_updated_at en %.', t;
    end if;

    -- (c) NINGUN trigger quedó apagado por el relleno. Esto es lo que no puede
    --     fallar en silencio: un guard apagado en produccion es mucho peor que
    --     no tener updated_at.
    select count(*) into v_n from pg_trigger g join pg_class c on c.oid = g.tgrelid
     where c.relname = t and not g.tgisinternal and g.tgenabled = 'D';
    if v_n > 0 then
      v_apag := v_apag || t || '(' || v_n || ') ';
    end if;

    -- (d) y que ningun BEFORE ordene DESPUES de trg_updated_at: si alguien añade
    --     un trg_v* o trg_z*, correria despues y podria revertir NEW tras el sello.
    select string_agg(g.tgname, ', ') into v_tarde
      from pg_trigger g join pg_class c on c.oid = g.tgrelid
     where c.relname = t and not g.tgisinternal
       and (g.tgtype & 2) <> 0            -- BEFORE
       and g.tgname > 'trg_updated_at';
    if v_tarde is not null then
      raise exception 'H-19: en % hay triggers BEFORE que corren DESPUES de trg_updated_at: %. Renombralos o renombra este.', t, v_tarde;
    end if;
  end loop;

  if v_falta <> '' then
    raise exception 'H-19: sin columna updated_at NOT NULL: %', v_falta;
  end if;
  if v_apag <> '' then
    raise exception 'H-19: TRIGGERS APAGADOS tras el relleno: %. El DISABLE TRIGGER USER no se revirtio.', v_apag;
  end if;

  -- ── Comportamiento, en una subtransacción que se descarta ──────────────
  begin
    -- Se elige `perfiles` porque siempre tiene filas, y se toca una columna
    -- libre (`descripcion`). Los guards se apagan durante la prueba —en psql
    -- `auth.uid()` es NULL y `guard_perfil_self_update` rechazaria el cambio— y
    -- se deja encendido solo el que se esta probando. Todo se descarta al salir
    -- del bloque, incluidos los ALTER.
    --
    -- OJO: `now()` es la hora de la TRANSACCION, constante dentro de ella. Por
    -- eso no se compara «antes vs despues» con esperas: se compara contra el
    -- valor que dejo el relleno (`created_at`, que es pasado). Un `pg_sleep`
    -- aqui no haria avanzar nada y habria dado falsa confianza.
    select user_id into v_id from public.perfiles limit 1;
    if v_id is null then
      raise exception 'H-19: no hay perfiles; la prueba de comportamiento NO se ejecuto. No se da por buena.';
    end if;

    -- El sello se comprueba contra un CENTINELA, no comparando «antes vs
    -- despues». Primera version de esta prueba: se guardaba updated_at, se hacia
    -- el cambio, y se miraba si habia subido. **No servia**, y lo demostro
    -- sabotear el trigger a `if true` (sella siempre): como `now()` es la hora de
    -- la TRANSACCION y es constante dentro de ella, el sello del cambio real y el
    -- del no-op daban el MISMO valor, asi que la asercion del no-op no podia
    -- distinguir nada y el sabotaje paso en verde.
    --
    -- Con un centinela en el pasado la pregunta cambia: no es «subio?» sino
    -- «lo toco?». Eso si se distingue dentro de una sola transaccion.
    alter table public.perfiles disable trigger user;
    update public.perfiles set updated_at = '2000-01-01T00:00:00Z' where user_id = v_id;
    alter table public.perfiles enable trigger trg_updated_at;

    -- (e) un cambio real SELLA: el centinela tiene que desaparecer.
    update public.perfiles set descripcion = coalesce(descripcion,'') || ' H19' where user_id = v_id;
    select updated_at into v_dsp from public.perfiles where user_id = v_id;
    if v_dsp = '2000-01-01T00:00:00Z'::timestamptz then
      raise exception 'H-19: un cambio real NO sello updated_at: sigue en el centinela.';
    end if;
    if v_dsp <> now() then
      raise exception 'H-19: el sello no es now() sino %. Revisa set_updated_at().', v_dsp;
    end if;

    -- (f) un UPDATE que no cambia nada NO SELLA: el centinela tiene que
    --     sobrevivir. Sin el `IS DISTINCT FROM`, aqui se perderia.
    alter table public.perfiles disable trigger user;
    update public.perfiles set updated_at = '2000-01-01T00:00:00Z' where user_id = v_id;
    alter table public.perfiles enable trigger trg_updated_at;

    update public.perfiles set descripcion = descripcion where user_id = v_id;
    select updated_at into v_dsp from public.perfiles where user_id = v_id;
    if v_dsp <> '2000-01-01T00:00:00Z'::timestamptz then
      raise exception 'H-19: un UPDATE que no cambia nada SI sello updated_at (quedo en %). Cada reenvio de payload subiria la fila en la cola.', v_dsp;
    end if;

    raise exception 'H19-DESCARTAR';
  exception
    when others then
      if sqlerrm <> 'H19-DESCARTAR' then
        raise;
      end if;
  end;

  raise notice 'H-19: updated_at en las 10 tablas con flujo, con trg_updated_at corriendo despues de los guards. Ejercitado: un cambio real sella, un UPDATE que no cambia nada NO sella, y ningun trigger quedo apagado por el relleno.';
end $$;
