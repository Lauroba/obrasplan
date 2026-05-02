-- =============================================================================
-- ObrasPlan — Migración 3: Fotos en maestros + orden de obras en Gantt
-- Ejecutar en Supabase SQL Editor
-- =============================================================================

-- 1. Añadir foto_url a todos los maestros
ALTER TABLE recursos_humanos ADD COLUMN IF NOT EXISTS foto_url TEXT;
ALTER TABLE maquinaria ADD COLUMN IF NOT EXISTS foto_url TEXT;
ALTER TABLE vehiculos ADD COLUMN IF NOT EXISTS foto_url TEXT;
ALTER TABLE materiales ADD COLUMN IF NOT EXISTS foto_url TEXT;

-- 2. Añadir orden_gantt a obras (para reordenar filas)
ALTER TABLE obras ADD COLUMN IF NOT EXISTS orden_gantt INTEGER NOT NULL DEFAULT 0;

-- 3. Inicializar orden según id existente
UPDATE obras SET orden_gantt = sub.rn
FROM (SELECT id, ROW_NUMBER() OVER (ORDER BY created_at) as rn FROM obras) sub
WHERE obras.id = sub.id;

-- 4. Crear bucket público para avatares/fotos de maestros
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 5. Políticas de storage para avatars (público para lectura, autenticado para escritura)
CREATE POLICY "avatars_public_read" ON storage.objects FOR SELECT USING (bucket_id = 'avatars');
CREATE POLICY "avatars_auth_insert" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'avatars' AND auth.role() = 'authenticated'
);
CREATE POLICY "avatars_auth_update" ON storage.objects FOR UPDATE USING (
  bucket_id = 'avatars' AND auth.role() = 'authenticated'
);
CREATE POLICY "avatars_auth_delete" ON storage.objects FOR DELETE USING (
  bucket_id = 'avatars' AND auth.role() = 'authenticated'
);
