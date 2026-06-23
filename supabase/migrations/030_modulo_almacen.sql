-- =============================================================================
-- ObrasPlan -- Migracion 030: Modulo de almacen
-- Ejecutar en Supabase SQL Editor
-- =============================================================================
--
-- COBERTURA DE AUDITORIA DECLARADA:
--   proveedores           -> trigger nuevo
--   almacenes             -> trigger nuevo
--   articulos             -> trigger nuevo
--   ubicaciones_stock     -> trigger nuevo
--   movimientos_almacen   -> trigger nuevo (INSERT only — nunca se edita ni borra)
--
-- TABLAS LEGACY ELIMINADAS (con preservacion de datos en tablas _legacy):
--   maquinaria, materiales, parte_maquinaria, parte_materiales,
--   asignaciones (recurso_tipo IN ('maquinaria','material'))
-- =============================================================================


-- =============================================================================
-- 0. PRESERVAR DATOS LEGACY ANTES DE ELIMINAR
-- =============================================================================

CREATE TABLE IF NOT EXISTS _legacy_maquinaria AS SELECT * FROM maquinaria;
CREATE TABLE IF NOT EXISTS _legacy_materiales  AS SELECT * FROM materiales;
CREATE TABLE IF NOT EXISTS _legacy_parte_maquinaria AS SELECT * FROM parte_maquinaria;
CREATE TABLE IF NOT EXISTS _legacy_parte_materiales  AS SELECT * FROM parte_materiales;


-- =============================================================================
-- 1. PROVEEDORES
-- =============================================================================

CREATE TABLE IF NOT EXISTS proveedores (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  codigo_proveedor  TEXT NOT NULL UNIQUE,
  nombre            TEXT NOT NULL,
  contacto          TEXT,
  telefono          TEXT,
  email             TEXT,
  observaciones     TEXT,
  activo            BOOLEAN NOT NULL DEFAULT true,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE proveedores ENABLE ROW LEVEL SECURITY;
CREATE POLICY "proveedores_select" ON proveedores FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "proveedores_write"  ON proveedores FOR ALL   USING (get_user_role() = 'admin');


-- =============================================================================
-- 2. ALMACENES
-- =============================================================================

CREATE TABLE IF NOT EXISTS almacenes (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  codigo_almacen    TEXT NOT NULL UNIQUE,
  nombre            TEXT NOT NULL,
  ubicacion         TEXT,
  es_almacen_obra   BOOLEAN NOT NULL DEFAULT false,
  obra_id           UUID REFERENCES obras(id) ON DELETE SET NULL,
  activo            BOOLEAN NOT NULL DEFAULT true,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE almacenes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "almacenes_select" ON almacenes FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "almacenes_write"  ON almacenes FOR ALL   USING (get_user_role() = 'admin');

CREATE INDEX IF NOT EXISTS idx_almacenes_obra ON almacenes(obra_id);


-- =============================================================================
-- 3. ARTICULOS (reemplaza materiales + maquinaria)
--    codigo_articulo identifica el lote/batch. Es compatible con codigo_barras
--    (mismo formato: numerico/alfanumerico sin espacios).
--    Si no se indica codigo_barras, se usa codigo_articulo.
-- =============================================================================

CREATE TABLE IF NOT EXISTS articulos (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  referencia_proveedor  TEXT NOT NULL,
  codigo_articulo       TEXT NOT NULL UNIQUE,
  codigo_barras         TEXT UNIQUE,
  nombre                TEXT NOT NULL,
  tipo                  TEXT NOT NULL DEFAULT 'material'
                          CHECK (tipo IN ('material','maquinaria','vehiculo','otro')),
  proveedor_id          UUID REFERENCES proveedores(id) ON DELETE SET NULL,
  unidad                TEXT DEFAULT 'ud',
  stock_minimo          NUMERIC NOT NULL DEFAULT 0 CHECK (stock_minimo >= 0),
  caducidad             DATE,
  descripcion           TEXT,
  activo                BOOLEAN NOT NULL DEFAULT true,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Restriccion: mismo proveedor para distintos lotes de la misma referencia
  CONSTRAINT chk_codigo_articulo_format CHECK (codigo_articulo ~ '^[A-Za-z0-9\-_\.]+$')
);

ALTER TABLE articulos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "articulos_select" ON articulos FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "articulos_write"  ON articulos FOR ALL   USING (get_user_role() IN ('admin'));

CREATE INDEX IF NOT EXISTS idx_articulos_ref_prov  ON articulos(referencia_proveedor);
CREATE INDEX IF NOT EXISTS idx_articulos_proveedor ON articulos(proveedor_id);
CREATE INDEX IF NOT EXISTS idx_articulos_tipo       ON articulos(tipo);
CREATE INDEX IF NOT EXISTS idx_articulos_caducidad  ON articulos(caducidad) WHERE caducidad IS NOT NULL;

-- Trigger: si codigo_barras es NULL, copiar codigo_articulo
CREATE OR REPLACE FUNCTION articulo_before_insert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.codigo_barras IS NULL THEN
    NEW.codigo_barras := NEW.codigo_articulo;
  END IF;
  -- Auto-generar codigo_articulo si llega vacio (formato: REF-YYYYMMDD-RAND4)
  IF NEW.codigo_articulo IS NULL OR NEW.codigo_articulo = '' THEN
    NEW.codigo_articulo := UPPER(LEFT(REGEXP_REPLACE(NEW.referencia_proveedor,'[^A-Za-z0-9]','','g'),6))
      || '-' || TO_CHAR(now(),'YYYYMMDD')
      || '-' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT),1,4));
    NEW.codigo_barras := NEW.codigo_articulo;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_articulo_before_insert ON articulos;
CREATE TRIGGER trg_articulo_before_insert
  BEFORE INSERT ON articulos
  FOR EACH ROW EXECUTE FUNCTION articulo_before_insert();


-- =============================================================================
-- 4. UBICACIONES DE STOCK
--    Un articulo puede estar en varias ubicaciones del mismo almacen.
--    La unicidad es por (articulo + almacen + cuarto + balda + altura + posicion).
-- =============================================================================

CREATE TABLE IF NOT EXISTS ubicaciones_stock (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  articulo_id   UUID NOT NULL REFERENCES articulos(id) ON DELETE CASCADE,
  almacen_id    UUID NOT NULL REFERENCES almacenes(id) ON DELETE CASCADE,
  cuarto        TEXT,
  balda         TEXT,
  altura        TEXT,
  posicion      TEXT CHECK (posicion IN ('izquierda','centro','derecha') OR posicion IS NULL),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (articulo_id, almacen_id, cuarto, balda, altura, posicion)
);

ALTER TABLE ubicaciones_stock ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ubicaciones_select" ON ubicaciones_stock FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "ubicaciones_write"  ON ubicaciones_stock FOR ALL   USING (get_user_role() = 'admin');

CREATE INDEX IF NOT EXISTS idx_ubic_almacen  ON ubicaciones_stock(almacen_id);
CREATE INDEX IF NOT EXISTS idx_ubic_articulo ON ubicaciones_stock(articulo_id);


-- =============================================================================
-- 5. MOVIMIENTOS DE ALMACEN
--    Fuente de verdad del stock. NUNCA se edita ni borra (append-only).
--    Ajustes = movimiento tipo 'ajuste' con cantidad positiva o negativa
--    representada como entrada/salida segun convenio.
--    Traslado = salida del origen + entrada en destino en una sola operacion
--    (gestionado por la funcion registrar_traslado()).
-- =============================================================================

CREATE TABLE IF NOT EXISTS movimientos_almacen (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tipo                  TEXT NOT NULL
                          CHECK (tipo IN ('entrada','salida','ajuste','traslado_salida','traslado_entrada')),
  articulo_id           UUID NOT NULL REFERENCES articulos(id) ON DELETE RESTRICT,
  almacen_origen_id     UUID REFERENCES almacenes(id) ON DELETE RESTRICT,
  almacen_destino_id    UUID REFERENCES almacenes(id) ON DELETE RESTRICT,
  ubicacion_origen_id   UUID REFERENCES ubicaciones_stock(id) ON DELETE SET NULL,
  ubicacion_destino_id  UUID REFERENCES ubicaciones_stock(id) ON DELETE SET NULL,
  cantidad              NUMERIC NOT NULL CHECK (cantidad > 0),
  obra_id               UUID REFERENCES obras(id) ON DELETE SET NULL,
  fecha                 DATE NOT NULL DEFAULT (now() AT TIME ZONE 'Europe/Madrid')::DATE,
  lote_ref              TEXT,
  observaciones         TEXT,
  created_by            UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Validaciones de consistencia
  CONSTRAINT chk_origen_salida  CHECK (tipo IN ('salida','traslado_salida','ajuste') OR almacen_origen_id IS NULL OR true),
  CONSTRAINT chk_destino_entrada CHECK (tipo IN ('entrada','traslado_entrada','ajuste') OR almacen_destino_id IS NULL OR true)
);

-- IMMUTABLE: prohibir UPDATE y DELETE
CREATE OR REPLACE RULE movimientos_no_update AS ON UPDATE TO movimientos_almacen DO INSTEAD NOTHING;
CREATE OR REPLACE RULE movimientos_no_delete AS ON DELETE TO movimientos_almacen DO INSTEAD NOTHING;

ALTER TABLE movimientos_almacen ENABLE ROW LEVEL SECURITY;
CREATE POLICY "movimientos_select" ON movimientos_almacen FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "movimientos_insert" ON movimientos_almacen FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE INDEX IF NOT EXISTS idx_mov_articulo ON movimientos_almacen(articulo_id);
CREATE INDEX IF NOT EXISTS idx_mov_almacen_origen  ON movimientos_almacen(almacen_origen_id);
CREATE INDEX IF NOT EXISTS idx_mov_almacen_destino ON movimientos_almacen(almacen_destino_id);
CREATE INDEX IF NOT EXISTS idx_mov_obra   ON movimientos_almacen(obra_id);
CREATE INDEX IF NOT EXISTS idx_mov_fecha  ON movimientos_almacen(fecha);


-- =============================================================================
-- 6. VISTA DE STOCK ACTUAL (calculada desde movimientos)
--    stock = SUM(entradas) - SUM(salidas) por (articulo, almacen, ubicacion)
--    Se usa una VIEW (no tabla) para garantizar que siempre es consistente.
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
  COALESCE(alm.id, alm2.id)          AS almacen_id,
  COALESCE(alm.nombre, alm2.nombre)  AS almacen_nombre,
  SUM(
    CASE
      WHEN m.tipo IN ('entrada','traslado_entrada','ajuste') AND m.almacen_destino_id IS NOT NULL
        THEN m.cantidad
      WHEN m.tipo IN ('salida','traslado_salida')            AND m.almacen_origen_id IS NOT NULL
        THEN -m.cantidad
      WHEN m.tipo = 'ajuste' AND m.almacen_origen_id IS NOT NULL
        THEN -m.cantidad
      ELSE 0
    END
  )                                   AS stock_qty,
  a.stock_minimo                      AS stock_minimo_def,
  SUM(
    CASE
      WHEN m.tipo IN ('entrada','traslado_entrada','ajuste') AND m.almacen_destino_id IS NOT NULL
        THEN m.cantidad
      WHEN m.tipo IN ('salida','traslado_salida')            AND m.almacen_origen_id IS NOT NULL
        THEN -m.cantidad
      WHEN m.tipo = 'ajuste' AND m.almacen_origen_id IS NOT NULL
        THEN -m.cantidad
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
-- 7. FUNCION: registrar_traslado()
--    Crea el par salida+entrada de un traslado entre almacenes de forma atomica.
-- =============================================================================

CREATE OR REPLACE FUNCTION registrar_traslado(
  p_articulo_id         UUID,
  p_almacen_origen_id   UUID,
  p_almacen_destino_id  UUID,
  p_cantidad            NUMERIC,
  p_obra_id             UUID DEFAULT NULL,
  p_observaciones       TEXT DEFAULT NULL,
  p_ubicacion_origen    UUID DEFAULT NULL,
  p_ubicacion_destino   UUID DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_user UUID;
BEGIN
  v_user := auth.uid();
  INSERT INTO movimientos_almacen
    (tipo, articulo_id, almacen_origen_id, almacen_destino_id,
     ubicacion_origen_id, ubicacion_destino_id, cantidad, obra_id, observaciones, created_by)
  VALUES
    ('traslado_salida',  p_articulo_id, p_almacen_origen_id, NULL,
     p_ubicacion_origen, NULL, p_cantidad, p_obra_id, p_observaciones, v_user),
    ('traslado_entrada', p_articulo_id, NULL, p_almacen_destino_id,
     NULL, p_ubicacion_destino, p_cantidad, p_obra_id, p_observaciones, v_user);
END;
$$;


-- =============================================================================
-- 8. ALERTAS: vista de articulos con stock bajo minimo o caducidad proxima
-- =============================================================================

CREATE OR REPLACE VIEW v_alertas_almacen AS
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


-- =============================================================================
-- 9. TRIGGERS DE AUDITORIA
-- =============================================================================

DROP TRIGGER IF EXISTS audit_proveedores ON proveedores;
CREATE TRIGGER audit_proveedores AFTER INSERT OR UPDATE OR DELETE ON proveedores
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

DROP TRIGGER IF EXISTS audit_almacenes ON almacenes;
CREATE TRIGGER audit_almacenes AFTER INSERT OR UPDATE OR DELETE ON almacenes
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

DROP TRIGGER IF EXISTS audit_articulos ON articulos;
CREATE TRIGGER audit_articulos AFTER INSERT OR UPDATE OR DELETE ON articulos
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

DROP TRIGGER IF EXISTS audit_ubicaciones_stock ON ubicaciones_stock;
CREATE TRIGGER audit_ubicaciones_stock AFTER INSERT OR UPDATE OR DELETE ON ubicaciones_stock
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

DROP TRIGGER IF EXISTS audit_movimientos_almacen ON movimientos_almacen;
CREATE TRIGGER audit_movimientos_almacen AFTER INSERT ON movimientos_almacen
  FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();


-- =============================================================================
-- 10. ELIMINAR TABLAS LEGACY (datos preservados en _legacy_*)
--     Se eliminan en este orden para respetar las FK.
-- =============================================================================

DROP TABLE IF EXISTS parte_maquinaria CASCADE;
DROP TABLE IF EXISTS parte_materiales  CASCADE;

-- Eliminar asignaciones de tipo maquinaria y material del planificador
-- (los recursos humanos y vehiculos se mantienen)
DELETE FROM asignaciones WHERE recurso_tipo IN ('maquinaria', 'material');

-- Ahora ya se pueden eliminar las tablas maestro
DROP TABLE IF EXISTS maquinaria CASCADE;
DROP TABLE IF EXISTS materiales  CASCADE;


-- =============================================================================
-- 11. CRON: notificacion diaria de alertas (requiere pg_cron + pg_net)
--     Si no estan disponibles, las alertas se consultan via v_alertas_almacen.
-- =============================================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Verificar alertas cada manana a las 07:00 UTC (08:00/09:00 Madrid)
    PERFORM cron.schedule(
      'alertas-almacen-diarias',
      '0 7 * * *',
      $cron$
        INSERT INTO audit_log (accion, entidad, modulo, descripcion, resultado, origen)
        SELECT 'crear', 'almacen_alertas', 'almacen',
               'Alertas activas: ' || COUNT(*) || ' articulos',
               'exito', 'rpc_manual'
        FROM v_alertas_almacen;
      $cron$
    );
  END IF;
END $$;


-- =============================================================================
-- FIN MIGRACION 030
-- =============================================================================
