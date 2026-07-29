-- Estados de pago de las reservaciones.
--
-- Hasta ahora el cobro se reflejaba con un solo booleano `pagado` que alguien
-- marcaba a mano, sin fecha de vencimiento ni rastro de cuando ni como se
-- cobro. Como el mercado opera a credito (el cliente paga N dias despues del
-- servicio), hace falta saber cuando vence cada cobro para poder distinguir
-- "por cobrar" de "vencido".
--
-- Se mantiene `pagado` para no romper lo existente. El estado visible se
-- deriva en la interfaz: pagado / vencido (no pagado y ya paso la fecha) /
-- por cobrar. Derivarlo evita tener que correr un proceso que cambie estados
-- todos los dias.

alter table public.reservaciones
  -- Snapshot del plazo pactado en el pedido ("30 dias", "Anticipado", ...).
  -- Se guarda en la reservacion porque el pedido puede reabrirse o cambiar.
  add column if not exists plazo_pago text,
  -- Se calcula al aprobarse la finalizacion del servicio.
  add column if not exists fecha_vencimiento_pago date,
  add column if not exists pagado_en timestamptz,
  add column if not exists pagado_por uuid references auth.users(id) on delete set null,
  add column if not exists pago_metodo text,
  add column if not exists pago_referencia text;

-- Para listar rapido los cobros vencidos.
create index if not exists idx_reservaciones_cobro
  on public.reservaciones (pagado, fecha_vencimiento_pago)
  where estado = 'Completada';

-- Coherencia: si se marca pagado, debe quedar la fecha; si se revierte, se
-- limpian los datos del cobro. Evita filas a medias por un update parcial.
create or replace function public.sync_datos_pago()
returns trigger
language plpgsql
as $$
begin
  if new.pagado is true and (old.pagado is distinct from true) then
    new.pagado_en := coalesce(new.pagado_en, now());
  elsif new.pagado is not true then
    new.pagado_en      := null;
    new.pagado_por     := null;
    new.pago_metodo    := null;
    new.pago_referencia := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_datos_pago on public.reservaciones;
create trigger trg_sync_datos_pago
  before update on public.reservaciones
  for each row execute function public.sync_datos_pago();
