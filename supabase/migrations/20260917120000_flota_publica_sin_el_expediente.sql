-- ============================================================================
-- El catalogo deja de entregar el expediente completo de cada unidad (H-10)
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- Cuatro politicas abren la FILA ENTERA de cada recurso aprobado a cualquier
-- usuario con sesion:
--
--     camiones_public_read   USING (aprobacion = 'aprobada')
--     custodios_public_read  USING (aprobacion = 'aprobada')
--     patios_public_read     USING (aprobacion = 'aprobada')
--     lavados_public_read    USING (aprobacion = 'aprobada')
--
-- RLS decide QUE FILAS ves, no que columnas. Asi que "ver el catalogo" y "leer
-- el expediente de la unidad" son hoy el mismo permiso.
--
-- Comprobado contra la base el 2026-09-17, con una sesion de empresa normal y
-- una sola peticion HTTP —sin pasar por ninguna pantalla—:
--
--     GET /rest/v1/camiones?select=*&aprobacion=eq.aprobada&propietario_id=neq.<yo>
--     -> 200 · 9 unidades ajenas · 48 columnas cada una
--
-- Y con datos dentro, no vacias: de los 11 camiones aprobados en produccion,
-- 9 tienen num_serie, num_motor, placas y tarjeta_circulacion; 9 tienen las
-- rutas de doc_sct y doc_seguro; 8 tienen precio_dia. Un competidor lee el VIN
-- y el precio por dia de toda la flota ajena.
--
-- ── Por que una vista, y no algo mas simple ───────────────────────────────
--
-- Pedir menos columnas desde el cliente NO protege: catalogo.js ya pide cuatro,
-- y quien quiera el resto escribe select=* a mano. Es cosmetica, igual que
-- ocultar un boton.
--
-- Permisos por columna (GRANT SELECT (id, tipo) ON camiones) si existen, pero
-- se aplican AL ROL, no a la politica. Como todos los usuarios de la app son el
-- mismo rol `authenticated`, eso dejaria tambien al dueno sin poder leer las
-- suyas completas y rompe la pantalla de Mis unidades.
--
-- La vista es el unico mecanismo que distingue los dos casos, y es el que este
-- proyecto ya uso para perfiles (empresas_publico, 20260831210000).
--
-- ── Que columnas, y por que esas ──────────────────────────────────────────
--
-- Las que el cliente pinta HOY, leidas del codigo, ni una mas:
--
--   catalogo.js:28-31  -> id, tipo, estado, propietario_id
--                         (lavados: tipos_vehiculo, tipos_lavado en vez de tipo)
--   _bloqueEstandar    -> estado, tipo
--   _bloqueLavado      -> estado, tipos_vehiculo, tipos_lavado
--   reservaciones.js   -> id, nombre, propietario_id
--   pedidos.js:2481-84 -> id, estado
--
-- camiones NO lleva `nombre` porque la tabla no lo tiene: su etiqueta es el id.
--
-- ── ESTA MIGRACION NO CIERRA NADA TODAVIA ─────────────────────────────────
--
-- Solo crea las vistas. Las cuatro politicas siguen abiertas, asi que la fuga
-- sigue ahi hasta que se retiren — y eso es un borrado que necesita
-- autorizacion explicita (Regla #1), en una migracion aparte.
--
-- El orden es a proposito: vistas y codigo primero, politicas al final. Al
-- reves, el catalogo se queda sin los bloques de flota de cada empresa hasta
-- que el despliegue termine. Es la ventana que ya sufrimos en H-02.
--
-- ── security_invoker se queda en false, como en empresas_publico ──────────
--
-- Con security_invoker = true la vista aplicaria el RLS del que consulta, y
-- cuando se cierren las politicas dejaria de ver nada. Corriendo con permisos
-- del propietario de la vista, el filtro `aprobacion = 'aprobada'` que lleva
-- dentro es lo que acota lo que sale — por eso va en la vista y no se confia
-- a que lo ponga quien consulta.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. Las cuatro vistas
-- ─────────────────────────────────────────────────────────────────────────

create or replace view public.camiones_publico as
  select id, tipo, estado, propietario_id
    from public.camiones
   where aprobacion = 'aprobada';

create or replace view public.custodios_publico as
  select id, tipo, nombre, estado, propietario_id
    from public.custodios
   where aprobacion = 'aprobada';

create or replace view public.patios_publico as
  select id, tipo, nombre, estado, propietario_id
    from public.patios
   where aprobacion = 'aprobada';

create or replace view public.lavados_publico as
  select id, nombre, tipos_vehiculo, tipos_lavado, estado, propietario_id
    from public.lavados
   where aprobacion = 'aprobada';

comment on view public.camiones_publico  is 'Lo que el catalogo ensena de un camion ajeno: nada del expediente. Ver H-10.';
comment on view public.custodios_publico is 'Lo que el catalogo ensena de un custodio ajeno. Ver H-10.';
comment on view public.patios_publico    is 'Lo que el catalogo ensena de un patio ajeno. Ver H-10.';
comment on view public.lavados_publico   is 'Lo que el catalogo ensena de un lavado ajeno. Ver H-10.';


-- ─────────────────────────────────────────────────────────────────────────
-- 2. Solo lectura. Esto NO es opcional
-- ─────────────────────────────────────────────────────────────────────────
-- Una vista nueva NACE ESCRIBIBLE. El esquema lleva
-- `ALTER DEFAULT PRIVILEGES ... GRANT ALL ON TABLES TO authenticated` y en
-- PostgreSQL "TABLES" incluye las vistas, asi que un `grant select` por si solo
-- no retira nada: vuelve a conceder algo que ya estaba dentro de ALL.
--
-- Eso es exactamente H-01, que dejo empresas_publico aceptando INSERT, UPDATE y
-- DELETE de cualquier usuario con sesion durante dos semanas. Estas cuatro son
-- auto-actualizables igual que aquella.
--
-- Se retira primero y se concede despues, en ese orden.

revoke all on public.camiones_publico  from public, anon, authenticated;
revoke all on public.custodios_publico from public, anon, authenticated;
revoke all on public.patios_publico    from public, anon, authenticated;
revoke all on public.lavados_publico   from public, anon, authenticated;

grant select on public.camiones_publico  to authenticated;
grant select on public.custodios_publico to authenticated;
grant select on public.patios_publico    to authenticated;
grant select on public.lavados_publico   to authenticated;

-- service_role tambien, como empresas_publico. El `revoke all ... from public`
-- de arriba no le quita nada —PUBLIC es el pseudo-rol, no una lista de roles—
-- pero estas vistas nacieron sin concesion para el, y sin esto responden 403.
--
-- Hoy no lo usa nadie: ninguna Edge Function lee flota. Se concede igual porque
-- dejarlo a medias hace divergir la paridad entre proyectos y obliga a razonar
-- por que empresas_publico si lo tiene y estas cuatro no. Es lectura: la clave
-- de servicio ya se salta RLS en las tablas de todos modos.
grant select on public.camiones_publico  to service_role;
grant select on public.custodios_publico to service_role;
grant select on public.patios_publico    to service_role;
grant select on public.lavados_publico   to service_role;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
-- Tres cosas, y las tres importan. Que las vistas se lean (si no, el catalogo
-- se queda en blanco), que NO se escriban (H-01 otra vez), y que no expongan
-- ninguna columna del expediente — que es el hallazgo entero.

do $$
declare
  v        text;
  v_falta  text;
  v_sobra  text;
  -- Lo que NUNCA debe salir por estas vistas.
  v_prohibido text[] := array[
    'num_serie','num_motor','placas','tarjeta_circulacion','caat','num_economico',
    'precio_dia','precio_lavado','doc_sct','doc_seguro','doc_caat','doc_verificacion',
    'doc_permiso_peligrosa','doc_permiso','doc_licencia_sedena','imagen_tc','imagen_caat',
    'snapshot_anterior','rechazo_nota','rechazo_campos','campos_editados','archivos',
    'num_licencia_sedena','certificaciones','area_m2','capacidad','dimensiones','rutas'
  ];
begin
  foreach v in array array['camiones_publico','custodios_publico','patios_publico','lavados_publico']
  loop
    if not has_table_privilege('authenticated', 'public.'||v, 'SELECT') then
      raise exception 'H-10: authenticated no puede LEER %. El catalogo se quedaria en blanco.', v;
    end if;

    if has_table_privilege('authenticated', 'public.'||v, 'INSERT')
    or has_table_privilege('authenticated', 'public.'||v, 'UPDATE')
    or has_table_privilege('authenticated', 'public.'||v, 'DELETE') then
      raise exception 'H-10: % acepta escrituras. Es H-01 otra vez.', v;
    end if;

    if has_table_privilege('anon', 'public.'||v, 'SELECT') then
      raise exception 'H-10: anon puede leer %. Debe hacer falta sesion.', v;
    end if;

    -- Se comprueba porque ya paso: la primera version de esta migracion no lo
    -- concedia y las cuatro vistas respondian 403 a la clave de servicio.
    if not has_table_privilege('service_role', 'public.'||v, 'SELECT') then
      raise exception 'H-10: service_role no puede leer %. empresas_publico si lo tiene; esto divergiria.', v;
    end if;

    -- Ninguna columna del expediente
    select string_agg(a.attname, ', ') into v_sobra
      from pg_attribute a
     where a.attrelid = ('public.'||v)::regclass
       and a.attnum > 0 and not a.attisdropped
       and a.attname = any(v_prohibido);

    if v_sobra is not null then
      raise exception 'H-10: % expone columnas del expediente: %', v, v_sobra;
    end if;
  end loop;

  -- Y que lleven lo que el catalogo necesita, o se queda sin pintar.
  select string_agg(c, ', ') into v_falta from unnest(array['id','tipo','estado','propietario_id']) c
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = 'public.camiones_publico'::regclass
                        and a.attname = c and a.attnum > 0 and not a.attisdropped);
  if v_falta is not null then
    raise exception 'H-10: a camiones_publico le faltan columnas que el catalogo pinta: %', v_falta;
  end if;

  raise notice 'H-10: cuatro vistas creadas, solo lectura, sin una columna del expediente.';
  raise notice 'H-10: las politicas *_public_read SIGUEN ABIERTAS. La fuga no se cierra hasta retirarlas.';
end $$;
