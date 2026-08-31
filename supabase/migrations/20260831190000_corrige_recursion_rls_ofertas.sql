-- Corrige la recursión infinita entre las políticas RLS de ofertas y pedidos.
--
-- SÍNTOMA
--   Al contraofertar, el cliente recibe:
--     ERROR: infinite recursion detected in policy for relation "ofertas"
--   La contraoferta es un paso obligatorio del ciclo de negocio (el cliente
--   responde con su precio antes de aceptar), así que hoy ese camino está
--   roto en producción. Lo detectó pruebas/03-flujo-completo.mjs el
--   2026-08-31, sobre una copia fiel de producción — con la base de pruebas
--   anterior, que tenía otras políticas, no se habría visto.
--
-- CAUSA
--   Dos políticas se llaman entre sí:
--     of_update  (ofertas) → SELECT cliente_id FROM public.pedidos WHERE ...
--     ped_select (pedidos) → EXISTS (SELECT 1 FROM public.ofertas WHERE ...)
--   Actualizar una oferta obliga a evaluar of_update, que lee pedidos, que
--   obliga a evaluar ped_select, que lee ofertas, que vuelve a entrar en las
--   políticas de ofertas. Postgres lo corta y aborta la sentencia.
--
--   Es el único par mutuo del esquema: las demás políticas consultan perfiles
--   o reservaciones, y ninguna de esas dos consulta de vuelta.
--
-- ARREGLO
--   of_update pasa a usar es_mi_pedido(), que ya existe, es SECURITY DEFINER
--   con search_path fijo y por tanto NO vuelve a entrar en las políticas de
--   pedidos. Es exactamente lo que of_select ya hace para el mismo predicado;
--   a of_update simplemente no se le aplicó.
--
--   El permiso no cambia: sigue siendo "puede actualizar la oferta el dueño de
--   la oferta, el cliente dueño del pedido, o un superadmin". Las otras dos
--   ramas se conservan tal cual.
--
--   ALTER POLICY modifica en sitio: no se borra ninguna política, así que si
--   esto se revierte no queda un hueco sin proteger en el intermedio.

alter policy of_update on public.ofertas
  using (
    ((select auth.uid()) = admin_id)
    or (select public.es_mi_pedido(ofertas.pedido_id))
    or (exists (
          select 1
            from public.perfiles
           where perfiles.user_id = (select auth.uid())
             and perfiles.rol = 'superadmin'))
  );
