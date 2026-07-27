-- Cierra un hueco de RLS: el dueño de un camion/custodio/patio/lavado/operador podia
-- auto-aprobar su propio recurso via REST directo (sb.from('camiones').update({aprobacion:'aprobada'}))
-- porque las politicas de UPDATE solo verifican propietario_id, sin WITH CHECK que
-- restrinja que columnas cambian. El boton "Aprobar" en la UI solo se ocultaba
-- client-side; no habia nada del lado del servidor evitandolo.
--
-- Confirmado por lectura del codigo: en todos los flujos de edicion propios (admin.js,
-- operadores.js) el dueno unicamente escribe aprobacion:'pendiente', nunca 'aprobada'.
-- Por eso basta con bloquear la transicion a cualquier valor distinto de 'pendiente'
-- cuando quien actualiza no es superadmin.

CREATE OR REPLACE FUNCTION public.guard_fleet_resource_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  IF NEW.aprobacion IS DISTINCT FROM OLD.aprobacion AND NEW.aprobacion IS DISTINCT FROM 'pendiente' THEN
    RAISE EXCEPTION 'No autorizado: solo un superadmin puede aprobar o rechazar este recurso';
  END IF;

  IF NEW.propietario_id IS DISTINCT FROM OLD.propietario_id THEN
    RAISE EXCEPTION 'No autorizado: no puedes transferir la propiedad de este recurso';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_camiones_update ON public.camiones;
CREATE TRIGGER trg_guard_camiones_update
  BEFORE UPDATE ON public.camiones
  FOR EACH ROW EXECUTE FUNCTION public.guard_fleet_resource_update();

DROP TRIGGER IF EXISTS trg_guard_custodios_update ON public.custodios;
CREATE TRIGGER trg_guard_custodios_update
  BEFORE UPDATE ON public.custodios
  FOR EACH ROW EXECUTE FUNCTION public.guard_fleet_resource_update();

DROP TRIGGER IF EXISTS trg_guard_patios_update ON public.patios;
CREATE TRIGGER trg_guard_patios_update
  BEFORE UPDATE ON public.patios
  FOR EACH ROW EXECUTE FUNCTION public.guard_fleet_resource_update();

DROP TRIGGER IF EXISTS trg_guard_lavados_update ON public.lavados;
CREATE TRIGGER trg_guard_lavados_update
  BEFORE UPDATE ON public.lavados
  FOR EACH ROW EXECUTE FUNCTION public.guard_fleet_resource_update();

DROP TRIGGER IF EXISTS trg_guard_operadores_update ON public.operadores;
CREATE TRIGGER trg_guard_operadores_update
  BEFORE UPDATE ON public.operadores
  FOR EACH ROW EXECUTE FUNCTION public.guard_fleet_resource_update();
