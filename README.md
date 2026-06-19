# Modulo Aplicaciones + Interpretacion de Georradar — ObrasPlan

## Que incluye esta entrega

1. Nuevo modulo de navegacion **Aplicaciones** (mismo nivel que Principal,
   Maestros, Administracion), con catalogo preparado para futuras apps.
2. Primera app: **Interpretacion de Georradar**, migrada desde el HTML
   original (`loynek_gpr_v12_OK.html`) al stack de ObrasPlan (Next.js,
   Supabase, Tailwind, Zustand), manteniendo el motor de calculo
   (parser SEG-Y, algoritmo de deteccion de anomalias, formula Sanders)
   portado literal y validado contra los datos demo de referencia.
3. Permisos integrados con el sistema existente de ObrasPlan
   (`rol_permisos` / `usePermissions` / `useRouteGuard`), protegidos
   tanto en frontend (menu) como en backend (RLS de Supabase).
4. Logs de auditoria desde el dia uno para toda accion relevante del
   modulo (alta de pasada, analisis IA, generacion de informe, errores).
5. Analisis IA (Claude / GPT-4o) con clave de empresa en servidor —
   el usuario nunca ve ni gestiona ninguna clave de API.
6. Informe Word generado con la skill docx de ObrasPlan (no el generador
   XML manual del HTML original).

## AVISO DE SEGURIDAD — accion requerida antes de desplegar

El HTML original (`loynek_gpr_v12_OK.html`) contenia una **clave de API
de OpenAI en texto plano** dentro del codigo JavaScript
(`sk-proj-nROYlbUm...`). Si ese archivo HTML se ha compartido, subido a
algun repositorio, o desplegado en algun sitio accesible, esa clave debe
**revocarse inmediatamente** en el dashboard de OpenAI
(platform.openai.com -> API keys), igual que se hizo anteriormente con
las claves de OpenAI/Resend que se compartieron por error. Esta
migracion ya no usa esa clave ni ese patron en ningun sitio.

## Despliegue automatico (recomendado)

1. Descarga este zip completo en una carpeta cualquiera de tu PC.
2. En esa carpeta, ejecuta en PowerShell:
   ```powershell
   .\deploy-aplicaciones-georadar.ps1
   ```
3. El script:
   - Localiza el zip automaticamente.
   - Copia todos los archivos a tu repo local
     (`C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan`),
     con los renombres correctos (Sidebar.tsx, usePermissions.ts,
     useRouteGuard.ts, las dos paginas page.tsx).
   - Hace backup de cualquier archivo que sobrescriba en
     `.georadar-backup-<fecha>` dentro del repo.
   - Anade la dependencia `docx` a `package.json` por sustitucion de
     texto exacta (detecta si ya esta aplicado, asi que es seguro
     reejecutarlo).
   - Ejecuta `npm install` para instalar `docx`.
4. Si quieres que ademas haga el commit y push:
   ```powershell
   .\deploy-aplicaciones-georadar.ps1 -GitCommit
   ```
   Pide confirmacion explicita (s/n) antes de hacer push.

Si tu carpeta de proyecto esta en otra ruta:
```powershell
.\deploy-aplicaciones-georadar.ps1 -RepoPath "D:\otra\ruta\obrasplan"
```

## Lo que el script NO puede hacer por ti

### 1. Ejecutar el SQL en Supabase
Abre el **SQL Editor de Supabase** y ejecuta el contenido completo de
`supabase/migrations/028_aplicaciones_georadar.sql`. Es idempotente: si
algo falla a mitad puedes reejecutarlo entero sin riesgo.

### 2. Configurar las claves de IA en Vercel
En el dashboard de Vercel, anade estas dos variables de entorno
(Settings -> Environment Variables):

| Variable | Valor |
|---|---|
| `GEORADAR_ANTHROPIC_API_KEY` | Tu clave de Anthropic (empieza por `sk-ant-...`) |
| `GEORADAR_OPENAI_API_KEY` | Tu clave de OpenAI (empieza por `sk-...`) |

Estas son claves **nuevas y propias de empresa** -- nunca reutilices la
clave que estaba hardcodeada en el HTML original (deberia estar
revocada, ver aviso de seguridad arriba).

Si no configuras alguna de las dos, el boton correspondiente (Claude o
GPT-4o) devolvera un error controlado en vez de fallar silenciosamente.

### 3. Promocionar a produccion
Tras el push, **promociona manualmente en el dashboard de Vercel** (plan
Hobby no promociona automaticamente).

## Verificacion post-despliegue

1. `npm run build` local para confirmar que compila.
2. Inicia sesion como admin, ve a **Aplicaciones** en el menu lateral.
3. Entra a **Interpretacion de Georradar**, pulsa "Probar con datos
   demo" -- deberian aparecer 10 anomalias (7 huecos, 3 suministros).
4. Pulsa "Claude" o "GPT-4o" en el panel de Analisis IA (requiere las
   variables de entorno del paso 2 ya configuradas en Vercel/local).
5. Pulsa "Generar informe Word" y descarga el documento.
6. Verifica en `/logs` que aparecen las entradas correspondientes
   (alta de pasada, analisis IA, generacion de informe).
7. Inicia sesion con un usuario del rol "Operario" y confirma que
   **no** ve el modulo Aplicaciones en el menu (acceso denegado por
   defecto, segun lo especificado).
8. Inicia sesion con un usuario del rol "Encargado" o "Jefe de obra" y
   confirma que **si** ve el modulo y puede crear pasadas.

## Cobertura de auditoria declarada en esta entrega

`georadar_pasadas` (tabla nueva, trigger desde el alta), mas correccion
de un hueco preexistente detectado durante esta entrega: `roles` y
`rol_permisos` (de la migracion `010_roles.sql`) nunca tuvieron trigger
de auditoria. Como esta misma migracion modifica `rol_permisos` para dar
de alta los permisos del modulo nuevo, se corrige aqui tambien, conforme
a la regla del proyecto de dejar cubierto todo lo que se toca.

## Archivos de esta entrega (referencia)

| Archivo en el zip | Destino final en tu repo |
|---|---|
| `supabase/migrations/028_aplicaciones_georadar.sql` | mismo path |
| `src/lib/georadar/*.ts` (8 archivos) | mismo path |
| `src/app/api/aplicaciones/georadar/analizar/route.ts` | mismo path |
| `src/app/api/aplicaciones/georadar/informe/route.ts` | mismo path |
| `src/app/aplicaciones/aplicaciones-page.tsx` | `src/app/aplicaciones/page.tsx` |
| `src/app/aplicaciones/georadar/georadar-page.tsx` | `src/app/aplicaciones/georadar/page.tsx` |
| `src/components/layout/sidebar-georadar.tsx` | `src/components/layout/Sidebar.tsx` |
| `src/hooks/usepermissions-georadar.ts` | `src/hooks/usePermissions.ts` |
| `src/hooks/userouteguard-georadar.ts` | `src/hooks/useRouteGuard.ts` |
| `PATCH_package_json.txt` | Aplicado automaticamente por el script; referencia/fallback |

## Decisiones de arquitectura confirmadas contigo

- **Clave de IA**: unica clave de empresa en servidor (Vercel env vars),
  nunca expuesta al navegador. El campo de "pegar tu API key" del HTML
  original ha desaparecido por completo.
- **Informe Word**: reconstruido con la skill docx de ObrasPlan
  (libreria `docx`/docx-js), no el generador XML manual del original.
  El formato visual es propio de ObrasPlan, no una replica pixel a pixel
  del original.
- **Procesamiento de SGY**: sigue ocurriendo en el navegador del
  operario, igual que en el HTML original. No se sube el archivo SGY al
  servidor; solo se persisten los resultados ya calculados
  (anomalias, metadatos de la pasada) en `georadar_pasadas`.

## Pendiente / fuera de alcance de esta entrega

- Las apps futuras mencionadas como ejemplo (calculadoras tecnicas,
  generadores de informes, herramientas de almacen) no estan
  implementadas -- el catalogo en `/aplicaciones` y el Sidebar ya estan
  preparados para anadirlas sin tocar el resto de la arquitectura.
- No se ha implementado un panel de administracion de permisos por app
  especifico para el modulo Aplicaciones; los permisos se gestionan
  igual que el resto de pantallas, desde `/configuracion` (gestion de
  roles existente).
