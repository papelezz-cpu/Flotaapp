-- ============================================================================
-- Auditoria, lote de esquema: valida lo que nunca se reviso, indexa las FK
-- que se recorren al borrar una cuenta, y cierra tres huecos de unicidad
-- ============================================================================
--
-- Recoge los hallazgos de la auditoria que son SOLO ESQUEMA: ninguna linea de
-- js/ cambia con esto. H-06, H-08, H-09, H-14, H-15 y H-20.
--
-- ── Por que sin CONCURRENTLY ──────────────────────────────────────────────
--
-- supabase/aplicar-a-pruebas.sh corre psql con --single-transaction, y
-- CREATE INDEX CONCURRENTLY no puede ejecutarse dentro de un bloque de
-- transaccion: Postgres lo rechaza con
--
--     ERROR: CREATE INDEX CONCURRENTLY cannot run inside a transaction block
--
-- y con --single-transaction eso tumba el archivo entero. La migracion
-- 20260901150000 usa CONCURRENTLY y por eso no se puede aplicar con el guion
-- del proyecto; hubo que aplicarla a mano.
--
-- Aqui se usa CREATE INDEX a secas a proposito. La tabla mas grande es
-- notificaciones con 866 filas y la que mas indices recibe, reservaciones,
-- tiene 20: construir cualquiera de estos indices toma milisegundos y el
-- bloqueo ACCESS EXCLUSIVE dura menos que la latencia de red. CONCURRENTLY
-- existe para tablas donde ese bloqueo se nota; aqui solo compraria la
-- incompatibilidad con el guion.
--
-- Si algun dia estas tablas crecen y hay que reindexar en caliente, entonces
-- si toca CONCURRENTLY, y entonces toca aplicarlo fuera del guion.
--
-- ── Comprobado antes de escribir esto, contra portgo-pruebas ──────────────
--
--   · 20 reservaciones, 0 con estado fuera del CHECK, 0 con recurso_tipo
--     fuera del CHECK  -> los dos VALIDATE pasan
--   · 0 NULL en las cinco columnas que pasan a NOT NULL
--   · 3 operadores, 0 duplicados en (propietario_id, curp) y en
--     (propietario_id, num_trabajador)
--   · 11 camiones, 9 con placa, 8 placas distintas -> HAY UN DUPLICADO.
--     Ver el bloque 5: esa restriccion queda fuera.
--
-- ⚠ El sello de paridad es del 2026-09-01 y hoy es el 2026-09-08: tiene una
--   semana. Las comprobaciones de arriba se hicieron leyendo portgo-pruebas
--   directamente, no confiando en el sello. Antes de aplicar esto en serio,
--   volver a replicar (Regla #3) y repetirlas.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. H-14 · validar los dos CHECK que nunca miraron el historico
-- ─────────────────────────────────────────────────────────────────────────
-- Se anadieron como NOT VALID, asi que vigilan lo que entra pero nunca
-- revisaron lo que ya estaba, y Postgres tampoco puede apoyarse en ellos
-- para razonar sobre la tabla. VALIDATE toma un bloqueo SHARE UPDATE
-- EXCLUSIVE: no impide leer ni escribir.
--
-- Si alguna fila historica los violara, esto falla en seco y revierte todo
-- el archivo. Es el comportamiento correcto: mejor enterarse aqui.

alter table public.reservaciones validate constraint reservaciones_estado_check;
alter table public.reservaciones validate constraint reservaciones_recurso_tipo_check;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. H-20 · columnas con DEFAULT que nunca deberian aceptar NULL
-- ─────────────────────────────────────────────────────────────────────────
-- Las cinco tienen valor por defecto y nadie las inserta en NULL, pero hay
-- logica que depende de que no lo sean y hoy nada lo garantiza:
--
--   · created_at de pedidos es la clave de la paginacion keyset. Un NULL la
--     rompe en silencio: la fila no aparece ni en una pagina ni en otra.
--   · created_at de reservaciones es lo mismo desde 20260901150000.
--   · notificaciones.leido lo filtra la purga mensual (leido = true). Un
--     NULL no entra ni en true ni en false: la fila no se purgaria nunca.
--
-- En PG 17 SET NOT NULL no reescribe la tabla, solo la recorre para
-- verificar.

alter table public.reservaciones  alter column estado     set not null;
alter table public.reservaciones  alter column created_at set not null;
alter table public.pedidos        alter column created_at set not null;
alter table public.notificaciones alter column created_at set not null;
alter table public.notificaciones alter column leido      set not null;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. H-08 · las FK que se recorren al borrar una cuenta
-- ─────────────────────────────────────────────────────────────────────────
-- PostgreSQL indexa la clave PRIMARIA automaticamente, nunca la FORANEA del
-- lado hijo. Cada vez que se borra la fila padre, el motor comprueba los
-- hijos; sin indice eso es un recorrido secuencial de la tabla hija entera,
-- uno por cada FK.
--
-- Importa porque el borrado de cuenta EXISTE (gestionar-usuario, accion
-- eliminar) y es ademas la via con la que se atiende una solicitud ARCO de
-- cancelacion. Hoy son microsegundos; con 100.000 reservaciones es un
-- recorrido completo por cada FK, sosteniendo bloqueos mientras dura.
--
-- La auditoria conto 14 FK sin indice. Aqui van SEIS, no las catorce: las
-- otras ocho estan sobre tablas vacias o que no crecen, y anadir un indice
-- que nadie va a usar tambien cuesta (espacio, y trabajo en cada escritura).
-- El criterio es: la tabla hija crece sin techo Y el padre se borra de
-- verdad.
--
-- Los tres primeros van parciales: la inmensa mayoria de las filas tiene
-- NULL en esas columnas —solo se llenan cuando alguien cancela o paga— y un
-- indice parcial se salta esas filas por completo.

create index if not exists idx_reservaciones_pagado_por
  on public.reservaciones (pagado_por) where pagado_por is not null;

create index if not exists idx_reservaciones_canc_solicitada_por
  on public.reservaciones (cancelacion_solicitada_por) where cancelacion_solicitada_por is not null;

create index if not exists idx_reservaciones_canc_resuelta_por
  on public.reservaciones (cancelacion_resuelta_por) where cancelacion_resuelta_por is not null;

-- mensajes crece con el cliente movil y su FK es ON DELETE CASCADE: al
-- borrar un usuario hay que encontrar y borrar todos sus mensajes.
create index if not exists idx_mensajes_de_user
  on public.mensajes (de_user_id);

-- pagos y documentos_fiscales estan vacias hoy, pero su FK apunta a
-- reservaciones, que si crece, y ambas se consultan siempre por reservacion.
create index if not exists idx_pagos_reservacion
  on public.pagos (reservacion_id);

create index if not exists idx_docfiscales_reservacion
  on public.documentos_fiscales (reservacion_id);


-- ─────────────────────────────────────────────────────────────────────────
-- 4. H-09 · el indice de pedidos no cubria el desempate de su paginacion
-- ─────────────────────────────────────────────────────────────────────────
-- js/pedidos.js:212-214 ordena por (created_at DESC, id DESC), pero
-- idx_pedidos_fecha (20260826120000) es solo (created_at DESC). Las filas
-- que empatan en fecha hay que ordenarlas aparte por id.
--
-- Es el mismo arreglo que 20260901150000 le hizo a reservaciones.
--
-- NO se retira idx_pedidos_fecha aqui. En teoria el compuesto lo hace
-- redundante, pero eso es una prediccion: sin haber leido
-- pg_stat_user_indexes no hay dato de uso, y retirar un indice porque
-- "deberia" sobrar es exactamente el cambio teorico que la auditoria
-- desaconseja. Se retira cuando se vea que el nuevo recibe los escaneos.

create index if not exists idx_pedidos_fecha_id
  on public.pedidos (created_at desc, id desc);


-- ─────────────────────────────────────────────────────────────────────────
-- 5. H-15 · unicidad en claves de negocio
-- ─────────────────────────────────────────────────────────────────────────
-- js/operadores.js:9-17 calcula num_trabajador en el NAVEGADOR: lee todos
-- los de la empresa, saca el maximo y le suma uno. Dos altas simultaneas de
-- la misma empresa leen el mismo maximo y generan el mismo numero, y hoy
-- nada lo impide: la base lo acepta sin decir nada.
--
-- El indice unico no arregla la carrera —para eso hay que mover el calculo
-- a la base o reintentar— pero convierte un fallo SILENCIOSO en un error
-- visible, que ya es un salto grande.
--
-- Van por (propietario_id, curp) y no por curp a secas a proposito: un mismo
-- chofer puede estar dado de alta por dos transportistas distintos, y eso es
-- legitimo. Lo que no es legitimo es que aparezca dos veces en la MISMA
-- empresa.

create unique index if not exists uq_operadores_num_trabajador
  on public.operadores (propietario_id, num_trabajador)
  where num_trabajador is not null;

create unique index if not exists uq_operadores_curp
  on public.operadores (propietario_id, curp)
  where curp is not null;

-- ⚠ camiones.placas SE QUEDA FUERA, y no por precaucion: HAY UN DUPLICADO
--   REAL EN PRODUCCION.
--
--   Medido sobre el volcado del 2026-08-31 y confirmado en portgo-pruebas:
--   11 camiones, 9 con placa, 8 placas distintas. Las unidades T-001 y
--   R-8C5DEE8E comparten placa, y las DOS estan en aprobacion = 'aprobada'.
--   Son ademas de tipo distinto (un Torton y un Rabon), asi que no es una
--   fila duplicada: son dos vehiculos distintos con la misma placa
--   registrada. Uno de los dos la tiene mal.
--
--   Crear el indice unico hoy FALLA en seco y tumba este archivo entero.
--
--   Cual de las dos placas es la correcta no se puede deducir desde aqui:
--   es una pregunta para el dueno de la flota. Cuando este resuelto, la
--   restriccion es esta y aplica sin mas:
--
-- create unique index if not exists uq_camiones_placas
--   on public.camiones (placas) where placas is not null;
--
--   (La auditoria decia que esta restriccion aplicaba limpia. Era un error
--   de medicion: se leyo el volcado separando por espacios en vez de por
--   tabuladores, y el campo que salia no era el de la placa.)


-- ─────────────────────────────────────────────────────────────────────────
-- 6. H-06 · dejar constancia de las columnas que no usa nadie
-- ─────────────────────────────────────────────────────────────────────────
-- Ocho columnas sin una sola referencia en js/, android/, las Edge Functions
-- ni las migraciones: aparecen unicamente en su propia definicion. No se
-- retira ninguna aqui —eso es destructivo y necesita una decision— pero si
-- se anota, para que quien lea el esquema no tenga que investigarlo otra vez.
--
-- Las seis de reservaciones son un conjunto coherente: son los campos de
-- Carta Porte. Encajan con documentos_fiscales y pagos, que existen, tienen
-- sus CHECK bien puestos y cero filas. Es funcionalidad preparada y no
-- construida, no un descuido. La decision pendiente es de producto: si Carta
-- Porte sigue en el plan se quedan; si no, se retiran con esas dos tablas.

comment on column public.reservaciones.peso_kg is
  'SIN USO. Campo de Carta Porte, funcionalidad no construida. 0 filas con valor, 0 referencias en el proyecto.';
comment on column public.reservaciones.descripcion_mercancia is
  'SIN USO. Campo de Carta Porte, funcionalidad no construida. 0 filas con valor, 0 referencias en el proyecto.';
comment on column public.reservaciones.clave_sat_mercancia is
  'SIN USO. Campo de Carta Porte, funcionalidad no construida. 0 filas con valor, 0 referencias en el proyecto.';
comment on column public.reservaciones.unidad_medida_sat is
  'SIN USO. Campo de Carta Porte, funcionalidad no construida. 0 filas con valor, 0 referencias en el proyecto.';
comment on column public.reservaciones.num_piezas is
  'SIN USO. Campo de Carta Porte, funcionalidad no construida. 0 filas con valor, 0 referencias en el proyecto.';
comment on column public.reservaciones.num_pedido_factura is
  'SIN USO. Campo de Carta Porte, funcionalidad no construida. 0 filas con valor, 0 referencias en el proyecto.';

-- Estas dos son distintas: nacieron duplicando datos que solicitudes_cuenta
-- ya captura y llena, y nunca se poblaron.
comment on column public.perfiles.regimen_fiscal is
  'SIN USO. 0 filas con valor, 0 referencias en el proyecto. El dato vive en solicitudes_cuenta.';
comment on column public.perfiles.cp_fiscal is
  'SIN USO. 0 filas con valor, 0 referencias en el proyecto. El dato vive en solicitudes_cuenta.';
