-- ──────────────────────────────────────────────────────────────────────────
-- La solicitud se arma desde la CARGA, no desde el camión.
--
-- Antes el cliente tenía que elegir "Torton caja seca" o "Full porta
-- contenedor 40/20" — o sea, saber de camiones. Ahora describe lo que va a
-- mover y el sistema le propone la unidad.
--
-- tipo_camion NO desaparece: sigue siendo lo que determina qué empresas
-- reciben el aviso y quién puede ofertar (ver destinatariosEmpresas en la
-- Edge Function y el gate de pedidoCardHTML). Lo que cambia es que ya no lo
-- teclea el cliente, lo calcula el sistema y el cliente puede corregirlo.
--
-- Las columnas viejas (carga_peligrosa, temp_controlada, tipo_contenedor,
-- num_bultos, peso_carga) se conservan y se siguen escribiendo, derivadas de
-- los campos nuevos: hay pedidos históricos y vistas que las leen.
-- ──────────────────────────────────────────────────────────────────────────

ALTER TABLE public.pedidos
  -- Qué tipo de carga es. Manda el resto del formulario.
  ADD COLUMN IF NOT EXISTS categoria_carga text,

  -- Refrigeración: es un atributo, no un tipo de carga — una carga puede ser
  -- contenerizada Y refrigerada a la vez.
  ADD COLUMN IF NOT EXISTS refrigerado boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS temp_min numeric,
  ADD COLUMN IF NOT EXISTS temp_max numeric,

  -- Contenedores. Dos columnas por contenedor en vez de un jsonb: son máximo
  -- dos (doble remolque) y así se pueden filtrar e indexar sin desempacar.
  ADD COLUMN IF NOT EXISTS num_contenedores smallint,
  ADD COLUMN IF NOT EXISTS contenedor_1_tipo text,
  ADD COLUMN IF NOT EXISTS contenedor_1_peso numeric,
  ADD COLUMN IF NOT EXISTS contenedor_2_tipo text,
  ADD COLUMN IF NOT EXISTS contenedor_2_peso numeric,

  -- Sobredimensionada
  ADD COLUMN IF NOT EXISTS largo_m numeric,
  ADD COLUMN IF NOT EXISTS ancho_m numeric,
  ADD COLUMN IF NOT EXISTS alto_m numeric,

  -- Hazmat
  ADD COLUMN IF NOT EXISTS hazmat_clase text,
  ADD COLUMN IF NOT EXISTS hazmat_un text,

  -- Qué propuso el sistema, aunque el cliente lo haya cambiado. Sirve para
  -- saber si las reglas de recomendación están acertando.
  ADD COLUMN IF NOT EXISTS tipo_camion_sugerido text;

COMMENT ON COLUMN public.pedidos.categoria_carga IS
  'General | Consolidada | Suelta | Sobredimensionada | Hazmat | Contenerizada. Determina qué campos pide el formulario y qué unidad se recomienda.';
COMMENT ON COLUMN public.pedidos.tipo_camion_sugerido IS
  'Unidad que calculó el sistema. Si difiere de tipo_camion, el cliente la cambió a mano.';
COMMENT ON COLUMN public.pedidos.refrigerado IS
  'Atributo transversal: aplica a General, Consolidada, Suelta y Contenerizada. Reemplaza el antiguo checkbox temp_controlada, que se sigue escribiendo por compatibilidad.';

-- Índice para el panel del superadmin y los reportes por tipo de carga.
CREATE INDEX IF NOT EXISTS idx_pedidos_categoria_carga
  ON public.pedidos (categoria_carga)
  WHERE categoria_carga IS NOT NULL;

-- ── Las solicitudes frecuentes guardan los mismos campos ────────────────────
ALTER TABLE public.plantillas_pedido
  ADD COLUMN IF NOT EXISTS categoria_carga text,
  ADD COLUMN IF NOT EXISTS refrigerado boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS temp_min numeric,
  ADD COLUMN IF NOT EXISTS temp_max numeric,
  ADD COLUMN IF NOT EXISTS num_contenedores smallint,
  ADD COLUMN IF NOT EXISTS contenedor_1_tipo text,
  ADD COLUMN IF NOT EXISTS contenedor_1_peso numeric,
  ADD COLUMN IF NOT EXISTS contenedor_2_tipo text,
  ADD COLUMN IF NOT EXISTS contenedor_2_peso numeric,
  ADD COLUMN IF NOT EXISTS largo_m numeric,
  ADD COLUMN IF NOT EXISTS ancho_m numeric,
  ADD COLUMN IF NOT EXISTS alto_m numeric,
  ADD COLUMN IF NOT EXISTS hazmat_clase text,
  ADD COLUMN IF NOT EXISTS hazmat_un text;

-- ── Volumen: un camión se llena por peso O por espacio ──────────────────────
-- Sin este dato, 2 toneladas de carga voluminosa (unicel, muebles, plástico)
-- caían en una camioneta de 3.5 ton, cuando no entran ni en un tráiler.
ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS volumen_m3 numeric;
ALTER TABLE public.plantillas_pedido
  ADD COLUMN IF NOT EXISTS volumen_m3 numeric;

COMMENT ON COLUMN public.pedidos.volumen_m3 IS
  'Volumen aproximado de la carga. Junto con peso_carga determina la unidad recomendada: manda la restricción más exigente (cubicaje).';

-- ── Punto exacto de la maniobra ─────────────────────────────────────────────
-- La dirección escrita es la referencia humana ("andén 4, portón azul"); estas
-- coordenadas son para que el operador llegue al punto y no solo a la calle.
ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS origen_lat  numeric,
  ADD COLUMN IF NOT EXISTS origen_lng  numeric,
  ADD COLUMN IF NOT EXISTS destino_lat numeric,
  ADD COLUMN IF NOT EXISTS destino_lng numeric;
