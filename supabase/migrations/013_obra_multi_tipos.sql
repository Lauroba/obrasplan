-- =============================================================================
-- ObrasPlan — Migración 13: Obra puede tener múltiples tipos
-- =============================================================================

CREATE TABLE IF NOT EXISTS obra_tipos_obra (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  obra_id UUID NOT NULL REFERENCES obras(id) ON DELETE CASCADE,
  tipo_obra_id UUID NOT NULL REFERENCES tipos_obra(id) ON DELETE CASCADE,
  UNIQUE(obra_id, tipo_obra_id)
);

ALTER TABLE obra_tipos_obra ENABLE ROW LEVEL SECURITY;
CREATE POLICY "obra_tipos_select" ON obra_tipos_obra FOR SELECT USING (true);
CREATE POLICY "obra_tipos_all" ON obra_tipos_obra FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- Migrar datos existentes del campo tipo_obra_id a la tabla intermedia
INSERT INTO obra_tipos_obra (obra_id, tipo_obra_id)
SELECT id, tipo_obra_id FROM obras WHERE tipo_obra_id IS NOT NULL
ON CONFLICT (obra_id, tipo_obra_id) DO NOTHING;
