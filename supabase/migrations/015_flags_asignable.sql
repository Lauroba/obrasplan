-- =============================================================================
-- ObrasPlan — Migración 15: Flags asignable, obras especiales, responsable
-- =============================================================================

-- 1. Flag "asignable" en recursos (default true)
ALTER TABLE recursos_humanos ADD COLUMN IF NOT EXISTS asignable BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE vehiculos ADD COLUMN IF NOT EXISTS asignable BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE maquinaria ADD COLUMN IF NOT EXISTS asignable BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE materiales ADD COLUMN IF NOT EXISTS asignable BOOLEAN NOT NULL DEFAULT true;

-- 2. Flags especiales en obras
ALTER TABLE obras ADD COLUMN IF NOT EXISTS flag_rrhh_sin_asignar BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE obras ADD COLUMN IF NOT EXISTS flag_vehiculo_sin_asignar BOOLEAN NOT NULL DEFAULT false;

-- 3. Responsable de obra
ALTER TABLE obras ADD COLUMN IF NOT EXISTS responsable_obra_id UUID REFERENCES recursos_humanos(id) ON DELETE SET NULL;
