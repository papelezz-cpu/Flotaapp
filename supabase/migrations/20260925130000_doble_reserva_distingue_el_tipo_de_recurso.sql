-- ============================================================================
-- La doble reserva distingue el tipo de recurso (H-06 a)
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- `reservaciones.unidad` es un `text` que guarda el id de un camión, un
-- custodio, un patio o un lavado según `recurso_tipo`. Cuatro tablas con PK
-- propia: no hay clave foránea posible y no existe. Lo sostienen el trigger
-- `trg_guard_unidad_existe` —que resuelve la tabla con `tabla_recurso()`— y un
-- convenio de prefijos en los id.
--
-- Pero la protección contra doble reserva **no mira `recurso_tipo`**, así que
-- trata «PAT-001» y «PAT-001» como el mismo recurso aunque uno sea un patio y
-- el otro un camión. Reservar uno impediría reservar el otro en las mismas
-- fechas, con un `RECURSO_NO_DISPONIBLE` sobre un recurso libre.
--
-- ── Lo que la ficha del hallazgo se dejó ──────────────────────────────────
--
-- H-06 propone «añadir `recurso_tipo` a la restricción EXCLUDE». Eso solo
-- arregla la mitad, y no la mitad que se ve. **Son DOS capas**, y la que da la
-- cara es la otra:
--
--   · `check_reservacion_disponibilidad()` — trigger BEFORE INSERT/UPDATE.
--     Compara `unidad = NEW.unidad` y nada más, y es quien LANZA el
--     `RECURSO_NO_DISPONIBLE` que la propia ficha cita como síntoma.
--   · `reservaciones_sin_solape` — EXCLUDE con GiST sobre `unidad` y el rango
--     de fechas. Es la red contra la carrera: dos inserciones simultáneas que
--     ambas pasan el trigger.
--
-- El trigger es BEFORE, así que **salta antes de que la restricción llegue a
-- evaluarse**. Arreglar solo el EXCLUDE habría dejado el falso positivo
-- exactamente igual de visible, y habría parecido arreglado.
--
-- ── Por qué es seguro ─────────────────────────────────────────────────────
--
-- Añadir una columna a un `EXCLUDE` lo hace **más permisivo**, no menos: un par
-- de filas choca solo si TODOS los operadores casan, así que exigir además
-- `recurso_tipo WITH =` reduce los pares en conflicto. Ninguna fila que cumpla
-- la restricción actual puede incumplir la nueva. La ficha pedía comprobar antes
-- que ninguna fila viva la incumple; no hace falta comprobarlo, se deduce — y
-- el bloque de abajo lo comprueba igualmente, que es más barato que razonarlo
-- mal.
--
-- El riesgo real de este cambio es el opuesto, y sí se verificó: si
-- `recurso_tipo` admitiera NULL, `NULL = NULL` no es cierto y la protección
-- quedaría **desactivada** para esa fila. No puede pasar:
--
--     recurso_tipo text DEFAULT 'camion' NOT NULL
--     CONSTRAINT reservaciones_recurso_tipo_check
--       CHECK (recurso_tipo = ANY (ARRAY['camion','custodio','patio','lavado']))
--
-- (`unidad` sí es nullable, y con `unidad` NULL la protección ya no actúa hoy.
-- Es anterior a este cambio y no lo empeora; queda anotado. Medido: 0 de las 2
-- filas en `Pendiente`/`Activa` tienen `unidad` NULL.)
--
-- ── Estado medido en producción (volcado del 2026-09-21) ──────────────────
--
--     reservaciones            20 filas   (19 camion, 1 custodio)
--     en Pendiente/Activa       2 filas   ← las únicas que vigila el EXCLUDE
--     unidad usada con más de un recurso_tipo:   ninguna
--     colisiones de id entre las cinco tablas:   ninguna
--
-- O sea: **hoy el falso positivo no puede ocurrir.** Esto cierra una puerta
-- antes de que alguien entre por ella, y cuesta una migración de 20 filas.
--
-- ── Sobre (c), el CHECK de prefijos: no se hace, y no por pereza ───────────
--
-- H-06 (c) propone «evaluar un CHECK de prefijo por tabla que convierta el
-- convenio en regla». Medido en el volcado, el convenio **no es por tabla**:
--
--     camiones    12 filas   prefijos C, T, R, F, S   ← cinco, no dos
--     custodios    6 filas   CUS
--     patios       5 filas   PAT
--     lavados      1 fila    LAV
--     operadores   3 filas   OP
--
-- En `camiones` el prefijo codifica el **tipo de camión**, no la tabla. Un CHECK
-- tendría que enumerar los cinco de hoy y se rompería con el sexto tipo que
-- alguien dé de alta — una restricción que falla al añadir un producto nuevo.
-- Y sobre todo: **con `recurso_tipo` en las dos capas, el convenio deja de
-- sostener nada.** Una colisión entre tablas ya no tiene consecuencia, que era
-- la única razón para convertirlo en regla. (c) se queda sin hacer por
-- innecesario, no por coste.
--
-- Lo que sigue sosteniendo la referencia es `trg_guard_unidad_existe`, que no se
-- toca: sigue exigiendo que el id exista en la tabla que dice `recurso_tipo`.
-- ============================================================================

-- ── 1. El trigger, que es quien da la cara ────────────────────────────────

create or replace function public.check_reservacion_disponibilidad()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM reservaciones
    WHERE unidad = NEW.unidad
      -- H-06: sin esto, un patio y un camión que compartan cadena de id se
      -- estorban entre ellos. `recurso_tipo` es NOT NULL con CHECK, así que
      -- esta comparación nunca se vuelve NULL y nunca desactiva la protección.
      AND recurso_tipo = NEW.recurso_tipo
      AND estado IN ('Pendiente', 'Activa')
      AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND tstzrange(fecha_ini::timestamptz, fecha_fin::timestamptz, '[]')
       && tstzrange(NEW.fecha_ini::timestamptz, NEW.fecha_fin::timestamptz, '[]')
  ) THEN
    RAISE EXCEPTION 'RECURSO_NO_DISPONIBLE: El recurso ya tiene una reserva activa en esas fechas';
  END IF;
  RETURN NEW;
END;
$$;

comment on function public.check_reservacion_disponibilidad() is
  'H-06: impide solapar reservas del MISMO recurso, comparando recurso_tipo ademas de unidad. Es la capa que lanza RECURSO_NO_DISPONIBLE y es BEFORE, asi que salta antes que reservaciones_sin_solape; las dos tienen que mirar lo mismo o la restriccion nunca se evalua.';


-- ── 2. La restricción, que es la red contra la carrera ────────────────────
--
-- Recrearla exige retirar la anterior: un EXCLUDE no se altera en sitio. Va en
-- la misma transacción que el ADD, así que no hay ni un instante sin
-- protección. Con 20 filas el índice GiST se reconstruye al momento.

alter table public.reservaciones drop constraint if exists reservaciones_sin_solape;

alter table public.reservaciones
  add constraint reservaciones_sin_solape
  exclude using gist (
    recurso_tipo with =,
    unidad       with =,
    daterange(fecha_ini, fecha_fin, '[]') with &&
  ) where (estado = any (array['Pendiente'::text, 'Activa'::text]));

comment on constraint reservaciones_sin_solape on public.reservaciones is
  'H-06: solape prohibido para el mismo recurso_tipo Y la misma unidad. recurso_tipo va PRIMERO porque es el mas selectivo de los dos en el indice GiST. Red contra la carrera de check_reservacion_disponibilidad(), que es BEFORE y no ve inserciones simultaneas.';


-- ── Comprobación ───────────────────────────────────────────────────────────
--
-- Lo estructural y lo de comportamiento. Lo segundo es lo que importa: prueba
-- que el falso positivo desaparece, que la protección real sigue en pie, y
-- **que las dos capas lo hacen por separado** — porque el trigger tapa a la
-- restricción, y una restricción que nadie llega a evaluar puede estar mal
-- durante meses sin que nada falle.
--
-- Todo dentro de una subtransacción que se descarta: no se borra nada.

do $$
declare
  v_cam    text;
  v_cli    uuid;
  v_prop   uuid;
  v_d      date := current_date + 3650;   -- diez años fuera: no roza dato real
  v_ok     boolean;
  v_def    text;
  v_r1     uuid := gen_random_uuid();
  v_r2     uuid := gen_random_uuid();
begin
  -- ── Estructural ────────────────────────────────────────────────────────
  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conname = 'reservaciones_sin_solape'
     and conrelid = 'public.reservaciones'::regclass;
  if v_def is null then
    raise exception 'H-06: reservaciones_sin_solape no existe. Se retiro y no se volvio a crear: la tabla quedo SIN red contra la doble reserva.';
  end if;
  if v_def not like '%recurso_tipo%' then
    raise exception 'H-06: la restriccion no incluye recurso_tipo: %', v_def;
  end if;
  if v_def not like '%unidad%' or v_def not like '%daterange%' then
    raise exception 'H-06: la restriccion perdio unidad o el rango de fechas: %', v_def;
  end if;

  if not exists (select 1 from pg_proc
                  where proname = 'check_reservacion_disponibilidad'
                    and pronamespace = 'public'::regnamespace
                    and prosrc like '%recurso_tipo = NEW.recurso_tipo%') then
    raise exception 'H-06: el trigger check_reservacion_disponibilidad sigue comparando solo unidad. Es BEFORE, asi que el falso positivo se veria igual aunque la restriccion este bien.';
  end if;

  -- ── Comportamiento ─────────────────────────────────────────────────────
  select id into v_cam from public.camiones limit 1;
  select user_id into v_cli  from public.perfiles where rol = 'cliente' limit 1;
  select user_id into v_prop from public.perfiles where rol = 'admin'   limit 1;
  if v_cam is null or v_cli is null or v_prop is null then
    raise exception 'H-06: falta un camion, un cliente o una empresa para la prueba de comportamiento. NO se da por buena.';
  end if;

  begin
    -- `guard_reservacion_insert` deja pasar con este GUC: es la misma puerta que
    -- usa cerrar_acuerdo(), no un agujero abierto para la prueba.
    perform set_config('portgo.cierre_acuerdo', 'on', true);

    -- Un patio que comparte cadena de id con un camion. Es el escenario que hoy
    -- "no puede pasar porque los prefijos difieren" — y nada en el esquema lo
    -- impide, que es justamente el motivo de esta migracion.
    insert into public.patios (id, nombre, tipo, propietario_id)
    values (v_cam, 'PRUEBA H-06', 'techado', v_prop);

    -- (1) Reserva del CAMION.
    insert into public.reservaciones (id, unidad, recurso_tipo, cliente_user_id, propietario_id,
                                      cliente, fecha_ini, fecha_fin, estado)
    values (v_r1, v_cam, 'camion', v_cli, v_prop, 'PRUEBA H-06', v_d, v_d + 2, 'Activa');

    -- (2) Reserva del PATIO con la misma cadena y las mismas fechas.
    --     ESTO es lo que fallaba. Tiene que entrar.
    begin
      insert into public.reservaciones (id, unidad, recurso_tipo, cliente_user_id, propietario_id,
                                        cliente, fecha_ini, fecha_fin, estado)
      values (v_r2, v_cam, 'patio', v_cli, v_prop, 'PRUEBA H-06', v_d, v_d + 2, 'Activa');
    exception when others then
      raise exception 'H-06: un patio y un camion que comparten id SIGUEN estorbandose (%). El falso positivo no se cerro.', sqlerrm;
    end;

    -- (3) Y la proteccion de verdad sigue en pie: otro camion, misma unidad,
    --     fechas solapadas -> tiene que fallar. Si esto entra, el cambio
    --     desactivo la doble reserva en vez de afinarla.
    v_ok := false;
    begin
      insert into public.reservaciones (unidad, recurso_tipo, cliente_user_id, propietario_id,
                                        cliente, fecha_ini, fecha_fin, estado)
      values (v_cam, 'camion', v_cli, v_prop, 'PRUEBA H-06', v_d + 1, v_d + 3, 'Activa');
    exception when others then
      v_ok := true;
      if position('RECURSO_NO_DISPONIBLE' in sqlerrm) = 0 then
        raise exception 'H-06: el solape del mismo recurso se rechazo, pero NO por el trigger (%). El mensaje que ve el usuario cambio.', sqlerrm;
      end if;
    end;
    if not v_ok then
      raise exception 'H-06: se pudo solapar DOS reservas del mismo camion. La prueba sabe fallar: si esto pasa, la doble reserva quedo abierta.';
    end if;

    -- (4) La misma prueba con el trigger APAGADO, para que la responda la
    --     restriccion y no el trigger. Sin esto, un EXCLUDE mal escrito se
    --     quedaria oculto detras del BEFORE durante meses.
    alter table public.reservaciones disable trigger trg_check_reservacion_disponibilidad;
    v_ok := false;
    begin
      insert into public.reservaciones (unidad, recurso_tipo, cliente_user_id, propietario_id,
                                        cliente, fecha_ini, fecha_fin, estado)
      values (v_cam, 'camion', v_cli, v_prop, 'PRUEBA H-06', v_d + 1, v_d + 3, 'Activa');
    exception when exclusion_violation then
      v_ok := true;
    end;
    alter table public.reservaciones enable trigger trg_check_reservacion_disponibilidad;
    if not v_ok then
      raise exception 'H-06: con el trigger apagado, la RESTRICCION dejo solapar el mismo camion. La red contra la carrera no esta cerrada.';
    end if;

    -- (5) Y con el trigger apagado, los dos tipos distintos siguen pudiendo
    --     convivir: eso lo decide la restriccion, no el trigger.
    alter table public.reservaciones disable trigger trg_check_reservacion_disponibilidad;
    begin
      insert into public.reservaciones (unidad, recurso_tipo, cliente_user_id, propietario_id,
                                        cliente, fecha_ini, fecha_fin, estado)
      values (v_cam, 'lavado', v_cli, v_prop, 'PRUEBA H-06', v_d, v_d + 2, 'Activa');
      raise exception 'H-06-LAVADO-ENTRO';
    exception
      when others then
        if sqlerrm <> 'H-06-LAVADO-ENTRO' then
          -- guard_unidad_existe lo rechaza porque no hay lavado con ese id, y
          -- eso es CORRECTO: la referencia sigue vigilada. Lo que no debe pasar
          -- es que lo rechace la restriccion de solape.
          if sqlerrm like '%solape%' or position('exclusion' in lower(sqlerrm)) > 0 then
            raise exception 'H-06: la restriccion rechazo un recurso_tipo DISTINTO (%). Sigue mezclando tipos.', sqlerrm;
          end if;
        end if;
    end;
    alter table public.reservaciones enable trigger trg_check_reservacion_disponibilidad;

    raise exception 'H-06-DESCARTAR';
  exception
    when others then
      -- El ALTER de reactivacion se deshace con la subtransaccion, asi que el
      -- trigger vuelve solo. No hace falta rehabilitarlo aqui.
      if sqlerrm <> 'H-06-DESCARTAR' then
        raise;
      end if;
  end;

  raise notice 'H-06: la doble reserva distingue el tipo. Ejercitado: patio y camion con el MISMO id ya no se estorban; dos reservas del mismo camion siguen prohibidas por el trigger; y con el trigger apagado las prohibe la restriccion. Constraint: %', v_def;
end $$;
