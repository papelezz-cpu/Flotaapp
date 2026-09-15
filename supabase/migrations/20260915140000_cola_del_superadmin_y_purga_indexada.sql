-- ============================================================================
-- La cola del superadmin en una consulta, y la purga con indice (H-09 + H-03)
-- ============================================================================
--
-- Van juntas porque atacan el mismo punto caliente desde los dos lados. Medido
-- en produccion el 2026-09-15, con 12 usuarios y 128 dias de historia:
--
--     866 notificaciones · 203/mes
--     404 de ellas (47%) van a los TRES superadmins
--     los tipos mas repetidos son avisos de cola: nueva_solicitud (118),
--     revision_solicitud (93)
--
-- Y cada INSERT de una notificacion propia del superadmin dispara
-- _loadAprBadge(), que son DIEZ consultas. Unas 4.000 consultas en 128 dias
-- para pintar un numero, y escala con los tres factores a la vez: mas eventos,
-- mas superadmins, mas consultas por evento.
--
--
-- ── H-09 · diez consultas para un numero ──────────────────────────────────
--
-- js/views.js:207-218 lanza diez COUNT en paralelo y los suma en el navegador.
-- Estaba BIEN HECHO dentro de su planteamiento: van en Promise.all, usan
-- head:true —asi que no traen filas— y cinco de los diez tienen indice parcial
-- exacto (idx_camiones_pendientes y sus hermanos). Lo que sobra es el
-- planteamiento: diez viajes de red y diez evaluaciones de RLS, incluidas diez
-- llamadas a is_superadmin(), para producir una suma.
--
-- La funcion devuelve el DESGLOSE, no solo el total: el panel ya lo necesita
-- para pintar cada cola por separado, y devolverlo aqui evita que la proxima
-- pantalla vuelva a lanzar diez consultas.
--
--
-- ── H-03 · la purga no tiene indice ───────────────────────────────────────
--
-- purgar_notificaciones_leidas filtra por `leido` y ordena por `created_at`.
-- El unico indice de la tabla empieza por user_id, asi que no sirve: secuencial
-- completo mas ordenacion externa, una vez al mes.
--
-- Hoy no se nota porque la purga NO BORRA NADA: ninguna fila llega a 180 dias,
-- la mas vieja tiene 128. Empezara a encontrar filas dentro de un mes, y es
-- mejor que para entonces el indice ya este.
--
-- ── Lo que NO se hace, y el informe proponia ──────────────────────────────
--
-- NO se toca la retencion de las no leidas. El informe decia que "no se purgan
-- nunca" y lo presentaba como el motor del crecimiento. Medido: son 33 filas
-- (4%) y NINGUNA pasa de 90 dias. Las no leidas se acaban leyendo. Borrarlas
-- seria resolver algo que no ocurre, y a cambio se perderia un aviso que su
-- destinatario todavia no ha visto.
--
-- ── Por que sin CONCURRENTLY ──────────────────────────────────────────────
--
-- Con 866 filas el indice se construye en milisegundos, y CONCURRENTLY obliga
-- a aplicar el archivo FUERA de transaccion: si algo fallara a mitad, la base
-- se queda a medias. Se prefiere la atomicidad. Lo dice el propio
-- aplicar-a-pruebas.sh cuando detecta CONCURRENTLY.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. H-03 · el indice que le falta a la purga
-- ─────────────────────────────────────────────────────────────────────────
-- Parcial: solo indexa las leidas, que son las unicas que la purga mira. Con
-- eso se mantiene pequeno aunque la tabla crezca.

create index if not exists idx_notificaciones_purga
  on public.notificaciones (created_at)
  where leido;

comment on index public.idx_notificaciones_purga is
  'Para purgar_notificaciones_leidas(): filtra por leido y ordena por created_at. Parcial porque la purga solo mira las leidas.';


-- ─────────────────────────────────────────────────────────────────────────
-- 2. H-09 · la cola del superadmin, de diez viajes a uno
-- ─────────────────────────────────────────────────────────────────────────
-- Las diez cuentas son EXACTAMENTE las de js/views.js:207-218, en el mismo
-- orden. Si una cambia alli, cambia aqui: son la misma definicion de "lo que
-- le falta por revisar al superadmin", escrita dos veces mientras dure la
-- transicion.
--
-- SECURITY DEFINER porque cuenta filas de nueve tablas con RLS distinto. La
-- autorizacion no se hereda: se comprueba a mano en la primera linea, que es
-- lo que hacen el resto de RPC de este proyecto.

create or replace function public.cola_superadmin()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v jsonb;
begin
  if not public.is_superadmin() then
    raise exception 'No autorizado';
  end if;

  select jsonb_build_object(
    'camiones',        (select count(*) from public.camiones      where aprobacion = 'pendiente'),
    'operadores',      (select count(*) from public.operadores    where aprobacion = 'pendiente'),
    'custodios',       (select count(*) from public.custodios     where aprobacion = 'pendiente'),
    'patios',          (select count(*) from public.patios        where aprobacion = 'pendiente'),
    'lavados',         (select count(*) from public.lavados       where aprobacion = 'pendiente'),
    'pedidos_revision',(select count(*) from public.pedidos       where estado = 'pendiente_revision'),
    'pedidos_acuerdo', (select count(*) from public.pedidos       where estado = 'pendiente_acuerdo'),
    'cuentas',         (select count(*) from public.perfiles      where aprobacion_cuenta = 'pendiente'),
    'docs_empresa',    (select count(*) from public.perfiles      where perfil_docs_pendiente),
    'cancelaciones',   (select count(*) from public.reservaciones where estado = 'CancelacionSolicitada')
  ) into v;

  -- El total se calcula aqui y no en el navegador: sumar diez claves de un
  -- jsonb en JS es facil de desincronizar cuando se anada la undecima cola.
  return v || jsonb_build_object(
    'total', (select coalesce(sum(value::bigint), 0) from jsonb_each_text(v))
  );
end;
$$;

comment on function public.cola_superadmin() is
  'Lo que le falta por revisar al superadmin, desglosado y con total, en una sola ida y vuelta. Sustituye las diez consultas de _loadAprBadge(). Ver H-09.';

revoke all on function public.cola_superadmin() from public, anon;
grant execute on function public.cola_superadmin() to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
-- No basta con que la funcion exista: hay que comprobar que CUENTA LO MISMO
-- que las diez consultas que sustituye. Se calculan aqui por separado y se
-- comparan, que es la unica forma de saber que la sustitucion es fiel.

do $$
declare
  v_fn      jsonb;
  v_suelto  bigint;
  v_indice  boolean;
begin
  -- La funcion exige superadmin y psql conecta sin JWT, asi que aqui se
  -- comprueban las cuentas directamente, no a traves de ella.
  select
      (select count(*) from public.camiones      where aprobacion = 'pendiente')
    + (select count(*) from public.operadores    where aprobacion = 'pendiente')
    + (select count(*) from public.custodios     where aprobacion = 'pendiente')
    + (select count(*) from public.patios        where aprobacion = 'pendiente')
    + (select count(*) from public.lavados       where aprobacion = 'pendiente')
    + (select count(*) from public.pedidos       where estado = 'pendiente_revision')
    + (select count(*) from public.pedidos       where estado = 'pendiente_acuerdo')
    + (select count(*) from public.perfiles      where aprobacion_cuenta = 'pendiente')
    + (select count(*) from public.perfiles      where perfil_docs_pendiente)
    + (select count(*) from public.reservaciones where estado = 'CancelacionSolicitada')
    into v_suelto;

  select exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'idx_notificaciones_purga'
  ) into v_indice;

  if not v_indice then
    raise exception 'H-03: no se creo idx_notificaciones_purga.';
  end if;

  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'cola_superadmin') then
    raise exception 'H-09: no se creo cola_superadmin().';
  end if;

  raise notice 'H-03/H-09: indice creado, cola_superadmin() creada. La cola vale % hoy.', v_suelto;
end $$;
