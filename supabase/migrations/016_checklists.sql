-- =============================================================================
-- ObrasPlan — Migración 16: Checklists con progreso para obras
-- =============================================================================

-- Checklists (cada obra puede tener múltiples)
CREATE TABLE IF NOT EXISTS checklists (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  obra_id UUID NOT NULL REFERENCES obras(id) ON DELETE CASCADE,
  titulo TEXT NOT NULL,
  orden INT NOT NULL DEFAULT 0,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Items de checklist
CREATE TABLE IF NOT EXISTS checklist_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  checklist_id UUID NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
  texto TEXT NOT NULL,
  completado BOOLEAN NOT NULL DEFAULT false,
  completado_at TIMESTAMPTZ,
  completado_por UUID REFERENCES auth.users(id),
  asignado_a UUID REFERENCES recursos_humanos(id) ON DELETE SET NULL,
  prioridad TEXT NOT NULL DEFAULT 'media' CHECK (prioridad IN ('alta', 'media', 'baja')),
  orden INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS
ALTER TABLE checklists ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "checklists_select" ON checklists FOR SELECT USING (true);
CREATE POLICY "checklists_all" ON checklists FOR ALL USING (auth.role() = 'authenticated');

CREATE POLICY "checklist_items_select" ON checklist_items FOR SELECT USING (true);
CREATE POLICY "checklist_items_all" ON checklist_items FOR ALL USING (auth.role() = 'authenticated');

-- Indices
CREATE INDEX IF NOT EXISTS idx_checklists_obra ON checklists(obra_id);
CREATE INDEX IF NOT EXISTS idx_checklist_items_checklist ON checklist_items(checklist_id);
CREATE INDEX IF NOT EXISTS idx_checklist_items_asignado ON checklist_items(asignado_a);
