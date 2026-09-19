-- ============================================================================
-- H-04 · Etapa 1 — La tabla `vigencias`, que todavía nadie lee
-- ============================================================================
--
-- ── Qué resuelve ──────────────────────────────────────────────────────────
--
-- «Un papel, su ruta en Storage y su fecha» está modelado cinco veces en unas
-- 35 columnas con cinco nomenclaturas distintas: perfiles, camiones,
-- operadores, custodios y patios. Añadir un tipo de documento son dos
-- columnas, una migración, un cambio de formulario y dos de consulta, POR
-- TABLA. Y ninguna de esas fechas está indexada, así que las diez consultas
-- de js/vigencias.js hacen secuencial.
--
-- ── Qué NO hace esta migración ────────────────────────────────────────────
--
-- No copia datos, no cambia ninguna lectura, no retira ni una columna. Crea
-- la tabla, su catálogo, sus restricciones, su RLS y su guard. El objetivo es
-- que aplicarla no cambie el comportamiento de una sola pantalla.
--
-- Etapa 2 copia (~44 filas, medidas). Etapa 3 dobla la escritura. Etapa 4
-- cambia lecturas fichero a fichero. Etapa 5 mueve los guards. Retirar
-- columnas no forma parte del plan — ver docs/PLAN-H04-VIGENCIAS.md.
--
-- ── La decisión de diseño que salió de leer el código ──────────────────────
--
-- Las columnas de hoy NO guardan todas lo mismo. `fecha_vencimiento_seguro`
-- es una caducidad; `fecha_examen_medico` es la fecha DEL EXAMEN, y
-- js/vigencias.js:69-72 le suma un año en JavaScript para saber cuándo vence.
-- Lo mismo con el toxicológico y la carta de antecedentes.
--
-- Meterlas todas en un `fecha_vencimiento` perdería esa diferencia, y
-- calcular la caducidad al copiar hornearía la regla en los datos: el día que
-- un examen valga dos años, las filas viejas quedarían mal y nadie sabría por
-- qué.
--
-- Así que se guarda LO QUE EL USUARIO CAPTURÓ, en `fecha_documento`, y la
-- regla vive en el catálogo: `meta->>'vigencia_meses'`. Nulo significa «la
-- fecha capturada YA es la caducidad». La caducidad efectiva se calcula al
-- leer, con la función `vigencia_vence_el()`. Cambiar la regla pasa a ser un
-- UPDATE a una fila de catálogo, no una migración — que es exactamente el
-- beneficio que justifica todo este trabajo.
--
-- ── Sin `begin` ni `commit` en este fichero ───────────────────────────────
--
-- Los guiones aplicar-a-* ya envuelven todo en --single-transaction, y
-- aplicar-a-produccion.sh aplica VARIOS archivos en una sola: "o entra el
-- conjunto o no entra nada". Un `commit` aquí dentro cerraría esa transacción
-- a mitad de tanda, dejando lo anterior confirmado y lo posterior fuera de la
-- garantía. Las otras 74 migraciones de este repositorio no lo llevan; esta
-- lo llevó por error y se vio al aplicarla, por dos WARNING de psql.
--
-- ============================================================================

-- ── 1 · El catálogo de tipos de documento ──────────────────────────────────
--
-- Va en `catalogos`, la tabla que este proyecto ya usa para «valores que se
-- editan sin desplegar». La clave es 'vigencia_tipo'.
--
-- `meta` lleva dos cosas por tipo:
--   entidad_tipo    a qué se le pega ese documento
--   vigencia_meses  cuántos meses vale desde la fecha capturada; null = la
--                   fecha capturada ya es la caducidad
--
-- Los 17 tipos salen de las columnas que existen hoy, una por una. Donde hoy
-- hay documento y fecha separados, se unen en un tipo.

insert into public.catalogos (clave, valor, etiqueta, orden, activo, meta) values
  -- perfiles (3)
  ('vigencia_tipo','permiso_sct',        'Permiso SCT',                    10, true, '{"entidad_tipo":"perfil","vigencia_meses":null}'),
  ('vigencia_tipo','seguro_rc',          'Seguro de responsabilidad civil',20, true, '{"entidad_tipo":"perfil","vigencia_meses":null}'),
  ('vigencia_tipo','seguro_carga',       'Seguro de carga',                30, true, '{"entidad_tipo":"perfil","vigencia_meses":null}'),
  -- camiones (6)
  ('vigencia_tipo','tarjeta_circulacion','Tarjeta de circulación',         40, true, '{"entidad_tipo":"camion","vigencia_meses":null}'),
  ('vigencia_tipo','seguro_unidad',      'Seguro de la unidad',            50, true, '{"entidad_tipo":"camion","vigencia_meses":null}'),
  ('vigencia_tipo','permiso_sct_unidad', 'Permiso SCT de la unidad',       60, true, '{"entidad_tipo":"camion","vigencia_meses":null}'),
  ('vigencia_tipo','verificacion',       'Verificación',                   70, true, '{"entidad_tipo":"camion","vigencia_meses":null}'),
  ('vigencia_tipo','permiso_peligrosa',  'Permiso de materiales peligrosos',80,true, '{"entidad_tipo":"camion","vigencia_meses":null}'),
  ('vigencia_tipo','caat',               'CAAT',                           90, true, '{"entidad_tipo":"camion","vigencia_meses":null}'),
  -- operadores (5) — tres de ellas son fecha de EMISIÓN, no de caducidad
  ('vigencia_tipo','licencia',           'Licencia de conducir',          100, true, '{"entidad_tipo":"operador","vigencia_meses":null}'),
  ('vigencia_tipo','licencia_peligrosa', 'Licencia de materiales peligrosos',110,true,'{"entidad_tipo":"operador","vigencia_meses":null}'),
  ('vigencia_tipo','examen_medico',      'Examen médico',                 120, true, '{"entidad_tipo":"operador","vigencia_meses":12}'),
  ('vigencia_tipo','examen_toxicologico','Examen toxicológico',           130, true, '{"entidad_tipo":"operador","vigencia_meses":12}'),
  ('vigencia_tipo','carta_antecedentes', 'Carta de no antecedentes',      140, true, '{"entidad_tipo":"operador","vigencia_meses":12}'),
  -- custodios (2) y patios (1) — se modelan por completitud. Hoy no tienen
  -- ni un dato y sus pantallas están apagadas (ver FLUJO-OPERATIVO.md).
  ('vigencia_tipo','certificacion',      'Certificación',                 150, true, '{"entidad_tipo":"custodio","vigencia_meses":null}'),
  ('vigencia_tipo','licencia_sedena',    'Licencia SEDENA',               160, true, '{"entidad_tipo":"custodio","vigencia_meses":null}'),
  ('vigencia_tipo','permiso_patio',      'Permiso de operación del patio',170, true, '{"entidad_tipo":"patio","vigencia_meses":null}')
on conflict (clave, valor) do nothing;


-- ── 2 · La tabla ───────────────────────────────────────────────────────────

create table if not exists public.vigencias (
  id                uuid primary key default gen_random_uuid(),
  entidad_tipo      text not null,
  entidad_id        text not null,
  tipo_documento    text not null,
  archivo_path      text,
  fecha_documento   date,
  estado            text not null default 'vigente',
  nota_rechazo      text,
  subido_en         timestamptz not null default now(),
  subido_por        uuid references auth.users(id) on delete set null,
  revisado_en       timestamptz,
  revisado_por      uuid references auth.users(id) on delete set null,

  -- Columna generada con un valor constante, solo para poder colgar una FK
  -- COMPUESTA del catálogo. Se probó en un banco local antes de escribirla:
  -- PostgreSQL la acepta en una clave foránea y rechaza un tipo inventado.
  -- Es una FK de verdad, no un trigger que se olvide de comprobar.
  cat_clave         text generated always as ('vigencia_tipo'::text) stored,

  constraint vigencias_entidad_tipo_check
    check (entidad_tipo in ('perfil','camion','operador','custodio','patio')),
  constraint vigencias_estado_check
    check (estado in ('vigente','pendiente','rechazado')),

  -- Una fila sin papel Y sin fecha no dice nada. H-02 enseñó lo que cuesta un
  -- campo que existe y está vacío: el control parece estar y no está.
  constraint vigencias_algo_que_guardar
    check (archivo_path is not null or fecha_documento is not null),

  -- Un rechazo sin motivo es una notificación inútil para quien la recibe.
  constraint vigencias_rechazo_con_motivo
    check (estado <> 'rechazado' or nota_rechazo is not null),

  constraint vigencias_tipo_del_catalogo
    foreign key (cat_clave, tipo_documento)
    references public.catalogos (clave, valor)
);

-- El tipo tiene que corresponder a la entidad: un 'seguro_rc' es de un
-- perfil, no de un camión. La FK garantiza que el tipo existe; esto, que va
-- donde debe.
create or replace function public.vigencias_tipo_coincide()
returns trigger language plpgsql
security definer set search_path to 'public', 'pg_temp' as $$
declare v_esperado text;
begin
  select meta->>'entidad_tipo' into v_esperado
    from public.catalogos
   where clave = 'vigencia_tipo' and valor = new.tipo_documento;
  if v_esperado is distinct from new.entidad_tipo then
    raise exception 'VIGENCIA_TIPO_AJENO: % es de % y se intentó colgar de %',
      new.tipo_documento, coalesce(v_esperado,'(sin entidad)'), new.entidad_tipo;
  end if;
  return new;
end $$;

drop trigger if exists trg_vigencias_tipo_coincide on public.vigencias;
create trigger trg_vigencias_tipo_coincide
  before insert or update of tipo_documento, entidad_tipo on public.vigencias
  for each row execute function public.vigencias_tipo_coincide();


-- ── 3 · Uno vigente y uno pendiente, no más ────────────────────────────────
--
-- Hoy `perfiles` tiene doc_seguro_rc y doc_seguro_rc_pendiente: la empresa
-- PROPONE una renovación sin destruir la que sigue valiendo, y el superadmin
-- acredita. Un único UNIQUE(entidad, tipo) rompería eso.
--
-- Dos índices parciales lo modelan tal cual: como mucho un vigente y como
-- mucho un pendiente por documento. Los rechazados no se limitan — son
-- historial.

create unique index if not exists vigencias_uno_vigente
  on public.vigencias (entidad_tipo, entidad_id, tipo_documento)
  where estado = 'vigente';

create unique index if not exists vigencias_uno_pendiente
  on public.vigencias (entidad_tipo, entidad_id, tipo_documento)
  where estado = 'pendiente';

-- El índice que hoy no existe en ninguna de las cinco tablas, y por el que
-- las diez consultas de vigencias.js hacen secuencial.
create index if not exists vigencias_por_fecha
  on public.vigencias (fecha_documento)
  where fecha_documento is not null;

create index if not exists vigencias_por_entidad
  on public.vigencias (entidad_tipo, entidad_id);


-- ── 4 · Cuándo vence de verdad ─────────────────────────────────────────────
--
-- La regla vive en el catálogo, no en los datos ni en el navegador. Hoy
-- js/vigencias.js le suma un año al examen médico en JavaScript; mañana eso
-- se lee de aquí y cambiarlo es un UPDATE a una fila.

create or replace function public.vigencia_vence_el(
  p_tipo text, p_fecha date
) returns date
language sql stable
security definer set search_path to 'public', 'pg_temp' as $$
  select case
    when p_fecha is null then null
    when (c.meta->>'vigencia_meses') is null then p_fecha
    else p_fecha + make_interval(months => (c.meta->>'vigencia_meses')::int)
  end::date
  from public.catalogos c
  where c.clave = 'vigencia_tipo' and c.valor = p_tipo;
$$;

revoke all on function public.vigencia_vence_el(text, date) from public, anon;
grant execute on function public.vigencia_vence_el(text, date) to authenticated;


-- ── 5 · RLS, con la lección de H-02 puesta desde el primer día ─────────────
--
-- H-02 se cerró haciendo que SOLO el superadmin escriba una fecha de
-- vigencia, porque RLS deja a la empresa actualizar su propia fila y ocultar
-- el campo en la interfaz no protege nada. Una tabla nueva nace sin esa
-- protección: si se creara «y ya luego le ponemos el guard», quedaría abierta
-- justo lo que H-02 cerró, y esta vez sin que nadie estuviera mirando.
--
-- Por eso el guard entra en la MISMA migración que la tabla.

alter table public.vigencias enable row level security;

-- Quién es el dueño de la entidad a la que cuelga la fila.
create or replace function public.vigencia_propietario(p_tipo text, p_id text)
returns uuid
language plpgsql stable
security definer set search_path to 'public', 'pg_temp' as $$
declare v uuid;
begin
  case p_tipo
    when 'perfil'   then select user_id        into v from public.perfiles   where user_id = p_id::uuid;
    when 'camion'   then select propietario_id into v from public.camiones   where id = p_id;
    when 'operador' then select propietario_id into v from public.operadores where id = p_id;
    when 'custodio' then select propietario_id into v from public.custodios  where id = p_id;
    when 'patio'    then select propietario_id into v from public.patios     where id = p_id;
    else v := null;
  end case;
  return v;
end $$;

revoke all on function public.vigencia_propietario(text, text) from public, anon;
grant execute on function public.vigencia_propietario(text, text) to authenticated;

-- Lee el dueño y el superadmin. No es público: una ruta de Storage y una
-- caducidad son datos de la empresa, no del catálogo.
drop policy if exists vigencias_lee_dueno_o_sa on public.vigencias;
create policy vigencias_lee_dueno_o_sa on public.vigencias
  for select to authenticated
  using (public.is_superadmin()
      or public.vigencia_propietario(entidad_tipo, entidad_id) = auth.uid());

-- La empresa PROPONE: solo filas suyas y solo en estado 'pendiente'.
drop policy if exists vigencias_propone_el_dueno on public.vigencias;
create policy vigencias_propone_el_dueno on public.vigencias
  for insert to authenticated
  with check (public.vigencia_propietario(entidad_tipo, entidad_id) = auth.uid()
              and estado = 'pendiente');

-- El superadmin hace el resto.
drop policy if exists vigencias_sa_todo on public.vigencias;
create policy vigencias_sa_todo on public.vigencias
  for all to authenticated
  using (public.is_superadmin()) with check (public.is_superadmin());

-- Y el guard, que es lo que de verdad frena: RLS decide SI puedes escribir la
-- fila; esto decide QUÉ puedes cambiar. Una empresa no puede acreditarse sola
-- —ni pasar su propia propuesta a 'vigente', ni tocar la fecha de una ya
-- acreditada— aunque llegue por el API y no por la pantalla.
create or replace function public.guard_vigencia_update()
returns trigger language plpgsql
security definer set search_path to 'public', 'pg_temp' as $$
begin
  if public.is_superadmin() then return new; end if;

  if old.estado = 'vigente' then
    raise exception 'VIGENCIA_ACREDITADA: solo el superadmin puede modificar un documento ya acreditado';
  end if;
  if new.estado is distinct from old.estado then
    raise exception 'VIGENCIA_SIN_AUTOACREDITAR: solo el superadmin cambia el estado de un documento';
  end if;
  if new.revisado_por is distinct from old.revisado_por
     or new.revisado_en is distinct from old.revisado_en then
    raise exception 'VIGENCIA_SIN_AUTOREVISAR: la revisión la firma el superadmin';
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_vigencia_update on public.vigencias;
create trigger trg_guard_vigencia_update
  before update on public.vigencias
  for each row execute function public.guard_vigencia_update();

-- Permisos de tabla: el modelo de Supabase es rol uniforme + RLS como
-- frontera (§5 de la auditoría). anon no entra.
revoke all on table public.vigencias from anon, public;
grant select, insert, update, delete on table public.vigencias to authenticated;

-- service_role como en las otras 24 tablas. La primera versión de esta
-- migración se lo dejó sin nada, y la paridad lo cazó: habría sido la ÚNICA
-- tabla del esquema donde la clave de servicio no puede leer. Hoy no rompe
-- nada porque ninguna Edge Function la toca; el día que una la toque falla
-- sin motivo aparente. Salirse del patrón tiene que ser una decisión, y aquí
-- no lo era.
grant all on table public.vigencias to service_role;

-- ── Y las dos funciones de TRIGGER, que es H-21 otra vez ───────────────────
--
-- H-21 retiró EXECUTE de las funciones que devuelven `trigger`, con un bucle
-- sobre pg_proc. Pero fue una BARRIDA DE UNA SOLA VEZ: no cubre las que se
-- creen después, y estas dos nacieron con EXECUTE para anon, authenticated y
-- service_role. Lo cazó la paridad, no una revisión.
--
-- No es explotable —una función que devuelve trigger no se puede invocar por
-- REST, PostgreSQL responde «can only be called as trigger»— y retirarlo no
-- impide que el trigger dispare, porque eso no depende de EXECUTE. Se retira
-- por lo mismo que H-21: es un permiso que nadie necesita y que obliga a
-- razonar sobre por qué está ahí cada vez que alguien audita los grants.
--
-- `public` va en la lista A PROPÓSITO: quitarlo solo de anon y authenticated
-- no retira nada, porque PostgreSQL concede a PUBLIC por omisión. Esa fue
-- exactamente la primera pasada fallida de H-21.
revoke all on function public.vigencias_tipo_coincide()  from public, anon, authenticated;
revoke all on function public.guard_vigencia_update()    from public, anon, authenticated;


-- ── 6 · Comprobación ───────────────────────────────────────────────────────
-- Si algo de lo de arriba no quedó, la migración falla en vez de mentir.

do $$
declare v_falta text;
begin
  if to_regclass('public.vigencias') is null then
    raise exception 'H-04: no se creó public.vigencias';
  end if;

  select string_agg(c, ', ') into v_falta from (
    select c from unnest(array['vigencias_entidad_tipo_check','vigencias_estado_check',
                               'vigencias_algo_que_guardar','vigencias_rechazo_con_motivo',
                               'vigencias_tipo_del_catalogo']) c
     where not exists (select 1 from pg_constraint
                        where conrelid = 'public.vigencias'::regclass and conname = c)) s;
  if v_falta is not null then raise exception 'H-04: faltan restricciones: %', v_falta; end if;

  if not exists (select 1 from pg_class where relname = 'vigencias_uno_vigente')
  or not exists (select 1 from pg_class where relname = 'vigencias_uno_pendiente') then
    raise exception 'H-04: faltan los índices parciales de vigente/pendiente';
  end if;

  if not (select relrowsecurity from pg_class where oid = 'public.vigencias'::regclass) then
    raise exception 'H-04: la tabla quedó SIN RLS';
  end if;

  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.vigencias'::regclass
                    and tgname = 'trg_guard_vigencia_update') then
    raise exception 'H-04: falta el guard. Sin él esta tabla reabre H-02.';
  end if;

  if has_table_privilege('anon', 'public.vigencias', 'SELECT') then
    raise exception 'H-04: anon puede leer vigencias';
  end if;

  if not has_table_privilege('service_role', 'public.vigencias', 'SELECT') then
    raise exception 'H-04: service_role se quedó sin privilegios sobre vigencias, a diferencia de las otras 24 tablas';
  end if;

  -- H-21: ninguna función de trigger debe conservar EXECUTE. Se comprueba
  -- contra los tres roles MÁS public, que es lo que la primera pasada de
  -- H-21 se dejó.
  select string_agg(f, ', ') into v_falta from (
    select f from unnest(array['public.vigencias_tipo_coincide()',
                               'public.guard_vigencia_update()']) f
     where has_function_privilege('anon',          f, 'EXECUTE')
        or has_function_privilege('authenticated', f, 'EXECUTE')) s;
  if v_falta is not null then
    raise exception 'H-04/H-21: estas funciones de trigger conservan EXECUTE: %', v_falta;
  end if;

  if (select count(*) from public.catalogos where clave = 'vigencia_tipo') <> 17 then
    raise exception 'H-04: el catálogo no tiene los 17 tipos (tiene %)',
      (select count(*) from public.catalogos where clave = 'vigencia_tipo');
  end if;

  raise notice 'H-04 etapa 1: tabla, catálogo de 17 tipos, RLS y guard en su sitio.';
  raise notice 'H-04 etapa 1: nadie la lee todavía. Ninguna pantalla cambia.';
end $$;
