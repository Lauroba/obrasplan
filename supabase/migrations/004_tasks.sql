-- =============================================================================
-- ObrasPlan — Migración 4: Tareas, tipos de tarea, asignación a fases
-- Ejecutar en Supabase SQL Editor
-- =============================================================================

-- 1. Tabla de tipos de tarea (personalizables)
CREATE TABLE IF NOT EXISTS tipo_tarea (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre TEXT NOT NULL UNIQUE,
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Tipos por defecto
INSERT INTO tipo_tarea (nombre) VALUES 
  ('Compra'), ('Gestión'), ('Revisión'), ('Trámite'), ('Otro')
ON CONFLICT (nombre) DO NOTHING;

-- 2. Tabla de tareas
CREATE TYPE tarea_prioridad AS ENUM ('alta', 'media', 'baja');
CREATE TYPE tarea_estado AS ENUM ('pendiente', 'completada');

CREATE TABLE IF NOT EXISTS tareas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  obra_id UUID NOT NULL REFERENCES obras(id) ON DELETE CASCADE,
  descripcion TEXT NOT NULL,
  tipo_tarea_id UUID REFERENCES tipo_tarea(id) ON DELETE SET NULL,
  prioridad tarea_prioridad NOT NULL DEFAULT 'media',
  estado tarea_estado NOT NULL DEFAULT 'pendiente',
  fecha_limite DATE,
  asignado_a UUID REFERENCES recursos_humanos(id) ON DELETE SET NULL,
  comentario_cierre TEXT,
  completada_at TIMESTAMPTZ,
  completada_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_tareas_obra ON tareas(obra_id);
CREATE INDEX idx_tareas_asignado ON tareas(asignado_a);
CREATE INDEX idx_tareas_estado ON tareas(estado);
CREATE INDEX idx_tareas_fecha ON tareas(fecha_limite);

-- Trigger updated_at
CREATE TRIGGER trg_tareas_updated BEFORE UPDATE ON tareas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Auditoría
CREATE TRIGGER audit_tareas AFTER INSERT OR UPDATE OR DELETE ON tareas
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

-- 3. RLS para tareas
ALTER TABLE tareas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tareas_select" ON tareas FOR SELECT USING (true);
CREATE POLICY "tareas_insert" ON tareas FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin', 'partes'))
);
CREATE POLICY "tareas_update" ON tareas FOR UPDATE USING (true);
CREATE POLICY "tareas_delete" ON tareas FOR DELETE USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- 4. RLS para tipo_tarea
ALTER TABLE tipo_tarea ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tipo_tarea_select" ON tipo_tarea FOR SELECT USING (true);
CREATE POLICY "tipo_tarea_insert" ON tipo_tarea FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "tipo_tarea_update" ON tipo_tarea FOR UPDATE USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- 5. Añadir fase_id a asignaciones si no existe (ya existe pero confirmamos)
-- La columna fase_id ya existe en asignaciones desde la migración 001
