-- Chat por reservación: el superadmin puede SUPERVISAR (solo lectura) los hilos
-- cliente↔empresa de las reservaciones, sin ser participante del hilo.
--
-- Las políticas RLS son permisivas y se combinan con OR, por lo que añadir esta
-- política NO altera el acceso existente de los participantes: solo SUMA la
-- lectura para superadmin. El superadmin nunca inserta mensajes (la UI lo abre
-- en modo observador de solo lectura), así que no se toca la política de INSERT.

DROP POLICY IF EXISTS msg_select_superadmin ON public.mensajes;
CREATE POLICY msg_select_superadmin ON public.mensajes
  FOR SELECT TO authenticated
  USING (public.is_superadmin());
