-- =============================================================================
-- ObrasPlan — Migración 2: Soporte para asignaciones día a día y archivo
-- Ejecutar en Supabase SQL Editor
-- =============================================================================

-- 1. Añadir campo "archivada" a obras
ALTER TABLE obras ADD COLUMN IF NOT EXISTS archivada BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_obras_archivada ON obras(archivada);

-- 2. Hacer fecha_inicio y fecha_fin opcionales en obras (se calculan desde asignaciones)
ALTER TABLE obras ALTER COLUMN fecha_inicio DROP NOT NULL;

-- 3. Las asignaciones ya soportan fecha_inicio = fecha_fin (un solo día)
-- No hay cambios de esquema necesarios

-- 4. Función para calcular rango de fechas de una obra desde sus asignaciones
CREATE OR REPLACE FUNCTION get_obra_date_range(p_obra_id UUID)
RETURNS TABLE (min_date DATE, max_date DATE) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    MIN(a.fecha_inicio) as min_date,
    MAX(a.fecha_fin) as max_date
  FROM asignaciones a
  WHERE a.obra_id = p_obra_id;
END;
$$ LANGUAGE plpgsql;
