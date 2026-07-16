-- ============================================================
-- 043_asignaciones_estado_snapshot.sql
-- Snapshot del estado de la obra al crear cada asignación
-- ============================================================

-- 1. Añadir columnas a asignaciones
ALTER TABLE asignaciones
  ADD COLUMN IF NOT EXISTS estado_obra_snapshot_id    UUID REFERENCES estados_obra(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS estado_obra_snapshot_nombre TEXT,
  ADD COLUMN IF NOT EXISTS estado_obra_snapshot_color  TEXT,
  ADD COLUMN IF NOT EXISTS snapshot_estimado           BOOLEAN DEFAULT false;
-- snapshot_estimado = true cuando el dato fue reconstruido, no registrado en tiempo real

COMMENT ON COLUMN asignaciones.estado_obra_snapshot_id     IS 'Estado de la obra en el momento de crear la asignación';
COMMENT ON COLUMN asignaciones.estado_obra_snapshot_nombre IS 'Nombre del estado (snapshot inmutable)';
COMMENT ON COLUMN asignaciones.estado_obra_snapshot_color  IS 'Color del estado (snapshot inmutable)';
COMMENT ON COLUMN asignaciones.snapshot_estimado           IS 'true = reconstruido desde audit_log o estado actual, no registrado en tiempo real';

-- 2. Trigger automático: capturar estado al INSERT en asignaciones
CREATE OR REPLACE FUNCTION asignaciones_snapshot_estado()
RETURNS TRIGGER AS $$
DECLARE
  _estado_id    UUID;
  _estado_nombre TEXT;
  _estado_color  TEXT;
BEGIN
  -- Solo en INSERT y solo si no viene ya con snapshot
  IF TG_OP = 'INSERT' AND NEW.estado_obra_snapshot_id IS NULL THEN
    -- Leer estado actual de la obra
    SELECT o.estado_obra_id, e.nombre, e.color
      INTO _estado_id, _estado_nombre, _estado_color
      FROM obras o
      LEFT JOIN estados_obra e ON e.id = o.estado_obra_id
     WHERE o.id = NEW.obra_id;

    NEW.estado_obra_snapshot_id     := _estado_id;
    NEW.estado_obra_snapshot_nombre := _estado_nombre;
    NEW.estado_obra_snapshot_color  := _estado_color;
    NEW.snapshot_estimado           := false;  -- capturado en tiempo real
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_asignaciones_snapshot_estado ON asignaciones;
CREATE TRIGGER trg_asignaciones_snapshot_estado
  BEFORE INSERT ON asignaciones
  FOR EACH ROW EXECUTE FUNCTION asignaciones_snapshot_estado();

-- 3. Backfill: reconstruir estado histórico desde audit_log
-- Estrategia:
--   a) Buscar en audit_log el último UPDATE de estado en obras ANTERIOR a created_at de la asignación
--   b) Si no hay registro → usar el estado actual de la obra
--   c) Marcar snapshot_estimado = true en todos los casos de backfill

UPDATE asignaciones a
SET
  estado_obra_snapshot_id     = estado_historico.id,
  estado_obra_snapshot_nombre = estado_historico.nombre,
  estado_obra_snapshot_color  = estado_historico.color,
  snapshot_estimado           = true
FROM (
  SELECT
    a2.id AS asignacion_id,
    COALESCE(
      -- Intentar recuperar desde audit_log: último cambio de estado ANTES de la asignación
      (
        SELECT (al.valor_nuevo->>'estado_obra_id')::uuid
          FROM audit_log al
         WHERE al.entidad = 'obras'
           AND al.entidad_id = a2.obra_id::text
           AND al.accion = 'editar'
           AND (al.valor_nuevo->>'estado_obra_id') IS NOT NULL
           AND al.created_at <= a2.created_at
         ORDER BY al.created_at DESC
         LIMIT 1
      ),
      -- Fallback: estado actual de la obra
      o.estado_obra_id
    ) AS estado_id_calculado
  FROM asignaciones a2
  JOIN obras o ON o.id = a2.obra_id
  WHERE a2.estado_obra_snapshot_id IS NULL  -- solo las que no tienen snapshot
) sub
JOIN estados_obra estado_historico ON estado_historico.id = sub.estado_id_calculado
WHERE a.id = sub.asignacion_id;

-- Para asignaciones cuya obra no tiene estado (NULL), dejar snapshot_estimado = true y columnas NULL
UPDATE asignaciones
SET snapshot_estimado = true
WHERE estado_obra_snapshot_id IS NULL
  AND created_at < now();  -- excluye futuras inserciones que usarán el trigger

-- 4. Índice para consultas por obra
CREATE INDEX IF NOT EXISTS idx_asignaciones_obra_snapshot
  ON asignaciones(obra_id, estado_obra_snapshot_id);
