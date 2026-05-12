CREATE TABLE IF NOT EXISTS pagos (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservacion_id   uuid REFERENCES reservaciones(id),
  monto            numeric NOT NULL,
  moneda           text NOT NULL DEFAULT 'MXN',
  -- Método y procesador
  metodo           text CHECK (metodo IN ('spei', 'tarjeta', 'efectivo', 'transferencia', 'otro')),
  proveedor        text CHECK (proveedor IN ('stripe', 'conekta', 'openpay', 'manual')),
  proveedor_id     text,           -- ID de la transacción en el procesador (payment_intent, etc.)
  -- Estado
  estado           text NOT NULL DEFAULT 'pendiente'
                   CHECK (estado IN ('pendiente', 'completado', 'fallido', 'reembolsado')),
  -- Referencia para el pagador (CLABE SPEI, últimos 4 dígitos tarjeta, etc.)
  referencia       text,
  comprobante_url  text,
  -- Auditoría
  registrado_por   uuid REFERENCES auth.users(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  completado_en    timestamptz,
  nota             text
);

ALTER TABLE pagos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_ve_sus_pagos" ON pagos
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM reservaciones r
      WHERE r.id = reservacion_id
        AND r.propietario_id = auth.uid()
    )
  );

CREATE POLICY "cliente_ve_sus_pagos" ON pagos
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM reservaciones r
      WHERE r.id = reservacion_id
        AND r.cliente_user_id = auth.uid()
    )
  );

CREATE POLICY "superadmin_gestiona_pagos" ON pagos
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM perfiles
      WHERE user_id = auth.uid() AND rol = 'superadmin'
    )
  );

CREATE POLICY "admin_registra_pago_manual" ON pagos
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM reservaciones r
      WHERE r.id = reservacion_id
        AND r.propietario_id = auth.uid()
    )
  );
