-- ============================================================================
-- Un techo por hora a los avisos al superadmin (H-20)
-- ============================================================================
--
-- ── El defecto ────────────────────────────────────────────────────────────
--
-- `notificar_superadmins(p_tipo, p_titulo, p_mensaje)` es SECURITY DEFINER,
-- está concedida a `authenticated`, y escribe en `notificaciones` saltándose
-- `puede_notificar()` con título y mensaje libres. Sin techo. Cualquier cuenta
-- con sesión puede llenar el panel del superadmin del texto que quiera, tantas
-- veces como quiera.
--
-- **La concesión es correcta y se queda.** El flujo la necesita desde quince
-- sitios, y el RLS de `notificaciones` —restringido por relación— no permitiría
-- a un cliente avisar al superadmin de otro modo. Lo que falta es el techo.
--
-- ── Por qué NO lanza excepción ────────────────────────────────────────────
--
-- Esto no se podía decidir leyendo la ficha del hallazgo, que dice «rechazar por
-- encima de un umbral». Rechazar *cómo* importa, porque la función **no se llama
-- solo desde el navegador**: cuatro RPC de negocio la invocan con PERFORM dentro
-- de su propia transacción —
--
--     aceptar_y_cerrar_acuerdo, cancelar_reservacion,
--     registrar_evidencias,    solicitar_cancelacion
--
-- — y una excepción ahí **tumba la transacción entera**. El cliente no podría
-- aceptar una oferta porque un contador de avisos dijo que no. Un techo de
-- notificaciones que rompe el cierre de un acuerdo es peor que el abuso que
-- evita, así que por encima del techo la función **descarta el aviso y vuelve**,
-- sin tocar la transacción de quien la llamó. Comprobado, no supuesto: la
-- verificación de abajo escribe algo y llama a la función por encima del techo,
-- y exige que la escritura sobreviva.
--
-- El descarte no es del todo silencioso: deja un `raise warning` en el log de
-- Postgres. En este proyecto un fallo callado cuesta horas.
--
-- ── Por qué descartar un aviso es asumible ────────────────────────────────
--
-- Porque **`cola_superadmin()` no lee `notificaciones`**: el globo y el panel
-- «Por aprobar» se calculan sobre las tablas de negocio. Un aviso descartado
-- pierde la campanita, no esconde el trabajo — que es justo el fallo que R-05
-- describió («un globo oculto es indistinguible de una cola vacía») y que aquí
-- no se reproduce. El correo tampoco pasa por esta función: lo manda
-- `enviar-notificacion` desde el cliente, por su propio camino.
--
-- ── De dónde sale el 60, y de dónde no ────────────────────────────────────
--
-- Medido sobre el volcado de PRODUCCIÓN del 2026-09-21 13:05
-- (`supabase/espejo/05-datos-public.sql`, 885 filas de `notificaciones`), no
-- sobre pruebas —cuyo sello de paridad estaba vencido y en `diverge` el día que
-- se escribió esto—. Una llamada deja una fila por superadmin con el MISMO
-- `created_at`, porque `now()` es fijo dentro de la sentencia; agrupando por ese
-- valor y quedándose con los grupos cuyos destinatarios son todos superadmins:
--
--     132 llamadas en todo el histórico
--     por hora:   mediana 1    p90 4    MÁXIMO 17
--     minuto punta: 7 llamadas
--
-- El techo se pone en **60/hora**, 3,5× el máximo observado. Deja sitio de
-- sobra a la ráfaga legítima que la ficha del hallazgo señalaba —un alta de
-- flota de N unidades dispara N avisos seguidos— y aun así convierte
-- «ilimitado» en 60 llamadas/hora como peor caso.
--
-- Lo que este número NO es: una medición por usuario. El volcado no guarda
-- quién generó cada fila —esta migración es la que empieza a guardarlo—, así
-- que 17 es el máximo de TODAS las cuentas juntas en su hora peor, y por tanto
-- una cota superior de lo que hizo cualquiera de ellas. Sirve para elegir un
-- techo holgado; no serviría para elegir uno apretado.
--
-- ── Por qué una tabla nueva, contra lo que dice la ficha ───────────────────
--
-- La ficha dice «contar las filas que ese `auth.uid()` ha generado» y «no
-- necesita tabla nueva». Las dos frases se apoyan en algo que no es cierto:
-- **`notificaciones` no guarda quién generó la fila.** `user_id` es el
-- DESTINATARIO. El dato del autor no existía.
--
-- El primer intento fue guardarlo en `meta->>'generado_por'` y contar por ahí.
-- **Es explotable, y peor que el defecto que arregla.** La política de INSERT
-- es `WITH CHECK (puede_notificar(user_id))`: solo restringe el destinatario,
-- no `meta`; y `puede_notificar()` deja a cualquiera notificarse **a sí mismo**.
-- Así que la cuenta A podía insertarse 60 filas a sí misma con
-- `meta.generado_por` = uuid de B y **dejar muda a B durante una hora**. Un
-- arreglo para un abuso de severidad baja que abre una denegación de servicio
-- contra terceros no es un arreglo.
--
-- El contador tiene que vivir donde el cliente no escriba. De ahí
-- `avisos_superadmin`: RLS activo y **cero políticas**, más los privilegios
-- revocados, así que no hay camino desde PostgREST — ni lectura ni escritura.
-- Solo la escribe esta función, que es SECURITY DEFINER y pertenece al dueño de
-- la tabla. De paso cuenta **llamadas** de forma natural, una fila por llamada:
-- contar filas de `notificaciones` habría atado el techo al número de
-- superadmins, y pasar de tres a cuatro lo habría apretado un 25 % sin que
-- nadie lo tocara.
--
-- **Ojo con el privilegio por omisión.** En este proyecto
-- `ALTER DEFAULT PRIVILEGES` concede ALL sobre TABLES a `authenticated` y
-- `service_role`, así que esta tabla **nace escribible** y lo único que la
-- cierra es el `revoke` de abajo. Es literalmente cómo pasó H-01 y cómo casi
-- volvió a pasar con `vigencias_caducidad`. La comprobación lo exige.
--
-- Crecimiento: una fila por aviso enviado. En producción son 132 en todo el
-- histórico volcado, ~26 al mes. A ese ritmo son ~3 000 filas en diez años, así
-- que no lleva purga; si algún día la lleva, será una decisión con su propia
-- conversación y no un `delete` escondido aquí.
-- ============================================================================

create table if not exists public.avisos_superadmin (
  id         bigint generated by default as identity primary key,
  autor      uuid        not null,
  tipo       text,
  created_at timestamptz not null default now()
);

comment on table public.avisos_superadmin is
  'H-20: una fila por llamada ACEPTADA a notificar_superadmins(), para contar el techo de 60/hora por autor. Vive aparte de notificaciones porque el autor no se puede guardar en una columna que el cliente escriba: la politica de INSERT de notificaciones solo restringe el destinatario, asi que cualquiera podria falsificar el autor y consumirle el techo a otro. RLS activo y SIN politicas: no hay acceso desde PostgREST.';

create index if not exists idx_avisos_superadmin_autor_hora
  on public.avisos_superadmin (autor, created_at desc);

alter table public.avisos_superadmin enable row level security;

-- Sin esto la tabla nace con ALL para authenticated y service_role, por el
-- ALTER DEFAULT PRIVILEGES del proyecto. RLS sin politicas ya bloquearia a
-- authenticated, pero service_role se salta el RLS: el revoke es lo que lo para.
revoke all on table public.avisos_superadmin from public, anon, authenticated, service_role;
revoke all on sequence public.avisos_superadmin_id_seq from public, anon, authenticated, service_role;


create or replace function public.notificar_superadmins(p_tipo text, p_titulo text, p_mensaje text)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid   uuid := auth.uid();
  v_techo constant integer := 60;   -- llamadas/hora por autor; ver cabecera
  v_n     integer;
begin
  -- Sin `auth.uid()` no hay a quién contarle nada: es el camino de
  -- `service_role` (Edge Functions, psql), que ya está por encima del RLS y no
  -- es el actor del que protege este techo. Pasa sin límite, a propósito.
  if v_uid is not null then
    select count(*) into v_n
      from public.avisos_superadmin a
     where a.autor = v_uid
       and a.created_at > now() - interval '1 hour';

    if v_n >= v_techo then
      -- Volver, NO lanzar: cuatro RPC de negocio llaman a esta función dentro
      -- de su transacción y una excepción se las llevaría por delante.
      raise warning 'notificar_superadmins: % lleva % avisos en la ultima hora (techo %). Aviso "%" descartado.',
        v_uid, v_n, v_techo, p_tipo;
      return;
    end if;

    insert into public.avisos_superadmin (autor, tipo) values (v_uid, p_tipo);
  end if;

  insert into public.notificaciones (user_id, tipo, titulo, mensaje, leido)
  select p.user_id, p_tipo, p_titulo, p_mensaje, false
    from public.perfiles p
   where p.rol = 'superadmin';
end $$;

comment on function public.notificar_superadmins(text, text, text) is
  'H-20: avisa a los superadmins con un techo de 60 llamadas/hora por autor (auth.uid()), contadas en public.avisos_superadmin. Por encima del techo DESCARTA el aviso y vuelve, sin excepcion: cuatro RPC de negocio la llaman con PERFORM dentro de su transaccion y una excepcion las abortaria. El techo sale de medir el volcado de produccion del 2026-09-21: maximo 17 llamadas/hora en todo el historico.';


-- La concesión de la función se mantiene tal cual —`authenticated` la necesita—
-- pero se reafirma: aunque `create or replace` conserva el ACL del objeto
-- existente, dejarlo escrito es lo que impide que la próxima vez se cuele.
revoke all on function public.notificar_superadmins(text, text, text) from public, anon;
grant execute on function public.notificar_superadmins(text, text, text) to authenticated, service_role;


-- ── Comprobación ───────────────────────────────────────────────────────────
--
-- La parte que importa es la de comportamiento: **ejercita el techo de
-- verdad**, con una sesión simulada, y comprueba que sabe fallar en cuatro
-- sentidos — por debajo deja pasar, por encima descarta, el techo es por autor,
-- y la transacción de quien llama sobrevive. Todo dentro de una subtransacción
-- que se descarta al final: no se borra nada, se tira el bloque.
--
-- `psql` conecta sin JWT, así que `auth.uid()` es NULL y el camino del techo no
-- se recorrería nunca. Se simula poniendo el claim que lee `auth.uid()`; si no
-- se consigue, esto **aborta la migración** en vez de darse por bueno. Una
-- comprobación que no se pudo ejecutar no es una comprobación que pasó.

do $$
declare
  v_uid     uuid := gen_random_uuid();
  v_otro    uuid := gen_random_uuid();
  v_sa      integer;
  v_antes   integer;
  v_despues integer;
  v_secdef  boolean;
  v_pol     integer;
  v_rls     boolean;
  r         record;
begin
  -- ── Lo estático ────────────────────────────────────────────────────────
  select prosecdef into v_secdef from pg_proc
   where proname = 'notificar_superadmins' and pronamespace = 'public'::regnamespace;
  if not coalesce(v_secdef, false) then
    raise exception 'H-20: notificar_superadmins dejo de ser SECURITY DEFINER; sin eso no puede saltarse puede_notificar() y el flujo se rompe.';
  end if;
  if has_function_privilege('anon', 'public.notificar_superadmins(text,text,text)', 'EXECUTE') then
    raise exception 'H-20: anon puede ejecutar notificar_superadmins.';
  end if;
  if not has_function_privilege('authenticated', 'public.notificar_superadmins(text,text,text)', 'EXECUTE') then
    raise exception 'H-20: authenticated NO puede ejecutarla; se caen los quince avisos del flujo.';
  end if;

  -- El contador tiene que ser inalcanzable desde el cliente. Si esto se abre,
  -- el techo pasa de proteger a ser un arma: cualquiera consume el de otro.
  select relrowsecurity into v_rls from pg_class
   where oid = 'public.avisos_superadmin'::regclass;
  if not coalesce(v_rls, false) then
    raise exception 'H-20: avisos_superadmin sin RLS.';
  end if;
  select count(*) into v_pol from pg_policies
   where schemaname = 'public' and tablename = 'avisos_superadmin';
  if v_pol <> 0 then
    raise exception 'H-20: avisos_superadmin tiene % politica(s). Debe tener CERO: nadie la lee ni la escribe desde PostgREST.', v_pol;
  end if;
  for r in select rol, priv
             from unnest(array['anon','authenticated','service_role']) rol
            cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) priv
  loop
    if has_table_privilege(r.rol, 'public.avisos_superadmin', r.priv) then
      raise exception 'H-20: % conserva % sobre avisos_superadmin. La tabla nace abierta por ALTER DEFAULT PRIVILEGES y el revoke no la cerro.', r.rol, r.priv;
    end if;
  end loop;

  if not exists (select 1 from pg_class where relname = 'idx_avisos_superadmin_autor_hora') then
    raise exception 'H-20: falta idx_avisos_superadmin_autor_hora.';
  end if;

  select count(*) into v_sa from public.perfiles where rol = 'superadmin';
  if v_sa < 1 then
    raise exception 'H-20: no hay superadmins; la prueba de comportamiento no distinguiria "descartado" de "no hay a quien avisar".';
  end if;

  -- ── Comportamiento, en una subtransacción que se descarta ──────────────
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_uid)::text, true);
    if auth.uid() is distinct from v_uid then
      perform set_config('request.jwt.claim.sub', v_uid::text, true);
    end if;
    if auth.uid() is distinct from v_uid then
      raise exception 'H-20-NOSIMULA';
    end if;

    -- (a) Por debajo del techo, deja pasar. 59 llamadas previas simuladas.
    insert into public.avisos_superadmin (autor, tipo, created_at)
    select v_uid, 'prueba_h20', now() - (i * interval '1 second')
      from generate_series(1, 59) i;

    select count(*) into v_antes from public.notificaciones;
    perform public.notificar_superadmins('prueba_h20', 't', 'm');
    select count(*) into v_despues from public.notificaciones;
    if v_despues - v_antes <> v_sa then
      raise exception 'H-20: con 59 avisos en la hora el techo YA bloquea (esperaba % filas nuevas, hubo %). Cortaria uso legitimo.',
        v_sa, v_despues - v_antes;
    end if;

    -- (b) Por encima del techo, descarta — y NO lanza excepcion. Esa llamada va
    --     en su propio bloque para poder distinguir "lanzo" de cualquier otro
    --     error: sin esto, sabotear el `return` a un `raise` aborta la migracion
    --     con el mensaje de la funcion y nadie entiende por que.
    select count(*) into v_antes from public.notificaciones;
    begin
      perform public.notificar_superadmins('prueba_h20', 't', 'm');
    exception when others then
      raise exception 'H-20: por encima del techo la funcion LANZO (%) en vez de volver. Asi se lleva por delante la transaccion de las cuatro RPC que la llaman con PERFORM.', sqlerrm;
    end;
    select count(*) into v_despues from public.notificaciones;
    if v_despues <> v_antes then
      raise exception 'H-20: con 60 avisos en la hora el techo NO bloqueo (% filas nuevas). La prueba sabe fallar: si esto pasa, el limite no existe.',
        v_despues - v_antes;
    end if;

    -- (c) La transaccion de quien llama SOBREVIVE al descarte. Es la razon de
    --     que la funcion vuelva en vez de lanzar: si lanzara, esta escritura
    --     —y con ella el cierre de un acuerdo— se perderia.
    create temp table h20_negocio(x int) on commit drop;
    insert into h20_negocio values (1);
    perform public.notificar_superadmins('prueba_h20', 't', 'm');
    if (select count(*) from h20_negocio) <> 1 then
      raise exception 'H-20: el descarte se llevo por delante la escritura de quien llamo.';
    end if;

    -- (d) El techo es por autor. Otra cuenta no arrastra el bloqueo de la
    --     primera: sin esto, un solo abusador dejaria muda a toda la app.
    perform set_config('request.jwt.claims', json_build_object('sub', v_otro)::text, true);
    perform set_config('request.jwt.claim.sub', v_otro::text, true);
    if auth.uid() is distinct from v_otro then
      raise exception 'H-20-NOSIMULA';
    end if;
    select count(*) into v_antes from public.notificaciones;
    perform public.notificar_superadmins('prueba_h20', 't', 'm');
    select count(*) into v_despues from public.notificaciones;
    if v_despues - v_antes <> v_sa then
      raise exception 'H-20: el techo NO es por autor: otra cuenta quedo bloqueada por los avisos de la primera (esperaba %, hubo %).',
        v_sa, v_despues - v_antes;
    end if;

    -- Descartar el bloque. No se borra nada: se tira la subtransaccion.
    raise exception 'H-20-DESCARTAR';
  exception
    when others then
      if sqlerrm = 'H-20-NOSIMULA' then
        raise exception 'H-20: no se pudo simular auth.uid() desde psql, asi que la prueba de comportamiento NO se ejecuto. No se da por buena: revisa como lee auth.uid() los claims en este proyecto.';
      elsif sqlerrm <> 'H-20-DESCARTAR' then
        raise;
      end if;
  end;

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  raise notice 'H-20: techo de 60 avisos/hora por autor. Ejercitado: 59 pasa, 60 descarta sin excepcion, la transaccion de quien llama sobrevive, y el bloqueo no salpica a otra cuenta. % superadmins. El contador vive en avisos_superadmin, sin politicas y sin privilegios para anon/authenticated/service_role.', v_sa;
end $$;
