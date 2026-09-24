-- ============================================================================
-- Un recurso sin dueño no puede existir  (hueco 9 de FLUJO-OPERATIVO.md)
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- `propietario_id` era **nullable en las cinco tablas de flota**, y había 7
-- filas sin dueño: los custodios CUS-001, CUS-002, CUS-003, CUS-006 y los
-- patios PAT-001, PAT-002, PAT-005. Todos `aprobada`.
--
-- No era cosmético. `vigencia_propietario()` devuelve NULL para ellos, y la
-- política `vigencia_propietario(...) = auth.uid()` compara contra NULL, que
-- **nunca da verdadero**. Consecuencia medida el 2026-09-23: sus documentos
-- solo los veía el superadmin, y **ninguna empresa podía renovarlos** porque
-- ninguna era su dueña. En el panel de Vigencias aparecían agrupados bajo una
-- empresa sin nombre — que es correcto, porque no había empresa que poner.
--
-- ── La decisión ───────────────────────────────────────────────────────────
--
-- **Del usuario, 2026-09-24:** los siete se asignan a **Omar Silva Preciado**
-- (`5919a6f2-03f0-4ccc-877f-fb9fc75139da`), y el dueño pasa a ser
-- **obligatorio** para que no vuelva a ocurrir.
--
-- El id es el mismo en los dos proyectos: el verificador de paridad confirmó
-- ese mismo día que los usuarios de auth son idénticos (13 líneas iguales).
--
-- ── Dos cosas que esta migración tiene que esquivar ───────────────────────
--
-- 1. **El guard de flota bloquea cambiar el dueño.**
--    `guard_fleet_resource_update` lanza «No autorizado: no puedes transferir
--    la propiedad de este recurso» en cuanto `propietario_id` cambia, salvo
--    para un superadmin. psql conecta sin JWT, así que `auth.uid()` es NULL,
--    `is_superadmin()` da false y la migración se bloquearía a sí misma. Se
--    aparta el trigger DENTRO de la transacción, como hizo 20260915120000 con
--    trg_guard_pedido_update, y se vuelve a encender antes de terminar.
--
-- 2. **El orden importa.** Primero se asigna el dueño, después se pone el
--    NOT NULL. Al revés, el ALTER fallaría por las 7 filas existentes.
--
-- ⚠ ESTO MODIFICA DATOS: 7 filas cambian de dueño. No borra nada y es
--   re-aplicable (el UPDATE está acotado a `propietario_id is null`).
-- ============================================================================

-- ── 1 · Asignar dueño a los huérfanos ─────────────────────────────────────

alter table public.custodios disable trigger trg_guard_custodios_update;
alter table public.patios    disable trigger trg_guard_patios_update;

update public.custodios
   set propietario_id = '5919a6f2-03f0-4ccc-877f-fb9fc75139da'
 where propietario_id is null;

update public.patios
   set propietario_id = '5919a6f2-03f0-4ccc-877f-fb9fc75139da'
 where propietario_id is null;

alter table public.custodios enable trigger trg_guard_custodios_update;
alter table public.patios    enable trigger trg_guard_patios_update;


-- ── 2 · Y que no vuelva a pasar ───────────────────────────────────────────
-- Las cinco tablas, aunque hoy solo dos tuvieran huérfanos: dejar tres
-- nullables sería dejar la puerta abierta por donde no ha entrado nadie
-- todavía. Comprobado antes de escribir esto que **todas las altas ponen
-- propietario_id** (js/admin.js:1010, :1133, :1318, :1464 y
-- js/operadores.js:422), así que el NOT NULL no rompe ningún camino.

alter table public.camiones   alter column propietario_id set not null;
alter table public.operadores alter column propietario_id set not null;
alter table public.custodios  alter column propietario_id set not null;
alter table public.patios     alter column propietario_id set not null;
alter table public.lavados    alter column propietario_id set not null;


-- ── 3 · Comprobación ──────────────────────────────────────────────────────

do $$
declare
  v_nulos    int;
  v_nullable text;
  v_apagado  text;
  v_omar     int;
begin
  -- El dueño existe. Si el id estuviera mal, las 7 filas apuntarían a nadie y
  -- el problema sería el mismo con otra cara.
  select count(*) into v_omar from public.perfiles
   where user_id = '5919a6f2-03f0-4ccc-877f-fb9fc75139da' and rol = 'admin';
  if v_omar <> 1 then
    raise exception 'El propietario asignado no existe como perfil admin en esta base. Revisar el user_id antes de reintentar.';
  end if;

  -- Ninguna fila sin dueño.
  select coalesce(sum(n), 0) into v_nulos from (
    select count(*) n from public.camiones   where propietario_id is null
    union all select count(*) from public.operadores where propietario_id is null
    union all select count(*) from public.custodios  where propietario_id is null
    union all select count(*) from public.patios     where propietario_id is null
    union all select count(*) from public.lavados    where propietario_id is null) s;
  if v_nulos > 0 then
    raise exception 'Quedan % recursos sin dueño.', v_nulos;
  end if;

  -- Y la columna es obligatoria en las cinco.
  select string_agg(table_name, ', ') into v_nullable
    from information_schema.columns
   where table_schema = 'public' and column_name = 'propietario_id'
     and table_name in ('camiones','operadores','custodios','patios','lavados')
     and is_nullable = 'YES';
  if v_nullable is not null then
    raise exception 'propietario_id sigue admitiendo nulos en: %', v_nullable;
  end if;

  -- Los guards volvieron a estar encendidos. Si el bloque 1 fallara a mitad
  -- dejándolos apagados, cualquiera podría transferirse un recurso ajeno y
  -- nadie se enteraría — que es peor que el problema que vino a arreglar.
  select string_agg(c.relname, ', ') into v_apagado
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal
     and t.tgfoid = 'public.guard_fleet_resource_update()'::regprocedure
     and t.tgenabled = 'D';
  if v_apagado is not null then
    raise exception 'GRAVE: el guard de flota quedo DESHABILITADO en: %', v_apagado;
  end if;

  raise notice 'Recursos con dueño obligatorio en las cinco tablas. % recursos asignados a Omar Silva Preciado.',
    (select count(*) from public.custodios where propietario_id = '5919a6f2-03f0-4ccc-877f-fb9fc75139da')
    + (select count(*) from public.patios  where propietario_id = '5919a6f2-03f0-4ccc-877f-fb9fc75139da');
end $$;
