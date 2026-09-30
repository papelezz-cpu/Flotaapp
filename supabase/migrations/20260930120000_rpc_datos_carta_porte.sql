-- ─────────────────────────────────────────────────────────────────────────
-- Carta Porte: RPC para leer los dos lados de la reservación
-- ─────────────────────────────────────────────────────────────────────────
--
-- generarCartaPorte() (js/cartaporte.js) hacía consultas directas a
-- `perfiles` por cliente_user_id Y por propietario_id. Desde
-- 20260901120000_perfiles_cierra_leer_nombre_empresa.sql, `perfiles` solo
-- se puede leer la fila propia (o cualquiera, si eres superadmin) —
-- `perfiles_lectura_propia`: `user_id = auth.uid()`. Cuando quien genera el
-- documento es la EMPRESA, su consulta al perfil del CLIENTE la bloquea RLS
-- en silencio (0 filas, sin error): el remitente salía en blanco mientras
-- el transportista —su propia fila— salía completo. Medido el 2026-09-30
-- contra portgo-pruebas.
--
-- Esta función verifica al llamador contra la reservación concreta —no
-- contra la tabla entera— y entrega los dos lados en una sola consulta.
-- Mismo patrón que registrar_evidencias/calificar_servicio: SECURITY
-- DEFINER salta RLS, así que la autorización la hace la propia función, a
-- mano, no la política.
--
-- De paso resuelve el otro hueco que había quedado documentado en
-- js/cartaporte.js: el cliente tampoco podía generarla (camiones_publico no
-- trae placas/config/permiso SCT). Con esta función, cliente y propietario
-- quedan en el mismo pie — los dos son "parte" de la misma reservación.

create or replace function public.datos_carta_porte(p_reserva_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_r public.reservaciones%rowtype;
begin
  select * into v_r from public.reservaciones where id = p_reserva_id;
  if v_r.id is null then
    raise exception 'RESERVACION_NO_ENCONTRADA';
  end if;

  if not (
    public.is_superadmin()
    or v_r.cliente_user_id = auth.uid()
    or v_r.propietario_id  = auth.uid()
  ) then
    raise exception 'No autorizado';
  end if;

  return jsonb_build_object(
    'reservacion',   to_jsonb(v_r),
    'pedido',        (select to_jsonb(p)   from public.pedidos p     where p.id      = v_r.pedido_id),
    'cliente',       (select to_jsonb(c)   from public.perfiles c    where c.user_id = v_r.cliente_user_id),
    'transportista', (select to_jsonb(t)   from public.perfiles t    where t.user_id = v_r.propietario_id),
    -- Sin filtrar por recurso_tipo a propósito: si la unidad no es un
    -- camión, v_r.unidad no coincide con ningún id de `camiones` y esto da
    -- null solo, sin necesitar una rama aparte.
    'camion',        (select to_jsonb(cam) from public.camiones cam  where cam.id    = v_r.unidad),
    'operador',      (select to_jsonb(op)  from public.operadores op where op.id     = v_r.operador_id)
  );
end;
$$;

comment on function public.datos_carta_porte(uuid) is
  'Junta reservación+pedido+perfiles de cliente y propietario+camión+operador para la Carta Porte de referencia (js/cartaporte.js). Verifica que el llamador sea el cliente, el propietario o el superadmin de ESA reservación — SECURITY DEFINER salta RLS, así que la autorización la hace esta función, no la política de perfiles.';

revoke all on function public.datos_carta_porte(uuid) from public, anon;
grant execute on function public.datos_carta_porte(uuid) to authenticated;
