-- El vacío no siempre vuelve al recinto portuario: a veces la naviera lo
-- manda a un depósito/patio externo. Es una bandera distinta de
-- entra_a_puerto (puede aplicar una, la otra, o ambas), y sirve para
-- disparar solo el expediente de 'entrega_vacios' apenas se hace match,
-- en vez de esperar a que el tracking llegue a 'Entregado'
-- (ver js/pedidos.js:cerrarAcuerdo y js/expedientes.js:_crearExpedienteAuto).

ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS patio_externo boolean NOT NULL DEFAULT false;
ALTER TABLE public.plantillas_pedido
  ADD COLUMN IF NOT EXISTS patio_externo boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.pedidos.patio_externo IS
  'El contenedor vacío se devuelve a un depósito externo (no necesariamente el recinto portuario). Habilita el expediente documental de entrega de vacíos apenas se cierra el acuerdo.';
