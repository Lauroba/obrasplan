-- =============================================================================
-- ObrasPlan — Datos de prueba (Seed)
-- Ejecutar después de crear un usuario admin en Supabase Auth
-- =============================================================================

-- Clientes de ejemplo
INSERT INTO clientes (id, nombre, contacto, telefono, email, direccion) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'Ayuntamiento de Madrid', 'María García', '911234567', 'maria@madrid.es', 'Plaza de Cibeles, 1, Madrid'),
  ('a0000000-0000-0000-0000-000000000002', 'Constructora Ibérica S.L.', 'Pedro López', '912345678', 'pedro@consiberica.es', 'Calle Gran Vía, 45, Madrid'),
  ('a0000000-0000-0000-0000-000000000003', 'Comunidad Propietarios Alcobendas', 'Ana Martínez', '913456789', 'ana@cpropietarios.es', 'Av. de España, 12, Alcobendas'),
  ('a0000000-0000-0000-0000-000000000004', 'Mercadona S.A.', 'Carlos Ruiz', '914567890', 'carlos.ruiz@mercadona.es', 'C/ Valencia, 5, Getafe'),
  ('a0000000-0000-0000-0000-000000000005', 'Hotel Meliá Sol', 'Laura Fernández', '915678901', 'laura@meliasol.es', 'Paseo de la Castellana, 78, Madrid');

-- Recursos humanos
INSERT INTO recursos_humanos (id, nombre, perfil, telefono, email) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'Juan García Pérez', 'Encargado de obra', '600111001', 'juan@loynek.es'),
  ('b0000000-0000-0000-0000-000000000002', 'Pedro López Martín', 'Oficial 1ª', '600111002', 'pedro@loynek.es'),
  ('b0000000-0000-0000-0000-000000000003', 'Ana Martínez Ruiz', 'Oficial 2ª', '600111003', 'ana@loynek.es'),
  ('b0000000-0000-0000-0000-000000000004', 'Carlos Fernández Gil', 'Peón especialista', '600111004', 'carlos@loynek.es'),
  ('b0000000-0000-0000-0000-000000000005', 'Miguel Torres Sanz', 'Peón', '600111005', 'miguel@loynek.es'),
  ('b0000000-0000-0000-0000-000000000006', 'Lucía Navarro Díaz', 'Oficial 1ª', '600111006', 'lucia@loynek.es'),
  ('b0000000-0000-0000-0000-000000000007', 'David Romero Vega', 'Encargado de obra', '600111007', 'david@loynek.es'),
  ('b0000000-0000-0000-0000-000000000008', 'Sara Molina Cruz', 'Oficial 2ª', '600111008', 'sara@loynek.es'),
  ('b0000000-0000-0000-0000-000000000009', 'Andrés Jiménez Ramos', 'Peón especialista', '600111009', 'andres@loynek.es'),
  ('b0000000-0000-0000-0000-000000000010', 'Elena Ruiz Moreno', 'Peón', '600111010', 'elena@loynek.es'),
  ('b0000000-0000-0000-0000-000000000011', 'Raúl Serrano López', 'Oficial 1ª', '600111011', 'raul@loynek.es'),
  ('b0000000-0000-0000-0000-000000000012', 'Patricia Díaz Gómez', 'Peón', '600111012', 'patricia@loynek.es'),
  ('b0000000-0000-0000-0000-000000000013', 'Óscar Blanco Herrero', 'Oficial 2ª', '600111013', 'oscar@loynek.es'),
  ('b0000000-0000-0000-0000-000000000014', 'Marta Iglesias Prieto', 'Peón especialista', '600111014', 'marta@loynek.es'),
  ('b0000000-0000-0000-0000-000000000015', 'Fernando Castro León', 'Peón', '600111015', 'fernando@loynek.es');

-- Vehículos
INSERT INTO vehiculos (id, nombre, matricula, tipo, estado) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'Furgón Ford Transit', '1234 ABC', 'Furgoneta', 'disponible'),
  ('c0000000-0000-0000-0000-000000000002', 'Camión MAN 18t', '5678 DEF', 'Camión', 'disponible'),
  ('c0000000-0000-0000-0000-000000000003', 'Furgón Renault Master', '9012 GHI', 'Furgoneta', 'disponible'),
  ('c0000000-0000-0000-0000-000000000004', 'Pick-up Toyota Hilux', '3456 JKL', 'Pick-up', 'disponible'),
  ('c0000000-0000-0000-0000-000000000005', 'Camión Iveco 12t', '7890 MNO', 'Camión', 'disponible'),
  ('c0000000-0000-0000-0000-000000000006', 'Furgón Mercedes Sprinter', '2345 PQR', 'Furgoneta', 'disponible');

-- Maquinaria (selección de 20 de las 50)
INSERT INTO maquinaria (id, nombre, tipo, estado) VALUES
  ('d0000000-0000-0000-0000-000000000001', 'Retroexcavadora CAT 420F', 'Movimiento de tierras', 'disponible'),
  ('d0000000-0000-0000-0000-000000000002', 'Mini excavadora Kubota KX040', 'Movimiento de tierras', 'disponible'),
  ('d0000000-0000-0000-0000-000000000003', 'Dumper Ausa D150', 'Transporte', 'disponible'),
  ('d0000000-0000-0000-0000-000000000004', 'Hormigonera 250L', 'Hormigón', 'disponible'),
  ('d0000000-0000-0000-0000-000000000005', 'Compactador vibrante Bomag', 'Compactación', 'disponible'),
  ('d0000000-0000-0000-0000-000000000006', 'Martillo hidráulico Atlas', 'Demolición', 'disponible'),
  ('d0000000-0000-0000-0000-000000000007', 'Generador 50 kVA', 'Energía', 'disponible'),
  ('d0000000-0000-0000-0000-000000000008', 'Compresor Atlas Copco', 'Neumática', 'disponible'),
  ('d0000000-0000-0000-0000-000000000009', 'Plataforma elevadora 12m', 'Elevación', 'disponible'),
  ('d0000000-0000-0000-0000-000000000010', 'Radial de corte Stihl', 'Corte', 'disponible'),
  ('d0000000-0000-0000-0000-000000000011', 'Vibradora de hormigón', 'Hormigón', 'disponible'),
  ('d0000000-0000-0000-0000-000000000012', 'Sierra de mesa', 'Corte', 'disponible'),
  ('d0000000-0000-0000-0000-000000000013', 'Taladro columna Bosch', 'Taladro', 'disponible'),
  ('d0000000-0000-0000-0000-000000000014', 'Soldadora MIG Lincoln', 'Soldadura', 'disponible'),
  ('d0000000-0000-0000-0000-000000000015', 'Bomba de achique', 'Bombeo', 'disponible'),
  ('d0000000-0000-0000-0000-000000000016', 'Nivel láser Leica', 'Topografía', 'disponible'),
  ('d0000000-0000-0000-0000-000000000017', 'Cizalla hidráulica', 'Corte', 'disponible'),
  ('d0000000-0000-0000-0000-000000000018', 'Alisadora de hormigón', 'Hormigón', 'disponible'),
  ('d0000000-0000-0000-0000-000000000019', 'Grupo electrógeno 20 kVA', 'Energía', 'disponible'),
  ('d0000000-0000-0000-0000-000000000020', 'Carretilla elevadora Toyota', 'Elevación', 'disponible');

-- Materiales
INSERT INTO materiales (id, nombre, tipo, unidad) VALUES
  ('e0000000-0000-0000-0000-000000000001', 'Cemento Portland', 'Cementante', 'kg'),
  ('e0000000-0000-0000-0000-000000000002', 'Arena lavada', 'Árido', 'm³'),
  ('e0000000-0000-0000-0000-000000000003', 'Grava 20/40', 'Árido', 'm³'),
  ('e0000000-0000-0000-0000-000000000004', 'Hormigón HA-25', 'Hormigón', 'm³'),
  ('e0000000-0000-0000-0000-000000000005', 'Acero corrugado B500S', 'Acero', 'kg'),
  ('e0000000-0000-0000-0000-000000000006', 'Ladrillo hueco doble', 'Albañilería', 'ud'),
  ('e0000000-0000-0000-0000-000000000007', 'Tubo PVC 110mm', 'Fontanería', 'ml'),
  ('e0000000-0000-0000-0000-000000000008', 'Cable eléctrico 2.5mm', 'Electricidad', 'ml'),
  ('e0000000-0000-0000-0000-000000000009', 'Pintura plástica blanca', 'Pintura', 'l'),
  ('e0000000-0000-0000-0000-000000000010', 'Impermeabilizante', 'Aislamiento', 'kg');

-- Obras de ejemplo
INSERT INTO obras (id, nombre, cliente_id, ubicacion, fecha_inicio, fecha_fin, estado, color) VALUES
  ('f0000000-0000-0000-0000-000000000001', 'Reforma Local Comercial Gran Vía', 'a0000000-0000-0000-0000-000000000002', 'C/ Gran Vía 45, Madrid', '2025-06-01', '2025-07-15', 'planificada', '#DC2626'),
  ('f0000000-0000-0000-0000-000000000002', 'Nave Industrial Getafe', 'a0000000-0000-0000-0000-000000000004', 'Polígono Los Ángeles, Getafe', '2025-06-10', '2025-09-30', 'planificada', '#2563EB'),
  ('f0000000-0000-0000-0000-000000000003', 'Rehabilitación Fachada Alcobendas', 'a0000000-0000-0000-0000-000000000003', 'Av. de España 12, Alcobendas', '2025-06-15', '2025-08-15', 'planificada', '#16A34A'),
  ('f0000000-0000-0000-0000-000000000004', 'Acondicionamiento Oficinas Castellana', 'a0000000-0000-0000-0000-000000000005', 'Paseo de la Castellana 78, Madrid', '2025-07-01', '2025-08-30', 'planificada', '#9333EA'),
  ('f0000000-0000-0000-0000-000000000005', 'Urbanización Plaza Mayor', 'a0000000-0000-0000-0000-000000000001', 'Plaza Mayor s/n, Madrid', '2025-07-15', '2025-10-31', 'planificada', '#EA580C');

-- Fases para las obras
INSERT INTO obra_fases (obra_id, nombre, fecha_inicio, fecha_fin, estado, orden) VALUES
  ('f0000000-0000-0000-0000-000000000001', 'Preparación', '2025-06-01', '2025-06-07', 'pendiente', 1),
  ('f0000000-0000-0000-0000-000000000001', 'Ejecución', '2025-06-08', '2025-07-05', 'pendiente', 2),
  ('f0000000-0000-0000-0000-000000000001', 'Remates', '2025-07-06', '2025-07-12', 'pendiente', 3),
  ('f0000000-0000-0000-0000-000000000001', 'Entrega', '2025-07-13', '2025-07-15', 'pendiente', 4),
  ('f0000000-0000-0000-0000-000000000002', 'Preparación', '2025-06-10', '2025-06-25', 'pendiente', 1),
  ('f0000000-0000-0000-0000-000000000002', 'Ejecución', '2025-06-26', '2025-09-15', 'pendiente', 2),
  ('f0000000-0000-0000-0000-000000000002', 'Remates', '2025-09-16', '2025-09-25', 'pendiente', 3),
  ('f0000000-0000-0000-0000-000000000002', 'Entrega', '2025-09-26', '2025-09-30', 'pendiente', 4);

-- Asignaciones de ejemplo
INSERT INTO asignaciones (obra_id, recurso_tipo, recurso_id, fecha_inicio, fecha_fin) VALUES
  ('f0000000-0000-0000-0000-000000000001', 'humano', 'b0000000-0000-0000-0000-000000000001', '2025-06-01', '2025-07-15'),
  ('f0000000-0000-0000-0000-000000000001', 'humano', 'b0000000-0000-0000-0000-000000000002', '2025-06-01', '2025-07-15'),
  ('f0000000-0000-0000-0000-000000000001', 'humano', 'b0000000-0000-0000-0000-000000000003', '2025-06-01', '2025-07-15'),
  ('f0000000-0000-0000-0000-000000000001', 'vehiculo', 'c0000000-0000-0000-0000-000000000001', '2025-06-01', '2025-07-15'),
  ('f0000000-0000-0000-0000-000000000001', 'maquinaria', 'd0000000-0000-0000-0000-000000000010', '2025-06-01', '2025-07-15'),
  ('f0000000-0000-0000-0000-000000000002', 'humano', 'b0000000-0000-0000-0000-000000000007', '2025-06-10', '2025-09-30'),
  ('f0000000-0000-0000-0000-000000000002', 'humano', 'b0000000-0000-0000-0000-000000000004', '2025-06-10', '2025-09-30'),
  ('f0000000-0000-0000-0000-000000000002', 'humano', 'b0000000-0000-0000-0000-000000000005', '2025-06-10', '2025-09-30'),
  ('f0000000-0000-0000-0000-000000000002', 'humano', 'b0000000-0000-0000-0000-000000000006', '2025-06-10', '2025-09-30'),
  ('f0000000-0000-0000-0000-000000000002', 'humano', 'b0000000-0000-0000-0000-000000000008', '2025-06-10', '2025-09-30'),
  ('f0000000-0000-0000-0000-000000000002', 'vehiculo', 'c0000000-0000-0000-0000-000000000002', '2025-06-10', '2025-09-30'),
  ('f0000000-0000-0000-0000-000000000002', 'vehiculo', 'c0000000-0000-0000-0000-000000000004', '2025-06-10', '2025-09-30'),
  ('f0000000-0000-0000-0000-000000000002', 'maquinaria', 'd0000000-0000-0000-0000-000000000001', '2025-06-10', '2025-09-30'),
  ('f0000000-0000-0000-0000-000000000002', 'maquinaria', 'd0000000-0000-0000-0000-000000000003', '2025-06-10', '2025-09-30'),
  ('f0000000-0000-0000-0000-000000000002', 'maquinaria', 'd0000000-0000-0000-0000-000000000005', '2025-06-10', '2025-09-30');
