-- =============================================================================
-- ObrasPlan — Migración 25: Visibilidad total de planificación (solo lectura)
-- El operario debe poder VER toda la planificación de todo el equipo, para
-- todos los días, aunque no pueda modificar nada. Esto sustituye y simplifica
-- la política de 'asignaciones_select' de la migración 023 (que solo dejaba
-- ver las asignaciones propias), y elimina del todo la dependencia circular
-- entre 'obras' y 'asignaciones' abriendo la lectura de obras a cualquier
-- usuario autenticado. La escritura sigue restringida a admin (sin cambios:
-- obras_insert/update/delete y asignaciones_insert/update/delete).
-- =============================================================================

DROP POLICY IF EXISTS "obras_select" ON obras;
CREATE POLICY "obras_select" ON obras FOR SELECT USING (true);

DROP POLICY IF EXISTS "asignaciones_select" ON asignaciones;
CREATE POLICY "asignaciones_select" ON asignaciones FOR SELECT USING (true);
