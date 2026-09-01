-- ============================================================================
-- H-03: refrigerado y temp_controlada divergen — iguala el histórico
-- ============================================================================
--
-- El comentario de la columna en producción ya dice cuál manda:
--   "Reemplaza el antiguo checkbox temp_controlada, que se sigue escribiendo
--    por compatibilidad."
-- Pero el código leía la vieja (js/pedidos.js:669, js/aprobaciones.js:1000),
-- y esos dos puntos de lectura ya se movieron a `refrigerado` en un commit
-- aparte. Esta migración solo cierra la brecha de datos: los pedidos
-- anteriores a la columna nueva que quedaron con temp_controlada=true y
-- refrigerado=false (medido en producción el 31 ago 2026: 3 de 40 filas).
--
-- No toca la escritura: pedidos.js sigue guardando las dos desde el mismo
-- checkbox, así que no vuelve a divergir hacia adelante. Retirar
-- temp_controlada del todo queda para una fase posterior (columna generada
-- o DROP), fuera de alcance aquí.
-- ============================================================================

update public.pedidos
   set refrigerado = true
 where temp_controlada = true
   and refrigerado is distinct from true;
