-- ============================================================================
-- H-04 · Etapa 3b — El espejo deja de tumbar la escritura de origen
-- ============================================================================
--
-- ── Qué cambia y por qué ──────────────────────────────────────────────────
--
-- La Etapa 3 dejó el espejo en «todo o nada»: es un trigger AFTER dentro de la
-- misma transacción, así que si el espejo falla, la escritura de origen falla
-- con él. Se eligió así pensando en la integridad — «nunca una fuente sin su
-- espejo».
--
-- Medido en banco local el 2026-09-22, rompiendo el espejo a propósito
-- (retirando del catálogo el tipo que usa) y guardando un camión:
--
--   La escritura de origen FALLO por culpa del espejo: VIGENCIA_TIPO_AJENO
--
-- **Ese precio lo paga la operación, no la integridad.** Mientras nadie lea
-- `vigencias` —y hasta la Etapa 4 nadie la lee— un fallo del espejo no le
-- quita un dato a ninguna pantalla, pero sí le impide a una empresa guardar su
-- camión. Un tipo de catálogo que falte, un dato con una forma no prevista, y
-- alguien ve un error al guardar por una tabla que todavía no sirve para nada.
--
-- Así que durante la doble escritura el espejo pasa a ser TOLERANTE: si falla,
-- avisa y deja pasar la escritura de origen. La divergencia no queda oculta —
-- `pruebas/14-sonda-espejo-vigencias.mjs` compara las dos fuentes y la caza.
-- Ese es el trato: se cambia «romper la operación» por «divergir y que una
-- sonda lo diga».
--
-- ⚠ **La Etapa 4 tiene que devolverlo a estricto.** Cuando las lecturas se
-- muevan a `vigencias`, una fuente sin espejo deja de ser una divergencia
-- anotada y pasa a ser un dato que falta en pantalla. Está escrito aquí y en
-- docs/PLAN-H04-VIGENCIAS.md para que no se quede tolerante por olvido.
--
-- ── Por qué es un fichero aparte y no una corrección del anterior ──────────
--
-- Porque no es un arreglo de algo roto: la Etapa 3 hacía lo que decía. Es una
-- decisión distinta, tomada después de medir el precio. Editar aquel fichero
-- borraría que se aplicó estricto primero, y eso es justo lo que hay que
-- poder leer dentro de un año.
--
-- ============================================================================

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

      if v_arch is null and v_fecha is null then
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
      raise warning 'H-04 espejo: no se pudo reflejar %/% de %: % (la escritura de origen continúa)',
        m.entidad, m.tipo, coalesce(v_id, '?'), sqlerrm;
    end;
  end loop;

  return new;
end $$;

revoke all on function public.vigencias_espejo() from public, anon, authenticated;


-- ── Comprobación ───────────────────────────────────────────────────────────

do $$
declare v_n int;
begin
  select count(*) into v_n from pg_proc
   where proname = 'vigencias_espejo'
     and prosrc like '%exception when others then%';
  if v_n <> 1 then
    raise exception 'H-04 etapa 3b: el espejo NO quedó tolerante. Un fallo suyo seguiría tumbando la escritura de origen.';
  end if;

  if has_function_privilege('anon', 'public.vigencias_espejo()', 'EXECUTE')
  or has_function_privilege('authenticated', 'public.vigencias_espejo()', 'EXECUTE') then
    raise exception 'H-04/H-21: vigencias_espejo() conserva EXECUTE';
  end if;

  raise notice 'H-04 etapa 3b: el espejo es tolerante. Si falla, avisa y deja pasar la escritura.';
  raise notice 'H-04 etapa 3b: RECORDATORIO — la Etapa 4 tiene que devolverlo a estricto.';
end $$;
