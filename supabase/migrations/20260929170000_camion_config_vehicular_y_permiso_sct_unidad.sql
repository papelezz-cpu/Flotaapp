-- ─────────────────────────────────────────────────────────────────────────
-- Carta Porte, Etapa 2: configuración vehicular (SAT) y permiso SCT de la
-- unidad — ninguno de los dos existía
-- ─────────────────────────────────────────────────────────────────────────
--
-- `camiones` solo tenía la fecha de vencimiento del permiso SCT y su
-- documento — nunca el número — y ningún campo para la clave de
-- configuración vehicular que el Complemento Carta Porte exige (C2, C3,
-- T3S2…). Los dos son identificadores estáticos, no fechas de vigencia:
-- no entran al espejo hacia `vigencias` (trg_vigencias_espejo), así que
-- este ALTER no necesita el mismo rodeo que 20260929140000.

alter table public.camiones
  add column if not exists configuracion_vehicular text,
  add column if not exists numero_permiso_sct      text;

comment on column public.camiones.configuracion_vehicular is
  'Clave SAT de configuración vehicular del Complemento Carta Porte (C2, C3, T3S2…) — catálogo en catalogos, clave=''config_vehicular_sat''.';
comment on column public.camiones.numero_permiso_sct is
  'Número de permiso SCT de ESTA unidad — distinto de perfiles.permiso_sct, que es el permiso general de la empresa.';

-- Catálogo curado, no el completo del SAT (~80 claves, la mayoría para
-- transporte de pasajeros o configuraciones que esta flota no usa). Agregar
-- una clave que falte es una fila nueva, no una migración — mismo patrón
-- que 'vigencia_tipo' en js/vigencias.js:57.
insert into public.catalogos (clave, valor, etiqueta, orden, activo) values
  ('config_vehicular_sat', 'VL',     'Vehículo ligero de carga',            10, true),
  ('config_vehicular_sat', 'C2',     'Camión unitario (2 ejes)',            20, true),
  ('config_vehicular_sat', 'C3',     'Camión unitario (3 ejes)',            30, true),
  ('config_vehicular_sat', 'C2R2',   'Camión-remolque (2+2 ejes)',          40, true),
  ('config_vehicular_sat', 'C3R2',   'Camión-remolque (3+2 ejes)',          50, true),
  ('config_vehicular_sat', 'C3R3',   'Camión-remolque (3+3 ejes)',          60, true),
  ('config_vehicular_sat', 'T2S1',   'Tractocamión articulado (2+1 ejes)',  70, true),
  ('config_vehicular_sat', 'T2S2',   'Tractocamión articulado (2+2 ejes)',  80, true),
  ('config_vehicular_sat', 'T2S3',   'Tractocamión articulado (2+3 ejes)',  90, true),
  ('config_vehicular_sat', 'T3S1',   'Tractocamión articulado (3+1 ejes)', 100, true),
  ('config_vehicular_sat', 'T3S2',   'Tractocamión articulado (3+2 ejes)', 110, true),
  ('config_vehicular_sat', 'T3S3',   'Tractocamión articulado (3+3 ejes)', 120, true),
  ('config_vehicular_sat', 'T3S2R4', 'Tractocamión articulado-remolque (3+2+4 ejes)', 130, true),
  ('config_vehicular_sat', 'T3S3R4', 'Tractocamión articulado-remolque (3+3+4 ejes)', 140, true),
  ('config_vehicular_sat', 'OTROS',  'Otra configuración no listada',      990, true)
on conflict (clave, valor) do nothing;
