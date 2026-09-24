-- Prueba de la Etapa 5 de H-04 (el guard de ofertas lee `vigencias`), en banco
-- local y revertida.
--
--   psql -d portgo_h04 -v ON_ERROR_STOP=1 -f pruebas/banco-local/h04-etapa5.sql
--
-- Requiere las etapas 1, 2, 3, 4, 4.7 y 5 aplicadas al banco.
--
-- Lo que se persigue, y por qué cada cosa:
--
--   · que con un documento VENCIDO el guard siga frenando — la dirección obvia;
--   · que con los documentos AL DÍA deje pasar — la dirección que nadie prueba
--     y que convierte un guard en un muro;
--   · **que lea `vigencias` y no `perfiles`**: se divergen a propósito las dos
--     fuentes y se mira a cuál hace caso. Sin esto, la etapa podría no haber
--     movido nada y las dos primeras pruebas saldrían igual de verdes;
--   · que un papel sin fecha no bloquee (el hueco conocido de los 14);
--   · que el superadmin siga pudiendo forzar, porque si no una empresa con un
--     papel vencido queda atrapada sin salida;
--   · **que acepte el CLIENTE**, que es quien acepta en la vida real y quien NO
--     tiene permiso de RLS para leer los documentos de la empresa. Si el guard
--     dejara de ser SECURITY DEFINER, no vería ninguna fila y dejaría pasar
--     todo: fallaría abierto y en silencio.
--
-- Todo termina con un `rollback`.

begin;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'empresa@ejemplo.mx'),
  ('33333333-3333-3333-3333-333333333333', 'cliente@ejemplo.mx'),
  ('99999999-9999-9999-9999-999999999999', 'sa@ejemplo.mx');

insert into public.perfiles (user_id, nombre, rol) values
  ('99999999-9999-9999-9999-999999999999', 'Super',   'superadmin'),
  ('11111111-1111-1111-1111-111111111111', 'Empresa', 'admin'),
  ('33333333-3333-3333-3333-333333333333', 'Cliente', 'cliente');

insert into public.camiones (id, propietario_id, tipo, capacidad, placas, aprobacion)
values ('C-500', '11111111-1111-1111-1111-111111111111', 'Rabón', 8, 'XYZ-500', 'aprobada');

-- Un pedido del cliente, abierto, y una oferta de la empresa en 'enviada':
-- ese es el estado desde el que el cliente acepta.
insert into public.pedidos (id, cliente_id, cliente_nombre, cliente_email, tipo_camion, origen, destino, fecha_ini, estado)
values ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333',
        'Cliente', 'cliente@ejemplo.mx', 'Rabón', 'Manzanillo', 'Colima', current_date + 5, 'abierto');

insert into public.ofertas (id, pedido_id, admin_id, admin_nombre, precio_oferta, camion_id, estado)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', 'Empresa', 10000, 'C-500', 'enviada');

-- Deja la oferta como estaba, para poder reintentar la aceptación varias veces.
create or replace function pruebas_resetear_oferta() returns void language sql as $$
  update public.ofertas set estado = 'enviada'
   where id = 'bbbbbbbb-0000-0000-0000-000000000001';
$$;

-- Intenta aceptar COMO EL CLIENTE y devuelve el error, o 'ACEPTADA'.
create or replace function pruebas_aceptar_como_cliente() returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  update public.ofertas set estado = 'aceptada'
   where id = 'bbbbbbbb-0000-0000-0000-000000000001';
  return 'ACEPTADA';
exception when others then
  return sqlerrm;
end $$;


\echo ''
\echo '── 1 · Con el permiso SCT VENCIDO, el guard frena ──'

do $$
declare r text;
begin
  -- El superadmin acredita un permiso ya caducado. El espejo crea la fila.
  perform set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
  update public.perfiles
     set doc_permiso_sct = 'u/sct.pdf', fecha_vencimiento_permiso_sct = current_date - 10
   where user_id = '11111111-1111-1111-1111-111111111111';

  perform pruebas_resetear_oferta();
  r := pruebas_aceptar_como_cliente();
  if r not like 'DOCUMENTOS_VENCIDOS%' then
    raise exception 'FALLA: el cliente pudo aceptar con el SCT vencido. Respuesta: %', r;
  end if;
  raise notice '  OK    frena: %', left(r, 60);
end $$;


\echo ''
\echo '── 2 · El texto del error, intacto ──'
-- La RPC aceptar_y_cerrar_acuerdo hace LIKE 'DOCUMENTOS_VENCIDOS%' para mandar
-- el pedido a pendiente_acuerdo. Si el mensaje cambiara, ese aviso manejado se
-- convertiría en un error crudo en pantalla.

do $$
declare r text;
begin
  perform pruebas_resetear_oferta();
  r := pruebas_aceptar_como_cliente();
  if r <> 'DOCUMENTOS_VENCIDOS: la empresa tiene documentos vencidos (permiso SCT, seguro RC o seguro de carga)' then
    raise exception 'FALLA: el mensaje cambio. Es: %', r;
  end if;
  raise notice '  OK    el mensaje es el que la RPC espera, palabra por palabra';
end $$;


\echo ''
\echo '── 3 · LA PRUEBA QUE IMPORTA: ¿lee vigencias o perfiles? ──'
-- Se borra la fila del espejo SIN tocar la columna de perfiles, que sigue
-- caducada. Si el guard siguiera leyendo perfiles, seguiría frenando y esta
-- etapa no habría movido nada.

do $$
declare r text; v_col date;
begin
  delete from public.vigencias
   where entidad_tipo = 'perfil' and tipo_documento = 'permiso_sct' and estado = 'vigente';

  select fecha_vencimiento_permiso_sct into v_col from public.perfiles
   where user_id = '11111111-1111-1111-1111-111111111111';
  if v_col is null or v_col >= current_date then
    raise exception 'PREPARACION MAL: la columna de perfiles deberia seguir caducada';
  end if;

  perform pruebas_resetear_oferta();
  r := pruebas_aceptar_como_cliente();
  if r like 'DOCUMENTOS_VENCIDOS%' then
    raise exception 'FALLA: sigue frenando sin fila en vigencias — el guard lee perfiles, no la tabla nueva';
  end if;
  if r <> 'ACEPTADA' then
    raise exception 'Se esperaba que pasara y fallo por otro motivo: %', r;
  end if;
  raise notice '  OK    sin fila en vigencias deja pasar, aunque perfiles siga en % — lee la tabla nueva', v_col;
end $$;


\echo ''
\echo '── 4 · Con los documentos AL DÍA, deja pasar ──'
-- La dirección que nadie prueba. Un guard que frena siempre no es un guard.

do $$
declare r text;
begin
  perform set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
  update public.perfiles
     set doc_permiso_sct = 'u/sct.pdf', fecha_vencimiento_permiso_sct = current_date + 365
   where user_id = '11111111-1111-1111-1111-111111111111';

  perform pruebas_resetear_oferta();
  r := pruebas_aceptar_como_cliente();
  if r <> 'ACEPTADA' then
    raise exception 'FALLA: con los papeles al dia no deberia frenar. Respuesta: %', r;
  end if;
  raise notice '  OK    con el SCT vigente el cliente acepta sin problema';
end $$;


\echo ''
\echo '── 5 · Un papel sin fecha no bloquea (hueco conocido de los 14) ──'

do $$
declare r text;
begin
  perform set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
  -- Papel subido, sin fecha: la fila del espejo existe con fecha_documento nulo.
  update public.perfiles
     set doc_seguro_rc = 'u/rc.pdf', fecha_vencimiento_seguro_rc = null
   where user_id = '11111111-1111-1111-1111-111111111111';

  if not exists (select 1 from public.vigencias
                  where entidad_tipo='perfil' and tipo_documento='seguro_rc'
                    and estado='vigente' and fecha_documento is null) then
    raise exception 'PREPARACION MAL: no se creo la fila del seguro RC sin fecha';
  end if;

  perform pruebas_resetear_oferta();
  r := pruebas_aceptar_como_cliente();
  if r <> 'ACEPTADA' then
    raise exception 'FALLA: un documento sin fecha no deberia bloquear (cambiaria el comportamiento de hoy). Respuesta: %', r;
  end if;
  raise notice '  OK    papel sin fecha: no bloquea, igual que antes — y sigue sin vigilarse';
end $$;


\echo ''
\echo '── 6 · El superadmin puede forzar aunque esté vencido ──'
-- Sin esta salida, una empresa con un papel caducado queda atrapada.

do $$
declare r text;
begin
  perform set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
  update public.perfiles
     set fecha_vencimiento_permiso_sct = current_date - 30
   where user_id = '11111111-1111-1111-1111-111111111111';

  perform pruebas_resetear_oferta();
  begin
    perform set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
    update public.ofertas set estado = 'aceptada'
     where id = 'bbbbbbbb-0000-0000-0000-000000000001';
    raise notice '  OK    el superadmin fuerza el acuerdo con el papel vencido';
  exception when others then
    raise exception 'FALLA: el superadmin no pudo forzar: %', sqlerrm;
  end;
end $$;


\echo ''
\echo '   Etapa 5: el guard lee vigencias, frena por los dos lados y el'
\echo '   superadmin conserva la salida.'
\echo ''

rollback;
