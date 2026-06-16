-- =============================================================================
-- ObrasPlan — Migración 23: Romper referencia circular RLS asignaciones<->obras
-- La política original de asignaciones_select exigía que la obra fuera
-- visible en 'obras', y la de obras_select (para no-admin) exige que exista
-- una fila visible en 'asignaciones' -> referencia circular. Para admin no
-- falla (tiene atajo directo por rol), pero para el rol 'partes' (operario)
-- puede devolver vacío aunque la asignación exista de verdad.
-- Esta versión consulta directamente recurso_id/rol, sin pasar por 'obras'.
-- =============================================================================

DROP POLICY IF EXISTS "asignaciones_select" ON asignaciones;

CREATE POLICY "asignaciones_select" ON asignaciones FOR SELECT USING (
  get_user_role() IN ('admin', 'lectura')
  OR (recurso_tipo = 'humano' AND recurso_id = get_user_recurso_id())
);
