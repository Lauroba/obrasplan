-- =============================================================================
-- ObrasPlan — Migración 26: Corrección completa del sistema de auditoría
-- Ejecutar en Supabase SQL Editor
-- =============================================================================
--
-- CONTEXTO DEL FIX
-- -----------------
-- Se detectó que crear un "tipo de obra" no generaba entrada en audit_log.
-- Causa raíz confirmada:
--   1) La tabla `tipos_obra` nunca tuvo un CREATE TABLE en las migraciones
--      versionadas (se creó manualmente en el SQL Editor de Supabase en algún
--      momento) y, por tanto, tampoco tenía trigger de auditoría asociado.
--   2) Auditando el resto del esquema se encontraron más tablas de negocio
--      sin trigger: users, obra_fases, parte_trabajadores, parte_maquinaria,
--      parte_vehiculos, parte_materiales, configuracion.
--
-- Esta migración:
--   A) Amplía audit_log con columnas nuevas (modulo, descripcion, resultado,
--      error_detalle, origen, user_rol) sin romper nada existente.
--   B) Asegura la existencia de tipos_obra con CREATE TABLE IF NOT EXISTS
--      (estructura defensiva — si ya existe en producción, esta sentencia
--      no hace nada gracias a IF NOT EXISTS).
--   C) Redefine audit_log_trigger() para rellenar los campos nuevos.
--   D) Añade los triggers que faltaban en TODAS las tablas detectadas.
--
-- COBERTURA DECLARADA EN ESTA ENTREGA (regla de auditoría obligatoria):
--   tipos_obra            -> NUEVO trigger (caso reportado)
--   users                 -> NUEVO trigger
--   obra_fases             -> NUEVO trigger
--   parte_trabajadores     -> NUEVO trigger
--   parte_maquinaria        -> NUEVO trigger
--   parte_vehiculos         -> NUEVO trigger
--   parte_materiales        -> NUEVO trigger
--   configuracion           -> NUEVO trigger
-- =============================================================================


-- =============================================================================
-- A) AMPLIAR audit_log
-- =============================================================================

ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS modulo TEXT;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS descripcion TEXT;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS resultado TEXT NOT NULL DEFAULT 'exito';
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS error_detalle TEXT;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS origen TEXT NOT NULL DEFAULT 'trigger_db';
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS user_rol TEXT;

ALTER TABLE audit_log ADD CONSTRAINT audit_log_resultado_check
  CHECK (resultado IN ('exito', 'error'));

ALTER TABLE audit_log ADD CONSTRAINT audit_log_origen_check
  CHECK (origen IN ('trigger_db', 'api_route', 'rpc_manual', 'client_catch'));

-- Índices para filtros habituales del listado de logs
CREATE INDEX IF NOT EXISTS idx_audit_log_entidad ON audit_log(entidad);
CREATE INDEX IF NOT EXISTS idx_audit_log_resultado ON audit_log(resultado);
CREATE INDEX IF NOT EXISTS idx_audit_log_entidad_id ON audit_log(entidad_id);


-- =============================================================================
-- B) ASEGURAR EXISTENCIA DE tipos_obra (defensivo, no rompe si ya existe)
-- =============================================================================

CREATE TABLE IF NOT EXISTS tipos_obra (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre TEXT NOT NULL,
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE tipos_obra ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'tipos_obra' AND policyname = 'tipos_obra_select'
  ) THEN
    CREATE POLICY "tipos_obra_select" ON tipos_obra FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'tipos_obra' AND policyname = 'tipos_obra_insert'
  ) THEN
    CREATE POLICY "tipos_obra_insert" ON tipos_obra FOR INSERT WITH CHECK (get_user_role() = 'admin');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'tipos_obra' AND policyname = 'tipos_obra_update'
  ) THEN
    CREATE POLICY "tipos_obra_update" ON tipos_obra FOR UPDATE USING (get_user_role() = 'admin');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'tipos_obra' AND policyname = 'tipos_obra_delete'
  ) THEN
    CREATE POLICY "tipos_obra_delete" ON tipos_obra FOR DELETE USING (get_user_role() = 'admin');
  END IF;
END $$;


-- =============================================================================
-- C) REDEFINIR audit_log_trigger() — añade modulo, descripcion, user_rol, origen
-- =============================================================================
-- Mapeo de tabla -> (módulo legible, nombre de campo "principal" para la
-- descripción). Se resuelve con un CASE simple porque PL/pgSQL no tiene
-- introspección cómoda de "el campo que mejor identifica la fila"; mantenerlo
-- aquí centralizado evita tener que tocar cada trigger individualmente si en
-- el futuro se quiere refinar la descripción de un módulo concreto.

CREATE OR REPLACE FUNCTION audit_log_trigger()
RETURNS TRIGGER AS $$
DECLARE
  _user_id UUID;
  _user_rol TEXT;
  _accion audit_accion;
  _modulo TEXT;
  _nombre_campo TEXT;
  _descripcion TEXT;
BEGIN
  _user_id := COALESCE(
    (current_setting('request.jwt.claims', true)::json ->> 'sub')::uuid,
    NULL
  );

  -- Snapshot del rol en el momento de la acción (no depender de JOIN futuro)
  IF _user_id IS NOT NULL THEN
    SELECT role::TEXT INTO _user_rol FROM users WHERE id = _user_id;
  END IF;

  -- Módulo legible por tabla
  _modulo := CASE TG_TABLE_NAME
    WHEN 'obras' THEN 'obras'
    WHEN 'obra_fases' THEN 'obras.fases'
    WHEN 'tipos_obra' THEN 'maestros.tipos_obra'
    WHEN 'tipos_trabajo' THEN 'maestros.tipos_trabajo'
    WHEN 'estados_obra' THEN 'maestros.estados_obra'
    WHEN 'clientes' THEN 'maestros.clientes'
    WHEN 'recursos_humanos' THEN 'maestros.rrhh'
    WHEN 'maquinaria' THEN 'maestros.maquinaria'
    WHEN 'vehiculos' THEN 'maestros.vehiculos'
    WHEN 'materiales' THEN 'maestros.materiales'
    WHEN 'asignaciones' THEN 'planificacion.asignaciones'
    WHEN 'partes_diarios' THEN 'partes'
    WHEN 'parte_trabajadores' THEN 'partes.detalle_humano'
    WHEN 'parte_maquinaria' THEN 'partes.detalle_maquinaria'
    WHEN 'parte_vehiculos' THEN 'partes.detalle_vehiculo'
    WHEN 'parte_materiales' THEN 'partes.detalle_material'
    WHEN 'documentos' THEN 'documentos'
    WHEN 'tareas' THEN 'tareas'
    WHEN 'users' THEN 'usuarios'
    WHEN 'configuracion' THEN 'configuracion'
    ELSE TG_TABLE_NAME
  END;

  -- Campo "nombre" más representativo de cada tabla, para la descripción legible.
  -- Si la tabla no tiene un campo de texto evidente, se usa el id.
  IF TG_OP = 'DELETE' THEN
    _nombre_campo := CASE TG_TABLE_NAME
      WHEN 'tipos_obra' THEN (to_jsonb(OLD) ->> 'nombre')
      WHEN 'tipos_trabajo' THEN (to_jsonb(OLD) ->> 'nombre')
      WHEN 'estados_obra' THEN (to_jsonb(OLD) ->> 'nombre')
      WHEN 'clientes' THEN (to_jsonb(OLD) ->> 'nombre')
      WHEN 'recursos_humanos' THEN (to_jsonb(OLD) ->> 'nombre')
      WHEN 'maquinaria' THEN (to_jsonb(OLD) ->> 'nombre')
      WHEN 'vehiculos' THEN (to_jsonb(OLD) ->> 'nombre')
      WHEN 'materiales' THEN (to_jsonb(OLD) ->> 'nombre')
      WHEN 'obras' THEN (to_jsonb(OLD) ->> 'nombre')
      WHEN 'obra_fases' THEN (to_jsonb(OLD) ->> 'nombre')
      WHEN 'users' THEN (to_jsonb(OLD) ->> 'nombre')
      WHEN 'configuracion' THEN (to_jsonb(OLD) ->> 'clave')
      ELSE (OLD.id)::TEXT
    END;
  ELSE
    _nombre_campo := CASE TG_TABLE_NAME
      WHEN 'tipos_obra' THEN (to_jsonb(NEW) ->> 'nombre')
      WHEN 'tipos_trabajo' THEN (to_jsonb(NEW) ->> 'nombre')
      WHEN 'estados_obra' THEN (to_jsonb(NEW) ->> 'nombre')
      WHEN 'clientes' THEN (to_jsonb(NEW) ->> 'nombre')
      WHEN 'recursos_humanos' THEN (to_jsonb(NEW) ->> 'nombre')
      WHEN 'maquinaria' THEN (to_jsonb(NEW) ->> 'nombre')
      WHEN 'vehiculos' THEN (to_jsonb(NEW) ->> 'nombre')
      WHEN 'materiales' THEN (to_jsonb(NEW) ->> 'nombre')
      WHEN 'obras' THEN (to_jsonb(NEW) ->> 'nombre')
      WHEN 'obra_fases' THEN (to_jsonb(NEW) ->> 'nombre')
      WHEN 'users' THEN (to_jsonb(NEW) ->> 'nombre')
      WHEN 'configuracion' THEN (to_jsonb(NEW) ->> 'clave')
      ELSE (NEW.id)::TEXT
    END;
  END IF;

  IF TG_OP = 'INSERT' THEN
    _accion := 'crear';
    _descripcion := 'Creó ' || _modulo || COALESCE(': ' || _nombre_campo, '');
    INSERT INTO audit_log (user_id, user_rol, accion, entidad, entidad_id, valor_nuevo, modulo, descripcion, resultado, origen)
    VALUES (_user_id, _user_rol, _accion, TG_TABLE_NAME, NEW.id, to_jsonb(NEW), _modulo, _descripcion, 'exito', 'trigger_db');
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    -- Soft delete detectado: si la tabla tiene columna `activo` y pasa de
    -- true a false, se describe como "Desactivó" en vez de "Editó".
    IF (to_jsonb(OLD) ? 'activo') AND (to_jsonb(OLD) ->> 'activo') = 'true'
       AND (to_jsonb(NEW) ->> 'activo') = 'false' THEN
      _accion := 'editar';
      _descripcion := 'Desactivó ' || _modulo || COALESCE(': ' || _nombre_campo, '');
    ELSIF (to_jsonb(OLD) ? 'activo') AND (to_jsonb(OLD) ->> 'activo') = 'false'
       AND (to_jsonb(NEW) ->> 'activo') = 'true' THEN
      _accion := 'editar';
      _descripcion := 'Reactivó ' || _modulo || COALESCE(': ' || _nombre_campo, '');
    ELSE
      _accion := 'editar';
      _descripcion := 'Editó ' || _modulo || COALESCE(': ' || _nombre_campo, '');
    END IF;
    INSERT INTO audit_log (user_id, user_rol, accion, entidad, entidad_id, valor_anterior, valor_nuevo, modulo, descripcion, resultado, origen)
    VALUES (_user_id, _user_rol, _accion, TG_TABLE_NAME, NEW.id, to_jsonb(OLD), to_jsonb(NEW), _modulo, _descripcion, 'exito', 'trigger_db');
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    _accion := 'eliminar';
    _descripcion := 'Eliminó ' || _modulo || COALESCE(': ' || _nombre_campo, '');
    INSERT INTO audit_log (user_id, user_rol, accion, entidad, entidad_id, valor_anterior, modulo, descripcion, resultado, origen)
    VALUES (_user_id, _user_rol, _accion, TG_TABLE_NAME, OLD.id, to_jsonb(OLD), _modulo, _descripcion, 'exito', 'trigger_db');
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =============================================================================
-- D) TRIGGERS QUE FALTABAN (idempotente: se eliminan si existían y se recrean)
-- =============================================================================

DROP TRIGGER IF EXISTS audit_tipos_obra ON tipos_obra;
CREATE TRIGGER audit_tipos_obra AFTER INSERT OR UPDATE OR DELETE ON tipos_obra
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

DROP TRIGGER IF EXISTS audit_users ON users;
CREATE TRIGGER audit_users AFTER INSERT OR UPDATE OR DELETE ON users
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

DROP TRIGGER IF EXISTS audit_obra_fases ON obra_fases;
CREATE TRIGGER audit_obra_fases AFTER INSERT OR UPDATE OR DELETE ON obra_fases
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

DROP TRIGGER IF EXISTS audit_parte_trabajadores ON parte_trabajadores;
CREATE TRIGGER audit_parte_trabajadores AFTER INSERT OR UPDATE OR DELETE ON parte_trabajadores
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

DROP TRIGGER IF EXISTS audit_parte_maquinaria ON parte_maquinaria;
CREATE TRIGGER audit_parte_maquinaria AFTER INSERT OR UPDATE OR DELETE ON parte_maquinaria
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

DROP TRIGGER IF EXISTS audit_parte_vehiculos ON parte_vehiculos;
CREATE TRIGGER audit_parte_vehiculos AFTER INSERT OR UPDATE OR DELETE ON parte_vehiculos
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

DROP TRIGGER IF EXISTS audit_parte_materiales ON parte_materiales;
CREATE TRIGGER audit_parte_materiales AFTER INSERT OR UPDATE OR DELETE ON parte_materiales
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

DROP TRIGGER IF EXISTS audit_configuracion ON configuracion;
CREATE TRIGGER audit_configuracion AFTER INSERT OR UPDATE OR DELETE ON configuracion
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();


-- =============================================================================
-- E) POLICY DE INSERT DE ERRORES DESDE LA CAPA DE API (service_role / authenticated)
-- =============================================================================
-- La policy audit_insert ya existente (WITH CHECK (true)) ya permite que
-- cualquier usuario autenticado inserte filas de auditoría (necesario tanto
-- para los triggers SECURITY DEFINER como para el endpoint /api/audit/log-error
-- que inserta usando el cliente admin). No se requiere cambio adicional aquí,
-- se deja documentado para que quede explícito en la propia migración.

-- =============================================================================
-- FIN MIGRACIÓN 26
-- =============================================================================
