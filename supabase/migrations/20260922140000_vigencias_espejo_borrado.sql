-- ============================================================================
-- H-04 · Etapa 3c — El espejo también tiene que enterarse de los borrados
-- ============================================================================
--
-- ── El hueco ──────────────────────────────────────────────────────────────
--
-- La Etapa 3 colgó el espejo de `after insert or update`. Falta `delete`, y
-- las cinco tablas de origen se borran de verdad desde el cliente:
--
--   js/admin.js:840       eliminarUnidad()      → delete from camiones
--   js/admin.js:668       eliminarMiRecurso()   → delete from <tabla>
--   js/admin.js:1249      → custodios      js/admin.js:1400 → patios
--   js/operadores.js:500  → operadores
--   perfiles              → en cascada al borrar el usuario de auth
--                           (gestionar-usuario, acción `eliminar`)
--
-- `vigencias.entidad_id` es `text` y polimórfico: apunta a cinco tablas con
-- PK distinta, así que NO puede tener clave foránea y NO hay `on delete
-- cascade` que lo salve. Verificado en la Etapa 1: las únicas FK de la tabla
-- son a `auth.users` (subido_por / revisado_por) y al catálogo.
--
-- Resultado hoy: se borra un camión y sus filas de `vigencias` se quedan ahí
-- para siempre, apuntando a una unidad que ya no existe. Mientras nadie lea
-- la tabla no se nota — y en la Etapa 4, cuando las pantallas de vigencias
-- lean de aquí, esos fantasmas aparecerían como documentos por vencer de
-- unidades fantasma.
--
-- Por qué no se detectó antes: la sonda 14 SÍ los cazaría (los cuenta como
-- «filas de más»), pero solo después de que alguien borre algo. Nadie ha
-- borrado nada desde que se aplicó la Etapa 2, así que la sonda sale limpia
-- y el hueco sigue ahí. Un verde no es una prueba de que el caso se cubrió;
-- es una prueba de que el caso no ha ocurrido.
--
-- ── Qué hace este fichero ─────────────────────────────────────────────────
--
-- 1. `vigencias_espejo()` aprende `TG_OP = 'DELETE'`: lee OLD en vez de NEW y
--    borra las filas de esa entidad — **de cualquier estado**, no solo las
--    que el mapeo escribe. Un `rechazado` de la Etapa 4 cuya unidad se borró
--    es igual de fantasma que un `vigente`.
-- 2. Los cinco triggers pasan a `after insert or update or delete`, con
--    `create or replace trigger` (PG 14+) para no tirar nada por el camino.
-- 3. Limpia los fantasmas que ya hubiera — que a día de hoy deberían ser
--    cero, y el bloque de comprobación dice cuántos encontró.
--
-- Sigue siendo TOLERANTE (Etapa 3b): si el borrado del espejo falla, avisa y
-- deja que el borrado de origen siga. Nadie debe quedarse sin poder borrar su
-- camión por una tabla que todavía no se lee.
--
-- ============================================================================

create or replace function public.vigencias_espejo()
returns trigger language plpgsql
security definer set search_path to 'public', 'pg_temp' as $$
declare
  j        jsonb;
  m        record;
  v_ent    text;
  v_id     text;
  v_arch   text;
  v_fecha  date;
begin
  -- En DELETE no hay NEW. El resto del cuerpo trabaja sobre `j`, así que es
  -- lo único que cambia de raíz entre los tres eventos.
  if tg_op = 'DELETE' then j := to_jsonb(old); else j := to_jsonb(new); end if;

  for m in
    select * from (values
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
    -- Cada documento va en su propio bloque: así un tipo que falle no se
    -- lleva por delante a los otros cinco de la misma unidad, ni a la
    -- escritura de origen.
    begin
      v_ent   := m.entidad;
      v_id    := case when m.tabla = 'perfiles' then j->>'user_id' else j->>'id' end;
      v_arch  := case when m.col_arch is null then null else j->>(m.col_arch) end;
      v_fecha := nullif(j->>(m.col_fecha), '')::date;

      if tg_op = 'DELETE' then
        -- La entidad ya no existe: nada suyo debe sobrevivir en el espejo.
        -- Sin filtro de estado a propósito — un 'rechazado' huérfano es tan
        -- fantasma como un 'vigente'.
        delete from public.vigencias
         where entidad_tipo = v_ent and entidad_id = v_id
           and tipo_documento = m.tipo;

      elsif v_arch is null and v_fecha is null then
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

    exception when others then
      -- Tolerante: la escritura de origen sigue su camino. La divergencia la
      -- caza la sonda del espejo, que compara las dos fuentes. Lo que NO se
      -- hace es tragarse el error sin dejar rastro: va al log del servidor
      -- con la entidad y el documento concretos.
      raise warning 'H-04 espejo (%): no se pudo reflejar %/% de %: % (la escritura de origen continua)',
        tg_op, m.entidad, m.tipo, coalesce(v_id, '?'), sqlerrm;
    end;
  end loop;

  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;

revoke all on function public.vigencias_espejo() from public, anon, authenticated;


-- ── Los cinco triggers, ahora con DELETE ──────────────────────────────────
-- `create or replace trigger` (PG 14+) en vez de drop + create: no deja a la
-- tabla ni un instante sin espejo, y no borra nada.

create or replace trigger trg_vigencias_espejo
  after insert or update or delete on public.perfiles
  for each row execute function public.vigencias_espejo();

create or replace trigger trg_vigencias_espejo
  after insert or update or delete on public.camiones
  for each row execute function public.vigencias_espejo();

create or replace trigger trg_vigencias_espejo
  after insert or update or delete on public.operadores
  for each row execute function public.vigencias_espejo();

create or replace trigger trg_vigencias_espejo
  after insert or update or delete on public.custodios
  for each row execute function public.vigencias_espejo();

create or replace trigger trg_vigencias_espejo
  after insert or update or delete on public.patios
  for each row execute function public.vigencias_espejo();


-- ── Barrido de los fantasmas que ya hubiera ───────────────────────────────
-- Filas del espejo cuya entidad de origen ya no existe. Hoy deberían ser
-- cero; el NOTICE dice cuántas fueron, y si no es cero eso es el dato.

do $$
declare v_n int;
begin
  with huerfanas as (
    select v.id from public.vigencias v
     where (v.entidad_tipo = 'perfil'   and not exists (select 1 from public.perfiles   p where p.user_id::text = v.entidad_id))
        or (v.entidad_tipo = 'camion'   and not exists (select 1 from public.camiones   c where c.id          = v.entidad_id))
        or (v.entidad_tipo = 'operador' and not exists (select 1 from public.operadores o where o.id          = v.entidad_id))
        or (v.entidad_tipo = 'custodio' and not exists (select 1 from public.custodios  u where u.id          = v.entidad_id))
        or (v.entidad_tipo = 'patio'    and not exists (select 1 from public.patios     t where t.id          = v.entidad_id))
  )
  delete from public.vigencias v using huerfanas h where v.id = h.id;
  get diagnostics v_n = row_count;
  raise notice 'H-04 etapa 3c: fantasmas barridos: %', v_n;
end $$;


-- ── Comprobación ───────────────────────────────────────────────────────────

do $$
declare v_n int; v_h int;
begin
  -- tgtype bit 3 (valor 8) = DELETE. Los cinco triggers tienen que tenerlo.
  select count(*) into v_n
    from pg_trigger
   where tgname = 'trg_vigencias_espejo'
     and not tgisinternal
     and (tgtype & 8) = 8;
  if v_n <> 5 then
    raise exception 'H-04 etapa 3c: solo % de 5 triggers del espejo escuchan DELETE. Borrar una unidad dejaria fantasmas en vigencias.', v_n;
  end if;

  -- Y que no hayan perdido INSERT (4) ni UPDATE (16) por el camino.
  select count(*) into v_n
    from pg_trigger
   where tgname = 'trg_vigencias_espejo'
     and not tgisinternal
     and (tgtype & 4) = 4 and (tgtype & 16) = 16;
  if v_n <> 5 then
    raise exception 'H-04 etapa 3c: % de 5 triggers conservan INSERT y UPDATE. El reemplazo se comio un evento.', v_n;
  end if;

  select count(*) into v_n from pg_proc
   where proname = 'vigencias_espejo'
     and prosrc like '%exception when others then%';
  if v_n <> 1 then
    raise exception 'H-04 etapa 3c: el espejo dejo de ser tolerante.';
  end if;

  select count(*) into v_n from pg_proc
   where proname = 'vigencias_espejo' and prosrc like '%to_jsonb(old)%';
  if v_n <> 1 then
    raise exception 'H-04 etapa 3c: la funcion no lee OLD; en DELETE no tendria de donde sacar la entidad.';
  end if;

  if has_function_privilege('anon', 'public.vigencias_espejo()', 'EXECUTE')
  or has_function_privilege('authenticated', 'public.vigencias_espejo()', 'EXECUTE') then
    raise exception 'H-04/H-21: vigencias_espejo() conserva EXECUTE';
  end if;

  select count(*) into v_h from public.vigencias v
   where (v.entidad_tipo = 'perfil'   and not exists (select 1 from public.perfiles   p where p.user_id::text = v.entidad_id))
      or (v.entidad_tipo = 'camion'   and not exists (select 1 from public.camiones   c where c.id          = v.entidad_id))
      or (v.entidad_tipo = 'operador' and not exists (select 1 from public.operadores o where o.id          = v.entidad_id))
      or (v.entidad_tipo = 'custodio' and not exists (select 1 from public.custodios  u where u.id          = v.entidad_id))
      or (v.entidad_tipo = 'patio'    and not exists (select 1 from public.patios     t where t.id          = v.entidad_id));
  if v_h <> 0 then
    raise exception 'H-04 etapa 3c: quedan % filas de vigencias sin entidad de origen.', v_h;
  end if;

  raise notice 'H-04 etapa 3c: los 5 triggers escuchan INSERT, UPDATE y DELETE. Sin huerfanas.';
  raise notice 'H-04 etapa 3c: RECORDATORIO - la Etapa 4 sigue teniendo que devolver el espejo a estricto.';
end $$;
