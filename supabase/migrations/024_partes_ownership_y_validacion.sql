-- =============================================================================
-- ObrasPlan — Migración 24: Ownership real en partes_diarios + validar asignación
-- La migración 007 dejó partes_insert/partes_update abiertos a "cualquier
-- autenticado", permitiendo en teoría tocar partes de otro usuario.
-- Esta migración: 1) vuelve a exigir ownership real (excepto admin), y
-- 2) valida en el INSERT que el operario tiene una asignación real para
-- ese recurso+obra+fecha (no solo lo que diga el frontend).
-- =============================================================================

CREATE OR REPLACE FUNCTION tiene_asignacion_en_fecha(p_obra_id UUID, p_fecha DATE)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM asignaciones
    WHERE recurso_tipo = 'humano'
      AND recurso_id = get_user_recurso_id()
      AND obra_id = p_obra_id
      AND fecha_inicio <= p_fecha
      AND fecha_fin >= p_fecha
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

DROP POLICY IF EXISTS "partes_insert" ON partes_diarios;
CREATE POLICY "partes_insert" ON partes_diarios FOR INSERT WITH CHECK (
  get_user_role() = 'admin'
  OR (
    created_by = auth.uid()
    AND (obra_id IS NULL OR tiene_asignacion_en_fecha(obra_id, fecha))
  )
);

DROP POLICY IF EXISTS "partes_update" ON partes_diarios;
CREATE POLICY "partes_update" ON partes_diarios FOR UPDATE USING (
  get_user_role() = 'admin'
  OR (created_by = auth.uid() AND estado IN ('borrador', 'pendiente', 'rechazado'))
);
