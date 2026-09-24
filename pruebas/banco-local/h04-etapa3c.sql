-- Prueba de la Etapa 3c de H-04 (el espejo se entera de los borrados),
-- en banco local y revertida.
--
--   psql -d portgo_h04 -v ON_ERROR_STOP=1 -f pruebas/banco-local/h04-etapa3c.sql
--
-- Requiere las Etapas 1, 2, 3, 3b y 3c aplicadas al banco.
--
-- Lo que se persigue:
--   · que borrar un camión se lleve TODAS sus filas del espejo
--   · que no toque las de OTRO camión — un delete que barre de más es peor
--     que uno que no barre
--   · que también funcione para operador, custodio, patio y perfil
--   · que un estado 'rechazado' (que el mapeo nunca escribe) también caiga
--   · que el borrado de origen siga siendo posible aunque el espejo falle
--
-- Todo termina con un `rollback`: el banco queda intacto.

begin;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'empresa@ejemplo.mx'),
  ('22222222-2222-2222-2222-222222222222', 'otra@ejemplo.mx'),
  ('99999999-9999-9999-9999-999999999999', 'sa@ejemplo.mx');

insert into public.perfiles (user_id, nombre, rol)
values ('99999999-9999-9999-9999-999999999999', 'Super', 'superadmin'),
       ('11111111-1111-1111-1111-111111111111', 'Transportes Ejemplo', 'admin'),
       ('22222222-2222-2222-2222-222222222222', 'Transportes Otra', 'admin');

insert into public.camiones (id, propietario_id, tipo, capacidad, placas) values
  ('C-001', '11111111-1111-1111-1111-111111111111', 'Rabón', 8, 'ABC-123'),
  ('C-002', '11111111-1111-1111-1111-111111111111', 'Rabón', 8, 'DEF-456');

-- El superadmin pone papeles en los dos camiones: tres documentos en C-001 y
-- uno en C-002, que es el testigo de que el barrido no se pasa de largo.
do $$
begin
  perform set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
  update public.camiones
     set doc_seguro = 'u/seg.pdf',  fecha_vencimiento_seguro = '2027-02-01',
         imagen_tc  = 'u/tc.pdf',   fecha_vencimiento_tc     = '2027-03-01',
         doc_verificacion = 'u/ver.pdf', fecha_vencimiento_verificacion = '2027-04-01'
   where id = 'C-001';
  update public.camiones
     set doc_seguro = 'u/seg2.pdf', fecha_vencimiento_seguro = '2027-05-01'
   where id = 'C-002';
end $$;


\echo ''
\echo '── 1 · Borrar un camión se lleva sus filas, y SOLO las suyas ──'

do $$
declare n int;
begin
  select count(*) into n from public.vigencias where entidad_id = 'C-001';
  if n <> 3 then raise exception 'PREPARACION MAL: C-001 debería tener 3 filas, tiene %', n; end if;
  select count(*) into n from public.vigencias where entidad_id = 'C-002';
  if n <> 1 then raise exception 'PREPARACION MAL: C-002 debería tener 1 fila, tiene %', n; end if;

  -- Una fila 'rechazado' a mano: el mapeo nunca la escribe, así que es la
  -- única forma de comprobar que el barrido no filtra por estado.
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, archivo_path, estado, nota_rechazo)
  values ('camion', 'C-001', 'permiso_sct_unidad', 'u/viejo.pdf', 'rechazado', 'ilegible');

  select count(*) into n from public.vigencias where entidad_id = 'C-001';
  if n <> 4 then raise exception 'PREPARACION MAL: esperaba 4 filas en C-001, hay %', n; end if;

  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  delete from public.camiones where id = 'C-001';

  select count(*) into n from public.vigencias where entidad_id = 'C-001';
  if n <> 0 then
    raise exception 'FALLA: quedan % filas fantasma de C-001 tras borrarlo', n; end if;
  raise notice '  OK    borrar C-001 barrió sus 4 filas, incluida la rechazada';

  select count(*) into n from public.vigencias where entidad_id = 'C-002';
  if n <> 1 then
    raise exception 'FALLA: el barrido se llevó por delante a C-002 (quedan % de 1)', n; end if;
  raise notice '  OK    C-002 sigue con su fila: el barrido no se pasó de largo';
end $$;


\echo ''
\echo '── 2 · Lo mismo para operador, custodio, patio y perfil ──'

insert into public.operadores (id, propietario_id, nombre, curp, num_licencia)
values ('O-001', '11111111-1111-1111-1111-111111111111', 'Juan Ruiz', 'RUXJ800101HDFXXX01', 'LIC-9');
insert into public.custodios (id, propietario_id, nombre, tipo)
values ('U-001', '11111111-1111-1111-1111-111111111111', 'Custodia Uno', 'Armado');
insert into public.patios (id, propietario_id, nombre, tipo)
values ('P-001', '11111111-1111-1111-1111-111111111111', 'Patio Uno', 'Contenedores');

do $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);

  update public.operadores set foto_licencia = 'o/lic.jpg', fecha_vencimiento = '2027-06-01' where id = 'O-001';
  update public.custodios  set doc_licencia_sedena = 'c/sed.pdf', fecha_vencimiento_licencia_sedena = '2027-07-01' where id = 'U-001';
  update public.patios     set doc_permiso = 'p/per.pdf', fecha_vencimiento_permiso = '2027-08-01' where id = 'P-001';
  update public.perfiles   set doc_seguro_rc = 'e/rc.pdf', fecha_vencimiento_seguro_rc = '2027-09-01'
   where user_id = '22222222-2222-2222-2222-222222222222';

  select count(*) into n from public.vigencias
   where entidad_id in ('O-001','U-001','P-001','22222222-2222-2222-2222-222222222222');
  if n <> 4 then raise exception 'PREPARACION MAL: esperaba 4 filas nuevas, hay %', n; end if;

  delete from public.operadores where id = 'O-001';
  delete from public.custodios  where id = 'U-001';
  delete from public.patios     where id = 'P-001';
  delete from public.perfiles   where user_id = '22222222-2222-2222-2222-222222222222';

  select count(*) into n from public.vigencias
   where entidad_id in ('O-001','U-001','P-001','22222222-2222-2222-2222-222222222222');
  if n <> 0 then
    raise exception 'FALLA: quedan % filas fantasma de operador/custodio/patio/perfil', n; end if;
  raise notice '  OK    las cuatro entidades restantes también limpian al borrarse';
end $$;


\echo ''
\echo '── 3 · Sin la Etapa 3c esto NO pasaba (se comprueba quitando el DELETE) ──'
-- Un verde no vale si no se sabe que el rojo era posible. Se devuelven los
-- triggers a `insert or update`, se borra, y tiene que quedar el fantasma.

create or replace trigger trg_vigencias_espejo
  after insert or update on public.camiones
  for each row execute function public.vigencias_espejo();

do $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  delete from public.camiones where id = 'C-002';
  select count(*) into n from public.vigencias where entidad_id = 'C-002';
  if n = 0 then
    raise exception 'FALLA: la prueba no sabe detectar el hueco — sin el trigger DELETE el fantasma tendría que quedarse';
  end if;
  raise notice '  OK    sin DELETE en el trigger queda % fila fantasma: el hueco era real', n;
end $$;

-- Y se devuelve a como lo deja la migración.
create or replace trigger trg_vigencias_espejo
  after insert or update or delete on public.camiones
  for each row execute function public.vigencias_espejo();


\echo ''
\echo '── 4 · Si el espejo falla, el borrado de origen sigue ──'
-- Se rompe el espejo a propósito poniendo una regla que lo hará estallar, y
-- se comprueba que la empresa PUEDE borrar su camión igualmente. Es el trato
-- de la Etapa 3b, y tiene que seguir en pie para el borrado.

insert into public.camiones (id, propietario_id, tipo, capacidad, placas)
values ('C-003', '11111111-1111-1111-1111-111111111111', 'Rabón', 8, 'GHI-789');

do $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
  update public.camiones set doc_seguro='u/s3.pdf', fecha_vencimiento_seguro='2027-10-01' where id='C-003';

  -- Un trigger que revienta en cuanto alguien toque vigencias de C-003.
  execute $f$
    create or replace function public.pruebas_romper_espejo() returns trigger
    language plpgsql as $b$
    begin
      if coalesce(old.entidad_id, new.entidad_id) = 'C-003' then
        raise exception 'espejo roto a proposito';
      end if;
      return coalesce(new, old);
    end $b$ $f$;
  create trigger trg_pruebas_romper before delete on public.vigencias
    for each row execute function public.pruebas_romper_espejo();

  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  delete from public.camiones where id = 'C-003';

  select count(*) into n from public.camiones where id = 'C-003';
  if n <> 0 then
    raise exception 'FALLA: el fallo del espejo impidió borrar el camión. El espejo dejó de ser tolerante.'; end if;
  raise notice '  OK    el espejo falló (WARNING arriba) y el camión se borró igual';

  select count(*) into n from public.vigencias where entidad_id = 'C-003';
  if n <> 1 then raise exception 'esperaba 1 fila divergente de C-003, hay %', n; end if;
  raise notice '  OK    y la divergencia queda a la vista: 1 fila que la sonda 14 cazará';
end $$;


\echo ''
\echo '── 5 · El barrido de huérfanas de la migración sabe encontrarlas ──'
-- Esta corrida dejó DOS huérfanas de verdad, una por cada camino que las
-- produce: la de C-002, por un trigger sin DELETE (el hueco que cerró esta
-- etapa, y que en pruebas y producción puede haber dejado filas ya), y la de
-- C-003, por un espejo que falló y fue tolerante. La consulta del barrido de
-- la migración tiene que ver las dos.

do $$
declare n int;
begin
  drop trigger trg_pruebas_romper on public.vigencias;

  select count(*) into n from public.vigencias v
   where v.entidad_tipo = 'camion'
     and not exists (select 1 from public.camiones c where c.id = v.entidad_id);
  if n <> 2 then
    raise exception 'FALLA: el barrido debería ver 2 huérfanas (C-002 y C-003), ve %', n; end if;
  raise notice '  OK    el barrido ve las 2 huérfanas: la del trigger sin DELETE y la del espejo tolerante';
end $$;

\echo ''
\echo '   Etapa 3c: el espejo se entera de los borrados, sin pasarse ni bloquear.'
\echo ''

rollback;
