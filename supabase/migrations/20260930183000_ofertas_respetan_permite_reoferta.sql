-- ═════════════════════════════════════════════════════════════════════════
-- Q-18 · «No permitir que vuelva a ofertar» solo lo cumplia la interfaz
-- ═════════════════════════════════════════════════════════════════════════
--
-- El defecto (anotado al escribir Q-04, 2026-09-29; comprobado en `dev` el
-- 2026-09-30): al rechazar una oferta, el cliente puede marcar que esa
-- empresa NO vuelva a ofertar en la solicitud (`ofertas.permite_reoferta =
-- false`; tambien lo pone cancelar_reservacion() para quien cancela). Solo lo
-- respeta la interfaz: js/pedidos.js aparta esa solicitud de las
-- «disponibles» de la empresa. La base acepta la oferta nueva: una segunda
-- pestana o una llamada directa a la API se saltan la decision del cliente.
--
-- El arreglo: una comprobacion mas en `guard_oferta_insert()` (Q-04,
-- 20260929160000). Si la empresa tiene en esa solicitud una oferta
-- `rechazada` con `permite_reoferta = false`, la nueva se rechaza.
--
-- La funcion NO se reescribe a mano (regla 3; R-11): se lee su definicion
-- viva, se inserta el bloque justo despues de la comprobacion del estado del
-- pedido, y el bloque de verificacion comprueba que es lo unico que cambio.
-- Si la funcion viva no tiene exactamente una vez ese punto de anclaje, no se
-- toca nada y la migracion aborta.
--
-- Lo que no cambia: superadmin y clave de servicio siguen saliendo antes;
-- volver a ofertar tras un rechazo que SI lo permite sigue funcionando.
--
-- Reglas de docs/AUDITORIA.md §4: 2, 3 (comparar la definicion antes y
-- despues), 9 (sin DROP), 16 (nada de reglas solo en el cliente).
-- ═════════════════════════════════════════════════════════════════════════


create temporary table q18_antes on commit drop as
  select pg_get_functiondef('public.guard_oferta_insert()'::regprocedure) as def,
         false as ya_estaba;

do $$
declare
  v_def    text;
  v_n      int;
  v_ancla  constant text :=
    'raise exception ''Esta solicitud ya no admite ofertas\.''\s+using hint = ''Q-04'';\s+end if;';
  v_bloque constant text :=
       '\&' || E'\n\n'
    || '  -- Q-18 (20260930183000): el cliente rechazo una oferta de esta empresa en' || E'\n'
    || '  -- esta solicitud sin permitir otra (permite_reoferta = false).' || E'\n'
    || '  if exists (select 1 from public.ofertas o' || E'\n'
    || '              where o.pedido_id = new.pedido_id and o.admin_id = new.admin_id' || E'\n'
    || '                and o.estado = ''rechazada'' and o.permite_reoferta = false) then' || E'\n'
    || '    raise exception ''No puedes volver a ofertar en esta solicitud: el cliente rechazo tu oferta anterior sin permitir otra.''' || E'\n'
    || '      using hint = ''Q-18'';' || E'\n'
    || '  end if;';
begin
  select def into v_def from q18_antes;

  if position('using hint = ''Q-18''' in v_def) > 0 then
    update q18_antes set ya_estaba = true;
    return;
  end if;

  v_n := regexp_count(v_def, v_ancla);
  if v_n <> 1 then
    raise exception 'Q-18: guard_oferta_insert() tiene % veces el punto de anclaje (se esperaba 1). La funcion viva no es la que se midio: no se toca.', v_n;
  end if;

  execute regexp_replace(v_def, v_ancla, v_bloque);
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- Comprobacion — falla si el objetivo no se cumplio
-- ─────────────────────────────────────────────────────────────────────────
--
-- Con un pedido de prueba y una empresa real (perfil con rol admin), dentro
-- de una subtransaccion que se deshace entera:
--   · oferta rechazada SIN permitir otra → la nueva, como esa empresa, se
--     rechaza con HINT 'Q-18';
--   · oferta rechazada PERMITIENDO otra  → la nueva entra.
-- Como sabe fallar: sin el bloque, el primer caso entraria.

do $$
declare
  v_antes  text;
  v_ahora  text;
  v_ya     boolean;
  v_cli    uuid;
  v_emp    uuid;
  v_ped    uuid;
  v_caso   boolean;
  v_estado text;
  v_hint   text;
  v_msg    text;
  v_quien  text := current_user;
  v_fallos text[] := '{}';
begin
  select def, ya_estaba into v_antes, v_ya from q18_antes;
  v_ahora := pg_get_functiondef('public.guard_oferta_insert()'::regprocedure);
  if not v_ya then
    if v_ahora = v_antes then
      raise exception 'Q-18: guard_oferta_insert() no cambio.';
    end if;
    if regexp_replace(v_ahora, E'\n\n  -- Q-18 \\(20260930183000\\).*?using hint = ''Q-18'';\\s+end if;', '')
       is distinct from v_antes then
      raise exception 'Q-18: guard_oferta_insert() cambio en algo mas que el bloque nuevo.';
    end if;
  end if;
  if position('using hint = ''Q-18''' in v_ahora) = 0 then
    raise exception 'Q-18: el bloque nuevo no esta en guard_oferta_insert().';
  end if;
  if has_function_privilege('authenticated', 'public.guard_oferta_insert()', 'EXECUTE') then
    raise exception 'Q-18: guard_oferta_insert() quedo ejecutable por authenticated.';
  end if;

  select user_id into v_emp from public.perfiles where rol = 'admin' order by created_at limit 1;
  select user_id into v_cli from public.perfiles where user_id <> v_emp order by created_at limit 1;
  if v_emp is null or v_cli is null then
    raise exception 'Q-18: hace falta una empresa (rol admin) y otro perfil para la prueba.';
  end if;

  begin
    insert into public.pedidos (cliente_id, cliente_nombre, cliente_email, estado)
    values (v_cli, 'q18', 'q18@example.com', 'abierto') returning id into v_ped;

    foreach v_caso in array array[false, true] loop     -- permite_reoferta de la oferta rechazada
      begin
        insert into public.ofertas (pedido_id, admin_id, admin_nombre, precio_oferta, estado, permite_reoferta)
        values (v_ped, v_emp, 'q18', 100, 'rechazada', v_caso);

        perform set_config('request.jwt.claim.sub', v_emp::text, true);
        perform set_config('request.jwt.claims',
                           json_build_object('sub', v_emp, 'role', 'authenticated')::text, true);
        perform set_config('role', 'authenticated', true);
        insert into public.ofertas (pedido_id, admin_id, admin_nombre, precio_oferta)
        values (v_ped, v_emp, 'q18', 90);
        raise exception 'Q18_ENTRO';
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate,
                                v_msg    = message_text,
                                v_hint   = pg_exception_hint;
      end;

      if not v_caso and v_hint is distinct from 'Q-18' then
        v_fallos := v_fallos || format('sin permitir otra: no la freno Q-18 (%s %s)', v_estado, v_msg);
      elsif v_caso and v_msg <> 'Q18_ENTRO' then
        v_fallos := v_fallos || format('permitiendo otra: no entro (%s %s)', v_estado, v_msg);
      end if;
    end loop;

    raise exception 'Q18_FIN';
  exception when others then
    if sqlerrm <> 'Q18_FIN' then
      raise exception 'Q-18: la comprobacion no pudo montar sus datos de prueba: %', sqlerrm;
    end if;
  end;

  if current_user <> v_quien then
    raise exception 'Q-18: la comprobacion dejo el rol en % (era %).', current_user, v_quien;
  end if;
  if exists (select 1 from public.pedidos where cliente_email = 'q18@example.com') then
    raise exception 'Q-18: quedaron datos de prueba sin deshacer.';
  end if;
  if cardinality(v_fallos) > 0 then
    raise exception E'Q-18: el guard no hace lo que debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'Q-18: una empresa no puede volver a ofertar si el cliente no lo permitio; 2 casos, los dos como se esperaba.';
end $$;
