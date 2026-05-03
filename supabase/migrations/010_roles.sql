-- =============================================================================
-- ObrasPlan — Migración 10: Roles con permisos por menú
-- Ejecutar en Supabase SQL Editor
-- =============================================================================

-- 1. Tabla de roles
CREATE TABLE IF NOT EXISTS roles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre TEXT NOT NULL UNIQUE,
  descripcion TEXT,
  is_admin BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "roles_select" ON roles FOR SELECT USING (true);
CREATE POLICY "roles_all" ON roles FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- 2. Tabla de permisos por rol y pantalla
CREATE TABLE IF NOT EXISTS rol_permisos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  rol_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  pantalla TEXT NOT NULL,
  visible BOOLEAN NOT NULL DEFAULT false,
  crear BOOLEAN NOT NULL DEFAULT false,
  editar BOOLEAN NOT NULL DEFAULT false,
  eliminar BOOLEAN NOT NULL DEFAULT false,
  asignar BOOLEAN NOT NULL DEFAULT false,
  UNIQUE(rol_id, pantalla)
);

ALTER TABLE rol_permisos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rol_permisos_select" ON rol_permisos FOR SELECT USING (true);
CREATE POLICY "rol_permisos_all" ON rol_permisos FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- 3. Añadir rol_id a users
ALTER TABLE users ADD COLUMN IF NOT EXISTS rol_id UUID REFERENCES roles(id) ON DELETE SET NULL;

-- 4. Roles por defecto
INSERT INTO roles (nombre, descripcion, is_admin) VALUES
  ('Administrador', 'Acceso total a todas las funcionalidades', true)
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO roles (nombre, descripcion, is_admin) VALUES
  ('Jefe de obra', 'Gestión de obras, partes y planificación', false),
  ('Encargado', 'Partes diarios y consulta de obras', false),
  ('Operario', 'Consulta básica y partes', false)
ON CONFLICT (nombre) DO NOTHING;

-- 5. Permisos para cada rol
-- Admin: todo visible (se gestiona en frontend, is_admin=true)

-- Jefe de obra
INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, p.pantalla, p.visible, p.crear, p.editar, p.eliminar, p.asignar
FROM roles r
CROSS JOIN (VALUES
  ('dashboard', true, false, false, false, false),
  ('planificacion', true, false, false, false, true),
  ('obras', true, true, true, false, false),
  ('partes', true, true, true, false, false),
  ('maestros_rrhh', false, false, false, false, false),
  ('maestros_maquinaria', true, false, false, false, false),
  ('maestros_vehiculos', true, false, false, false, false),
  ('maestros_materiales', true, false, false, false, false),
  ('maestros_clientes', true, false, false, false, false),
  ('maestros_estados', false, false, false, false, false),
  ('maestros_tipos_trabajo', false, false, false, false, false),
  ('logs', false, false, false, false, false),
  ('configuracion', false, false, false, false, false)
) AS p(pantalla, visible, crear, editar, eliminar, asignar)
WHERE r.nombre = 'Jefe de obra'
ON CONFLICT (rol_id, pantalla) DO NOTHING;

-- Encargado
INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, p.pantalla, p.visible, p.crear, p.editar, p.eliminar, p.asignar
FROM roles r
CROSS JOIN (VALUES
  ('dashboard', true, false, false, false, false),
  ('planificacion', true, false, false, false, false),
  ('obras', true, false, false, false, false),
  ('partes', true, true, true, false, false),
  ('maestros_rrhh', false, false, false, false, false),
  ('maestros_maquinaria', false, false, false, false, false),
  ('maestros_vehiculos', false, false, false, false, false),
  ('maestros_materiales', false, false, false, false, false),
  ('maestros_clientes', false, false, false, false, false),
  ('maestros_estados', false, false, false, false, false),
  ('maestros_tipos_trabajo', false, false, false, false, false),
  ('logs', false, false, false, false, false),
  ('configuracion', false, false, false, false, false)
) AS p(pantalla, visible, crear, editar, eliminar, asignar)
WHERE r.nombre = 'Encargado'
ON CONFLICT (rol_id, pantalla) DO NOTHING;

-- Operario
INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, p.pantalla, p.visible, p.crear, p.editar, p.eliminar, p.asignar
FROM roles r
CROSS JOIN (VALUES
  ('dashboard', true, false, false, false, false),
  ('planificacion', true, false, false, false, false),
  ('obras', true, false, false, false, false),
  ('partes', true, true, false, false, false),
  ('maestros_rrhh', false, false, false, false, false),
  ('maestros_maquinaria', false, false, false, false, false),
  ('maestros_vehiculos', false, false, false, false, false),
  ('maestros_materiales', false, false, false, false, false),
  ('maestros_clientes', false, false, false, false, false),
  ('maestros_estados', false, false, false, false, false),
  ('maestros_tipos_trabajo', false, false, false, false, false),
  ('logs', false, false, false, false, false),
  ('configuracion', false, false, false, false, false)
) AS p(pantalla, visible, crear, editar, eliminar, asignar)
WHERE r.nombre = 'Operario'
ON CONFLICT (rol_id, pantalla) DO NOTHING;

-- 6. Asignar rol Admin a los admins existentes
UPDATE users SET rol_id = (SELECT id FROM roles WHERE nombre = 'Administrador')
WHERE role = 'admin' AND rol_id IS NULL;

-- 7. Asignar rol Operario a los demás
UPDATE users SET rol_id = (SELECT id FROM roles WHERE nombre = 'Operario')
WHERE role != 'admin' AND rol_id IS NULL;
