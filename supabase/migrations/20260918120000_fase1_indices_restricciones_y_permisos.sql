-- ============================================================================
-- Fase 1 de la auditoria: lo que no puede romper nada
-- ============================================================================
--
-- Cinco hallazgos que comparten una propiedad: ninguno cambia el comportamiento
-- de una sola pantalla. Son indices, restricciones que los datos ya cumplen,
-- permisos que nadie usa y comentarios.
--
--   H-12  dos indices para los trabajos de cron
--   H-13  ocho indices de clave foranea
--   H-14  CHECK de coherencia en num_contenedores
--   H-18  CHECK en perfiles.aprobacion_cuenta
--   H-15  COMMENT en las columnas sin uso — NINGUN DROP
--   H-21  retirar EXECUTE de las funciones de trigger
--
-- Todo medido contra produccion el 2026-09-18, no contra el volcado del 14:
-- las ocho FK siguen sin indice, los dos de cron tampoco existen, ningun CHECK
-- esta puesto, y CERO filas romperian los que se anaden.
--
-- ── Sin CONCURRENTLY, a proposito ─────────────────────────────────────────
--
-- La tabla mas grande son las notificaciones, con menos de mil filas: cada
-- indice se construye en milisegundos. CONCURRENTLY obligaria a aplicar el
-- archivo FUERA de transaccion, y si algo fallara a mitad la base quedaria a
-- medias. Se prefiere la atomicidad. Lo dice el propio aplicar-a-pruebas.sh
-- cuando detecta la palabra.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. H-12 · los dos cron recorren tablas enteras
-- ─────────────────────────────────────────────────────────────────────────
-- expire-stale-offers corre cada hora; portgo-sincronizar-estados cada 15
-- minutos y hace cinco UPDATE. Las condiciones son literales de cada funcion,
-- y los parciales se mantienen diminutos porque excluyen las filas ya cerradas.

create index if not exists idx_ofertas_por_vencer
  on public.ofertas (expira_en)
  where estado in ('enviada', 'contra_oferta');

create index if not exists idx_pedidos_acordados_fin
  on public.pedidos (fecha_fin)
  where estado = 'acordado';

comment on index public.idx_ofertas_por_vencer is
  'Para expire_stale_offers(), que corre cada hora. Parcial: las ofertas cerradas no se vuelven a mirar.';
comment on index public.idx_pedidos_acordados_fin is
  'Para la regla (d) de sincronizar_estados_pedidos(), que corre cada 15 minutos.';


-- ─────────────────────────────────────────────────────────────────────────
-- 2. H-13 · ocho claves foraneas sin indice
-- ─────────────────────────────────────────────────────────────────────────
-- PostgreSQL no indexa el lado hijo de una FK. Al borrar la fila padre tiene
-- que comprobar cada hijo, y sin indice eso es un recorrido completo de la
-- tabla hija por cada fila borrada.
--
-- Estas ocho son las que atraviesa el flujo de borrado de cuenta
-- (20260827190000) y la via ARCO de cancelacion, que tiene plazo legal.
--
-- Parciales porque estas columnas son mayoritariamente nulas: el indice ocupa
-- una fraccion y el coste de escritura es despreciable fuera de su condicion.
--
-- NO se indexa toda columna que aparezca en un WHERE. Estas ocho tienen un
-- motivo concreto, y emitido_por ademas filtra una politica RLS de lectura
-- (admin_ve_sus_docs), asi que se justifica dos veces.

create index if not exists idx_calificaciones_cliente
  on public.calificaciones (cliente_id) where cliente_id is not null;

create index if not exists idx_pedidos_oferta_pendiente
  on public.pedidos (oferta_pendiente_id) where oferta_pendiente_id is not null;

create index if not exists idx_docfiscales_emitido_por
  on public.documentos_fiscales (emitido_por) where emitido_por is not null;

create index if not exists idx_docfiscales_cancelado_por
  on public.documentos_fiscales (cancelado_por) where cancelado_por is not null;

create index if not exists idx_pagos_registrado_por
  on public.pagos (registrado_por) where registrado_por is not null;

create index if not exists idx_arco_atendida_por
  on public.solicitudes_arco (atendida_por) where atendida_por is not null;

create index if not exists idx_expedientes_incidente_por
  on public.expedientes (incidente_reportado_por) where incidente_reportado_por is not null;

create index if not exists idx_historico_archivado_por
  on public.reservaciones_historico (archivado_por) where archivado_por is not null;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. H-14 y H-18 · restricciones de coherencia
-- ─────────────────────────────────────────────────────────────────────────
-- NOT VALID: no recorre las filas existentes ni bloquea la tabla. Las nuevas y
-- las modificadas si se comprueban desde el primer momento.
--
-- Se validan al final, en el bloque 6, porque medido hoy CERO filas las
-- incumplen y con estos volumenes la validacion es instantanea. Si algun dia
-- hubiera datos sucios, ese VALIDATE es lo unico que habria que aplazar.

-- El grupo repetitivo contenedor_1/_2 pone el techo en 2, pero nada impedia que
-- num_contenedores dijera 3. No se normaliza a tabla hija: anadiria un JOIN a
-- la consulta mas caliente para modelar un maximo de dos.
alter table public.pedidos
  drop constraint if exists pedidos_num_contenedores_check;
alter table public.pedidos
  add constraint pedidos_num_contenedores_check
  check (num_contenedores is null or num_contenedores between 0 and 2) not valid;

alter table public.plantillas_pedido
  drop constraint if exists plantillas_num_contenedores_check;
alter table public.plantillas_pedido
  add constraint plantillas_num_contenedores_check
  check (num_contenedores is null or num_contenedores between 0 and 2) not valid;

-- aprobacion_cuenta admitia cualquier texto, siendo la unica columna de estado
-- del esquema sin CHECK. Es el hueco conocido nº 2 del flujo operativo.
-- NULL es "cuenta activa" y se conserva como valor valido.
alter table public.perfiles
  drop constraint if exists perfiles_aprobacion_cuenta_check;
alter table public.perfiles
  add constraint perfiles_aprobacion_cuenta_check
  check (aprobacion_cuenta is null
      or aprobacion_cuenta in ('pendiente', 'rechazada', 'suspendida')) not valid;


-- ─────────────────────────────────────────────────────────────────────────
-- 4. H-15 · las columnas sin uso se DOCUMENTAN, no se borran
-- ─────────────────────────────────────────────────────────────────────────
-- ⚠ NO HAY NINGUN DROP AQUI, y es deliberado. No cuestan rendimiento —un NULL
--   ocupa un bit en el mapa— y borrarlas descartaria el diseno de Carta Porte
--   que alguien ya penso. Se documentan para que la pregunta quede contestada
--   en el sitio donde se hace.
--
-- Medido el 2026-09-18 contra produccion: las seis de reservaciones y telefono
-- siguen con CERO valores.

comment on column public.reservaciones.peso_kg               is 'Carta Porte (SAT) — sin implementar. Cero referencias en el codigo y cero filas con valor (18/09/2026).';
comment on column public.reservaciones.descripcion_mercancia is 'Carta Porte (SAT) — sin implementar. Cero referencias en el codigo y cero filas con valor (18/09/2026).';
comment on column public.reservaciones.clave_sat_mercancia   is 'Carta Porte (SAT) — sin implementar. Cero referencias en el codigo y cero filas con valor (18/09/2026).';
comment on column public.reservaciones.unidad_medida_sat     is 'Carta Porte (SAT) — sin implementar. Cero referencias en el codigo y cero filas con valor (18/09/2026).';
comment on column public.reservaciones.num_piezas            is 'Carta Porte (SAT) — sin implementar. Cero referencias en el codigo y cero filas con valor (18/09/2026).';
comment on column public.reservaciones.num_pedido_factura    is 'Carta Porte (SAT) — sin implementar. Cero referencias en el codigo y cero filas con valor (18/09/2026).';

comment on column public.reservaciones.telefono is
  'Duplica perfiles.telefono. La interfaz la lee pero nada la escribe: cero filas con valor (18/09/2026). Pendiente de decidir si se rellena al cerrar el acuerdo o se retira de la interfaz.';

-- CORRECCION al informe del 14/09, que decia "sin uso y NULL en las 11 filas".
-- La primera mitad es cierta; la segunda no. Medido el 18/09: SEIS camiones
-- tienen valor ("Menos de 1 hora", "Mismo dia", "1-2 horas"...), todos creados
-- entre abril y junio. La escribio una version anterior de la app; el codigo de
-- hoy ni la lee ni la escribe. La medicion original estaba mal.
comment on column public.camiones.tiempo_respuesta is
  'Heredada de una version anterior: 6 camiones creados entre abril y junio de 2026 tienen valor, y el codigo actual ni la lee ni la escribe. No confundir con "vacia": tiene datos, no tiene uso.';


-- ─────────────────────────────────────────────────────────────────────────
-- 5. H-21 · las funciones de trigger no necesitan EXECUTE
-- ─────────────────────────────────────────────────────────────────────────
-- No es explotable: una funcion que devuelve trigger no se puede invocar fuera
-- de un trigger —PostgreSQL responde "can only be called as trigger"— y el
-- permiso EXECUTE no es lo que permite al trigger dispararse.
--
-- Se retira por el mismo motivo que 20260911150000 retiro un TRUNCATE que
-- tampoco era explotable: "es un permiso que nadie necesita, y dejarlo obliga a
-- razonar sobre por que esta ahi cada vez que alguien audita los grants".
--
-- Se le pregunta al catalogo en vez de enumerar a mano. Idempotente, y sirve de
-- red para las funciones de trigger que se creen despues.

do $$
declare
  r    record;
  v_n  int := 0;
begin
  for r in
    select p.oid::regprocedure::text as fn
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prorettype = 'trigger'::regtype
       and (has_function_privilege('anon',          p.oid, 'EXECUTE')
         or has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     order by 1
  loop
    -- PUBLIC va en la lista, y es lo que de verdad importa: PostgreSQL concede
    -- EXECUTE a PUBLIC por defecto en TODA funcion nueva, asi que anon y
    -- authenticated lo heredan aunque no tengan concesion directa. Revocar solo
    -- a los dos roles no quita nada — comprobado: el bloque 6 lo cazo y se nego
    -- a dar la migracion por buena.
    execute format('revoke all on function %s from public, anon, authenticated', r.fn);
    v_n := v_n + 1;
  end loop;
  raise notice 'H-21: EXECUTE retirado de % funcion(es) de trigger.', v_n;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 6. Validar las restricciones y comprobar
-- ─────────────────────────────────────────────────────────────────────────

alter table public.pedidos           validate constraint pedidos_num_contenedores_check;
alter table public.plantillas_pedido validate constraint plantillas_num_contenedores_check;
alter table public.perfiles          validate constraint perfiles_aprobacion_cuenta_check;

do $$
declare
  v_falta   text;
  v_quedan  text;
  v_novalid text;
begin
  -- Los diez indices
  select string_agg(i, ', ') into v_falta
    from unnest(array[
      'idx_ofertas_por_vencer','idx_pedidos_acordados_fin',
      'idx_calificaciones_cliente','idx_pedidos_oferta_pendiente',
      'idx_docfiscales_emitido_por','idx_docfiscales_cancelado_por',
      'idx_pagos_registrado_por','idx_arco_atendida_por',
      'idx_expedientes_incidente_por','idx_historico_archivado_por']) i
   where to_regclass('public.'||i) is null;
  if v_falta is not null then
    raise exception 'Fase 1: faltan indices: %', v_falta;
  end if;

  -- Las tres restricciones, y VALIDADAS: una NOT VALID que se quedo a medias
  -- no protege de los datos que ya estaban.
  select string_agg(conname, ', ') into v_novalid
    from pg_constraint
   where conname in ('pedidos_num_contenedores_check',
                     'plantillas_num_contenedores_check',
                     'perfiles_aprobacion_cuenta_check')
     and not convalidated;
  if v_novalid is not null then
    raise exception 'Fase 1: restricciones sin validar: %', v_novalid;
  end if;

  if (select count(*) from pg_constraint
       where conname in ('pedidos_num_contenedores_check',
                         'plantillas_num_contenedores_check',
                         'perfiles_aprobacion_cuenta_check')) <> 3 then
    raise exception 'Fase 1: no estan las tres restricciones.';
  end if;

  -- Ninguna funcion de trigger con EXECUTE
  select string_agg(p.oid::regprocedure::text, ', ') into v_quedan
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prorettype = 'trigger'::regtype
     and (has_function_privilege('anon', p.oid, 'EXECUTE')
       or has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  if v_quedan is not null then
    raise exception 'Fase 1: funciones de trigger con EXECUTE: %', v_quedan;
  end if;

  raise notice 'Fase 1: 10 indices, 3 restricciones validadas, 8 columnas documentadas, 0 DROP.';
end $$;
