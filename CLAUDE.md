# ObrasPlan — Guía operativa para Claude Code

ObrasPlan es la aplicación web de gestión de obras y recursos de **Loynek Soluciones Técnicas** (~15 usuarios: operarios, encargados, jefes de obra, admins). Repo: `github.com/Lauroba/obrasplan` (rama `main`). Producción: `obrasplan.vercel.app`.

Contexto completo, historial de decisiones y bugs resueltos → [`docs/PROJECT_CONTEXT.md`](docs/PROJECT_CONTEXT.md). Lee ese documento antes de tocar planificador, permisos/RLS o subida de archivos: son las zonas con más historial de bugs sutiles.

## Stack

Next.js 14.2.18 (App Router, mayoría `"use client"`) · TypeScript · Tailwind CSS · Supabase Cloud (Postgres + RLS + Storage + Auth) · Zustand · @dnd-kit · @tanstack/react-table · jsPDF/jspdf-autotable · docx · Resend (email) · sharp (server, lazy) · Leaflet · Vercel Hobby.

## Comandos

```bash
npm run dev          # servidor local (localhost:3000)
npm run build        # build de producción (Next ignora errores de TS/ESLint, ver más abajo)
npm run lint
npm run test          # vitest run — suite actual: solo lógica pura (17 tests)
npm run test:watch

npm run db:start      # stack Supabase local (Docker)
npm run db:migrate    # nueva migración con supabase CLI
npm run db:types      # regenera src/lib/types/database.ts desde el esquema LOCAL
```

No hay CI configurado (sin `.github/workflows`). El build/lint/test no se ejecuta automáticamente en ningún sitio salvo el build de Next en Vercel al hacer push — y ese build tiene `ignoreBuildErrors`/`ignoreDuringBuilds` activados, así que errores de tipos y de lint **no** rompen el deploy. Corre `npm run test` y revisa `tsc --noEmit` manualmente antes de dar algo por bueno.

## Arquitectura en una pasada

- **App Router** bajo `src/app/`, un directorio por módulo (`planificacion`, `obras`, `partes`, `almacen`, `maestros`, `aplicaciones/georadar*`, `configuracion`, `logs`, `usuarios`). `src/app/api/*` para todo lo que necesita `service_role` o librerías server-only (PDF, email, transcripción, admin de usuarios).
- **Supabase** es la única base de datos: Postgres con RLS activo en todas las tablas, Storage (buckets `documentos`, `audios`), Auth. Cliente browser (`src/lib/supabase/client.ts`), cliente server con cookies (`server.ts`), cliente admin con `service_role` (`admin.ts`, **solo** en API routes).
- **Permisos**: `usePermissions()` (`src/hooks/usePermissions.ts`) carga `rol_permisos` por `rol_id` y expone `isAdmin`, `canDo(pantalla, "crear"|"editar"|"eliminar")`, `canAccess(pantalla)`. El equivalente en SQL es la función `user_has_permiso(pantalla, accion)` (migración 044) — úsala en cualquier política RLS nueva que deba respetar permisos por rol en vez de hardcodear `admin`/email.
- **Auditoría**: `audit_log` es obligatoria. Los triggers de BD cubren éxitos; `src/lib/audit/logAuditError.ts` (`logAuditErrorServer` / `logAuditErrorClient`) cubre fallos silenciosos (RLS que bloquea sin error visible, validaciones, etc.). Todo módulo/tabla/endpoint nuevo debe declarar su cobertura de auditoría al entregarlo.
- **Fechas**: siempre como string `YYYY-MM-DD` vía `toDS()`, nunca objetos `Date` comparados directamente — España está en UTC+2 y las comparaciones UTC desplazan un día.

## Reglas obligatorias (no negociables)

1. **RLS con `WITH CHECK` explícito en toda política `UPDATE`/`INSERT`.** Omitirlo hace que Postgres reutilice `USING` también para la fila resultante — causó que nadie pudiera firmar partes durante meses (ver §"Bug: RLS partes_update" en PROJECT_CONTEXT.md). Toda política nueva debe escribir `USING` y `WITH CHECK` por separado y pensar explícitamente qué debe cumplir cada uno.
2. **Ninguna query a Supabase sin `.order()` + paginación explícita si puede devolver >1000 filas.** PostgREST trunca silenciosamente a 1000 filas (`max_rows` en `supabase/config.toml`) sin avisar ni dar error, aunque el cliente pida `.limit(5000)`. Usa `src/lib/utils/fetchAllPaginated.ts` para cualquier fetch que pueda crecer. **Pendiente de auditar:** `src/app/dashboard/page.tsx` (líneas ~66 y ~213) hace el mismo patrón sin paginar — mismo bug, sin corregir todavía.
3. **Comentarios ASCII-only antes de cualquier `return()` JSX.** SWC (el compilador de Next 14) falla con acentos/tildes/em-dash en comentarios situados antes del `return`. Después del `return` no hay problema.
4. **`useSearchParams()` siempre en un componente hijo envuelto en `<Suspense fallback={null}>`.**
5. **Todos los hooks antes de cualquier `return` condicional** (si no, error #310 de React).
6. **Nombres de fichero sanitizados antes de subir a Supabase Storage**: `.normalize("NFD").replace(/[̀-ͯ]/g,"").replace(/[^a-zA-Z0-9.\-_]/g,"_")`. Sin esto, nombres con acentos rompen la subida.
7. **`sharp` solo con `require()` perezoso** (`try { sharp = require("sharp") } catch { sharp = null }`), nunca `import` estático — si no, warning de Webpack. PDFs con foto: máx. 1200px, JPEG 72%.
8. **Snapshot de `obra_id` antes de cualquier `await`** en el flujo de subida de partes (Android puede re-renderizar el componente durante el file picker y perder el valor). Para el `<input type="file">` en Android: crear el input con `document.createElement`, `appendChild`, y usar `opacity:0; position:absolute` — **nunca** `display:none`, que bloquea el selector en Android Chrome.
9. **Migraciones SQL: nunca se aplican solas.** Se escriben en `supabase/migrations/`, numeradas secuencialmente (última: `045`), pero deben aplicarse **manualmente** en el SQL Editor de Supabase — no hay despliegue automático de esquema. Prefiere migraciones idempotentes (`CREATE OR REPLACE`, `DROP POLICY IF EXISTS`) con un bloque `DO $$ ... RAISE EXCEPTION/NOTICE $$` de verificación al final (ver 045 como plantilla).
10. **Vercel Hobby no promociona solo.** Tras cada `git push` a `main` hay que ir a Deployments → ⋮ → **Promote to Production** manualmente.
11. **No usar la columna `role` legacy (`admin|lectura|partes`) como única fuente de admin.** El criterio correcto y consistente entre frontend y SQL es: `users.role === "admin"` **O** `roles.is_admin = true` para el `rol_id` vinculado (así lo hacen `usePermissions()` y `user_has_permiso()` — replica siempre ambos si tocas uno).

## Sobre el flujo de trabajo anterior (Claude Chat/Cowork → Claude Code)

Hasta este traspaso, toda entrega de código se hacía como un script `.ps1` autocontenido (base64 + `git pull/add/commit/push`) porque el desarrollo ocurría por chat sin acceso directo al repo. **Esa restricción ya no aplica en Claude Code**: con acceso directo al filesystem y a git, no generes scripts `.ps1` de despliegue — edita los archivos directamente y haz commit/push normal. El repo tiene ~140 scripts `.ps1` históricos en la raíz (`deploy-*.ps1`, `fix-*.ps1`, `feat-*.ps1`); son artefactos del flujo antiguo, no documentación activa ni código que se ejecute en producción — no hace falta mantenerlos ni replicar su formato, pero no los borres sin que Eneko lo pida explícitamente (ver deuda técnica en PROJECT_CONTEXT.md).
