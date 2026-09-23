-- ============================================================================
-- H-04 · Etapa 4, primer fichero — catalogo.js (0 líneas tocadas) + estricto
-- ============================================================================
--
-- ── Por qué catalogo.js no cambia ────────────────────────────────────────
--
-- Las 11 apariciones que contó el plan (docs/PLAN-H04-VIGENCIAS.md) no leen
-- `perfiles` directo: pasan por la vista `empresas_publico`
-- (20260831210000_perfiles_ficha_publica.sql), que ya bloquea a `anon` y solo
-- expone lo público de la empresa. «Cambiar la lectura» aquí es repuntar la
-- vista, no tocar el JS — catalogo.js sigue pidiendo las mismas tres columnas
-- por su mismo nombre y recibe exactamente la misma forma de dato.
--
-- Las tres fechas (`fecha_vencimiento_permiso_sct/seguro_rc/seguro_carga`)
-- pasan de leer la columna de `perfiles` a leer la fila `vigente` de
-- `vigencias` para ese perfil. Todo lo demás de la vista queda igual.
--
-- El número de permiso (`permiso_sct`, texto) NO se toca: ese campo nunca
-- entró al espejo (solo se refleja `doc_permiso_sct` + su fecha), sigue
-- siendo de `perfiles`.
--
-- ── Por qué el espejo vuelve a estricto en esta misma migración ─────────
--
-- Las etapas 3b y 3c dejaron la advertencia escrita en su propio SQL: mientras
-- nadie leyera `vigencias`, un espejo que fallaba en silencio solo dejaba una
-- divergencia que la sonda 14 cazaba tarde o temprano. A partir de esta
-- migración el catálogo público SÍ depende de `vigencias` para decidir si una
-- empresa se ve "Docs al día". Un espejo tolerante que fallara callado dejaría
-- de ser una divergencia anotada: sería un distintivo mal mostrado a
-- cualquier cliente que abra el catálogo, sin que nadie se entere.
--
-- El cambio es quitar el `exception when others` de cada bloque del mapeo:
-- si un documento no se puede reflejar, la transacción de origen (guardar el
-- camión, aprobar el perfil, etc.) falla entera, como antes de la Etapa 3b.
-- Nada más de la función cambia — mismo mapeo, mismos cinco triggers, mismo
-- tratamiento de DELETE de la Etapa 3c.
--
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1 · El espejo, sin la red de seguridad de 3b/3c
-- ─────────────────────────────────────────────────────────────────────────

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
    -- Sin bloque exception: si un documento falla, toda la transacción de
    -- origen falla con él. A partir de aquí una pantalla pública depende de
    -- lo que este trigger escriba, así que un fallo callado ya no es
    -- aceptable (ver cabecera). Comprobado ruidosamente a propósito: un
    -- espejo roto ahora tumba el guardado, exactamente como antes de 3b.
    v_ent   := m.entidad;
    v_id    := case when m.tabla = 'perfiles' then j->>'user_id' else j->>'id' end;
    v_arch  := case when m.col_arch is null then null else j->>(m.col_arch) end;
    v_fecha := nullif(j->>(m.col_fecha), '')::date;

    if tg_op = 'DELETE' then
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
  end loop;

  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;

revoke all on function public.vigencias_espejo() from public, anon, authenticated;

comment on function public.vigencias_espejo() is
  'H-04 Etapa 4: ESTRICTO. Un documento que no se pueda reflejar tumba la transaccion de origen entera — dejo de ser tolerante en la Etapa 3b/3c porque catalogo.js ya lee de vigencias via empresas_publico. No tocar sin releer docs/PLAN-H04-VIGENCIAS.md.';

-- Los cinco triggers no cambian de forma (siguen en insert/update/delete),
-- solo la función que ejecutan. `create or replace trigger` de todos modos,
-- por si alguna vez alguno quedó apuntando a otra función.

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


-- ─────────────────────────────────────────────────────────────────────────
-- 2 · empresas_publico: las tres fechas pasan a leer vigencias
-- ─────────────────────────────────────────────────────────────────────────
-- Mismas columnas, mismo orden, mismo nombre — catalogo.js no se entera.
-- Cada fecha sale de la fila 'vigente' de vigencias para ese perfil y ese
-- tipo de documento; sin fila vigente, NULL — igual que hoy con la columna
-- de perfiles cuando nunca se acreditó.

create or replace view public.empresas_publico as
  select p.user_id,
         p.nombre,
         p.razon_social,
         p.rfc,
         p.descripcion,
         p.telefono,
         p.anos_operacion,
         p.num_unidades,
         p.seguro_rc,
         p.seguro_carga,
         p.permiso_sct,
         p.verificado,
         v_sct.fecha_documento   as fecha_vencimiento_permiso_sct,
         v_rc.fecha_documento    as fecha_vencimiento_seguro_rc,
         v_carga.fecha_documento as fecha_vencimiento_seguro_carga
    from public.perfiles p
    left join public.vigencias v_sct
      on v_sct.entidad_tipo = 'perfil' and v_sct.entidad_id = p.user_id::text
     and v_sct.tipo_documento = 'permiso_sct' and v_sct.estado = 'vigente'
    left join public.vigencias v_rc
      on v_rc.entidad_tipo = 'perfil' and v_rc.entidad_id = p.user_id::text
     and v_rc.tipo_documento = 'seguro_rc' and v_rc.estado = 'vigente'
    left join public.vigencias v_carga
      on v_carga.entidad_tipo = 'perfil' and v_carga.entidad_id = p.user_id::text
     and v_carga.tipo_documento = 'seguro_carga' and v_carga.estado = 'vigente'
   where p.rol = 'admin';

comment on view public.empresas_publico is
  'Ficha publica del transportista. H-04 Etapa 4: las tres fechas de vigencia ya no leen perfiles, leen la fila vigente de vigencias. Solo filas rol=admin. Ver H-01.';

revoke all on public.empresas_publico from anon, public;
grant select on public.empresas_publico to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 3 · Comprobación
-- ─────────────────────────────────────────────────────────────────────────

do $$
declare
  v_n         int;
  v_cols      text;
  v_divergen  int;
begin
  -- El espejo ya no atrapa nada.
  select count(*) into v_n from pg_proc
   where proname = 'vigencias_espejo' and prosrc like '%exception when others%';
  if v_n <> 0 then
    raise exception 'H-04 etapa 4: vigencias_espejo() sigue siendo tolerante — el exception handler no se quito.';
  end if;

  -- Los cinco triggers siguen enteros (insert+update+delete).
  select count(*) into v_n
    from pg_trigger
   where tgname = 'trg_vigencias_espejo' and not tgisinternal
     and (tgtype & 4) = 4 and (tgtype & 16) = 16 and (tgtype & 8) = 8;
  if v_n <> 5 then
    raise exception 'H-04 etapa 4: solo % de 5 triggers conservan insert+update+delete tras el cambio de funcion.', v_n;
  end if;

  -- La vista sigue exponiendo exactamente las mismas columnas, en el mismo
  -- orden -- si esto cambiara, cualquier .select('col,col,...') de un JS que
  -- no se toco en este commit dejaria de pedir lo que existe.
  select string_agg(column_name, ',' order by ordinal_position) into v_cols
    from information_schema.columns
   where table_schema = 'public' and table_name = 'empresas_publico';
  if v_cols is distinct from 'user_id,nombre,razon_social,rfc,descripcion,telefono,anos_operacion,num_unidades,seguro_rc,seguro_carga,permiso_sct,verificado,fecha_vencimiento_permiso_sct,fecha_vencimiento_seguro_rc,fecha_vencimiento_seguro_carga' then
    raise exception 'H-04 etapa 4: empresas_publico cambio su forma de columnas: %', v_cols;
  end if;

  -- Y por si la doble escritura hubiera divergido en algun perfil sin que la
  -- sonda 14 se hubiera corrido despues: la vista tiene que decir hoy lo
  -- mismo que decia perfiles ayer, o el catalogo cambiaria de golpe.
  select count(*) into v_divergen
    from public.perfiles p
    join public.empresas_publico e on e.user_id = p.user_id
   where p.rol = 'admin'
     and (p.fecha_vencimiento_permiso_sct  is distinct from e.fecha_vencimiento_permiso_sct
       or p.fecha_vencimiento_seguro_rc    is distinct from e.fecha_vencimiento_seguro_rc
       or p.fecha_vencimiento_seguro_carga is distinct from e.fecha_vencimiento_seguro_carga);
  if v_divergen > 0 then
    raise exception 'H-04 etapa 4: % perfil(es) verian una fecha distinta en el catalogo tras el corte a vigencias. Correr 14-sonda-espejo-vigencias.mjs antes de reintentar.', v_divergen;
  end if;

  raise notice 'H-04 etapa 4: catalogo.js migrado (via empresas_publico), espejo ESTRICTO. % perfiles comprobados sin divergencia.', (select count(*) from public.perfiles where rol = 'admin');
end $$;
