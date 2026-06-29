-- =============================================================================
-- ObrasPlan -- Migracion 037: Añadir foto_url a vistas de stock
-- =============================================================================
-- La migracion 035 añadio foto_url a la tabla articulos.
-- Las vistas v_stock_actual y v_stock_actual_ext no la incluian.
-- Se recrean aqui para que todas las pantallas de stock vean la foto.
-- =============================================================================

DROP VIEW IF EXISTS v_stock_actual_ext;
DROP VIEW IF EXISTS v_alertas_almacen;
DROP VIEW IF EXISTS v_stock_actual;

CREATE VIEW v_stock_actual AS
SELECT
  m.articulo_id,
  a.referencia_proveedor,
  a.codigo_articulo,
  a.codigo_barras,
  a.nombre,
  a.tipo,
  a.unidad,
  a.stock_minimo,
  a.caducidad,
  a.foto_url,
  a.proximo_mantenimiento,
  COALESCE(alm.id,  alm2.id)          AS almacen_id,
  COALESCE(alm.nombre, alm2.nombre)   AS almacen_nombre,
  SUM(
    CASE
      WHEN m.tipo IN ('entrada','traslado_entrada') AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
      WHEN m.tipo = 'ajuste'                        AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
      WHEN m.tipo IN ('salida','traslado_salida')   AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
      WHEN m.tipo = 'ajuste'                        AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
      ELSE 0
    END
  )                                   AS stock_qty,
  a.stock_minimo                      AS stock_minimo_def,
  SUM(
    CASE
      WHEN m.tipo IN ('entrada','traslado_entrada') AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
      WHEN m.tipo = 'ajuste'                        AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
      WHEN m.tipo IN ('salida','traslado_salida')   AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
      WHEN m.tipo = 'ajuste'                        AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
      ELSE 0
    END
  ) < 0                               AS stock_negativo,
  SUM(
    CASE
      WHEN m.tipo IN ('entrada','traslado_entrada') AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
      WHEN m.tipo = 'ajuste'                        AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
      WHEN m.tipo IN ('salida','traslado_salida')   AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
      WHEN m.tipo = 'ajuste'                        AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
      ELSE 0
    END
  ) < a.stock_minimo                  AS bajo_minimo
FROM movimientos_almacen m
JOIN articulos a ON a.id = m.articulo_id
LEFT JOIN almacenes alm  ON alm.id  = m.almacen_destino_id
LEFT JOIN almacenes alm2 ON alm2.id = m.almacen_origen_id
GROUP BY
  m.articulo_id, a.referencia_proveedor, a.codigo_articulo, a.codigo_barras,
  a.nombre, a.tipo, a.unidad, a.stock_minimo, a.caducidad,
  a.foto_url, a.proximo_mantenimiento,
  COALESCE(alm.id, alm2.id), COALESCE(alm.nombre, alm2.nombre);

CREATE VIEW v_alertas_almacen AS
SELECT
  s.articulo_id, s.codigo_articulo, s.nombre, s.foto_url,
  s.almacen_id, s.almacen_nombre,
  s.stock_qty, s.stock_minimo_def, s.caducidad,
  CASE WHEN s.bajo_minimo THEN 'stock_bajo' ELSE NULL END  AS alerta_stock,
  CASE
    WHEN s.caducidad IS NOT NULL AND s.caducidad <= (now() AT TIME ZONE 'Europe/Madrid')::DATE
      THEN 'caducado'
    WHEN s.caducidad IS NOT NULL AND s.caducidad <= (now() AT TIME ZONE 'Europe/Madrid')::DATE + 30
      THEN 'caduca_pronto'
    ELSE NULL
  END AS alerta_caducidad
FROM v_stock_actual s
WHERE s.bajo_minimo = true
   OR (s.caducidad IS NOT NULL AND s.caducidad <= (now() AT TIME ZONE 'Europe/Madrid')::DATE + 30);

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
-- FIN MIGRACION 037
-- =============================================================================
