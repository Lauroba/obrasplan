-- =============================================================================
-- ObrasPlan — Migración 8: Auditoría completa
-- Ejecutar en Supabase SQL Editor
-- =============================================================================

-- 1. Añadir triggers de auditoría a tablas que faltan
CREATE TRIGGER audit_tareas AFTER INSERT OR UPDATE OR DELETE ON tareas
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

CREATE TRIGGER audit_documentos AFTER INSERT OR UPDATE OR DELETE ON documentos
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

CREATE TRIGGER audit_parte_lineas AFTER INSERT OR UPDATE OR DELETE ON parte_lineas
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

CREATE TRIGGER audit_parte_audios AFTER INSERT OR UPDATE OR DELETE ON parte_audios
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

CREATE TRIGGER audit_tipos_trabajo AFTER INSERT OR UPDATE OR DELETE ON tipos_trabajo
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

CREATE TRIGGER audit_estados_obra AFTER INSERT OR UPDATE OR DELETE ON estados_obra
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

-- 2. Función para registrar login (se llama desde el frontend)
CREATE OR REPLACE FUNCTION log_user_login(p_user_id UUID, p_ip TEXT DEFAULT NULL, p_user_agent TEXT DEFAULT NULL)
RETURNS void AS $$
BEGIN
  INSERT INTO audit_log (user_id, accion, entidad, entidad_id, valor_nuevo, ip_address, user_agent)
  VALUES (p_user_id, 'login', 'session', p_user_id, 
    jsonb_build_object('timestamp', now(), 'user_id', p_user_id), 
    p_ip, p_user_agent);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
