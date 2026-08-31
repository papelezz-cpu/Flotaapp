-- ============================================================================
-- H-01: perfiles deja de entregar la fila entera a cualquier autenticado
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- La politica "Leer nombre de empresa" es:
--
--     FOR SELECT USING ((SELECT auth.uid()) IS NOT NULL)
--
-- Sin clausula TO y sin restriccion de fila. RLS filtra FILAS, no COLUMNAS,
-- asi que dejar pasar la fila deja pasar sus 37 columnas. Cualquier usuario
-- con sesion lee el registro completo de todos los demas.
--
-- Medido en produccion el 2026-08-31: 12 perfiles, de los cuales 6 son
-- clientes cuyo nombre, telefono y RFC no se muestran en ninguna pantalla.
-- Se filtran y ya.
--
-- Lo que se escapa y NO deberia:
--
--   · PII de los clientes           nombre, telefono, rfc
--   · Estado interno de moderacion  aprobacion_cuenta, nota_rechazo_cuenta
--                                   (el texto que el superadmin escribio al
--                                    rechazar una cuenta, legible por la
--                                    competencia)
--   · Inventario documental         doc_permiso_sct, doc_seguro_rc,
--                                   doc_seguro_carga, los *_pendiente,
--                                   fotos_verificacion
--   · Detalle fiscal e interno      tipo_persona, regimen_fiscal, cp_fiscal,
--                                   docs_aprobados_por / _en
--
-- Precision sobre las rutas de documentos, para no exagerar el hallazgo: lo
-- que se filtra es la RUTA, no el archivo. Las politicas de storage
-- (reg_select y "Propietario y superadmin leen archivos") limitan el SELECT
-- sobre storage.objects al dueño o al superadmin, asi que un tercero con la
-- ruta no puede firmar una URL ni descargar nada. Es fuga de inventario
-- —que existen, como se llaman, cuantos son— no de contenido.
--
-- ── Lo que NO es el defecto ───────────────────────────────────────────────
--
-- Buena parte de lo que hoy se lee es DELIBERADO. js/catalogo.js y
-- js/detalle.js muestran a proposito la ficha del transportista a cualquier
-- usuario con sesion: es el panel de confianza con el que un cliente elige
-- empresa. Cerrar perfiles a solo `nombre` dejaria en blanco la pestaña
-- "Empresa" y el catalogo de proveedores.
--
-- Por eso la solucion no es cerrar, es SEPARAR: una ficha publica con
-- exactamente lo que ya se muestra, y la tabla cerrada para todo lo demas.
--
-- ── Por que una vista y no otra cosa ──────────────────────────────────────
--
--   · RLS no filtra columnas. No hay politica que diga "esta fila si, pero
--     sin nota_rechazo_cuenta".
--   · GRANT SELECT (columna) si filtra columnas, pero es POR ROL, no por
--     fila. Limitar las columnas de `authenticated` romperia la edicion del
--     perfil propio (js/admin.js:218, js/preferencias.js:44), que necesita
--     la fila completa. No sirve.
--   · La vista es aditiva: se crea, se migran las lecturas una a una, y la
--     politica vieja se retira al final. En ningun momento hay pantalla rota.
--
-- security_invoker se deja en su valor por defecto (false) A PROPOSITO. Con
-- security_invoker = true la vista aplicaria el RLS del que consulta y
-- devolveria cero filas en cuanto se cierre la tabla: seria inutil. Con el
-- valor por defecto corre con permisos de su dueño (postgres, que no tiene
-- FORCE ROW LEVEL SECURITY sobre perfiles — verificado), y el filtro de
-- seguridad va ESCRITO DENTRO de la vista: WHERE rol = 'admin'.
--
-- ⚠ Esta migracion NO retira todavia la politica vieja. Ver el bloque 5.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. La ficha publica del transportista
-- ─────────────────────────────────────────────────────────────────────────
-- Las 15 columnas son EXACTAMENTE las que hoy pintan js/catalogo.js:22,
-- js/catalogo.js:281 y js/detalle.js. Ni una mas. Decidido asi para que el
-- arreglo sea verificable comparando pantallas: no debe cambiar nada visible.
--
-- WHERE rol = 'admin' es la mitad del arreglo: los perfiles de CLIENTE no
-- aparecen en esta vista en absoluto, y son los que hoy se filtran sin que
-- ninguna pantalla los use.

create or replace view public.empresas_publico as
  select user_id,
         nombre,
         razon_social,
         rfc,
         descripcion,
         telefono,
         anos_operacion,
         num_unidades,
         seguro_rc,
         seguro_carga,
         permiso_sct,
         verificado,
         fecha_vencimiento_permiso_sct,
         fecha_vencimiento_seguro_rc,
         fecha_vencimiento_seguro_carga
    from public.perfiles
   where rol = 'admin';

comment on view public.empresas_publico is
  'Ficha publica del transportista: lo que catalogo y detalle ya mostraban a cualquier usuario con sesion. Solo filas rol=admin. Sustituye la lectura directa de perfiles ajenos. Ver H-01.';

-- anon no lee nada: mantiene la linea de 20260827160000_anon_sin_privilegios.
revoke all on public.empresas_publico from anon, public;
grant select on public.empresas_publico to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. El superadmin necesita una politica de SELECT propia
-- ─────────────────────────────────────────────────────────────────────────
-- ESTE ES EL PASO QUE NO SE PUEDE OLVIDAR. Hoy perfiles tiene cinco
-- politicas y NINGUNA da SELECT al superadmin: lee los perfiles ajenos
-- colandose por "Leer nombre de empresa", igual que todo el mundo.
--
-- Si se retirara esa politica sin crear esta, el panel de aprobaciones,
-- la verificacion presencial, la gestion de usuarios y los avisos de
-- vigencia se quedarian a ciegas de golpe.
--
-- is_superadmin() es SECURITY DEFINER, asi que no recursa contra el RLS de
-- perfiles. Envuelta en SELECT para que se evalue una vez por consulta y no
-- una por fila, como el resto de politicas desde 20260827200000.

drop policy if exists perfiles_superadmin_select on public.perfiles;
create policy perfiles_superadmin_select on public.perfiles
  for select to authenticated
  using ( (select public.is_superadmin()) );


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Los ids de los superadmins, sin abrir la tabla
-- ─────────────────────────────────────────────────────────────────────────
-- js/reservaciones.js:899 (_notificarCambioReserva) lee los superadmins para
-- armar la lista de destinatarios, y lo llama un admin o un cliente. Con la
-- tabla cerrada esa consulta devolveria vacio Y NO DARIA ERROR: los
-- superadmins simplemente dejarian de recibir el aviso, en silencio. Ese es
-- justo el fallo mudo que hay que evitar.
--
-- El comentario en ese punto del codigo explica por que no usa la RPC
-- notificar_superadmins(): necesita los ids para el correo, no solo insertar.
--
-- Devolver los ids no abre nada nuevo: la politica de INSERT de
-- notificaciones ya permite notificar a un superadmin, y notificar_superadmins()
-- ya escribe a todos ellos. Aqui solo se expone la lista de destinatarios que
-- el modelo ya daba por accesible, sin una sola columna de datos personales.

create or replace function public.ids_superadmins()
  returns setof uuid
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select user_id from public.perfiles where rol = 'superadmin';
$$;

revoke all on function public.ids_superadmins() from anon, public;
grant execute on function public.ids_superadmins() to authenticated;

comment on function public.ids_superadmins() is
  'Ids de los superadmins para armar destinatarios de notificacion. No expone ninguna columna de datos personales. Ver H-01.';


-- ─────────────────────────────────────────────────────────────────────────
-- 4. Lo que sigue funcionando igual, y por que
-- ─────────────────────────────────────────────────────────────────────────
-- Verificado sobre el volcado de produccion antes de escribir esto:
--
--   · Las 15 politicas RLS de OTRAS tablas que consultan perfiles
--     (of_insert, ped_update, sc_select, del_operadores, …) filtran TODAS
--     por auth.uid(): leen la fila propia. "Leer propio perfil" las cubre.
--
--   · Los embeds propietario:perfiles(nombre) de js/vigencias.js:21-24,
--     js/aprobaciones.js:78-82 y js/admin.js:94 son de superadmin (cubiertos
--     por el bloque 2) o van filtrados por propietario_id = auth.uid()
--     (fila propia). NINGUN embed hay que reescribir.
--
--   · js/pedidos.js:104 (_adminsConFlotaPara) lee rol=admin sin filtro de
--     usuario, pero sus dos unicos llamadores estan en js/aprobaciones.js
--     (1033 y 1630), que es panel de superadmin. Cubierto por el bloque 2.
--
--   · Las funciones SECURITY DEFINER que leen perfiles ignoran RLS por
--     definicion y no cambian.


-- ─────────────────────────────────────────────────────────────────────────
-- 5. El cierre — NO va en esta migracion
-- ─────────────────────────────────────────────────────────────────────────
-- ⚠ CAMBIO DESTRUCTIVO. Retirar estas dos politicas MIENTRAS el codigo siga
--   leyendo perfiles ajenos rompe cinco pantallas: detalle de unidad,
--   catalogo de proveedores, listado de camiones, listado de recursos y los
--   nombres de empresa en reservaciones.
--
--   Orden seguro, y en este orden:
--     1. Aplicar esta migracion (aditiva: no quita nada).
--     2. Desplegar el codigo que lee de empresas_publico.
--     3. Comprobar las cinco pantallas en el entorno de pruebas.
--     4. Solo entonces, en una migracion POSTERIOR, ejecutar los dos drop.
--
--   Reversion: volver a crear la politica, que es una sola sentencia.
--
--   "Leer propio perfil" se retira junto con la otra porque queda cubierta
--   por la politica de fila propia que hay que crear en su lugar; hacerlo
--   antes dejaria al usuario sin acceso a su propio registro.
--
-- create policy perfiles_lectura_propia on public.perfiles
--   for select to authenticated
--   using ( user_id = (select auth.uid()) );
--
-- drop policy "Leer nombre de empresa" on public.perfiles;
-- drop policy "Leer propio perfil"     on public.perfiles;
