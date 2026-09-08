-- ============================================================================
-- H-03: refrigerado y temp_controlada divergen — iguala el histórico
-- ============================================================================
--
-- El comentario de la columna en producción ya dice cuál manda:
--   "Reemplaza el antiguo checkbox temp_controlada, que se sigue escribiendo
--    por compatibilidad."
-- Pero el código leía la vieja (js/pedidos.js:669, js/aprobaciones.js:1000),
-- y esos dos puntos de lectura ya se movieron a `refrigerado` en un commit
-- aparte. Esta migración solo cierra la brecha de datos: los pedidos
-- anteriores a la columna nueva que quedaron con temp_controlada=true y
-- refrigerado=false (medido en producción el 31 ago 2026: 3 de 40 filas).
--
-- No toca la escritura: pedidos.js sigue guardando las dos desde el mismo
-- checkbox, así que no vuelve a divergir hacia adelante. Retirar
-- temp_controlada del todo queda para una fase posterior (columna generada
-- o DROP), fuera de alcance aquí.
-- ============================================================================

-- ── Por que hay que desactivar el guard para esto ────────────────────────
--
-- Corregido el 2026-09-08. La version anterior de este archivo era el UPDATE
-- a secas, y fallaba al aplicarlo con psql:
--
--     ERROR: No autorizado
--     CONTEXT: PL/pgSQL function guard_pedido_update() line 60 at RAISE
--
-- No es un problema de datos: es estructural, y habria fallado igual en
-- cualquier base. trg_guard_pedido_update decide quien puede cambiar que
-- leyendo auth.uid(), y psql conecta como `postgres` SIN JWT, asi que
-- auth.uid() es NULL. El guard entonces:
--
--     is_superadmin()            -> false  (no hay fila con user_id = NULL)
--     OLD.cliente_id = auth.uid()-> NULL   (no entra)
--     es_admin                   -> NULL   (no entra)
--     RAISE EXCEPTION 'No autorizado'      <- cae aqui
--
-- Es decir: el guard hace bien su trabajo. Esta pensado para que nadie
-- cambie un pedido fuera de las transiciones legales, y una correccion de
-- datos por psql no es ninguna de ellas. Hay que apartarlo a proposito.
--
-- Se desactiva SOLO ese trigger y SOLO durante el UPDATE, no
-- session_replication_role: ese apaga todos los triggers y ademas las
-- comprobaciones de clave foranea, que es mucho mas de lo que hace falta.
--
-- DISABLE TRIGGER toma un ACCESS EXCLUSIVE sobre pedidos, y eso aqui es una
-- ventaja: mientras dura la transaccion ninguna otra sesion puede siquiera
-- leer la tabla, asi que no existe una ventana en la que otro escriba
-- saltandose el guard.
--
-- El guion aplica con --single-transaction, asi que si algo falla entre el
-- DISABLE y el ENABLE, la reversion devuelve el trigger a su sitio. El
-- bloque de comprobacion del final esta para que un fallo sea ruidoso y no
-- se quede el guard apagado en silencio.

alter table public.pedidos disable trigger trg_guard_pedido_update;

update public.pedidos
   set refrigerado = true
 where temp_controlada = true
   and refrigerado is distinct from true;

alter table public.pedidos enable trigger trg_guard_pedido_update;


-- ── Comprobacion: el guard volvio, y no quedan filas divergentes ─────────
do $$
declare
  v_activo char;
  v_div    int;
begin
  select t.tgenabled into v_activo
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
   where c.relname = 'pedidos' and t.tgname = 'trg_guard_pedido_update';

  if v_activo is distinct from 'O' then
    raise exception 'trg_guard_pedido_update quedo desactivado (tgenabled=%). Abortando.', v_activo;
  end if;

  select count(*) into v_div
    from public.pedidos
   where temp_controlada = true and refrigerado is distinct from true;

  if v_div <> 0 then
    raise exception 'quedan % pedidos con temp_controlada=true y refrigerado distinto', v_div;
  end if;

  raise notice 'refrigerado igualado: 0 filas divergentes, guard activo';
end $$;
