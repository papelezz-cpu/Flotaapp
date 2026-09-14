-- ============================================================================
-- A6 (remate): el REVOKE de TRUNCATE se dejo una relacion fuera
-- ============================================================================
--
-- ── Que paso ──────────────────────────────────────────────────────────────
--
-- 20260911130000 revoca truncate/references/trigger sobre una LISTA ESCRITA A
-- MANO de 24 tablas. El esquema tiene 25 relaciones en public: las 24 tablas
-- mas la vista empresas_publico, que tambien recibio GRANT ALL en su momento
-- (20260831210000 hace `grant select`, pero el ALL venia de antes).
--
-- Una vista no se puede truncar, asi que el permiso sobrante no es explotable
-- ni siquiera en teoria. Se retira igual por el mismo motivo que el resto: es
-- un permiso que nadie necesita, y dejarlo obliga a razonar sobre por que esta
-- ahi cada vez que alguien audita los grants.
--
-- ── La leccion, que importa mas que el permiso ────────────────────────────
--
-- El fallo no fue el permiso: fue enumerar a mano algo que la base sabe
-- contar. Una lista escrita a mano envejece en cuanto alguien crea una tabla o
-- una vista, y no avisa — la migracion se aplica sin error y deja el trabajo a
-- medias. Aqui se hace al reves: se le pregunta al catalogo quien tiene el
-- permiso y se le retira a todos, sea cual sea su tipo.
--
-- Es idempotente y sirve tambien como red para el futuro: volver a ejecutarla
-- despues de crear una tabla nueva la deja limpia.
-- ============================================================================

do $$
declare
  r        record;
  v_hechas text[] := '{}';
begin
  for r in
    select c.oid,
           c.oid::regclass::text as rel,
           case c.relkind
             when 'r' then 'tabla' when 'p' then 'tabla particionada'
             when 'v' then 'vista' when 'm' then 'vista materializada'
             when 'f' then 'tabla externa' else c.relkind::text end as tipo
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind in ('r', 'p', 'v', 'm', 'f')
       and has_table_privilege('authenticated', c.oid, 'TRUNCATE')
     order by 2
  loop
    execute format('revoke truncate, references, trigger on %s from authenticated', r.rel);
    v_hechas := v_hechas || (r.rel || ' (' || r.tipo || ')');
  end loop;

  if array_length(v_hechas, 1) is null then
    raise notice 'A6: nada que retirar, authenticated ya no tiene TRUNCATE en public.';
  else
    raise notice 'A6: TRUNCATE retirado de % relacion(es): %',
      array_length(v_hechas, 1), array_to_string(v_hechas, ', ');
  end if;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- Comprobacion
-- ─────────────────────────────────────────────────────────────────────────

do $$
declare
  v_quedan text;
begin
  select string_agg(c.oid::regclass::text, ', ')
    into v_quedan
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind in ('r', 'p', 'v', 'm', 'f')
     and has_table_privilege('authenticated', c.oid, 'TRUNCATE');

  if v_quedan is not null then
    raise exception 'A6: todavia queda TRUNCATE para authenticated en: %', v_quedan;
  end if;
  raise notice 'A6: comprobado, authenticated no puede truncar nada en public.';
end $$;
