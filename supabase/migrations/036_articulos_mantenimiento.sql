-- =============================================================================
-- ObrasPlan -- Migracion 036: Mantenimiento maquinaria + dias en almacen
-- =============================================================================

-- A) Campo proximo_mantenimiento en articulos
ALTER TABLE articulos
  ADD COLUMN IF NOT EXISTS proximo_mantenimiento DATE;

CREATE INDEX IF NOT EXISTS idx_articulos_mantenimiento
  ON articulos(proximo_mantenimiento)
  WHERE proximo_mantenimiento IS NOT NULL AND tipo = 'maquinaria';

-- B) Vista v_stock_actual_ext con dias_en_almacen
--    Criterio: dias desde el ultimo movimiento de entrada al almacen.
DROP VIEW IF EXISTS v_stock_actual_ext;
CREATE VIEW v_stock_actual_ext AS
SELECT
  s.*,
  EXTRACT(DAY FROM (
    (NOW() AT TIME ZONE 'Europe/Madrid') -
    (
      SELECT MAX(m2.created_at)
      FROM movimientos_almacen m2
      WHERE m2.articulo_id = s.articulo_id
        AND m2.almacen_destino_id = s.almacen_id
        AND m2.tipo IN ('entrada', 'traslado_entrada', 'ajuste')
    )
  ))::INTEGER AS dias_en_almacen
FROM v_stock_actual s;

-- =============================================================================
-- FIN MIGRACION 036
-- =============================================================================
