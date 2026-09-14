-- ============================================================================
-- empresas_publico aceptaba escrituras de cualquier usuario con sesion
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- Volcado de produccion del 2026-09-14 13:52 UTC:
--
--     GRANT SELECT,INSERT,DELETE,MAINTAIN,UPDATE ON TABLE public.empresas_publico TO authenticated;
--
-- Tres cosas se juntan y ninguna es un fallo por si sola:
--
--   1. empresas_publico es una vista simple sobre perfiles -- un solo FROM,
--      sin agregados, sin DISTINCT -- asi que PostgreSQL la considera
--      AUTO-ACTUALIZABLE: un INSERT/UPDATE/DELETE contra la vista se traduce
--      a la tabla base.
--
--   2. Corre con security_invoker en su valor por omision (false), A PROPOSITO
--      -- lo explica 20260831210000. Eso significa que NO aplica el RLS de
--      perfiles. Para leer es justo lo que se queria.
--
--   3. Tiene concedidos INSERT, UPDATE y DELETE a authenticated.
--
-- Juntas: cualquier cuenta con sesion podia escribir y BORRAR filas de
-- perfiles saltandose el RLS.
--
-- ── Que quedaba expuesto ──────────────────────────────────────────────────
--
-- trg_guard_perfil_self_update SI se dispara en las escrituras enrutadas por
-- la vista, y bloquea rol, aprobacion_cuenta y los campos de verificacion.
-- No bloquea el resto. De las 15 columnas de la vista quedaban escribibles:
--
--     nombre, razon_social, rfc, descripcion, telefono, anos_operacion,
--     num_unidades, seguro_rc, seguro_carga, permiso_sct,
--     fecha_vencimiento_permiso_sct, fecha_vencimiento_seguro_rc,
--     fecha_vencimiento_seguro_carga
--
-- Las tres ultimas son EXACTAMENTE las que lee guard_oferta_update para
-- decidir si una empresa puede cerrar un trato. Una cuenta podia ponerle a un
-- competidor una fecha pasada y dejarlo sin poder aceptar ofertas.
--
-- Y el DELETE es peor: perfiles NO TIENE NINGUNA POLITICA FOR DELETE. Contra
-- la tabla, con RLS activo y sin politica, no puede borrar nadie. La vista era
-- literalmente el unico camino de borrado que existia para authenticated, y
-- borrar una fila de perfiles arrastra ON DELETE CASCADE sobre notificaciones
-- y ON DELETE SET NULL sobre su flota, sus ofertas y sus reservaciones.
--
-- No hay indicio de que se haya usado: las 12 filas de perfiles del volcado
-- son coherentes. Eso no es una defensa, es una casualidad.
--
-- ── La causa de fondo, que importa mas que este caso ──────────────────────
--
-- No fue un descuido al escribir 20260831210000. Esa migracion hizo:
--
--     revoke all on public.empresas_publico from anon, public;
--     grant  select on public.empresas_publico to authenticated;
--
-- y es correcto salvo por un detalle: el REVOKE apunta a anon y a public, no a
-- authenticated. Y authenticated ya tenia ALL, porque el esquema lleva puesto:
--
--     ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
--       GRANT ALL ON TABLES TO authenticated;
--
-- En PostgreSQL, "TABLES" en los privilegios por omision cubre tambien las
-- VISTAS. Es decir: TODA vista creada en public nace con ALL concedido a
-- authenticated, y un `grant select` posterior no retira nada -- solo vuelve a
-- conceder algo que ya estaba dentro de ALL.
--
-- Lo mismo le paso a 20260911150000 (A6), que retiro TRUNCATE, REFERENCES y
-- TRIGGER preguntandole al catalogo en vez de enumerar a mano. Funciono: esos
-- tres ya no estan. Pero la lista de privilegios a retirar SI estaba escrita a
-- mano, y dejo fuera los tres que importaban.
--
-- ── Lo que esta migracion NO hace, y por que ──────────────────────────────
--
-- NO toca ALTER DEFAULT PRIVILEGES.
--
-- La tentacion es evidente: retirar INSERT/UPDATE/DELETE de los privilegios
-- por omision y que ninguna vista futura vuelva a nacer escribible. Se
-- descarta porque ese mismo ajuste alcanza a las TABLAS futuras, y en este
-- proyecto las tablas SI necesitan esos permisos: RLS es la frontera, no el
-- GRANT. Comprobado: 20260728160000 y 20260729160000 crean tablas y NO
-- conceden nada explicitamente -- dependen por completo de los privilegios por
-- omision.
--
-- Cambiarlos dejaria la siguiente tabla nueva legible y no escribible, y el
-- fallo aparece con cara de problema de RLS. Es una decision con
-- consecuencias, y no se toma de paso dentro de un arreglo de seguridad.
--
-- ── CONSECUENCIA PARA QUIEN CREE LA PROXIMA VISTA ─────────────────────────
--
-- Mientras los privilegios por omision sigan como estan, TODA vista nueva en
-- public nace escribible por authenticated. Crear una vista y poner
-- `grant select` NO basta: hay que retirar la escritura explicitamente.
--
-- Esto es inmediato, no teorico: el plan de la auditoria propone cuatro vistas
-- nuevas (camiones_publico, custodios_publico, patios_publico,
-- lavados_publico). Sin el revoke, cada una nace con este mismo defecto.
--
-- El bloque 2 de abajo es idempotente a proposito: volver a ejecutarlo despues
-- de crear una vista la deja limpia.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────
-- 1. El caso concreto
-- ─────────────────────────────────────────────────────────────────────────
-- SELECT se conserva: es para lo que se creo la vista, y las 13 lecturas del
-- cliente dependen de el (catalogo.js, detalle.js, reservaciones.js,
-- camiones.js, recursos.js, reportes.js, admin.js, pedidos.js).
-- service_role no se toca: las Edge Functions escriben con esa clave.
--
-- MAINTAIN entra aqui por higiene, no por riesgo: sobre una vista no
-- materializada no habilita nada util. Es otro resto del GRANT ALL.

revoke insert, update, delete, maintain on public.empresas_publico from authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. Y la causa: ninguna vista de public debe aceptar escrituras
-- ─────────────────────────────────────────────────────────────────────────
-- Se le pregunta al catalogo en vez de enumerar a mano. Misma leccion que A6,
-- aplicada esta vez a los privilegios que si eran explotables.
--
-- Solo se retiran privilegios de ESCRITURA. SELECT no se toca: hay vistas que
-- existen precisamente para ser leidas, y retirarselo dejaria el catalogo en
-- blanco. Se cubren anon y authenticated; service_role queda fuera a
-- proposito.
--
-- Una vista no tiene RLS detras. Una tabla si. Por eso esto se aplica a
-- relkind in ('v','m') y no a las tablas.

do $$
declare
  r        record;
  v_hechas text[] := '{}';
begin
  for r in
    select c.oid,
           c.oid::regclass::text as rel,
           case c.relkind when 'v' then 'vista' else 'vista materializada' end as tipo,
           g.rol
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      cross join (values ('anon'), ('authenticated')) as g(rol)
     where n.nspname = 'public'
       and c.relkind in ('v', 'm')
       and (has_table_privilege(g.rol, c.oid, 'INSERT')
         or has_table_privilege(g.rol, c.oid, 'UPDATE')
         or has_table_privilege(g.rol, c.oid, 'DELETE')
         or has_table_privilege(g.rol, c.oid, 'MAINTAIN'))
     order by 2, 4
  loop
    execute format('revoke insert, update, delete, maintain on %s from %I', r.rel, r.rol);
    v_hechas := v_hechas || (r.rel || ' (' || r.tipo || ') <- ' || r.rol);
  end loop;

  if array_length(v_hechas, 1) is null then
    raise notice 'Vistas: nada que retirar, ninguna acepta escrituras de anon ni authenticated.';
  else
    raise notice 'Vistas: escritura retirada en % caso(s): %',
      array_length(v_hechas, 1), array_to_string(v_hechas, ', ');
  end if;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion
-- ─────────────────────────────────────────────────────────────────────────
-- Dos direcciones, y las dos importan. La primera es el arreglo. La SEGUNDA es
-- la que evita cambiar un agujero por una pantalla en blanco: si alguien
-- endurece esto de mas y retira tambien el SELECT, el catalogo de empresas
-- deja de cargar y el sintoma (nombres como "—") no apunta al permiso.

do $$
declare
  v_quedan text;
begin
  select string_agg(c.oid::regclass::text || ' <- ' || g.rol, ', ')
    into v_quedan
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join (values ('anon'), ('authenticated')) as g(rol)
   where n.nspname = 'public'
     and c.relkind in ('v', 'm')
     and (has_table_privilege(g.rol, c.oid, 'INSERT')
       or has_table_privilege(g.rol, c.oid, 'UPDATE')
       or has_table_privilege(g.rol, c.oid, 'DELETE')
       or has_table_privilege(g.rol, c.oid, 'MAINTAIN'));

  if v_quedan is not null then
    -- Si esto salta DESPUES del bloque 2, el revoke directo no basto: casi
    -- seguro el privilegio no es directo sino heredado -- concedido a PUBLIC,
    -- que alcanza a todos los roles. Comprobar con:
    --   select relacl from pg_class where oid = 'public.<vista>'::regclass;
    raise exception 'Todavia hay vistas escribibles en public: %. Si el revoke ya corrio, mirar si el privilegio esta concedido a PUBLIC.', v_quedan;
  end if;

  if not has_table_privilege('authenticated', 'public.empresas_publico', 'SELECT') then
    raise exception 'Se ha retirado de mas: authenticated ya no puede LEER empresas_publico. El catalogo de empresas y la ficha publica se quedarian en blanco.';
  end if;

  raise notice 'Comprobado: ninguna vista de public acepta escrituras, y empresas_publico se sigue leyendo.';
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- Como revertir
-- ─────────────────────────────────────────────────────────────────────────
--   grant insert, update, delete on public.empresas_publico to authenticated;
--
-- No hace falta mas: esta migracion no modifica ni una sola fila, solo
-- permisos. Pero revertirla es reabrir el agujero, no deshacer un error.
