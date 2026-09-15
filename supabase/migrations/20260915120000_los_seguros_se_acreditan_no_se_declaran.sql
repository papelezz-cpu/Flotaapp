-- ============================================================================
-- Los seguros y el permiso SCT se acreditan, no se declaran (H-02)
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- La misma pregunta se hacia dos veces en la misma tarjeta, con rigor
-- distinto, y el catalogo leia la floja.
--
--   Arriba  (guardarPerfilEmpresa)  -> casilla "Seguro RC" + permiso_sct texto
--                                      libre. Sin documento, sin fecha, sin
--                                      aprobacion de nadie.
--   Abajo   (solicitarActualizacionDocs) -> documento + fecha + revision del
--                                      superadmin.
--
-- El chip "Seg. RC ✓" que ve el cliente salia de la casilla. Es decir,
-- significaba "la empresa marco una casilla", no "alguien vio la poliza", y las
-- dos cosas se veian identicas en pantalla.
--
-- Peor: el camino riguroso NO premiaba. Rellenarlo no anadia ninguna palomita
-- nueva; solo podia quitartela al vencer. Por eso las 3 empresas de produccion
-- (verificado en vivo el 2026-09-15) tenian CERO fechas y CERO documentos, y el
-- estado pendiente_acuerdo era inalcanzable: guard_oferta_update compara
-- `IS NOT NULL AND < current_date`, y con todo a NULL nunca disparaba.
--
-- ── El arreglo ────────────────────────────────────────────────────────────
--
-- La fuente de verdad pasa a ser la FECHA DE VIGENCIA, y la fecha solo la
-- escribe aprobarDocsEmpresa() al promover un documento revisado.
--
-- Eso convierte la fecha en prueba suficiente para el catalogo, que ya la
-- recibe por empresas_publico -- y asi no hay que exponer las rutas de los
-- documentos en la vista publica solo para pintar un distintivo.
--
-- Pero solo es prueba si la empresa NO puede escribirla por su cuenta. RLS le
-- permite actualizar su propia fila de perfiles, asi que sin este guard bastaba
-- una llamada al API, sin pasar por ninguna pantalla, para ponerse una vigencia
-- inventada. De ahi el bloque 2: es lo que sostiene todo lo demas.
--
-- ── Lo que NO se toca ─────────────────────────────────────────────────────
--
-- Las columnas *_pendiente siguen siendo escribibles por la empresa: ahi es
-- donde deja lo que quiere que le revisen. Lo que se cierra son las columnas
-- REALES, que son las que el cliente ve.
--
-- Y camiones.fecha_vencimiento_permiso_sct es OTRA cosa -- el permiso del
-- camion, no el de la empresa. No entra aqui.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. El numero de permiso tambien pasa por revision
-- ─────────────────────────────────────────────────────────────────────────
-- Faltaba la gemela _pendiente del numero de permiso: las seis columnas de
-- documento y fecha la tenian, permiso_sct no. Sin ella el numero seguiria
-- entrando sin que nadie lo mirara, al lado de un documento que si se revisa.

alter table public.perfiles
  add column if not exists permiso_sct_pendiente text;

comment on column public.perfiles.permiso_sct_pendiente is
  'Numero de permiso SCT propuesto por la empresa, a la espera de revision. Lo promueve aprobarDocsEmpresa() junto con su documento y su vigencia.';


-- ─────────────────────────────────────────────────────────────────────────
-- 2. La empresa deja de poder acreditarse a si misma
-- ─────────────────────────────────────────────────────────────────────────
-- Se anaden seis columnas a lo que el guard ya vigilaba. El resto de la
-- funcion queda igual que en 20260914120000: misma marca portgo.cambio_rol,
-- misma salida por is_superadmin(), mismas tres comprobaciones previas.

CREATE OR REPLACE FUNCTION public.guard_perfil_self_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  -- Cambio de rol hecho por cambiar_rol(), que ya comprobo lo que habia que
  -- comprobar. La marca es local a la transaccion y solo la enciende esa
  -- funcion: set_config vive en pg_catalog y PostgREST no lo expone.
  IF current_setting('portgo.cambio_rol', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF public.is_superadmin() THEN
    RETURN NEW;
  END IF;

  IF NEW.rol IS DISTINCT FROM OLD.rol THEN
    RAISE EXCEPTION 'No autorizado: no puedes cambiar tu rol';
  END IF;

  IF NEW.aprobacion_cuenta IS DISTINCT FROM OLD.aprobacion_cuenta THEN
    IF NOT (OLD.aprobacion_cuenta = 'rechazada' AND NEW.aprobacion_cuenta = 'pendiente') THEN
      RAISE EXCEPTION 'No autorizado: no puedes cambiar el estado de aprobacion de tu cuenta';
    END IF;
  END IF;

  IF NEW.verificado           IS DISTINCT FROM OLD.verificado
     OR NEW.docs_aprobados_en   IS DISTINCT FROM OLD.docs_aprobados_en
     OR NEW.docs_aprobados_por  IS DISTINCT FROM OLD.docs_aprobados_por
     OR NEW.metodo_verificacion IS DISTINCT FROM OLD.metodo_verificacion THEN
    RAISE EXCEPTION 'No autorizado: campos de verificacion solo modificables por superadmin';
  END IF;

  -- H-02: la acreditacion no se autodeclara.
  --
  -- Estas seis son las que el cliente ve como "Seguro RC ✓" o "Permiso SCT".
  -- Solo las escribe aprobarDocsEmpresa(), que corre como superadmin y sale
  -- por el IF de arriba. La empresa propone en las columnas *_pendiente, que
  -- siguen abiertas para ella a proposito.
  IF NEW.permiso_sct  IS DISTINCT FROM OLD.permiso_sct
     OR NEW.seguro_rc    IS DISTINCT FROM OLD.seguro_rc
     OR NEW.seguro_carga IS DISTINCT FROM OLD.seguro_carga
     OR NEW.fecha_vencimiento_permiso_sct  IS DISTINCT FROM OLD.fecha_vencimiento_permiso_sct
     OR NEW.fecha_vencimiento_seguro_rc    IS DISTINCT FROM OLD.fecha_vencimiento_seguro_rc
     OR NEW.fecha_vencimiento_seguro_carga IS DISTINCT FROM OLD.fecha_vencimiento_seguro_carga THEN
    RAISE EXCEPTION 'No autorizado: los seguros y el permiso SCT se acreditan con documento aprobado, no se declaran. Subelos en Perfil de empresa -> Documentos legales.';
  END IF;

  RETURN NEW;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Retirar lo declarado sin respaldo
-- ─────────────────────────────────────────────────────────────────────────
-- ⚠ ESTO MODIFICA DATOS. Deja a las empresas que declararon un seguro sin
--   documento con el distintivo retirado, y tendran que subir el papel para
--   recuperarlo. Autorizado expresamente el 2026-09-15: produccion todavia no
--   tiene clientes reales.
--
--   NO borra ninguna fila. Solo pone a su valor de origen lo que nunca estuvo
--   acreditado: seguro_rc/seguro_carga a false (su DEFAULT) y permiso_sct a
--   NULL. Si manana alguien sube el documento, la aprobacion lo repone.
--
--   Condicion: se limpia SOLO donde no hay documento aprobado. Una empresa que
--   si lo tuviera conserva todo, asi que es seguro correrlo de nuevo.
--
-- psql conecta sin JWT, asi que auth.uid() es NULL, is_superadmin() da false y
-- el guard recien escrito rechazaria este UPDATE con su propio mensaje. Se
-- aparta el trigger dentro de la transaccion, como hizo 20260901130000 con
-- trg_guard_pedido_update.

alter table public.perfiles disable trigger trg_guard_perfil_self_update;

update public.perfiles
   set seguro_rc = false
 where rol = 'admin' and seguro_rc is true and doc_seguro_rc is null;

update public.perfiles
   set seguro_carga = false
 where rol = 'admin' and seguro_carga is true and doc_seguro_carga is null;

update public.perfiles
   set permiso_sct = null
 where rol = 'admin' and permiso_sct is not null and doc_permiso_sct is null;

alter table public.perfiles enable trigger trg_guard_perfil_self_update;


-- ─────────────────────────────────────────────────────────────────────────
-- 4. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────

do $$
declare
  v_sin_respaldo int;
  v_trigger_ok   boolean;
begin
  select count(*) into v_sin_respaldo
    from public.perfiles
   where rol = 'admin'
     and ( (seguro_rc    is true     and doc_seguro_rc    is null)
        or (seguro_carga is true     and doc_seguro_carga is null)
        or (permiso_sct  is not null and doc_permiso_sct  is null) );

  if v_sin_respaldo > 0 then
    raise exception 'H-02: quedan % empresa(s) con acreditacion sin documento.', v_sin_respaldo;
  end if;

  -- El trigger tiene que quedar ENCENDIDO. Si el bloque 3 fallara a mitad
  -- dejandolo apagado, perfiles se quedaria sin su guard y nadie se enteraria.
  select tgenabled <> 'D' into v_trigger_ok
    from pg_trigger
   where tgrelid = 'public.perfiles'::regclass
     and tgname  = 'trg_guard_perfil_self_update';

  if not coalesce(v_trigger_ok, false) then
    raise exception 'H-02: trg_guard_perfil_self_update quedo DESHABILITADO.';
  end if;

  raise notice 'H-02: sin acreditaciones huerfanas, y el guard sigue activo.';
end $$;
