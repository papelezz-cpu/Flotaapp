-- Prueba de la Etapa 2 de H-04 contra el banco local, en transacción revertida.
--
-- Siembra filas ELEGIDAS POR SUS BORDES, no «unas cuantas»: sin datos la
-- migración pasa trivialmente y no demuestra nada, y con datos cómodos solo
-- demuestra el caso cómodo.
--
--   psql -d portgo_h04 -v ON_ERROR_STOP=1 -f pruebas/banco-local/h04-etapa2.sql
--
-- Requiere la Etapa 1 ya aplicada al banco.
--
-- ⚠ ESTE GUION TERMINA EN ERROR A PROPÓSITO, Y SALE CON CÓDIGO 3.
--
-- La última prueba mete una fila de sobra y vuelve a correr la migración: su
-- bloque de comprobación TIENE que cazarla. Ese ERROR final es la última
-- afirmación pasando, no un fallo.
--
-- Cómo se lee el resultado:
--   · ocho «OK» y luego  ERROR: ... No cuadran   -> todo bien
--   · si aparece «NO SE DEBERÍA LLEGAR AQUÍ»     -> la comprobación NO caza
--     la fila de sobra, y entonces sí hay un problema
--
-- La transacción nunca llega al commit, así que el banco queda intacto.

begin;

-- ── Siembra ────────────────────────────────────────────────────────────────

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'empresa@ejemplo.mx'),
  ('22222222-2222-2222-2222-222222222222', 'otra@ejemplo.mx');

-- Un perfil con los tres documentos acreditados Y una renovación pendiente de
-- uno de ellos: el caso que obliga a los dos índices parciales.
insert into public.perfiles (user_id, nombre, rol,
    doc_permiso_sct, fecha_vencimiento_permiso_sct,
    doc_seguro_rc,   fecha_vencimiento_seguro_rc,
    doc_seguro_carga, fecha_vencimiento_seguro_carga,
    doc_seguro_rc_pendiente, fecha_vencimiento_seguro_rc_pendiente)
values ('11111111-1111-1111-1111-111111111111', 'Transportes Ejemplo', 'admin',
    'e/sct.pdf', '2027-03-01',
    'e/rc.pdf',  '2027-04-01',
    'e/carga.pdf','2027-05-01',
    'e/rc-nuevo.pdf', '2028-04-01');

-- Un perfil SIN un solo documento: no debe generar ninguna fila.
insert into public.perfiles (user_id, nombre, rol)
values ('22222222-2222-2222-2222-222222222222', 'Cliente Pelado', 'cliente');

-- Un camión completo, con los dos nombres raros: imagen_tc y vigencia_caat.
insert into public.camiones (id, propietario_id, tipo, capacidad, placas,
    imagen_tc, fecha_vencimiento_tc,
    doc_seguro, fecha_vencimiento_seguro,
    doc_sct, fecha_vencimiento_permiso_sct,
    doc_verificacion, fecha_vencimiento_verificacion,
    doc_permiso_peligrosa, fecha_vencimiento_permiso_peligrosa,
    doc_caat, vigencia_caat)
values ('C-001', '11111111-1111-1111-1111-111111111111', 'Rabón', 8, 'ABC-123',
    'u/tc.jpg', '2027-01-01',
    'u/seg.pdf','2027-02-01',
    'u/sct.pdf','2027-03-01',
    'u/ver.pdf','2027-04-01',
    'u/pel.pdf','2027-05-01',
    'u/caat.pdf','2027-06-01');

-- Un camión con SOLO fecha en un documento y SOLO archivo en otro: los dos
-- deben entrar, porque el CHECK pide una cosa o la otra, no las dos.
insert into public.camiones (id, propietario_id, tipo, capacidad, placas,
    fecha_vencimiento_seguro, doc_verificacion)
values ('C-002', '11111111-1111-1111-1111-111111111111', 'Torton', 12, 'XYZ-789',
    '2027-07-01', 'u/ver2.pdf');

-- Un camión sin ningún papel: cero filas.
insert into public.camiones (id, propietario_id, tipo, capacidad, placas)
values ('C-003', '11111111-1111-1111-1111-111111111111', 'Full', 20, 'QQQ-000');

-- Un operador con las tres fechas de EMISIÓN, que es el caso delicado.
insert into public.operadores (id, propietario_id, nombre,
    foto_licencia, fecha_vencimiento,
    doc_examen_medico, fecha_examen_medico,
    doc_examen_toxicologico, fecha_examen_toxicologico,
    doc_carta_antecedentes, fecha_carta_antecedentes)
values ('OP-001', '11111111-1111-1111-1111-111111111111', 'Juan',
    'o/lic.jpg', '2028-01-01',
    'o/med.pdf', '2026-03-01',
    'o/tox.pdf', '2026-04-01',
    'o/ant.pdf', '2026-05-01');

-- Un custodio con SOLO la certificación, que es el único tipo sin archivo.
insert into public.custodios (id, propietario_id, nombre, tipo, fecha_vencimiento_cert)
values ('CUS-001', '11111111-1111-1111-1111-111111111111', 'Vigía', 'Custodio Armado', '2027-09-01');

-- Un patio vacío: cero filas, y no debe fallar.
insert into public.patios (id, propietario_id, nombre, tipo)
values ('PAT-001', '11111111-1111-1111-1111-111111111111', 'Patio Norte', 'Patio');

\echo ''
\echo '── Sembrado. Esperado: 3+1 perfil · 6+2 camion · 4 operador · 1 custodio = 17 ──'
\echo ''
\echo '── Primera pasada de la Etapa 2 ──'

\i supabase/migrations/20260921120000_vigencias_etapa2_copiar.sql

\echo ''
\echo '── Segunda pasada: no debe duplicar ni fallar ──'

\i supabase/migrations/20260921120000_vigencias_etapa2_copiar.sql

\echo ''
\echo '── Comprobaciones ──'

do $$
declare n bigint; d date; a text;
begin
  select count(*) into n from public.vigencias;
  if n <> 17 then raise exception 'FALLA: se esperaban 17 filas, hay %', n; end if;
  raise notice '  OK    17 filas tras DOS pasadas — la copia es repetible';

  -- El perfil pelado y el camión sin papeles no generaron nada.
  select count(*) into n from public.vigencias
   where entidad_id in ('22222222-2222-2222-2222-222222222222','C-003');
  if n <> 0 then raise exception 'FALLA: entidades sin documentos generaron % fila(s)', n; end if;
  raise notice '  OK    una entidad sin papeles no genera filas';

  -- La renovación pendiente convive con la acreditada.
  select count(*) into n from public.vigencias
   where entidad_tipo='perfil' and tipo_documento='seguro_rc';
  if n <> 2 then raise exception 'FALLA: seguro_rc debía tener vigente+pendiente, tiene %', n; end if;
  select fecha_documento into d from public.vigencias
   where entidad_tipo='perfil' and tipo_documento='seguro_rc' and estado='pendiente';
  if d <> '2028-04-01' then raise exception 'FALLA: la pendiente tiene la fecha equivocada: %', d; end if;
  raise notice '  OK    la renovación pendiente no pisó a la acreditada';

  -- Los nombres raros llegaron a su sitio.
  select archivo_path, fecha_documento into a, d from public.vigencias
   where entidad_id='C-001' and tipo_documento='tarjeta_circulacion';
  if a <> 'u/tc.jpg' or d <> '2027-01-01' then
    raise exception 'FALLA: imagen_tc/fecha_vencimiento_tc mal mapeados: % %', a, d; end if;
  select archivo_path, fecha_documento into a, d from public.vigencias
   where entidad_id='C-001' and tipo_documento='caat';
  if a <> 'u/caat.pdf' or d <> '2027-06-01' then
    raise exception 'FALLA: doc_caat/vigencia_caat mal mapeados: % %', a, d; end if;
  raise notice '  OK    imagen_tc y vigencia_caat, los dos nombres fuera de patrón, bien mapeados';

  -- Solo fecha, y solo archivo.
  select count(*) into n from public.vigencias where entidad_id='C-002';
  if n <> 2 then raise exception 'FALLA: C-002 debía dar 2 filas, dio %', n; end if;
  raise notice '  OK    entran las filas con solo fecha y con solo archivo';

  -- La certificación del custodio, sin archivo.
  select archivo_path, fecha_documento into a, d from public.vigencias
   where entidad_id='CUS-001' and tipo_documento='certificacion';
  if a is not null or d <> '2027-09-01' then
    raise exception 'FALLA: la certificación debía ir sin archivo: % %', a, d; end if;
  raise notice '  OK    un documento sin archivo entra solo con su fecha';

  -- Y LO QUE MÁS IMPORTA: la fecha de examen se copia TAL CUAL, y la
  -- caducidad se deriva. Si alguien "mejorara" la copia sumando los meses
  -- aquí, esto lo caza.
  select fecha_documento into d from public.vigencias
   where entidad_id='OP-001' and tipo_documento='examen_medico';
  if d <> '2026-03-01' then
    raise exception 'FALLA: el examen médico debía guardar la fecha CAPTURADA (2026-03-01), guardó %', d; end if;
  if public.vigencia_vence_el('examen_medico', d) <> '2027-03-01' then
    raise exception 'FALLA: la caducidad derivada debía ser 2027-03-01, es %',
      public.vigencia_vence_el('examen_medico', d); end if;
  raise notice '  OK    el examen guarda la fecha capturada y la caducidad se deriva (2026-03-01 -> 2027-03-01)';

  -- La licencia, en cambio, SÍ guarda una caducidad: vigencia_meses es nulo.
  select fecha_documento into d from public.vigencias
   where entidad_id='OP-001' and tipo_documento='licencia';
  if public.vigencia_vence_el('licencia', d) <> d then
    raise exception 'FALLA: la licencia no debía derivar nada'; end if;
  raise notice '  OK    la licencia vence el día capturado, sin derivar';
end $$;

\echo ''
\echo '── Y que la comprobación de la migración sepa FALLAR ──'

do $$
begin
  -- Se mete a mano una fila de más: el recuento origen/destino debe cazarla.
  insert into public.vigencias (entidad_tipo, entidad_id, tipo_documento, fecha_documento, estado, nota_rechazo)
  values ('patio','PAT-001','permiso_patio','2027-01-01','rechazado','de mentira');
  raise notice '  (metida una fila de sobra a propósito)';
end $$;

\echo '   la siguiente pasada DEBE fallar con "No cuadran":'
\i supabase/migrations/20260921120000_vigencias_etapa2_copiar.sql

\echo ''
\echo '✗✗✗ NO SE DEBERÍA LLEGAR AQUÍ ✗✗✗'
\echo '    La migración aceptó una fila de sobra sin quejarse. Su bloque de'
\echo '    comprobación no sirve: arréglalo antes de fiarte de esta copia.'
rollback;
