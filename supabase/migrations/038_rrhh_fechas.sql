-- =============================================================================
-- ObrasPlan -- Migracion 038: fecha_inicio / fecha_fin en recursos_humanos
-- =============================================================================
-- CAMBIOS:
--   A) Columnas fecha_inicio y fecha_fin en recursos_humanos
--   B) Backfill: fecha_inicio = 2026-01-01 para todos los existentes
--   C) Indice para filtrado eficiente en el planificador
-- AUDITORIA: audit_articulos cubre la tabla recursos_humanos (trigger existente)
-- =============================================================================

ALTER TABLE recursos_humanos
  ADD COLUMN IF NOT EXISTS fecha_inicio DATE,
  ADD COLUMN IF NOT EXISTS fecha_fin DATE;

-- Backfill: todos los RRHH existentes arrancan el 01/01/2026
UPDATE recursos_humanos
SET fecha_inicio = '2026-01-01'
WHERE fecha_inicio IS NULL;

-- Los nuevos recursos deben tener fecha_inicio por defecto = hoy
ALTER TABLE recursos_humanos
  ALTER COLUMN fecha_inicio SET DEFAULT CURRENT_DATE;

-- Indice para el planificador (filtra por rango de fechas)
CREATE INDEX IF NOT EXISTS idx_rrhh_fechas
  ON recursos_humanos(fecha_inicio, fecha_fin)
  WHERE activo = true;

-- =============================================================================
-- FIN MIGRACION 038
-- =============================================================================
