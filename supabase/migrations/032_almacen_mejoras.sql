-- =============================================================================
-- ObrasPlan -- Migracion 032: Mejoras modulo almacen
-- =============================================================================
--
-- CAMBIOS:
--   A) Campo motivo en movimientos_almacen (para ajustes)
--   B) UNIQUE parcial en almacenes: solo un almacen por obra
--   C) RPC crear_almacen_obra(p_obra_id) -- crea almacen OBRA-{num_presupuesto}
--   D) Trigger en obras para auto-crear almacen en INSERT
--   E) Vista v_resumen_almacenes con sumatorios por tipo
--   F) Mejora de v_stock_actual: anade indicador stock negativo
--   G) Permiso almacen_ajustes en rol_permisos por defecto (admin)
--
-- COBERTURA DE AUDITORIA:
--   movimientos_almacen ya tiene trigger audit_movimientos_almacen (migracion 030)
--   almacenes ya tiene trigger audit_almacenes (migracion 030)
--   No se requieren triggers adicionales.
-- =============================================================================


-- =============================================================================
-- A) CAMPO motivo EN movimientos_almacen
--    Obligatorio para tipo='ajuste', opcional para el resto.
--    La constraint CHECK se aplica al insertar, no al nivel de columna,
--    para poder usar NULLIF de forma idiomatica.
-- =============================================================================

ALTER TABLE movimientos_almacen
  ADD COLUMN IF NOT EXISTS motivo TEXT;

-- Constraint: si tipo = ajuste, motivo debe estar informado.
-- Usamos DO $$ para no fallar si ya existe el constraint.
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
--    Crea el almacen de una obra. Codigo = OBRA-{num_presupuesto}.
--    Falla con mensaje claro si:
--      - La obra no existe
--      - La obra no tiene num_presupuesto
--      - Ya existe un almacen activo para esa obra
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
  -- Obtener datos de la obra
  SELECT id, nombre, num_presupuesto
  INTO v_obra
  FROM obras
  WHERE id = p_obra_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Obra no encontrada: %', p_obra_id;
  END IF;

  -- Validar que tiene num_presupuesto
  IF v_obra.num_presupuesto IS NULL OR TRIM(v_obra.num_presupuesto) = '' THEN
    RAISE EXCEPTION 'La obra no tiene numero de presupuesto. Asigna un numero antes de crear el almacen.';
  END IF;

  -- Verificar que no existe ya un almacen activo para esta obra
  IF EXISTS (
    SELECT 1 FROM almacenes
    WHERE obra_id = p_obra_id AND es_almacen_obra = true AND activo = true
  ) THEN
    RAISE EXCEPTION 'Esta obra ya tiene un almacen asociado.';
  END IF;

  v_codigo := 'OBRA-' || TRIM(v_obra.num_presupuesto);
  v_nombre := 'Almacen obra - ' || v_obra.nombre;

  -- Crear el almacen
  INSERT INTO almacenes (codigo_almacen, nombre, es_almacen_obra, obra_id, activo)
  VALUES (v_codigo, v_nombre, true, p_obra_id, true)
  RETURNING id INTO v_almacen_id;

  RETURN v_almacen_id;
END;
$$;


-- =============================================================================
-- D) TRIGGER EN OBRAS: auto-crear almacen al crear una obra nueva
--    Solo si la obra ya tiene num_presupuesto en el INSERT.
--    Si no tiene num_presupuesto, no falla -- el almacen se crea manualmente
--    desde la ficha de obra.
-- =============================================================================

CREATE OR REPLACE FUNCTION obras_after_insert_crear_almacen()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Solo intentar si hay num_presupuesto
  IF NEW.num_presupuesto IS NOT NULL AND TRIM(NEW.num_presupuesto) <> '' THEN
    BEGIN
      PERFORM crear_almacen_obra(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      -- No fallar el INSERT de la obra si el almacen no se puede crear
      -- (ej: codigo duplicado). El usuario puede crearlo manualmente.
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
-- E) VISTA v_resumen_almacenes
--    Sumatorios de stock por almacen, agrupados por tipo de articulo.
--    Usada en el listado de almacenes (no muestra lineas individuales).
-- =============================================================================

CREATE OR REPLACE VIEW v_resumen_almacenes AS
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
  -- Sumatorios por tipo
  COALESCE(SUM(s.stock_qty) FILTER (WHERE ar.tipo = 'material'),   0) AS stock_material,
  COALESCE(SUM(s.stock_qty) FILTER (WHERE ar.tipo = 'maquinaria'), 0) AS stock_maquinaria,
  COALESCE(SUM(s.stock_qty) FILTER (WHERE ar.tipo = 'vehiculo'),   0) AS stock_vehiculo,
  COALESCE(SUM(s.stock_qty) FILTER (WHERE ar.tipo = 'otro'),       0) AS stock_otro,
  COALESCE(SUM(s.stock_qty),                                       0) AS stock_total,
  -- Contadores
  COUNT(DISTINCT s.articulo_id)                                       AS num_articulos,
  COUNT(DISTINCT s.articulo_id) FILTER (WHERE s.stock_qty < 0)        AS num_negativos,
  COUNT(DISTINCT s.articulo_id) FILTER (WHERE s.bajo_minimo = true)   AS num_bajo_minimo
FROM almacenes al
LEFT JOIN obras ob ON ob.id = al.obra_id
LEFT JOIN (
  -- Stock calculado por articulo + almacen (replica la logica de v_stock_actual)
  SELECT
    m.articulo_id,
    COALESCE(m.almacen_destino_id, m.almacen_origen_id) AS almacen_id,
    SUM(
      CASE
        WHEN m.tipo IN ('entrada','traslado_entrada') AND m.almacen_destino_id IS NOT NULL THEN m.cantidad
        WHEN m.tipo = 'ajuste' AND m.almacen_destino_id IS NOT NULL                        THEN m.cantidad
        WHEN m.tipo IN ('salida','traslado_salida')   AND m.almacen_origen_id IS NOT NULL  THEN -m.cantidad
        WHEN m.tipo = 'ajuste' AND m.almacen_origen_id IS NOT NULL                         THEN -m.cantidad
        ELSE 0
      END
    ) AS stock_qty,
    SUM(
      CASE
        WHEN m.tipo IN ('entrada','traslado_entrada') AND m.almacen_destino_id IS NOT NULL THEN m.cantidad
        WHEN m.tipo = 'ajuste' AND m.almacen_destino_id IS NOT NULL                        THEN m.cantidad
        WHEN m.tipo IN ('salida','traslado_salida')   AND m.almacen_origen_id IS NOT NULL  THEN -m.cantidad
        WHEN m.tipo = 'ajuste' AND m.almacen_origen_id IS NOT NULL                         THEN -m.cantidad
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
-- F) MEJORA v_stock_actual: anadir columna stock_negativo para UI
-- =============================================================================

CREATE OR REPLACE VIEW v_stock_actual AS
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


-- =============================================================================
-- G) PERMISO almacen_ajustes en rol_permisos (solo admin por defecto)
-- =============================================================================

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'almacen_ajustes', false, false, false, false, false
FROM roles r WHERE r.nombre = 'Jefe de obra'
ON CONFLICT (rol_id, pantalla) DO NOTHING;

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'almacen_ajustes', false, false, false, false, false
FROM roles r WHERE r.nombre = 'Encargado'
ON CONFLICT (rol_id, pantalla) DO NOTHING;

INSERT INTO rol_permisos (rol_id, pantalla, visible, crear, editar, eliminar, asignar)
SELECT r.id, 'almacen_ajustes', false, false, false, false, false
FROM roles r WHERE r.nombre = 'Operario'
ON CONFLICT (rol_id, pantalla) DO NOTHING;

-- Admin tiene acceso por is_admin = true, no necesita fila en rol_permisos.

-- =============================================================================
-- FIN MIGRACION 032
-- =============================================================================
