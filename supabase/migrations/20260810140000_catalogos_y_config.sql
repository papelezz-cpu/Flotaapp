-- ──────────────────────────────────────────────────────────────────────────
-- CATÁLOGOS Y CONFIGURACIÓN DE LA APP
--
-- El problema que resuelve: una app publicada queda congelada en el teléfono
-- del usuario. En la web, cambiar "metros cúbicos" por "tarimas" costó un
-- commit y 30 segundos. En móvil cuesta un build, la revisión de la tienda, y
-- después los usuarios que no actualizan — en flota, un equipo puede quedarse
-- un año con la versión que se instaló.
--
-- El historial de este repo dice exactamente qué cambia: de los últimos 15
-- commits, CINCO tocan el formulario de solicitud (4112981, 901dc69, b962818,
-- 588bc66, 63aae18). Esas listas no pueden vivir dentro del binario.
--
-- El patrón no es nuevo aquí: `documentos_catalogo` ya vive en la base
-- "porque cada naviera y cada terminal pide cosas distintas, así que la lista
-- no vive en el código" (migración 20260801120000). Esto es lo mismo, aplicado
-- al resto de las listas.
--
-- ── Aditiva ───────────────────────────────────────────────────────────────
-- Dos tablas nuevas, una función nueva, y un REPLACE de tracking_pasos() —que
-- se creó en la migración anterior y todavía no usa nadie en producción— para
-- que lea del catálogo con respaldo a los valores fijos. Nada de lo que hoy
-- funciona en la web se toca.
-- ──────────────────────────────────────────────────────────────────────────


-- ══════════════════════════════════════════════════════════════════════════
-- 1) CATÁLOGOS
-- ══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.catalogos (
  clave    text     NOT NULL,   -- 'plazo_pago', 'tipo_contenedor', 'tracking_camion'…
  valor    text     NOT NULL,   -- lo que se guarda en la base
  etiqueta text     NOT NULL,   -- lo que ve el usuario
  ayuda    text,                -- explicación corta, cuando hace falta
  orden    smallint NOT NULL DEFAULT 0,
  activo   boolean  NOT NULL DEFAULT true,
  -- Datos extra que dependen del catálogo: qué campos pide una categoría de
  -- carga, el icono de un paso de seguimiento, etc. Va en jsonb para no tener
  -- que migrar la tabla cada vez que un catálogo necesita un atributo propio.
  meta     jsonb,
  PRIMARY KEY (clave, valor)
);

COMMENT ON TABLE public.catalogos IS
  'Listas de negocio que las apps móviles leen en vez de traerlas compiladas. Agregar un plazo de pago o un paso de seguimiento debe ser un INSERT, no una versión nueva en las tiendas.';

CREATE INDEX IF NOT EXISTS idx_catalogos_clave
  ON public.catalogos (clave, orden) WHERE activo;

ALTER TABLE public.catalogos ENABLE ROW LEVEL SECURITY;

-- Los permisos de tabla van explícitos y no se dejan a los privilegios por
-- defecto del proyecto: sin GRANT, las políticas RLS ni siquiera se evalúan —
-- Postgres corta antes, con "permiso denegado a la tabla", y el síntoma se
-- parece a un problema de políticas cuando en realidad es de permisos.
GRANT SELECT ON public.catalogos TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.catalogos TO authenticated;  -- lo acota la RLS

-- Los lee cualquiera con sesión. No hay nada sensible: son listas de opciones.
DROP POLICY IF EXISTS catalogos_select ON public.catalogos;
CREATE POLICY catalogos_select ON public.catalogos
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS catalogos_write ON public.catalogos;
CREATE POLICY catalogos_write ON public.catalogos
  FOR ALL TO authenticated
  USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());


-- ══════════════════════════════════════════════════════════════════════════
-- 2) CONFIGURACIÓN DE LA APP
-- ══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.app_config (
  clave          text PRIMARY KEY,
  valor          jsonb NOT NULL,
  descripcion    text,
  actualizado_en timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.app_config IS
  'Interruptores y versión mínima de las apps. No evita publicar versiones: las vuelve seguras, porque permite bloquear una versión vieja que escribiría datos mal en lugar de esperar a que todos actualicen.';

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.app_config TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.app_config TO authenticated;  -- lo acota la RLS

-- Legible SIN sesión, a propósito: la comprobación de versión mínima tiene que
-- correr ANTES del login. Si una versión vieja hay que bloquearla, se bloquea
-- en la pantalla de arranque, no después de entrar. Aquí no hay datos de
-- nadie: son banderas y números de versión.
DROP POLICY IF EXISTS app_config_select ON public.app_config;
CREATE POLICY app_config_select ON public.app_config
  FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS app_config_write ON public.app_config;
CREATE POLICY app_config_write ON public.app_config
  FOR ALL TO authenticated
  USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());


-- ══════════════════════════════════════════════════════════════════════════
-- 3) COMPARACIÓN DE VERSIONES
--    Comparar "1.10.0" contra "1.9.0" como texto da el resultado equivocado.
--    Vive aquí y no en cada app para no escribir el mismo parser tres veces.
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.version_al_menos(p_version text, p_minima text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  a int[]; b int[]; i int;
BEGIN
  IF p_minima IS NULL OR btrim(p_minima) = '' THEN RETURN true; END IF;
  IF p_version IS NULL OR btrim(p_version) = '' THEN RETURN false; END IF;

  -- Se ignora cualquier sufijo tipo "1.2.3-beta": solo interesan los números.
  a := string_to_array(split_part(btrim(p_version), '-', 1), '.')::int[];
  b := string_to_array(split_part(btrim(p_minima),  '-', 1), '.')::int[];

  FOR i IN 1 .. greatest(array_length(a,1), array_length(b,1)) LOOP
    IF COALESCE(a[i], 0) > COALESCE(b[i], 0) THEN RETURN true;  END IF;
    IF COALESCE(a[i], 0) < COALESCE(b[i], 0) THEN RETURN false; END IF;
  END LOOP;

  RETURN true;  -- iguales
EXCEPTION WHEN others THEN
  -- Una versión con formato raro no debe dejar a nadie fuera de la app.
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.version_al_menos(text, text) TO anon, authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 4) ARRANQUE DE LA APP
--    Todo lo que la app necesita al abrir, en UNA llamada: si su versión
--    sigue soportada, el aviso global, las banderas y los catálogos.
--
--    Una sola llamada y no cinco porque esto corre en el puerto, con señal
--    mala: cada viaje de red extra es otra oportunidad de que el arranque se
--    quede colgado.
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.arranque_app(
  p_plataforma text DEFAULT 'android',   -- 'android' | 'ios'
  p_version    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_min     text;
  v_url     text;
  v_cfg     jsonb;
  v_aviso   jsonb;
  v_flags   jsonb;
  v_catalogos jsonb;
BEGIN
  SELECT valor INTO v_cfg FROM public.app_config
   WHERE clave = 'version_minima_' || COALESCE(p_plataforma, 'android');

  v_min := v_cfg ->> 'version';
  v_url := v_cfg ->> 'url';

  SELECT valor INTO v_aviso FROM public.app_config WHERE clave = 'aviso_global';
  SELECT valor INTO v_flags FROM public.app_config WHERE clave = 'flags';

  -- Los catálogos activos, agrupados por clave y ya ordenados.
  SELECT jsonb_object_agg(clave, items) INTO v_catalogos
    FROM (
      SELECT clave,
             jsonb_agg(
               jsonb_build_object(
                 'valor', valor, 'etiqueta', etiqueta,
                 'ayuda', ayuda, 'meta', meta)
               ORDER BY orden, etiqueta) AS items
        FROM public.catalogos
       WHERE activo
       GROUP BY clave
    ) t;

  RETURN jsonb_build_object(
    'soportada',      public.version_al_menos(p_version, v_min),
    'version_minima', v_min,
    'url_descarga',   v_url,
    'aviso',          v_aviso,
    'flags',          COALESCE(v_flags, '{}'::jsonb),
    'catalogos',      COALESCE(v_catalogos, '{}'::jsonb)
  );
END;
$$;

-- Sin sesión a propósito: el bloqueo por versión tiene que poder evaluarse
-- antes de que nadie inicie sesión.
GRANT EXECUTE ON FUNCTION public.arranque_app(text, text) TO anon, authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 5) tracking_pasos() ahora lee del catálogo
--    Se creó en la migración anterior con la lista fija. Se reemplaza para que
--    tome los pasos del catálogo, con respaldo a los valores de siempre si el
--    catálogo estuviera vacío: así agregar un paso al seguimiento no obliga a
--    publicar dos apps.
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.tracking_pasos(p_recurso_tipo text)
RETURNS text[]
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_clave text := 'tracking_' || COALESCE(NULLIF(p_recurso_tipo, ''), 'camion');
  v_pasos text[];
BEGIN
  SELECT array_agg(valor ORDER BY orden) INTO v_pasos
    FROM public.catalogos WHERE clave = v_clave AND activo;

  IF v_pasos IS NOT NULL AND array_length(v_pasos, 1) >= 2 THEN
    RETURN v_pasos;
  END IF;

  -- Respaldo: si alguien vacía el catálogo por accidente, el cierre de
  -- servicios (registrar_evidencias comprueba el último paso) tiene que seguir
  -- funcionando.
  RETURN CASE p_recurso_tipo
    WHEN 'custodio' THEN ARRAY['Confirmado','Asignado','En ruta','En servicio','Finalizado']
    WHEN 'patio'    THEN ARRAY['Confirmado','Listo','Recibido','En almacenaje','Liberado']
    WHEN 'lavado'   THEN ARRAY['Confirmado','Recibido','En lavado','Control','Listo']
    ELSE                 ARRAY['Confirmado','En camino','En carga','En tránsito','Entregado']
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tracking_pasos(text) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 6) SEMILLAS
--    Son exactamente los valores que hoy están escritos dentro del código de
--    la web y de la app. Sembrarlos idénticos garantiza que encender esto no
--    cambie ni una opción de lo que el usuario ve hoy.
-- ══════════════════════════════════════════════════════════════════════════

-- Plazos de pago — js/pedidos.js y NuevaSolicitudViewModel.PLAZOS_PAGO
INSERT INTO public.catalogos (clave, valor, etiqueta, orden) VALUES
  ('plazo_pago', 'Anticipado',     'Anticipado',     1),
  ('plazo_pago', 'Contra entrega', 'Contra entrega', 2),
  ('plazo_pago', '15 días',        '15 días',        3),
  ('plazo_pago', '30 días',        '30 días',        4),
  ('plazo_pago', '45 días',        '45 días',        5),
  ('plazo_pago', '60 días',        '60 días',        6)
ON CONFLICT (clave, valor) DO NOTHING;

-- Tipos de contenedor
INSERT INTO public.catalogos (clave, valor, etiqueta, orden) VALUES
  ('tipo_contenedor', '20''',       '20 pies',           1),
  ('tipo_contenedor', '40''',       '40 pies',           2),
  ('tipo_contenedor', '40'' HC',    '40 pies High Cube', 3),
  ('tipo_contenedor', 'Reefer 20''','Reefer 20 pies',    4),
  ('tipo_contenedor', 'Reefer 40''','Reefer 40 pies',    5),
  ('tipo_contenedor', 'Open top',   'Open top',          6),
  ('tipo_contenedor', 'Flat rack',  'Flat rack',         7)
ON CONFLICT (clave, valor) DO NOTHING;

-- Categorías de carga. `meta.campos` dice qué pide cada una: es lo que hoy
-- está duplicado en NP_CARGA (js/pedidos.js) y en Formulario.pide* (Kotlin).
INSERT INTO public.catalogos (clave, valor, etiqueta, ayuda, orden, meta) VALUES
  ('categoria_carga', 'General', 'Carga general',
   'Tarimas, cajas, mercancía empacada', 1,
   '{"campos":["peso","tarimas","refri"]}'),
  ('categoria_carga', 'Consolidada', 'Consolidada',
   'Varios embarques en la misma unidad', 2,
   '{"campos":["peso","tarimas","bultos","refri"]}'),
  ('categoria_carga', 'Suelta', 'Carga suelta',
   'Granel, sacos, material sin empacar', 3,
   '{"campos":["peso","refri"]}'),
  ('categoria_carga', 'Sobredimensionada', 'Sobredimensionada',
   'Excede medidas o peso estándar', 4,
   '{"campos":["peso","dim"]}'),
  ('categoria_carga', 'Hazmat', 'Materiales peligrosos',
   'Requiere permiso y unidad certificada', 5,
   '{"campos":["peso","hazmat"]}'),
  ('categoria_carga', 'Contenerizada', 'Contenerizada',
   'Contenedor de 20 o 40 pies', 6,
   '{"campos":["contenedores","refri"]}')
ON CONFLICT (clave, valor) DO NOTHING;

-- Tipos de unidad — la lista que puede elegir el cliente si corrige la
-- recomendación del sistema.
INSERT INTO public.catalogos (clave, valor, etiqueta, orden) VALUES
  ('tipo_unidad', 'Camioneta 1.5 ton caja seca',      'Camioneta 1.5 ton',            1),
  ('tipo_unidad', 'Camioneta 3.5 ton caja seca',      'Camioneta 3.5 ton',            2),
  ('tipo_unidad', 'Rabón',                            'Rabón',                        3),
  ('tipo_unidad', 'Torton caja seca',                 'Torton caja seca',             4),
  ('tipo_unidad', 'Torton plataforma',                'Torton plataforma',            5),
  ('tipo_unidad', 'Full',                             'Full',                         6),
  ('tipo_unidad', 'Full porta contenedor 40/20',      'Full porta contenedor',        7),
  ('tipo_unidad', 'Sencillo porta contenedor 40/20',  'Sencillo porta contenedor',    8),
  ('tipo_unidad', 'Plataforma de 3 ejes (sobrepeso)', 'Plataforma 3 ejes',            9),
  ('tipo_unidad', 'Lowboy',                           'Lowboy / cama baja',          10),
  ('tipo_unidad', 'HAZMAT',                           'HAZMAT',                      11)
ON CONFLICT (clave, valor) DO NOTHING;

-- Pasos de seguimiento. `valor` es lo que se guarda en
-- reservaciones.tracking_estado; `etiqueta` es lo que se muestra.
INSERT INTO public.catalogos (clave, valor, etiqueta, orden, meta) VALUES
  ('tracking_camion', 'Confirmado',    'Confirmado',          1, '{"icono":"✅"}'),
  ('tracking_camion', 'En camino',     'En camino al origen', 2, '{"icono":"🚛"}'),
  ('tracking_camion', 'En carga',      'En carga',            3, '{"icono":"⚓"}'),
  ('tracking_camion', 'En tránsito',   'En tránsito',         4, '{"icono":"📍"}'),
  ('tracking_camion', 'Entregado',     'Entregado',           5, '{"icono":"✓"}'),

  ('tracking_custodio', 'Confirmado',  'Confirmado',          1, '{"icono":"✅"}'),
  ('tracking_custodio', 'Asignado',    'Custodio asignado',   2, '{"icono":"👮"}'),
  ('tracking_custodio', 'En ruta',     'En ruta al punto',    3, '{"icono":"🚗"}'),
  ('tracking_custodio', 'En servicio', 'En servicio',         4, '{"icono":"🛡️"}'),
  ('tracking_custodio', 'Finalizado',  'Servicio finalizado', 5, '{"icono":"✓"}'),

  ('tracking_patio', 'Confirmado',     'Confirmado',          1, '{"icono":"✅"}'),
  ('tracking_patio', 'Listo',          'Patio listo',         2, '{"icono":"🏭"}'),
  ('tracking_patio', 'Recibido',       'Vehículo recibido',   3, '{"icono":"🚗"}'),
  ('tracking_patio', 'En almacenaje',  'En almacenaje',       4, '{"icono":"📦"}'),
  ('tracking_patio', 'Liberado',       'Vehículo liberado',   5, '{"icono":"✓"}'),

  ('tracking_lavado', 'Confirmado',    'Confirmado',          1, '{"icono":"✅"}'),
  ('tracking_lavado', 'Recibido',      'Vehículo recibido',   2, '{"icono":"🚗"}'),
  ('tracking_lavado', 'En lavado',     'En proceso de lavado',3, '{"icono":"🚿"}'),
  ('tracking_lavado', 'Control',       'Control de calidad',  4, '{"icono":"🔍"}'),
  ('tracking_lavado', 'Listo',         'Listo para entrega',  5, '{"icono":"✓"}')
ON CONFLICT (clave, valor) DO NOTHING;

-- ── Configuración inicial ─────────────────────────────────────────────────
-- Versión mínima en 0.0.0: NO bloquea a nadie. Se sube el día que de verdad
-- haga falta forzar una actualización. Dejarlo en la versión actual desde el
-- principio es la forma más fácil de dejar fuera a todo el mundo por error.
INSERT INTO public.app_config (clave, valor, descripcion) VALUES
  ('version_minima_android',
   '{"version":"0.0.0","url":"https://play.google.com/store/apps/details?id=mx.portgo.app"}',
   'Versión mínima soportada en Android. Subirla bloquea las anteriores en el arranque.'),
  ('version_minima_ios',
   '{"version":"0.0.0","url":"https://apps.apple.com/app/portgo"}',
   'Versión mínima soportada en iOS.'),
  ('aviso_global',
   'null',
   'Mensaje que la app muestra al arrancar. Formato: {"titulo":"…","mensaje":"…","tipo":"info|alerta"}. null para no mostrar nada.'),
  ('flags',
   '{}',
   'Interruptores de funciones. Permite enviar código apagado y encenderlo sin publicar una versión.')
ON CONFLICT (clave) DO NOTHING;
