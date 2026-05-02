-- =============================================================================
-- ObrasPlan — Migración 5: Estados personalizables de obra
-- Ejecutar en Supabase SQL Editor
-- =============================================================================

-- 1. Tabla maestro de estados de obra
CREATE TABLE IF NOT EXISTS estados_obra (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre TEXT NOT NULL UNIQUE,
  color TEXT NOT NULL DEFAULT '#6B7280',
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Estados por defecto
INSERT INTO estados_obra (nombre, color) VALUES
  ('Preparación', '#3B82F6'),
  ('Pendiente de planificar', '#F59E0B'),
  ('Planificada', '#8B5CF6'),
  ('En reparo', '#EF4444'),
  ('Terminada', '#22C55E')
ON CONFLICT (nombre) DO NOTHING;

-- 3. Añadir referencia al nuevo estado en obras
ALTER TABLE obras ADD COLUMN IF NOT EXISTS estado_obra_id UUID REFERENCES estados_obra(id) ON DELETE SET NULL;

-- 4. Asignar "Pendiente de planificar" a obras existentes
UPDATE obras SET estado_obra_id = (SELECT id FROM estados_obra WHERE nombre = 'Pendiente de planificar')
WHERE estado_obra_id IS NULL;

-- 5. RLS para estados_obra
ALTER TABLE estados_obra ENABLE ROW LEVEL SECURITY;
CREATE POLICY "estados_obra_select" ON estados_obra FOR SELECT USING (true);
CREATE POLICY "estados_obra_insert" ON estados_obra FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "estados_obra_update" ON estados_obra FOR UPDATE USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "estados_obra_delete" ON estados_obra FOR DELETE USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);
