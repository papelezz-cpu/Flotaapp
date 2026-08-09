-- ──────────────────────────────────────────────────────────────────────────
-- EXPEDIENTES DOCUMENTALES DEL VIAJE
--
-- Un viaje de importación tiene dos puntos donde el transportista se queda
-- varado por papeles, y ninguno de los dos vivía en la app:
--
--   1. INGRESO A PUERTO — sin pedimento pagado, carta de liberación de la
--      naviera y BL revalidado, no lo dejan entrar. Viaje en falso.
--   2. ENTREGA DE VACÍOS — el contenedor se devuelve al depósito que indica
--      la naviera. Las demoras corren por día desde que sale de la terminal
--      hasta que entra al patio de vacíos.
--
-- Ojo con la división: los documentos DEL TRANSPORTISTA (permiso SCT, seguro,
-- licencia federal, tarjeta de circulación, padrón de API) ya viven en
-- perfiles y operadores. Esto es solo para los documentos DEL EMBARQUE, que
-- son distintos en cada viaje y los tiene el cliente o su agente aduanal.
--
-- El expediente cuelga de la reservación, no del pedido: antes de que se
-- apruebe el acuerdo no hay transportista a quién pedirle ni a quién avisarle.
-- ──────────────────────────────────────────────────────────────────────────

-- ── 1) Bandera en la solicitud ─────────────────────────────────────────────
-- Se pregunta al pedir el viaje. Le sirve a la empresa para cotizar: entrar a
-- puerto implica maniobras, tiempos de espera y riesgo de viaje en falso.
ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS entra_a_puerto boolean NOT NULL DEFAULT false;
ALTER TABLE public.plantillas_pedido
  ADD COLUMN IF NOT EXISTS entra_a_puerto boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.pedidos.entra_a_puerto IS
  'El transporte debe ingresar al recinto portuario. Habilita el expediente documental de ingreso en la reservación.';

-- ── 2) Catálogo de documentos, editable por el superadmin ──────────────────
-- Cada naviera y cada terminal pide cosas distintas, así que la lista no vive
-- en el código.
CREATE TABLE IF NOT EXISTS public.documentos_catalogo (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  etapa       text NOT NULL CHECK (etapa IN ('ingreso_puerto', 'entrega_vacios')),
  nombre      text NOT NULL,
  descripcion text,
  obligatorio boolean NOT NULL DEFAULT true,
  orden       smallint NOT NULL DEFAULT 0,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.documentos_catalogo IS
  'Qué documentos se le piden al cliente en cada etapa. Editable por el superadmin: cada naviera y terminal pide cosas distintas.';

-- ── 3) El expediente de una reservación en una etapa ───────────────────────
CREATE TABLE IF NOT EXISTS public.expedientes (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reserva_id     uuid NOT NULL REFERENCES public.reservaciones(id) ON DELETE CASCADE,
  etapa          text NOT NULL CHECK (etapa IN ('ingreso_puerto', 'entrega_vacios')),

  -- solicitado: el transportista lo pidió y el cliente aún no completa
  -- en_revision: el cliente subió todo lo obligatorio, falta que lo revise
  -- completo: el transportista lo dio por bueno
  estado         text NOT NULL DEFAULT 'solicitado'
                 CHECK (estado IN ('solicitado', 'en_revision', 'completo')),

  solicitado_por uuid,
  solicitado_en  timestamptz NOT NULL DEFAULT now(),
  completado_en  timestamptz,
  nota           text,

  -- Solo para entrega_vacios. La fecha límite es donde está el dinero: las
  -- demoras se cobran por día de retraso en devolver el contenedor.
  deposito_vacios      text,
  fecha_limite_vacios  date,

  UNIQUE (reserva_id, etapa)
);

CREATE INDEX IF NOT EXISTS idx_expedientes_reserva ON public.expedientes (reserva_id);

COMMENT ON COLUMN public.expedientes.fecha_limite_vacios IS
  'Último día para devolver el contenedor sin que corran demoras. Se avisa a ambas partes conforme se acerca.';

-- ── 4) Cada renglón del checklist ──────────────────────────────────────────
-- Es checklist y no subida libre a propósito: con subida libre nadie sabe qué
-- falta. Así los dos ven el mismo semáforo.
CREATE TABLE IF NOT EXISTS public.expediente_documentos (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  expediente_id uuid NOT NULL REFERENCES public.expedientes(id) ON DELETE CASCADE,

  -- Se copia el nombre del catálogo en vez de referenciarlo: si mañana editan
  -- el catálogo, un expediente viejo debe seguir diciendo lo que se pidió.
  nombre        text NOT NULL,
  descripcion   text,
  obligatorio   boolean NOT NULL DEFAULT true,
  orden         smallint NOT NULL DEFAULT 0,

  estado        text NOT NULL DEFAULT 'pendiente'
                CHECK (estado IN ('pendiente', 'subido', 'aceptado', 'rechazado')),
  archivo_path  text,
  archivo_nombre text,
  nota_rechazo  text,
  subido_en     timestamptz,
  subido_por    uuid
);

CREATE INDEX IF NOT EXISTS idx_expdocs_expediente ON public.expediente_documentos (expediente_id);

-- ── 5) Semilla del catálogo ────────────────────────────────────────────────
-- Lista de partida, sacada de cómo opera hoy la importación por Manzanillo.
-- El superadmin la ajusta desde el panel; esto es solo para no arrancar vacío.
INSERT INTO public.documentos_catalogo (etapa, nombre, descripcion, obligatorio, orden)
SELECT * FROM (VALUES
  ('ingreso_puerto', 'Pedimento aduanal pagado',
   'Comprobante de pago del pedimento. Sin él no se libera la mercancía.', true, 1),
  ('ingreso_puerto', 'Carta de liberación de la naviera',
   'Autoriza el retiro del contenedor. La emite la naviera al agente aduanal.', true, 2),
  ('ingreso_puerto', 'BL revalidado',
   'Bill of Lading con la revalidación que transfiere los derechos de la mercancía.', true, 3),
  ('ingreso_puerto', 'Factura comercial',
   'Factura del proveedor en el extranjero.', true, 4),
  ('ingreso_puerto', 'Packing list',
   'Desglose de la mercancía por bulto.', false, 5),
  ('ingreso_puerto', 'Datos del contenedor y sello',
   'Número de contenedor y número de sello o precinto.', true, 6),
  ('entrega_vacios', 'Carta de devolución de la naviera',
   'Indica a qué depósito se devuelve. No es libre: reefer, open top y flat rack regresan al puerto de arribo.', true, 1),
  ('entrega_vacios', 'Comprobante de libre adeudo',
   'Que no haya demoras pendientes de pago; si las hay, el comprobante de pago.', true, 2),
  ('entrega_vacios', 'Datos del depósito asignado',
   'Nombre, dirección y horario del patio de vacíos.', true, 3)
) AS v(etapa, nombre, descripcion, obligatorio, orden)
WHERE NOT EXISTS (SELECT 1 FROM public.documentos_catalogo);

-- ── 6) Bucket privado ──────────────────────────────────────────────────────
-- Privado sin discusión: un pedimento y una factura comercial son datos
-- fiscales y comerciales sensibles. Se leen con createSignedUrl, nunca con
-- getPublicUrl.
INSERT INTO storage.buckets (id, name, public)
VALUES ('documentos-viaje', 'documentos-viaje', false)
ON CONFLICT (id) DO NOTHING;

-- ── 7) RLS ─────────────────────────────────────────────────────────────────
ALTER TABLE public.documentos_catalogo    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expedientes            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expediente_documentos  ENABLE ROW LEVEL SECURITY;

-- ¿Este usuario participa en la reservación del expediente?
-- SECURITY DEFINER porque las políticas de expediente_documentos necesitan
-- consultar reservaciones, y no queremos depender de que el usuario pueda
-- leerla directamente.
CREATE OR REPLACE FUNCTION public.participa_en_expediente(exp_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.expedientes e
    JOIN public.reservaciones r ON r.id = e.reserva_id
    WHERE e.id = exp_id
      AND (r.cliente_user_id = auth.uid() OR r.propietario_id = auth.uid())
  ) OR public.is_superadmin();
$$;

REVOKE ALL ON FUNCTION public.participa_en_expediente(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.participa_en_expediente(uuid) TO authenticated;

-- Catálogo: todos lo leen (el cliente necesita saber qué le van a pedir),
-- solo el superadmin lo edita.
DROP POLICY IF EXISTS docs_catalogo_select ON public.documentos_catalogo;
CREATE POLICY docs_catalogo_select ON public.documentos_catalogo
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS docs_catalogo_write ON public.documentos_catalogo;
CREATE POLICY docs_catalogo_write ON public.documentos_catalogo
  FOR ALL TO authenticated
  USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());

-- Expedientes: solo las dos partes de la reservación.
DROP POLICY IF EXISTS expedientes_select ON public.expedientes;
CREATE POLICY expedientes_select ON public.expedientes
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.reservaciones r
    WHERE r.id = reserva_id
      AND (r.cliente_user_id = auth.uid() OR r.propietario_id = auth.uid())
  ) OR public.is_superadmin());

-- Crear el expediente: el transportista lo solicita. También el cliente, por
-- si se adelanta, y el superadmin.
DROP POLICY IF EXISTS expedientes_insert ON public.expedientes;
CREATE POLICY expedientes_insert ON public.expedientes
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.reservaciones r
    WHERE r.id = reserva_id
      AND (r.cliente_user_id = auth.uid() OR r.propietario_id = auth.uid())
  ) OR public.is_superadmin());

DROP POLICY IF EXISTS expedientes_update ON public.expedientes;
CREATE POLICY expedientes_update ON public.expedientes
  FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.reservaciones r
    WHERE r.id = reserva_id
      AND (r.cliente_user_id = auth.uid() OR r.propietario_id = auth.uid())
  ) OR public.is_superadmin());

-- Renglones del checklist: quien participa en el expediente.
DROP POLICY IF EXISTS expdocs_all ON public.expediente_documentos;
CREATE POLICY expdocs_all ON public.expediente_documentos
  FOR ALL TO authenticated
  USING (public.participa_en_expediente(expediente_id))
  WITH CHECK (public.participa_en_expediente(expediente_id));

-- ── 8) Guard: cada quien mueve lo suyo ─────────────────────────────────────
-- El cliente sube archivos; el transportista acepta o rechaza. Sin esto, el
-- cliente podría marcar sus propios documentos como aceptados por REST y
-- saltarse la revisión.
CREATE OR REPLACE FUNCTION public.guard_expediente_documento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  es_cliente boolean;
BEGIN
  IF public.is_superadmin() THEN RETURN NEW; END IF;

  SELECT (r.cliente_user_id = auth.uid()) INTO es_cliente
  FROM public.expedientes e
  JOIN public.reservaciones r ON r.id = e.reserva_id
  WHERE e.id = NEW.expediente_id;

  -- Solo el transportista dictamina.
  IF es_cliente AND NEW.estado IN ('aceptado', 'rechazado')
     AND NEW.estado IS DISTINCT FROM OLD.estado THEN
    RAISE EXCEPTION 'No autorizado: solo el transportista revisa los documentos';
  END IF;

  -- Solo el cliente sube.
  IF NOT es_cliente AND NEW.archivo_path IS DISTINCT FROM OLD.archivo_path THEN
    RAISE EXCEPTION 'No autorizado: solo el cliente sube los documentos';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_expediente_documento ON public.expediente_documentos;
CREATE TRIGGER trg_guard_expediente_documento
  BEFORE UPDATE ON public.expediente_documentos
  FOR EACH ROW EXECUTE FUNCTION public.guard_expediente_documento();

-- ── 9) Storage: solo las partes de la reservación ──────────────────────────
-- La ruta es {expediente_id}/{archivo}, así que el primer segmento identifica
-- el expediente y de ahí se resuelve quién puede verlo.
DROP POLICY IF EXISTS docviaje_select ON storage.objects;
CREATE POLICY docviaje_select ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'documentos-viaje'
         AND public.participa_en_expediente((storage.foldername(name))[1]::uuid));

DROP POLICY IF EXISTS docviaje_insert ON storage.objects;
CREATE POLICY docviaje_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'documentos-viaje'
              AND public.participa_en_expediente((storage.foldername(name))[1]::uuid));

DROP POLICY IF EXISTS docviaje_update ON storage.objects;
CREATE POLICY docviaje_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'documentos-viaje'
         AND public.participa_en_expediente((storage.foldername(name))[1]::uuid));
