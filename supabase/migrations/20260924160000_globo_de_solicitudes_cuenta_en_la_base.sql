-- ============================================================================
-- El globo de «Solicitudes» de la empresa se cuenta en la base (R-09)
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- `actualizarBadgePedidos()` (js/views.js) para el rol `admin` hace esto:
--
--   1. trae el `id` de TODOS los pedidos abiertos,
--   2. trae TODAS las ofertas de esa empresa,
--   3. y cuenta en JavaScript.
--
-- Un contador implementado transfiriendo filas. `auditoria-2.md:535` lo midió:
-- **890 llamadas**, marcado 🟠 ALTA. Y el globo se repinta con cada notificación
-- propia, así que el coste no es de una vez.
--
-- El camino del rol `cliente` ya estaba bien —usa `count: 'exact', head: true`—
-- y no se toca.
--
-- ── Lo que esta migración NO cambia ───────────────────────────────────────
--
-- **El número.** Se comparó la condición del globo con la del panel antes de
-- escribir nada, porque la lección de R-05 fue justamente esa: un globo que
-- cuenta algo distinto de lo que la pantalla lista es peor que no tener globo.
--
--   panel (js/pedidos.js, `disponibles`):
--     estado 'abierto' y ninguna oferta mía «activa» ni «bloqueada», donde
--     activa = estado <> 'rechazada', y bloqueada = rechazada con
--     permite_reoferta en false.
--
--   globo (antes, en JS):
--     excluía si (estado <> 'rechazada') OR (permite_reoferta = false).
--
-- Son equivalentes: si el estado no es 'rechazada' la primera cláusula ya
-- excluye, así que el segundo término solo actúa sobre las rechazadas. La
-- condición de abajo reproduce eso literalmente.
--
-- ── Por qué SECURITY INVOKER y no DEFINER ─────────────────────────────────
--
-- Porque así la visibilidad es **exactamente** la que tiene hoy el navegador:
-- las mismas políticas, evaluadas como el mismo usuario. Verificado que no
-- cambia el resultado —`ped_select` deja leer todo pedido en 'abierto' a
-- cualquier autenticado, y `of_select` deja a la empresa ver sus ofertas—, así
-- que DEFINER no habría dado otro número; pero pedir el privilegio que no se
-- necesita es como se acumulan los H-21.
--
-- `permite_reoferta IS FALSE` y no `= false`: la columna admite NULL, y en JS
-- `o.permite_reoferta === false` es falso cuando viene nulo. Con `= false` un
-- NULL daría NULL y la fila no contaría igual, pero dejarlo explícito evita que
-- alguien lo «simplifique» mañana y cambie el número sin darse cuenta.
-- ============================================================================

create or replace function public.pedidos_disponibles_para_mi()
returns integer
language sql
stable
set search_path to 'public', 'pg_temp'
as $$
  select count(*)::int
    from public.pedidos p
   where p.estado = 'abierto'
     and not exists (
       select 1
         from public.ofertas o
        where o.pedido_id = p.id
          and o.admin_id  = (select auth.uid())
          and (o.estado <> 'rechazada' or o.permite_reoferta is false)
     );
$$;

comment on function public.pedidos_disponibles_para_mi() is
  'R-09: cuenta las solicitudes abiertas en las que esta empresa todavia puede ofertar, con la MISMA condicion que la seccion "Solicitudes disponibles" de js/pedidos.js. Sustituye a un contador que traia todos los pedidos abiertos y todas las ofertas propias para contar en JavaScript (890 llamadas medidas). SECURITY INVOKER a proposito: la visibilidad es la del usuario que llama.';

revoke all on function public.pedidos_disponibles_para_mi() from public, anon;
grant execute on function public.pedidos_disponibles_para_mi() to authenticated;


-- ── Comprobación ───────────────────────────────────────────────────────────

do $$
declare
  v_secdef boolean;
  v_n      int;
begin
  -- No debe ser SECURITY DEFINER: se pidió invoker a propósito.
  select prosecdef into v_secdef from pg_proc where proname = 'pedidos_disponibles_para_mi';
  if v_secdef then
    raise exception 'R-09: la funcion quedo SECURITY DEFINER. Se queria invoker, para que la visibilidad sea la del usuario.';
  end if;

  -- anon fuera, authenticated dentro.
  if has_function_privilege('anon', 'public.pedidos_disponibles_para_mi()', 'EXECUTE') then
    raise exception 'R-09: anon puede ejecutarla.';
  end if;
  if not has_function_privilege('authenticated', 'public.pedidos_disponibles_para_mi()', 'EXECUTE') then
    raise exception 'R-09: authenticated no puede ejecutarla; el globo quedaria siempre oculto.';
  end if;

  -- Y que la condición sea la del panel, no una parecida. Si alguien la
  -- reescribe, esto salta antes de que el globo empiece a mentir.
  select count(*) into v_n from pg_proc
   where proname = 'pedidos_disponibles_para_mi'
     and prosrc like '%permite_reoferta is false%'
     and prosrc like '%o.estado <> ''rechazada''%'
     and prosrc like '%p.estado = ''abierto''%';
  if v_n <> 1 then
    raise exception 'R-09: la condicion no es la esperada. Debe reproducir la de "Solicitudes disponibles" en js/pedidos.js.';
  end if;

  raise notice 'R-09: el globo de solicitudes de la empresa se cuenta en la base, con la condicion del panel.';
end $$;
