-- =============================================================================
-- ObrasPlan -- Migracion 033: Maestro de tipos de articulo
-- Ejecutar en Supabase SQL Editor
-- =============================================================================
--
-- RESUMEN:
--   A) Crea tabla tipos_articulo con auditoria via trigger existente
--   B) Inserta los 4 tipos legacy (material, maquinaria, vehiculo, otro)
--   C) Añade columna tipo_articulo_id en articulos (nullable, FK)
--   D) Migra datos: vincula cada articulo existente a su tipo por nombre
--   E) RLS en tipos_articulo
--   F) Indice para FK
--   G) Permisos en rol_permisos (solo admin gestionable, resto sin acceso)
--
-- DECISION DE MIGRACION:
--   La columna articulos.tipo (TEXT con CHECK enum) se mantiene sin tocar
--   para no romper datos existentes ni el campo 'tipo' de v_stock_actual
--   y v_resumen_almacenes. La columna nueva tipo_articulo_id es nullable.
--   En una migracion futura (034) se puede eliminar articulos.tipo cuando
--   todas las pantallas usen tipo_articulo_id exclusivamente.
--
-- COBERTURA DE AUDITORIA:
--   tipos_articulo -> trigger audit_tipos_articulo (nuevo)
--   articulos -> ya tiene trigger audit_articulos (migracion 030)
--   Los UPDATE de tipo_articulo_id en articulos quedan cubiertos por
--   el trigger existente audit_articulos.
-- =============================================================================


-- =============================================================================
-- A) TABLA tipos_articulo
-- =============================================================================

CREATE TABLE IF NOT EXISTS tipos_articulo (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre      TEXT        NOT NULL UNIQUE,
  descripcion TEXT,
  activo      BOOLEAN     NOT NULL DEFAULT true,
  orden       INTEGER     NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE tipos_articulo ENABLE ROW LEVEL SECURITY;

-- Solo usuarios autenticados pueden leer
CREATE POLICY "tipos_articulo_select" ON tipos_articulo
  FOR SELECT USING (auth.role() = 'authenticated');

-- Solo admin puede escribir (CREATE/UPDATE/DELETE)
CREATE POLICY "tipos_articulo_write" ON tipos_articulo
  FOR ALL USING (get_user_role() = 'admin');

CREATE INDEX IF NOT EXISTS idx_tipos_articulo_orden  ON tipos_articulo(orden, nombre);
CREATE INDEX IF NOT EXISTS idx_tipos_articulo_activo ON tipos_articulo(activo);

-- Trigger updated_at
CREATE OR REPLACE FUNCTION tipos_articulo_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_tipos_articulo_updated_at ON tipos_articulo;
CREATE TRIGGER trg_tipos_articulo_updated_at
  BEFORE UPDATE ON tipos_articulo
  FOR EACH ROW EXECUTE FUNCTION tipos_articulo_set_updated_at();

-- Trigger auditoria (usa la misma funcion que el resto del modulo almacen)
DROP TRIGGER IF EXISTS audit_tipos_articulo ON tipos_articulo;
CREATE TRIGGER audit_tipos_articulo
  AFTER INSERT OR UPDATE OR DELETE ON tipos_articulo
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();


-- =============================================================================
-- B) INSERTAR LOS 4 TIPOS LEGACY
--    Orden: los mas comunes primero
-- =============================================================================

INSERT INTO tipos_articulo (nombre, descripcion, activo, orden) VALUES
  ('Material',   'Material fungible y consumibles',        true, 1),
  ('Maquinaria', 'Maquinaria y equipos',                   true, 2),
  ('Vehiculo',   'Vehiculos e items de transporte',        true, 3),
  ('Otro',       'Otros articulos no clasificados',        true, 4)
ON CONFLICT (nombre) DO NOTHING;


-- =============================================================================
-- C) NUEVA COLUMNA EN articulos
-- =============================================================================

ALTER TABLE articulos
  ADD COLUMN IF NOT EXISTS tipo_articulo_id UUID
    REFERENCES tipos_articulo(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_articulos_tipo_articulo_id
  ON articulos(tipo_articulo_id);


-- =============================================================================
-- D) MIGRACION DE DATOS: vincular articulos existentes a su tipo_articulo_id
--    Mapeo: tipo TEXT (lowercase) -> nombre en tipos_articulo (capitalized)
-- =============================================================================

UPDATE articulos SET tipo_articulo_id = (
  SELECT id FROM tipos_articulo WHERE LOWER(nombre) = LOWER(articulos.tipo)
)
WHERE tipo_articulo_id IS NULL
  AND tipo IS NOT NULL;


-- =============================================================================
-- E) PERMISOS en rol_permisos
--    Solo admin tiene acceso (is_admin = true en roles, sin fila necesaria).
--    Los demas roles se insertan explicitamente sin acceso para que
--    la pantalla de Configuracion los muestre correctamente.
-- =============================================================================

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'almacen_tipos_articulo', false, false, false, false, false
FROM roles r
WHERE r.nombre IN ('Jefe de obra', 'Encargado', 'Operario')
ON CONFLICT (rol_id, pantalla) DO NOTHING;


-- =============================================================================
-- FIN MIGRACION 033
-- =============================================================================
