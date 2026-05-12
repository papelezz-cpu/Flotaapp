CREATE TABLE IF NOT EXISTS documentos_fiscales (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservacion_id   uuid REFERENCES reservaciones(id),
  tipo             text NOT NULL CHECK (tipo IN ('carta_porte', 'factura')),
  -- Datos del CFDI
  folio_fiscal     text,           -- UUID timbrado por el SAT
  numero_folio     text,
  serie            text,
  -- PAC que lo generó (Facturapi, Facturama, etc.)
  pac              text,
  pac_id           text,           -- ID interno del PAC
  -- Archivos
  xml_url          text,
  pdf_url          text,
  -- Estado
  estado           text NOT NULL DEFAULT 'vigente' CHECK (estado IN ('vigente', 'cancelado')),
  cancelado_en     timestamptz,
  cancelado_por    uuid REFERENCES auth.users(id),
  motivo_cancelacion text,
  -- Auditoría
  emitido_por      uuid REFERENCES auth.users(id),
  created_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE documentos_fiscales ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_ve_sus_docs" ON documentos_fiscales
  FOR SELECT USING (
    emitido_por = auth.uid()
  );

CREATE POLICY "cliente_ve_sus_docs" ON documentos_fiscales
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM reservaciones r
      WHERE r.id = reservacion_id
        AND r.cliente_user_id = auth.uid()
    )
  );

CREATE POLICY "superadmin_ve_todo_docs" ON documentos_fiscales
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM perfiles
      WHERE user_id = auth.uid() AND rol = 'superadmin'
    )
  );
