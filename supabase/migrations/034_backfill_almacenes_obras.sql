-- =============================================================================
-- ObrasPlan -- Migracion 034: Almacenes para obras existentes (backfill)
-- Ejecutar en Supabase SQL Editor
-- =============================================================================
--
-- CAMBIOS:
--   A) RPC crear_almacen_obra_v2: acepta obras sin num_presupuesto
--      usando OBRA-{primeros 8 chars del UUID} como fallback
--   B) Backfill: crea almacenes para todas las obras (activas + archivadas)
--      que todavia no tengan almacen vinculado
--   C) Actualiza el trigger para usar la nueva RPC con fallback
--
-- COBERTURA DE AUDITORIA:
--   almacenes ya tiene trigger audit_almacenes (migracion 030)
--   Los INSERT del backfill quedan cubiertos automaticamente
-- =============================================================================


-- =============================================================================
-- A) RPC crear_almacen_obra MEJORADA
--    Fallback: si no hay num_presupuesto -> OBRA-{primeros 8 del UUID}
--    Sigue respetando el UNIQUE INDEX idx_almacenes_obra_unique
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
  v_intento       INTEGER := 0;
BEGIN
  SELECT id, nombre, num_presupuesto
  INTO v_obra
  FROM obras
  WHERE id = p_obra_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Obra no encontrada: %', p_obra_id;
  END IF;

  -- Verificar que no existe ya un almacen activo para esta obra
  IF EXISTS (
    SELECT 1 FROM almacenes
    WHERE obra_id = p_obra_id AND es_almacen_obra = true AND activo = true
  ) THEN
    -- Devolver el ID existente en vez de fallar
    SELECT id INTO v_almacen_id FROM almacenes
    WHERE obra_id = p_obra_id AND es_almacen_obra = true AND activo = true
    LIMIT 1;
    RETURN v_almacen_id;
  END IF;

  -- Codigo: OBRA-{num_presupuesto} o OBRA-{primeros 8 del UUID}
  IF v_obra.num_presupuesto IS NOT NULL AND TRIM(v_obra.num_presupuesto) <> '' THEN
    v_codigo := 'OBRA-' || TRIM(v_obra.num_presupuesto);
  ELSE
    v_codigo := 'OBRA-' || UPPER(LEFT(REPLACE(p_obra_id::TEXT, '-', ''), 8));
  END IF;

  v_nombre := 'Almacen obra - ' || v_obra.nombre;

  -- Manejar colision de codigo (aunque rara, puede pasar en el backfill)
  LOOP
    BEGIN
      INSERT INTO almacenes (codigo_almacen, nombre, es_almacen_obra, obra_id, activo)
      VALUES (
        CASE WHEN v_intento = 0 THEN v_codigo ELSE v_codigo || '-' || v_intento END,
        v_nombre,
        true,
        p_obra_id,
        true
      )
      RETURNING id INTO v_almacen_id;
      EXIT; -- Exito
    EXCEPTION WHEN unique_violation THEN
      v_intento := v_intento + 1;
      IF v_intento > 10 THEN
        RAISE EXCEPTION 'No se pudo generar un codigo unico para el almacen de la obra %', p_obra_id;
      END IF;
    END;
  END LOOP;

  RETURN v_almacen_id;
END;
$$;


-- =============================================================================
-- B) BACKFILL: crear almacenes para todas las obras que no tienen uno
--    Incluye obras archivadas (archivada = true)
--    Usa la RPC mejorada que ya maneja duplicados y fallback de codigo
-- =============================================================================

DO $$
DECLARE
  v_obra    RECORD;
  v_created INTEGER := 0;
  v_errors  INTEGER := 0;
BEGIN
  FOR v_obra IN
    SELECT o.id, o.nombre
    FROM obras o
    WHERE NOT EXISTS (
      SELECT 1 FROM almacenes a
      WHERE a.obra_id = o.id
        AND a.es_almacen_obra = true
        AND a.activo = true
    )
    ORDER BY o.created_at
  LOOP
    BEGIN
      PERFORM crear_almacen_obra(v_obra.id);
      v_created := v_created + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'No se pudo crear almacen para obra % (%): %',
        v_obra.nombre, v_obra.id, SQLERRM;
      v_errors := v_errors + 1;
    END;
  END LOOP;

  RAISE NOTICE 'Backfill completado: % almacenes creados, % errores', v_created, v_errors;
END $$;


-- =============================================================================
-- C) ACTUALIZAR TRIGGER en obras para usar la RPC mejorada
--    (ya no falla si no hay num_presupuesto)
-- =============================================================================

CREATE OR REPLACE FUNCTION obras_after_insert_crear_almacen()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  BEGIN
    PERFORM crear_almacen_obra(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'No se pudo crear almacen automatico para obra %: %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_obras_crear_almacen ON obras;
CREATE TRIGGER trg_obras_crear_almacen
  AFTER INSERT ON obras
  FOR EACH ROW EXECUTE FUNCTION obras_after_insert_crear_almacen();


-- =============================================================================
-- D) VERIFICACION: ver resultado del backfill
-- =============================================================================

SELECT
  COUNT(*) FILTER (WHERE EXISTS (
    SELECT 1 FROM almacenes a
    WHERE a.obra_id = o.id AND a.es_almacen_obra = true AND a.activo = true
  )) AS obras_con_almacen,
  COUNT(*) FILTER (WHERE NOT EXISTS (
    SELECT 1 FROM almacenes a
    WHERE a.obra_id = o.id AND a.es_almacen_obra = true AND a.activo = true
  )) AS obras_sin_almacen,
  COUNT(*) AS total_obras
FROM obras o;

-- =============================================================================
-- FIN MIGRACION 034
-- =============================================================================
