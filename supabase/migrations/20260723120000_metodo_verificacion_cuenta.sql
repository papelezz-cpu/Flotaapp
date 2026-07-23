-- Distingue el metodo usado al aprobar una cuenta: verificacion fisica vs solo documental.
ALTER TABLE public.perfiles
  ADD COLUMN IF NOT EXISTS metodo_verificacion text;

ALTER TABLE public.perfiles
  DROP CONSTRAINT IF EXISTS perfiles_metodo_verificacion_check;

ALTER TABLE public.perfiles
  ADD CONSTRAINT perfiles_metodo_verificacion_check
  CHECK (metodo_verificacion IS NULL OR metodo_verificacion IN ('fisica','documental'));

-- Misma regla que 'verificado': solo superadmin puede tocar este campo.
CREATE OR REPLACE FUNCTION public.guard_perfil_self_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
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
