-- =============================================================================
-- ObrasPlan -- Migración 041: Corregir stock_cache para stocks negativos
-- =============================================================================
-- La migración 040 tenía un bug: la función recalcular_stock_articulo
-- usaba UNION de dos SELECT separados, lo que generaba filas duplicadas
-- y un cálculo incorrecto para stocks negativos.
-- Esta migración reescribe la función con un único SELECT correcto.
-- También elimina la línea "DELETE WHERE stock_qty = 0" para conservar
-- los stocks negativos (son datos válidos y necesarios).
-- =============================================================================

CREATE OR REPLACE FUNCTION recalcular_stock_articulo(p_articulo_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Calcular stock por almacén en un único SELECT (sin UNION que duplica)
  -- Misma lógica que v_stock_actual pero volcando a stock_cache
  WITH calc AS (
    SELECT
      COALESCE(m.almacen_destino_id, m.almacen_origen_id) AS almacen_id,
      SUM(
        CASE
          WHEN m.tipo IN ('entrada','traslado_entrada') AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
          WHEN m.tipo = 'ajuste'                        AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
          WHEN m.tipo IN ('salida','traslado_salida')   AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
          WHEN m.tipo = 'ajuste'                        AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
          ELSE 0
        END
      ) AS stock_qty
    FROM movimientos_almacen m
    WHERE m.articulo_id = p_articulo_id
    GROUP BY COALESCE(m.almacen_destino_id, m.almacen_origen_id)
  )
  INSERT INTO stock_cache (articulo_id, almacen_id, stock_qty, updated_at)
  SELECT p_articulo_id, almacen_id, stock_qty, now()
  FROM calc
  WHERE almacen_id IS NOT NULL
  ON CONFLICT (articulo_id, almacen_id)
  DO UPDATE SET
    stock_qty  = EXCLUDED.stock_qty,
    updated_at = now();

  -- Borrar SOLO filas con stock exactamente 0 (no negativos)
  -- Los negativos son válidos y deben conservarse
  DELETE FROM stock_cache
  WHERE articulo_id = p_articulo_id
    AND stock_qty = 0;

  -- Borrar almacenes que ya no aparecen en los movimientos
  -- (por ejemplo si se borraron movimientos, aunque no debería pasar
  -- con la tabla append-only)
  DELETE FROM stock_cache
  WHERE articulo_id = p_articulo_id
    AND almacen_id NOT IN (
      SELECT DISTINCT COALESCE(almacen_destino_id, almacen_origen_id)
      FROM movimientos_almacen
      WHERE articulo_id = p_articulo_id
        AND COALESCE(almacen_destino_id, almacen_origen_id) IS NOT NULL
    );
END;
$$;

-- Reejecutar backfill con la función corregida
SELECT recalcular_stock_todos();

-- Verificación: ver artículos con stock negativo
SELECT
  a.nombre,
  a.codigo_articulo,
  alm.nombre AS almacen,
  sc.stock_qty
FROM stock_cache sc
JOIN articulos a ON a.id = sc.articulo_id
JOIN almacenes alm ON alm.id = sc.almacen_id
WHERE sc.stock_qty < 0
ORDER BY sc.stock_qty;

-- Resumen general
SELECT
  COUNT(DISTINCT articulo_id)                              AS articulos_con_stock,
  COUNT(*)                                                 AS filas_total,
  COUNT(*) FILTER (WHERE stock_qty > 0)                   AS filas_positivas,
  COUNT(*) FILTER (WHERE stock_qty < 0)                   AS filas_negativas,
  SUM(stock_qty)                                          AS stock_total_empresa
FROM stock_cache;

-- =============================================================================
-- FIN MIGRACIÓN 041
-- =============================================================================
