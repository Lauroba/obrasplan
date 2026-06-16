-- =============================================================================
-- ObrasPlan — Migración 20: Añadir columna nif a clientes (faltaba)
-- La migración 019 asumió erróneamente que 'nif' ya existía. Nunca se creó.
-- Esto rompía: PDF de obra, maestro de clientes (crear/editar), informe de clientes.
-- =============================================================================

ALTER TABLE clientes ADD COLUMN IF NOT EXISTS nif TEXT;
