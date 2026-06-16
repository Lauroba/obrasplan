-- =============================================================================
-- ObrasPlan — Migración 19: Modelo completo clientes/contactos/obras
-- =============================================================================

-- 1. Nuevos campos en clientes
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS tipo_cliente TEXT;
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS web TEXT;
-- nif ya existe, lo usamos como CIF/NIF en la UI

-- 2. Nuevos campos en contactos (tabla ya existe de migración 018)
ALTER TABLE contactos ADD COLUMN IF NOT EXISTS notas TEXT;

-- 3. Tabla N:N obra_contactos (múltiples contactos por obra)
CREATE TABLE IF NOT EXISTS obra_contactos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  obra_id UUID NOT NULL REFERENCES obras(id) ON DELETE CASCADE,
  contacto_id UUID NOT NULL REFERENCES contactos(id) ON DELETE CASCADE,
  rol TEXT NOT NULL DEFAULT 'principal',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(obra_id, contacto_id)
);

ALTER TABLE obra_contactos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "obra_contactos_select" ON obra_contactos FOR SELECT USING (true);
CREATE POLICY "obra_contactos_all" ON obra_contactos FOR ALL USING (auth.role() = 'authenticated');
CREATE INDEX IF NOT EXISTS idx_obra_contactos_obra ON obra_contactos(obra_id);
CREATE INDEX IF NOT EXISTS idx_obra_contactos_contacto ON obra_contactos(contacto_id);

-- 4. Migrar datos legacy: crear contactos desde clientes que tengan campo contacto
INSERT INTO contactos (cliente_id, nombre, email, telefono)
SELECT c.id, c.contacto, c.email, c.telefono
FROM clientes c
WHERE c.contacto IS NOT NULL AND c.contacto != ''
AND NOT EXISTS (
  SELECT 1 FROM contactos ct WHERE ct.cliente_id = c.id AND ct.nombre = c.contacto
);
