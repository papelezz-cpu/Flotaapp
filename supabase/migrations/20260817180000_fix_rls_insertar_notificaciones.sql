-- La política insertar_notificaciones (INSERT en notificaciones) tenía la
-- lógica correcta en texto (self, superadmin, contraparte de reservación u
-- oferta) pero fallaba con 42501 en producción para TODO lo que no fuera
-- auto-notificarse — incluso is_superadmin() llamado directo en el WITH
-- CHECK fallaba, aunque evaluado por separado daba true. Se mueve la
-- lógica a una función SECURITY DEFINER (mismo patrón que is_superadmin())
-- para que la política solo evalúe una llamada a función, no subconsultas
-- EXISTS inline contra otras tablas con RLS propio.
CREATE OR REPLACE FUNCTION public.puede_notificar(p_target uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_ok boolean;
BEGIN
  SELECT
    (p_target = auth.uid())
    OR is_superadmin()
    OR EXISTS (SELECT 1 FROM perfiles pf WHERE pf.user_id = p_target AND pf.rol = 'superadmin')
    OR EXISTS (
      SELECT 1 FROM reservaciones r
      WHERE (r.propietario_id = auth.uid() AND r.cliente_user_id = p_target)
         OR (r.cliente_user_id = auth.uid() AND r.propietario_id = p_target)
    )
    OR EXISTS (
      SELECT 1 FROM ofertas o JOIN pedidos p ON p.id = o.pedido_id
      WHERE (o.admin_id = auth.uid() AND p.cliente_id = p_target)
         OR (p.cliente_id = auth.uid() AND o.admin_id = p_target)
    )
  INTO v_ok;
  RETURN coalesce(v_ok, false);
END;
$$;

DROP POLICY IF EXISTS insertar_notificaciones ON public.notificaciones;
CREATE POLICY insertar_notificaciones ON public.notificaciones
  FOR INSERT TO authenticated
  WITH CHECK (puede_notificar(user_id));
