-- =============================================================================
-- DIAGNOSTICO: Por que falla INSERT en asignaciones
-- Ejecutar en Supabase SQL Editor con Role: postgres
-- =============================================================================

-- 1. Triggers activos en asignaciones
SELECT trigger_name, event_manipulation, action_statement, action_timing
FROM information_schema.triggers
WHERE event_object_table = 'asignaciones'
ORDER BY trigger_name;

-- 2. Estados de obra existentes (calcular_estado_obra los necesita)
SELECT id, nombre FROM estados_obra ORDER BY nombre;

-- 3. Probar calcular_estado_obra con una obra real
DO $$
DECLARE
  v_obra_id UUID;
  v_resultado UUID;
BEGIN
  SELECT id INTO v_obra_id FROM obras WHERE activo = true LIMIT 1;
  RAISE NOTICE 'Probando con obra: %', v_obra_id;
  v_resultado := calcular_estado_obra(v_obra_id);
  RAISE NOTICE 'Resultado calcular_estado_obra: %', v_resultado;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ERROR en calcular_estado_obra: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
END $$;

-- 4. INSERT de prueba directo (como postgres, sin RLS)
-- Si esto funciona, el problema es RLS o el cliente
-- Si falla, el problema es el trigger
DO $$
DECLARE
  v_obra_id UUID;
  v_recurso_id UUID;
  v_new_id UUID;
BEGIN
  SELECT id INTO v_obra_id FROM obras WHERE activo = true LIMIT 1;
  SELECT id INTO v_recurso_id FROM recursos_humanos WHERE activo = true LIMIT 1;
  RAISE NOTICE 'Insertando: obra=%, recurso=%', v_obra_id, v_recurso_id;

  INSERT INTO asignaciones (obra_id, recurso_tipo, recurso_id, fecha_inicio, fecha_fin)
  VALUES (v_obra_id, 'humano', v_recurso_id, CURRENT_DATE, CURRENT_DATE)
  RETURNING id INTO v_new_id;

  RAISE NOTICE 'INSERT OK, id=%', v_new_id;

  DELETE FROM asignaciones WHERE id = v_new_id;
  RAISE NOTICE 'DELETE OK - limpieza completada';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ERROR: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
END $$;
