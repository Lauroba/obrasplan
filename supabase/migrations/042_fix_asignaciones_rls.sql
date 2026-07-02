-- =============================================================================
-- ObrasPlan -- Migración 042: Ampliar RLS de asignaciones para el planificador
-- =============================================================================
-- PROBLEMA: asignaciones_insert solo permitía a 'admin' insertar asignaciones.
-- Cualquier usuario con rol distinto (encargado, jefe de obra, partes) no
-- podía arrastrar recursos en el planificador ni usar el botón +.
-- El INSERT fallaba silenciosamente (RLS devuelve 0 filas, no error visible).
--
-- SOLUCIÓN: permitir INSERT y DELETE a todos los usuarios autenticados.
-- El planificador es una herramienta operativa que todos los roles usan.
-- El SELECT ya era público (true) desde la migración 025.
-- =============================================================================

-- INSERT: cualquier usuario autenticado puede crear asignaciones
DROP POLICY IF EXISTS "asignaciones_insert" ON asignaciones;
CREATE POLICY "asignaciones_insert" ON asignaciones
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- UPDATE: cualquier usuario autenticado puede actualizar asignaciones
DROP POLICY IF EXISTS "asignaciones_update" ON asignaciones;
CREATE POLICY "asignaciones_update" ON asignaciones
  FOR UPDATE USING (auth.role() = 'authenticated');

-- DELETE: cualquier usuario autenticado puede eliminar asignaciones
-- (necesario para arrastrar recursos a SIN ASIGNAR = eliminar)
DROP POLICY IF EXISTS "asignaciones_delete" ON asignaciones;
CREATE POLICY "asignaciones_delete" ON asignaciones
  FOR DELETE USING (auth.role() = 'authenticated');

-- Verificar políticas resultantes
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'asignaciones'
ORDER BY policyname;

-- =============================================================================
-- FIN MIGRACIÓN 042
-- =============================================================================
