-- F4 + F8: tipo_contenedor y plazo_pago en pedidos
ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS tipo_contenedor text,
  ADD COLUMN IF NOT EXISTS plazo_pago text;

-- F1: evidencias en reservaciones (completado_en ya existe)
ALTER TABLE public.reservaciones
  ADD COLUMN IF NOT EXISTS evidencias text[];

-- F7: badge de verificacion en perfiles
ALTER TABLE public.perfiles
  ADD COLUMN IF NOT EXISTS verificado boolean DEFAULT false;

-- F5: permiso de carga peligrosa en camiones
ALTER TABLE public.camiones
  ADD COLUMN IF NOT EXISTS doc_permiso_peligrosa text,
  ADD COLUMN IF NOT EXISTS fecha_vencimiento_permiso_peligrosa date;
