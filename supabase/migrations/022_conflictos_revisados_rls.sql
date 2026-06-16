-- =============================================================================
-- ObrasPlan — Migración 22: Políticas RLS para conflictos_revisados
-- La tabla se creó sin políticas explícitas y el proyecto tiene RLS activo
-- por defecto en tablas nuevas -> bloqueaba todos los inserts.
-- Mismo patrón que checklists/checklist_items (migración 016).
-- =============================================================================

ALTER TABLE conflictos_revisados ENABLE ROW LEVEL SECURITY;

CREATE POLICY "conflictos_revisados_select" ON conflictos_revisados FOR SELECT USING (true);
CREATE POLICY "conflictos_revisados_all" ON conflictos_revisados FOR ALL USING (auth.role() = 'authenticated');
