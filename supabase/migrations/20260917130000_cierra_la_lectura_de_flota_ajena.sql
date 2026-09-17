-- ============================================================================
-- Paso 3 de H-10: retirar las cuatro politicas que abren la fila entera
-- ============================================================================
--
-- ⚠ ESTA MIGRACION BORRA CUATRO POLITICAS RLS. Regla #1: no se aplica sin
--   autorizacion explicita para este cambio concreto.
--
--   QUE:      camiones_public_read, custodios_public_read, patios_public_read
--             y lavados_public_read — una politica de SELECT por tabla de flota.
--
--   PARA QUE SIRVEN: son lo unico que hoy deja a un usuario ver unidades que no
--             son suyas. Es lo que alimenta el catalogo, la ficha de empresa y
--             el nombre del recurso en las reservaciones del cliente.
--
--   POR QUE:  son exactamente la fuga de H-10. RLS decide que FILAS ves, no que
--             columnas, asi que mientras existan, "ver el catalogo" y "leer el
--             expediente de la unidad" son el mismo permiso. Desde
--             20260917120000 ese trabajo lo hacen las vistas *_publico, que
--             entregan 4-6 columnas en vez de 48.
--
--   SI SALE MAL: el catalogo pierde los bloques de flota de cada empresa, la
--             ficha de empresa sale con 0 unidades, y las reservaciones del
--             cliente muestran el id en vez del nombre del recurso. Reversible:
--             el bloque 3 de abajo tiene las cuatro sentencias para recrearlas
--             tal cual estaban.
--
-- ── Requisito: el codigo nuevo tiene que estar desplegado ANTES ───────────
--
-- Si esto se aplica con el codigo viejo delante, esas tres pantallas se quedan
-- sin datos hasta que el despliegue termine. Por eso va DESPUES, no antes.
--
-- El bloque 1 lo comprueba y se niega a seguir si las vistas no existen.
--
-- ── Quien lee flota ajena, revisado uno a uno el 2026-09-17 ───────────────
--
--   catalogo.js:28-31        -> vistas *_publico            ✓ migrado
--   reservaciones.js cliente -> vistas *_publico            ✓ migrado
--   pedidos.js openEmpresaPerfil -> vistas *_publico        ✓ migrado
--   reservaciones.js empresa -> tablas, pero es el dueno    ✓ *_owner_read
--   pedidos.js openHacerOferta -> tablas, filtra por propietario_id = uid ✓
--   pedidos.js _cargarAdminCamionTipos -> idem              ✓
--   vigencias.js             -> filtra a lo propio salvo superadmin ✓
--   aprobaciones.js _adminsConFlotaPara -> solo lo llama el superadmin ✓
--
--   camiones.js:59, recursos.js:31 y :107 -> CODIGO MUERTO. Son las funciones
--   que pintan la rejilla de unidades oculta (hueco conocido #6 del flujo
--   operativo: #truck-grid vive con display:none y no hay forma de abrir una
--   unidad por su ficha desde la app). Tras esta migracion devuelven 0 filas
--   para quien no sea dueno. No se tocan: retirarlas es otra conversacion, y
--   dejarlas devolviendo vacio no cambia nada visible.
--
-- ── Lo que NO cambia ──────────────────────────────────────────────────────
--
-- El dueno sigue viendo sus unidades enteras (camiones_owner_read y las
-- *_owner_all), y el superadmin tambien. Mis unidades, Operadores, Vigencias y
-- el selector al ofertar no se tocan.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. No seguir si el reemplazo no esta puesto
-- ─────────────────────────────────────────────────────────────────────────
-- Sin las vistas, esto deja tres pantallas sin datos y sin aviso. Mejor fallar
-- aqui, en una transaccion que revierte, que descubrirlo en el catalogo.

do $$
declare v_falta text;
begin
  select string_agg(v, ', ') into v_falta
    from unnest(array['camiones_publico','custodios_publico','patios_publico','lavados_publico']) v
   where to_regclass('public.'||v) is null;

  if v_falta is not null then
    raise exception 'H-10 paso 3: faltan las vistas (%). Aplica antes 20260917120000.', v_falta;
  end if;

  -- Y que se puedan leer: una vista sin GRANT deja el catalogo igual de vacio.
  select string_agg(v, ', ') into v_falta
    from unnest(array['camiones_publico','custodios_publico','patios_publico','lavados_publico']) v
   where not has_table_privilege('authenticated', 'public.'||v, 'SELECT');

  if v_falta is not null then
    raise exception 'H-10 paso 3: authenticated no puede leer (%).', v_falta;
  end if;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. Retirar las cuatro
-- ─────────────────────────────────────────────────────────────────────────
-- IF EXISTS para que sea idempotente: volver a aplicarla no falla.

drop policy if exists camiones_public_read  on public.camiones;
drop policy if exists custodios_public_read on public.custodios;
drop policy if exists patios_public_read    on public.patios;
drop policy if exists lavados_public_read   on public.lavados;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Como deshacerlo, palabra por palabra
-- ─────────────────────────────────────────────────────────────────────────
-- Copiadas del volcado de produccion del 14/09, antes de retirarlas. Si el
-- catalogo se queda sin flota, esto lo devuelve al estado anterior:
--
--   create policy camiones_public_read  on public.camiones  for select to authenticated using (aprobacion = 'aprobada');
--   create policy custodios_public_read on public.custodios for select to authenticated using (aprobacion = 'aprobada');
--   create policy patios_public_read    on public.patios    for select to authenticated using (aprobacion = 'aprobada');
--   create policy lavados_public_read   on public.lavados   for select to authenticated using (aprobacion = 'aprobada');


-- ─────────────────────────────────────────────────────────────────────────
-- 4. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
-- Que se fueron, que el dueno conserva lo suyo, y que RLS sigue encendido —
-- porque una tabla sin politicas Y sin RLS estaria abierta del todo, que es el
-- fallo contrario y peor.

do $$
declare
  t         text;
  v_quedan  text;
  v_sin_rls text;
  v_sin_due text;
begin
  select string_agg(polname, ', ') into v_quedan
    from pg_policy
   where polname in ('camiones_public_read','custodios_public_read',
                     'patios_public_read','lavados_public_read');
  if v_quedan is not null then
    raise exception 'H-10 paso 3: todavia estan: %', v_quedan;
  end if;

  foreach t in array array['camiones','custodios','patios','lavados']
  loop
    if not (select relrowsecurity from pg_class where oid = ('public.'||t)::regclass) then
      v_sin_rls := coalesce(v_sin_rls||', ','')||t;
    end if;

    -- Tiene que quedarle AL MENOS una politica de lectura, o el dueno se queda
    -- sin ver sus propias unidades y Mis unidades sale vacia.
    if not exists (
      select 1 from pg_policy p
       where p.polrelid = ('public.'||t)::regclass
         and p.polcmd in ('r', '*')          -- SELECT o ALL
    ) then
      v_sin_due := coalesce(v_sin_due||', ','')||t;
    end if;
  end loop;

  if v_sin_rls is not null then
    raise exception 'H-10 paso 3: RLS apagado en %. Estaria abierta del todo.', v_sin_rls;
  end if;
  if v_sin_due is not null then
    raise exception 'H-10 paso 3: % se quedo sin ninguna politica de lectura: el dueno no veria sus unidades.', v_sin_due;
  end if;

  raise notice 'H-10: las cuatro politicas retiradas. RLS sigue activo y el dueno conserva las suyas.';
  raise notice 'H-10: la flota ajena ya solo se lee por las vistas *_publico.';
end $$;
