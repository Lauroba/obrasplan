-- =============================================================================
-- ObrasPlan -- Migración 040: Stock cache + Etiquetas plantillas
-- =============================================================================
-- CAMBIOS:
--   A) Tabla stock_cache: stock por (articulo_id, almacen_id) cacheado en BD
--   B) Función recalcular_stock_articulo(p_articulo_id): recalcula un artículo
--   C) Función recalcular_stock_todos(): recalcula todos los artículos
--   D) Trigger AFTER INSERT ON movimientos_almacen: recalcula automáticamente
--   E) Cron job diario vía pg_cron (si está disponible)
--   F) Tabla etiquetas_plantillas: plantillas de diseño de etiquetas
--   G) RLS en ambas tablas
--   H) Backfill inicial: calcular stock actual para todos los artículos
-- =============================================================================


-- =============================================================================
-- A) TABLA stock_cache
-- =============================================================================

CREATE TABLE IF NOT EXISTS stock_cache (
  articulo_id  UUID        NOT NULL REFERENCES articulos(id) ON DELETE CASCADE,
  almacen_id   UUID        NOT NULL REFERENCES almacenes(id) ON DELETE CASCADE,
  stock_qty    NUMERIC     NOT NULL DEFAULT 0,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (articulo_id, almacen_id)
);

ALTER TABLE stock_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY "stock_cache_select" ON stock_cache FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "stock_cache_write"  ON stock_cache FOR ALL   USING (get_user_role() = 'admin');

CREATE INDEX IF NOT EXISTS idx_stock_cache_articulo ON stock_cache(articulo_id);
CREATE INDEX IF NOT EXISTS idx_stock_cache_almacen  ON stock_cache(almacen_id);
CREATE INDEX IF NOT EXISTS idx_stock_cache_qty      ON stock_cache(stock_qty) WHERE stock_qty <> 0;


-- =============================================================================
-- B) FUNCIÓN recalcular_stock_articulo
--    Recalcula el stock de UN artículo en TODOS sus almacenes.
--    Usa UPSERT: actualiza si existe la fila, inserta si no.
--    Elimina filas con stock 0 para mantener la tabla limpia.
-- =============================================================================

CREATE OR REPLACE FUNCTION recalcular_stock_articulo(p_articulo_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Calcular y hacer upsert del stock por almacén
  INSERT INTO stock_cache (articulo_id, almacen_id, stock_qty, updated_at)
  SELECT
    p_articulo_id,
    almacen_id,
    SUM(CASE
      WHEN tipo IN ('entrada', 'traslado_entrada') AND almacen_destino_id IS NOT NULL THEN  cantidad
      WHEN tipo = 'ajuste'                         AND almacen_destino_id IS NOT NULL THEN  cantidad
      WHEN tipo IN ('salida', 'traslado_salida')   AND almacen_origen_id  IS NOT NULL THEN -cantidad
      WHEN tipo = 'ajuste'                         AND almacen_origen_id  IS NOT NULL THEN -cantidad
      ELSE 0
    END) AS stock_qty,
    now()
  FROM (
    SELECT tipo, cantidad, almacen_destino_id AS almacen_id, almacen_destino_id, almacen_origen_id
    FROM movimientos_almacen WHERE articulo_id = p_articulo_id AND almacen_destino_id IS NOT NULL
    UNION ALL
    SELECT tipo, cantidad, almacen_origen_id  AS almacen_id, almacen_destino_id, almacen_origen_id
    FROM movimientos_almacen WHERE articulo_id = p_articulo_id AND almacen_origen_id IS NOT NULL
  ) sub
  GROUP BY almacen_id
  ON CONFLICT (articulo_id, almacen_id)
  DO UPDATE SET
    stock_qty  = EXCLUDED.stock_qty,
    updated_at = now();

  -- Limpiar filas con stock = 0 (no aportan información útil)
  DELETE FROM stock_cache
  WHERE articulo_id = p_articulo_id AND stock_qty = 0;
END;
$$;


-- =============================================================================
-- C) FUNCIÓN recalcular_stock_todos
--    Recalcula el stock de TODOS los artículos con movimientos.
--    Diseñada para ejecución nocturna o bajo demanda global.
-- =============================================================================

CREATE OR REPLACE FUNCTION recalcular_stock_todos()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_articulo UUID;
  v_count    INTEGER := 0;
  v_errors   INTEGER := 0;
BEGIN
  -- Recalcular para cada artículo que tenga al menos un movimiento
  FOR v_articulo IN
    SELECT DISTINCT articulo_id FROM movimientos_almacen
  LOOP
    BEGIN
      PERFORM recalcular_stock_articulo(v_articulo);
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
      RAISE WARNING 'Error recalculando articulo %: %', v_articulo, SQLERRM;
    END;
  END LOOP;

  -- Limpiar stock_cache de artículos que ya no tienen movimientos
  DELETE FROM stock_cache
  WHERE articulo_id NOT IN (SELECT DISTINCT articulo_id FROM movimientos_almacen);

  RETURN jsonb_build_object(
    'articulos_procesados', v_count,
    'errores', v_errors,
    'timestamp', now()
  );
END;
$$;


-- =============================================================================
-- D) TRIGGER: recalcular stock automáticamente tras cada INSERT en movimientos
-- =============================================================================

CREATE OR REPLACE FUNCTION trg_movimientos_recalcular_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Recalcular el artículo del movimiento recién insertado
  PERFORM recalcular_stock_articulo(NEW.articulo_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stock_cache_on_movimiento ON movimientos_almacen;
CREATE TRIGGER trg_stock_cache_on_movimiento
  AFTER INSERT ON movimientos_almacen
  FOR EACH ROW EXECUTE FUNCTION trg_movimientos_recalcular_stock();


-- =============================================================================
-- E) CRON JOB DIARIO (requiere extensión pg_cron)
--    Si pg_cron no está disponible, ignorar el error.
-- =============================================================================

DO $$
BEGIN
  -- Intentar activar pg_cron si está disponible
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Ejecutar recalcular_stock_todos() cada día a las 03:00 hora España
    PERFORM cron.schedule(
      'recalcular_stock_diario',
      '0 2 * * *',  -- 02:00 UTC = 03:00 CET / 04:00 CEST
      'SELECT recalcular_stock_todos()'
    );
    RAISE NOTICE 'Cron job diario configurado correctamente';
  ELSE
    RAISE NOTICE 'pg_cron no disponible — el recálculo diario debe configurarse manualmente en Supabase Dashboard > Database > Scheduled Functions';
  END IF;
END $$;


-- =============================================================================
-- F) TABLA etiquetas_plantillas
-- =============================================================================

CREATE TABLE IF NOT EXISTS etiquetas_plantillas (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre          TEXT        NOT NULL,
  descripcion     TEXT,
  -- Configuración de tamaño de hoja
  hoja_ancho_mm   NUMERIC     NOT NULL DEFAULT 210,  -- A4 210mm
  hoja_alto_mm    NUMERIC     NOT NULL DEFAULT 297,  -- A4 297mm
  -- Configuración de la etiqueta individual
  etiq_ancho_mm   NUMERIC     NOT NULL DEFAULT 70,
  etiq_alto_mm    NUMERIC     NOT NULL DEFAULT 42,
  etiq_cols       INTEGER     NOT NULL DEFAULT 3,    -- columnas por hoja
  etiq_filas      INTEGER     NOT NULL DEFAULT 7,    -- filas por hoja
  margen_h_mm     NUMERIC     NOT NULL DEFAULT 0,    -- margen horizontal
  margen_v_mm     NUMERIC     NOT NULL DEFAULT 0,    -- margen vertical
  espacio_h_mm    NUMERIC     NOT NULL DEFAULT 0,    -- espacio entre columnas
  espacio_v_mm    NUMERIC     NOT NULL DEFAULT 0,    -- espacio entre filas
  -- Campos a incluir en la etiqueta (JSON array de strings)
  campos          JSONB       NOT NULL DEFAULT '["nombre","codigo_articulo","referencia_proveedor","qr"]',
  -- Tamaño del QR (porcentaje del ancho de etiqueta, 0 = sin QR)
  qr_size_pct     INTEGER     NOT NULL DEFAULT 40,
  -- Estilo
  font_size       INTEGER     NOT NULL DEFAULT 8,
  mostrar_borde   BOOLEAN     NOT NULL DEFAULT true,
  -- Meta
  activo          BOOLEAN     NOT NULL DEFAULT true,
  created_by      UUID        REFERENCES users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE etiquetas_plantillas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "etiquetas_select" ON etiquetas_plantillas FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "etiquetas_write"  ON etiquetas_plantillas FOR ALL   USING (get_user_role() = 'admin');

CREATE OR REPLACE FUNCTION etiquetas_plantillas_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;
DROP TRIGGER IF EXISTS trg_etiquetas_updated_at ON etiquetas_plantillas;
CREATE TRIGGER trg_etiquetas_updated_at
  BEFORE UPDATE ON etiquetas_plantillas
  FOR EACH ROW EXECUTE FUNCTION etiquetas_plantillas_updated_at();

DROP TRIGGER IF EXISTS audit_etiquetas_plantillas ON etiquetas_plantillas;
CREATE TRIGGER audit_etiquetas_plantillas
  AFTER INSERT OR UPDATE OR DELETE ON etiquetas_plantillas
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

-- Permisos para roles no-admin
INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'almacen_etiquetas', false, false, false, false, false
FROM roles r WHERE r.nombre IN ('Jefe de obra', 'Encargado', 'Operario')
ON CONFLICT (rol_id, pantalla) DO NOTHING;


-- =============================================================================
-- G) PLANTILLAS POR DEFECTO
-- =============================================================================

INSERT INTO etiquetas_plantillas (nombre, descripcion, hoja_ancho_mm, hoja_alto_mm, etiq_ancho_mm, etiq_alto_mm, etiq_cols, etiq_filas, campos, qr_size_pct, font_size)
VALUES
  ('Avery L7160 (3x7)', '21 etiquetas por hoja', 210, 297, 63.5, 38.1, 3, 7, '["qr","nombre","codigo_articulo","referencia_proveedor"]', 45, 7),
  ('Avery L7163 (2x7)', '14 etiquetas por hoja', 210, 297, 99.1, 38.1, 2, 7, '["qr","nombre","codigo_articulo","referencia_proveedor","proveedor"]', 40, 8),
  ('Etiqueta grande (2x4)', '8 etiquetas por hoja', 210, 297, 105, 74.25, 2, 4, '["qr","nombre","codigo_articulo","referencia_proveedor","proveedor","tipo","unidad"]', 50, 9),
  ('Etiqueta individual A6', 'Una etiqueta grande por hoja', 148, 105, 140, 97, 1, 1, '["qr","nombre","codigo_articulo","referencia_proveedor","proveedor","tipo","unidad","stock_minimo"]', 55, 10)
ON CONFLICT DO NOTHING;


-- =============================================================================
-- H) BACKFILL: calcular stock actual para todos los artículos existentes
-- =============================================================================

SELECT recalcular_stock_todos();

-- Verificación
SELECT
  COUNT(DISTINCT articulo_id) AS articulos_con_stock,
  COUNT(*)                    AS filas_stock_cache,
  SUM(stock_qty)              AS stock_total_empresa
FROM stock_cache;

-- =============================================================================
-- FIN MIGRACIÓN 040
-- =============================================================================
