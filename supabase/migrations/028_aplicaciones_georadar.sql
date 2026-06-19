-- =============================================================================
-- ObrasPlan -- Migracion 28: Modulo Aplicaciones + app Interpretacion de Georradar
-- Ejecutar en Supabase SQL Editor
-- =============================================================================
--
-- CONTEXTO
-- --------
-- Se crea el nuevo modulo "Aplicaciones" (al mismo nivel que Principal,
-- Maestros, Administracion), con la primera app: Interpretacion de Georradar.
--
-- Esta migracion:
--   A) Crea el bucket de storage 'georadar' (capturas de radargrama e informes)
--   B) Crea la tabla georadar_pasadas (una fila por pasada/zona analizada)
--   C) Anade trigger de auditoria a georadar_pasadas desde el dia 1
--   D) Cubre un hueco de auditoria preexistente detectado durante esta entrega:
--      las tablas roles y rol_permisos (migracion 010_roles.sql) nunca
--      tuvieron trigger de auditoria. Como esta misma migracion inserta
--      permisos nuevos en rol_permisos, se corrige aqui para que quede
--      cubierto desde ya.
--   E) Da de alta los permisos por defecto de pantalla='apps_georadar' para
--      los roles existentes (Jefe de obra y Encargado con acceso, Operario
--      sin acceso por defecto, Administrador ya tiene acceso total via
--      is_admin)
--
-- COBERTURA DE AUDITORIA DECLARADA EN ESTA ENTREGA:
--   georadar_pasadas  -> NUEVO trigger (tabla nueva de este modulo)
--   roles             -> NUEVO trigger (hueco preexistente, corregido ahora)
--   rol_permisos      -> NUEVO trigger (hueco preexistente, corregido ahora)
-- =============================================================================


-- =============================================================================
-- A) BUCKET DE STORAGE
-- =============================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('georadar', 'georadar', false)
ON CONFLICT (id) DO NOTHING;

-- Politicas de storage: solo usuarios autenticados con permiso del modulo
-- pueden subir/leer. La comprobacion fina de permiso por rol se hace en la
-- capa de aplicacion (usePermissions); aqui solo se exige sesion valida,
-- igual que el resto de buckets privados de ObrasPlan (documentos, audios).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'georadar_storage_select'
  ) THEN
    CREATE POLICY "georadar_storage_select" ON storage.objects FOR SELECT
      USING (bucket_id = 'georadar' AND auth.role() = 'authenticated');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'georadar_storage_insert'
  ) THEN
    CREATE POLICY "georadar_storage_insert" ON storage.objects FOR INSERT
      WITH CHECK (bucket_id = 'georadar' AND auth.role() = 'authenticated');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'georadar_storage_delete'
  ) THEN
    CREATE POLICY "georadar_storage_delete" ON storage.objects FOR DELETE
      USING (bucket_id = 'georadar' AND auth.role() = 'authenticated');
  END IF;
END $$;


-- =============================================================================
-- B) TABLA georadar_pasadas
-- =============================================================================
-- Una fila por pasada/zona analizada. Guarda metadatos y resultados resumidos;
-- los datos pesados (SGY original) NO se almacenan en BD -- el procesamiento
-- es en navegador, segun se acordo, y solo se persiste el resultado.

CREATE TABLE IF NOT EXISTS georadar_pasadas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  obra_id UUID REFERENCES obras(id) ON DELETE SET NULL,
  cliente_nombre TEXT,
  proyecto TEXT,
  zona_nombre TEXT NOT NULL DEFAULT 'ZONA 1',
  fecha DATE NOT NULL DEFAULT CURRENT_DATE,
  operador TEXT,
  dispositivo_sn TEXT,
  dispositivo_fw TEXT,
  longitud_m NUMERIC,
  velocidad_em NUMERIC DEFAULT 0.09,
  material TEXT DEFAULT 'gr',
  num_anomalias INTEGER NOT NULL DEFAULT 0,
  num_suministros INTEGER NOT NULL DEFAULT 0,
  volumen_bruto_m3 NUMERIC,
  volumen_neto_m3 NUMERIC,
  riesgo_alto INTEGER NOT NULL DEFAULT 0,
  riesgo_medio INTEGER NOT NULL DEFAULT 0,
  riesgo_bajo INTEGER NOT NULL DEFAULT 0,
  anomalias_json JSONB,
  analisis_ia_texto TEXT,
  analisis_ia_modelo TEXT,
  informe_storage_path TEXT,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE georadar_pasadas ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'georadar_pasadas' AND policyname = 'georadar_pasadas_select'
  ) THEN
    CREATE POLICY "georadar_pasadas_select" ON georadar_pasadas FOR SELECT
      USING (auth.role() = 'authenticated');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'georadar_pasadas' AND policyname = 'georadar_pasadas_insert'
  ) THEN
    CREATE POLICY "georadar_pasadas_insert" ON georadar_pasadas FOR INSERT
      WITH CHECK (auth.role() = 'authenticated');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'georadar_pasadas' AND policyname = 'georadar_pasadas_update'
  ) THEN
    CREATE POLICY "georadar_pasadas_update" ON georadar_pasadas FOR UPDATE
      USING (auth.role() = 'authenticated');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'georadar_pasadas' AND policyname = 'georadar_pasadas_delete'
  ) THEN
    CREATE POLICY "georadar_pasadas_delete" ON georadar_pasadas FOR DELETE
      USING (get_user_role() = 'admin');
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_georadar_pasadas_obra ON georadar_pasadas(obra_id);
CREATE INDEX IF NOT EXISTS idx_georadar_pasadas_fecha ON georadar_pasadas(fecha);


-- =============================================================================
-- C) TRIGGER DE AUDITORIA: georadar_pasadas (NUEVO, tabla de este modulo)
-- =============================================================================

DROP TRIGGER IF EXISTS audit_georadar_pasadas ON georadar_pasadas;
CREATE TRIGGER audit_georadar_pasadas AFTER INSERT OR UPDATE OR DELETE ON georadar_pasadas
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();


-- =============================================================================
-- D) CORRECCION DE HUECO PREEXISTENTE: roles y rol_permisos sin trigger
-- =============================================================================
-- Detectado al revisar el sistema de permisos para integrar el modulo nuevo.
-- No formaba parte del alcance original pero se corrige aqui porque esta
-- misma migracion modifica rol_permisos (alta de permisos del modulo nuevo)
-- y la regla del proyecto exige que todo desarrollo que toque una tabla sin
-- auditoria la deje cubierta.

DROP TRIGGER IF EXISTS audit_roles ON roles;
CREATE TRIGGER audit_roles AFTER INSERT OR UPDATE OR DELETE ON roles
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

DROP TRIGGER IF EXISTS audit_rol_permisos ON rol_permisos;
CREATE TRIGGER audit_rol_permisos AFTER INSERT OR UPDATE OR DELETE ON rol_permisos
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();


-- =============================================================================
-- E) PERMISOS POR DEFECTO DEL MODULO NUEVO (pantalla = 'apps_georadar')
-- =============================================================================
-- Criterio de negocio acordado: Jefe de obra y Encargado con acceso de uso
-- (visible + crear, sin editar/eliminar pasadas ajenas); Operario sin acceso
-- por defecto (consistente con "Operario: sin acceso por defecto" del
-- encargo original). Administrador ya tiene acceso total via is_admin.

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'apps_georadar', true, true, true, false, false
FROM roles r WHERE r.nombre = 'Jefe de obra'
ON CONFLICT (rol_id, pantalla) DO UPDATE SET visible = true, crear = true, editar = true;

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'apps_georadar', true, true, false, false, false
FROM roles r WHERE r.nombre = 'Encargado'
ON CONFLICT (rol_id, pantalla) DO UPDATE SET visible = true, crear = true;

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'apps_georadar', false, false, false, false, false
FROM roles r WHERE r.nombre = 'Operario'
ON CONFLICT (rol_id, pantalla) DO NOTHING;

-- =============================================================================
-- FIN MIGRACION 28
-- =============================================================================
