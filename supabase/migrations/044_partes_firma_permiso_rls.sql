-- =============================================================================
-- ObrasPlan — Migración 44: RLS de partes_diarios alineada con el sistema de
-- permisos (rol_permisos), no solo con "admin" o "creador del parte"
-- =============================================================================
--
-- CAUSA DEL BUG REPORTADO
-- ------------------------
-- lucian.leyna@gmail.com (rol "Jefe de obra", con permiso "editar" = true en
-- la pantalla "partes") no podía firmar partes que él no había creado.
--
-- La política "partes_update" (migración 024) solo permitía la escritura a:
--   get_user_role() = 'admin'  OR  created_by = auth.uid()
-- Esto ignora por completo rol_permisos / lo que el frontend calcula con
-- usePermissions().canDo("partes","editar"). Un Jefe de obra con permiso de
-- edición explícito, pero que no es el creador del parte, quedaba bloqueado
-- por RLS: la escritura UPDATE afectaba 0 filas (RLS no lanza error, filtra
-- la fila en silencio), y el frontend no comprobaba el resultado -> fallo
-- totalmente silencioso (el parte se quedaba en "Pendiente").
--
-- FIX
-- ---
-- 1) Nueva función user_has_permiso(pantalla, accion), reutilizable desde
--    cualquier política RLS, que replica exactamente la lógica de
--    usePermissions().canDo() en el frontend: admin -> true; rol.is_admin
--    -> true; si no, columna correspondiente de rol_permisos para esa
--    pantalla. Ningún rol ni email está hardcodeado.
-- 2) "partes_update" pasa a permitir la escritura cuando:
--      admin
--      OR (estado en borrador/pendiente/rechazado Y (creador del parte
--          OR user_has_permiso('partes','editar')))
--    Se mantiene la vía de "creador" para que un Operario (que solo tiene
--    "crear" en partes, no "editar") pueda seguir completando su propio
--    borrador, exactamente igual que antes. Se AÑADE la vía por permiso
--    explícito para que cualquier usuario con "editar" en Partes —
--    cualquiera que sea su rol— pueda firmar partes de otros.
--    No se amplía nada para roles de solo lectura (visible=true,
--    crear/editar/eliminar=false): user_has_permiso devuelve false y, si
--    tampoco son el creador, siguen bloqueados.
-- =============================================================================

CREATE OR REPLACE FUNCTION user_has_permiso(p_pantalla TEXT, p_accion TEXT)
RETURNS BOOLEAN AS $$
DECLARE
  v_rol_id UUID;
  v_is_admin BOOLEAN;
  v_visible BOOLEAN;
  v_crear BOOLEAN;
  v_editar BOOLEAN;
  v_eliminar BOOLEAN;
  v_asignar BOOLEAN;
BEGIN
  -- Mismo criterio que isAdmin en el frontend: users.role = 'admin' ...
  IF get_user_role() = 'admin' THEN
    RETURN true;
  END IF;

  SELECT rol_id INTO v_rol_id FROM users WHERE id = auth.uid();
  IF v_rol_id IS NULL THEN
    RETURN false;
  END IF;

  -- ... o rol vinculado con is_admin = true
  SELECT is_admin INTO v_is_admin FROM roles WHERE id = v_rol_id;
  IF v_is_admin THEN
    RETURN true;
  END IF;

  SELECT visible, crear, editar, eliminar, asignar
    INTO v_visible, v_crear, v_editar, v_eliminar, v_asignar
    FROM rol_permisos WHERE rol_id = v_rol_id AND pantalla = p_pantalla;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  RETURN CASE p_accion
    WHEN 'visible'  THEN v_visible
    WHEN 'crear'    THEN v_crear
    WHEN 'editar'   THEN v_editar
    WHEN 'eliminar' THEN v_eliminar
    WHEN 'asignar'  THEN v_asignar
    ELSE false
  END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

COMMENT ON FUNCTION user_has_permiso(TEXT, TEXT) IS
  'Replica usePermissions().canDo(pantalla, accion) del frontend para usarla en políticas RLS. No depende de email ni de nombre de rol, solo de rol_permisos / roles.is_admin / users.role.';

-- CAUSA ADICIONAL (más profunda) DEL MISMO BUG
-- ---------------------------------------------
-- La política original (migración 024) NO definía WITH CHECK explícito.
-- En PostgreSQL, si una política UPDATE omite WITH CHECK, se reutiliza la
-- misma expresión de USING también para validar la FILA RESULTANTE tras el
-- update. Como USING exigía "estado IN ('borrador','pendiente','rechazado')",
-- esa misma condición se aplicaba también al NUEVO valor de estado — y como
-- firmar pone estado='firmado', la fila resultante SIEMPRE incumplía esa
-- condición. Resultado: NINGÚN usuario no-admin ha podido firmar nunca un
-- parte por esta vía (ni siquiera el propio creador), independientemente de
-- sus permisos — coincide exactamente con "funciona para admin, nunca para
-- nadie más" del bug reportado. Esta migración separa USING (qué filas se
-- pueden tocar: deben estar en un estado editable) de WITH CHECK (quién
-- puede dejar la fila así: dueño o con permiso "editar" en Partes), sin
-- volver a exigir el estado antiguo sobre la fila nueva.

DROP POLICY IF EXISTS "partes_update" ON partes_diarios;
CREATE POLICY "partes_update" ON partes_diarios FOR UPDATE
  USING (
    get_user_role() = 'admin'
    OR (
      estado IN ('borrador', 'pendiente', 'rechazado')
      AND (created_by = auth.uid() OR user_has_permiso('partes', 'editar'))
    )
  )
  WITH CHECK (
    get_user_role() = 'admin'
    OR created_by = auth.uid()
    OR user_has_permiso('partes', 'editar')
  );
