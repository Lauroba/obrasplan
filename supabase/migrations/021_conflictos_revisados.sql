-- =============================================================================
-- ObrasPlan — Migración 21: Histórico de conflictos revisados
-- Los conflictos no se guardan en BD (se calculan al vuelo desde 'asignaciones').
-- Esta tabla registra qué conflictos (recurso+fecha) ya se han revisado,
-- sin borrar ni modificar nada existente. Es 100% nueva y aditiva.
-- =============================================================================

CREATE TABLE IF NOT EXISTS conflictos_revisados (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  recurso_tipo TEXT NOT NULL,
  recurso_id UUID NOT NULL,
  fecha DATE NOT NULL,
  revisado_por UUID REFERENCES users(id),
  revisado_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_conflictos_revisados_lookup
  ON conflictos_revisados (recurso_tipo, recurso_id, fecha);
