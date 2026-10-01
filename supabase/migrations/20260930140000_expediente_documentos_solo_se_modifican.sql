-- ═════════════════════════════════════════════════════════════════════════
-- Q-06 (segunda mitad) · Los renglones de un expediente no se crean ni se
--                        borran desde la app
-- ═════════════════════════════════════════════════════════════════════════
--
-- El defecto (quinta auditoria, 2026-09-29; medido de nuevo el 2026-09-30):
--
--   CREATE POLICY expdocs_all ON expediente_documentos TO authenticated
--     USING (participa_en_expediente(expediente_id))
--     WITH CHECK (participa_en_expediente(expediente_id));
--   GRANT SELECT, INSERT, DELETE, UPDATE ON expediente_documentos TO authenticated;
--
-- La politica es FOR ALL y el unico guard, `trg_guard_expediente_documento`,
-- es BEFORE UPDATE. Cualquiera de las dos partes del viaje puede, por la API:
--   · BORRAR un renglon — p. ej. el cliente quita el pedimento obligatorio y
--     el expediente parece completo sin haberlo entregado;
--   · INSERTAR renglones que no salen del catalogo, o volver a meter uno que
--     la otra parte ya reviso.
--
-- Quien escribe renglones hoy, medido el 2026-09-30:
--   · Crearlos: solo `abrir_expediente()` (SECURITY DEFINER), que los COPIA de
--     `documentos_catalogo` al abrir el expediente. Es la unica funcion de la
--     base que escribe en la tabla.
--   · Web (js/expedientes.js:331 y :411) y Android
--     (ReservacionesRepository.kt:198 y :221): solo UPDATE — subir el archivo,
--     aprobar o rechazar. Eso lo vigila el guard y no se toca.
--   · Nadie inserta ni borra renglones desde un cliente.
--
-- El arreglo: retirar INSERT y DELETE a `authenticated` (y a anon/PUBLIC, por
-- si acaso). SELECT y UPDATE se quedan. `expdocs_all` NO se borra (seria un
-- DROP, Regla #1): sigue gobernando SELECT y UPDATE, que es lo que se usa; para
-- INSERT y DELETE queda sin efecto porque no hay privilegio. Mismo patron que
-- Q-03 y la primera mitad de Q-06 (20260930130000).
--
-- Reglas de docs/AUDITORIA.md §4: 2 (bloque que sabe fallar), 9 (sin DROP),
-- 13 (abrir_expediente ya es DEFINER y reverifica al autor).
-- ═════════════════════════════════════════════════════════════════════════


revoke insert, delete on public.expediente_documentos from authenticated, anon, public;

comment on policy expdocs_all on public.expediente_documentos is
  'Desde 20260930140000 (Q-06) solo gobierna SELECT y UPDATE: authenticated ya '
  'no tiene INSERT ni DELETE. Los renglones nacen en abrir_expediente() desde '
  'documentos_catalogo y no se borran desde la app.';


-- ─────────────────────────────────────────────────────────────────────────
-- Comprobacion — falla si el objetivo no se cumplio
-- ─────────────────────────────────────────────────────────────────────────
--
-- Como sabe fallar:
--   · Privilegios leidos del catalogo.
--   · Ejercido como `authenticated`: sin el REVOKE, el INSERT lo frenaria la
--     RLS ("new row violates row-level security policy", tambien 42501) y el
--     DELETE no daria error —la RLS filtra y borra 0 filas—. Por eso se exige
--     el mensaje de PRIVILEGIO ("permission denied"), no solo el codigo.

do $$
declare
  v_u      uuid := gen_random_uuid();
  v_estado text;
  v_msg    text;
  v_quien  text := current_user;
  v_dueno  name;
  v_def    boolean;
begin
  if has_table_privilege('authenticated', 'public.expediente_documentos', 'INSERT')
  or has_table_privilege('authenticated', 'public.expediente_documentos', 'DELETE')
  or has_table_privilege('anon',          'public.expediente_documentos', 'INSERT')
  or has_table_privilege('anon',          'public.expediente_documentos', 'DELETE') then
    raise exception 'Q-06b: authenticated o anon siguen teniendo INSERT o DELETE en expediente_documentos.';
  end if;
  if not (has_table_privilege('authenticated', 'public.expediente_documentos', 'SELECT')
      and has_table_privilege('authenticated', 'public.expediente_documentos', 'UPDATE')) then
    raise exception 'Q-06b: authenticated perdio SELECT o UPDATE; la web y Android los usan.';
  end if;

  -- abrir_expediente() sigue pudiendo crear los renglones.
  select pg_get_userbyid(p.proowner), p.prosecdef into v_dueno, v_def
    from pg_proc p
   where p.oid = 'public.abrir_expediente(uuid, text, boolean)'::regprocedure;
  if not v_def then
    raise exception 'Q-06b: abrir_expediente() ya no es SECURITY DEFINER; sin INSERT no podria crear renglones.';
  end if;
  if not has_table_privilege(v_dueno, 'public.expediente_documentos', 'INSERT') then
    raise exception 'Q-06b: el dueño de abrir_expediente (%) no tiene INSERT en expediente_documentos.', v_dueno;
  end if;

  -- INSERT como usuario final.
  begin
    perform set_config('request.jwt.claim.sub', v_u::text, true);
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_u, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    insert into public.expediente_documentos (expediente_id, nombre) values (gen_random_uuid(), 'q06b');
    raise exception 'Q06B_SENTINELA';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  end;
  if not (v_estado = '42501' and v_msg like 'permission denied%') then
    raise exception 'Q-06b: el INSERT de un usuario no lo frena el privilegio: % %', v_estado, v_msg;
  end if;

  -- DELETE como usuario final.
  begin
    perform set_config('request.jwt.claim.sub', v_u::text, true);
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_u, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    delete from public.expediente_documentos where false;
    raise exception 'Q06B_SENTINELA';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  end;
  if not (v_estado = '42501' and v_msg like 'permission denied%') then
    raise exception 'Q-06b: el DELETE de un usuario no lo frena el privilegio: % %', v_estado, v_msg;
  end if;

  if current_user <> v_quien then
    raise exception 'Q-06b: la comprobacion dejo el rol en % (era %).', current_user, v_quien;
  end if;

  raise notice 'Q-06b: expediente_documentos sin INSERT ni DELETE para usuarios; abrir_expediente (dueño %) conserva el suyo.', v_dueno;
end $$;
