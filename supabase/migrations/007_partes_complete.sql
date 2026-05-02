-- =============================================================================
-- ObrasPlan — Migración 7: Módulo de Partes completo
-- Ejecutar en Supabase SQL Editor
-- =============================================================================

-- 1. Maestro de tipos de trabajo
CREATE TABLE IF NOT EXISTS tipos_trabajo (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre TEXT NOT NULL UNIQUE,
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO tipos_trabajo (nombre) VALUES
  ('Junta dilatación'), ('Inyección'), ('Raseo'), ('Chapado'),
  ('Demolición'), ('Impermeabilización'), ('Soldadura'), ('Fontanería'),
  ('Electricidad'), ('Pintura'), ('Albañilería'), ('Desplazamiento'), ('Otro')
ON CONFLICT (nombre) DO NOTHING;

ALTER TABLE tipos_trabajo ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tipos_trabajo_select" ON tipos_trabajo FOR SELECT USING (true);
CREATE POLICY "tipos_trabajo_insert" ON tipos_trabajo FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "tipos_trabajo_update" ON tipos_trabajo FOR UPDATE USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- 2. Actualizar partes_diarios
ALTER TABLE partes_diarios ADD COLUMN IF NOT EXISTS firma_cliente TEXT;
ALTER TABLE partes_diarios ADD COLUMN IF NOT EXISTS jefe_obra TEXT;
ALTER TABLE partes_diarios ADD COLUMN IF NOT EXISTS encargado_obra TEXT;
ALTER TABLE partes_diarios ADD COLUMN IF NOT EXISTS responsable_empresa TEXT;
ALTER TABLE partes_diarios ADD COLUMN IF NOT EXISTS direccion TEXT;
ALTER TABLE partes_diarios ADD COLUMN IF NOT EXISTS localidad TEXT;
ALTER TABLE partes_diarios ADD COLUMN IF NOT EXISTS provincia TEXT;
ALTER TABLE partes_diarios ALTER COLUMN obra_id DROP NOT NULL;

-- 3. Añadir estado 'firmado'
ALTER TYPE parte_estado ADD VALUE IF NOT EXISTS 'firmado';

-- 4. Tabla de líneas del parte (conceptos de trabajo)
CREATE TABLE IF NOT EXISTS parte_lineas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  parte_id UUID NOT NULL REFERENCES partes_diarios(id) ON DELETE CASCADE,
  orden INTEGER NOT NULL DEFAULT 0,
  concepto TEXT NOT NULL,
  tipo_trabajo_id UUID REFERENCES tipos_trabajo(id) ON DELETE SET NULL,
  fabricante TEXT,
  producto TEXT,
  unidades TEXT,
  cantidad NUMERIC,
  observaciones TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE parte_lineas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "parte_lineas_select" ON parte_lineas FOR SELECT USING (true);
CREATE POLICY "parte_lineas_write" ON parte_lineas FOR ALL USING (auth.role() = 'authenticated');

-- 5. Tabla de audios
CREATE TABLE IF NOT EXISTS parte_audios (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  parte_id UUID NOT NULL REFERENCES partes_diarios(id) ON DELETE CASCADE,
  nombre_archivo TEXT NOT NULL,
  storage_path TEXT NOT NULL,
  duracion INTEGER,
  tamano BIGINT,
  uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE parte_audios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "parte_audios_select" ON parte_audios FOR SELECT USING (true);
CREATE POLICY "parte_audios_write" ON parte_audios FOR ALL USING (auth.role() = 'authenticated');

-- 6. Bucket de audios
INSERT INTO storage.buckets (id, name, public) VALUES ('audios', 'audios', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 7. Quitar constraint unique si existe
ALTER TABLE partes_diarios DROP CONSTRAINT IF EXISTS unique_parte_obra_fecha_user;

-- 8. RLS actualizar partes para permitir insert a todos los autenticados
DROP POLICY IF EXISTS "partes_insert" ON partes_diarios;
CREATE POLICY "partes_insert" ON partes_diarios FOR INSERT WITH CHECK (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "partes_update" ON partes_diarios;
CREATE POLICY "partes_update" ON partes_diarios FOR UPDATE USING (auth.role() = 'authenticated');
