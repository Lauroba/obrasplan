-- =============================================================================
-- ObrasPlan -- Migracion 029: Estados automaticos de obra por asignaciones
-- Ejecutar en Supabase SQL Editor
-- =============================================================================
--
-- Logica:
--   Hoy (hora Madrid) con asignacion activa  -> "3-En ejecucion"
--   Sin hoy pero con futuras                 -> "2-Planificada"
--   Solo pasadas                             -> "4-Terminada"
--   Sin ninguna asignacion                  -> "1-A planificar"
--
-- Estados protegidos (el automatismo no los sobreescribe):
--   "En repaso" y cualquier otro no incluido en los 4 automaticos.
--   Las obras archivadas tambien se saltan.
--
-- COBERTURA DE AUDITORIA:
--   Las actualizaciones de estado pasan por UPDATE en obras, que ya tiene
--   trigger audit_obras (migracion 008). No se necesita trigger adicional.
-- =============================================================================


-- =============================================================================
-- A) INSERTAR LOS 4 ESTADOS AUTOMATICOS
-- =============================================================================

INSERT INTO estados_obra (nombre, color) VALUES
  ('1-A planificar', '#6B7280'),
  ('2-Planificada',  '#8B5CF6'),
  ('3-En ejecucion', '#22C55E'),
  ('4-Terminada',    '#3B82F6')
ON CONFLICT (nombre) DO NOTHING;


-- =============================================================================
-- B) FUNCION: calcular_estado_obra(obra_id)
--    Devuelve el UUID del estado que le corresponde segun asignaciones.
--    Devuelve NULL si la obra debe ser ignorada (protegida).
-- =============================================================================

CREATE OR REPLACE FUNCTION calcular_estado_obra(p_obra_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_hoy          DATE;
  v_estado_actual TEXT;
  v_tiene_hoy    BOOLEAN;
  v_tiene_futura BOOLEAN;
  v_tiene_pasada BOOLEAN;
  v_nuevo_nombre  TEXT;
  v_nuevo_id      UUID;
BEGIN
  -- Fecha de hoy en zona horaria de Espana peninsular
  v_hoy := (NOW() AT TIME ZONE 'Europe/Madrid')::DATE;

  -- Estado actual de la obra (nombre del estado)
  SELECT eo.nombre INTO v_estado_actual
  FROM obras o
  LEFT JOIN estados_obra eo ON eo.id = o.estado_obra_id
  WHERE o.id = p_obra_id;

  -- Proteger estados manuales: si el estado actual NO es uno de los 4
  -- automaticos, devolver NULL (no tocar esta obra).
  IF v_estado_actual IS NOT NULL AND v_estado_actual NOT IN (
    '1-A planificar', '2-Planificada', '3-En ejecucion', '4-Terminada'
  ) THEN
    RETURN NULL;
  END IF;

  -- Comprobar asignaciones
  SELECT EXISTS(
    SELECT 1 FROM asignaciones
    WHERE obra_id = p_obra_id
      AND fecha_inicio <= v_hoy
      AND fecha_fin    >= v_hoy
  ) INTO v_tiene_hoy;

  SELECT EXISTS(
    SELECT 1 FROM asignaciones
    WHERE obra_id = p_obra_id
      AND fecha_inicio > v_hoy
  ) INTO v_tiene_futura;

  SELECT EXISTS(
    SELECT 1 FROM asignaciones
    WHERE obra_id = p_obra_id
      AND fecha_fin < v_hoy
  ) INTO v_tiene_pasada;

  -- Aplicar prioridad
  IF v_tiene_hoy THEN
    v_nuevo_nombre := '3-En ejecucion';
  ELSIF v_tiene_futura THEN
    v_nuevo_nombre := '2-Planificada';
  ELSIF v_tiene_pasada THEN
    v_nuevo_nombre := '4-Terminada';
  ELSE
    v_nuevo_nombre := '1-A planificar';
  END IF;

  SELECT id INTO v_nuevo_id FROM estados_obra WHERE nombre = v_nuevo_nombre;
  RETURN v_nuevo_id;
END;
$$;


-- =============================================================================
-- C) FUNCION: recalcular_estado_obra_trigger()
--    Llamada por los triggers de asignaciones.
-- =============================================================================

CREATE OR REPLACE FUNCTION recalcular_estado_obra_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_obra_id UUID;
  v_nuevo_id UUID;
BEGIN
  -- Obtener obra_id segun operacion
  IF TG_OP = 'DELETE' THEN
    v_obra_id := OLD.obra_id;
  ELSE
    v_obra_id := NEW.obra_id;
    -- Si cambia de obra, recalcular tambien la antigua
    IF TG_OP = 'UPDATE' AND OLD.obra_id <> NEW.obra_id THEN
      v_nuevo_id := calcular_estado_obra(OLD.obra_id);
      IF v_nuevo_id IS NOT NULL THEN
        UPDATE obras SET estado_obra_id = v_nuevo_id, updated_at = now()
        WHERE id = OLD.obra_id AND (estado_obra_id IS DISTINCT FROM v_nuevo_id);
      END IF;
    END IF;
  END IF;

  v_nuevo_id := calcular_estado_obra(v_obra_id);
  IF v_nuevo_id IS NOT NULL THEN
    UPDATE obras SET estado_obra_id = v_nuevo_id, updated_at = now()
    WHERE id = v_obra_id AND (estado_obra_id IS DISTINCT FROM v_nuevo_id);
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;


-- =============================================================================
-- D) TRIGGERS EN ASIGNACIONES
-- =============================================================================

DROP TRIGGER IF EXISTS trg_estado_obra_asignacion ON asignaciones;
CREATE TRIGGER trg_estado_obra_asignacion
  AFTER INSERT OR UPDATE OR DELETE ON asignaciones
  FOR EACH ROW EXECUTE FUNCTION recalcular_estado_obra_trigger();


-- =============================================================================
-- E) FUNCION: recalcular_estados_todas_obras()
--    Recalcula y actualiza todas las obras no archivadas y no protegidas.
--    Devuelve cuantas se actualizaron.
-- =============================================================================

CREATE OR REPLACE FUNCTION recalcular_estados_todas_obras()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_obra    RECORD;
  v_nuevo   UUID;
  v_count   INTEGER := 0;
BEGIN
  FOR v_obra IN
    SELECT id FROM obras WHERE archivada = false
  LOOP
    v_nuevo := calcular_estado_obra(v_obra.id);
    IF v_nuevo IS NOT NULL THEN
      UPDATE obras
      SET estado_obra_id = v_nuevo, updated_at = now()
      WHERE id = v_obra.id
        AND (estado_obra_id IS DISTINCT FROM v_nuevo);
      IF FOUND THEN v_count := v_count + 1; END IF;
    END IF;
  END LOOP;
  RETURN v_count;
END;
$$;


-- =============================================================================
-- F) CRON: recalcular cada noche a las 00:05 (hora UTC, = 01:05 Madrid invierno
--    / 02:05 Madrid verano). Requiere pg_cron habilitado en Supabase.
--    Si no tienes pg_cron, ejecuta manualmente: SELECT recalcular_estados_todas_obras();
-- =============================================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'recalcular-estados-obras',
      '5 0 * * *',
      $cron$SELECT recalcular_estados_todas_obras();$cron$
    );
  END IF;
END $$;


-- =============================================================================
-- G) ACTUALIZACION MASIVA INMEDIATA DE TODAS LAS OBRAS EXISTENTES
-- =============================================================================

SELECT recalcular_estados_todas_obras() AS obras_actualizadas;


-- =============================================================================
-- H) TRIGGER AUDITORIA (hueco detectado: asignaciones ya tenia trigger
--    desde migracion 026, pero recalcular_estados_todas_obras es una RPC
--    que actualiza obras directamente, quedando cubierta por audit_obras)
-- =============================================================================
-- No se requiere trigger adicional: el UPDATE sobre obras ya dispara
-- audit_obras (migracion 008), que registra el cambio de estado_obra_id
-- con valor_anterior y valor_nuevo automaticamente.

-- =============================================================================
-- FIN MIGRACION 029
-- =============================================================================
