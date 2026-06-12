-- =============================================================================
-- ObrasPlan — Migración 17: Notas por día y obra en planificador
-- =============================================================================

CREATE TABLE IF NOT EXISTS planificador_notas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  obra_id UUID NOT NULL REFERENCES obras(id) ON DELETE CASCADE,
  fecha DATE NOT NULL,
  texto TEXT NOT NULL DEFAULT '',
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES auth.users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(obra_id, fecha)
);

ALTER TABLE planificador_notas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notas_select" ON planificador_notas FOR SELECT USING (true);
CREATE POLICY "notas_all" ON planificador_notas FOR ALL USING (auth.role() = 'authenticated');

CREATE INDEX IF NOT EXISTS idx_notas_obra_fecha ON planificador_notas(obra_id, fecha);
