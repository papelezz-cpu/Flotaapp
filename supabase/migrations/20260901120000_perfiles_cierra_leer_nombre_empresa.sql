-- ============================================================================
-- H-01, mitad 2: cierra la política que dejaba pasar la fila entera de
-- perfiles a cualquier autenticado.
-- ============================================================================
--
-- Precondición: 20260831210000_perfiles_ficha_publica.sql ya está aplicada,
-- desplegada, y las cinco pantallas que dependían de leer `perfiles` ajeno
-- directamente ya leen `empresas_publico` (catálogo de proveedores, detalle
-- de unidad → pestaña Empresa, listado de camiones, listado de recursos,
-- nombres de empresa en reservaciones). Verificado por código en esta sesión
-- el 2026-09-01: las cinco piden exactamente las columnas que la vista
-- expone. Falta la comprobación en vivo contra portgo-pruebas antes de
-- aplicar esto — ver CLAUDE.md Regla #3.
--
-- No editar la migración anterior: esta es aditiva sobre lo que ya existe,
-- y su reversión es una sola sentencia (recrear la política vieja).
-- ============================================================================

create policy perfiles_lectura_propia on public.perfiles
  for select to authenticated
  using ( user_id = (select auth.uid()) );

drop policy if exists "Leer nombre de empresa" on public.perfiles;
drop policy if exists "Leer propio perfil"     on public.perfiles;
