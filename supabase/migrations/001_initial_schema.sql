-- =============================================================================
-- ObrasPlan — Migración inicial completa
-- Base de datos para gestión y planificación de obras
-- =============================================================================

-- Extensiones necesarias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- ENUMS
-- =============================================================================

CREATE TYPE user_role AS ENUM ('admin', 'lectura', 'partes');
CREATE TYPE obra_estado AS ENUM ('planificada', 'en_curso', 'pausada', 'finalizada', 'cerrada');
CREATE TYPE fase_estado AS ENUM ('pendiente', 'en_curso', 'completada');
CREATE TYPE recurso_tipo AS ENUM ('humano', 'maquinaria', 'vehiculo', 'material');
CREATE TYPE parte_estado AS ENUM ('borrador', 'pendiente', 'aprobado', 'rechazado');
CREATE TYPE documento_tipo AS ENUM ('foto', 'pdf', 'documento');
CREATE TYPE documento_categoria AS ENUM ('antes', 'durante', 'despues', 'general');
CREATE TYPE recurso_estado AS ENUM ('disponible', 'en_uso', 'mantenimiento', 'baja');
CREATE TYPE audit_accion AS ENUM ('crear', 'editar', 'eliminar', 'aprobar', 'rechazar', 'login', 'logout');

-- =============================================================================
-- TABLA: clientes
-- =============================================================================

CREATE TABLE clientes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre TEXT NOT NULL,
  contacto TEXT,
  telefono TEXT,
  email TEXT,
  direccion TEXT,
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- TABLA: recursos_humanos
-- =============================================================================

CREATE TABLE recursos_humanos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre TEXT NOT NULL,
  perfil TEXT,
  telefono TEXT,
  email TEXT,
  observaciones TEXT,
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- TABLA: maquinaria
-- =============================================================================

CREATE TABLE maquinaria (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre TEXT NOT NULL,
  tipo TEXT,
  estado recurso_estado NOT NULL DEFAULT 'disponible',
  observaciones TEXT,
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- TABLA: vehiculos
-- =============================================================================

CREATE TABLE vehiculos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre TEXT NOT NULL,
  matricula TEXT,
  tipo TEXT,
  estado recurso_estado NOT NULL DEFAULT 'disponible',
  observaciones TEXT,
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- TABLA: materiales
-- =============================================================================

CREATE TABLE materiales (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre TEXT NOT NULL,
  tipo TEXT,
  unidad TEXT,
  observaciones TEXT,
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- TABLA: users (perfil extendido de auth.users)
-- =============================================================================

CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  nombre TEXT NOT NULL,
  role user_role NOT NULL DEFAULT 'partes',
  recurso_id UUID REFERENCES recursos_humanos(id) ON DELETE SET NULL,
  avatar_url TEXT,
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- TABLA: obras
-- =============================================================================

CREATE TABLE obras (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre TEXT NOT NULL,
  cliente_id UUID REFERENCES clientes(id) ON DELETE SET NULL,
  ubicacion TEXT,
  fecha_inicio DATE NOT NULL,
  fecha_fin DATE,
  estado obra_estado NOT NULL DEFAULT 'planificada',
  fase_actual TEXT,
  observaciones TEXT,
  color TEXT DEFAULT '#DC2626',
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- TABLA: obra_fases
-- =============================================================================

CREATE TABLE obra_fases (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  obra_id UUID NOT NULL REFERENCES obras(id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  fecha_inicio DATE,
  fecha_fin DATE,
  estado fase_estado NOT NULL DEFAULT 'pendiente',
  orden INTEGER NOT NULL DEFAULT 0,
  observaciones TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- TABLA: asignaciones (polimórfica — cubre humanos, maquinaria, vehículos, materiales)
-- =============================================================================

CREATE TABLE asignaciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  obra_id UUID NOT NULL REFERENCES obras(id) ON DELETE CASCADE,
  fase_id UUID REFERENCES obra_fases(id) ON DELETE SET NULL,
  recurso_tipo recurso_tipo NOT NULL,
  recurso_id UUID NOT NULL,
  fecha_inicio DATE NOT NULL,
  fecha_fin DATE NOT NULL,
  cantidad NUMERIC,
  unidad TEXT,
  observaciones TEXT,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  CONSTRAINT check_fechas CHECK (fecha_fin >= fecha_inicio)
);

-- =============================================================================
-- TABLA: partes_diarios
-- =============================================================================

CREATE TABLE partes_diarios (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  obra_id UUID NOT NULL REFERENCES obras(id) ON DELETE CASCADE,
  fecha DATE NOT NULL,
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  descripcion TEXT,
  incidencias TEXT,
  observaciones TEXT,
  estado parte_estado NOT NULL DEFAULT 'borrador',
  firma_data TEXT,
  aprobado_by UUID REFERENCES users(id) ON DELETE SET NULL,
  aprobado_at TIMESTAMPTZ,
  motivo_rechazo TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  CONSTRAINT unique_parte_obra_fecha_user UNIQUE (obra_id, fecha, created_by)
);

-- =============================================================================
-- TABLAS: detalle de partes diarios
-- =============================================================================

CREATE TABLE parte_trabajadores (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  parte_id UUID NOT NULL REFERENCES partes_diarios(id) ON DELETE CASCADE,
  recurso_id UUID NOT NULL REFERENCES recursos_humanos(id) ON DELETE CASCADE,
  hora_entrada TIME,
  hora_salida TIME,
  observaciones TEXT
);

CREATE TABLE parte_maquinaria (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  parte_id UUID NOT NULL REFERENCES partes_diarios(id) ON DELETE CASCADE,
  maquinaria_id UUID NOT NULL REFERENCES maquinaria(id) ON DELETE CASCADE,
  observaciones TEXT
);

CREATE TABLE parte_vehiculos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  parte_id UUID NOT NULL REFERENCES partes_diarios(id) ON DELETE CASCADE,
  vehiculo_id UUID NOT NULL REFERENCES vehiculos(id) ON DELETE CASCADE,
  observaciones TEXT
);

CREATE TABLE parte_materiales (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  parte_id UUID NOT NULL REFERENCES partes_diarios(id) ON DELETE CASCADE,
  material_id UUID NOT NULL REFERENCES materiales(id) ON DELETE CASCADE,
  cantidad NUMERIC NOT NULL,
  unidad TEXT,
  observaciones TEXT
);

-- =============================================================================
-- TABLA: documentos (fotos, PDFs, archivos)
-- =============================================================================

CREATE TABLE documentos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  obra_id UUID NOT NULL REFERENCES obras(id) ON DELETE CASCADE,
  parte_id UUID REFERENCES partes_diarios(id) ON DELETE SET NULL,
  nombre_archivo TEXT NOT NULL,
  tipo documento_tipo NOT NULL DEFAULT 'documento',
  categoria documento_categoria NOT NULL DEFAULT 'general',
  storage_path TEXT NOT NULL,
  tamano BIGINT,
  mime_type TEXT,
  uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- TABLA: audit_log
-- =============================================================================

CREATE TABLE audit_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  accion audit_accion NOT NULL,
  entidad TEXT NOT NULL,
  entidad_id UUID,
  valor_anterior JSONB,
  valor_nuevo JSONB,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- TABLA: configuracion
-- =============================================================================

CREATE TABLE configuracion (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  clave TEXT NOT NULL UNIQUE,
  valor JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- ÍNDICES
-- =============================================================================

-- Asignaciones
CREATE INDEX idx_asignaciones_obra ON asignaciones(obra_id);
CREATE INDEX idx_asignaciones_recurso ON asignaciones(recurso_tipo, recurso_id);
CREATE INDEX idx_asignaciones_fechas ON asignaciones(fecha_inicio, fecha_fin);
CREATE INDEX idx_asignaciones_conflicto ON asignaciones(recurso_tipo, recurso_id, fecha_inicio, fecha_fin);

-- Obras
CREATE INDEX idx_obras_estado ON obras(estado);
CREATE INDEX idx_obras_fechas ON obras(fecha_inicio, fecha_fin);
CREATE INDEX idx_obras_cliente ON obras(cliente_id);

-- Fases
CREATE INDEX idx_fases_obra ON obra_fases(obra_id);

-- Partes
CREATE INDEX idx_partes_obra_fecha ON partes_diarios(obra_id, fecha);
CREATE INDEX idx_partes_estado ON partes_diarios(estado);
CREATE INDEX idx_partes_created_by ON partes_diarios(created_by);

-- Documentos
CREATE INDEX idx_docs_obra ON documentos(obra_id);
CREATE INDEX idx_docs_parte ON documentos(parte_id);

-- Auditoría
CREATE INDEX idx_audit_user ON audit_log(user_id, created_at);
CREATE INDEX idx_audit_entidad ON audit_log(entidad, entidad_id);
CREATE INDEX idx_audit_created ON audit_log(created_at);

-- Users
CREATE INDEX idx_users_recurso ON users(recurso_id);
CREATE INDEX idx_users_role ON users(role);

-- =============================================================================
-- FUNCIONES Y TRIGGERS
-- =============================================================================

-- Función para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Aplicar trigger de updated_at a todas las tablas relevantes
CREATE TRIGGER trg_clientes_updated BEFORE UPDATE ON clientes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_rrhh_updated BEFORE UPDATE ON recursos_humanos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_maquinaria_updated BEFORE UPDATE ON maquinaria
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_vehiculos_updated BEFORE UPDATE ON vehiculos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_materiales_updated BEFORE UPDATE ON materiales
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_obras_updated BEFORE UPDATE ON obras
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_fases_updated BEFORE UPDATE ON obra_fases
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_asignaciones_updated BEFORE UPDATE ON asignaciones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_partes_updated BEFORE UPDATE ON partes_diarios
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Función para registrar auditoría
CREATE OR REPLACE FUNCTION audit_log_trigger()
RETURNS TRIGGER AS $$
DECLARE
  _user_id UUID;
  _accion audit_accion;
BEGIN
  -- Obtener user_id del contexto JWT de Supabase
  _user_id := COALESCE(
    (current_setting('request.jwt.claims', true)::json ->> 'sub')::uuid,
    NULL
  );

  IF TG_OP = 'INSERT' THEN
    _accion := 'crear';
    INSERT INTO audit_log (user_id, accion, entidad, entidad_id, valor_nuevo)
    VALUES (_user_id, _accion, TG_TABLE_NAME, NEW.id, to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    _accion := 'editar';
    INSERT INTO audit_log (user_id, accion, entidad, entidad_id, valor_anterior, valor_nuevo)
    VALUES (_user_id, _accion, TG_TABLE_NAME, NEW.id, to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    _accion := 'eliminar';
    INSERT INTO audit_log (user_id, accion, entidad, entidad_id, valor_anterior)
    VALUES (_user_id, _accion, TG_TABLE_NAME, OLD.id, to_jsonb(OLD));
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Aplicar auditoría a tablas principales
CREATE TRIGGER audit_obras AFTER INSERT OR UPDATE OR DELETE ON obras
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();
CREATE TRIGGER audit_asignaciones AFTER INSERT OR UPDATE OR DELETE ON asignaciones
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();
CREATE TRIGGER audit_partes AFTER INSERT OR UPDATE OR DELETE ON partes_diarios
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();
CREATE TRIGGER audit_clientes AFTER INSERT OR UPDATE OR DELETE ON clientes
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();
CREATE TRIGGER audit_rrhh AFTER INSERT OR UPDATE OR DELETE ON recursos_humanos
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();
CREATE TRIGGER audit_maquinaria AFTER INSERT OR UPDATE OR DELETE ON maquinaria
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();
CREATE TRIGGER audit_vehiculos AFTER INSERT OR UPDATE OR DELETE ON vehiculos
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();
CREATE TRIGGER audit_materiales AFTER INSERT OR UPDATE OR DELETE ON materiales
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

-- =============================================================================
-- FUNCIÓN: Detectar conflictos de asignación
-- =============================================================================

CREATE OR REPLACE FUNCTION check_asignacion_conflictos(
  p_recurso_tipo recurso_tipo,
  p_recurso_id UUID,
  p_fecha_inicio DATE,
  p_fecha_fin DATE,
  p_exclude_id UUID DEFAULT NULL
)
RETURNS TABLE (
  conflicto_id UUID,
  obra_id UUID,
  obra_nombre TEXT,
  fecha_inicio DATE,
  fecha_fin DATE
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    a.id AS conflicto_id,
    a.obra_id,
    o.nombre AS obra_nombre,
    a.fecha_inicio,
    a.fecha_fin
  FROM asignaciones a
  JOIN obras o ON o.id = a.obra_id
  WHERE a.recurso_tipo = p_recurso_tipo
    AND a.recurso_id = p_recurso_id
    AND a.fecha_inicio <= p_fecha_fin
    AND a.fecha_fin >= p_fecha_inicio
    AND (p_exclude_id IS NULL OR a.id != p_exclude_id);
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- ROW LEVEL SECURITY (RLS)
-- =============================================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE obras ENABLE ROW LEVEL SECURITY;
ALTER TABLE obra_fases ENABLE ROW LEVEL SECURITY;
ALTER TABLE asignaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE recursos_humanos ENABLE ROW LEVEL SECURITY;
ALTER TABLE maquinaria ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehiculos ENABLE ROW LEVEL SECURITY;
ALTER TABLE materiales ENABLE ROW LEVEL SECURITY;
ALTER TABLE partes_diarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE parte_trabajadores ENABLE ROW LEVEL SECURITY;
ALTER TABLE parte_maquinaria ENABLE ROW LEVEL SECURITY;
ALTER TABLE parte_vehiculos ENABLE ROW LEVEL SECURITY;
ALTER TABLE parte_materiales ENABLE ROW LEVEL SECURITY;
ALTER TABLE documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE configuracion ENABLE ROW LEVEL SECURITY;

-- Helper: obtener el role del usuario autenticado
CREATE OR REPLACE FUNCTION get_user_role()
RETURNS user_role AS $$
BEGIN
  RETURN (
    SELECT role FROM users WHERE id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Helper: obtener el recurso_id del usuario autenticado
CREATE OR REPLACE FUNCTION get_user_recurso_id()
RETURNS UUID AS $$
BEGIN
  RETURN (
    SELECT recurso_id FROM users WHERE id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ---- USERS ----
CREATE POLICY "users_select" ON users FOR SELECT USING (true);
CREATE POLICY "users_insert" ON users FOR INSERT WITH CHECK (get_user_role() = 'admin');
CREATE POLICY "users_update" ON users FOR UPDATE USING (
  id = auth.uid() OR get_user_role() = 'admin'
);
CREATE POLICY "users_delete" ON users FOR DELETE USING (get_user_role() = 'admin');

-- ---- OBRAS ----
CREATE POLICY "obras_select" ON obras FOR SELECT USING (
  get_user_role() IN ('admin', 'lectura')
  OR id IN (
    SELECT obra_id FROM asignaciones
    WHERE recurso_tipo = 'humano' AND recurso_id = get_user_recurso_id()
  )
);
CREATE POLICY "obras_insert" ON obras FOR INSERT WITH CHECK (get_user_role() = 'admin');
CREATE POLICY "obras_update" ON obras FOR UPDATE USING (get_user_role() = 'admin');
CREATE POLICY "obras_delete" ON obras FOR DELETE USING (get_user_role() = 'admin');

-- ---- FASES ----
CREATE POLICY "fases_select" ON obra_fases FOR SELECT USING (
  obra_id IN (SELECT id FROM obras)  -- hereda visibilidad de obras
);
CREATE POLICY "fases_insert" ON obra_fases FOR INSERT WITH CHECK (get_user_role() = 'admin');
CREATE POLICY "fases_update" ON obra_fases FOR UPDATE USING (get_user_role() = 'admin');
CREATE POLICY "fases_delete" ON obra_fases FOR DELETE USING (get_user_role() = 'admin');

-- ---- ASIGNACIONES ----
CREATE POLICY "asignaciones_select" ON asignaciones FOR SELECT USING (
  obra_id IN (SELECT id FROM obras)
);
CREATE POLICY "asignaciones_insert" ON asignaciones FOR INSERT WITH CHECK (get_user_role() = 'admin');
CREATE POLICY "asignaciones_update" ON asignaciones FOR UPDATE USING (get_user_role() = 'admin');
CREATE POLICY "asignaciones_delete" ON asignaciones FOR DELETE USING (get_user_role() = 'admin');

-- ---- MAESTROS (todos: select para todos, write para admin) ----
CREATE POLICY "clientes_select" ON clientes FOR SELECT USING (true);
CREATE POLICY "clientes_write" ON clientes FOR ALL USING (get_user_role() = 'admin');

CREATE POLICY "rrhh_select" ON recursos_humanos FOR SELECT USING (true);
CREATE POLICY "rrhh_write" ON recursos_humanos FOR ALL USING (get_user_role() = 'admin');

CREATE POLICY "maquinaria_select" ON maquinaria FOR SELECT USING (true);
CREATE POLICY "maquinaria_write" ON maquinaria FOR ALL USING (get_user_role() = 'admin');

CREATE POLICY "vehiculos_select" ON vehiculos FOR SELECT USING (true);
CREATE POLICY "vehiculos_write" ON vehiculos FOR ALL USING (get_user_role() = 'admin');

CREATE POLICY "materiales_select" ON materiales FOR SELECT USING (true);
CREATE POLICY "materiales_write" ON materiales FOR ALL USING (get_user_role() = 'admin');

-- ---- PARTES DIARIOS ----
CREATE POLICY "partes_select" ON partes_diarios FOR SELECT USING (
  get_user_role() = 'admin'
  OR created_by = auth.uid()
);
CREATE POLICY "partes_insert" ON partes_diarios FOR INSERT WITH CHECK (
  get_user_role() IN ('admin', 'partes')
);
CREATE POLICY "partes_update" ON partes_diarios FOR UPDATE USING (
  get_user_role() = 'admin'
  OR (created_by = auth.uid() AND estado IN ('borrador', 'rechazado'))
);
CREATE POLICY "partes_delete" ON partes_diarios FOR DELETE USING (
  get_user_role() = 'admin'
  OR (created_by = auth.uid() AND estado = 'borrador')
);

-- ---- DETALLE DE PARTES ----
CREATE POLICY "parte_trab_select" ON parte_trabajadores FOR SELECT USING (
  parte_id IN (SELECT id FROM partes_diarios)
);
CREATE POLICY "parte_trab_write" ON parte_trabajadores FOR ALL USING (
  parte_id IN (SELECT id FROM partes_diarios WHERE created_by = auth.uid() OR get_user_role() = 'admin')
);

CREATE POLICY "parte_maq_select" ON parte_maquinaria FOR SELECT USING (
  parte_id IN (SELECT id FROM partes_diarios)
);
CREATE POLICY "parte_maq_write" ON parte_maquinaria FOR ALL USING (
  parte_id IN (SELECT id FROM partes_diarios WHERE created_by = auth.uid() OR get_user_role() = 'admin')
);

CREATE POLICY "parte_veh_select" ON parte_vehiculos FOR SELECT USING (
  parte_id IN (SELECT id FROM partes_diarios)
);
CREATE POLICY "parte_veh_write" ON parte_vehiculos FOR ALL USING (
  parte_id IN (SELECT id FROM partes_diarios WHERE created_by = auth.uid() OR get_user_role() = 'admin')
);

CREATE POLICY "parte_mat_select" ON parte_materiales FOR SELECT USING (
  parte_id IN (SELECT id FROM partes_diarios)
);
CREATE POLICY "parte_mat_write" ON parte_materiales FOR ALL USING (
  parte_id IN (SELECT id FROM partes_diarios WHERE created_by = auth.uid() OR get_user_role() = 'admin')
);

-- ---- DOCUMENTOS ----
CREATE POLICY "docs_select" ON documentos FOR SELECT USING (
  obra_id IN (SELECT id FROM obras)
);
CREATE POLICY "docs_insert" ON documentos FOR INSERT WITH CHECK (
  get_user_role() IN ('admin', 'partes')
);
CREATE POLICY "docs_delete" ON documentos FOR DELETE USING (get_user_role() = 'admin');

-- ---- AUDIT LOG ----
CREATE POLICY "audit_select" ON audit_log FOR SELECT USING (get_user_role() = 'admin');
CREATE POLICY "audit_insert" ON audit_log FOR INSERT WITH CHECK (true);

-- ---- CONFIGURACION ----
CREATE POLICY "config_select" ON configuracion FOR SELECT USING (true);
CREATE POLICY "config_write" ON configuracion FOR ALL USING (get_user_role() = 'admin');

-- =============================================================================
-- STORAGE BUCKETS
-- =============================================================================

INSERT INTO storage.buckets (id, name, public) VALUES ('documentos', 'documentos', false);
INSERT INTO storage.buckets (id, name, public) VALUES ('fotos', 'fotos', false);
INSERT INTO storage.buckets (id, name, public) VALUES ('firmas', 'firmas', false);

-- Storage policies
CREATE POLICY "docs_storage_select" ON storage.objects FOR SELECT USING (
  bucket_id IN ('documentos', 'fotos', 'firmas') AND auth.role() = 'authenticated'
);
CREATE POLICY "docs_storage_insert" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id IN ('documentos', 'fotos', 'firmas') AND auth.role() = 'authenticated'
);
CREATE POLICY "docs_storage_delete" ON storage.objects FOR DELETE USING (
  bucket_id IN ('documentos', 'fotos', 'firmas') AND auth.role() = 'authenticated'
);

-- =============================================================================
-- DATOS INICIALES
-- =============================================================================

-- Configuración por defecto
INSERT INTO configuracion (clave, valor) VALUES
  ('empresa', '{"nombre": "Loynek Soluciones Técnicas", "logo_url": "/logo.png"}'),
  ('fases_defecto', '["Preparación", "Ejecución", "Remates", "Entrega"]'),
  ('festivos', '["2025-01-01", "2025-01-06", "2025-05-01", "2025-08-15", "2025-10-12", "2025-11-01", "2025-12-06", "2025-12-08", "2025-12-25"]');
