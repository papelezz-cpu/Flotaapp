-- ──────────────────────────────────────────────────────────────────────────
-- El panel de usuarios no podía cambiar un rol.
--
-- Síntoma: el superadmin edita un usuario a 'superadmin', el panel dice
-- "✓ Usuario actualizado" y al recargar sigue como 'admin'.
--
-- Causa: trg_guard_perfil_self_update es un BEFORE UPDATE sobre perfiles, y
-- los triggers NO se saltan con la service role key — eso solo salta RLS. La
-- Edge Function gestionar-usuario escribe con esa llave, así que no hay
-- sesión: auth.uid() es NULL, is_superadmin() da falso, y el guard llega a
--
--     IF NEW.rol IS DISTINCT FROM OLD.rol THEN RAISE EXCEPTION ...
--
-- La excepción abortaba el UPDATE. La función descartaba el error y respondía
-- ok igual (eso se corrige aparte, en supabase/functions/gestionar-usuario).
--
-- ── Por qué eximir a service_role no debilita nada ────────────────────────
--
-- El guard existe para que un usuario no se ascienda a sí mismo desde el
-- cliente. Quien llama con la service role key ya puede hacer cualquier cosa
-- en la base — incluido borrar este trigger — así que la exención no concede
-- ningún poder nuevo. Y la Edge Function ya verifica del lado del servidor
-- que quien llama sea superadmin (valida su JWT contra perfiles.rol) antes de
-- tocar nada.
--
-- Se usa auth.role() y no current_user: esta función es SECURITY DEFINER, así
-- que current_user es el dueño de la función, no quien la invoca. auth.role()
-- lee el claim del JWT desde un GUC de la petición, que SECURITY DEFINER no
-- altera.
--
-- El resto del cuerpo es idéntico a 20260723120000_metodo_verificacion_cuenta.
-- ──────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.guard_perfil_self_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- Administración desde el servidor (Edge Function gestionar-usuario).
  IF COALESCE(auth.role(), '') = 'service_role' THEN
    RETURN NEW;
  END IF;

  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  IF NEW.rol IS DISTINCT FROM OLD.rol THEN
    RAISE EXCEPTION 'No autorizado: no puedes cambiar tu rol';
  END IF;

  IF NEW.aprobacion_cuenta IS DISTINCT FROM OLD.aprobacion_cuenta THEN
    IF NOT (OLD.aprobacion_cuenta = 'rechazada' AND NEW.aprobacion_cuenta = 'pendiente') THEN
      RAISE EXCEPTION 'No autorizado: no puedes cambiar el estado de aprobacion de tu cuenta';
    END IF;
  END IF;

  IF NEW.verificado           IS DISTINCT FROM OLD.verificado
     OR NEW.docs_aprobados_en   IS DISTINCT FROM OLD.docs_aprobados_en
     OR NEW.docs_aprobados_por  IS DISTINCT FROM OLD.docs_aprobados_por
     OR NEW.metodo_verificacion IS DISTINCT FROM OLD.metodo_verificacion THEN
    RAISE EXCEPTION 'No autorizado: campos de verificacion solo modificables por superadmin';
  END IF;

  RETURN NEW;
END;
$$;

-- El trigger sigue siendo el mismo; solo cambió el cuerpo de la función.
-- (Se deja el CREATE TRIGGER por si se aplica sobre una base donde no exista.)
DROP TRIGGER IF EXISTS trg_guard_perfil_self_update ON public.perfiles;
CREATE TRIGGER trg_guard_perfil_self_update
  BEFORE UPDATE ON public.perfiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_perfil_self_update();
