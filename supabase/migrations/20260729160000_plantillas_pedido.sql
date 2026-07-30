-- Plantillas de solicitud ("frecuentes") del cliente.
--
-- Muchos clientes repiten la misma ruta con la misma carga. El formulario de
-- solicitud tiene ~20 campos, asi que volver a llenarlo cada vez es la friccion
-- mas grande del flujo del cliente. Con esto puede guardar una solicitud como
-- frecuente y reutilizarla con un toque.
--
-- Deliberadamente NO se guardan las fechas: son lo unico que cambia siempre.

create table if not exists public.plantillas_pedido (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references auth.users(id) on delete cascade,
  nombre      text not null,

  -- Servicio y carga
  tipo_camion       text,
  tipo_carga        text,
  capacidad_min     numeric,
  peso_carga        numeric,
  num_bultos        integer,
  tipo_contenedor   text,

  -- Ruta y logistica
  origen            text,
  destino           text,
  hora_carga        text,
  contacto_nombre   text,
  contacto_tel      text,

  -- Requisitos especiales
  carga_peligrosa   boolean not null default false,
  temp_controlada   boolean not null default false,
  requiere_seguro   boolean not null default false,
  requiere_factura  boolean not null default false,

  -- Comercial
  precio_cliente    numeric,
  plazo_pago        text,
  descripcion       text,

  -- Campos de los otros tipos de servicio (hoy deshabilitados en la UI, pero
  -- la plantilla los soporta para no tener que migrar cuando se activen)
  num_custodios     integer,
  zona_cobertura    text,
  horario_servicio  text,
  num_vehiculos     integer,
  tipo_vehiculos    text,
  area_necesaria    numeric,

  -- Para ordenar por utilidad real, no por fecha de creacion
  veces_usada       integer not null default 0,
  ultima_vez_usada  timestamptz,
  created_at        timestamptz not null default now()
);

create index if not exists idx_plantillas_cliente
  on public.plantillas_pedido (cliente_id, veces_usada desc, created_at desc);

-- Un cliente no deberia acumular decenas: evita una lista inmanejable y un
-- uso abusivo de la tabla.
create or replace function public.limitar_plantillas()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.plantillas_pedido where cliente_id = new.cliente_id) >= 12 then
    raise exception 'Alcanzaste el maximo de 12 solicitudes frecuentes. Elimina alguna para guardar otra.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_limitar_plantillas on public.plantillas_pedido;
create trigger trg_limitar_plantillas
  before insert on public.plantillas_pedido
  for each row execute function public.limitar_plantillas();

alter table public.plantillas_pedido enable row level security;

-- Cada cliente gestiona unicamente las suyas. El superadmin no las necesita:
-- son una comodidad privada del cliente, no informacion operativa.
drop policy if exists plantillas_select_propias on public.plantillas_pedido;
create policy plantillas_select_propias on public.plantillas_pedido
  for select to authenticated using (cliente_id = auth.uid());

drop policy if exists plantillas_insert_propias on public.plantillas_pedido;
create policy plantillas_insert_propias on public.plantillas_pedido
  for insert to authenticated with check (cliente_id = auth.uid());

drop policy if exists plantillas_update_propias on public.plantillas_pedido;
create policy plantillas_update_propias on public.plantillas_pedido
  for update to authenticated
  using (cliente_id = auth.uid()) with check (cliente_id = auth.uid());

drop policy if exists plantillas_delete_propias on public.plantillas_pedido;
create policy plantillas_delete_propias on public.plantillas_pedido
  for delete to authenticated using (cliente_id = auth.uid());
