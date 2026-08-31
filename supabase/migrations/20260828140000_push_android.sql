-- ============================================================================
-- Notificaciones push: el lado de la base
-- ============================================================================
--
-- ── Qué problema resuelve, y cuál NO ──────────────────────────────────────
--
-- La campana ya avisa en tiempo real: notificaciones esta publicada y los dos
-- clientes se suscriben con filtro por user_id. Eso cubre el caso "app
-- abierta" y funciona hoy.
--
-- Lo que NO cubre es "app cerrada", que hoy solo llega por correo. En una
-- plataforma de pujas eso importa: quien oferta primero suele ganar, y un
-- transportista en patio ve un push pero no lee el correo hasta la noche.
--
-- ── Por qué se dispara desde el servidor ──────────────────────────────────
--
-- El correo se dispara desde el navegador (_notificarEmail, fire-and-forget).
-- Eso significa que si quien aprueba cierra la pestana a mitad, el aviso no
-- sale. Y que la regla de "a quien se notifica" vive en el cliente, con lo que
-- los tres clientes pueden divergir.
--
-- Aqui se hace al reves: un trigger sobre notificaciones. La fila de
-- notificaciones YA es la decision de a quien avisar —esta tomada en un solo
-- sitio y los tres clientes la comparten—, asi que el push se engancha ahi y
-- hereda esa decision sin duplicarla.
--
-- ── Trigger por SENTENCIA, no por fila ────────────────────────────────────
--
-- Las notificaciones se insertan en lote: medido en produccion, 1,9 de media
-- y hasta 8 de golpe (una por empresa con flota compatible). Un trigger FOR
-- EACH ROW haria 8 peticiones HTTP; uno FOR EACH STATEMENT con tabla de
-- transicion hace una.
--
-- ── No puede romper una insercion ─────────────────────────────────────────
--
-- net.http_post de pg_net es asincrono: encola la peticion y devuelve al
-- instante. No espera respuesta, no bloquea y no falla la transaccion. Ademas
-- el cuerpo del trigger va envuelto en un bloque con EXCEPTION que traga
-- cualquier error: una notificacion debe guardarse aunque el push falle.
--
-- ── Mientras no este configurado, no hace nada ────────────────────────────
--
-- Lee el destino de vault.decrypted_secrets. Si los secretos no existen —que
-- es el estado al aplicar esta migracion— el trigger sale sin hacer nada. Se
-- puede aplicar hoy sin efecto y activarlo despues creando los secretos.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. pg_net: peticiones HTTP asincronas desde la base
-- ─────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_net;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. Los dispositivos a los que enviar
-- ─────────────────────────────────────────────────────────────────────────
-- Un usuario puede tener varios: telefono y tablet, o haber reinstalado.
-- El token es de FCM y lo renueva Android por su cuenta, asi que la app lo
-- reenvia en cada arranque y aqui se hace UPSERT.
CREATE TABLE IF NOT EXISTS public.dispositivos_push (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES public.perfiles(user_id) ON DELETE CASCADE,
  token        text NOT NULL,
  plataforma   text NOT NULL DEFAULT 'android'
                 CHECK (plataforma IN ('android', 'ios', 'web')),
  modelo       text,
  creado_en    timestamptz NOT NULL DEFAULT now(),
  visto_en     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT dispositivos_push_token_key UNIQUE (token)
);

-- El envio busca por user_id; la limpieza de tokens muertos, por visto_en.
CREATE INDEX IF NOT EXISTS idx_dispositivos_push_user  ON public.dispositivos_push (user_id);
CREATE INDEX IF NOT EXISTS idx_dispositivos_push_visto ON public.dispositivos_push (visto_en);

ALTER TABLE public.dispositivos_push ENABLE ROW LEVEL SECURITY;

-- Cada quien gestiona sus propios dispositivos. Nadie lee los de otro: un
-- token de push es un identificador de dispositivo, no un dato publico.
DROP POLICY IF EXISTS dispositivos_push_propios ON public.dispositivos_push;
CREATE POLICY dispositivos_push_propios ON public.dispositivos_push
  FOR ALL TO authenticated
  USING      (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

-- Sin esto la tabla nace accesible para anon, por el ALTER DEFAULT PRIVILEGES
-- de Supabase (ver migracion 20260827160000).
REVOKE ALL ON public.dispositivos_push FROM anon;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Qué tipos merecen despertar un teléfono
-- ─────────────────────────────────────────────────────────────────────────
-- Hay 37 tipos de notificacion en produccion. Empujarlos todos entrena a
-- ignorar el push, que es el mismo error que el codigo ya evito con la campana
-- ("una empresa que solo tiene plataformas recibia aviso de cada torton").
--
-- La lista vive en `catalogos`, que es el patron del proyecto para listas
-- editables sin desplegar. Se siembra conservadora: solo lo que exige una
-- accion con ventana de tiempo. Anadir o quitar despues es un UPDATE.
INSERT INTO public.catalogos (clave, valor, etiqueta, ayuda, orden, activo)
VALUES
  ('push_tipos','nueva_solicitud',       'Nueva solicitud para ofertar', 'La empresa puede ofertar; llega primero quien responde antes', 1, true),
  ('push_tipos','nueva_oferta',          'Nueva oferta recibida',        'El cliente tiene una oferta que responder',                    2, true),
  ('push_tipos','respuesta_oferta',      'Respuesta a tu oferta',        'La empresa espera saber si la aceptaron',                      3, true),
  ('push_tipos','respuesta_contra_oferta','Respuesta a la contraoferta', NULL,                                                          4, true),
  ('push_tipos','acuerdo_aprobado',      'Acuerdo aprobado',             'El servicio arranca',                                          5, true),
  ('push_tipos','reserva_aceptada',      'Reserva aceptada',             NULL,                                                           6, true),
  ('push_tipos','cancelacion_solicitada','Cancelacion solicitada',       'Requiere resolucion del superadmin',                           7, true),
  ('push_tipos','cambio_reportado',      'Cambio o problema reportado',  'Algo salio mal en un servicio en curso',                        8, true),
  ('push_tipos','confirmar_lugar_hora',  'Confirmar lugar y hora',       NULL,                                                           9, true),
  ('push_tipos','documentos_solicitados','Documentos solicitados',       'Bloquea el ingreso a puerto',                                  10, true)
ON CONFLICT (clave, valor) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────────────
-- 4. El disparador
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enviar_push_de_notificaciones()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net', 'vault', 'pg_temp'
AS $fn$
DECLARE
  v_url   text;
  v_clave text;
  v_lote  jsonb;
BEGIN
  -- Destino y credencial. Si no estan configurados, esto no hace nada: es lo
  -- que permite aplicar la migracion antes de tener el proyecto de Firebase.
  SELECT decrypted_secret INTO v_url   FROM vault.decrypted_secrets WHERE name = 'push_endpoint';
  SELECT decrypted_secret INTO v_clave FROM vault.decrypted_secrets WHERE name = 'push_service_key';
  IF v_url IS NULL OR v_clave IS NULL THEN
    RETURN NULL;
  END IF;

  -- Solo los tipos marcados, y solo si el destinatario tiene algun dispositivo.
  -- Ese segundo filtro evita despertar a la Edge Function para usuarios que
  -- solo usan la web.
  SELECT jsonb_agg(jsonb_build_object(
           'user_id', n.user_id,
           'tipo',    n.tipo,
           'titulo',  n.titulo,
           'mensaje', n.mensaje,
           'meta',    n.meta))
    INTO v_lote
    FROM nuevas n
   WHERE EXISTS (SELECT 1 FROM public.catalogos c
                  WHERE c.clave = 'push_tipos' AND c.valor = n.tipo AND c.activo)
     AND EXISTS (SELECT 1 FROM public.dispositivos_push d WHERE d.user_id = n.user_id);

  IF v_lote IS NULL THEN
    RETURN NULL;
  END IF;

  -- Asincrono: encola y devuelve. No espera respuesta ni bloquea el INSERT.
  PERFORM net.http_post(
    url     := v_url,
    body    := jsonb_build_object('notificaciones', v_lote),
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || v_clave),
    timeout_milliseconds := 5000
  );

  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  -- Una notificacion tiene que guardarse aunque el push falle. Nunca se
  -- propaga el error a la transaccion que la inserto.
  RAISE WARNING 'push omitido: %', SQLERRM;
  RETURN NULL;
END;
$fn$;

REVOKE ALL ON FUNCTION public.enviar_push_de_notificaciones() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_enviar_push ON public.notificaciones;
CREATE TRIGGER trg_enviar_push
  AFTER INSERT ON public.notificaciones
  REFERENCING NEW TABLE AS nuevas
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.enviar_push_de_notificaciones();


-- ─────────────────────────────────────────────────────────────────────────
-- 5. Limpieza de tokens muertos
-- ─────────────────────────────────────────────────────────────────────────
-- Un token deja de valer cuando el usuario desinstala o limpia los datos de la
-- app. FCM responde con NotRegistered, y la Edge Function borra ese token. Esto
-- es la red por si esa via falla: un dispositivo que no aparece en seis meses
-- ya no existe.
CREATE OR REPLACE FUNCTION public.purgar_dispositivos_inactivos(p_dias integer DEFAULT 180)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v_n integer;
BEGIN
  IF p_dias < 30 THEN
    RAISE EXCEPTION 'Retencion demasiado corta (% dias). El minimo son 30.', p_dias;
  END IF;
  DELETE FROM public.dispositivos_push
   WHERE visto_en < now() - make_interval(days => p_dias);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$fn$;

REVOKE ALL ON FUNCTION public.purgar_dispositivos_inactivos(integer) FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule('purgar-dispositivos')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purgar-dispositivos');
  PERFORM cron.schedule('purgar-dispositivos', '30 3 1 * *',
                        'SELECT public.purgar_dispositivos_inactivos()');
END $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 6. Comprobación
-- ─────────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_tipos integer; v_configurado boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_enviar_push') THEN
    RAISE EXCEPTION 'El trigger de push no quedo instalado';
  END IF;
  IF has_table_privilege('anon', 'public.dispositivos_push', 'SELECT') THEN
    RAISE EXCEPTION 'dispositivos_push quedo accesible para anon';
  END IF;

  SELECT count(*) INTO v_tipos FROM public.catalogos WHERE clave = 'push_tipos' AND activo;
  SELECT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'push_endpoint')
    INTO v_configurado;

  RAISE NOTICE 'Verificado. Tipos con push: %. Configurado: %.',
               v_tipos,
               CASE WHEN v_configurado THEN 'si, ya envia'
                    ELSE 'NO todavia - el trigger no hace nada hasta crear los secretos' END;
END $$;
