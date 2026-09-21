-- ============================================================================
-- H-04 · Etapa 2 — Copiar lo que ya existe a `vigencias`
-- ============================================================================
--
-- La Etapa 1 creó la tabla y nadie la lee. Esta la llena con lo que hoy vive
-- repartido en 35 columnas de cinco tablas. **Sigue sin leerla nadie**: las
-- pantallas siguen consultando las columnas viejas, y esta migración no toca
-- ni una de ellas.
--
-- Medido el 2026-09-18 contra producción: unas 44 filas. El coste de H-04 no
-- está en los datos, está en las 168 apariciones de código de la Etapa 4.
--
-- ── Se puede correr varias veces ──────────────────────────────────────────
--
-- Es un plan por etapas y esto se va a re-correr: después de cada réplica de
-- producción a pruebas, por ejemplo, porque la réplica hace DROP SCHEMA y se
-- lleva la tabla por delante. Así que cada `insert` lleva su `on conflict`
-- contra el índice parcial que corresponde, y una segunda pasada no duplica
-- nada ni falla.
--
-- ── Lo que NO se copia, y por qué ─────────────────────────────────────────
--
-- `camiones.fecha_expedicion_tc` y `operadores.fecha_expedicion` guardan
-- EMISIÓN, no caducidad. Decisión del usuario del 2026-09-19: «solo nos
-- interesa la fecha en la que vence el documento; para la operación no es
-- relevante cuándo fue emitido». Se quedan en sus columnas, sus formularios
-- siguen leyéndolas, y no entran en este modelo ni en la retirada de la
-- Etapa 6. Ver docs/PLAN-H04-VIGENCIAS.md.
--
-- `camiones.imagen_caat` tampoco: el archivo del CAAT vive en `doc_caat`, que
-- es la que escribe admin.js. `imagen_caat` no aparece ni una vez en js/.
-- Pero no se da por supuesto — el bloque 3 cuenta si alguna fila tiene dato
-- ahí y no en `doc_caat`, y si lo hay, **la migración falla** en vez de
-- perderlo en silencio.
--
-- ── Sobre `subido_en` ─────────────────────────────────────────────────────
--
-- Queda con su valor por omisión, o sea el momento de la copia. **No es
-- cuándo se subió el papel**: las tablas de origen no lo guardan en ninguna
-- parte. Se podría haber usado el `created_at` del recurso, pero eso sería
-- una suposición presentada como dato — y es mejor un campo que dice «cuándo
-- llegó aquí» que uno que finge saber algo que nadie registró.
--
-- ============================================================================


-- ── 1 · Perfiles ───────────────────────────────────────────────────────────
--
-- Los tres documentos de empresa, en sus dos versiones: la acreditada
-- (`vigente`) y la que la empresa propuso y el superadmin no ha revisado
-- (`pendiente`). Esa distinción es la razón de que la Etapa 1 tenga dos
-- índices únicos parciales en vez de un UNIQUE — ver la segunda decisión.

insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, archivo_path, fecha_documento, estado)
select 'perfil', p.user_id::text, v.tipo, v.archivo, v.fecha, 'vigente'
  from public.perfiles p
  cross join lateral (values
    ('permiso_sct',  p.doc_permiso_sct,  p.fecha_vencimiento_permiso_sct),
    ('seguro_rc',    p.doc_seguro_rc,    p.fecha_vencimiento_seguro_rc),
    ('seguro_carga', p.doc_seguro_carga, p.fecha_vencimiento_seguro_carga)
  ) as v(tipo, archivo, fecha)
 where v.archivo is not null or v.fecha is not null
on conflict (entidad_tipo, entidad_id, tipo_documento) where estado = 'vigente' do nothing;

insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, archivo_path, fecha_documento, estado)
select 'perfil', p.user_id::text, v.tipo, v.archivo, v.fecha, 'pendiente'
  from public.perfiles p
  cross join lateral (values
    ('permiso_sct',  p.doc_permiso_sct_pendiente,  p.fecha_vencimiento_permiso_sct_pendiente),
    ('seguro_rc',    p.doc_seguro_rc_pendiente,    p.fecha_vencimiento_seguro_rc_pendiente),
    ('seguro_carga', p.doc_seguro_carga_pendiente, p.fecha_vencimiento_seguro_carga_pendiente)
  ) as v(tipo, archivo, fecha)
 where v.archivo is not null or v.fecha is not null
on conflict (entidad_tipo, entidad_id, tipo_documento) where estado = 'pendiente' do nothing;


-- ── 2 · Camiones ───────────────────────────────────────────────────────────
--
-- Seis documentos. Ojo con dos nombres que no siguen el patrón: el archivo de
-- la tarjeta de circulación es `imagen_tc` (no `doc_tc`), y la caducidad del
-- CAAT es `vigencia_caat` (no `fecha_vencimiento_caat`). Esas cinco
-- convenciones distintas para lo mismo son, literalmente, el hallazgo H-04.

insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, archivo_path, fecha_documento, estado)
select 'camion', c.id, v.tipo, v.archivo, v.fecha, 'vigente'
  from public.camiones c
  cross join lateral (values
    ('tarjeta_circulacion', c.imagen_tc,             c.fecha_vencimiento_tc),
    ('seguro_unidad',       c.doc_seguro,            c.fecha_vencimiento_seguro),
    ('permiso_sct_unidad',  c.doc_sct,               c.fecha_vencimiento_permiso_sct),
    ('verificacion',        c.doc_verificacion,      c.fecha_vencimiento_verificacion),
    ('permiso_peligrosa',   c.doc_permiso_peligrosa, c.fecha_vencimiento_permiso_peligrosa),
    ('caat',                c.doc_caat,              c.vigencia_caat)
  ) as v(tipo, archivo, fecha)
 where v.archivo is not null or v.fecha is not null
on conflict (entidad_tipo, entidad_id, tipo_documento) where estado = 'vigente' do nothing;


-- ── 3 · Operadores ─────────────────────────────────────────────────────────
--
-- Cinco documentos, y tres de ellos —los exámenes y la carta— guardan la
-- fecha en que se hicieron, no cuándo caducan. Se copian TAL CUAL: la
-- caducidad la calcula `vigencia_vence_el()` con los meses del catálogo. Ver
-- la sexta decisión del plan: calcularla aquí hornearía la regla en los datos.

insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, archivo_path, fecha_documento, estado)
select 'operador', o.id, v.tipo, v.archivo, v.fecha, 'vigente'
  from public.operadores o
  cross join lateral (values
    ('licencia',            o.foto_licencia,           o.fecha_vencimiento),
    ('licencia_peligrosa',  o.doc_licencia_peligrosa,  o.fecha_vencimiento_licencia_peligrosa),
    ('examen_medico',       o.doc_examen_medico,       o.fecha_examen_medico),
    ('examen_toxicologico', o.doc_examen_toxicologico, o.fecha_examen_toxicologico),
    ('carta_antecedentes',  o.doc_carta_antecedentes,  o.fecha_carta_antecedentes)
  ) as v(tipo, archivo, fecha)
 where v.archivo is not null or v.fecha is not null
on conflict (entidad_tipo, entidad_id, tipo_documento) where estado = 'vigente' do nothing;


-- ── 4 · Custodios y patios ─────────────────────────────────────────────────
--
-- Medido el 2026-09-18: cero filas con fecha en las dos tablas, y sus
-- pantallas están apagadas. Se copian igualmente porque el día que se
-- reactiven no habrá que acordarse de esto, y hoy no cuesta nada.
--
-- `certificacion` es el único tipo sin columna de archivo: solo existe la
-- fecha. Por eso la Etapa 1 permite `archivo_path` nulo.

insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, archivo_path, fecha_documento, estado)
select 'custodio', c.id, v.tipo, v.archivo, v.fecha, 'vigente'
  from public.custodios c
  cross join lateral (values
    ('certificacion',   null::text,            c.fecha_vencimiento_cert),
    ('licencia_sedena', c.doc_licencia_sedena, c.fecha_vencimiento_licencia_sedena)
  ) as v(tipo, archivo, fecha)
 where v.archivo is not null or v.fecha is not null
on conflict (entidad_tipo, entidad_id, tipo_documento) where estado = 'vigente' do nothing;

insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, archivo_path, fecha_documento, estado)
select 'patio', p.id, 'permiso_patio', p.doc_permiso, p.fecha_vencimiento_permiso, 'vigente'
  from public.patios p
 where p.doc_permiso is not null or p.fecha_vencimiento_permiso is not null
on conflict (entidad_tipo, entidad_id, tipo_documento) where estado = 'vigente' do nothing;


-- ── 5 · Comprobación: que no se haya quedado nada por el camino ────────────
--
-- Esta es la parte que importa. Una copia que pierde filas en silencio es
-- peor que no copiar: la Etapa 4 cambiaría las lecturas a una tabla
-- incompleta y el dato desaparecería de la pantalla sin un solo error.
--
-- Así que se cuenta el origen y el destino por separado y se exige que
-- cuadren. El origen se recuenta con las MISMAS expresiones de arriba, que no
-- es una comprobación independiente de verdad —comparte el mapeo— pero sí
-- caza lo que de verdad falla aquí: un `on conflict` que descarte de más, una
-- fila rechazada por un CHECK, un tipo mal escrito.

do $$
declare
  v_origen  bigint;
  v_destino bigint;
  v_huerfanas bigint;
  v_caat_perdido bigint;
begin
  -- Origen: cuántos pares (documento, fecha) con algo dentro hay en las cinco
  -- tablas, contando la pareja _pendiente de perfiles como fila aparte.
  select
      (select count(*) from public.perfiles p cross join lateral (values
         (p.doc_permiso_sct, p.fecha_vencimiento_permiso_sct),
         (p.doc_seguro_rc, p.fecha_vencimiento_seguro_rc),
         (p.doc_seguro_carga, p.fecha_vencimiento_seguro_carga)) v(a,f)
        where v.a is not null or v.f is not null)
    + (select count(*) from public.perfiles p cross join lateral (values
         (p.doc_permiso_sct_pendiente, p.fecha_vencimiento_permiso_sct_pendiente),
         (p.doc_seguro_rc_pendiente, p.fecha_vencimiento_seguro_rc_pendiente),
         (p.doc_seguro_carga_pendiente, p.fecha_vencimiento_seguro_carga_pendiente)) v(a,f)
        where v.a is not null or v.f is not null)
    + (select count(*) from public.camiones c cross join lateral (values
         (c.imagen_tc, c.fecha_vencimiento_tc),
         (c.doc_seguro, c.fecha_vencimiento_seguro),
         (c.doc_sct, c.fecha_vencimiento_permiso_sct),
         (c.doc_verificacion, c.fecha_vencimiento_verificacion),
         (c.doc_permiso_peligrosa, c.fecha_vencimiento_permiso_peligrosa),
         (c.doc_caat, c.vigencia_caat)) v(a,f)
        where v.a is not null or v.f is not null)
    + (select count(*) from public.operadores o cross join lateral (values
         (o.foto_licencia, o.fecha_vencimiento),
         (o.doc_licencia_peligrosa, o.fecha_vencimiento_licencia_peligrosa),
         (o.doc_examen_medico, o.fecha_examen_medico),
         (o.doc_examen_toxicologico, o.fecha_examen_toxicologico),
         (o.doc_carta_antecedentes, o.fecha_carta_antecedentes)) v(a,f)
        where v.a is not null or v.f is not null)
    + (select count(*) from public.custodios c cross join lateral (values
         (null::text, c.fecha_vencimiento_cert),
         (c.doc_licencia_sedena, c.fecha_vencimiento_licencia_sedena)) v(a,f)
        where v.a is not null or v.f is not null)
    + (select count(*) from public.patios p
        where p.doc_permiso is not null or p.fecha_vencimiento_permiso is not null)
  into v_origen;

  select count(*) into v_destino from public.vigencias;

  if v_destino <> v_origen then
    raise exception 'H-04 etapa 2: el origen tiene % pares con dato y vigencias tiene % filas. No cuadran: algo se perdió o se duplicó.',
      v_origen, v_destino;
  end if;

  -- Ninguna fila debe apuntar a una entidad que no existe. Si la hay, el
  -- mapeo de entidad_id está mal (por ejemplo un uuid contra una PK de texto).
  select count(*) into v_huerfanas
    from public.vigencias v
   where public.vigencia_propietario(v.entidad_tipo, v.entidad_id) is null;
  if v_huerfanas > 0 then
    raise exception 'H-04 etapa 2: % fila(s) de vigencias no resuelven propietario. El entidad_id no casa con su tabla.', v_huerfanas;
  end if;

  -- El CAAT: si alguna unidad tiene el archivo en imagen_caat y no en
  -- doc_caat, esta copia lo estaría tirando. Mejor parar que perderlo.
  select count(*) into v_caat_perdido
    from public.camiones
   where imagen_caat is not null and doc_caat is null;
  if v_caat_perdido > 0 then
    raise exception 'H-04 etapa 2: % camión(es) tienen CAAT en imagen_caat y no en doc_caat. Esta copia lo perdería.', v_caat_perdido;
  end if;

  raise notice 'H-04 etapa 2: % filas copiadas, que son todos los pares con dato del origen.', v_destino;
  raise notice 'H-04 etapa 2: las pantallas siguen leyendo las columnas viejas. Nada cambia todavía.';
end $$;
