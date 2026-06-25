-- =============================================================================
-- ObrasPlan -- Migracion 031: Almacen fase 3
-- Permisos de almacen en rol_permisos + clave de configuracion de alertas
-- =============================================================================

-- Insertar permisos de almacen para todos los roles existentes
-- (admin ya tiene acceso total via is_admin)

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'almacen_articulos', true, true, true, false, false
FROM roles r WHERE r.nombre = 'Jefe de obra'
ON CONFLICT (rol_id, pantalla) DO UPDATE SET visible = true, crear = true, editar = true;

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'almacen_almacenes', true, false, false, false, false
FROM roles r WHERE r.nombre = 'Jefe de obra'
ON CONFLICT (rol_id, pantalla) DO UPDATE SET visible = true;

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'almacen_proveedores', true, false, false, false, false
FROM roles r WHERE r.nombre = 'Jefe de obra'
ON CONFLICT (rol_id, pantalla) DO UPDATE SET visible = true;

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'almacen_movimientos', true, true, false, false, false
FROM roles r WHERE r.nombre = 'Jefe de obra'
ON CONFLICT (rol_id, pantalla) DO UPDATE SET visible = true, crear = true;

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'almacen_articulos', true, false, false, false, false
FROM roles r WHERE r.nombre = 'Encargado'
ON CONFLICT (rol_id, pantalla) DO UPDATE SET visible = true;

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'almacen_movimientos', true, true, false, false, false
FROM roles r WHERE r.nombre = 'Encargado'
ON CONFLICT (rol_id, pantalla) DO UPDATE SET visible = true, crear = true;

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'almacen_articulos', false, false, false, false, false
FROM roles r WHERE r.nombre = 'Operario'
ON CONFLICT (rol_id, pantalla) DO NOTHING;

-- Clave de configuracion de alertas de almacen en app_settings
INSERT INTO app_settings (key, value)
VALUES ('almacen_alertas', '{
  "emails": [],
  "activo": true,
  "frecuencia": "diaria",
  "dias_aviso_caducidad": 30,
  "asunto": "Alertas de almacen - ObrasPlan"
}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- COBERTURA DE AUDITORIA:
-- rol_permisos tiene trigger audit_rol_permisos desde migracion 028.
-- app_settings tiene trigger audit_configuracion desde migracion 026.
-- No se requieren triggers adicionales.

-- =============================================================================
-- FIN MIGRACION 031
-- =============================================================================
