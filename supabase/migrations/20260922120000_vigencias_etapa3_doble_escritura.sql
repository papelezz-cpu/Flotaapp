-- ============================================================================
-- H-04 · Etapa 3 — Doble escritura: `vigencias` se mantiene sola
-- ============================================================================
--
-- La Etapa 2 copió lo que había. Desde ahora, cada vez que alguien escriba una
-- de las 35 columnas de documento o fecha, la fila de `vigencias` se actualiza
-- en el mismo acto.
--
-- **Las lecturas NO cambian.** Todas las pantallas siguen consultando las
-- columnas viejas. Aquí se vive un tiempo: si las dos fuentes divergen, se ve
-- sin que nadie pierda nada. La Etapa 4 es la que mueve las lecturas.
--
-- ── Por qué en la base y no en el cliente ─────────────────────────────────
--
-- Porque los sitios que escriben esas columnas hoy son **128** entre
-- admin.js (44), operadores.js (29) y aprobaciones.js (55). Duplicar la
-- escritura ahí significa tocar 128 puntos, y olvidar UNO no da error: deja
-- las dos fuentes divergiendo en silencio, que es justo lo que esta etapa
-- existe para poder detectar.
--
-- Y hay un escritor que el navegador no cubre: los clientes nativos de
-- iOS/Android escriben por su cuenta contra la misma base (docs/CONTRATO-
-- MOVIL.md). Un espejo en JavaScript los dejaría fuera.
--
-- En la base es un solo sitio, imposible de saltarse, y cubre a todo el que
-- escriba — incluidas las RPC y las Edge Functions.
--
-- ── El guard de la Etapa 1 estaba mal, y se corrige aquí ──────────────────
--
-- Al montar el espejo saltó esto, reproducido en banco local antes de tocar
-- nada:
--
--   ERROR: VIGENCIA_ACREDITADA: solo el superadmin puede modificar un
--          documento ya acreditado
--
-- La causa no era el espejo: era `guard_vigencia_update`, que aplicaba la
-- lección de H-02 —«solo el superadmin acredita»— a las CINCO entidades por
-- igual. Y las reglas reales no son iguales:
--
--   · `perfiles`  — `guard_perfil_self_update` impide a la empresa escribir
--                   sus propias fechas de vigencia. Esa es H-02, y sigue.
--   · flota       — `guard_fleet_resource_update` solo impide auto-aprobarse
--                   y transferir la propiedad. La empresa SÍ edita hoy las
--                   fechas de su propio camión, y al hacerlo la unidad vuelve
--                   a `aprobacion = 'pendiente'`.
--
-- Mi guard era más estricto que el sistema, así que el espejo no podía
-- reflejar una escritura que la fuente sí permite. Se corrige para que diga
-- lo mismo que las reglas de origen, ni más ni menos. Con eso el espejo no
-- necesita ninguna puerta trasera: hereda la autorización de la fuente,
-- porque la escritura de origen ya pasó por su propio RLS y su propio guard.
--
-- ============================================================================


-- ── 1 · El guard, con la regla real de cada entidad ────────────────────────

create or replace function public.guard_vigencia_update()
returns trigger language plpgsql
security definer set search_path to 'public', 'pg_temp' as $$
begin
  if public.is_superadmin() then return new; end if;

  -- El perfil de empresa: H-02. La empresa propone, el superadmin acredita.
  -- Sin esto, quitar la casilla de la interfaz no protegería nada, porque RLS
  -- deja a la empresa actualizar su propia fila.
  if old.entidad_tipo = 'perfil' then
    if old.estado = 'vigente' then
      raise exception 'VIGENCIA_ACREDITADA: solo el superadmin puede modificar un documento acreditado de empresa';
    end if;
    if new.estado is distinct from old.estado then
      raise exception 'VIGENCIA_SIN_AUTOACREDITAR: solo el superadmin acredita un documento de empresa';
    end if;
  else
    -- Flota y operadores: el dueño mantiene los papeles de su recurso, igual
    -- que hoy hace sobre las columnas. Lo que NO puede es acreditarse solo:
    -- pasar una propuesta a `vigente` sigue siendo del superadmin.
    if new.estado is distinct from old.estado and new.estado = 'vigente' then
      raise exception 'VIGENCIA_SIN_AUTOACREDITAR: solo el superadmin pasa un documento a vigente';
    end if;
  end if;

  -- Para todos: la revisión la firma quien revisa.
  if new.revisado_por is distinct from old.revisado_por
     or new.revisado_en is distinct from old.revisado_en then
    raise exception 'VIGENCIA_SIN_AUTOREVISAR: la revisión la firma el superadmin';
  end if;

  -- Y nadie se cuelga un documento de una entidad que no es suya.
  if new.entidad_tipo is distinct from old.entidad_tipo
     or new.entidad_id is distinct from old.entidad_id then
    raise exception 'VIGENCIA_SIN_MUDANZA: un documento no cambia de dueño';
  end if;

  return new;
end $$;


-- ── 2 · El espejo ──────────────────────────────────────────────────────────
--
-- Una sola función para las cinco tablas. El mapeo vive aquí como datos —la
-- misma lista que usó la Etapa 2— y se recorre con `to_jsonb(new)`, que deja
-- leer la columna por su nombre sin escribir cinco funciones casi iguales.
--
-- Tres casos por par (archivo, fecha):
--   · hay algo  ->  se inserta o se actualiza la fila
--   · no hay nada y antes sí  ->  se borra la fila: el papel se quitó y el
--     espejo tiene que reflejarlo, o dejaría un documento fantasma vigilando
--   · no hay nada y antes tampoco  ->  nada que hacer
--
-- Es SECURITY DEFINER, así que salta el RLS de `vigencias`. Eso es correcto y
-- conviene decir por qué: su autoridad no es propia, es la de la escritura
-- que lo disparó, y esa ya pasó por el RLS y el guard de su tabla. Los guards
-- de `vigencias` SÍ siguen aplicando —leen auth.uid() y se disparan también
-- dentro de un SECURITY DEFINER—, que es lo que se acaba de corregir arriba.

create or replace function public.vigencias_espejo()
returns trigger language plpgsql
security definer set search_path to 'public', 'pg_temp' as $$
declare
  j        jsonb := to_jsonb(new);
  m        record;
  v_ent    text;
  v_id     text;
  v_arch   text;
  v_fecha  date;
begin
  for m in
    select * from (values
      -- tabla,        entidad,    tipo_documento,        col_archivo,                 col_fecha,                              estado
      ('perfiles',   'perfil',   'permiso_sct',         'doc_permiso_sct',            'fecha_vencimiento_permiso_sct',        'vigente'),
      ('perfiles',   'perfil',   'seguro_rc',           'doc_seguro_rc',              'fecha_vencimiento_seguro_rc',          'vigente'),
      ('perfiles',   'perfil',   'seguro_carga',        'doc_seguro_carga',           'fecha_vencimiento_seguro_carga',       'vigente'),
      ('perfiles',   'perfil',   'permiso_sct',         'doc_permiso_sct_pendiente',  'fecha_vencimiento_permiso_sct_pendiente',  'pendiente'),
      ('perfiles',   'perfil',   'seguro_rc',           'doc_seguro_rc_pendiente',    'fecha_vencimiento_seguro_rc_pendiente',    'pendiente'),
      ('perfiles',   'perfil',   'seguro_carga',        'doc_seguro_carga_pendiente', 'fecha_vencimiento_seguro_carga_pendiente', 'pendiente'),
      ('camiones',   'camion',   'tarjeta_circulacion', 'imagen_tc',                  'fecha_vencimiento_tc',                 'vigente'),
      ('camiones',   'camion',   'seguro_unidad',       'doc_seguro',                 'fecha_vencimiento_seguro',             'vigente'),
      ('camiones',   'camion',   'permiso_sct_unidad',  'doc_sct',                    'fecha_vencimiento_permiso_sct',        'vigente'),
      ('camiones',   'camion',   'verificacion',        'doc_verificacion',           'fecha_vencimiento_verificacion',       'vigente'),
      ('camiones',   'camion',   'permiso_peligrosa',   'doc_permiso_peligrosa',      'fecha_vencimiento_permiso_peligrosa',  'vigente'),
      ('camiones',   'camion',   'caat',                'doc_caat',                   'vigencia_caat',                        'vigente'),
      ('operadores', 'operador', 'licencia',            'foto_licencia',              'fecha_vencimiento',                    'vigente'),
      ('operadores', 'operador', 'licencia_peligrosa',  'doc_licencia_peligrosa',     'fecha_vencimiento_licencia_peligrosa', 'vigente'),
      ('operadores', 'operador', 'examen_medico',       'doc_examen_medico',          'fecha_examen_medico',                  'vigente'),
      ('operadores', 'operador', 'examen_toxicologico', 'doc_examen_toxicologico',    'fecha_examen_toxicologico',            'vigente'),
      ('operadores', 'operador', 'carta_antecedentes',  'doc_carta_antecedentes',     'fecha_carta_antecedentes',             'vigente'),
      ('custodios',  'custodio', 'certificacion',       null,                         'fecha_vencimiento_cert',               'vigente'),
      ('custodios',  'custodio', 'licencia_sedena',     'doc_licencia_sedena',        'fecha_vencimiento_licencia_sedena',    'vigente'),
      ('patios',     'patio',    'permiso_patio',       'doc_permiso',                'fecha_vencimiento_permiso',            'vigente')
    ) t(tabla, entidad, tipo, col_arch, col_fecha, estado)
    where t.tabla = tg_table_name
  loop
    v_ent   := m.entidad;
    v_id    := case when m.tabla = 'perfiles' then j->>'user_id' else j->>'id' end;
    v_arch  := case when m.col_arch is null then null else j->>(m.col_arch) end;
    v_fecha := nullif(j->>(m.col_fecha), '')::date;

    if v_arch is null and v_fecha is null then
      -- El papel se quitó: el espejo no puede dejar un documento fantasma.
      delete from public.vigencias
       where entidad_tipo = v_ent and entidad_id = v_id
         and tipo_documento = m.tipo and estado = m.estado;
    elsif m.estado = 'vigente' then
      insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, archivo_path, fecha_documento, estado)
      values (v_ent, v_id, m.tipo, v_arch, v_fecha, 'vigente')
      on conflict (entidad_tipo, entidad_id, tipo_documento) where estado = 'vigente'
      do update set archivo_path = excluded.archivo_path,
                    fecha_documento = excluded.fecha_documento;
    else
      insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, archivo_path, fecha_documento, estado)
      values (v_ent, v_id, m.tipo, v_arch, v_fecha, 'pendiente')
      on conflict (entidad_tipo, entidad_id, tipo_documento) where estado = 'pendiente'
      do update set archivo_path = excluded.archivo_path,
                    fecha_documento = excluded.fecha_documento;
    end if;
  end loop;

  return new;
end $$;

revoke all on function public.vigencias_espejo() from public, anon, authenticated;

-- AFTER: la fila de origen ya está escrita y validada por su propio guard
-- cuando el espejo corre. Si el espejo falla, la transacción entera revierte
-- y la escritura de origen tampoco entra — que es lo que se quiere: nunca una
-- fuente sin su espejo.
drop trigger if exists trg_vigencias_espejo on public.perfiles;
create trigger trg_vigencias_espejo after insert or update on public.perfiles
  for each row execute function public.vigencias_espejo();

drop trigger if exists trg_vigencias_espejo on public.camiones;
create trigger trg_vigencias_espejo after insert or update on public.camiones
  for each row execute function public.vigencias_espejo();

drop trigger if exists trg_vigencias_espejo on public.operadores;
create trigger trg_vigencias_espejo after insert or update on public.operadores
  for each row execute function public.vigencias_espejo();

drop trigger if exists trg_vigencias_espejo on public.custodios;
create trigger trg_vigencias_espejo after insert or update on public.custodios
  for each row execute function public.vigencias_espejo();

drop trigger if exists trg_vigencias_espejo on public.patios;
create trigger trg_vigencias_espejo after insert or update on public.patios
  for each row execute function public.vigencias_espejo();


-- ── 3 · Comprobación ───────────────────────────────────────────────────────

do $$
declare v_falta text; v_n int;
begin
  select string_agg(t, ', ') into v_falta from (
    select t from unnest(array['perfiles','camiones','operadores','custodios','patios']) t
     where not exists (select 1 from pg_trigger
                        where tgrelid = ('public.'||t)::regclass
                          and tgname = 'trg_vigencias_espejo')) s;
  if v_falta is not null then
    raise exception 'H-04 etapa 3: falta el trigger espejo en: %', v_falta;
  end if;

  -- El espejo no debe ser invocable por nadie de fuera.
  if has_function_privilege('anon', 'public.vigencias_espejo()', 'EXECUTE')
  or has_function_privilege('authenticated', 'public.vigencias_espejo()', 'EXECUTE') then
    raise exception 'H-04/H-21: vigencias_espejo() conserva EXECUTE';
  end if;

  -- Y el guard corregido tiene que seguir distinguiendo perfil de flota.
  select count(*) into v_n from pg_proc
   where proname = 'guard_vigencia_update'
     and prosrc like '%entidad_tipo = ''perfil''%';
  if v_n <> 1 then
    raise exception 'H-04 etapa 3: el guard no distingue el perfil de la flota. Sin eso, o bloquea al espejo o reabre H-02.';
  end if;

  raise notice 'H-04 etapa 3: espejo en las cinco tablas, guard corregido por entidad.';
  raise notice 'H-04 etapa 3: las lecturas NO cambian. Ninguna pantalla se entera todavía.';
end $$;
