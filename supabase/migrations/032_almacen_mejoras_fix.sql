-- =============================================================================
-- ObrasPlan -- Migracion 032: Mejoras modulo almacen (FIX)
-- Ejecutar en lugar de 032_almacen_mejoras.sql
-- =============================================================================
--
-- Fix respecto al original: v_stock_actual se DROPA antes de recrearse
-- porque PostgreSQL no permite anadir columnas a una vista con
-- CREATE OR REPLACE (error 42P16: cannot change name of view column).
-- Lo mismo para v_alertas_almacen que depende de v_stock_actual.
-- =============================================================================


-- =============================================================================
-- A) CAMPO motivo EN movimientos_almacen
-- =============================================================================

ALTER TABLE movimientos_almacen
  ADD COLUMN IF NOT EXISTS motivo TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'movimientos_almacen'::regclass
      AND conname = 'chk_ajuste_motivo'
  ) THEN
    ALTER TABLE movimientos_almacen
      ADD CONSTRAINT chk_ajuste_motivo
      CHECK (tipo <> 'ajuste' OR (motivo IS NOT NULL AND motivo <> ''));
  END IF;
END $$;


-- =============================================================================
-- B) UNIQUE PARCIAL: solo un almacen por obra
-- =============================================================================

DROP INDEX IF EXISTS idx_almacenes_obra_unique;
CREATE UNIQUE INDEX idx_almacenes_obra_unique
  ON almacenes (obra_id)
  WHERE es_almacen_obra = true AND activo = true;


-- =============================================================================
-- C) RPC crear_almacen_obra
-- =============================================================================

CREATE OR REPLACE FUNCTION crear_almacen_obra(p_obra_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_obra          RECORD;
  v_codigo        TEXT;
  v_nombre        TEXT;
  v_almacen_id    UUID;
BEGIN
  SELECT id, nombre, num_presupuesto
  INTO v_obra
  FROM obras
  WHERE id = p_obra_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Obra no encontrada: %', p_obra_id;
  END IF;

  IF v_obra.num_presupuesto IS NULL OR TRIM(v_obra.num_presupuesto) = '' THEN
    RAISE EXCEPTION 'La obra no tiene numero de presupuesto. Asigna un numero antes de crear el almacen.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM almacenes
    WHERE obra_id = p_obra_id AND es_almacen_obra = true AND activo = true
  ) THEN
    RAISE EXCEPTION 'Esta obra ya tiene un almacen asociado.';
  END IF;

  v_codigo := 'OBRA-' || TRIM(v_obra.num_presupuesto);
  v_nombre := 'Almacen obra - ' || v_obra.nombre;

  INSERT INTO almacenes (codigo_almacen, nombre, es_almacen_obra, obra_id, activo)
  VALUES (v_codigo, v_nombre, true, p_obra_id, true)
  RETURNING id INTO v_almacen_id;

  RETURN v_almacen_id;
END;
$$;


-- =============================================================================
-- D) TRIGGER EN OBRAS: auto-crear almacen al crear obra
-- =============================================================================

CREATE OR REPLACE FUNCTION obras_after_insert_crear_almacen()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.num_presupuesto IS NOT NULL AND TRIM(NEW.num_presupuesto) <> '' THEN
    BEGIN
      PERFORM crear_almacen_obra(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'No se pudo crear almacen automatico para obra %: %', NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_obras_crear_almacen ON obras;
CREATE TRIGGER trg_obras_crear_almacen
  AFTER INSERT ON obras
  FOR EACH ROW EXECUTE FUNCTION obras_after_insert_crear_almacen();


-- =============================================================================
-- E + F) VISTAS: DROP en orden correcto por dependencias, luego recrear
--
-- Orden de dependencias:
--   v_alertas_almacen  depende de  v_stock_actual
--   v_resumen_almacenes es independiente
-- Hay que dropear v_alertas_almacen antes que v_stock_actual.
-- =============================================================================

DROP VIEW IF EXISTS v_alertas_almacen;
DROP VIEW IF EXISTS v_stock_actual;


-- v_stock_actual con columna stock_negativo nueva
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
  COALESCE(alm.id, alm2.id), COALESCE(alm.nombre, alm2.nombre);


-- v_alertas_almacen restaurada (identica a la de migracion 030)
CREATE VIEW v_alertas_almacen AS
SELECT
  s.articulo_id,
  s.codigo_articulo,
  s.nombre,
  s.almacen_id,
  s.almacen_nombre,
  s.stock_qty,
  s.stock_minimo_def,
  s.caducidad,
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


-- v_resumen_almacenes (nueva en esta migracion)
DROP VIEW IF EXISTS v_resumen_almacenes;
CREATE VIEW v_resumen_almacenes AS
SELECT
  al.id                                                           AS almacen_id,
  al.codigo_almacen,
  al.nombre,
  al.ubicacion,
  al.es_almacen_obra,
  al.obra_id,
  ob.nombre                                                       AS obra_nombre,
  al.activo,
  al.created_at,
  COALESCE(SUM(s.stock_qty) FILTER (WHERE ar.tipo = 'material'),   0) AS stock_material,
  COALESCE(SUM(s.stock_qty) FILTER (WHERE ar.tipo = 'maquinaria'), 0) AS stock_maquinaria,
  COALESCE(SUM(s.stock_qty) FILTER (WHERE ar.tipo = 'vehiculo'),   0) AS stock_vehiculo,
  COALESCE(SUM(s.stock_qty) FILTER (WHERE ar.tipo = 'otro'),       0) AS stock_otro,
  COALESCE(SUM(s.stock_qty),                                       0) AS stock_total,
  COUNT(DISTINCT s.articulo_id)                                       AS num_articulos,
  COUNT(DISTINCT s.articulo_id) FILTER (WHERE s.stock_qty < 0)        AS num_negativos,
  COUNT(DISTINCT s.articulo_id) FILTER (WHERE s.bajo_minimo = true)   AS num_bajo_minimo
FROM almacenes al
LEFT JOIN obras ob ON ob.id = al.obra_id
LEFT JOIN (
  SELECT
    m.articulo_id,
    COALESCE(m.almacen_destino_id, m.almacen_origen_id) AS almacen_id,
    SUM(
      CASE
        WHEN m.tipo IN ('entrada','traslado_entrada') AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
        WHEN m.tipo = 'ajuste'                        AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
        WHEN m.tipo IN ('salida','traslado_salida')   AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
        WHEN m.tipo = 'ajuste'                        AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
        ELSE 0
      END
    ) AS stock_qty,
    SUM(
      CASE
        WHEN m.tipo IN ('entrada','traslado_entrada') AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
        WHEN m.tipo = 'ajuste'                        AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
        WHEN m.tipo IN ('salida','traslado_salida')   AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
        WHEN m.tipo = 'ajuste'                        AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
        ELSE 0
      END
    ) < ar2.stock_minimo AS bajo_minimo
  FROM movimientos_almacen m
  JOIN articulos ar2 ON ar2.id = m.articulo_id
  GROUP BY m.articulo_id, COALESCE(m.almacen_destino_id, m.almacen_origen_id), ar2.stock_minimo
) s ON s.almacen_id = al.id
LEFT JOIN articulos ar ON ar.id = s.articulo_id
GROUP BY al.id, al.codigo_almacen, al.nombre, al.ubicacion,
         al.es_almacen_obra, al.obra_id, ob.nombre, al.activo, al.created_at;


-- =============================================================================
-- G) PERMISO almacen_ajustes en rol_permisos
-- =============================================================================

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'almacen_ajustes', false, false, false, false, false
FROM roles r WHERE r.nombre IN ('Jefe de obra', 'Encargado', 'Operario')
ON CONFLICT (rol_id, pantalla) DO NOTHING;


-- =============================================================================
-- FIN MIGRACION 032 (FIX)
-- =============================================================================
