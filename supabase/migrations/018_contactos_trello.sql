-- =============================================================================
-- ObrasPlan — Migración 18: Contactos + campos Trello en obras
-- =============================================================================

-- Tabla contactos (personas de contacto vinculadas a clientes)
CREATE TABLE IF NOT EXISTS contactos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  cliente_id UUID REFERENCES clientes(id) ON DELETE SET NULL,
  nombre TEXT NOT NULL,
  email TEXT,
  telefono TEXT,
  cargo TEXT,
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE contactos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "contactos_select" ON contactos FOR SELECT USING (true);
CREATE POLICY "contactos_all" ON contactos FOR ALL USING (auth.role() = 'authenticated');

CREATE INDEX IF NOT EXISTS idx_contactos_cliente ON contactos(cliente_id);
CREATE INDEX IF NOT EXISTS idx_contactos_email ON contactos(email);

-- Campos nuevos en obras para trazabilidad Trello
ALTER TABLE obras ADD COLUMN IF NOT EXISTS trello_card_id TEXT;
ALTER TABLE obras ADD COLUMN IF NOT EXISTS trello_url TEXT;
ALTER TABLE obras ADD COLUMN IF NOT EXISTS contacto_id UUID REFERENCES contactos(id) ON DELETE SET NULL;
ALTER TABLE obras ADD COLUMN IF NOT EXISTS sync_status TEXT;
ALTER TABLE obras ADD COLUMN IF NOT EXISTS sync_notes TEXT;
ALTER TABLE obras ADD COLUMN IF NOT EXISTS synced_at TIMESTAMPTZ;

-- Índice único para deduplicación por Trello
CREATE UNIQUE INDEX IF NOT EXISTS idx_obras_trello_card_id ON obras(trello_card_id) WHERE trello_card_id IS NOT NULL;
