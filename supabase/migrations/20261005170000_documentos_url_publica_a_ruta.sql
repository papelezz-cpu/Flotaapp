-- ════════════════════════════════════════════════════════════════════════
-- S-01 paso 2, etapa B · Las URL públicas guardadas pasan a ser rutas
-- ════════════════════════════════════════════════════════════════════════
--
-- Contexto (docs/AUDITORIA.md, S-01). Los buckets `operadores`,
-- `documentos-empresa` y `custodios` son públicos, y sus columnas guardaban
-- la URL pública: quien la tuviera abría el documento —examen toxicológico,
-- antecedentes, pólizas— sin sesión. El plan en tres etapas:
--   A. la web abre siempre con URL firmada y guarda rutas
--      (utils.js v10 y siguientes; en producción desde el 05/10, 671f132);
--   B. ESTA: convertir las URL ya guardadas en rutas;
--   C. volver privados los tres buckets.
-- La web de la etapa A acepta las dos formas, así que B no rompe nada en
-- pantalla; es requisito de C, porque una URL pública deja de servir en un
-- bucket privado y la ruta es lo que se firma.
--
-- Qué convierte: toda columna que guarda un documento de esos buckets:
--   operadores:  foto_operador, foto_licencia, doc_examen_medico,
--                doc_examen_toxicologico, doc_carta_antecedentes,
--                doc_licencia_peligrosa                       (bucket operadores)
--   perfiles:    doc_permiso_sct, doc_seguro_rc, doc_seguro_carga y sus
--                tres *_pendiente                     (bucket documentos-empresa)
--   custodios:   doc_licencia_sedena                           (bucket custodios)
-- Medido en el volcado del 28/09: 15 URL en operadores y 12 en su espejo
-- vigencias.archivo_path; 0 en perfiles y custodios. Se cubren todas por si
-- producción tiene alguna más desde entonces.
--
-- `vigencias.archivo_path` no se toca a mano: vigencias_espejo() lo reescribe
-- al cambiar la columna de origen. Lo que quedara después (una fila que no
-- correspondiera a su origen) sí se convierte directamente, y se cuenta.
--
-- Por qué en contexto de superadmin: las rutas de los documentos acreditados
-- de empresa solo las cambia el superadmin (S-12), y el espejo choca con
-- guard_vigencia_update sobre filas vigentes de perfil si no lo es. Dentro de
-- esta transacción se fijan los claims de un superadmin real; nada sale de
-- ella.
--
-- No borra nada. Es reversible: la ruta es la URL sin el prefijo
-- `<proyecto>/storage/v1/object/public/<bucket>/`. Una URL con caracteres
-- codificados (%xx) o parámetros (?…) no se toca y aborta: no hay ninguna en
-- los datos medidos, y si apareciera se decide aparte.
--
-- Reglas de docs/AUDITORIA.md §4: 2, 44, 44b.
-- ════════════════════════════════════════════════════════════════════════

create temporary table s01b_antes on commit drop as
  select 'operadores'::text t, count(*) filter (where concat_ws(' ', foto_operador, foto_licencia, doc_examen_medico,
           doc_examen_toxicologico, doc_carta_antecedentes, doc_licencia_peligrosa) like '%/object/public/%') n
    from public.operadores
  union all
  select 'perfiles', count(*) filter (where concat_ws(' ', doc_permiso_sct, doc_seguro_rc, doc_seguro_carga,
           doc_permiso_sct_pendiente, doc_seguro_rc_pendiente, doc_seguro_carga_pendiente) like '%/object/public/%')
    from public.perfiles
  union all
  select 'custodios', count(*) filter (where doc_licencia_sedena like '%/object/public/%') from public.custodios
  union all
  select 'vigencias', count(*) filter (where archivo_path like '%/object/public/%') from public.vigencias;

do $$
declare
  v_sa    uuid;
  v_raras int;
begin
  -- URL que esta migración no sabe convertir sin decidir: codificadas o con parámetros.
  select count(*) into v_raras from (
    select unnest(array[foto_operador, foto_licencia, doc_examen_medico, doc_examen_toxicologico,
                        doc_carta_antecedentes, doc_licencia_peligrosa]) v from public.operadores
    union all select unnest(array[doc_permiso_sct, doc_seguro_rc, doc_seguro_carga, doc_permiso_sct_pendiente,
                        doc_seguro_rc_pendiente, doc_seguro_carga_pendiente]) from public.perfiles
    union all select doc_licencia_sedena from public.custodios
    union all select archivo_path from public.vigencias) x
   where v like '%/object/public/%' and (v like '%\%%' escape '\' or v like '%?%');
  if v_raras > 0 then
    raise exception 'S-01 B: hay % URL con caracteres codificados o parámetros. No se convierte nada: revisarlas antes.', v_raras;
  end if;

  select user_id into v_sa from public.perfiles where rol = 'superadmin' order by created_at limit 1;
  if v_sa is null then
    raise exception 'S-01 B: hace falta un superadmin para hacer la conversión.';
  end if;
  perform set_config('request.jwt.claim.sub', v_sa::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);

  update public.operadores set
    foto_operador           = regexp_replace(foto_operador,           '^.*/storage/v1/object/public/operadores/', ''),
    foto_licencia           = regexp_replace(foto_licencia,           '^.*/storage/v1/object/public/operadores/', ''),
    doc_examen_medico       = regexp_replace(doc_examen_medico,       '^.*/storage/v1/object/public/operadores/', ''),
    doc_examen_toxicologico = regexp_replace(doc_examen_toxicologico, '^.*/storage/v1/object/public/operadores/', ''),
    doc_carta_antecedentes  = regexp_replace(doc_carta_antecedentes,  '^.*/storage/v1/object/public/operadores/', ''),
    doc_licencia_peligrosa  = regexp_replace(doc_licencia_peligrosa,  '^.*/storage/v1/object/public/operadores/', '')
   where concat_ws(' ', foto_operador, foto_licencia, doc_examen_medico, doc_examen_toxicologico,
                   doc_carta_antecedentes, doc_licencia_peligrosa) like '%/object/public/operadores/%';

  update public.perfiles set
    doc_permiso_sct            = regexp_replace(doc_permiso_sct,            '^.*/storage/v1/object/public/documentos-empresa/', ''),
    doc_seguro_rc              = regexp_replace(doc_seguro_rc,              '^.*/storage/v1/object/public/documentos-empresa/', ''),
    doc_seguro_carga           = regexp_replace(doc_seguro_carga,           '^.*/storage/v1/object/public/documentos-empresa/', ''),
    doc_permiso_sct_pendiente  = regexp_replace(doc_permiso_sct_pendiente,  '^.*/storage/v1/object/public/documentos-empresa/', ''),
    doc_seguro_rc_pendiente    = regexp_replace(doc_seguro_rc_pendiente,    '^.*/storage/v1/object/public/documentos-empresa/', ''),
    doc_seguro_carga_pendiente = regexp_replace(doc_seguro_carga_pendiente, '^.*/storage/v1/object/public/documentos-empresa/', '')
   where concat_ws(' ', doc_permiso_sct, doc_seguro_rc, doc_seguro_carga, doc_permiso_sct_pendiente,
                   doc_seguro_rc_pendiente, doc_seguro_carga_pendiente) like '%/object/public/documentos-empresa/%';

  update public.custodios set
    doc_licencia_sedena = regexp_replace(doc_licencia_sedena, '^.*/storage/v1/object/public/custodios/', '')
   where doc_licencia_sedena like '%/object/public/custodios/%';

  -- Lo que el espejo no haya reescrito (filas de vigencias sin correspondencia
  -- con su origen): se quita el prefijo, sea del bucket que sea.
  update public.vigencias set
    archivo_path = regexp_replace(archivo_path, '^.*/storage/v1/object/public/[a-z-]+/', '')
   where archivo_path like '%/object/public/%';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end $$;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--   · no queda ninguna URL pública en las columnas convertidas ni en
--     vigencias.archivo_path;
--   · ninguna de esas columnas quedó con una URL de otro tipo (http…);
--   · y, como aviso (no falla): cuántas rutas de operadores no tienen su
--     archivo en storage.objects — una ruta sin archivo ya era una URL rota
--     antes de convertirla; la conversión no la empeora, pero se dice.
-- Como sabe fallar: sin los UPDATE, quedan URL públicas.

do $$
declare
  v_quedan  int;
  v_http    int;
  v_huerf   int;
  v_resumen text;
begin
  select count(*) into v_quedan from (
    select unnest(array[foto_operador, foto_licencia, doc_examen_medico, doc_examen_toxicologico,
                        doc_carta_antecedentes, doc_licencia_peligrosa]) v from public.operadores
    union all select unnest(array[doc_permiso_sct, doc_seguro_rc, doc_seguro_carga, doc_permiso_sct_pendiente,
                        doc_seguro_rc_pendiente, doc_seguro_carga_pendiente]) from public.perfiles
    union all select doc_licencia_sedena from public.custodios
    union all select archivo_path from public.vigencias) x
   where v like '%/object/public/%';
  if v_quedan > 0 then
    raise exception 'S-01 B: quedan % URL públicas sin convertir.', v_quedan;
  end if;

  select count(*) into v_http from (
    select unnest(array[foto_operador, foto_licencia, doc_examen_medico, doc_examen_toxicologico,
                        doc_carta_antecedentes, doc_licencia_peligrosa]) v from public.operadores
    union all select unnest(array[doc_permiso_sct, doc_seguro_rc, doc_seguro_carga, doc_permiso_sct_pendiente,
                        doc_seguro_rc_pendiente, doc_seguro_carga_pendiente]) from public.perfiles
    union all select doc_licencia_sedena from public.custodios) x
   where v ~* '^https?://';
  if v_http > 0 then
    raise exception 'S-01 B: % documentos siguen siendo una URL (no de Storage público): revisarlos.', v_http;
  end if;

  select count(*) into v_huerf from (
    select unnest(array[foto_operador, foto_licencia, doc_examen_medico, doc_examen_toxicologico,
                        doc_carta_antecedentes, doc_licencia_peligrosa]) v from public.operadores) x
   where v is not null
     and not exists (select 1 from storage.objects o where o.bucket_id = 'operadores' and o.name = x.v);

  select string_agg(t || ' ' || n, ', ') into v_resumen from s01b_antes;

  raise notice 'S-01 B: URL públicas convertidas a rutas (filas con URL antes: %). Rutas de operadores sin archivo en Storage: %.', v_resumen, v_huerf;
end $$;
