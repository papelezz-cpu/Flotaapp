-- ============================================================================
-- El doble booking pasa a ser imposible, no solo improbable
-- ============================================================================
--
-- check_reservacion_disponibilidad() comprueba con un EXISTS y despues deja
-- pasar el INSERT. Entre la comprobacion y el commit cabe otra transaccion
-- identica: las dos ven la unidad libre y las dos escriben. Es una carrera
-- TOCTOU de manual, y en logistica significa un camion que no llega.
--
-- Una restriccion EXCLUDE lo resuelve en el indice: Postgres garantiza que no
-- existan dos filas cuyo rango de fechas se solape para la misma unidad. No
-- hay ventana entre comprobar y escribir porque no hay comprobacion separada.
--
-- Necesita btree_gist para poder mezclar en un mismo indice una comparacion
-- por igualdad (unidad, que es text) con una por solapamiento (el rango).
--
-- ── Por que se puede aplicar ahora ────────────────────────────────────────
-- Si ya existieran solapes, la creacion del indice fallaria. Medido justo
-- antes en las dos bases: 0 pares solapados.
--
-- ── El trigger se queda ───────────────────────────────────────────────────
-- No se elimina check_reservacion_disponibilidad. Sigue siendo util porque
-- devuelve un mensaje legible ('RECURSO_NO_DISPONIBLE') que el cliente ya
-- interpreta, mientras que la restriccion devuelve un error de Postgres.
-- El trigger atrapa el caso normal; la restriccion atrapa la carrera. Con el
-- indice parcial idx_reservaciones_disponibilidad que añadio la auditoria, el
-- trigger ya no cuesta un seq scan.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE conname = 'reservaciones_sin_solape'
                AND conrelid = 'public.reservaciones'::regclass) THEN
    RAISE NOTICE 'La restriccion ya existe, no se hace nada.';
    RETURN;
  END IF;

  -- Solo los estados vivos: una reservacion completada o cancelada no ocupa
  -- la unidad, y exigirle no solaparse impediria volver a reservar el mismo
  -- camion en las mismas fechas del año siguiente.
  --
  -- El rango es '[]' —ambos extremos incluidos— igual que en el trigger, para
  -- que las dos defensas digan exactamente lo mismo: una reserva que termina
  -- el dia 10 y otra que empieza el dia 10 SI se solapan.
  ALTER TABLE public.reservaciones
    ADD CONSTRAINT reservaciones_sin_solape
    EXCLUDE USING gist (
      unidad WITH =,
      daterange(fecha_ini, fecha_fin, '[]') WITH &&
    )
    WHERE (estado IN ('Pendiente', 'Activa'));

  RAISE NOTICE 'Restriccion de no solape creada.';
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'reservaciones_sin_solape'
                    AND conrelid = 'public.reservaciones'::regclass) THEN
    RAISE EXCEPTION 'La restriccion de no solape no quedo instalada';
  END IF;
  RAISE NOTICE 'Verificado: el solape de reservas vivas es imposible a nivel de indice.';
END $$;
