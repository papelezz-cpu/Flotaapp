-- ============================================================================
-- Claves foraneas de reservaciones y calificaciones
-- ============================================================================
-- Las dos que quedaron fuera de la Fase 4, porque cada una escondia una
-- decision de negocio. Ya tomadas.
--
-- Comprobado en produccion antes de aplicar: 0 huerfanos en las cuatro
-- columnas (reservaciones.propietario_id y cliente_user_id, calificaciones
-- .admin_id y cliente_id).
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. reservaciones: conservar el historial, como la flota
-- ─────────────────────────────────────────────────────────────────────────
-- La reservacion es el registro comercial: viajes completados, pagos y
-- evidencias. No debe morir con la cuenta.
--
-- La tabla YA seguia esa convencion: sus cuatro FK existentes
-- (pagado_por, cancelacion_solicitada_por, cancelacion_resuelta_por,
-- pedido_id) son todas SET NULL. Lo unico que impedia extenderla a las dos
-- partes era el CHECK que se añadio el 2026-08-26, que exigia ambas siempre.
--
-- Se relaja: ambas partes son obligatorias mientras la reservacion esta VIVA
-- —que es cuando importan, porque de ellas depende RLS y sin ellas la fila se
-- vuelve ingestionable— y opcionales una vez terminada.
ALTER TABLE public.reservaciones DROP CONSTRAINT IF EXISTS reservaciones_partes_presentes;

ALTER TABLE public.reservaciones
  ADD CONSTRAINT reservaciones_partes_presentes
  CHECK (
    estado IN ('Completada', 'Cancelada', 'Rechazada')
    OR (cliente_user_id IS NOT NULL AND propietario_id IS NOT NULL)
  );

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reservaciones_propietario_id_fkey'
                  AND conrelid = 'public.reservaciones'::regclass) THEN
    ALTER TABLE public.reservaciones
      ADD CONSTRAINT reservaciones_propietario_id_fkey
      FOREIGN KEY (propietario_id) REFERENCES public.perfiles(user_id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reservaciones_cliente_user_id_fkey'
                  AND conrelid = 'public.reservaciones'::regclass) THEN
    ALTER TABLE public.reservaciones
      ADD CONSTRAINT reservaciones_cliente_user_id_fkey
      FOREIGN KEY (cliente_user_id) REFERENCES public.perfiles(user_id) ON DELETE SET NULL;
  END IF;
END $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. calificaciones: muere con la empresa, sobrevive al cliente
-- ─────────────────────────────────────────────────────────────────────────
-- Las calificaciones se leen SIEMPRE por admin_id: son la reputacion de la
-- empresa (js/catalogo.js, js/detalle.js, js/pedidos.js, js/views.js).
-- cliente_id solo se escribe, nunca se consulta.
--
--   admin_id   -> CASCADE. La calificacion es SOBRE esa empresa; sin ella no
--                 la lee ningun camino de codigo.
--   cliente_id -> SET NULL. Si se borra el cliente, su reseña sigue contando
--                 en el promedio de la empresa pero pierde autor, que es lo
--                 que hace cualquier sistema de reseñas al anonimizar.
ALTER TABLE public.calificaciones ALTER COLUMN cliente_id DROP NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'calificaciones_admin_id_fkey'
                  AND conrelid = 'public.calificaciones'::regclass) THEN
    ALTER TABLE public.calificaciones
      ADD CONSTRAINT calificaciones_admin_id_fkey
      FOREIGN KEY (admin_id) REFERENCES public.perfiles(user_id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'calificaciones_cliente_id_fkey'
                  AND conrelid = 'public.calificaciones'::regclass) THEN
    ALTER TABLE public.calificaciones
      ADD CONSTRAINT calificaciones_cliente_id_fkey
      FOREIGN KEY (cliente_id) REFERENCES public.perfiles(user_id) ON DELETE SET NULL;
  END IF;
END $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Archivar una reservacion ya no borra su calificacion
-- ─────────────────────────────────────────────────────────────────────────
-- js/reservaciones.js:673 archiva copiando la fila a reservaciones_historico y
-- borrando la original. Con reservacion_id en CASCADE, ese borrado se llevaba
-- por delante la calificacion: archivar, que existe para CONSERVAR, destruia
-- la reputacion ganada en ese servicio.
--
-- reservacion_id ya es nullable, y el indice unico que se añadio el 2026-08-26
-- es parcial (WHERE reservacion_id IS NOT NULL), asi que admite varias filas
-- en nulo sin chocar entre si.
ALTER TABLE public.calificaciones DROP CONSTRAINT IF EXISTS calificaciones_reservacion_id_fkey;
ALTER TABLE public.calificaciones
  ADD CONSTRAINT calificaciones_reservacion_id_fkey
  FOREIGN KEY (reservacion_id) REFERENCES public.reservaciones(id) ON DELETE SET NULL;


-- ─────────────────────────────────────────────────────────────────────────
-- 4. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
DO $$
DECLARE esperado text; obtenido text;
BEGIN
  SELECT string_agg(conrelid::regclass::text || '.' || conname || '=' ||
                    CASE confdeltype WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL'
                                     WHEN 'a' THEN 'NO ACTION' ELSE confdeltype::text END,
                    ', ' ORDER BY conname)
    INTO obtenido
    FROM pg_constraint
   WHERE contype = 'f' AND connamespace = 'public'::regnamespace
     AND conname IN ('reservaciones_propietario_id_fkey','reservaciones_cliente_user_id_fkey',
                     'calificaciones_admin_id_fkey','calificaciones_cliente_id_fkey',
                     'calificaciones_reservacion_id_fkey');

  esperado := 'calificaciones.calificaciones_admin_id_fkey=CASCADE, '
           || 'calificaciones.calificaciones_cliente_id_fkey=SET NULL, '
           || 'calificaciones.calificaciones_reservacion_id_fkey=SET NULL, '
           || 'reservaciones.reservaciones_cliente_user_id_fkey=SET NULL, '
           || 'reservaciones.reservaciones_propietario_id_fkey=SET NULL';

  IF obtenido IS DISTINCT FROM esperado THEN
    RAISE EXCEPTION 'Las FK no quedaron como se esperaba. Obtenido: %', obtenido;
  END IF;
  RAISE NOTICE 'Verificado: las 5 claves foraneas con el comportamiento decidido.';
END $$;
