-- =============================================================================
-- ObrasPlan -- Migracion 035: foto_url en articulos
-- =============================================================================
-- El bucket 'fotos' ya existe (migracion 001).
-- Solo anhadimos la columna foto_url a articulos.
-- La cobertura de auditoria ya esta cubierta por audit_articulos (migracion 030).
-- =============================================================================

ALTER TABLE articulos
  ADD COLUMN IF NOT EXISTS foto_url TEXT;

-- Politica de storage para el bucket fotos (si no existe ya):
-- Los usuarios autenticados pueden subir fotos de articulos.
INSERT INTO storage.buckets (id, name, public)
VALUES ('fotos', 'fotos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- RLS Storage: permitir subir fotos a usuarios autenticados
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'fotos_articulos_insert'
  ) THEN
    CREATE POLICY "fotos_articulos_insert" ON storage.objects
      FOR INSERT WITH CHECK (bucket_id = 'fotos' AND auth.role() = 'authenticated');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'fotos_articulos_select'
  ) THEN
    CREATE POLICY "fotos_articulos_select" ON storage.objects
      FOR SELECT USING (bucket_id = 'fotos');
  END IF;
END $$;

-- =============================================================================
-- FIN MIGRACION 035
-- =============================================================================
