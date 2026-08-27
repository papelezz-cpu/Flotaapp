-- ============================================================================
-- FASE 4 — cierre de la exposicion a anon y borrado de cuenta coherente
-- ============================================================================
--
-- ── 1. FUGA REAL, VERIFICADA EN PRODUCCION ────────────────────────────────
--
-- of_select estaba como USING (true) y SIN clausula TO, asi que alcanzaba al
-- rol `anon`. Como anon ademas tiene SELECT sobre la tabla, cualquier persona
-- con la clave anon —que viaja en js/config.js y es publica por diseño— podia
-- leer TODAS las ofertas sin iniciar sesion. Comprobado contra produccion por
-- REST el 2026-08-27: HTTP 200 y 34 filas con nombre de empresa, precio_oferta
-- y contra_precio.
--
-- Lo mismo, en menor grado, con custodios, patios y lavados: sus politicas
-- *_public_read tampoco tienen TO, asi que anon veia el catalogo completo con
-- precios y ubicaciones.
--
-- camiones, reservaciones y operadores se salvaban POR ACCIDENTE: sus
-- politicas llaman a is_superadmin(), que esta revocada para anon, asi que la
-- consulta falla en vez de devolver filas. Eso no es una defensa, es una
-- casualidad — basta que alguien conceda esa funcion para que se abran. Se
-- les pone el TO authenticated explicito igual que a las demas.
--
-- ── 2. BORRADO DE CUENTA ──────────────────────────────────────────────────
--
-- La app borra cuentas (js/usuarios.js -> gestionar-usuario ->
-- auth.admin.deleteUser), y hoy cada tipo de recurso reacciona distinto:
--
--   camiones    SET NULL  -> sobrevive huerfano
--   operadores  CASCADE   -> se borra
--   custodios   CASCADE y SET NULL a la vez -> gana el CASCADE, se borra
--   patios      idem
--   lavados     idem
--
-- Decision: conservar la flota sin dueño, como ya hacian los camiones. Asi el
-- historial no se rompe. F-303 es el ejemplo de lo contrario: una reservacion
-- completada que ya no puede decir que unidad hizo el viaje.
--
-- Los recursos sin dueño se ocultan del catalogo desde el cliente (ver el
-- cambio en js/camiones.js y js/recursos.js del mismo lote).
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. ofertas: solo las partes implicadas
-- ─────────────────────────────────────────────────────────────────────────
--
-- OJO CON LA RECURSION. El primer intento puso un EXISTS contra `pedidos`
-- dentro de la politica de `ofertas`. Eso rompe las dos tablas:
--
--   "infinite recursion detected in policy for relation ofertas"
--
-- porque ped_select ya contiene un EXISTS contra `ofertas`, asi que cada una
-- necesita evaluar la politica de la otra. Se detecto al comparar la huella
-- de visibilidad antes y despues: ofertas y pedidos quedaron ilegibles para
-- los tres roles con sesion.
--
-- La salida es la que ya usa el resto del esquema (is_superadmin,
-- puede_notificar, participa_en_expediente): una funcion SECURITY DEFINER.
-- Al no evaluar RLS por dentro, corta el ciclo.
CREATE OR REPLACE FUNCTION public.es_mi_pedido(p_pedido_id uuid) RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT EXISTS (SELECT 1 FROM public.pedidos p
                  WHERE p.id = p_pedido_id AND p.cliente_id = auth.uid());
$fn$;

-- Sin esto nace ejecutable por anon: los dos proyectos tienen ALTER DEFAULT
-- PRIVILEGES concediendo EXECUTE sobre toda funcion nueva de public.
REVOKE ALL   ON FUNCTION public.es_mi_pedido(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.es_mi_pedido(uuid) TO authenticated;

-- ALTER en vez de DROP+CREATE: no se elimina la politica, solo cambia su
-- expresion y los roles a los que aplica.
ALTER POLICY of_select ON public.ofertas
  TO authenticated
  USING (
    -- la empresa que oferto
    admin_id = (SELECT auth.uid())
    -- el cliente dueño de la solicitud
    OR (SELECT public.es_mi_pedido(ofertas.pedido_id))
    OR (SELECT public.is_superadmin())
  );


-- ─────────────────────────────────────────────────────────────────────────
-- 2. Catalogo de flota: visible para quien tenga sesion, no para internet
-- ─────────────────────────────────────────────────────────────────────────
ALTER POLICY camiones_public_read  ON public.camiones  TO authenticated USING (aprobacion = 'aprobada');
ALTER POLICY custodios_public_read ON public.custodios TO authenticated USING (aprobacion = 'aprobada');
ALTER POLICY patios_public_read    ON public.patios    TO authenticated USING (aprobacion = 'aprobada');
ALTER POLICY lavados_public_read   ON public.lavados   TO authenticated USING (aprobacion = 'aprobada');


-- ─────────────────────────────────────────────────────────────────────────
-- 3. lavados.propietario_id tiene que admitir NULL
-- ─────────────────────────────────────────────────────────────────────────
-- Sin esto, el SET NULL del punto 4 falla al borrar la cuenta y el borrado
-- se aborta entero.
ALTER TABLE public.lavados ALTER COLUMN propietario_id DROP NOT NULL;


-- ─────────────────────────────────────────────────────────────────────────
-- 4. Una sola regla de borrado para toda la flota: SET NULL
-- ─────────────────────────────────────────────────────────────────────────
-- Se retiran las claves foraneas hacia auth.users que imponian CASCADE y
-- contradecian al SET NULL que ya existia hacia perfiles. No se pierde
-- integridad: perfiles.user_id es a su vez FK contra auth.users con CASCADE,
-- asi que la cadena sigue cerrada.
ALTER TABLE public.custodios DROP CONSTRAINT IF EXISTS custodios_propietario_id_fkey;
ALTER TABLE public.patios    DROP CONSTRAINT IF EXISTS patios_propietario_id_fkey;
ALTER TABLE public.lavados   DROP CONSTRAINT IF EXISTS lavados_propietario_id_fkey;

-- Las que se conservan estaban NOT VALID: nunca se comprobaron contra las
-- filas existentes. Se validan ahora que son las unicas.
ALTER TABLE public.custodios VALIDATE CONSTRAINT custodios_propietario_fk;
ALTER TABLE public.patios    VALIDATE CONSTRAINT patios_propietario_fk;
ALTER TABLE public.lavados   VALIDATE CONSTRAINT lavados_propietario_fk;

-- operadores era el ultimo con CASCADE. Se reemplaza por SET NULL.
ALTER TABLE public.operadores DROP CONSTRAINT IF EXISTS operadores_propietario_id_fkey;
ALTER TABLE public.operadores
  ADD CONSTRAINT operadores_propietario_id_fkey
  FOREIGN KEY (propietario_id) REFERENCES public.perfiles(user_id) ON DELETE SET NULL;


-- ─────────────────────────────────────────────────────────────────────────
-- 5. notificaciones.user_id: la FK que faltaba
-- ─────────────────────────────────────────────────────────────────────────
-- Es la tabla que mas crece y no tenia clave foranea: nada impedia
-- notificaciones huerfanas. CASCADE es lo correcto aqui —una notificacion
-- para un usuario que ya no existe no le sirve a nadie— y ademas user_id es
-- NOT NULL, asi que SET NULL no seria posible.
-- Comprobado en produccion: 0 huerfanos de 866.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'notificaciones_user_id_fkey'
                    AND conrelid = 'public.notificaciones'::regclass) THEN
    ALTER TABLE public.notificaciones
      ADD CONSTRAINT notificaciones_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.perfiles(user_id) ON DELETE CASCADE;
  END IF;
END $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 6. pedidos.cliente_id NOT NULL
-- ─────────────────────────────────────────────────────────────────────────
-- Estaba al reves: cliente_nombre y cliente_email —las copias
-- desnormalizadas— eran obligatorias, y el vinculo real era opcional.
-- Comprobado en produccion: 0 nulos de 40.
ALTER TABLE public.pedidos ALTER COLUMN cliente_id SET NOT NULL;


-- ============================================================================
-- NO SE HACE AQUI, Y POR QUE
-- ============================================================================
-- FK de calificaciones.admin_id / cliente_id hacia perfiles:
--   ambas columnas son NOT NULL, asi que SET NULL no es posible. Quedarian
--   CASCADE (borrar una cuenta borra su reputacion historica) o NO ACTION
--   (imposible borrar una cuenta que tenga calificaciones, lo que romperia el
--   boton de eliminar usuario). Es otra decision de negocio, no un detalle.
--
-- FK de reservaciones.propietario_id / cliente_user_id hacia perfiles:
--   son nullable, pero el CHECK reservaciones_partes_presentes que se añadio
--   el 2026-08-26 exige que ninguna sea NULL. Un SET NULL al borrar violaria
--   ese CHECK y abortaria el borrado. Hay que decidir antes si una reservacion
--   debe sobrevivir al borrado de una de sus partes, y ajustar el CHECK.
--
-- FK de ofertas.camion_id y reservaciones.unidad:
--   IMPOSIBLES, y la auditoria se equivoco al pedirlas. Las dos columnas son
--   polimorficas: guardan el id de un camion, custodio, patio o lavado segun
--   el tipo de servicio. Verificado en produccion — la oferta 6ae8f1fb apunta
--   a PAT-004, que existe en `patios`, y js/pedidos.js:2348 resuelve la tabla
--   en tiempo de ejecucion. Una FK contra camiones romperia esas ofertas.
--   Lo que si cabe es un trigger que valide que el id existe en la tabla que
--   indica recurso_tipo. Queda pendiente.
--
-- Tablas pagos y documentos_fiscales:
--   duplican el cobro que hoy vive en reservaciones.pagado*. Estan vacias y
--   nadie las consulta, asi que no estorban. Se decide cuando haya requisitos
--   reales de facturacion, no antes.
-- ============================================================================
