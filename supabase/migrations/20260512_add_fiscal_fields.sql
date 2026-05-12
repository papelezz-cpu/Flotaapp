-- Campos fiscales en perfiles (requeridos por SAT para emitir CFDI)
ALTER TABLE perfiles
  ADD COLUMN IF NOT EXISTS regimen_fiscal      text,
  ADD COLUMN IF NOT EXISTS cp_fiscal           text,
  ADD COLUMN IF NOT EXISTS tipo_persona        text CHECK (tipo_persona IN ('fisica', 'moral'));

-- Campos de mercancía en reservaciones (requeridos para Complemento Carta Porte)
ALTER TABLE reservaciones
  ADD COLUMN IF NOT EXISTS peso_kg             numeric,
  ADD COLUMN IF NOT EXISTS descripcion_mercancia text,
  ADD COLUMN IF NOT EXISTS clave_sat_mercancia text,   -- catálogo c_ClaveProdServ del SAT
  ADD COLUMN IF NOT EXISTS unidad_medida_sat   text,   -- catálogo c_ClaveUnidad del SAT
  ADD COLUMN IF NOT EXISTS num_piezas          integer,
  ADD COLUMN IF NOT EXISTS num_pedido_factura  text;   -- número de pedido para referencia en factura
