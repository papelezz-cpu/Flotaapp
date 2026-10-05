-- ════════════════════════════════════════════════════════════════════════
-- S-03 · datos_carta_porte() entregaba filas enteras a la contraparte
-- ════════════════════════════════════════════════════════════════════════
--
-- El defecto (6ª auditoría, 2026-10-01). La RPC de la Carta Porte de
-- referencia (20260930120000) comprueba bien quién llama —cliente,
-- propietario o superadmin de ESA reservación— y luego devuelve to_jsonb()
-- de seis filas completas, saltándose el RLS de perfiles (es SECURITY
-- DEFINER):
--
--   perfil del cliente   → a la empresa   44 columnas, se pintan 8
--   perfil de la empresa → al cliente     44 columnas, se pintan 8
--   chofer               → al cliente     39 columnas, se pintan 6
--   camión                                51 columnas, se pintan 3
--
-- Entre lo que sobraba: nota_rechazo_cuenta, rutas de fotos_verificacion y
-- de pólizas, y del chofer nss, tipo_sanguineo, correo, telefono y las rutas
-- de sus exámenes médico y toxicológico. Es H-01 otra vez, por la puerta de
-- una RPC (reglas 11 y 43).
--
-- El arreglo: cada to_jsonb(fila) pasa a jsonb_build_object con las columnas
-- que js/cartaporte.js lee — la lista sale de un grep de ese archivo, que no
-- accede a ningún campo de forma indirecta. Mismos nombres de clave, así
-- que el navegador no cambia. Olvidar una columna no daría error: dejaría un
-- «—» en el documento (regla 18). Por eso la comprobación de abajo compara
-- las claves exactas.
--
-- La función NO se reescribe (regla 3; R-11, y Q-20: la versión viva de
-- producción lleva un comentario que el repositorio no tiene): se sustituye
-- cada to_jsonb(x) sobre la definición viva. Si alguno no aparece
-- exactamente una vez, no se toca nada y la migración aborta.
--
-- Reglas de docs/AUDITORIA.md §4: 2, 3, 11, 13, 18, 43.
-- ════════════════════════════════════════════════════════════════════════


create temporary table s03_antes on commit drop as
  select pg_get_functiondef('public.datos_carta_porte(uuid)'::regprocedure) as def,
         false as ya_estaba,
         null::text as esperado;

do $$
declare
  v_def  text;
  v_n    int;
  v_par  text[];
  v_pares text[][] := array[
    array['to_jsonb\(v_r\)',
          'jsonb_build_object(''id'', v_r.id, ''cliente'', v_r.cliente, ''unidad'', v_r.unidad, '
       || '''fecha_ini'', v_r.fecha_ini, ''fecha_fin'', v_r.fecha_fin, ''operador_nombre'', v_r.operador_nombre)'],
    array['to_jsonb\(p\)',
          'jsonb_build_object(''tipo_carga'', p.tipo_carga, ''categoria_carga'', p.categoria_carga, '
       || '''peso_carga'', p.peso_carga, ''num_contenedores'', p.num_contenedores, '
       || '''hazmat_clase'', p.hazmat_clase, ''hazmat_un'', p.hazmat_un, ''clave_prod_serv_sat'', p.clave_prod_serv_sat, '
       || '''origen'', p.origen, ''origen_colonia'', p.origen_colonia, ''origen_cp'', p.origen_cp, '
       || '''origen_ciudad'', p.origen_ciudad, ''origen_estado'', p.origen_estado, '
       || '''destino'', p.destino, ''destino_colonia'', p.destino_colonia, ''destino_cp'', p.destino_cp, '
       || '''destino_ciudad'', p.destino_ciudad, ''destino_estado'', p.destino_estado)'],
    array['to_jsonb\(c\)',
          'jsonb_build_object(''nombre'', c.nombre, ''rfc'', c.rfc, ''razon_social'', c.razon_social, '
       || '''calle'', c.calle, ''colonia'', c.colonia, ''cp'', c.cp, ''ciudad'', c.ciudad, ''estado_mx'', c.estado_mx)'],
    array['to_jsonb\(t\)',
          'jsonb_build_object(''rfc'', t.rfc, ''razon_social'', t.razon_social, ''permiso_sct'', t.permiso_sct, '
       || '''calle'', t.calle, ''colonia'', t.colonia, ''cp'', t.cp, ''ciudad'', t.ciudad, ''estado_mx'', t.estado_mx)'],
    array['to_jsonb\(cam\)',
          'jsonb_build_object(''placas'', cam.placas, ''numero_permiso_sct'', cam.numero_permiso_sct, '
       || '''configuracion_vehicular'', cam.configuracion_vehicular)'],
    array['to_jsonb\(op\)',
          'jsonb_build_object(''nombre'', op.nombre, ''primer_apellido'', op.primer_apellido, '
       || '''segundo_apellido'', op.segundo_apellido, ''rfc'', op.rfc, ''curp'', op.curp, ''num_licencia'', op.num_licencia)']
  ];
begin
  select def into v_def from s03_antes;

  if position('to_jsonb(' in v_def) = 0 then
    update s03_antes set ya_estaba = true;
    return;
  end if;

  foreach v_par slice 1 in array v_pares loop
    v_n := regexp_count(v_def, v_par[1]);
    if v_n <> 1 then
      raise exception 'S-03: datos_carta_porte() tiene % veces «%» (se esperaba 1). La función viva no es la que se midió: no se toca.', v_n, v_par[1];
    end if;
    v_def := regexp_replace(v_def, v_par[1], v_par[2]);
  end loop;

  if position('to_jsonb(' in v_def) > 0 then
    raise exception 'S-03: queda un to_jsonb() sin sustituir en datos_carta_porte().';
  end if;

  update s03_antes set esperado = v_def;
  execute v_def;
end $$;


-- ────────────────────────────────────────────────────────────────────────
-- Comprobación — falla si el objetivo no se cumplió
-- ────────────────────────────────────────────────────────────────────────
--
--   · fuera de las seis sustituciones, la función no cambió;
--   · llamada como el CLIENTE de una reservación real: las claves de cada
--     bloque son exactamente las que imprime la Carta Porte;
--   · llamada como alguien ajeno a la reservación: 'No autorizado' (no se
--     abrió nada al cambiar lo que devuelve).
-- Como sabe fallar: con la función vieja, `cliente` trae 44 claves.

do $$
declare
  v_antes  text;
  v_ahora  text;
  v_esperado text;
  v_ya     boolean;
  v_res    record;
  v_ajeno  uuid;
  v_j      jsonb;
  v_msg    text;
  v_quien  text := current_user;
  v_fallos text[] := '{}';
  v_bloque text;
  v_tiene  text[];
  v_espera jsonb := jsonb_build_object(
    'reservacion',   array['cliente','fecha_fin','fecha_ini','id','operador_nombre','unidad'],
    'pedido',        array['categoria_carga','clave_prod_serv_sat','destino','destino_ciudad','destino_colonia',
                           'destino_cp','destino_estado','hazmat_clase','hazmat_un','num_contenedores','origen',
                           'origen_ciudad','origen_colonia','origen_cp','origen_estado','peso_carga','tipo_carga'],
    'cliente',       array['calle','ciudad','colonia','cp','estado_mx','nombre','razon_social','rfc'],
    'transportista', array['calle','ciudad','colonia','cp','estado_mx','permiso_sct','razon_social','rfc'],
    'camion',        array['configuracion_vehicular','numero_permiso_sct','placas'],
    'operador',      array['curp','nombre','num_licencia','primer_apellido','rfc','segundo_apellido']);
begin
  select def, ya_estaba, esperado into v_antes, v_ya, v_esperado from s03_antes;
  v_ahora := pg_get_functiondef('public.datos_carta_porte(uuid)'::regprocedure);
  -- La función viva tiene que ser EXACTAMENTE el texto que construyó el bloque
  -- de arriba: la definición anterior con las seis sustituciones y nada más.
  if not v_ya and v_ahora is distinct from v_esperado then
    raise exception 'S-03: datos_carta_porte() no quedó como se construyó (cambió en algo más que las seis sustituciones).';
  end if;
  if position('to_jsonb(' in v_ahora) > 0 then
    raise exception 'S-03: datos_carta_porte() sigue devolviendo filas enteras.';
  end if;
  if has_function_privilege('anon', 'public.datos_carta_porte(uuid)', 'EXECUTE') then
    raise exception 'S-03: datos_carta_porte() quedó ejecutable por anon.';
  end if;

  -- Una reservación con cliente, empresa, pedido y, si la hay, chofer y camión.
  select r.id, r.cliente_user_id
    into v_res
    from public.reservaciones r
   where r.cliente_user_id is not null and r.propietario_id is not null and r.pedido_id is not null
   order by (r.operador_id is not null) desc, (r.recurso_tipo = 'camion') desc, r.created_at
   limit 1;
  select p.user_id into v_ajeno from public.perfiles p
   where p.rol <> 'superadmin'
     and not exists (select 1 from public.reservaciones r
                      where r.id = v_res.id and p.user_id in (r.cliente_user_id, r.propietario_id))
   order by p.created_at limit 1;
  if v_res.id is null or v_ajeno is null then
    raise exception 'S-03: hace falta una reservación con cliente, empresa y pedido, y un perfil ajeno, para la prueba.';
  end if;

  -- Como el cliente.
  perform set_config('request.jwt.claim.sub', v_res.cliente_user_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_res.cliente_user_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  v_j := public.datos_carta_porte(v_res.id);
  perform set_config('role', v_quien, true);

  for v_bloque in select jsonb_object_keys(v_espera) loop
    if jsonb_typeof(v_j -> v_bloque) = 'object' then
      select array_agg(k order by k) into v_tiene from jsonb_object_keys(v_j -> v_bloque) k;
      if v_tiene is distinct from (select array_agg(e order by e) from jsonb_array_elements_text(v_espera -> v_bloque) e) then
        v_fallos := v_fallos || format('%s devuelve %s claves: %s', v_bloque, cardinality(v_tiene), array_to_string(v_tiene, ','));
      end if;
    elsif v_bloque in ('reservacion', 'pedido', 'cliente', 'transportista') then
      v_fallos := v_fallos || format('%s no vino (%s)', v_bloque, coalesce(jsonb_typeof(v_j -> v_bloque), 'ausente'));
    end if;
  end loop;

  -- Como alguien ajeno.
  begin
    perform set_config('request.jwt.claim.sub', v_ajeno::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ajeno, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    v_j := public.datos_carta_porte(v_res.id);
    v_msg := 'ENTREGO';
  exception when others then
    v_msg := sqlerrm;
  end;
  perform set_config('role', v_quien, true);
  if v_msg <> 'No autorizado' then
    v_fallos := v_fallos || format('un perfil ajeno obtuvo «%s» en vez de No autorizado', v_msg);
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  if current_user <> v_quien then
    raise exception 'S-03: la comprobación dejó el rol en % (era %).', current_user, v_quien;
  end if;
  if cardinality(v_fallos) > 0 then
    raise exception E'S-03: datos_carta_porte() no devuelve lo que debe:\n  %', array_to_string(v_fallos, E'\n  ');
  end if;

  raise notice 'S-03: datos_carta_porte() devuelve solo lo que imprime la Carta Porte; un perfil ajeno sigue sin acceso.';
end $$;
