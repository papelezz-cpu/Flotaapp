-- ─────────────────────────────────────────────────────────────────────────
-- La ficha publica de las empresas ya aprobadas nace vacia
-- ─────────────────────────────────────────────────────────────────────────
--
-- El registro pide razon social, RFC y telefono, pero js/auth.js solo escribe
-- en `perfiles` cuatro columnas: user_id, nombre, rol y aprobacion_cuenta.
-- Todo lo demas se queda en `solicitudes_cuenta`, y aprobarCuenta() no lo
-- copiaba. Resultado: la empresa entrega los datos, el superadmin los revisa
-- para aprobarla, y acto seguido su tarjeta del Catalogo sale sin nada --
-- ni razon social, ni RFC, ni telefono, ni boton "Ver empresa" -- hasta que
-- alguien los vuelve a teclear en Mis unidades > Perfil de empresa.
--
-- js/aprobaciones.js ya copia estos campos en las aprobaciones nuevas. Esta
-- migracion arregla las cuentas aprobadas ANTES de ese cambio.
--
-- Que NO arregla: anos de operacion, numero de unidades, permiso SCT, seguros
-- y descripcion no se piden en el registro. Esos solo puede ponerlos la
-- empresa desde su perfil, y su ausencia no es un fallo.
--
-- Sobre los guards: `guard_perfil_self_update` solo lanza excepcion cuando
-- cambian rol, aprobacion_cuenta o los campos de verificacion. Este UPDATE no
-- toca ninguno, asi que pasa aunque psql conecte sin JWT y auth.uid() sea
-- NULL. No hace falta apartar el trigger.

-- Sin begin/commit propios: aplicar-a-produccion.sh corre toda la tanda con
-- --single-transaction, y un commit aqui dentro la cerraria antes de tiempo.
-- Las otras cinco migraciones tampoco los llevan.

-- Solo rellena huecos: nunca pisa un valor que la empresa ya haya escrito.
-- El nullif(btrim(...),'') trata la cadena vacia como ausencia, porque el
-- formulario de registro guarda '' en vez de NULL en algunos campos.
update public.perfiles p
   set razon_social = coalesce(nullif(btrim(p.razon_social), ''), nullif(btrim(s.razon_social), '')),
       rfc          = coalesce(nullif(btrim(p.rfc),          ''), nullif(btrim(s.rfc),          '')),
       telefono     = coalesce(nullif(btrim(p.telefono),     ''), nullif(btrim(s.telefono),     '')),
       tipo_persona = coalesce(nullif(btrim(p.tipo_persona), ''), nullif(btrim(s.tipo_persona), ''))
  from public.solicitudes_cuenta s
 where s.user_id = p.user_id
   and s.estado  = 'aprobada'
   -- Solo filas donde de verdad haya algo que rellenar: evita reescribir
   -- media tabla para no cambiar nada.
   and (
        (nullif(btrim(p.razon_social), '') is null and nullif(btrim(s.razon_social), '') is not null)
     or (nullif(btrim(p.rfc),          '') is null and nullif(btrim(s.rfc),          '') is not null)
     or (nullif(btrim(p.telefono),     '') is null and nullif(btrim(s.telefono),     '') is not null)
     or (nullif(btrim(p.tipo_persona), '') is null and nullif(btrim(s.tipo_persona), '') is not null)
   );



-- ── Comprobacion ─────────────────────────────────────────────────────────
-- Cuantas empresas siguen sin ficha publica despues de esto. Las que salgan
-- aqui no tienen los datos ni en la solicitud: hay que pedirselos.
--
--   select p.user_id, p.nombre,
--          p.razon_social is null as sin_razon,
--          p.rfc          is null as sin_rfc,
--          p.telefono     is null as sin_telefono
--     from public.perfiles p
--    where p.rol = 'admin'
--      and p.aprobacion_cuenta is null
--      and coalesce(nullif(btrim(p.razon_social),''), nullif(btrim(p.rfc),''),
--                   nullif(btrim(p.telefono),''), p.descripcion) is null
--    order by p.nombre;
