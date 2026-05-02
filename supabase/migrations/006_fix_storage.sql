-- =============================================================================
-- ObrasPlan — Migración 6: Arreglar políticas de storage para documentos
-- Ejecutar en Supabase SQL Editor
-- =============================================================================

-- Recrear bucket documentos como público para lectura
UPDATE storage.buckets SET public = true WHERE id = 'documentos';
UPDATE storage.buckets SET public = true WHERE id = 'fotos';

-- Eliminar políticas anteriores si existen (pueden dar error, ignorar)
DROP POLICY IF EXISTS "docs_storage_select" ON storage.objects;
DROP POLICY IF EXISTS "docs_storage_insert" ON storage.objects;
DROP POLICY IF EXISTS "docs_storage_delete" ON storage.objects;

-- Crear políticas permisivas para usuarios autenticados
CREATE POLICY "storage_select_all" ON storage.objects FOR SELECT USING (true);

CREATE POLICY "storage_insert_auth" ON storage.objects FOR INSERT WITH CHECK (
  auth.role() = 'authenticated'
);

CREATE POLICY "storage_update_auth" ON storage.objects FOR UPDATE USING (
  auth.role() = 'authenticated'
);

CREATE POLICY "storage_delete_auth" ON storage.objects FOR DELETE USING (
  auth.role() = 'authenticated'
);
