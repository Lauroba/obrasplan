-- =============================================================================
-- ObrasPlan — Migración 9: Permisos por pantalla
-- Ejecutar en Supabase SQL Editor
-- =============================================================================

-- Tabla de permisos por usuario
CREATE TABLE IF NOT EXISTS user_permisos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  pantalla TEXT NOT NULL,
  ver BOOLEAN NOT NULL DEFAULT false,
  crear BOOLEAN NOT NULL DEFAULT false,
  editar BOOLEAN NOT NULL DEFAULT false,
  eliminar BOOLEAN NOT NULL DEFAULT false,
  asignar BOOLEAN NOT NULL DEFAULT false,
  UNIQUE(user_id, pantalla)
);

ALTER TABLE user_permisos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "permisos_select" ON user_permisos FOR SELECT USING (true);
CREATE POLICY "permisos_insert" ON user_permisos FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "permisos_update" ON user_permisos FOR UPDATE USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "permisos_delete" ON user_permisos FOR DELETE USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- Insertar permisos por defecto para usuarios existentes (estándar = todo activo)
INSERT INTO user_permisos (user_id, pantalla, ver, crear, editar, eliminar, asignar)
SELECT u.id, p.pantalla, true, true, true, true, true
FROM users u
CROSS JOIN (VALUES ('planificacion'), ('obras'), ('partes'), ('maestros'), ('tareas'), ('logs'), ('configuracion')) AS p(pantalla)
WHERE u.role != 'admin'
ON CONFLICT (user_id, pantalla) DO NOTHING;
