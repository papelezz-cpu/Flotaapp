-- El guard de expedientes (20260817190000) bloqueaba TODO cambio de
-- `estado` hecho por el cliente, incluido el único que el propio cliente
-- debe poder disparar: cuando termina de subir el checklist completo, el
-- expediente pasa de 'solicitado' a 'en_revision' para que el transportista
-- lo revise (_avisarSiCompleto en js/expedientes.js).
--
-- Esa función corre en la sesión del cliente —es su propia subida la que la
-- dispara— así que el guard la rechazaba con la misma excepción que usa para
-- bloquear el hueco real (el cliente marcando 'completo' por su cuenta, sin
-- que nadie revise). El UPDATE fallaba, pero js/expedientes.js no
-- comprobaba el `error` de esa llamada, así que el aviso al transportista
-- SÍ salía («Documentación lista para revisar») mientras el expediente se
-- quedaba en 'solicitado' para siempre — la campana avisaba de un cambio
-- que nunca pasó. Verificado el 2026-09-29 en pruebas: los 5 documentos
-- obligatorios de Puerto en 'subido', expediente todavía 'solicitado'.
--
-- La corrección no relaja el guard en general — sigue sin dejar que el
-- cliente ponga el expediente en 'completo' ni en cualquier otro estado por
-- su cuenta. Abre un solo hueco, angosto y verificado contra la base, no
-- contra lo que mande el navegador: 'solicitado' → 'en_revision', y solo si
-- de verdad no queda ningún documento obligatorio sin subir.

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
    if new.estado is distinct from old.estado then
      if old.estado = 'solicitado' and new.estado = 'en_revision' then
        -- La única transición que dispara el cliente, y se verifica aquí
        -- —no en el navegador—: que no quede ningún documento obligatorio
        -- sin subir. Si alguno falta, ni el propio JS debería haber
        -- llegado hasta aquí, pero el guard no confía en eso.
        if exists (
          select 1 from public.expediente_documentos d
          where d.expediente_id = new.id
            and d.obligatorio
            and d.estado not in ('subido', 'aceptado')
        ) then
          raise exception 'No autorizado: todavía falta subir un documento obligatorio';
        end if;
      else
        raise exception 'No autorizado: eso lo gestiona el transportista';
      end if;
    end if;

    -- El cliente solo declara la entrega en físico; cerrar el expediente,
    -- fechar el cierre, reportar incidentes o fijar los datos del depósito
    -- de vacíos es trabajo del transportista.
    if new.completado_en        is distinct from old.completado_en
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
