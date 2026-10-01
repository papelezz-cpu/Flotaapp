-- ─────────────────────────────────────────────────────────────────────────
-- Carta Porte, Etapa 4: domicilio estructurado de origen y destino
-- ─────────────────────────────────────────────────────────────────────────
--
-- `pedidos.origen`/`destino` son texto libre (lo que Nominatim devuelve como
-- display_name), más lat/lng del punto marcado en el mapa. No hay colonia,
-- código postal, ciudad ni estado por separado en ningún lado — y el
-- Complemento Carta Porte pide domicilio con esos cuatro campos aparte,
-- no una sola línea de texto.
--
-- No se le pide nada nuevo al cliente: js/mapa.js YA le pregunta a Nominatim
-- por el punto marcado para armar la etiqueta legible, y esa misma respuesta
-- trae el desglose — antes se tiraba, ahora se guarda también (ver
-- js/mapa.js, _direccionDeNominatim()).
--
-- Identificadores de texto, no fechas de vigencia: no entran al espejo hacia
-- `vigencias` (trg_vigencias_espejo no existe sobre `pedidos`), así que este
-- ALTER no necesita ningún rodeo.

alter table public.pedidos
  add column if not exists origen_colonia  text,
  add column if not exists origen_cp       text,
  add column if not exists origen_ciudad   text,
  add column if not exists origen_estado   text,
  add column if not exists destino_colonia text,
  add column if not exists destino_cp      text,
  add column if not exists destino_ciudad  text,
  add column if not exists destino_estado  text;

comment on column public.pedidos.destino_cp is
  'Código postal del destino, si Nominatim lo resolvió al marcar el punto en el mapa (js/mapa.js). Nulo cuando no lo tenía — nunca inventado. Para el domicilio del Complemento Carta Porte de referencia.';
