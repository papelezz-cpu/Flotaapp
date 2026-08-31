-- Cierra los tres huecos que destapó pruebas/03-flujo-completo.mjs el
-- 2026-08-31, corriendo sobre una copia verificada de producción.
--
-- Los tres tienen la misma forma: la regla de negocio vive en el navegador o
-- en una RPC que el PWA no usa, así que cualquiera con la anon key y un
-- cliente REST se la salta. La defensa de verdad tiene que estar en la base.

-- ─────────────────────────────────────────────────────────────────────────
-- 1. El cliente no puede fabricarse una reservación ya activa y con precio
-- ─────────────────────────────────────────────────────────────────────────
--
-- OJO: reservar directo SÍ es una función del producto. Desde el catálogo
-- (js/camiones.js, js/recursos.js) el cliente pulsa "Agendar" y js/modal.js
-- crea la reservación. Pero la crea con estado 'Pendiente' y SIN precio: la
-- empresa es quien confirma y quien pone el precio.
--
-- Lo que se cuela por REST es otra cosa: insertar la fila ya en 'Activa' y con
-- precio_acordado a gusto. Eso compromete la unidad de una empresa en un trato
-- que nadie aceptó, y la empresa se entera cuando ya tiene el viaje encima.
--
-- Este guard deja intacto el "Agendar" real y bloquea solo eso.
create or replace function public.guard_reservacion_insert()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  -- El superadmin cierra los acuerdos: js/aprobaciones.js llama a
  -- cerrarAcuerdo(), y ahí la reserva nace 'Activa' con el precio pactado.
  if public.is_superadmin() then
    return new;
  end if;

  -- La empresa dueña del recurso puede crearla como quiera: es la parte que
  -- acepta el trato, no la que se lo impone a otro.
  if new.propietario_id = auth.uid() then
    return new;
  end if;

  if new.cliente_user_id = auth.uid() then
    if new.estado is distinct from 'Pendiente' then
      raise exception 'No autorizado: una reserva que tu creas nace Pendiente; la confirma la empresa';
    end if;
    if new.precio_acordado is not null then
      raise exception 'No autorizado: el precio lo fija la empresa al aceptar, no quien agenda';
    end if;
    if new.pedido_id is not null and not public.es_mi_pedido(new.pedido_id) then
      raise exception 'No autorizado: esa solicitud no es tuya';
    end if;
    return new;
  end if;

  raise exception 'No autorizado: solo puedes crear reservaciones a tu nombre';
end;
$$;

revoke all on function public.guard_reservacion_insert() from public, anon, authenticated;

drop trigger if exists trg_guard_reservacion_insert on public.reservaciones;
create trigger trg_guard_reservacion_insert
  before insert on public.reservaciones
  for each row execute function public.guard_reservacion_insert();

-- ─────────────────────────────────────────────────────────────────────────
-- 2. Un pedido nace en revisión, no acordado
-- ─────────────────────────────────────────────────────────────────────────
--
-- ped_insert_own solo comprobaba que el cliente_id fuera el del que inserta.
-- El estado inicial quedaba libre, así que un cliente podía publicar el pedido
-- directamente en 'acordado' y saltarse entera la revisión del superadmin.
-- Los guard triggers vigilan los UPDATE; el INSERT no lo miraba nadie.
--
-- Los dos sitios que crean pedidos en la app (js/pedidos.js:1473 y :2525)
-- ponen 'pendiente_revision', así que esto no cambia ningún camino real.
--
-- ALTER POLICY modifica en sitio: no se borra ninguna política.
alter policy ped_insert_own on public.pedidos
  with check (
    (((select auth.uid()) = cliente_id) and estado = 'pendiente_revision')
    or (select public.is_superadmin())
  );

-- ─────────────────────────────────────────────────────────────────────────
-- 3. El bloqueo de teléfonos, en la base y no solo en el navegador
-- ─────────────────────────────────────────────────────────────────────────
--
-- El filtro existía en dos sitios que se saltan igual de fácil: en el cliente
-- (_contieneTelefono() de js/chat.js) y en la RPC enviar_mensaje, que el PWA
-- no llama. Un insert directo a mensajes por REST pasaba el teléfono entero,
-- que es exactamente la desintermediación que el chat intenta evitar.
--
-- Mismo criterio que los otros dos, literal: 10 o más dígitos seguidos,
-- admitiendo espacios, puntos, guiones y paréntesis como separadores.
create or replace function public.guard_mensaje_texto()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if new.texto ~ '(\+?[0-9][ .\-()]*){10,}' then
    raise exception 'Por seguridad no se permiten números de teléfono en el chat. Mantén el trato dentro de PortGo.';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_mensaje_texto() from public, anon, authenticated;

-- INSERT y también UPDATE del texto: si no, bastaría con mandar un mensaje
-- limpio y editarlo después para colar el número.
drop trigger if exists trg_guard_mensaje_texto on public.mensajes;
create trigger trg_guard_mensaje_texto
  before insert or update of texto on public.mensajes
  for each row execute function public.guard_mensaje_texto();
