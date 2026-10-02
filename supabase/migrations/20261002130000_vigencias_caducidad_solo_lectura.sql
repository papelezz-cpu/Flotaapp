-- ════════════════════════════════════════════════════════════════════════
-- S-06 · La vista vigencias_caducidad seguía escribible por service_role
-- ════════════════════════════════════════════════════════════════════════
--
-- El defecto (6ª auditoría, 2026-10-01). `20260923130000` creó la vista y le
-- quitó la escritura a `authenticated`, pero no a `service_role`, que la
-- recibe por los privilegios por omisión de producción (ALL on TABLES, y en
-- PostgreSQL «TABLES» incluye las vistas). Medido en el volcado del 28/09:
-- service_role tiene INSERT, UPDATE, DELETE y MAINTAIN. La vista es una
-- consulta simple sobre `vigencias`, así que es auto-actualizable: una
-- escritura contra ella cae en la tabla base.
--
-- Es exactamente lo que la regla 10 de docs/AUDITORIA.md existe para
-- impedir (R-07: el barrido de H-01 olvidó el mismo tercer rol): «una vista
-- declarada de solo lectura tiene que serlo para todos». Riesgo bajo —la
-- clave de servicio solo vive en secretos de Edge Function—, pero hoy es la
-- única vista del esquema con escritura para algún rol.
--
-- Nada usa la vista con service_role (medido el 02/10: ni las dos Edge
-- Functions, ni Android, ni los guiones de pruebas/). La lectura se conserva.
-- TRUNCATE no se toca: sobre una vista no hace nada (PostgreSQL no permite
-- vaciar una vista), y las otras siete vistas lo tienen igual.
--
-- Reglas de docs/AUDITORIA.md §4: 1, 2, 10.
-- ════════════════════════════════════════════════════════════════════════

revoke insert, update, delete, maintain on public.vigencias_caducidad from service_role;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--   · ninguno de anon, authenticated, service_role puede INSERT/UPDATE/DELETE;
--   · authenticated y service_role siguen pudiendo leerla (lo que usa la app);
--   · y un UPDATE real como service_role se rechaza por privilegio. Lleva
--     `where false`: con el privilegio puesto no tocaría ni una fila, así que
--     la prueba no puede escribir nada aunque falle el REVOKE.
-- Como sabe fallar: sin el REVOKE, service_role conserva INSERT y el UPDATE
-- pasa.

do $$
declare
  v_rol    text;
  v_priv   text;
  v_quien  text := current_user;
  v_fallos text[] := '{}';
  v_msg    text;
  v_estado text;
begin
  foreach v_rol in array array['anon', 'authenticated', 'service_role'] loop
    foreach v_priv in array array['INSERT', 'UPDATE', 'DELETE'] loop
      if has_table_privilege(v_rol, 'public.vigencias_caducidad', v_priv) then
        v_fallos := v_fallos || format('%s conserva %s', v_rol, v_priv);
      end if;
    end loop;
  end loop;

  foreach v_rol in array array['authenticated', 'service_role'] loop
    if not has_table_privilege(v_rol, 'public.vigencias_caducidad', 'SELECT') then
      v_fallos := v_fallos || format('%s perdió SELECT', v_rol);
    end if;
  end loop;

  begin
    perform set_config('role', 'service_role', true);
    execute 'update public.vigencias_caducidad set estado = estado where false';
    v_msg := 'PASO';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  end;
  perform set_config('role', v_quien, true);
  if v_msg = 'PASO' then
    v_fallos := v_fallos || 'un UPDATE como service_role no se rechazó'::text;
  elsif v_estado <> '42501' then
    v_fallos := v_fallos || format('el UPDATE como service_role falló por otra causa (%s %s)', v_estado, v_msg);
  end if;

  if current_user <> v_quien then
    raise exception 'S-06: la comprobación dejó el rol en % (era %).', current_user, v_quien;
  end if;
  if cardinality(v_fallos) > 0 then
    raise exception E'S-06: vigencias_caducidad no quedó de solo lectura:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'S-06: vigencias_caducidad es de solo lectura para anon, authenticated y service_role; la lectura se conserva.';
end $$;
