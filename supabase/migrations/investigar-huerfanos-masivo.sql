-- =============================================================================
-- INVESTIGACION: por que hay tantos usuarios huerfanos
-- =============================================================================

-- PASO A: Cruzar con recursos_humanos usando TRIM y LOWER por si hay
-- espacios o mayusculas distintas que rompan el match exacto
SELECT
  au.id,
  au.email           AS auth_email,
  au.created_at      AS auth_created,
  rh.id              AS recurso_id,
  rh.nombre          AS recurso_nombre,
  rh.email           AS recurso_email,
  rh.activo          AS recurso_activo
FROM auth.users au
LEFT JOIN public.users u  ON u.id = au.id
LEFT JOIN public.recursos_humanos rh
  ON LOWER(TRIM(rh.email)) = LOWER(TRIM(au.email))
WHERE u.id IS NULL
ORDER BY au.created_at;

-- =============================================================================
-- PASO B: Ver si TODOS los usuarios de la empresa estan afectados,
-- o solo una parte (esto nos dice si fue algo puntual o algo sistemico)
-- =============================================================================

SELECT
  (SELECT COUNT(*) FROM auth.users) AS total_auth_users,
  (SELECT COUNT(*) FROM public.users) AS total_public_users,
  (SELECT COUNT(*) FROM auth.users au
     LEFT JOIN public.users u ON u.id = au.id
     WHERE u.id IS NULL) AS huerfanos_sin_perfil;

-- =============================================================================
-- PASO C: Ver si existe una copia de seguridad en algun lado -- comprobar
-- si audit_log tiene un registro de "eliminar" en users hecho recientemente
-- que nos diga si esto fue una accion masiva
-- =============================================================================

SELECT id, accion, entidad, descripcion, resultado, origen, created_at
FROM audit_log
WHERE entidad = 'users'
ORDER BY created_at DESC
LIMIT 30;
