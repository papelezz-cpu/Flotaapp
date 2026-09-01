-- ============================================================================
-- H-12: reservaciones pasa de paginación por OFFSET a paginación por cursor
-- ============================================================================
--
-- js/reservaciones.js ahora ordena por (created_at DESC, id DESC) y usa un
-- cursor keyset, igual que ya hacía js/pedidos.js al lado. Sin este índice,
-- cada página recorre y ordena la tabla entera en memoria — hoy son 20 filas
-- y no se nota, pero es exactamente el tipo de cosa que se vuelve cara en
-- silencio según la tabla crece.
--
-- Compuesto (created_at, id) — un paso más preciso que idx_pedidos_fecha
-- (20260826120000_auditoria_indices_e_integridad.sql), que resultó ser solo
-- (created_at DESC) sin id: cubre también el desempate del cursor sin dejarle
-- a Postgres un sort residual en memoria para las filas que empatan en fecha.
-- ============================================================================

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reservaciones_fecha
  ON public.reservaciones (created_at DESC, id DESC);
