-- ============================================================================
-- Los reportes dejan de sumarse en el navegador (H-07)
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- Dos pantallas se descargan el conjunto entero de un rango y calculan COUNT,
-- SUM, media y agrupacion por empresa en JavaScript. Ninguna de las dos
-- consultas lleva .limit().
--
--   js/reportes.js:30-35   Reportes del superadmin: todos los pedidos y todas
--                          las reservaciones del rango, mas TODAS las empresas
--                          sin filtro de fecha.
--   js/views.js:243-247    «Mi desempeno»: el historial COMPLETO de ofertas,
--                          reservaciones y calificaciones de la empresa, cada
--                          vez que se abre el inicio. Sin rango: ese historial
--                          no caduca nunca.
--
-- El coste crece con el historico y no con lo que se ensena. Un reporte anual
-- con cien mil pedidos descarga cien mil filas para pintar siete cifras.
--
-- Invisible hoy —40 pedidos y 19 reservaciones en produccion— y esa es la
-- razon de arreglarlo ahora: es la pantalla que primero deja de abrirse, y
-- falla por tiempo de espera, no con un error que explique nada.
--
-- El resto del cliente NO hace esto: los contadores usan
-- { count: 'exact', head: true }, que cuenta en el servidor sin traer filas.
-- El problema esta localizado en estas dos pantallas.
--
-- ── Que devuelven, y por que asi ──────────────────────────────────────────
--
-- Las dos entregan jsonb con los agregados, como cola_superadmin(). Devuelven
-- CONTEOS Y SUMAS, no porcentajes ni promedios ya redondeados: la tasa de
-- cierre y la calificacion media se siguen calculando en el navegador con las
-- mismas dos lineas de siempre. Asi el redondeo no puede divergir entre
-- Math.round de JavaScript y round() de PostgreSQL, que no son la misma
-- funcion en los empates.
--
-- Los meses se devuelven como mapa 'YYYY-MM' -> valor, y el navegador sigue
-- construyendo el rango y las etiquetas como hasta ahora. Es una fila por mes
-- con datos: ciento veinte tras una decada, frente a las cien mil de hoy.
--
-- La clave del mes sale de `created_at at time zone 'UTC'` porque es
-- exactamente lo que hace hoy el cliente: `created_at.substring(0, 7)` sobre
-- la cadena ISO, que viene en UTC. Cambiarlo a la zona local movería filas de
-- mes y el informe dejaría de cuadrar con el anterior.
--
-- ── desempeno_empresa() NO recibe el id de la empresa ─────────────────────
--
-- La propuesta de la auditoria era `desempeno_empresa(p_admin_id uuid)`. Se
-- deriva de auth.uid() en su lugar, que es la convencion que ya sigue el resto
-- del proyecto —calificar_servicio saca el admin_id del propietario de la
-- reserva, no de lo que mande el navegador—. Con el parametro, cualquier
-- empresa podria pedir el desempeno y los ingresos de otra.
--
-- ── Lo que se reproduce al pie de la letra, aunque chirrie ────────────────
--
--   · El rango superior es `hasta || 'T23:59:59'`, asi que las filas creadas
--     en el ultimo segundo del dia (23:59:59.000001 en adelante) quedan fuera.
--     Es lo que hace hoy el cliente. Se reproduce para que los numeros
--     coincidan; corregirlo es un cambio de comportamiento, no una migracion.
--
--   · `tipo_camion` vacio cuenta como 'Otro', igual que el `|| 'Otro'` de
--     JavaScript, que trata la cadena vacia y el nulo por igual.
--
--   · Los nombres de empresa salen de empresas_publico y no de perfiles,
--     porque es de donde los toma el cliente. perfiles tiene 13 filas y la
--     vista 3: usar la tabla meteria en el ranking a quien no es empresa.
--
--   · Lo que NO se reproduce es el desempate, y la diferencia es mas grande de
--     lo que parece. JavaScript ordena con un sort estable, asi que un empate
--     lo decide el orden en que las filas llegaron en la descarga. Y esa
--     descarga NO LLEVA ORDER BY: el orden lo elige PostgreSQL y no esta
--     garantizado entre dos cargas de la misma pantalla.
--
--     Con un top 5 eso no solo reordena: cambia QUIEN SALE. Comprobado en
--     pruebas el 2026-09-18 — tres tipos empatados a 3 pedidos peleando por el
--     quinto puesto, el calculo viejo ensenaba «Sencillo porta contenedor
--     40/20» y este ensena «Full». Los dos son igual de ciertos; solo uno es
--     reproducible.
--
--     Aqui se desempata por ingreso y luego por nombre. Es un cambio visible y
--     deliberado: la alternativa era conservar un orden que nadie eligio.
--
--   · `cancelados` se calcula en js/reportes.js:45 y no se pinta en ninguna
--     parte. Se devuelve igual, por si la tarjeta vuelve, y queda dicho.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. Reportes del superadmin
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.reporte_kpis(p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_ini   timestamptz;
  v_fin   timestamptz;
  v_ped   jsonb;
  v_res   jsonb;
  v_meses jsonb;
  v_top   jsonb;
  v_tipos jsonb;
begin
  if not public.is_superadmin() then
    raise exception 'No autorizado';
  end if;

  if p_desde is null or p_hasta is null then
    raise exception 'Hacen falta las dos fechas del rango';
  end if;
  if p_hasta < p_desde then
    raise exception 'El rango termina antes de empezar: % a %', p_desde, p_hasta;
  end if;

  -- Los mismos limites que arma el cliente hoy, ni un microsegundo mas.
  v_ini := p_desde::text::timestamptz;
  v_fin := (p_hasta::text || 'T23:59:59')::timestamptz;

  select jsonb_build_object(
    'total_pedidos', count(*),
    'acordados',     count(*) filter (where estado in ('acordado','finalizado','expirado')),
    'cancelados',    count(*) filter (where estado = 'cancelado'),
    'abiertos',      count(*) filter (where estado = 'abierto')
  ) into v_ped
    from public.pedidos
   where created_at >= v_ini and created_at <= v_fin;

  select jsonb_build_object(
    'total_reservas', count(*),
    'ingreso',        coalesce(sum(coalesce(precio_acordado, 0)), 0)
  ) into v_res
    from public.reservaciones
   where created_at >= v_ini and created_at <= v_fin;

  -- Mapa mes -> pedidos. El navegador construye el rango y las etiquetas.
  select coalesce(jsonb_object_agg(m, n), '{}'::jsonb) into v_meses
    from (select to_char(created_at at time zone 'UTC', 'YYYY-MM') as m, count(*) as n
            from public.pedidos
           where created_at >= v_ini and created_at <= v_fin
           group by 1) s;

  -- El ORDER BY va DENTRO del jsonb_agg, no solo en la subconsulta: una
  -- agregacion no tiene por que respetar el orden de lo que recibe, y aqui el
  -- orden es el resultado, no un adorno.
  select coalesce(jsonb_agg(jsonb_build_object(
           'nombre', nombre, 'reservas', n, 'ingreso', ing)
           order by n desc, ing desc, nombre), '[]'::jsonb) into v_top
    from (select coalesce(e.nombre, 'Empresa') as nombre,
                 count(*) as n,
                 coalesce(sum(coalesce(r.precio_acordado, 0)), 0) as ing
            from public.reservaciones r
            left join public.empresas_publico e on e.user_id = r.propietario_id
           where r.created_at >= v_ini and r.created_at <= v_fin
             and r.propietario_id is not null
           group by r.propietario_id, e.nombre
           order by n desc, ing desc, nombre
           limit 5) s;

  select coalesce(jsonb_agg(jsonb_build_object('tipo', t, 'n', n)
           order by n desc, t), '[]'::jsonb) into v_tipos
    from (select coalesce(nullif(tipo_camion, ''), 'Otro') as t, count(*) as n
            from public.pedidos
           where created_at >= v_ini and created_at <= v_fin
           group by 1
           order by n desc, t
           limit 5) s;

  return v_ped || v_res || jsonb_build_object(
    'meses', v_meses, 'top_admins', v_top, 'top_tipos', v_tipos);
end;
$$;

comment on function public.reporte_kpis(date, date) is
  'Los agregados de la pantalla Reportes, calculados en la base. Devuelve conteos y sumas; la tasa de cierre la sigue redondeando el navegador. Ver H-07.';

revoke all on function public.reporte_kpis(date, date) from public, anon;
grant execute on function public.reporte_kpis(date, date) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. «Mi desempeno» de una empresa
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.desempeno_empresa()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid   uuid := auth.uid();
  v_of    jsonb;
  v_res   jsonb;
  v_cal   jsonb;
  v_meses jsonb;
begin
  -- Sin sesion no hay desempeno que ensenar. Y el id NO se recibe: se deriva,
  -- para que nadie pida el de otra empresa.
  if v_uid is null then
    raise exception 'No autorizado';
  end if;

  select jsonb_build_object(
    'total_ofertas', count(*),
    'aceptadas',     count(*) filter (where estado = 'aceptada')
  ) into v_of
    from public.ofertas where admin_id = v_uid;

  select jsonb_build_object(
    'total_reservas', count(*),
    'completadas',    count(*) filter (where estado = 'Completada'),
    'ingreso_total',  coalesce(sum(coalesce(precio_acordado, 0)), 0)
  ) into v_res
    from public.reservaciones where propietario_id = v_uid;

  -- Suma y cuenta, no promedio: el navegador hace el (suma/n).toFixed(1) que
  -- ya hacia, y asi el redondeo no puede divergir.
  select jsonb_build_object(
    'rating_n',    count(*),
    'rating_suma', coalesce(sum(rating), 0)
  ) into v_cal
    from public.calificaciones where admin_id = v_uid;

  -- Todos los meses con ingreso, no solo seis: es una fila por mes y el
  -- navegador ya elige su ventana. Asi la funcion no tiene que adivinar que
  -- seis meses son, que en la frontera del mes no coinciden entre la zona
  -- local del navegador y UTC.
  select coalesce(jsonb_object_agg(m, ing), '{}'::jsonb) into v_meses
    from (select to_char(created_at at time zone 'UTC', 'YYYY-MM') as m,
                 coalesce(sum(coalesce(precio_acordado, 0)), 0) as ing
            from public.reservaciones
           where propietario_id = v_uid
           group by 1) s;

  return v_of || v_res || v_cal || jsonb_build_object('meses', v_meses);
end;
$$;

comment on function public.desempeno_empresa() is
  'Los agregados de «Mi desempeno» para la empresa que llama. El id sale de auth.uid(), nunca de un parametro. Ver H-07.';

revoke all on function public.desempeno_empresa() from public, anon;
grant execute on function public.desempeno_empresa() to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
-- Las dos exigen sesion y psql conecta sin JWT, asi que aqui solo se puede
-- comprobar que existen, que declaran lo que deben y que los permisos estan
-- como toca. Que los NUMEROS coincidan con los que calcula hoy el navegador se
-- comprueba aparte, comparando salida contra salida sobre los mismos datos:
-- eso es lo unico que prueba que la sustitucion es fiel, y no se puede hacer
-- desde aqui.

do $$
declare
  v_falta text;
  v_cuerpo text;
begin
  foreach v_falta in array array['reporte_kpis','desempeno_empresa']
  loop
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname = v_falta) then
      raise exception 'H-07: no se creo %()', v_falta;
    end if;

    -- SECURITY DEFINER sin search_path fijado es la puerta de atras clasica.
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname = v_falta
                      and p.prosecdef
                      and array_to_string(coalesce(p.proconfig, '{}'), ',') like '%search_path%') then
      raise exception 'H-07: %() no es SECURITY DEFINER con search_path fijado', v_falta;
    end if;

    if has_function_privilege('anon', (select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                        where n.nspname = 'public' and p.proname = v_falta limit 1), 'EXECUTE') then
      raise exception 'H-07: anon puede ejecutar %(). Hace falta sesion.', v_falta;
    end if;
  end loop;

  -- Que devuelvan las claves que las dos pantallas pintan.
  select prosrc into v_cuerpo from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reporte_kpis';
  select string_agg(k, ', ') into v_falta
    from unnest(array['total_pedidos','acordados','abiertos','total_reservas',
                      'ingreso','meses','top_admins','top_tipos']) k
   where strpos(v_cuerpo, quote_literal(k)) = 0;
  if v_falta is not null then
    raise exception 'H-07: a reporte_kpis() le faltan claves: %', v_falta;
  end if;

  select prosrc into v_cuerpo from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'desempeno_empresa';
  select string_agg(k, ', ') into v_falta
    from unnest(array['total_ofertas','aceptadas','total_reservas','completadas',
                      'ingreso_total','rating_n','rating_suma','meses']) k
   where strpos(v_cuerpo, quote_literal(k)) = 0;
  if v_falta is not null then
    raise exception 'H-07: a desempeno_empresa() le faltan claves: %', v_falta;
  end if;

  -- Y que no acepte un id por parametro, que es lo que la haria insegura.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'desempeno_empresa'
                and p.pronargs > 0) then
    raise exception 'H-07: desempeno_empresa() recibe parametros. El id debe salir de auth.uid().';
  end if;

  raise notice 'H-07: reporte_kpis() y desempeno_empresa() creadas, solo para sesiones autenticadas.';
  raise notice 'H-07: falta comparar sus numeros contra los que calcula hoy el navegador.';
end $$;
