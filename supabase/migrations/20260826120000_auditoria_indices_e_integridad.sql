-- ============================================================================
-- AUDITORÍA DE BASE DE DATOS — FASE 1 (sin riesgo) y FASE 3 (índices)
-- ============================================================================
-- Generada por la auditoría del 2026-08-26 sobre el volcado real de producción
-- (supabase/esquema/01-esquema-public.sql, proyecto xnyqsewaluezkkrlyhxg).
--
-- Cada índice de aquí está justificado por una consulta REAL del cliente o por
-- una política RLS / trigger que corre en el camino caliente. No se agrega
-- ningún índice "porque la columna aparece en un WHERE".
--
-- ORDEN DE APLICACIÓN (regla del proyecto): primero portgo-pruebas, se
-- verifica, y solo después producción.
--
-- Se usa CREATE INDEX CONCURRENTLY: no bloquea escrituras. Por eso NO debe
-- envolverse en una transacción. aplicar-migraciones.sh no lo hace, así que
-- este archivo se puede pasar tal cual:
--   psql "$CONN" -v ON_ERROR_STOP=1 -f <este archivo>
--
-- NADA en este archivo borra datos. Los DROP que propone la auditoría están
-- comentados al final y necesitan autorización explícita antes de ejecutarse.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. notificaciones — la consulta más caliente de toda la aplicación
-- ─────────────────────────────────────────────────────────────────────────
-- js/notificaciones.js:12  loadNotificaciones()
--   .eq('user_id', ...).order('created_at', desc).limit(20)
-- Corre al arrancar, en cada login y en CADA evento realtime de
-- notificaciones. Hoy la tabla no tiene ni un índice: es un seq scan + sort
-- completo cada vez. También sirve a la política RLS `ver_propias`.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_notificaciones_user_fecha
  ON public.notificaciones (user_id, created_at DESC);


-- ─────────────────────────────────────────────────────────────────────────
-- 2. ofertas — FK sin índice, caliente por tres rutas distintas
-- ─────────────────────────────────────────────────────────────────────────
-- (a) js/pedidos.js:229  .in('pedido_id', todosNuevosIds) en cada render de
--     la lista de solicitudes.
-- (b) política RLS `ped_select`: EXISTS (SELECT 1 FROM ofertas o WHERE
--     o.pedido_id = pedidos.id AND o.admin_id = auth.uid()), que se evalúa
--     por CADA fila de pedidos que se lea.
-- (c) puede_notificar(): JOIN ofertas x pedidos en cada INSERT de
--     notificaciones.
-- Postgres NO indexa las claves foráneas automáticamente.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ofertas_pedido
  ON public.ofertas (pedido_id);

-- js/views.js:146 para el badge, más el EXISTS de ped_select y el de
-- puede_notificar(). Seis filtros distintos por admin_id en el código.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ofertas_admin
  ON public.ofertas (admin_id);


-- ─────────────────────────────────────────────────────────────────────────
-- 3. reservaciones — sin ningún índice sobre lo que usa RLS
-- ─────────────────────────────────────────────────────────────────────────
-- La política `reservaciones_select` filtra por cliente_user_id /
-- propietario_id en CADA lectura, y ninguna de las dos está indexada. Los dos
-- índices parciales que ya existen (cancelación y cobro) no cubren esto.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reservaciones_cliente
  ON public.reservaciones (cliente_user_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reservaciones_propietario
  ON public.reservaciones (propietario_id);

-- FK que se usa al cancelar una reserva para reabrir el pedido
-- (js/reservaciones.js:783).
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reservaciones_pedido
  ON public.reservaciones (pedido_id);

-- Disponibilidad: lo consulta el trigger check_reservacion_disponibilidad()
-- en CADA INSERT y CADA UPDATE de reservaciones, y además js/modal.js:70,
-- js/detalle.js:28, js/camiones.js:80 y js/pedidos.js:2020.
-- Parcial a propósito: los estados vivos son una fracción pequeña de la tabla
-- y son los únicos que el trigger mira.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reservaciones_disponibilidad
  ON public.reservaciones (unidad, fecha_ini, fecha_fin)
  WHERE estado IN ('Pendiente', 'Activa');

-- Cola de cierres pendientes del superadmin (js/aprobaciones.js:85).
-- Parcial: 'PorAprobar' es un estado transitorio y raro. Un índice completo
-- sobre `estado` no serviría, porque 'Completada' acabará dominando la tabla.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reservaciones_por_aprobar
  ON public.reservaciones (completado_en)
  WHERE estado = 'PorAprobar';


-- ─────────────────────────────────────────────────────────────────────────
-- 4. pedidos — paginación por OFFSET sobre una columna sin índice
-- ─────────────────────────────────────────────────────────────────────────
-- js/pedidos.js:204  .order('created_at', desc).range(offset, offset+N)
-- Sin este índice cada página vuelve a escanear y ordenar la tabla entera.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_pedidos_fecha
  ON public.pedidos (created_at DESC);

-- FK + badge del cliente (js/views.js:135) + políticas ped_insert_own y
-- ped_update.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_pedidos_cliente
  ON public.pedidos (cliente_id);

-- Colas de revisión del superadmin: js/aprobaciones.js:75-76 y los dos
-- count(*) de js/views.js:212-213. Parcial porque ambos son estados raros.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_pedidos_cola_revision
  ON public.pedidos (estado, created_at)
  WHERE estado IN ('pendiente_revision', 'pendiente_acuerdo');

-- Tablero de la empresa: js/views.js:145 trae todos los pedidos abiertos.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_pedidos_abiertos
  ON public.pedidos (created_at DESC)
  WHERE estado = 'abierto';


-- ─────────────────────────────────────────────────────────────────────────
-- 5. perfiles — 22 consultas repetidas de eq('rol','superadmin')
-- ─────────────────────────────────────────────────────────────────────────
-- Hay 22 lugares en js/ que hacen SELECT user_id FROM perfiles WHERE
-- rol = 'superadmin' para poder insertar notificaciones. Hoy cada uno es un
-- seq scan de la tabla de usuarios.
-- Este índice es el parche de riesgo cero. El arreglo de fondo es usar la
-- función notificar_superadmins(), que YA existe en producción (ver FASE 2).
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_perfiles_superadmin
  ON public.perfiles (user_id)
  WHERE rol = 'superadmin';

-- Badges del superadmin: js/views.js:214-215.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_perfiles_cuenta_pendiente
  ON public.perfiles (user_id)
  WHERE aprobacion_cuenta = 'pendiente';

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_perfiles_docs_pendientes
  ON public.perfiles (user_id)
  WHERE perfil_docs_pendiente;


-- ─────────────────────────────────────────────────────────────────────────
-- 6. Tablas de flota — FK sin índice + cola de aprobación
-- ─────────────────────────────────────────────────────────────────────────
-- propietario_id: es FK, y es el filtro del tablero de la empresa en
-- js/admin.js.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_camiones_propietario   ON public.camiones   (propietario_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_custodios_propietario  ON public.custodios  (propietario_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_patios_propietario     ON public.patios     (propietario_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_lavados_propietario    ON public.lavados    (propietario_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_operadores_propietario ON public.operadores (propietario_id);

-- Cola de aprobación: los 5 count(*) en paralelo de js/views.js:207-211 y las
-- 5 consultas de js/aprobaciones.js:78-82. Parciales: 'pendiente' es la
-- minoría de las filas, que es justo cuando un índice parcial rinde.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_camiones_pendientes   ON public.camiones   (created_at DESC) WHERE aprobacion = 'pendiente';
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_custodios_pendientes  ON public.custodios  (created_at DESC) WHERE aprobacion = 'pendiente';
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_patios_pendientes     ON public.patios     (created_at DESC) WHERE aprobacion = 'pendiente';
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_lavados_pendientes    ON public.lavados    (id)              WHERE aprobacion = 'pendiente';
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_operadores_pendientes ON public.operadores (created_at)      WHERE aprobacion = 'pendiente';


-- ─────────────────────────────────────────────────────────────────────────
-- 7. Resto de FKs sin índice con uso real en el código
-- ─────────────────────────────────────────────────────────────────────────
-- js/catalogo.js y js/detalle.js piden la calificación de una empresa.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_calificaciones_admin
  ON public.calificaciones (admin_id, created_at DESC);

-- 7 lecturas por user_id en js/auth.js y js/aprobaciones.js.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_solicitudes_cuenta_user
  ON public.solicitudes_cuenta (user_id);


-- ─────────────────────────────────────────────────────────────────────────
-- 8. INTEGRIDAD — restricciones que hoy no existen
-- ─────────────────────────────────────────────────────────────────────────

-- 8.1 Una reservación solo puede calificarse una vez.
--     Hoy nada impide dos filas de calificación para la misma reservación:
--     reservaciones.calificado es solo una bandera que pone el cliente.
--     OJO: si ya hay duplicados, esto falla. Comprobar antes:
--       SELECT reservacion_id, count(*) FROM calificaciones
--        WHERE reservacion_id IS NOT NULL
--        GROUP BY 1 HAVING count(*) > 1;
--     Comprobado el 2026-08-26 en portgo-pruebas: 0 duplicados sobre 4
--     calificaciones. Falta comprobarlo en producción antes de promover.
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_calificaciones_reservacion
  ON public.calificaciones (reservacion_id)
  WHERE reservacion_id IS NOT NULL;

-- Postgres no admite ADD CONSTRAINT IF NOT EXISTS, y este archivo tiene que
-- poder reintentarse: si un CREATE INDEX CONCURRENTLY falla a mitad, se
-- corrige y se vuelve a pasar entero. Por eso cada restricción va dentro de
-- un guard que comprueba si ya está puesta.

-- 8.2 reservaciones.estado no tiene NINGÚN CHECK, a diferencia de
--     pedidos.estado. El código ya escribe un séptimo valor no documentado
--     ('Rechazada', js/reservaciones.js:467). Se añade NOT VALID para no
--     tocar las filas históricas: valida lo que entre de aquí en adelante.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'reservaciones_estado_check'
                    AND conrelid = 'public.reservaciones'::regclass) THEN
    ALTER TABLE public.reservaciones
      ADD CONSTRAINT reservaciones_estado_check
      CHECK (estado IN ('Pendiente','Activa','PorAprobar','CancelacionSolicitada',
                        'Completada','Cancelada','Rechazada'))
      NOT VALID;
  END IF;
END $$;

-- 8.3 recurso_tipo decide qué tabla resuelve `unidad` y qué secuencia de
--     tracking aplica. Un valor fuera de la lista rompe tracking_pasos().
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'reservaciones_recurso_tipo_check'
                    AND conrelid = 'public.reservaciones'::regclass) THEN
    ALTER TABLE public.reservaciones
      ADD CONSTRAINT reservaciones_recurso_tipo_check
      CHECK (recurso_tipo IN ('camion','custodio','patio','lavado'))
      NOT VALID;
  END IF;
END $$;

-- 8.4 Una reservación sin cliente_user_id o sin propietario_id es invisible
--     para RLS: nadie salvo el superadmin la vuelve a ver. NOT VALID por si
--     ya existen filas así; hay que revisarlas a mano antes de validar.
--     Comprobado el 2026-08-26 en portgo-pruebas: 0 filas con cualquiera de
--     las dos en nulo, sobre 20 reservaciones. Falta comprobarlo en
--     producción antes de promover.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'reservaciones_partes_presentes'
                    AND conrelid = 'public.reservaciones'::regclass) THEN
    ALTER TABLE public.reservaciones
      ADD CONSTRAINT reservaciones_partes_presentes
      CHECK (cliente_user_id IS NOT NULL AND propietario_id IS NOT NULL)
      NOT VALID;
  END IF;
END $$;

-- Para validar más adelante, cuando se hayan corregido las filas viejas:
--   ALTER TABLE public.reservaciones VALIDATE CONSTRAINT reservaciones_estado_check;
--   ALTER TABLE public.reservaciones VALIDATE CONSTRAINT reservaciones_recurso_tipo_check;
--   ALTER TABLE public.reservaciones VALIDATE CONSTRAINT reservaciones_partes_presentes;


-- ============================================================================
-- CAMBIOS DESTRUCTIVOS PROPUESTOS — NO SE EJECUTAN AQUÍ
-- ============================================================================
-- Quedan comentados a propósito. Necesitan un sí explícito antes de aplicarse
-- (regla #1 del proyecto). Ninguno borra datos de negocio, pero sí objetos.
--
-- D1. idx_expedientes_reserva es redundante: la restricción UNIQUE
--     (reserva_id, etapa) ya crea un índice cuya PRIMERA columna es
--     reserva_id, así que cubre exactamente las mismas búsquedas. Ocupa
--     espacio y encarece cada escritura sin dar nada a cambio.
--     Reversible con un CREATE INDEX.
--
--     DROP INDEX CONCURRENTLY public.idx_expedientes_reserva;
--
-- D2. idx_pedidos_categoria_carga no lo usa ninguna consulta:
--     `categoria_carga` aparece 7 veces en js/ y NINGUNA es un filtro, solo
--     lecturas del valor. Verificado con grep sobre todo js/.
--
--     DROP INDEX CONCURRENTLY public.idx_pedidos_categoria_carga;
--
-- D3. custodios, patios y lavados tienen DOS claves foráneas sobre la misma
--     columna propietario_id, con comportamientos de borrado CONTRADICTORIOS:
--       *_propietario_fk      -> perfiles(user_id)  ON DELETE SET NULL (NOT VALID)
--       *_propietario_id_fkey -> auth.users(id)     ON DELETE CASCADE
--     Como perfiles ya cae en cascada desde auth.users, gana el CASCADE: al
--     borrar un usuario se BORRA su flota, en vez de quedar huérfana como
--     pretendía la otra restricción. Hay que decidir cuál de las dos es la
--     intención real antes de tocar nada.
--
--     -- ALTER TABLE public.custodios DROP CONSTRAINT custodios_propietario_fk;
--     -- ALTER TABLE public.patios    DROP CONSTRAINT patios_propietario_fk;
--     -- ALTER TABLE public.lavados   DROP CONSTRAINT lavados_propietario_fk;
-- ============================================================================
