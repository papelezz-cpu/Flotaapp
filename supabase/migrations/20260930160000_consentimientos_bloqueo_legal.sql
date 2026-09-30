-- ═════════════════════════════════════════════════════════════════════════
-- Q-11 (segunda parte) · Bloqueo legal de consentimientos
-- ═════════════════════════════════════════════════════════════════════════
--
-- El defecto: `consentimientos.user_id` → auth.users ON DELETE CASCADE. Al
-- borrar una cuenta (gestionar-usuario «eliminar», o un derecho ARCO de
-- cancelacion) su constancia de haber aceptado el aviso de privacidad, los
-- terminos o la declaracion sobre los datos de un operador DESAPARECE. Si
-- despues hay que demostrar que el consentimiento existio, no queda nada.
--
-- Decision del usuario (2026-09-30), siguiendo la LFPDPPP:
--   1. Los consentimientos no se eliminan de inmediato: pasan a un BLOQUEO
--      LEGAL, sin usarse para marketing, analisis, personalizacion ni ningun
--      otro proposito operativo.
--   2. Se conserva solo lo minimo como evidencia: identificador del
--      consentimiento, version del documento aceptado, fecha y hora, tipo,
--      mecanismo por el que se otorgo, motivo y fecha del bloqueo. Sin IP (hoy
--      no se recoge y no hay justificacion para empezar). SI se conserva el
--      identificador de la cuenta (uuid), porque sin el la evidencia no
--      demuestra quien acepto.
--   3. Al terminar el plazo legal se ANONIMIZA (se borran titular y
--      referencia). El plazo lo define el usuario mas adelante: hasta
--      entonces `conservar_hasta` queda NULL y no hay purga automatica.
--   La revocacion del consentimiento no tiene efectos retroactivos; el motivo
--   'revocado' queda previsto para cuando exista ese flujo (hoy no existe).
--
-- El diseño:
--   · Tabla `consentimientos_bloqueados`, blindada como `avisos_superadmin`:
--     RLS encendida, CERO politicas y privilegios retirados a anon,
--     authenticated y service_role. Nadie la lee ni la escribe desde la app,
--     ni el superadmin; solo el administrador de la base, para atender un
--     requerimiento legal. Asi no puede usarse para ningun proposito
--     operativo.
--   · Trigger BEFORE DELETE en `consentimientos` que copia la fila antes de
--     que se borre. La cascada existente sigue funcionando: la FK NO se toca
--     (tocarla seria un DROP CONSTRAINT, Regla #1) y el borrado de cuentas
--     no cambia en nada visible.
--
-- Reglas de docs/AUDITORIA.md §4: 1 (todo nace abierto: se revoca aqui),
-- 2 (bloque que sabe fallar), 6 (nombre del trigger), 9 (sin DROP),
-- 13 (DEFINER: tiene que escribir en una tabla que nadie mas puede tocar;
-- search_path fijado y EXECUTE revocado), 14 (una tabla de evidencia sin
-- politicas ni privilegios), 43 (no traer PII que no se necesita: sin IP).
-- ═════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- 1. La tabla de bloqueo
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.consentimientos_bloqueados (
  id               uuid        primary key,          -- el mismo id que tenia en consentimientos
  titular          uuid,                             -- cuenta que acepto; NULL tras anonimizar
  tipo             text        not null,
  version          text        not null,
  aceptado_en      timestamptz not null,
  mecanismo        text,                             -- consentimientos.contexto: 'registro', 'alta_operador'
  referencia       text,                             -- p. ej. el operador de la declaracion; NULL tras anonimizar
  motivo           text        not null,
  bloqueado_en     timestamptz not null default now(),
  conservar_hasta  date,                             -- NULL hasta que el usuario defina el plazo legal
  anonimizado_en   timestamptz,
  constraint consentimientos_bloqueados_tipo_check
    check (tipo in ('aviso_privacidad', 'terminos', 'datos_sensibles_operador')),
  constraint consentimientos_bloqueados_motivo_check
    check (motivo in ('cuenta_eliminada', 'revocado', 'borrado_directo'))
);

comment on table public.consentimientos_bloqueados is
  'Bloqueo legal (Q-11, 20260930160000): evidencia minima de consentimientos '
  'cuya fila original se borro. NO se usa para ningun proposito operativo. '
  'RLS sin politicas y sin privilegios para anon/authenticated/service_role: '
  'solo el administrador de la base, ante un requerimiento legal. Al vencer '
  'conservar_hasta se anonimiza (titular y referencia a NULL).';

alter table public.consentimientos_bloqueados enable row level security;
revoke all on table public.consentimientos_bloqueados from public, anon, authenticated, service_role;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. Copiar antes de borrar
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.bloquear_consentimiento()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_motivo text := 'cuenta_eliminada';
begin
  -- En la cascada, la cuenta ya no existe cuando se dispara este trigger. Si
  -- no se pudiera consultar auth.users, NO se deja fallar: este trigger corre
  -- dentro del borrado de la cuenta, y un error aqui la haria imposible.
  begin
    if exists (select 1 from auth.users u where u.id = old.user_id) then
      v_motivo := 'borrado_directo';
    end if;
  exception when others then
    v_motivo := 'cuenta_eliminada';
  end;

  insert into public.consentimientos_bloqueados
    (id, titular, tipo, version, aceptado_en, mecanismo, referencia, motivo)
  values
    (old.id, old.user_id, old.tipo, old.version, old.aceptado_en, old.contexto, old.referencia, v_motivo)
  on conflict (id) do nothing;
  return old;
end;
$$;

comment on function public.bloquear_consentimiento() is
  'Q-11: copia el consentimiento a consentimientos_bloqueados antes de '
  'borrarlo (cascada al eliminar la cuenta, o borrado directo). '
  'Ver 20260930160000.';

revoke all on function public.bloquear_consentimiento() from public, anon, authenticated, service_role;

do $$
begin
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.consentimientos'::regclass
       and tgname  = 'trg_bloquear_consentimiento'
       and not tgisinternal
  ) then
    create trigger trg_bloquear_consentimiento
      before delete on public.consentimientos
      for each row execute function public.bloquear_consentimiento();
  end if;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion — falla si el objetivo no se cumplio
-- ─────────────────────────────────────────────────────────────────────────
--
-- Aqui se ejerce el BORRADO DIRECTO: se crea un consentimiento de prueba de
-- una cuenta existente, se borra y se comprueba la copia; todo dentro de una
-- subtransaccion que se deshace. La CASCADA desde auth.users se probo en el
-- banco local (no se toca auth.users en produccion); aqui se comprueba que la
-- FK sigue siendo ON DELETE CASCADE, que es lo que dispara el mismo trigger.
--
-- Como sabe fallar: sin el trigger, la fila no aparece en la tabla de
-- bloqueo; sin el REVOKE, los privilegios del catalogo lo delatan.

do $$
declare
  v_user   uuid;
  v_id     uuid;
  v_copia  public.consentimientos_bloqueados%rowtype;
  v_msg    text;
  v_hecho  boolean := false;
begin
  -- Blindaje de la tabla.
  if not (select relrowsecurity from pg_class where oid = 'public.consentimientos_bloqueados'::regclass) then
    raise exception 'Q-11: consentimientos_bloqueados no tiene RLS.';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'consentimientos_bloqueados') then
    raise exception 'Q-11: consentimientos_bloqueados tiene politicas; debe tener cero.';
  end if;
  if has_table_privilege('anon', 'public.consentimientos_bloqueados', 'SELECT')
  or has_table_privilege('authenticated', 'public.consentimientos_bloqueados', 'SELECT')
  or has_table_privilege('service_role', 'public.consentimientos_bloqueados', 'SELECT')
  or has_table_privilege('authenticated', 'public.consentimientos_bloqueados', 'INSERT') then
    raise exception 'Q-11: consentimientos_bloqueados es accesible desde la app.';
  end if;
  if has_function_privilege('anon', 'public.bloquear_consentimiento()', 'EXECUTE')
  or has_function_privilege('authenticated', 'public.bloquear_consentimiento()', 'EXECUTE') then
    raise exception 'Q-11: bloquear_consentimiento() es ejecutable desde la app.';
  end if;

  -- El trigger y la cascada que lo alimenta.
  if not exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
                  where t.tgrelid = 'public.consentimientos'::regclass
                    and t.tgname = 'trg_bloquear_consentimiento' and t.tgenabled <> 'D'
                    and p.proname = 'bloquear_consentimiento'
                    and (t.tgtype & 2) = 2 and (t.tgtype & 8) = 8) then   -- BEFORE, DELETE
    raise exception 'Q-11: falta o esta apagado trg_bloquear_consentimiento (BEFORE DELETE).';
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.consentimientos'::regclass and contype = 'f'
                    and confrelid = 'auth.users'::regclass and confdeltype = 'c') then
    raise exception 'Q-11: la FK de consentimientos a auth.users ya no es ON DELETE CASCADE; revisar el disparo del bloqueo.';
  end if;

  -- El borrado directo, ejercido.
  select user_id into v_user from public.perfiles order by created_at limit 1;
  if v_user is null then
    raise exception 'Q-11: no hay ningun perfil para la prueba.';
  end if;

  begin
    insert into public.consentimientos (user_id, tipo, version, contexto, referencia)
    values (v_user, 'terminos', 'q11-prueba', 'q11', 'q11-ref')
    returning id into v_id;

    delete from public.consentimientos where id = v_id;

    select * into v_copia from public.consentimientos_bloqueados where id = v_id;
    if not found then
      raise exception 'Q11_SIN_COPIA';
    end if;
    if v_copia.titular is distinct from v_user or v_copia.version <> 'q11-prueba'
       or v_copia.mecanismo is distinct from 'q11' or v_copia.referencia is distinct from 'q11-ref'
       or v_copia.motivo <> 'borrado_directo' or v_copia.conservar_hasta is not null then
      raise exception 'Q11_COPIA_MAL';
    end if;
    v_hecho := true;
    raise exception 'Q11_FIN';
  exception when others then
    v_msg := sqlerrm;
  end;

  if v_msg = 'Q11_SIN_COPIA' then
    raise exception 'Q-11: al borrar un consentimiento no se copio a la tabla de bloqueo.';
  elsif v_msg = 'Q11_COPIA_MAL' then
    raise exception 'Q-11: la copia bloqueada no conserva los datos esperados.';
  elsif v_msg <> 'Q11_FIN' or not v_hecho then
    raise exception 'Q-11: la comprobacion no pudo ejecutarse: %', v_msg;
  end if;

  if exists (select 1 from public.consentimientos_bloqueados where version = 'q11-prueba')
  or exists (select 1 from public.consentimientos where version = 'q11-prueba') then
    raise exception 'Q-11: quedaron filas de prueba sin deshacer.';
  end if;

  raise notice 'Q-11: bloqueo legal activo; un consentimiento borrado se conserva en consentimientos_bloqueados sin acceso desde la app.';
end $$;
