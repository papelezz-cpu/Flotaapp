-- ============================================================================
-- El globo del superadmin cuenta lo mismo que el panel lista (R-05)
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- renderAprobaciones() carga ONCE colas. cola_superadmin() cuenta DIEZ. Al
-- compararlas una a una, el 2026-09-18, salen dos desajustes:
--
--   1. Las reservaciones en 'PorAprobar' NO SE CUENTAN. El panel las lista
--      —js/aprobaciones.js:85— y el globo no las ve. Un cierre de servicio
--      esperando aprobacion deja el globo oculto, y un globo oculto es
--      indistinguible de "no hay nada que revisar". El servicio se queda sin
--      cerrar sin que nadie tenga motivo para entrar a mirar.
--
--   2. Las cuentas se cuentan de una tabla y se listan de otra. El panel lista
--      solicitudes_cuenta.estado = 'pendiente'; el globo cuenta
--      perfiles.aprobacion_cuenta = 'pendiente'. Son dos escrituras distintas,
--      sin transaccion que las una, y ya hay un comentario en js/auth.js:784
--      que describe el desajuste desde el otro lado.
--
--      aprobarCuenta() (js/aprobaciones.js:924) las actualiza en un
--      Promise.all y solo mira el error de la primera. Si la segunda falla, el
--      perfil queda aprobado, la solicitud sigue 'pendiente', el panel la
--      lista para siempre y el globo dice cero.
--
-- Esto no es una regresion de H-09: la version de diez consultas que habia
-- antes en _loadAprBadge() contaba exactamente lo mismo. La migracion
-- 20260915140000 la reprodujo fielmente, desajustes incluidos, que era lo
-- correcto entonces —una cosa a la vez— y es lo que se corrige ahora.
--
-- ── Lo que NO se puede comprobar contra produccion ────────────────────────
--
-- Medido el 2026-09-18 con la clave de servicio: las once colas valen CERO.
-- No hay hoy ninguna fila que ensene la diferencia. Que el estado se usa de
-- verdad lo dicen las 14 reservaciones 'Completada', que pasaron todas por
-- 'PorAprobar'. Y solicitudes_cuenta vs perfiles coinciden en las 7 filas que
-- hay: el camino de divergencia existe en el codigo, no en los datos de hoy.
--
-- ── Por que la union, y no cambiar de tabla ───────────────────────────────
--
-- Lo evidente seria contar solicitudes_cuenta, que es lo que el panel pinta.
-- Pero eso pierde una alarma: un perfil 'pendiente' SIN solicitud —el hueco
-- que describe js/auth.js:784, cuando el alta se corta a la mitad— dejaria de
-- levantar el globo, y esa persona no puede entrar a la aplicacion y nadie se
-- entera. La union no se queda corta por ningun lado: cuenta al usuario si
-- CUALQUIERA de las dos tablas dice que esta pendiente, y una sola vez aunque
-- lo digan las dos.
--
-- ── Lo que sigue sin arreglar aqui ────────────────────────────────────────
--
-- La escritura sin comprobar de aprobarCuenta() es un defecto aparte y no se
-- toca en una migracion: lo que se arregla aqui es que el numero no mienta, no
-- la causa por la que podria mentir.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. La funcion, con las once colas
-- ─────────────────────────────────────────────────────────────────────────

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
    -- Un usuario, no dos filas: UNION quita el duplicado cuando las dos tablas
    -- coinciden, que es el caso normal.
    'cuentas',         (select count(*) from (
                          select user_id from public.perfiles           where aprobacion_cuenta = 'pendiente'
                          union
                          select user_id from public.solicitudes_cuenta where estado = 'pendiente'
                        ) u),
    'docs_empresa',    (select count(*) from public.perfiles      where perfil_docs_pendiente),
    'cierres',         (select count(*) from public.reservaciones where estado = 'PorAprobar'),
    'cancelaciones',   (select count(*) from public.reservaciones where estado = 'CancelacionSolicitada')
  ) into v;

  -- El total se calcula aqui y no en el navegador: sumar las claves de un jsonb
  -- en JS es facil de desincronizar cuando se anada la duodecima cola.
  return v || jsonb_build_object(
    'total', (select coalesce(sum(value::bigint), 0) from jsonb_each_text(v))
  );
end;
$$;

comment on function public.cola_superadmin() is
  'Lo que le falta por revisar al superadmin, desglosado y con total, en una sola ida y vuelta. Las once colas que lista renderAprobaciones(), sin faltar ninguna. Ver H-09 y R-05.';

revoke all on function public.cola_superadmin() from public, anon;
grant execute on function public.cola_superadmin() to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
-- Que la funcion exista no prueba nada: lo que hay que comprobar es que cuenta
-- lo que el panel lista.
--
-- La funcion exige superadmin y psql conecta sin JWT, asi que no se la puede
-- llamar desde aqui. Se comprueba que su cuerpo declare las once claves —que
-- es justo lo que 20260915140000 NO comprobo, y por eso el hueco sobrevivio— y
-- se calculan aparte las dos que cambian.

do $$
declare
  v_esperadas text[] := array['camiones','operadores','custodios','patios','lavados',
                              'pedidos_revision','pedidos_acuerdo','cuentas',
                              'docs_empresa','cierres','cancelaciones','total'];
  v_falta   text;
  v_cierres bigint;
  v_cuentas bigint;
  v_cuerpo  text;
begin
  select prosrc into v_cuerpo
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'cola_superadmin';

  if v_cuerpo is null then
    raise exception 'R-05: cola_superadmin() no existe.';
  end if;

  select string_agg(k, ', ') into v_falta
    from unnest(v_esperadas) k
   where strpos(v_cuerpo, quote_literal(k)) = 0;

  if v_falta is not null then
    raise exception 'R-05: a cola_superadmin() le faltan claves: %', v_falta;
  end if;

  -- Y que las dos que cambian cuenten de verdad lo que deben.
  select count(*) into v_cierres from public.reservaciones where estado = 'PorAprobar';

  select count(*) into v_cuentas from (
    select user_id from public.perfiles           where aprobacion_cuenta = 'pendiente'
    union
    select user_id from public.solicitudes_cuenta where estado = 'pendiente'
  ) u;

  raise notice 'R-05: once colas. Cierres por aprobar hoy: %. Cuentas pendientes (union): %.',
    v_cierres, v_cuentas;
end $$;
