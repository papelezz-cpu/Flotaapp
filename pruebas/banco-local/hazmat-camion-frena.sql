-- Prueba de «el permiso hazmat del camión frena el trato», en banco local y
-- revertida.
--
--   psql -d portgo_ensayo -v ON_ERROR_STOP=1 -f pruebas/banco-local/hazmat-camion-frena.sql
--
-- Requiere 20260924150000_hazmat_del_camion_frena_el_trato.sql aplicada.
--
-- Lo que se persigue, y por qué cada cosa:
--
--   · que con el permiso VENCIDO frene — la dirección obvia;
--   · que SIN permiso también frene, que es la regla estricta que se decidió y
--     la que afecta a las unidades heredadas;
--   · que con el permiso VIGENTE deje pasar — la dirección que nadie prueba y
--     que convierte un guard en un muro;
--   · **que un pedido que NO es de carga peligrosa no se vea afectado**, aunque
--     el camión no tenga permiso: si se colara, bloquearíamos la mayoría de los
--     tratos del sistema;
--   · **que un pedido de carga peligrosa con CUSTODIO no quede bloqueado.**
--     `ofertas.camion_id` guarda el id de cualquier recurso, así que sin el
--     EXISTS contra `camiones` «no tiene permiso» sería cierto para todos ellos;
--   · que el superadmin conserve la salida, sin la cual las dos partes quedan
--     atrapadas;
--   · y que el mensaje conserve el prefijo DOCUMENTOS_VENCIDOS, que es lo que
--     la RPC captura para aparcar el pedido en vez de reventar.
--
-- Todo termina con un `rollback`.

begin;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'empresa@ejemplo.mx'),
  ('33333333-3333-3333-3333-333333333333', 'cliente@ejemplo.mx'),
  ('99999999-9999-9999-9999-999999999999', 'sa@ejemplo.mx') on conflict do nothing;

insert into public.perfiles (user_id, nombre, rol) values
  ('99999999-9999-9999-9999-999999999999', 'Super',   'superadmin'),
  ('11111111-1111-1111-1111-111111111111', 'Empresa', 'admin'),
  ('33333333-3333-3333-3333-333333333333', 'Cliente', 'cliente') on conflict do nothing;

-- La empresa con sus tres documentos al día, para que lo único que pueda
-- frenar sea el permiso del camión y no otra cosa.
do $$
begin
  perform set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
  update public.perfiles
     set doc_permiso_sct = 'u/a.pdf',  fecha_vencimiento_permiso_sct  = current_date + 400,
         doc_seguro_rc   = 'u/b.pdf',  fecha_vencimiento_seguro_rc    = current_date + 400,
         doc_seguro_carga= 'u/c.pdf',  fecha_vencimiento_seguro_carga = current_date + 400
   where user_id = '11111111-1111-1111-1111-111111111111';
end $$;

insert into public.camiones (id, propietario_id, tipo, capacidad, placas, aprobacion) values
  ('C-HAZ', '11111111-1111-1111-1111-111111111111', 'Rabón', 8, 'HAZ-001', 'aprobada');
insert into public.custodios (id, propietario_id, nombre, tipo, aprobacion) values
  ('CUS-HAZ', '11111111-1111-1111-1111-111111111111', 'Custodio Uno', 'Custodio armado', 'aprobada');

-- Un pedido de carga peligrosa y otro normal, cada uno con su oferta.
insert into public.pedidos (id, cliente_id, cliente_nombre, cliente_email, tipo_camion, origen, destino, fecha_ini, estado, carga_peligrosa) values
  ('aaaaaaaa-0000-0000-0000-0000000000a1', '33333333-3333-3333-3333-333333333333', 'Cliente', 'c@e.mx', 'Rabón', 'Manzanillo', 'Colima', current_date + 5, 'abierto', true),
  ('aaaaaaaa-0000-0000-0000-0000000000b1', '33333333-3333-3333-3333-333333333333', 'Cliente', 'c@e.mx', 'Rabón', 'Manzanillo', 'Colima', current_date + 5, 'abierto', false),
  ('aaaaaaaa-0000-0000-0000-0000000000c1', '33333333-3333-3333-3333-333333333333', 'Cliente', 'c@e.mx', 'Custodio armado', 'Manzanillo', 'Colima', current_date + 5, 'abierto', true);

insert into public.ofertas (id, pedido_id, admin_id, admin_nombre, precio_oferta, camion_id, estado) values
  ('bbbbbbbb-0000-0000-0000-0000000000a1', 'aaaaaaaa-0000-0000-0000-0000000000a1', '11111111-1111-1111-1111-111111111111', 'Empresa', 10000, 'C-HAZ',   'enviada'),
  ('bbbbbbbb-0000-0000-0000-0000000000b1', 'aaaaaaaa-0000-0000-0000-0000000000b1', '11111111-1111-1111-1111-111111111111', 'Empresa', 10000, 'C-HAZ',   'enviada'),
  ('bbbbbbbb-0000-0000-0000-0000000000c1', 'aaaaaaaa-0000-0000-0000-0000000000c1', '11111111-1111-1111-1111-111111111111', 'Empresa', 10000, 'CUS-HAZ', 'enviada');

create or replace function pruebas_aceptar(p_oferta uuid, p_quien uuid) returns text language plpgsql as $$
begin
  update public.ofertas set estado = 'enviada' where id = p_oferta;
  perform set_config('request.jwt.claim.sub', p_quien::text, true);
  update public.ofertas set estado = 'aceptada' where id = p_oferta;
  return 'ACEPTADA';
exception when others then
  return sqlerrm;
end $$;

-- Pone el permiso hazmat del camión a la fecha que se le diga (o lo quita).
create or replace function pruebas_permiso(p_fecha date) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
  update public.camiones
     set doc_permiso_peligrosa = case when p_fecha is null then null else 'u/haz.pdf' end,
         fecha_vencimiento_permiso_peligrosa = p_fecha
   where id = 'C-HAZ';
end $$;


\echo ''
\echo '── 1 · SIN permiso, y el pedido es de carga peligrosa: frena ──'

do $$
declare r text;
begin
  perform pruebas_permiso(null);
  r := pruebas_aceptar('bbbbbbbb-0000-0000-0000-0000000000a1', '33333333-3333-3333-3333-333333333333');
  if r not like 'DOCUMENTOS_VENCIDOS%' then
    raise exception 'FALLA: se pudo aceptar sin permiso hazmat. Respuesta: %', r;
  end if;
  if r not like '%C-HAZ%' then
    raise exception 'FALLA: el mensaje no dice qué unidad es. Dice: %', r;
  end if;
  raise notice '  OK    frena y nombra la unidad: %', left(r, 70);
end $$;


\echo ''
\echo '── 2 · Con el permiso VENCIDO: frena igual ──'

do $$
declare r text;
begin
  perform pruebas_permiso(current_date - 1);
  r := pruebas_aceptar('bbbbbbbb-0000-0000-0000-0000000000a1', '33333333-3333-3333-3333-333333333333');
  if r not like 'DOCUMENTOS_VENCIDOS%' then
    raise exception 'FALLA: se pudo aceptar con el permiso vencido ayer. Respuesta: %', r;
  end if;
  raise notice '  OK    vencido ayer: frena';
end $$;


\echo ''
\echo '── 3 · Con el permiso VIGENTE: deja pasar ──'
-- La dirección que nadie prueba. Un guard que frena siempre no es un guard.

do $$
declare r text;
begin
  perform pruebas_permiso(current_date + 30);
  r := pruebas_aceptar('bbbbbbbb-0000-0000-0000-0000000000a1', '33333333-3333-3333-3333-333333333333');
  if r <> 'ACEPTADA' then
    raise exception 'FALLA: con el permiso vigente no deberia frenar. Respuesta: %', r;
  end if;
  raise notice '  OK    permiso vigente: el cliente acepta sin problema';

  -- Y el borde: vence HOY cuenta como vigente, igual que la regla de la empresa
  -- (que usa < current_date).
  perform pruebas_permiso(current_date);
  r := pruebas_aceptar('bbbbbbbb-0000-0000-0000-0000000000a1', '33333333-3333-3333-3333-333333333333');
  if r <> 'ACEPTADA' then
    raise exception 'FALLA: un permiso que vence HOY deberia seguir valiendo. Respuesta: %', r;
  end if;
  raise notice '  OK    y vencer hoy todavia vale';
end $$;


\echo ''
\echo '── 4 · Un pedido que NO es de carga peligrosa no se toca ──'
-- Si esto se colara, bloquearíamos la mayoría de los tratos del sistema.

do $$
declare r text;
begin
  perform pruebas_permiso(null);   -- el camión sin permiso, a propósito
  r := pruebas_aceptar('bbbbbbbb-0000-0000-0000-0000000000b1', '33333333-3333-3333-3333-333333333333');
  if r <> 'ACEPTADA' then
    raise exception 'FALLA GRAVE: un pedido normal quedo bloqueado por el permiso hazmat. Respuesta: %', r;
  end if;
  raise notice '  OK    carga normal con el mismo camion sin permiso: pasa, como debe';
end $$;


\echo ''
\echo '── 5 · Carga peligrosa con CUSTODIO: tampoco se bloquea ──'
-- `ofertas.camion_id` guarda el id de cualquier recurso. Sin el EXISTS contra
-- `camiones`, «no tiene permiso» sería cierto para un custodio y este trato
-- quedaría bloqueado sin que nada explicara por qué.

do $$
declare r text;
begin
  r := pruebas_aceptar('bbbbbbbb-0000-0000-0000-0000000000c1', '33333333-3333-3333-3333-333333333333');
  if r <> 'ACEPTADA' then
    raise exception 'FALLA: un servicio de custodia para carga peligrosa quedo bloqueado. Respuesta: %', r;
  end if;
  raise notice '  OK    el custodio no se mide por el permiso de un camion';
end $$;


\echo ''
\echo '── 6 · El superadmin conserva la salida ──'

do $$
declare r text;
begin
  perform pruebas_permiso(null);
  r := pruebas_aceptar('bbbbbbbb-0000-0000-0000-0000000000a1', '99999999-9999-9999-9999-999999999999');
  if r <> 'ACEPTADA' then
    raise exception 'FALLA: el superadmin no pudo forzar; las dos partes quedarian atrapadas. Respuesta: %', r;
  end if;
  raise notice '  OK    el superadmin fuerza el acuerdo con la unidad sin permiso';
end $$;


\echo ''
\echo '   El permiso hazmat del camion frena el trato, solo cuando toca, y el'
\echo '   superadmin sigue teniendo la ultima palabra.'
\echo ''

rollback;
