-- Corrige dos desajustes de tipo en guardar_camion.
--
-- La funcion original insertaba texto en `capacidad` (integer NOT NULL) y un
-- text[] en `archivos` (jsonb). Postgres respondia con "column is of type ...
-- but expression is of type ...: You will need to rewrite or cast the
-- expression", asi que el alta de unidad desde la app nunca llego a guardar
-- nada.
--
-- Se coló porque al escribir la migracion verifique que cada columna existiera
-- y que ninguna NOT NULL sin default quedara vacia, pero NO compare los tipos
-- de cada expresion contra la columna destino. La verificacion parecia
-- completa y le faltaba justo la dimension que importaba.
--
-- `capacidad` ademas es NOT NULL: se valida antes con un mensaje legible, en
-- vez de dejar que salte la constraint.

-- Convierte un array JSON a jsonb, para columnas jsonb. Es el par de
-- `_lista_de`, que devuelve text[] y sirve para columnas text[].
CREATE OR REPLACE FUNCTION public._jsonb_lista_de(p jsonb, clave text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT CASE
    WHEN jsonb_typeof(p -> clave) = 'array' THEN p -> clave
    ELSE NULL
  END
$fn$;

REVOKE ALL ON FUNCTION public._jsonb_lista_de(jsonb, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.guardar_camion(
  p_datos jsonb,
  p_id    text DEFAULT NULL   -- null = alta; con valor = edición
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_id     text;
  v_tipo   text;
  v_existe boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  v_id   := COALESCE(p_id, public._texto_de(p_datos, 'id'));
  v_tipo := public._texto_de(p_datos, 'tipo');

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Falta el número económico de la unidad.';
  END IF;
  IF v_tipo IS NULL THEN
    RAISE EXCEPTION 'Falta el tipo de unidad.';
  END IF;
  -- capacidad es NOT NULL en la tabla. Sin esto el fallo llega como una
  -- violacion de constraint, que no le dice nada a quien esta en el patio.
  IF public._entero_de(p_datos, 'capacidad') IS NULL THEN
    RAISE EXCEPTION 'Falta la capacidad de la unidad, en toneladas enteras.';
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.camiones WHERE id = v_id) INTO v_existe;

  -- Al editar hay que ser el dueño. El guard de flota lo vuelve a verificar,
  -- pero aquí el mensaje es entendible en vez de un error de trigger.
  IF v_existe AND NOT EXISTS (
    SELECT 1 FROM public.camiones WHERE id = v_id AND propietario_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Esa unidad ya existe y no es tuya. Usa otro número económico.';
  END IF;

  IF v_existe THEN
    UPDATE public.camiones SET
      tipo             = v_tipo,
      capacidad        = public._entero_de(p_datos, 'capacidad'),
      placas           = public._texto_de(p_datos, 'placas'),
      tipo_placa       = public._texto_de(p_datos, 'tipo_placa'),
      marca            = public._texto_de(p_datos, 'marca'),
      version          = public._texto_de(p_datos, 'version'),
      modelo_anio      = public._entero_de(p_datos, 'modelo_anio'),
      color            = public._texto_de(p_datos, 'color'),
      num_serie        = public._texto_de(p_datos, 'num_serie'),
      num_motor        = public._texto_de(p_datos, 'num_motor'),
      num_economico    = COALESCE(public._texto_de(p_datos, 'num_economico'), v_id),
      tipo_combustible = public._texto_de(p_datos, 'tipo_combustible'),
      dimensiones      = public._texto_de(p_datos, 'dimensiones'),
      precio_dia       = public._numero_de(p_datos, 'precio_dia'),
      tarjeta_circulacion  = public._texto_de(p_datos, 'tarjeta_circulacion'),
      fecha_expedicion_tc  = public._fecha_de(p_datos, 'fecha_expedicion_tc'),
      fecha_vencimiento_tc = public._fecha_de(p_datos, 'fecha_vencimiento_tc'),
      fecha_vencimiento_seguro      = public._fecha_de(p_datos, 'fecha_vencimiento_seguro'),
      fecha_vencimiento_permiso_sct = public._fecha_de(p_datos, 'fecha_vencimiento_permiso_sct'),
      caat                = public._texto_de(p_datos, 'caat'),
      vigencia_caat       = public._fecha_de(p_datos, 'vigencia_caat'),
      fecha_vencimiento_verificacion = public._fecha_de(p_datos, 'fecha_vencimiento_verificacion'),
      fecha_vencimiento_permiso_peligrosa = public._fecha_de(p_datos, 'fecha_vencimiento_permiso_peligrosa'),
      -- Los archivos solo se pisan si vienen: al editar sin volver a
      -- fotografiar, se conservan los que ya estaban.
      imagen_tc  = COALESCE(public._texto_de(p_datos, 'imagen_tc'), imagen_tc),
      doc_sct    = COALESCE(public._texto_de(p_datos, 'doc_sct'), doc_sct),
      doc_seguro = COALESCE(public._texto_de(p_datos, 'doc_seguro'), doc_seguro),
      doc_permiso_peligrosa = COALESCE(
        public._texto_de(p_datos, 'doc_permiso_peligrosa'), doc_permiso_peligrosa),
      archivos   = COALESCE(public._jsonb_lista_de(p_datos, 'archivos'), archivos),
      tipo_carga = COALESCE(public._lista_de(p_datos, 'tipo_carga'), tipo_carga),
      -- Toda edición vuelve a revisión y limpia el rechazo anterior.
      aprobacion   = 'pendiente',
      rechazo_nota = NULL
    WHERE id = v_id;
  ELSE
    INSERT INTO public.camiones (
      id, propietario_id, tipo, capacidad, estado, emoji, aprobacion,
      placas, tipo_placa, marca, version, modelo_anio, color,
      num_serie, num_motor, num_economico, tipo_combustible,
      dimensiones, precio_dia, tipo_carga,
      tarjeta_circulacion, fecha_expedicion_tc, fecha_vencimiento_tc,
      fecha_vencimiento_seguro, fecha_vencimiento_permiso_sct,
      caat, vigencia_caat, fecha_vencimiento_verificacion,
      imagen_tc, doc_sct, doc_seguro,
      doc_permiso_peligrosa, fecha_vencimiento_permiso_peligrosa,
      archivos
    ) VALUES (
      v_id, auth.uid(), v_tipo,
      public._entero_de(p_datos, 'capacidad'),
      'disponible',
      COALESCE(public._texto_de(p_datos, 'emoji'), '🚛'),
      'pendiente',
      public._texto_de(p_datos, 'placas'),
      public._texto_de(p_datos, 'tipo_placa'),
      public._texto_de(p_datos, 'marca'),
      public._texto_de(p_datos, 'version'),
      public._entero_de(p_datos, 'modelo_anio'),
      public._texto_de(p_datos, 'color'),
      public._texto_de(p_datos, 'num_serie'),
      public._texto_de(p_datos, 'num_motor'),
      COALESCE(public._texto_de(p_datos, 'num_economico'), v_id),
      public._texto_de(p_datos, 'tipo_combustible'),
      public._texto_de(p_datos, 'dimensiones'),
      public._numero_de(p_datos, 'precio_dia'),
      public._lista_de(p_datos, 'tipo_carga'),
      public._texto_de(p_datos, 'tarjeta_circulacion'),
      public._fecha_de(p_datos, 'fecha_expedicion_tc'),
      public._fecha_de(p_datos, 'fecha_vencimiento_tc'),
      public._fecha_de(p_datos, 'fecha_vencimiento_seguro'),
      public._fecha_de(p_datos, 'fecha_vencimiento_permiso_sct'),
      public._texto_de(p_datos, 'caat'),
      public._fecha_de(p_datos, 'vigencia_caat'),
      public._fecha_de(p_datos, 'fecha_vencimiento_verificacion'),
      public._texto_de(p_datos, 'imagen_tc'),
      public._texto_de(p_datos, 'doc_sct'),
      public._texto_de(p_datos, 'doc_seguro'),
      public._texto_de(p_datos, 'doc_permiso_peligrosa'),
      public._fecha_de(p_datos, 'fecha_vencimiento_permiso_peligrosa'),
      COALESCE(public._jsonb_lista_de(p_datos, 'archivos'), '[]'::jsonb)
    );
  END IF;

  PERFORM public.notificar_superadmins(
    'nueva_unidad_pendiente',
    'Unidad pendiente de revisión',
    public.mi_nombre() || ' ' || CASE WHEN v_existe THEN 'editó' ELSE 'dio de alta' END
      || ' la unidad ' || v_id || ' (' || v_tipo || '). Revísala en Pendientes.');

  RETURN v_id;
END;
$fn$;
