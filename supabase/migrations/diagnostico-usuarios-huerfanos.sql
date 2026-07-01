-- =============================================================================
-- DIAGNOSTICO Y REPARACION: usuarios huerfanos en auth.users
-- Ejecutar en Supabase SQL Editor, PASO A PASO (no todo de golpe)
-- =============================================================================

-- =============================================================================
-- PASO 1: Cruzar cada ID huerfano con recursos_humanos por email
--         para saber el nombre real de cada uno y si tiene ficha de trabajador
-- =============================================================================

SELECT
  au.id,
  au.email,
  au.created_at        AS auth_created_at,
  au.last_sign_in_at,
  rh.id                 AS recurso_id,
  rh.nombre             AS nombre_recurso,
  rh.activo             AS recurso_activo
FROM auth.users au
LEFT JOIN public.users u  ON u.id = au.id
LEFT JOIN public.recursos_humanos rh ON LOWER(rh.email) = LOWER(au.email)
WHERE u.id IS NULL
ORDER BY au.created_at;

-- =============================================================================
-- Revisa el resultado. Para cada fila tienes dos opciones:
--
--   OPCION A — Restaurar el perfil (si fue un borrado accidental o el usuario
--              SIGUE necesitando acceso a la app):
--              usa el PASO 2 con ese id/email/nombre concretos.
--
--   OPCION B — Terminar de eliminarlo (si de verdad quieres que ese usuario
--              desaparezca del todo, incluido el acceso):
--              usa el PASO 3 con ese id concreto.
-- =============================================================================


-- =============================================================================
-- PASO 2: RESTAURAR un perfil concreto en public.users
-- Sustituye los valores de ejemplo por los reales del PASO 1.
-- recurso_id puede ser NULL si esa persona no tiene ficha de recurso humano.
-- =============================================================================

-- Ejemplo (NO ejecutar tal cual, sustituye el UUID y datos reales):
-- INSERT INTO public.users (id, email, nombre, role, recurso_id, activo)
-- VALUES (
--   '6d1dc1db-cc82-48df-b0e8-7dfb312b895c',  -- id de auth.users
--   'ortegalagojon@gmail.com',                -- email exacto de auth.users
--   'Nombre Apellido',                        -- nombre real
--   'partes',                                 -- role: admin / partes / lectura
--   NULL,                                     -- recurso_id si tiene ficha en recursos_humanos, si no NULL
--   true                                      -- activo
-- );


-- =============================================================================
-- PASO 3: ELIMINAR DEFINITIVAMENTE un usuario huerfano (solo Auth, ya que
-- public.users no tiene fila para el). Esto requiere la Admin API, no SQL
-- puro, porque auth.users no se puede tocar directamente con DELETE desde
-- el SQL Editor en Supabase (esta gestionado por el servicio de Auth).
--
-- Para terminar de borrar un usuario huerfano, ve a:
--   Supabase Dashboard -> Authentication -> Users
--   Busca el email de la fila que quieres eliminar
--   Pulsa los tres puntos (...) -> Delete user
--
-- Esto SI funciona desde el panel porque usa la Admin API correctamente,
-- y como ya no tiene fila en public.users, no debería toparse con las
-- mismas restricciones de FK que el endpoint de la app.
-- =============================================================================


-- =============================================================================
-- PASO 4 (opcional): si quieres identificar rapidamente cual de los 10
-- es Eneko u otro admin para evitar borrarlo sin querer
-- =============================================================================

SELECT au.id, au.email
FROM auth.users au
LEFT JOIN public.users u ON u.id = au.id
WHERE u.id IS NULL
  AND au.email ILIKE '%eneko%' OR au.email ILIKE '%loynek%';
