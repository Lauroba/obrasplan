-- =============================================================================
-- ObrasPlan -- Diagnostico y corrección de usuarios/roles/permisos
-- Ejecutar en Supabase SQL Editor
-- =============================================================================

-- =============================================================================
-- 1. DIAGNÓSTICO: estado de sergio.leina@gmail.com
-- =============================================================================

SELECT
  u.id,
  u.email,
  u.nombre,
  u.role          AS role_campo_texto,
  u.activo,
  r.nombre        AS rol_nombre,
  r.is_admin      AS rol_es_admin,
  u.rol_id
FROM users u
LEFT JOIN roles r ON r.id = u.rol_id
WHERE u.email ILIKE 'sergio%'
   OR u.email ILIKE '%leina%'
   OR u.email ILIKE '%leyna%';


-- =============================================================================
-- 2. DIAGNÓSTICO: todos los usuarios con rol admin pero sin role="admin"
-- =============================================================================

SELECT
  u.id,
  u.email,
  u.nombre,
  u.role          AS role_campo_texto,
  r.nombre        AS rol_nombre,
  r.is_admin
FROM users u
JOIN roles r ON r.id = u.rol_id
WHERE r.is_admin = true
  AND u.role <> 'admin';


-- =============================================================================
-- 3. CORRECCIÓN: sincronizar users.role para todos los usuarios
--    cuyo rol tiene is_admin = true
-- =============================================================================

UPDATE users
SET role = 'admin'
WHERE rol_id IN (
  SELECT id FROM roles WHERE is_admin = true
)
AND role <> 'admin';

-- Verificar resultado:
SELECT email, role, rol_id FROM users
WHERE rol_id IN (SELECT id FROM roles WHERE is_admin = true);


-- =============================================================================
-- 4. DIAGNÓSTICO: pantallas en rol_permisos para el rol admin
--    (si is_admin=true el sistema debería hacer bypass, pero revisamos igualmente)
-- =============================================================================

SELECT
  r.nombre  AS rol,
  r.is_admin,
  COUNT(rp.pantalla) AS num_permisos,
  STRING_AGG(rp.pantalla, ', ' ORDER BY rp.pantalla) AS pantallas
FROM roles r
LEFT JOIN rol_permisos rp ON rp.rol_id = r.id
GROUP BY r.id, r.nombre, r.is_admin
ORDER BY r.is_admin DESC, r.nombre;


-- =============================================================================
-- 5. DIAGNÓSTICO: verificar usuarios sin perfil en tabla users
--    (existentes en recursos_humanos pero sin registro en users)
-- =============================================================================

SELECT
  rh.nombre,
  rh.email,
  rh.activo
FROM recursos_humanos rh
WHERE rh.email IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM users u WHERE u.recurso_id = rh.id
  );


-- =============================================================================
-- 6. REGISTRO EN AUDIT_LOG de esta corrección
-- =============================================================================

INSERT INTO audit_log (accion, entidad, modulo, descripcion, resultado, origen)
VALUES (
  'editar',
  'users',
  'usuarios',
  'Sincronización masiva: campo role actualizado a "admin" para todos los usuarios con rol is_admin=true',
  'exito',
  'rpc_manual'
);

-- =============================================================================
-- FIN
-- =============================================================================
