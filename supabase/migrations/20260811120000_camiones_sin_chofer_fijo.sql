-- ──────────────────────────────────────────────────────────────────────────
-- El chofer deja de ser un dato de la unidad.
--
-- Se pedía dos veces: al dar de alta el camión (camiones.operador) y otra vez
-- al ofertar un viaje (ofertas.operador_id / operador_nombre). La segunda es
-- la que importa — es la que queda en el acuerdo y la que ve el cliente — y
-- además es la correcta: un camión no trae siempre al mismo operador.
--
-- Peor todavía, la primera nunca sirvió ni para prellenar la segunda:
-- camiones.operador guardaba el NOMBRE completo del chofer y el selector de la
-- oferta trabaja con el ID de la tabla operadores, así que la preselección
-- ("si esta unidad ya tiene chofer, márcalo") jamás encontraba coincidencia.
--
-- NO se hace DROP COLUMN: hay unidades históricas con el nombre escrito y la
-- misma convención se siguió con hora_carga, contacto_nombre y carga_peligrosa
-- — se conservan, se dejan de escribir. Desde esta versión la app no la escribe
-- (js/admin.js) ni la muestra (js/camiones.js, js/detalle.js).
-- ──────────────────────────────────────────────────────────────────────────

COMMENT ON COLUMN public.camiones.operador IS
  'OBSOLETA desde 2026-08-11. Nombre del chofer asignado fijo a la unidad. La app ya no la escribe ni la lee: el chofer se elige al ofertar el viaje (ofertas.operador_id). Se conserva solo por las unidades históricas.';
