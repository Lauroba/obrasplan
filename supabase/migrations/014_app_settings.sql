-- =============================================================================
-- ObrasPlan — Migración 14: Configuración de partes y app
-- =============================================================================

CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "settings_select" ON app_settings FOR SELECT USING (true);
CREATE POLICY "settings_write" ON app_settings FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- Default partes settings
INSERT INTO app_settings (key, value) VALUES (
  'partes_email',
  '{"cc_emails": [], "empresa_nombre": "LOYNEK Soluciones Técnicas", "footer_text": "Este email ha sido enviado automáticamente desde ObrasPlan", "color_primario": "#DC2626"}'
) ON CONFLICT (key) DO NOTHING;
