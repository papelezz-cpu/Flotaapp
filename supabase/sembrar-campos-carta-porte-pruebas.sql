-- ─────────────────────────────────────────────────────────────────────────
-- Dato de prueba (NO es una migración) para poder ver la Carta Porte de
-- referencia completa en portgo-pruebas
-- ─────────────────────────────────────────────────────────────────────────
--
-- Llena — SOLO donde el campo está vacío — los campos que las Etapas 1, 2 y
-- 5 del plan agregaron: domicilio fiscal (perfiles), configuración
-- vehicular y permiso SCT de la unidad (camiones), domicilio estructurado
-- de origen/destino y clave SAT de la mercancía (pedidos). Nunca pisa un
-- valor que ya exista — ni el que puso el registro real, ni el que alguien
-- haya corregido ya desde "Mi perfil" / "Perfil de empresa".
--
-- Es dato claramente ficticio ("… de Prueba"), no información real de nadie.
-- Se pierde en cuanto alguien vuelva a correr
-- replicar-produccion-a-pruebas.sh — es exactamente lo que debe pasar
-- (Regla #3: pruebas es un espejo de producción, no un lugar donde vive
-- dato inventado a largo plazo).
--
-- Solo para portgo-pruebas. No existe versión de esto para producción.

begin;

-- perfiles: mismo rodeo que 20260929140000 — cualquier UPDATE de perfiles
-- dispara trg_vigencias_espejo sin importar qué columna cambió, y su
-- reflejo hacia `vigencias` choca con guard_vigencia_update() al correr sin
-- sesión de usuario (auth.uid() es NULL en el SQL Editor). Estas columnas
-- no son de las que el espejo refleja, así que apagarlo aquí no pierde nada.
alter table public.perfiles disable trigger trg_vigencias_espejo;

-- rfc/razon_social/permiso_sct no son de las Etapas 1/2/5 -- ya existían --
-- pero una cuenta creada desde "Usuarios" (gestionar-usuario, accion
-- 'crear') solo escribe user_id/nombre/rol en perfiles: sin solicitud de
-- cuenta de la que copiar, se quedan vacíos para siempre. Se llenan aquí
-- también, por la misma razón que el domicilio: para poder ver el
-- documento completo al probarlo.
update public.perfiles
   set calle        = coalesce(calle,        'Calle de Prueba 123'),
       colonia      = coalesce(colonia,      'Colonia de Prueba'),
       cp           = coalesce(cp,           '00000'),
       ciudad       = coalesce(ciudad,       'Ciudad de Prueba'),
       estado_mx    = coalesce(estado_mx,    'Estado de Prueba'),
       rfc          = coalesce(rfc,          'XAXX010101000'),
       razon_social = coalesce(razon_social, nombre),
       permiso_sct  = case when rol = 'admin' then coalesce(permiso_sct, 'SCT/TPAF/PRUEBA-EMPRESA-0001/2024') else permiso_sct end
 where rol in ('cliente', 'admin');

alter table public.perfiles enable trigger trg_vigencias_espejo;

-- camiones: mismo trigger, mismo rodeo. configuracion_vehicular/
-- numero_permiso_sct tampoco son columnas que el espejo refleje.
alter table public.camiones disable trigger trg_vigencias_espejo;

update public.camiones
   set configuracion_vehicular = coalesce(configuracion_vehicular, 'C3'),
       numero_permiso_sct      = coalesce(numero_permiso_sct, 'SCT/TPAF/PRUEBA-0001/2024');

alter table public.camiones enable trigger trg_vigencias_espejo;

-- pedidos: sin trigger de espejo (no está en la lista de tablas que
-- vigencias_espejo() vigila) — pero SÍ tiene su propio guard
-- (guard_pedido_update()), y ese rechaza cualquier UPDATE de una sesión sin
-- auth.uid(): ninguna de sus ramas (cliente/admin/superadmin) reconoce una
-- sesión SQL cruda, así que cae directo al «RAISE EXCEPTION No autorizado»
-- final, sin mirar qué columna cambió.
--
-- portgo.sync es el escape que el propio proyecto ya construyó para esto
-- exacto: sincronizar_estados_pedidos() lo enciende para poder correr desde
-- un cron, sin sesión de usuario (ver 20260908140000_sincroniza_estados_por_cron.sql).
-- Local a la transacción — se apaga solo al hacer commit, pase lo que pase.
select set_config('portgo.sync', 'on', true);

update public.pedidos
   set origen_colonia      = coalesce(origen_colonia,      'Colonia Origen de Prueba'),
       origen_cp           = coalesce(origen_cp,            '00001'),
       origen_ciudad       = coalesce(origen_ciudad,        'Ciudad Origen de Prueba'),
       origen_estado       = coalesce(origen_estado,        'Estado de Prueba'),
       destino_colonia     = coalesce(destino_colonia,      'Colonia Destino de Prueba'),
       destino_cp          = coalesce(destino_cp,           '00002'),
       destino_ciudad      = coalesce(destino_ciudad,       'Ciudad Destino de Prueba'),
       destino_estado      = coalesce(destino_estado,       'Estado de Prueba'),
       clave_prod_serv_sat = coalesce(clave_prod_serv_sat,  '25171500');

commit;

-- ── Comprobación ─────────────────────────────────────────────────────────
--   select count(*) filter (where calle is null) as perfiles_sin_domicilio,
--          count(*) as perfiles_total
--     from public.perfiles where rol in ('cliente','admin');
--
--   select count(*) filter (where configuracion_vehicular is null) as camiones_sin_config,
--          count(*) as camiones_total
--     from public.camiones;
