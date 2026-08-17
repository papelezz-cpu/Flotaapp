-- Si la transportista no puede entregar el vacío (depósito lleno, problema
-- con la unidad, etc.), tiene que avisarle al cliente por qué — no dejarlo
-- sin noticias mientras corren las demoras.
ALTER TABLE public.expedientes
  ADD COLUMN IF NOT EXISTS incidente_motivo text,
  ADD COLUMN IF NOT EXISTS incidente_reportado_en timestamptz,
  ADD COLUMN IF NOT EXISTS incidente_reportado_por uuid REFERENCES auth.users(id) ON DELETE SET NULL;
