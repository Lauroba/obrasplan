# Fix sistema de auditoría — ObrasPlan

## Diagnóstico (resumen)
`tipos_obra` nunca tuvo trigger de auditoría: la tabla se creó fuera de las
migraciones versionadas y se quedó fuera del sistema de logs. Auditando el
resto del esquema se encontraron 7 tablas más en la misma situación (ver
respuesta completa en el chat para el detalle).

## Despliegue automático (recomendado — no requiere tocar archivos a mano)

1. Descarga **este zip completo** en una carpeta cualquiera de tu PC (por
   ejemplo, tu carpeta de Descargas). No hace falta descomprimirlo a mano.
2. En esa carpeta, haz clic derecho sobre `deploy-audit-fix.ps1` →
   **Ejecutar con PowerShell**. Si Windows bloquea el script por política
   de ejecución, abre PowerShell en esa carpeta y ejecuta:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\deploy-audit-fix.ps1
   ```
3. El script localiza automáticamente el .zip de la entrega (debe estar en
   la misma carpeta que el script). Lo descomprime a una carpeta temporal,
   copia todos los archivos a tu repo local
   (`C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan`) con
   los renombres correctos, y hace backup de cualquier archivo que
   sobrescriba (carpeta `.audit-fix-backup-<fecha>` dentro del repo).
4. Parchea automáticamente `src/lib/types/database.ts` (la interfaz
   `AuditLog`) por sustitución de texto exacta — detecta si ya estaba
   aplicado para no duplicarlo si lo ejecutas dos veces.
5. Si quieres que además haga el commit y push, ejecuta con `-GitCommit`:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\deploy-audit-fix.ps1 -GitCommit
   ```
   Te pedirá confirmación (`s`/`n`) antes de hacer push — nunca sube nada
   sin que lo confirmes explícitamente en pantalla.

Si tu carpeta de proyecto está en otra ruta, indícasela:
```powershell
powershell -ExecutionPolicy Bypass -File .\deploy-audit-fix.ps1 -RepoPath "D:\otra\ruta\obrasplan"
```

## Lo único que el script NO puede hacer por ti
Ejecutar SQL en Supabase requiere tus credenciales del panel — no es algo
automatizable desde tu PC local. Tienes que:

1. Abrir el **SQL Editor de Supabase**.
2. Pegar y ejecutar el contenido completo de
   `supabase/migrations/026_audit_complete_fix.sql` (incluido en este zip).
   Es idempotente: si algo falla a mitad puedes reejecutarlo entero sin
   riesgo.

Y, tras el push, **promocionar manualmente a producción en el dashboard de
Vercel** (plan Hobby no promociona automáticamente).

## Archivos de este paquete (referencia, no necesitas tocarlos a mano)

| Archivo en el zip | Destino final en tu repo |
|---|---|
| `supabase/migrations/026_audit_complete_fix.sql` | `supabase/migrations/026_audit_complete_fix.sql` |
| `src/lib/audit/logAuditError.ts` | `src/lib/audit/logAuditError.ts` |
| `src/app/api/audit/log-error/route.ts` | `src/app/api/audit/log-error/route.ts` |
| `src/app/maestros/tipos-obra/tipos-obra-page.tsx` | `src/app/maestros/tipos-obra/page.tsx` (rename automático) |
| `src/app/logs/logs-page.tsx` | `src/app/logs/page.tsx` (rename automático) |
| `PATCH_database_types.txt` | Aplicado automáticamente por el script sobre `src/lib/types/database.ts`; se conserva como referencia/fallback por si necesitas aplicarlo a mano |
| `deploy-audit-fix.ps1` | El script en sí — no se copia al repo, se ejecuta desde donde lo descargues |

## Verificación post-despliegue
1. Tras ejecutar el script y la migración SQL, lanza el proyecto local
   (`npm run dev`) y crea un tipo de obra de prueba desde `/maestros/tipos-obra`.
2. En Supabase, `SELECT * FROM audit_log WHERE entidad = 'tipos_obra' ORDER BY created_at DESC LIMIT 1;`
3. Confirma que aparece en `/logs` con la etiqueta "Tipo de obra" (no el
   texto crudo `tipos_obra`).
4. Repite editando y desactivando ese mismo tipo de obra.

## Cobertura de auditoría añadida en esta entrega
`tipos_obra`, `users`, `obra_fases`, `parte_trabajadores`, `parte_maquinaria`,
`parte_vehiculos`, `parte_materiales`, `configuracion` — todas con trigger
nuevo (ver bloque D de la migración). Capa de registro de errores (intentos
fallidos) añadida vía `/api/audit/log-error`, integrada como piloto en
`tipos_obra`; replicar el mismo patrón de `try/catch` + `logAuditErrorClient`
al resto de maestros (`clientes`, `vehiculos`, `maquinaria`, `materiales`,
`tipos_trabajo`, `estados_obra`) queda pendiente como siguiente paso, ya que
no estaba en el alcance reportado de este fix.
