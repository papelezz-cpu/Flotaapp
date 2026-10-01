-- ═════════════════════════════════════════════════════════════════════════
-- Q-09 · El catalogo descargaba todas las calificaciones para contar
-- ═════════════════════════════════════════════════════════════════════════
--
-- El defecto (quinta auditoria, 2026-09-29; medido de nuevo el 2026-09-30):
-- renderCatalogo() (js/catalogo.js) pide TODAS las calificaciones de todas
-- las empresas visibles —rating, comentario y fecha— solo para pintar en cada
-- tarjeta cuantas hay y su promedio. Crece con cada calificacion y trae texto
-- que esa pantalla no pinta (regla 43: no traer lo que no se pinta). Los
-- comentarios se piden aparte, por empresa, al abrir «Ver reseñas».
--
-- El arreglo: una vista con lo unico que la tarjeta necesita —empresa, total
-- y promedio—, calculada en la base. El catalogo pasa a leer la vista (mismo
-- commit, js/catalogo.js).
--
--   · security_invoker = true: se aplica la RLS de `calificaciones` de quien
--     consulta, como en `vigencias_caducidad`. Hoy esa RLS deja leer a todo
--     `authenticated` ("Todos pueden ver calificaciones"), asi que la vista no
--     abre nada que no estuviera abierto; si un dia se cierra, la vista lo
--     hereda sola.
--   · Regla 1/10: la vista nace con privilegios por omision. Se revoca todo a
--     anon, authenticated y service_role, y se concede solo SELECT a
--     authenticated. Una vista de solo lectura, para todos.
--
-- Sin DROP; `create or replace view` es idempotente mientras las columnas no
-- cambien. Reglas de docs/AUDITORIA.md §4: 1, 2, 10, 43.
-- ═════════════════════════════════════════════════════════════════════════


create or replace view public.calificaciones_resumen
with (security_invoker = true) as
select admin_id,
       count(*)::int                   as total,
       round(avg(rating)::numeric, 2)  as promedio
  from public.calificaciones
 group by admin_id;

comment on view public.calificaciones_resumen is
  'Q-09 (20260930193000): total y promedio de calificaciones por empresa, '
  'para las tarjetas del catalogo. security_invoker=true A PROPOSITO: hereda '
  'la RLS de calificaciones de quien consulta. Solo lectura.';

revoke all on public.calificaciones_resumen from public, anon, authenticated, service_role;
grant select on public.calificaciones_resumen to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Comprobacion — falla si el objetivo no se cumplio
-- ─────────────────────────────────────────────────────────────────────────
-- Como sabe fallar: sin el REVOKE la vista seria escribible o legible por
-- anon (privilegios por omision); sin security_invoker el catalogo del
-- servidor la delata; y el total y el promedio se contrastan contra la tabla.

do $$
declare
  v_opts   text[];
  v_malas  int;
begin
  select reloptions into v_opts from pg_class where oid = 'public.calificaciones_resumen'::regclass;
  if v_opts is null or not ('security_invoker=true' = any (v_opts)) then
    raise exception 'Q-09: calificaciones_resumen no es security_invoker.';
  end if;

  if has_table_privilege('anon', 'public.calificaciones_resumen', 'SELECT')
  or has_table_privilege('authenticated', 'public.calificaciones_resumen', 'INSERT')
  or has_table_privilege('authenticated', 'public.calificaciones_resumen', 'UPDATE')
  or has_table_privilege('authenticated', 'public.calificaciones_resumen', 'DELETE')
  or has_table_privilege('service_role',  'public.calificaciones_resumen', 'INSERT') then
    raise exception 'Q-09: calificaciones_resumen es escribible o legible por anon.';
  end if;
  if not has_table_privilege('authenticated', 'public.calificaciones_resumen', 'SELECT') then
    raise exception 'Q-09: authenticated no puede leer calificaciones_resumen.';
  end if;

  -- Los numeros cuadran con la tabla, empresa por empresa.
  select count(*) into v_malas
    from (select admin_id, count(*)::int t, round(avg(rating)::numeric, 2) p
            from public.calificaciones group by admin_id) c
    full join public.calificaciones_resumen r using (admin_id)
   where r.total is distinct from c.t or r.promedio is distinct from c.p;
  if v_malas > 0 then
    raise exception 'Q-09: calificaciones_resumen no cuadra con calificaciones en % empresa(s).', v_malas;
  end if;

  raise notice 'Q-09: calificaciones_resumen lista (solo lectura, security_invoker); cuadra con la tabla.';
end $$;
