-- =============================================================================
-- ObrasPlan — Migración 45: Re-aplicar RLS de firma de partes (idempotente)
--                            + verificación + diagnóstico
-- =============================================================================
--
-- Contexto: tras aplicar la migración 044, lucian.leyna@gmail.com sigue
-- recibiendo "new row violates row-level security policy for table
-- partes_diarios" al firmar. Ese mensaje es exclusivo de un fallo de
-- WITH CHECK en INSERT/UPDATE (nunca de SELECT/USING), y solo existe una
-- política UPDATE sobre partes_diarios ("partes_update"), así que el fallo
-- está ahí.
--
-- Se ha revisado y descartado:
--   - Recursividad entre users/roles/rol_permisos: sus políticas de SELECT
--     son USING(true) (abiertas), sin obstáculo de RLS para la función.
--   - Otra política UPDATE o restrictiva oculta sobre partes_diarios: no
--     existe ninguna otra.
--   - get_user_role() / enum user_role: correctos.
--
-- Esta migración es 100% idempotente (CREATE OR REPLACE / DROP+CREATE) por
-- si la 044 no llegó a ejecutarse completa, y añade una verificación
-- automática al final para confirmar en el propio SQL Editor que la
-- política queda activa con la definición correcta.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Función de permisos (idéntica a la de la migración 044; CREATE OR
--    REPLACE la deja igual si ya existía, o la crea si no llegó a aplicarse)
-- ---------------------------------------------------------------------------
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
  IF get_user_role() = 'admin' THEN
    RETURN true;
  END IF;

  SELECT rol_id INTO v_rol_id FROM users WHERE id = auth.uid();
  IF v_rol_id IS NULL THEN
    RETURN false;
  END IF;

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
  'Replica usePermissions().canDo(pantalla, accion) del frontend para usarla en políticas RLS. No depende de email ni de nombre de rol.';

-- ---------------------------------------------------------------------------
-- 2) Política partes_update (idéntica a la 044; se vuelve a crear por si
--    no llegó a aplicarse, o para confirmar que queda exactamente así)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 3) Verificación automática: muestra la definición real y activa de la
--    política tras ejecutar este script. Debe aparecer exactamente UNA fila.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_count INT;
  v_qual TEXT;
  v_check TEXT;
BEGIN
  SELECT count(*) INTO v_count FROM pg_policies
    WHERE tablename = 'partes_diarios' AND policyname = 'partes_update';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ERROR DE VERIFICACION: se esperaba exactamente 1 política "partes_update" sobre partes_diarios, se encontraron %', v_count;
  END IF;

  SELECT qual, with_check INTO v_qual, v_check FROM pg_policies
    WHERE tablename = 'partes_diarios' AND policyname = 'partes_update';

  IF v_check IS NULL OR v_check NOT ILIKE '%user_has_permiso%' THEN
    RAISE EXCEPTION 'ERROR DE VERIFICACION: el WITH CHECK activo de "partes_update" no contiene user_has_permiso. Definición actual: %', v_check;
  END IF;

  RAISE NOTICE '✅ Verificación OK: política "partes_update" activa con WITH CHECK correcto.';
  RAISE NOTICE 'USING: %', v_qual;
  RAISE NOTICE 'WITH CHECK: %', v_check;
END $$;

-- =============================================================================
-- DIAGNÓSTICO (ejecutar por separado, es de solo lectura — no modifica nada)
-- =============================================================================
-- Copia y ejecuta esta consulta para confirmar qué resuelve realmente
-- Supabase para un usuario concreto (cambia el email si hace falta):
--
-- SELECT
--   u.email,
--   u.role            AS users_role_legacy,   -- admin/lectura/partes (enum antiguo)
--   u.rol_id,
--   r.nombre          AS rol_nombre,
--   r.is_admin        AS rol_is_admin,
--   rp.pantalla,
--   rp.editar,
--   rp.crear,
--   rp.eliminar
-- FROM users u
-- LEFT JOIN roles r ON r.id = u.rol_id
-- LEFT JOIN rol_permisos rp ON rp.rol_id = u.rol_id AND rp.pantalla = 'partes'
-- WHERE u.email = 'lucian.leyna@gmail.com';
--
-- Resultado esperado para que la firma funcione: rol_nombre = 'Jefe de obra'
-- (o el que corresponda), rol_is_admin = false, y la fila de rol_permisos
-- con pantalla='partes' debe existir con editar = true.
-- Si rol_id es NULL, o no aparece fila de rol_permisos para 'partes', el
-- problema es de configuración del usuario/rol, no de esta política —
-- avísame con el resultado y lo corregimos (sin crear una excepción para
-- este usuario concreto: habría que corregir su rol_id o el rol_permisos
-- del rol que le corresponda).
-- =============================================================================
