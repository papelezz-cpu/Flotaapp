-- ============================================================================
-- A5 + A6 + M7: cerrar las tres puertas de permisos que quedaron entornadas
-- ============================================================================
--
-- Las tres comparten causa: la migracion 20260827160000 cerro el acceso de anon
-- retirando los permisos que EXISTIAN en ese momento. Eso es una fotografia, y
-- debajo quedaron tres cosas que la fotografia no toco.
--
-- Ninguna de las tres es explotable hoy a traves de PostgREST. Se arreglan
-- igualmente porque las tres dejan la seguridad apoyada en una sola capa donde
-- el diseno quiso tener dos, y porque el coste de cerrarlas es una linea cada
-- una.
--
-- ── A5 · El privilegio por defecto ────────────────────────────────────────
--
-- Verificado en el volcado de produccion del 2026-09-08:
--
--   ALTER DEFAULT PRIVILEGES FOR ROLE postgres       ... TO postgres, authenticated, service_role;
--   ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin ... TO postgres, anon, authenticated, service_role;
--                                                                    ^^^^
-- La linea de postgres ya no incluye anon. La de supabase_admin si. El arreglo
-- se aplico a un rol y no al otro.
--
-- Consecuencia: cualquier tabla que cree supabase_admin en public nace con ALL
-- para anon. Con RLS activada y sin politicas no se lee nada, asi que hoy no
-- pasa nada. Pero una tabla nueva a la que se olviden de activarle RLS queda
-- abierta a internet sin que nadie haya escrito un GRANT — y eso no aparece al
-- revisar el diff de la migracion que la creo, porque no esta en la migracion.
--
-- ⚠ Esta parte puede NO aplicarse. Cambiar los privilegios por defecto de un rol
--   exige ser miembro de ese rol, y el rol que aplica migraciones no lo es. Va
--   dentro de un bloque que avisa en vez de reventar: el resto de la migracion
--   es independiente y debe aplicarse igual. Ver el aviso del bloque 1.
--
-- ── A6 · TRUNCATE ─────────────────────────────────────────────────────────
--
-- Las 24 tablas tienen GRANT ALL ... TO authenticated, y ALL incluye TRUNCATE,
-- REFERENCES y TRIGGER. TRUNCATE IGNORA LA RLS por completo: no es una
-- operacion que las politicas puedan filtrar.
--
-- PostgREST no expone TRUNCATE, asi que no hay camino hoy. Pero es un permiso
-- que la aplicacion no usa jamas, y dejarlo hace que la seguridad de las 24
-- tablas dependa de que ninguna via futura ejecute SQL como authenticated.
--
-- ── M7 · Politicas sin clausula TO ────────────────────────────────────────
--
-- 33 de las 74 politicas se declararon sin TO, asi que aplican a TODOS los
-- roles, anon incluido. Hoy anon no tiene privilegios de tabla, de modo que no
-- llega a evaluarlas — pero es la misma capa unica de siempre, y A5 describe con
-- que facilidad puede reabrirse sin que nadie lo note.
--
-- Se usa ALTER POLICY ... TO y no DROP + CREATE a proposito: ALTER cambia SOLO
-- los roles y deja USING y WITH CHECK intactos. Reescribir 33 expresiones de
-- politica a mano es exactamente el tipo de cambio que introduce un agujero
-- mientras cierra otro.
--
-- app_config_select se queda como esta: es TO authenticated, anon a proposito,
-- porque la app lee la configuracion antes de que nadie inicie sesion.
--
-- ── Reversion ─────────────────────────────────────────────────────────────
--
-- Cada sentencia tiene su contraria: grant truncate/references/trigger,
-- alter policy ... to public, y el alter default privileges con grant. Nada de
-- esto borra datos ni objetos.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. A5 — el privilegio por defecto que reparte tablas futuras a anon
-- ─────────────────────────────────────────────────────────────────────────
do $$
begin
  alter default privileges for role supabase_admin in schema public
    revoke all on tables from anon;
  alter default privileges for role supabase_admin in schema public
    revoke all on sequences from anon;
  raise notice 'A5: privilegios por defecto de supabase_admin cerrados para anon.';
exception when insufficient_privilege then
  raise warning
    'A5 NO APLICADO: hace falta ser miembro de supabase_admin para cambiar sus '
    'privilegios por defecto, y este rol no lo es. El resto de la migracion si se '
    'aplico. Ejecuta estas dos lineas desde el SQL Editor del panel de Supabase, '
    'que corre con mas privilegios; si tampoco puede, es cosa de soporte. '
    'Mientras no se haga, cualquier tabla nueva que cree supabase_admin nacera '
    'con ALL para anon.';
end $$;

-- Las dos secuencias que hoy tienen ALL para anon (B6). Ningun cliente las
-- alcanza —PostgREST no expone secuencias— pero no hay motivo para el permiso.
revoke all on sequence public.custodios_seq from anon;
revoke all on sequence public.patios_seq   from anon;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. A6 — authenticated no necesita TRUNCATE, y TRUNCATE ignora la RLS
-- ─────────────────────────────────────────────────────────────────────────
-- Se retiran los tres verbos que la aplicacion no usa jamas y se dejan
-- intactos SELECT/INSERT/UPDATE/DELETE, que son los que mueve PostgREST.

revoke truncate, references, trigger on table public.app_config from authenticated;
revoke truncate, references, trigger on table public.calificaciones from authenticated;
revoke truncate, references, trigger on table public.camiones from authenticated;
revoke truncate, references, trigger on table public.catalogos from authenticated;
revoke truncate, references, trigger on table public.consentimientos from authenticated;
revoke truncate, references, trigger on table public.custodios from authenticated;
revoke truncate, references, trigger on table public.documentos_catalogo from authenticated;
revoke truncate, references, trigger on table public.documentos_fiscales from authenticated;
revoke truncate, references, trigger on table public.expediente_documentos from authenticated;
revoke truncate, references, trigger on table public.expedientes from authenticated;
revoke truncate, references, trigger on table public.lavados from authenticated;
revoke truncate, references, trigger on table public.mensajes from authenticated;
revoke truncate, references, trigger on table public.notificaciones from authenticated;
revoke truncate, references, trigger on table public.ofertas from authenticated;
revoke truncate, references, trigger on table public.operadores from authenticated;
revoke truncate, references, trigger on table public.pagos from authenticated;
revoke truncate, references, trigger on table public.patios from authenticated;
revoke truncate, references, trigger on table public.pedidos from authenticated;
revoke truncate, references, trigger on table public.perfiles from authenticated;
revoke truncate, references, trigger on table public.plantillas_pedido from authenticated;
revoke truncate, references, trigger on table public.reservaciones from authenticated;
revoke truncate, references, trigger on table public.reservaciones_historico from authenticated;
revoke truncate, references, trigger on table public.solicitudes_arco from authenticated;
revoke truncate, references, trigger on table public.solicitudes_cuenta from authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. M7 — las 33 politicas que no declaraban a quien se aplican
-- ─────────────────────────────────────────────────────────────────────────
-- ALTER POLICY ... TO cambia SOLO los roles: deja USING y WITH CHECK tal
-- como estan. Por eso no hace falta reescribir ni una expresion aqui, que
-- es justo lo que haria peligroso este cambio.


-- public.camiones
alter policy "Actualizar camiones" on public.camiones to authenticated;
alter policy "Eliminar camiones" on public.camiones to authenticated;
alter policy "Insertar camiones" on public.camiones to authenticated;
alter policy camiones_owner_read on public.camiones to authenticated;

-- public.custodios
alter policy custodios_owner_all on public.custodios to authenticated;
alter policy custodios_superadmin on public.custodios to authenticated;

-- public.documentos_fiscales
alter policy admin_ve_sus_docs on public.documentos_fiscales to authenticated;
alter policy cliente_ve_sus_docs on public.documentos_fiscales to authenticated;
alter policy superadmin_ve_todo_docs on public.documentos_fiscales to authenticated;

-- public.lavados
alter policy lavados_owner_all on public.lavados to authenticated;
alter policy lavados_superadmin on public.lavados to authenticated;

-- public.mensajes
alter policy mensajes_insert on public.mensajes to authenticated;
alter policy mensajes_select on public.mensajes to authenticated;
alter policy mensajes_update on public.mensajes to authenticated;

-- public.ofertas
alter policy of_insert on public.ofertas to authenticated;
alter policy of_update on public.ofertas to authenticated;

-- public.operadores
alter policy sel_operadores on public.operadores to authenticated;

-- public.pagos
alter policy admin_registra_pago_manual on public.pagos to authenticated;
alter policy admin_ve_sus_pagos on public.pagos to authenticated;
alter policy cliente_ve_sus_pagos on public.pagos to authenticated;
alter policy superadmin_gestiona_pagos on public.pagos to authenticated;

-- public.patios
alter policy patios_owner_all on public.patios to authenticated;
alter policy patios_superadmin on public.patios to authenticated;

-- public.pedidos
alter policy ped_delete on public.pedidos to authenticated;
alter policy ped_insert_own on public.pedidos to authenticated;
alter policy ped_update on public.pedidos to authenticated;

-- public.reservaciones
alter policy reservaciones_delete on public.reservaciones to authenticated;
alter policy reservaciones_select on public.reservaciones to authenticated;
alter policy reservaciones_update on public.reservaciones to authenticated;

-- public.reservaciones_historico
alter policy superadmin_historico_all on public.reservaciones_historico to authenticated;

-- public.solicitudes_cuenta
alter policy sc_insert on public.solicitudes_cuenta to authenticated;
alter policy sc_select on public.solicitudes_cuenta to authenticated;
alter policy sc_update_super on public.solicitudes_cuenta to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 4. Comprobacion: que no quede ninguna politica sin TO
-- ─────────────────────────────────────────────────────────────────────────
-- app_config_select es la unica excepcion legitima, y lleva anon a proposito.

do $$
declare
  v_faltan text;
begin
  select string_agg(tablename || '.' || policyname, ', ')
    into v_faltan
    from pg_policies
   where schemaname = 'public'
     and roles = '{public}'
     and policyname <> 'app_config_select';

  if v_faltan is not null then
    raise warning 'Siguen sin clausula TO: %', v_faltan;
  else
    raise notice 'M7: todas las politicas declaran a quien se aplican.';
  end if;
end $$;
