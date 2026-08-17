-- Dos huecos encontrados en la corrida de pruebas del 17-ago:
--
-- 1) trg_guard_expediente_documento solo protege expediente_documentos (cada
--    documento suelto); nada protegía a expedientes.estado, así que el
--    cliente podía marcar el expediente completo el mismo directo por API,
--    sin que el transportista lo revisara.
--
-- 2) No había ningún candado en la base para exigir licencia de materiales
--    peligrosos vigente al asignar chofer a un servicio de carga peligrosa
--    (carga_peligrosa=true en pedidos) — el filtro que oculta choferes sin
--    esa licencia solo vive en el <select> del navegador.

-- ── 1) Guard en expedientes (la fila completa, no solo cada documento) ──
create or replace function public.guard_expediente_update()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  es_cliente boolean;
begin
  if public.is_superadmin() then return new; end if;

  select (r.cliente_user_id = auth.uid()) into es_cliente
  from public.reservaciones r
  where r.id = new.reserva_id;

  if es_cliente then
    -- El cliente solo declara la entrega en físico; cerrar el expediente,
    -- fechar el cierre, reportar incidentes o fijar los datos del depósito
    -- de vacíos es trabajo del transportista.
    if new.estado                  is distinct from old.estado
       or new.completado_en        is distinct from old.completado_en
       or new.incidente_motivo     is distinct from old.incidente_motivo
       or new.incidente_reportado_en  is distinct from old.incidente_reportado_en
       or new.incidente_reportado_por is distinct from old.incidente_reportado_por
       or new.deposito_vacios      is distinct from old.deposito_vacios
       or new.fecha_limite_vacios  is distinct from old.fecha_limite_vacios then
      raise exception 'No autorizado: eso lo gestiona el transportista';
    end if;
  else
    -- El transportista no declara en nombre del cliente que la entrega va a
    -- ser en físico.
    if new.entrega_fisica            is distinct from old.entrega_fisica
       or new.entrega_fisica_direccion is distinct from old.entrega_fisica_direccion
       or new.entrega_fisica_contacto  is distinct from old.entrega_fisica_contacto then
      raise exception 'No autorizado: la entrega en físico la declara el cliente';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_expediente_update on public.expedientes;
create trigger trg_guard_expediente_update
  before update on public.expedientes
  for each row execute function public.guard_expediente_update();

-- ── 2) Licencia de materiales peligrosos vigente, exigida en la base ────
-- Aplica sin excepción de rol (ni superadmin): no es un permiso, es una
-- validez de datos — igual que check_reservacion_disponibilidad no deja
-- traslapar reservas para nadie.
create or replace function public.guard_operador_hazmat()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  es_peligrosa boolean;
  licencia_ok  boolean;
begin
  if new.operador_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.operador_id is not distinct from old.operador_id then
    return new;
  end if;

  select p.carga_peligrosa into es_peligrosa
  from public.pedidos p where p.id = new.pedido_id;

  if not coalesce(es_peligrosa, false) then return new; end if;

  select (o.doc_licencia_peligrosa is not null
          and o.fecha_vencimiento_licencia_peligrosa is not null
          and o.fecha_vencimiento_licencia_peligrosa >= current_date)
    into licencia_ok
  from public.operadores o where o.id = new.operador_id;

  if not coalesce(licencia_ok, false) then
    raise exception 'LICENCIA_PELIGROSA_REQUERIDA: este servicio es de carga peligrosa; el chofer necesita licencia vigente de materiales peligrosos';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_operador_hazmat_ofertas on public.ofertas;
create trigger trg_guard_operador_hazmat_ofertas
  before insert or update on public.ofertas
  for each row execute function public.guard_operador_hazmat();

drop trigger if exists trg_guard_operador_hazmat_reservaciones on public.reservaciones;
create trigger trg_guard_operador_hazmat_reservaciones
  before update on public.reservaciones
  for each row execute function public.guard_operador_hazmat();
