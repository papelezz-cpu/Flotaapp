-- ─────────────────────────────────────────────────────────────────────────
-- Carta Porte, Etapa 5: clave de producto/servicio SAT de la mercancía
-- ─────────────────────────────────────────────────────────────────────────
--
-- El catálogo SAT de claves de producto/servicio tiene decenas de miles de
-- entradas — no se importa completo, ni aquí ni en ningún otro catálogo del
-- sistema. Quien ya hace comercio exterior normalmente conoce la suya; se
-- captura como texto libre junto a la descripción de la mercancía
-- (`np-clave-sat`, opcional, no bloquea el pedido si se deja vacía).
--
-- Identificador de texto, no fecha de vigencia: no entra al espejo hacia
-- `vigencias`, así que este ALTER no necesita ningún rodeo.

alter table public.pedidos
  add column if not exists clave_prod_serv_sat text;

comment on column public.pedidos.clave_prod_serv_sat is
  'Clave del catálogo SAT "c_ClaveProdServ" para la mercancía del pedido — texto libre, opcional. Para el Complemento Carta Porte de referencia (Etapa 5). El catálogo completo no vive en este sistema: decenas de miles de claves, y quien ya hace comercio exterior conoce la suya.';
