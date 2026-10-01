-- ═════════════════════════════════════════════════════════════════════════
-- Q-14 · La negociacion de una oferta deja de tener tope de rondas
-- ═════════════════════════════════════════════════════════════════════════
--
-- El defecto (medido en `dev` el 2026-09-29 probando Q-04, y presente en
-- produccion): tras la contraoferta del cliente (ronda 2), el boton
-- «Responder» → «↩ Contraofertar» de la empresa calcula `ronda + 1` = 3
-- (js/pedidos.js) y `ofertas_ronda_check` solo admitia 1 o 2. Falla siempre,
-- desde que se añadio el boton el 2026-08-17.
--
-- Decision del usuario (2026-09-29): opcion B, SIN tope numerico. Lo unico que
-- acota la negociacion es la caducidad: ninguna contraoferta renueva
-- `expira_en`, asi que todo tiene que cerrarse en los 2 dias desde la oferta,
-- y `sincronizar_estados_pedidos()` vence lo que no.
--
-- Lo que cambia:
--   1. `ofertas_ronda_check` pasa de `ronda IN (1, 2)` a `ronda >= 1`.
--      ⚠ Es un DROP CONSTRAINT + ADD CONSTRAINT: un CHECK no se puede
--      modificar de otra forma. Autorizado por el usuario antes de aplicarse
--      (Regla #1).
--   2. `responder_oferta()` (RPC del contrato movil; la web no la usa) ponia
--      `ronda = 2` fijo: una segunda contraoferta del cliente haria retroceder
--      la ronda. Pasa a `ronda = ronda + 1`. La funcion NO se reescribe a mano
--      (regla 3; R-11 fue una reescritura que perdio un UPDATE): se lee su
--      definicion viva, se cambia esa unica subcadena y el bloque de
--      verificacion comprueba que es lo unico que cambio.
--   3. En el navegador (mismo commit, se despliega DESPUES — regla 41):
--      `enviarContraoferta()` deja de poner `ronda: 2` fijo y usa ronda + 1.
--
-- Lo que no cambia: una oferta NUEVA sigue naciendo en ronda 1 (guard de
-- Q-04). `guard_oferta_update` no mira la ronda.
-- ═════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- 1. El CHECK
-- ─────────────────────────────────────────────────────────────────────────

alter table public.ofertas drop constraint if exists ofertas_ronda_check;
alter table public.ofertas add constraint ofertas_ronda_check check (ronda >= 1);


-- ─────────────────────────────────────────────────────────────────────────
-- 2. responder_oferta(): solo `ronda = 2` → `ronda = ronda + 1`
-- ─────────────────────────────────────────────────────────────────────────

create temporary table q14_antes on commit drop as
  select pg_get_functiondef('public.responder_oferta(uuid, text, numeric, text)'::regprocedure) as def,
         false as ya_estaba;

do $$
declare
  v_def   text;
  v_nuevo text;
  v_n     int;
begin
  select def into v_def from q14_antes;
  v_n := (length(v_def) - length(replace(v_def, 'ronda = 2', ''))) / length('ronda = 2');

  -- Reaplicar no rompe: si ya no hay `ronda = 2` y si hay una `ronda = ronda + 1`,
  -- esta migracion ya corrio aqui. Se anota y no se toca.
  if v_n = 0
     and (length(v_def) - length(replace(v_def, 'ronda = ronda + 1', ''))) / length('ronda = ronda + 1') = 1 then
    update q14_antes set ya_estaba = true;
    return;
  end if;

  if v_n <> 1 then
    raise exception 'Q-14: responder_oferta() tiene % apariciones de "ronda = 2" (se esperaba 1). La funcion viva no es la que se midio: no se toca.', v_n;
  end if;
  v_nuevo := replace(v_def, 'ronda = 2', 'ronda = ronda + 1');
  execute v_nuevo;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Comprobacion — falla si el objetivo no se cumplio
-- ─────────────────────────────────────────────────────────────────────────
--
-- Como sabe fallar:
--   · El CHECK se lee del catalogo y ademas se ejerce: una ronda 3 tiene que
--     entrar y una ronda 0 no. Con el CHECK viejo, la 3 da 23514.
--   · responder_oferta(): la definicion nueva tiene que ser la vieja con esa
--     unica sustitucion, byte a byte; y sus permisos y su SECURITY DEFINER,
--     los de antes (CREATE OR REPLACE los conserva, pero se comprueba).

do $$
declare
  v_check   text;
  v_antes   text;
  v_ahora   text;
  v_def     boolean;
  v_estado  text;
  v_msg     text;
  v_oferta  uuid;
  v_ya      boolean;
begin
  select pg_get_constraintdef(c.oid) into v_check
    from pg_constraint c
   where c.conrelid = 'public.ofertas'::regclass and c.conname = 'ofertas_ronda_check';
  if v_check is null or v_check not like '%ronda >= 1%' then
    raise exception 'Q-14: ofertas_ronda_check no es "ronda >= 1": %', coalesce(v_check, '(no existe)');
  end if;

  -- El CHECK, ejercido sobre una oferta existente cualquiera, sin dejar rastro.
  select id into v_oferta from public.ofertas limit 1;
  if v_oferta is not null then
    begin
      alter table public.ofertas disable trigger user;
      update public.ofertas set ronda = 3 where id = v_oferta;
      raise exception 'Q14_OK';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    end;
    if v_msg <> 'Q14_OK' then
      raise exception 'Q-14: una ronda 3 sigue sin entrar: % %', v_estado, v_msg;
    end if;

    begin
      alter table public.ofertas disable trigger user;
      update public.ofertas set ronda = 0 where id = v_oferta;
      raise exception 'Q14_MAL';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    end;
    if v_estado <> '23514' then
      raise exception 'Q-14: una ronda 0 no la rechaza el CHECK: % %', v_estado, v_msg;
    end if;
  end if;

  -- responder_oferta(): exactamente la sustitucion, nada mas.
  select def, ya_estaba into v_antes, v_ya from q14_antes;
  v_ahora := pg_get_functiondef('public.responder_oferta(uuid, text, numeric, text)'::regprocedure);
  if v_ya then
    if v_ahora is distinct from v_antes then
      raise exception 'Q-14: responder_oferta() ya estaba migrada y aun asi cambio.';
    end if;
  else
    if v_ahora is distinct from replace(v_antes, 'ronda = 2', 'ronda = ronda + 1') then
      raise exception 'Q-14: responder_oferta() cambio en algo mas que la ronda.';
    end if;
    if v_ahora = v_antes then
      raise exception 'Q-14: responder_oferta() no cambio.';
    end if;
  end if;
  if position('ronda = 2' in v_ahora) > 0 or position('ronda = ronda + 1' in v_ahora) = 0 then
    raise exception 'Q-14: responder_oferta() no quedo con ronda = ronda + 1.';
  end if;

  select prosecdef into v_def from pg_proc
   where oid = 'public.responder_oferta(uuid, text, numeric, text)'::regprocedure;
  if not v_def then
    raise exception 'Q-14: responder_oferta() dejo de ser SECURITY DEFINER.';
  end if;
  if has_function_privilege('anon', 'public.responder_oferta(uuid, text, numeric, text)', 'EXECUTE') then
    raise exception 'Q-14: anon puede ejecutar responder_oferta().';
  end if;

  raise notice 'Q-14: ronda sin tope (CHECK ronda >= 1) y responder_oferta() con ronda + 1; ejercido sobre %.',
    coalesce(v_oferta::text, 'ninguna oferta (tabla vacia: solo catalogo)');
end $$;
