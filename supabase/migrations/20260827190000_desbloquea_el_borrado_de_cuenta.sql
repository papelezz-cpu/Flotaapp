-- ============================================================================
-- Desbloquea el borrado de cuenta
-- ============================================================================
-- Al probar un borrado real contra portgo-pruebas aparecio que NO FUNCIONA:
--
--   ERROR: update or delete on table "users" violates foreign key constraint
--          "ofertas_admin_id_fkey" on table "ofertas"
--
-- Seis claves foraneas apuntan a auth.users sin regla de borrado (NO ACTION),
-- asi que bloquean. Medido en produccion: solo 5 de las 12 cuentas se pueden
-- borrar — fallan 2 de las 3 empresas y 4 de los 6 clientes. El boton de
-- eliminar usuario (js/usuarios.js -> gestionar-usuario) lleva roto desde
-- siempre para cualquier cuenta con actividad.
--
-- No es un efecto de los cambios de esta auditoria: esas FK vienen del
-- esquema original. Lo que hizo esta migracion fue destaparlo, porque hasta
-- ahora nadie habia probado el borrado de una cuenta con movimiento.
--
-- Se aplica el mismo criterio ya decidido para la flota y las reservaciones:
-- conservar el historial. La oferta y la solicitud sobreviven al borrado de su
-- autor, y no quedan anonimas — ofertas.admin_nombre y pedidos.cliente_nombre
-- / cliente_email ya guardan el dato desnormalizado. Es justo el caso para el
-- que esa desnormalizacion sirve.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. ofertas.admin_id
-- ─────────────────────────────────────────────────────────────────────────
-- Obligatorio mientras la oferta esta viva; opcional una vez resuelta.
ALTER TABLE public.ofertas ALTER COLUMN admin_id DROP NOT NULL;

ALTER TABLE public.ofertas DROP CONSTRAINT IF EXISTS ofertas_admin_id_fkey;
ALTER TABLE public.ofertas
  ADD CONSTRAINT ofertas_admin_id_fkey
  FOREIGN KEY (admin_id) REFERENCES public.perfiles(user_id) ON DELETE SET NULL;

ALTER TABLE public.ofertas DROP CONSTRAINT IF EXISTS ofertas_admin_presente;
ALTER TABLE public.ofertas
  ADD CONSTRAINT ofertas_admin_presente
  CHECK (estado IN ('aceptada', 'rechazada') OR admin_id IS NOT NULL);


-- ─────────────────────────────────────────────────────────────────────────
-- 2. pedidos.cliente_id
-- ─────────────────────────────────────────────────────────────────────────
-- El NOT NULL que se puso el 2026-08-27 en la Fase 4 era correcto en su
-- intencion —el vinculo real no puede ser mas opcional que su copia
-- desnormalizada— pero impide que la solicitud sobreviva al borrado de la
-- cuenta. Se sustituye por un CHECK que exige lo mismo mientras la solicitud
-- esta viva, que es cuando de verdad hace falta.
ALTER TABLE public.pedidos ALTER COLUMN cliente_id DROP NOT NULL;

ALTER TABLE public.pedidos DROP CONSTRAINT IF EXISTS pedidos_cliente_id_fkey;
ALTER TABLE public.pedidos
  ADD CONSTRAINT pedidos_cliente_id_fkey
  FOREIGN KEY (cliente_id) REFERENCES public.perfiles(user_id) ON DELETE SET NULL;

ALTER TABLE public.pedidos DROP CONSTRAINT IF EXISTS pedidos_cliente_presente;
ALTER TABLE public.pedidos
  ADD CONSTRAINT pedidos_cliente_presente
  CHECK (estado IN ('finalizado', 'cancelado', 'expirado', 'rechazado')
         OR cliente_id IS NOT NULL);


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Las cuatro columnas de auditoria "quien lo hizo"
-- ─────────────────────────────────────────────────────────────────────────
-- Ya son nullable y sus tablas estan vacias o son minimas. Guardan quien
-- realizo una accion; que ese usuario desaparezca no debe borrar el registro
-- de la accion, solo su autor.
ALTER TABLE public.documentos_fiscales DROP CONSTRAINT IF EXISTS documentos_fiscales_emitido_por_fkey;
ALTER TABLE public.documentos_fiscales
  ADD CONSTRAINT documentos_fiscales_emitido_por_fkey
  FOREIGN KEY (emitido_por) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.documentos_fiscales DROP CONSTRAINT IF EXISTS documentos_fiscales_cancelado_por_fkey;
ALTER TABLE public.documentos_fiscales
  ADD CONSTRAINT documentos_fiscales_cancelado_por_fkey
  FOREIGN KEY (cancelado_por) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.pagos DROP CONSTRAINT IF EXISTS pagos_registrado_por_fkey;
ALTER TABLE public.pagos
  ADD CONSTRAINT pagos_registrado_por_fkey
  FOREIGN KEY (registrado_por) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.reservaciones_historico DROP CONSTRAINT IF EXISTS reservaciones_historico_archivado_por_fkey;
ALTER TABLE public.reservaciones_historico
  ADD CONSTRAINT reservaciones_historico_archivado_por_fkey
  FOREIGN KEY (archivado_por) REFERENCES auth.users(id) ON DELETE SET NULL;


-- ─────────────────────────────────────────────────────────────────────────
-- 4. El guard de flota tiene que dejar pasar la cascada
-- ─────────────────────────────────────────────────────────────────────────
-- Quitadas las FK bloqueantes, el borrado seguia fallando:
--
--   ERROR: No autorizado: no puedes transferir la propiedad de este recurso
--   CONTEXTO: guard_fleet_resource_update()
--             UPDATE ONLY "camiones" SET "propietario_id" = NULL
--
-- El guard ve cambiar propietario_id y lo trata como una transferencia. Y
-- tiene razon en el caso general: nadie debe poder pasarle su camion a otro.
-- Pero una cascada de borrado no es una transferencia, es una orfandad.
--
-- La excepcion se acota al maximo: solo se permite cuando propietario_id pasa
-- a NULL Y el perfil anterior YA NO EXISTE. Durante la cascada, la fila de
-- perfiles ya se borro cuando este trigger corre, asi que la condicion se
-- cumple. Un usuario con sesion no puede fingirla: su propio perfil existe,
-- de modo que sigue sin poder dejar su recurso sin dueño.
--
-- No se usa `auth.uid() IS NULL` como condicion, que seria lo comodo: eso
-- abriria la puerta a cualquier contexto sin sesion, no solo a la cascada.
CREATE OR REPLACE FUNCTION public.guard_fleet_resource_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $fn$
BEGIN
  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  -- Orfandad por borrado de cuenta: el dueño anterior ya no existe.
  IF NEW.propietario_id IS NULL
     AND OLD.propietario_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.perfiles WHERE user_id = OLD.propietario_id) THEN
    RETURN NEW;
  END IF;

  IF NEW.aprobacion IS DISTINCT FROM OLD.aprobacion AND NEW.aprobacion IS DISTINCT FROM 'pendiente' THEN
    RAISE EXCEPTION 'No autorizado: solo un superadmin puede aprobar o rechazar este recurso';
  END IF;

  IF NEW.propietario_id IS DISTINCT FROM OLD.propietario_id THEN
    RAISE EXCEPTION 'No autorizado: no puedes transferir la propiedad de este recurso';
  END IF;

  RETURN NEW;
END;
$fn$;


-- ─────────────────────────────────────────────────────────────────────────
-- 5. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
DO $$
DECLARE bloqueantes integer; detalle text;
BEGIN
  SELECT count(*), string_agg(conrelid::regclass::text||'.'||conname, ', ' ORDER BY conname)
    INTO bloqueantes, detalle
    FROM pg_constraint
   WHERE contype = 'f' AND connamespace = 'public'::regnamespace
     AND confrelid = 'auth.users'::regclass
     AND confdeltype = 'a';   -- NO ACTION

  IF bloqueantes > 0 THEN
    RAISE EXCEPTION 'Siguen bloqueando el borrado % FK: %', bloqueantes, detalle;
  END IF;
  RAISE NOTICE 'Verificado: ninguna FK hacia auth.users bloquea el borrado de cuenta.';
END $$;
