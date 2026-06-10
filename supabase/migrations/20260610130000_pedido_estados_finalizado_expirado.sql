-- Ciclo de vida del pedido: estados terminales 'finalizado' y 'expirado' (2026-06-10)
-- Antes, un pedido se quedaba en 'acordado' para siempre aunque el servicio ya
-- se hubiera completado o la fecha hubiera pasado, mostrandose como acuerdo activo.
--   - finalizado: la empresa marco el servicio como completado.
--   - expirado:   paso la fecha_fin del acuerdo sin completarse.

-- 1. Permitir los nuevos estados en el CHECK
ALTER TABLE public.pedidos DROP CONSTRAINT IF EXISTS pedidos_estado_check;
ALTER TABLE public.pedidos ADD CONSTRAINT pedidos_estado_check
  CHECK (estado = ANY (ARRAY[
    'abierto','en_negociacion','acordado','cancelado',
    'pendiente_revision','pendiente_acuerdo','rechazado',
    'finalizado','expirado'
  ]));

-- 2. Reparar enlaces pedido_id huerfanos en reservaciones (datos historicos)
UPDATE public.reservaciones r
   SET pedido_id = p.id
  FROM public.pedidos p
 WHERE r.pedido_id IS NULL
   AND p.estado = 'acordado'
   AND p.cliente_id = r.cliente_user_id
   AND p.fecha_ini = r.fecha_ini
   AND p.fecha_fin = r.fecha_fin;

-- 3. Cerrar acuerdos historicos colgados
UPDATE public.pedidos p SET estado = 'finalizado'
 WHERE p.estado = 'acordado'
   AND EXISTS (SELECT 1 FROM public.reservaciones r WHERE r.pedido_id = p.id AND r.estado = 'Completada');

UPDATE public.pedidos p SET estado = 'cancelado'
 WHERE p.estado = 'acordado'
   AND EXISTS (SELECT 1 FROM public.reservaciones r WHERE r.pedido_id = p.id AND r.estado = 'Cancelada');

UPDATE public.pedidos SET estado = 'expirado'
 WHERE estado = 'acordado' AND fecha_fin IS NOT NULL AND fecha_fin < current_date;
