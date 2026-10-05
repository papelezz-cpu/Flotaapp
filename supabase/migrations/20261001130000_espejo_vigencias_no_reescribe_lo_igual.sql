-- ════════════════════════════════════════════════════════════════════════
-- S-02 · La empresa acreditada no podía tocar su propio perfil
-- ════════════════════════════════════════════════════════════════════════
--
-- El defecto (6ª auditoría, 2026-10-01). `vigencias_espejo()` corre AFTER
-- UPDATE en perfiles y en la flota, y en CADA update repite el reflejo de
-- todos los documentos de la fila con INSERT … ON CONFLICT DO UPDATE, aunque
-- ninguno haya cambiado. Ese DO UPDATE dispara `guard_vigencia_update()`,
-- que —con razón, es H-02— rechaza cualquier UPDATE de una fila `vigente` de
-- tipo perfil si quien escribe no es superadmin.
--
-- Resultado, ejecutado en banco local con el esquema de producción y la única
-- empresa acreditada del volcado: guardarPerfilEmpresa(), guardarPreferencia-
-- Correo() (solo notif_email) y solicitarActualizacionDocs() (solo columnas
-- *_pendiente) fallaban los tres con VIGENCIA_ACREDITADA. La misma empresa sin
-- filas vigentes: OK. Es decir, la empresa mejor verificada era la única que
-- no podía renovar sus seguros. Lo mismo con la clave de servicio
-- (auth.uid() NULL), que es como lo encontró 20260929140000.
--
-- El arreglo: en un UPDATE, el espejo se salta el documento cuyo archivo y
-- fecha son iguales en OLD y NEW. Lo que no cambió ya está reflejado.
--
-- Lo que NO cambia:
--   · El guard de vigencias no se toca (regla 15). Si la empresa cambia la
--     RUTA de un documento acreditado (doc_seguro_rc…, que
--     guard_perfil_self_update no protege), el documento sí cambió, el espejo
--     escribe y el guard lo rechaza igual que hoy: H-02 no se reabre. La
--     comprobación de abajo lo ejerce.
--   · INSERT y DELETE se reflejan igual que antes.
--
-- Consecuencia asumida: un UPDATE que no toca documentos ya no «repara» una
-- fila de vigencias que se hubiera desincronizado a mano. El espejo es
-- estricto desde 20260923120000, así que esa desincronización no debería
-- poder ocurrir por las vías normales.
--
-- La función NO se reescribe a mano (regla 3; R-11): se lee su definición
-- viva, se inserta el bloque justo después de calcular v_fecha, y la
-- comprobación verifica que es lo único que cambió. Si el punto de anclaje no
-- aparece exactamente una vez, no se toca nada y la migración aborta.
--
-- Reglas de docs/AUDITORIA.md §4: 2, 3, 4 (se lee de la base), 15.
-- ════════════════════════════════════════════════════════════════════════


create temporary table s02_antes on commit drop as
  select pg_get_functiondef('public.vigencias_espejo()'::regprocedure) as def,
         false as ya_estaba;

do $$
declare
  v_def    text;
  v_n      int;
  v_ancla  constant text := 'v_fecha := nullif\(j->>\(m\.col_fecha\), ''''\)::date;';
  v_bloque constant text :=
       '\&' || E'\n\n'
    || '    -- S-02 (20261001130000): en un UPDATE, lo que no cambio ya esta reflejado.' || E'\n'
    || '    -- Reescribirlo disparaba guard_vigencia_update sobre filas vigentes y' || E'\n'
    || '    -- dejaba a la empresa acreditada sin poder tocar su propio perfil.' || E'\n'
    || '    if tg_op = ''UPDATE''' || E'\n'
    || '       and (m.col_arch is null or to_jsonb(old)->>(m.col_arch) is not distinct from v_arch)' || E'\n'
    || '       and to_jsonb(old)->>(m.col_fecha) is not distinct from j->>(m.col_fecha) then' || E'\n'
    || '      continue;' || E'\n'
    || '    end if;';
begin
  select def into v_def from s02_antes;

  if position('S-02 (20261001130000)' in v_def) > 0 then
    update s02_antes set ya_estaba = true;
    return;
  end if;

  v_n := regexp_count(v_def, v_ancla);
  if v_n <> 1 then
    raise exception 'S-02: vigencias_espejo() tiene % veces el punto de anclaje (se esperaba 1). La función viva no es la que se midió: no se toca.', v_n;
  end if;

  execute regexp_replace(v_def, v_ancla, v_bloque);
end $$;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--
-- Dentro de una subtransacción que se deshace entera, con una empresa real:
--   0. el superadmin le acredita el seguro RC (archivo + fecha) → el espejo
--      crea su fila `vigente`;
--   1. la empresa cambia notif_email            → debe pasar  (antes: fallaba)
--   2. la empresa propone *_pendiente del RC     → debe pasar  (antes: fallaba)
--   3. la empresa cambia la RUTA del RC vigente  → debe fallar (H-02)
--   4. la empresa cambia la FECHA del RC vigente → debe fallar (H-02)
-- Como sabe fallar: sin el bloque, 1 y 2 fallan con VIGENCIA_ACREDITADA.

do $$
declare
  v_antes  text;
  v_ahora  text;
  v_ya     boolean;
  v_emp    uuid;
  v_sa     uuid;
  v_quien  text := current_user;
  v_fallos text[] := '{}';
  v_casos  text[] := array[
    'notif_email = not coalesce(notif_email, true)',
    'fecha_vencimiento_seguro_rc_pendiente = current_date + 400, doc_seguro_rc_pendiente = user_id || ''/s02_pendiente.pdf''',
    'doc_seguro_rc = user_id || ''/s02_otra_ruta.pdf''',
    'fecha_vencimiento_seguro_rc = current_date + 500'];
  v_debe   boolean[] := array[true, true, false, false];   -- ¿debe pasar?
  v_i      int;
  v_msg    text;
begin
  select def, ya_estaba into v_antes, v_ya from s02_antes;
  v_ahora := pg_get_functiondef('public.vigencias_espejo()'::regprocedure);
  if not v_ya then
    if v_ahora = v_antes then
      raise exception 'S-02: vigencias_espejo() no cambió.';
    end if;
    if regexp_replace(v_ahora, E'\n\n    -- S-02 \\(20261001130000\\).*?continue;\\s+end if;', '')
       is distinct from v_antes then
      raise exception 'S-02: vigencias_espejo() cambió en algo más que el bloque nuevo.';
    end if;
  end if;
  if position('S-02 (20261001130000)' in v_ahora) = 0 then
    raise exception 'S-02: el bloque nuevo no está en vigencias_espejo().';
  end if;
  if has_function_privilege('authenticated', 'public.vigencias_espejo()', 'EXECUTE')
  or has_function_privilege('anon',          'public.vigencias_espejo()', 'EXECUTE') then
    raise exception 'S-02: vigencias_espejo() quedó ejecutable por anon o authenticated.';
  end if;

  select user_id into v_emp from public.perfiles
   where rol = 'admin' and aprobacion_cuenta is null order by created_at limit 1;
  select user_id into v_sa  from public.perfiles where rol = 'superadmin' order by created_at limit 1;
  if v_emp is null or v_sa is null then
    raise exception 'S-02: hace falta una empresa activa y un superadmin para la prueba.';
  end if;

  begin
    -- 0. El superadmin acredita el seguro RC de la empresa.
    perform set_config('request.jwt.claim.sub', v_sa::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    update public.perfiles
       set doc_seguro_rc = v_emp || '/s02_rc.pdf',
           fecha_vencimiento_seguro_rc = current_date + 300,
           seguro_rc = true
     where user_id = v_emp;
    perform set_config('role', v_quien, true);

    if not exists (select 1 from public.vigencias
                    where entidad_tipo = 'perfil' and entidad_id = v_emp::text
                      and tipo_documento = 'seguro_rc' and estado = 'vigente'
                      and archivo_path = v_emp || '/s02_rc.pdf') then
      raise exception 'S02_SIN_MONTAJE: el espejo no creó la fila vigente del seguro RC';
    end if;

    -- 1..4, cada uno como la empresa y en su propia subtransacción.
    for v_i in 1 .. 4 loop
      begin
        perform set_config('request.jwt.claim.sub', v_emp::text, true);
        perform set_config('request.jwt.claims', json_build_object('sub', v_emp, 'role', 'authenticated')::text, true);
        perform set_config('role', 'authenticated', true);
        execute format('update public.perfiles set %s where user_id = %L', v_casos[v_i], v_emp);
        raise exception 'S02_PASO';
      exception when others then
        v_msg := sqlerrm;
      end;
      perform set_config('role', v_quien, true);

      if v_debe[v_i] and v_msg <> 'S02_PASO' then
        v_fallos := v_fallos || format('caso %s (%s) debía pasar: %s', v_i, v_casos[v_i], v_msg);
      elsif not v_debe[v_i] and v_msg = 'S02_PASO' then
        v_fallos := v_fallos || format('caso %s (%s) debía rechazarse y pasó: H-02 reabierto', v_i, v_casos[v_i]);
      end if;
    end loop;

    raise exception 'S02_FIN';
  exception when others then
    if sqlerrm <> 'S02_FIN' then
      raise exception 'S-02: la comprobación no pudo montar sus datos de prueba: %', sqlerrm;
    end if;
  end;

  perform set_config('role', v_quien, true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  if current_user <> v_quien then
    raise exception 'S-02: la comprobación dejó el rol en % (era %).', current_user, v_quien;
  end if;
  if exists (select 1 from public.vigencias where archivo_path like '%/s02\_%' escape '\')
  or exists (select 1 from public.perfiles  where doc_seguro_rc like '%/s02\_%' escape '\') then
    raise exception 'S-02: quedaron datos de prueba sin deshacer.';
  end if;
  if cardinality(v_fallos) > 0 then
    raise exception E'S-02: el espejo no hace lo que debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'S-02: la empresa acreditada edita su perfil y propone renovaciones; cambiar un documento acreditado sigue rechazado. 4 casos, todos como se esperaba.';
end $$;
