-- ──────────────────────────────────────────────────────────────────────────
-- ALTA DE FLOTA DESDE LAS APPS
--
-- Hasta ahora dar de alta una unidad o un chofer solo se podía desde la web.
-- El supuesto era que es "un trámite de escritorio que se hace una vez", y era
-- equivocado: quien recibe una unidad nueva está en el patio, junto al camión,
-- sin computadora. El trámite no se pospone — simplemente no ocurre.
--
-- En el teléfono además queda mejor que en la web: la tarjeta de circulación se
-- fotografía ahí mismo en vez de buscar un escaneo.
--
-- Por qué RPC y no un INSERT directo:
--
--   · El alta de operador escribe TRES cosas que van juntas: el operador, el
--     consentimiento de datos sensibles y el aviso al superadmin. El
--     consentimiento es obligación legal (ver migración 20260728160000): si se
--     pierde porque falló una escritura intermedia, queda un expediente de
--     datos sensibles sin la constancia que lo respalda.
--
--   · Fuerzan propietario_id = auth.uid() y aprobacion = 'pendiente'. Nadie da
--     de alta una unidad a nombre de otro ni nace aprobada.
--
-- Los archivos se suben a Storage ANTES y aquí solo viajan sus rutas: subir
-- ocho fotos por la red de un puerto puede tardar, y no conviene tener una
-- transacción abierta todo ese rato.
-- ──────────────────────────────────────────────────────────────────────────

-- Lee una fecha de un jsonb tolerando cadenas vacías, que es lo que mandan los
-- formularios cuando el campo se deja en blanco.
CREATE OR REPLACE FUNCTION public._fecha_de(p jsonb, clave text)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
BEGIN
  RETURN NULLIF(btrim(COALESCE(p ->> clave, '')), '')::date;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$fn$;

CREATE OR REPLACE FUNCTION public._texto_de(p jsonb, clave text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $fn$ SELECT NULLIF(btrim(COALESCE(p ->> clave, '')), '') $fn$;

CREATE OR REPLACE FUNCTION public._entero_de(p jsonb, clave text)
RETURNS int
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
BEGIN
  RETURN NULLIF(btrim(COALESCE(p ->> clave, '')), '')::int;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$fn$;

CREATE OR REPLACE FUNCTION public._numero_de(p jsonb, clave text)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
BEGIN
  RETURN NULLIF(btrim(COALESCE(p ->> clave, '')), '')::numeric;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$fn$;

-- Convierte un arreglo jsonb de textos a text[]; NULL si viene vacío.
CREATE OR REPLACE FUNCTION public._lista_de(p jsonb, clave text)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT NULLIF(
    ARRAY(SELECT jsonb_array_elements_text(
            CASE WHEN jsonb_typeof(p -> clave) = 'array'
                 THEN p -> clave ELSE '[]'::jsonb END)),
    ARRAY[]::text[])
$fn$;


-- Los helpers son de uso interno de las dos funciones de abajo. Se cierran para
-- que PostgREST no los publique como endpoints: no exponen datos, pero cada
-- funcion visible en el esquema publico es superficie que alguien tiene que
-- revisar despues.
REVOKE ALL ON FUNCTION public._fecha_de(jsonb, text)  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._texto_de(jsonb, text)  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._entero_de(jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._numero_de(jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._lista_de(jsonb, text)  FROM PUBLIC, anon, authenticated;

-- ══════════════════════════════════════════════════════════════════════════
-- ALTA / EDICIÓN DE UNIDAD
-- ══════════════════════════════════════════════════════════════════════════
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
      capacidad        = public._texto_de(p_datos, 'capacidad'),
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
      archivos   = COALESCE(public._lista_de(p_datos, 'archivos'), archivos),
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
      public._texto_de(p_datos, 'capacidad'),
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
      public._lista_de(p_datos, 'archivos')
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

REVOKE ALL ON FUNCTION public.guardar_camion(jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.guardar_camion(jsonb, text) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- ALTA DE OPERADOR
--
-- Escribe tres cosas que van juntas. La del medio es la que importa: la
-- empresa declara que tiene el consentimiento del operador para tratar sus
-- datos sensibles (examen médico, toxicológico, antecedentes). Sin esa
-- constancia, el expediente queda sin respaldo legal.
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.alta_operador(
  p_datos         jsonb,
  p_version_aviso text DEFAULT 'borrador-0'
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_id     text;
  v_nombre text;
  v_curp   text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  v_nombre := public._texto_de(p_datos, 'nombre');
  v_curp   := public._texto_de(p_datos, 'curp');

  IF v_nombre IS NULL THEN
    RAISE EXCEPTION 'Falta el nombre del operador.';
  END IF;
  IF v_curp IS NULL THEN
    RAISE EXCEPTION 'El CURP es obligatorio.';
  END IF;

  -- Mismo CURP dos veces en la misma empresa es un alta duplicada.
  IF EXISTS (
    SELECT 1 FROM public.operadores
     WHERE propietario_id = auth.uid() AND curp = v_curp
  ) THEN
    RAISE EXCEPTION 'Ya tienes un operador registrado con ese CURP.';
  END IF;

  v_id := COALESCE(
    public._texto_de(p_datos, 'id'),
    'OP-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8)));

  INSERT INTO public.operadores (
    id, propietario_id, curp, nombre, primer_apellido, segundo_apellido,
    sexo, rfc, nss, tipo_sanguineo, num_trabajador, nivel_estudio,
    correo, telefono, area, puesto,
    fecha_examen_medico, fecha_examen_toxicologico, fecha_carta_antecedentes,
    doc_examen_medico, doc_examen_toxicologico, doc_carta_antecedentes,
    num_licencia, clase_licencia, tipo_licencia,
    fecha_expedicion, fecha_vencimiento,
    foto_operador, foto_licencia, aprobacion
  ) VALUES (
    v_id, auth.uid(), v_curp, v_nombre,
    public._texto_de(p_datos, 'primer_apellido'),
    public._texto_de(p_datos, 'segundo_apellido'),
    public._texto_de(p_datos, 'sexo'),
    public._texto_de(p_datos, 'rfc'),
    public._texto_de(p_datos, 'nss'),
    public._texto_de(p_datos, 'tipo_sanguineo'),
    public._texto_de(p_datos, 'num_trabajador'),
    public._texto_de(p_datos, 'nivel_estudio'),
    public._texto_de(p_datos, 'correo'),
    public._texto_de(p_datos, 'telefono'),
    public._texto_de(p_datos, 'area'),
    public._texto_de(p_datos, 'puesto'),
    public._fecha_de(p_datos, 'fecha_examen_medico'),
    public._fecha_de(p_datos, 'fecha_examen_toxicologico'),
    public._fecha_de(p_datos, 'fecha_carta_antecedentes'),
    public._texto_de(p_datos, 'doc_examen_medico'),
    public._texto_de(p_datos, 'doc_examen_toxicologico'),
    public._texto_de(p_datos, 'doc_carta_antecedentes'),
    public._texto_de(p_datos, 'num_licencia'),
    public._texto_de(p_datos, 'clase_licencia'),
    public._texto_de(p_datos, 'tipo_licencia'),
    public._fecha_de(p_datos, 'fecha_expedicion'),
    public._fecha_de(p_datos, 'fecha_vencimiento'),
    public._texto_de(p_datos, 'foto_operador'),
    public._texto_de(p_datos, 'foto_licencia'),
    'pendiente'
  );

  -- La constancia. Va en la MISMA transacción a propósito: un expediente de
  -- datos sensibles sin la declaración que lo ampara no debe poder existir.
  INSERT INTO public.consentimientos (user_id, tipo, version, contexto, referencia)
  VALUES (auth.uid(), 'datos_sensibles_operador', p_version_aviso, 'alta_operador', v_id);

  PERFORM public.notificar_superadmins(
    'nuevo_recurso_pendiente',
    'Operador pendiente de revisión',
    public.mi_nombre() || ' dio de alta al operador ' || v_nombre
      || '. Revísalo en Pendientes.');

  RETURN v_id;
END;
$fn$;

REVOKE ALL ON FUNCTION public.alta_operador(jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.alta_operador(jsonb, text) TO authenticated;
