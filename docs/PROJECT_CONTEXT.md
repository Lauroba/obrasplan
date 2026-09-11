# ObrasPlan — Contexto técnico completo

Documento de traspaso técnico. Objetivo: que otro desarrollador (o Claude Code) pueda continuar el proyecto sin depender del historial de conversaciones con Claude Chat/Cowork. No es un changelog de chats — es una descripción del sistema tal y como está hoy, por qué está así, y qué se rompió alguna vez y cómo se arregló.

Generado el 11/09/2026 a partir del código fuente real del repositorio (`github.com/Lauroba/obrasplan`, rama `main`, commit `d65a093`) y de la memoria de proyecto acumulada. Sustituye y amplía a `obrasplan_contexto_chatgpt.md` (16/07/2026), que se mantiene en la raíz del repo solo como referencia histórica.

---

## 1. Qué es ObrasPlan

Aplicación web de gestión de obras y recursos para **Loynek Soluciones Técnicas** (constructora vinculada a LEyNA, Inyecciones y Reparaciones Técnicas, S.L., Bilbao — impermeabilización por inyección y reparación estructural). En producción, ~15 usuarios activos: operarios, encargados, jefes de obra y administración.

- **Producción:** `obrasplan.vercel.app`
- **Repo:** `github.com/Lauroba/obrasplan` (rama `main`, sin otras ramas de trabajo — todo el desarrollo histórico se ha hecho directo sobre `main`)
- **Ruta local de Eneko:** `C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan`
- **Admin de referencia:** `eneko@loynek.com`
- **Proyecto Supabase:** `jpyffhiqqrseelootdhg` — `https://jpyffhiqqrseelootdhg.supabase.co`

Cubre: planificación semanal de recursos (Gantt drag&drop), fichas de obra, partes de trabajo diarios con firma digital, almacén/inventario con movimientos de stock, maestros (RRHH, vehículos, maquinaria, materiales, clientes), informes en PDF/Word, y dos aplicaciones internas de análisis de georradar (V1 y V2 con IA).

---

## 2. Arquitectura

Next.js 14 (App Router) como monolito full-stack: páginas cliente (`"use client"` en casi todo) que hablan directamente con Supabase vía el SDK JS para lecturas y escrituras simples, más un conjunto de **API routes** (`src/app/api/*`) para todo lo que necesita el `service_role` de Supabase o librerías que no pueden correr en el navegador (generación de PDF con `sharp`, envío de email con Resend, transcripción con Whisper, gestión de usuarios).

No hay backend separado ni capa de API propia más allá de esas rutas de Next. Toda la lógica de negocio "seria" (quién puede hacer qué, qué transiciones de estado son válidas) vive en dos sitios que deben mantenerse sincronizados a mano:

- **Frontend:** `usePermissions()` → `canDo(pantalla, accion)`.
- **Base de datos (RLS):** función `user_has_permiso(pantalla, accion)`, usada dentro de las políticas de Postgres.

Esto es una decisión consciente (ver §9), no un descuido: RLS es la última línea de defensa real (un usuario podría llamar a Supabase directamente sin pasar por el frontend), y el frontend replica la misma lógica solo por UX (ocultar botones, dar mensajes de error legibles).

No hay capa de estado global compleja: Zustand se usa únicamente para la sesión de usuario (`useAuthStore`, en `src/hooks/useAuth.ts`). El resto del estado es local a cada página/componente, cargado con `useEffect` + Supabase directamente. `@tanstack/react-query` está instalado pero **no se usa en ningún sitio** (confirmado por grep — ver deuda técnica, §20): la capa de datos real es `useEffect` + llamadas directas al SDK de Supabase, no React Query.

---

## 3. Stack tecnológico

| Capa | Tecnología | Versión (package.json) |
|---|---|---|
| Framework | Next.js (App Router) | 14.2.18 |
| Lenguaje | TypeScript | ^5.7.2 |
| Estilos | Tailwind CSS | ^3.4.16 |
| Componentes UI | Radix UI (`@radix-ui/react-*`) + `class-variance-authority` + `tailwind-merge` (patrón shadcn/ui sin el CLI) | varias |
| Base de datos | Supabase Cloud (PostgreSQL + RLS) | `@supabase/supabase-js` ^2.47.10, `@supabase/ssr` ^0.5.2 |
| Estado cliente | Zustand (solo sesión) | ^5.0.2 |
| Drag & drop | `@dnd-kit/core` + `sortable` + `utilities` | ^6/8/3 |
| Tablas | `@tanstack/react-table` | ^8.20.5 |
| PDF | `jspdf` + `jspdf-autotable` | ^2.5.2 / ^3.8.3 |
| Word | `docx` | ^9.7.1 |
| Email | Resend | ^4.8.0 |
| Imágenes (server) | `sharp` (carga perezosa) | via next/webpack |
| Mapas | Leaflet | ^1.9.4 |
| Firmas | `react-signature-canvas` | ^1.0.6 |
| Excel | `xlsx` | ^0.18.5 |
| QR | `qrcode` | ^1.5.4 |
| Iconos | `lucide-react` | ^0.462.0 |
| Testing | Vitest | ^5.0.0 (devDependency) |
| Hosting | Vercel (plan Hobby) | — |
| CLI Supabase | `supabase` (devDependency, para desarrollo local) | ^2.0.0 |

`react` y `react-dom` en `^18.3.1` (no React 19 — Next 14.2 no lo soporta bien todavía).

---

## 4. Estructura del repositorio

```
src/
  app/                        # Next.js App Router
    dashboard/                 # Resumen: asignaciones del día/semana, partes pendientes, alertas almacén
    planificacion/              # Gantt semanal (Vista Obras / Vista Personas) — módulo más complejo del repo
    obras/
      [id]/                     # Ficha de obra: General, Recursos, Tareas, Partes, Documentos, Checklists, Logs
      [id]/almacen/             # Stock/movimientos vinculados a una obra
      nueva/
    partes/                    # Partes diarios
      [id]/                     # Detalle: firma dual, fotos, audio, PDF, email
      nuevo/
      aprobar/
    almacen/
      articulos/  tipos-articulo/  almacenes/  proveedores/  movimientos/  etiquetas/
    maestros/                  # Tablas maestras (CRUD simples)
      recursos-humanos/[id]/  vehiculos/  maquinaria/  materiales/  clientes/
      estados-obra/  tipos-obra/  tipos-trabajo/  contactos-leyna/
    aplicaciones/
      georadar/                 # V1: CSV + heatmap Leaflet
      georadar-v2/               # V2: + IA (Anthropic/OpenAI), informe Word
    configuracion/              # Roles, permisos, ajustes de partes/email/almacén
    logs/                       # Visor de audit_log
    usuarios/                   # Gestión de usuarios (admin)
    login/
    api/                        # API routes — todo lo que necesita service_role o libs server-only
      almacen/alertas-email/  aplicaciones/georadar/  asignaciones/validar/
      audit/log-error/  informes/{planificador,rrhh,clientes}/
      obras/pdf/  partes/{pdf,email}/  transcribe/  users/
  components/
    layout/       # AppLayout, Sidebar (construido a partir de visibleScreens()), Topbar, AuthProvider
    shared/       # DataTable, Modal, PhotoUpload, ResourceAvatar, etc.
    obras/ partes/ planificacion/   # componentes específicos de cada módulo
  hooks/
    useAuth.ts            # Zustand store de sesión
    usePermissions.ts     # Motor de permisos (frontend)
    useRouteGuard.ts
    useLayout.ts
  lib/
    supabase/{client,server,admin}.ts   # 3 formas de crear el cliente Supabase — ver §7
    types/database.ts     # Tipos TS del esquema, MANTENIDOS A MANO (ver deuda técnica §20)
    utils/
      disponibilidadRrhh.ts     # Regla única de disponibilidad de RRHH (crítica, ver §8)
      planificadorRango.ts      # Cálculo del rango de fechas a pedir al planificador (fix sept. 2026)
      fetchAllPaginated.ts      # Paginación genérica anti-truncado de PostgREST (fix sept. 2026)
      obrasVisiblesOperario.ts
      cn.ts
    pdf/generatePartePdf.ts
    audit/logAuditError.ts      # logAuditErrorServer / logAuditErrorClient
    logo.ts                     # LOGO_BASE64
  middleware.ts            # Redirección auth (protege todo excepto /login)
supabase/
  migrations/               # 001..045 + varios scripts sueltos no numerados (ver §20)
  config.toml                # max_rows = 1000 ← relevante, ver §11 y §16
  seed.sql
public/                     # manifest.json, sw.js, iconos — PWA activa
*.ps1                       # ~140 scripts de despliegue del flujo de trabajo anterior (ver CLAUDE.md)
obrasplan_contexto_chatgpt.md   # Snapshot de contexto de julio 2026, ahora histórico
vitest.config.mts
next.config.js              # ignoreBuildErrors / ignoreDuringBuilds — ver §16 y §20
```

No hay `.github/workflows` (sin CI), ni `vercel.json` (configuración de Vercel 100% por defecto/auto-detectada).

---

## 5. Modelo de datos y Supabase

RLS activo en **todas** las tablas. 45 migraciones numeradas secuencialmente (`001_initial_schema.sql` → `045_partes_firma_rls_verificacion.sql`) más varios scripts sin numerar mezclados en el mismo directorio (diagnóstico, no esquema — ver §20).

### Usuarios, roles y permisos

```
users            id (FK auth.users), email, nombre, role (admin|lectura|partes — legacy),
                 rol_id (FK roles), recurso_id (FK recursos_humanos, vincula cuenta↔trabajador),
                 activo, avatar_url

roles            id, nombre, descripcion, is_admin

rol_permisos     id, rol_id (FK roles), pantalla (string libre, ver lista en usePermissions.ts),
                 visible, crear, editar, eliminar, asignar (bool)
                 -- "asignar" es legacy: existe en el esquema y en user_has_permiso() por
                 -- compatibilidad, pero el frontend actual ya no la usa (ver §9, permiso "Asignar" eliminado)
```

### Obras y planificación

```
obras            id, nombre, cliente_id (FK clientes), fecha_inicio, fecha_fin,
                 estado (planificada|en_curso|pausada|finalizada|cerrada — enum legacy),
                 estado_obra_id (FK estados_obra — estado real, personalizable con color),
                 tipo_obra_id (FK tipos_obra), num_presupuesto, num_factura,
                 contacto_obra_*, direccion/localidad/provincia, observaciones,
                 color, archivada, orden_gantt, created_by

estados_obra     id, nombre, color, activo        tipos_obra   id, nombre, activo
clientes         id, nombre, contacto, telefono, email, direccion, activo
obra_fases       id, obra_id, nombre, fecha_inicio, fecha_fin, estado, orden

asignaciones     ← tabla central del planificador
                 id, obra_id, fase_id (nullable),
                 recurso_tipo (humano|maquinaria|vehiculo|material), recurso_id,
                 fecha_inicio, fecha_fin, cantidad, unidad, observaciones, created_by
```

RPC: `check_asignacion_conflictos(recurso_tipo, recurso_id, fecha_inicio, fecha_fin, exclude_id?)` detecta solapes; `get_user_role()` y `get_user_recurso_id()` son helpers de sesión usados dentro de las políticas RLS.

### Recursos

```
recursos_humanos   id, nombre, perfil, telefono, email, observaciones, foto_url,
                    activo, asignable, fecha_inicio, fecha_fin   ← ver disponibilidadRrhh.ts (§8)
vehiculos          id, nombre, matricula, tipo, estado, foto_url, activo, asignable
maquinaria         id, nombre, tipo, estado, foto_url, activo
materiales         id, nombre, tipo, unidad, foto_url, activo
```

### Partes diarios

```
partes_diarios     id, obra_id (nullable), fecha, created_by,
                    descripcion, incidencias, observaciones,
                    estado (borrador|pendiente|aprobado|rechazado|firmado),
                    firma_data, firma_cliente (base64), jefe_obra, encargado_obra,
                    responsable_empresa, direccion/localidad/provincia,
                    aprobado_by, aprobado_at, motivo_rechazo

parte_lineas        id, parte_id, orden, concepto, tipo_trabajo_id, fabricante,
                    producto, unidades, cantidad, observaciones
parte_trabajadores  id, parte_id, recurso_id, hora_entrada, hora_salida
parte_maquinaria / parte_vehiculos / parte_materiales   (equivalentes por tipo de recurso)
parte_audios        id, parte_id, nombre_archivo, storage_path, duracion, tamano, uploaded_by
documentos           id, obra_id, parte_id (nullable), nombre_archivo, tipo, categoria,
                     storage_path, tamano, mime_type, uploaded_by
                     -- bucket "documentos"; nombres saneados (NFD, sin acentos, sin caracteres no-ASCII)
```

### Almacén

```
articulos            id, nombre, descripcion, tipo_id, proveedor_id, unidad,
                     precio_unitario, stock_minimo, codigo_barras, foto_url, activo
tipos_articulo        id, nombre, activo
proveedores           id, nombre, contacto, telefono, email, activo
almacenes             id, nombre, ubicacion, descripcion, activo
ubicaciones_stock     id, articulo_id, almacen_id, cantidad
movimientos_almacen   id, articulo_id, almacen_id, tipo (entrada|salida|ajuste|traslado),
                     cantidad, cantidad_anterior, cantidad_nueva, referencia, motivo, created_by
stock_cache           id, articulo_id, total_stock, ultima_actualizacion
etiquetas_plantillas  id, nombre, configuracion (jsonb), created_by
```

### Otros

```
tareas               id, obra_id, descripcion, tipo_tarea_id, prioridad, estado,
                     fecha_limite, asignado_a (FK recursos_humanos), created_by
obra_checklists / obra_checklist_items
contactos_leyna      id, nombre, cargo, empresa, telefono, email, notas, activo
georadar_pasadas     id, nombre_archivo, datos (jsonb), created_by
audit_log            id, user_id, user_rol, accion, entidad, entidad_id, modulo,
                     descripcion, resultado, error_detalle,
                     origen (trigger_db|api_route|rpc_manual|client_catch),
                     valor_anterior/valor_nuevo (jsonb), ip_address, user_agent
```

### `src/lib/types/database.ts`

Tipos TypeScript **mantenidos a mano**, no generados. El `package.json` incluye `npm run db:types` (`supabase gen types typescript --local`), pero exige tener el esquema aplicado en local (`db:start` + migraciones) — no hay constancia de que se use en el flujo real de trabajo. El archivo ha divergido del esquema real (ver bug de tipos `never` en §16/§19). El archivo empieza con un BOM UTF-8 (`\uFEFF`) — no da problemas en tiempo de ejecución pero puede confundir a herramientas que hagan diff/grep binario estricto.

---

## 6. Autenticación y roles

Flujo:

1. Supabase Auth gestiona login/sesión (`src/middleware.ts` redirige a `/login` si no hay usuario, y de `/login` a `/dashboard` si ya lo hay; protege todo excepto rutas de Next internas y los estáticos de PWA).
2. `AuthProvider` + `useAuthStore` (Zustand, `src/hooks/useAuth.ts`) guardan el usuario de sesión.
3. `usePermissions()` (`src/hooks/usePermissions.ts`), al montarse, **relee `rol_id` y `role` directamente de la tabla `users`** (no confía solo en el store cacheado), y:
   - Si `users.role === "admin"` → `isAdmin = true`, acceso total, no se cargan permisos granulares.
   - Si no, busca `roles.is_admin` para el `rol_id` vinculado → si es `true`, también `isAdmin = true`.
   - Si tampoco, carga `rol_permisos WHERE rol_id = ...` y expone `canDo(pantalla, accion)` / `canAccess(pantalla)` consultando esas filas, con fallback a `DEFAULT_OPERARIO` (dashboard visible, partes crear/editar, obras y planificación visibles) para pantallas sin fila configurada.
4. `visibleScreens()` calcula el set de pantallas a mostrar en el `Sidebar` (todas si es admin; si no, las marcadas `visible=true` en BD más las de `DEFAULT_OPERARIO`).

Roles existentes en producción (configurables desde `/configuracion`, no hardcodeados en código salvo `admin`): **admin** (acceso total vía `is_admin`), **Operario** (rol por defecto implícito), **Encargado**, **Oficina**, **Jefe de almacén** — estos tres últimos se configuran por completo desde `rol_permisos`, sin lógica especial en el código para ninguno de ellos por nombre.

**Importante:** el criterio de "es admin" tiene que evaluarse igual en frontend (`usePermissions`) y en SQL (`user_has_permiso()`, migración 044) — `users.role = 'admin'` **O** `roles.is_admin = true`. Si se toca uno de los dos sitios hay que tocar el otro, o un rol con `is_admin=true` en BD pero `role != 'admin'` en `users` (o viceversa) quedará con permisos inconsistentes entre lo que ve en el frontend y lo que RLS le permite realmente hacer.

---

## 7. Funcionalidades implementadas (por módulo)

**Dashboard** (`/dashboard`) — vista día/semana de asignaciones, panel "Sin asignar" (filtrado por `activo`+`asignable`+fechas de disponibilidad), refresh manual, resumen de obras activas / partes pendientes / tareas, alertas de stock mínimo de almacén.

**Planificador** (`/planificacion`) — el módulo más grande y más delicado del repo. Gantt semanal/mensual/anual con dos vistas (Obras / Personas), drag&drop (@dnd-kit) para asignar recursos a obras por fecha, fila "SIN ASIGNAR", detección visual de conflictos (`ring-2 ring-red-400`, respaldada por el RPC `check_asignacion_conflictos`), notas por celda, orden de filas persistido (`orden_gantt`), modal de asignación manual por rango de fechas, validación de disponibilidad en tiempo real (drag&drop, modal, panel lateral, y también server-side en `/api/asignaciones/validar`), vista móvil por tarjetas, `PlanificadorErrorBoundary` que registra en `audit_log` cualquier crash del componente.

**Obras** (`/obras`) — listado con filtro multi-estado (activas/archivadas/todas) y orden natural por `num_presupuesto` (P-20 antes que P-100, vacíos al final), ficha con pestañas General/Recursos/Tareas/Partes/Documentos/Checklists/Logs, cambio de estado inline con actualización optimista y rollback si falla, informe PDF con logo y filtros.

**Partes diarios** (`/partes`) — creación con auto-asignación de obra desde el contexto del planificador, líneas de trabajo, recursos asignados (RRHH/maquinaria/vehículos/materiales), doble firma digital (operario + cliente, `react-signature-canvas`), subida de fotos/documentos (con las cautelas de Android, ver §8), grabación y transcripción de audio (Whisper), generación de PDF con fotos comprimidas, envío automático por email al firmar (Resend — **destinatario fijo hardcodeado a `lauroba.eneko@gmail.com`**, ver `src/app/api/partes/email/route.ts:16`, no configurable desde la UI).

**Almacén** — artículos con tipo/proveedor/stock mínimo/código de barras, almacenes físicos, movimientos (entrada/salida/ajuste/traslado) con snapshot de cantidad anterior/nueva, caché de stock (`stock_cache`), diseñador de etiquetas QR, alertas de stock por email (`/api/almacen/alertas-email`).

**Maestros** — CRUD estándar para RRHH (con ficha modal de detalle: pestañas Detalle/Asignaciones + PDF filtrable), vehículos, maquinaria, materiales, clientes, estados de obra, tipos de obra, tipos de trabajo, contactos LEyNA.

**Georadar V1/V2** (`/aplicaciones/georadar*`) — V1: carga de CSV + heatmap sobre Leaflet. V2: añade análisis con IA (claves de Anthropic/OpenAI gestionadas desde un panel en `localStorage`, no en variables de entorno del servidor salvo las claves por defecto — ver §14) y generación de informe Word de 7 secciones.

**Configuración / Logs / Usuarios** — gestión de roles y `rol_permisos`, ajustes generales, visor de `audit_log`, alta/baja/edición de usuarios (`/api/users`, admin-only, usa `service_role`).

---

## 8. Reglas de negocio importantes

- **Disponibilidad de un recurso RRHH para una fecha** (`src/lib/utils/disponibilidadRrhh.ts`, función única usada en todo el proyecto — panel del planificador, drag&drop, modal de asignación manual, fila "SIN ASIGNAR", y validación server-side): disponible si y solo si `activo === true` **y** `asignable !== false` **y** `fecha >= fecha_inicio` **y** (`fecha_fin` es null **o** `fecha <= fecha_fin`). Comparación siempre como strings `YYYY-MM-DD`, nunca como `Date` (evita desplazamientos por huso horario).
- **El histórico de asignaciones no se oculta nunca por disponibilidad actual.** Dar de baja o desasignar un recurso (cambiar `activo`/`fecha_fin`) no debe hacer desaparecer visualmente sus asignaciones pasadas — la disponibilidad solo determina si HOY se le puede asignar algo nuevo. Esto se rompió una vez en Vista Personas (ver bug §19.1) y quedó como regla explícita a partir de ahí.
- **Quién puede firmar un parte:** el creador del parte (mientras esté en `borrador`/`pendiente`/`rechazado`), o cualquier usuario cuyo rol tenga `editar=true` en la pantalla `partes` — independientemente de si es el creador. Antes de la migración 044 solo el creador o un admin podían, lo cual bloqueaba a jefes de obra con permiso explícito de edición (ver §19.2).
- **Planificador — permiso para reordenar/asignar:** `puedeAsignar = canDo("planificacion", "crear")`. No hay un permiso "Asignar" separado (se eliminó, ver §9).
- **Numeración de presupuesto (`num_presupuesto`) se ordena naturalmente**, no alfabéticamente: P-20 antes que P-100.
- **Cobertura de auditoría es obligatoria** para cualquier tabla/endpoint/módulo nuevo — se ha dado el caso de un módulo (`tipos_obra`) que quedó fuera de `audit_log` por descuido; declarar explícitamente la cobertura al entregar es la única defensa contra que se repita.

---

## 9. Decisiones de arquitectura y por qué

- **RLS como fuente de verdad de permisos, con espejo en frontend.** Se decidió replicar la lógica de permisos en SQL (`user_has_permiso()`) en vez de confiar solo en que el frontend oculte botones, porque cualquier usuario autenticado puede llamar a la API REST de Supabase directamente. El frontend (`canDo`) existe solo para UX; si alguna vez divergen, gana RLS (más restrictivo) y el síntoma es "el botón deja hacer algo que luego falla en silencio" — exactamente lo que pasó en el bug de firma de partes (§19.2).
- **`next.config.js` con `ignoreBuildErrors`/`ignoreDuringBuilds`.** Decisión pragmática para no bloquear despliegues en Vercel por errores de tipos preexistentes (el proyecto arrastra ~90 errores de TypeScript, sobre todo por el desfase entre `database.ts` mantenido a mano y el esquema real — ver §20). Efecto secundario: el build **nunca** falla por errores de tipos o lint, así que esa red de seguridad no existe en producción — solo la da `npm run test` y una revisión manual de `tsc --noEmit`.
- **Eliminación del permiso "Asignar".** Existía como columna/acción separada de "crear"/"editar" y generaba confusión sobre qué necesitaba un usuario para mover recursos en el planificador. Se sustituyó por `canDo("planificacion","crear")` para asignar y `canDo("obras","editar")` donde aplicaba. La columna `asignar` sigue en el esquema (`rol_permisos`, `user_has_permiso()`) por compatibilidad hacia atrás, pero el frontend ya no la consulta directamente.
- **Buckets de Storage públicos con política de INSERT autenticado**, en vez de privados con URLs firmadas. Simplifica mostrar fotos/documentos directamente por URL pública; el control de acceso real está en que solo usuarios autenticados pueden subir, y en que las URLs no son adivinables (UUIDs). Trade-off consciente de simplicidad sobre confidencialidad estricta — aceptable para el tipo de documentos que maneja (partes de obra, no datos sensibles de terceros).
- **Vercel Hobby sin auto-promote.** Decisión de coste, no técnica: el plan gratuito no promociona automáticamente cada deploy a producción, así que cada `git push` a `main` requiere un paso manual (`Promote to Production`). Cualquier automatización de despliegue tendría que tenerlo en cuenta o requeriría subir de plan.
- **Sin entorno de staging.** Todo el desarrollo y las migraciones se prueban contra producción o localmente contra Supabase local (`supabase start`); no existe un segundo proyecto Supabase ni un dominio de preview usado sistemáticamente. Es una fuente directa de riesgo para cualquier cambio de esquema (ver §20).

---

## 10. Cambios importantes durante el proyecto (cronología resumida)

Basado en el historial de commits (197 commits, mayo–septiembre 2026) y en la memoria de proyecto. No exhaustivo; recoge los hitos que cambiaron cómo funciona el sistema, no cada commit.

- **Esquema inicial y auditoría completa** (`001`–`010`): tablas base, sistema de permisos por rol (`009`, `010`), auditoría completa (`008`).
- **Planificación visible para todos + ruptura de RLS circular** (`023`, `025`): `asignaciones_select` dependía de que la obra fuera visible en `obras`, y `obras_select` (para no-admin) dependía de que hubiera una asignación visible → referencia circular que devolvía vacío para el rol `partes` (operario) aunque los datos existieran. Se rompió el ciclo consultando `recurso_id`/rol directamente en `asignaciones_select` sin pasar por `obras`.
- **Sistema de estados de obra personalizables + presupuesto** (`029`, y feature "obras multi-estado + presupuesto"): sustituye el enum fijo `obras.estado` por `estados_obra` (tabla con color), añade `num_presupuesto` con orden natural, cambio de estado inline con optimistic update.
- **Módulo de almacén completo** (`030`–`041`): artículos, tipos, proveedores, almacenes, movimientos, caché de stock, corrección de stocks negativos (`041`).
- **RLS de asignaciones ampliada a todos los roles autenticados** (`042`, sept. 2026): antes solo `admin` podía insertar asignaciones — cualquier otro rol tenía el botón de arrastrar en el planificador pero la operación fallaba en silencio (RLS bloqueaba el INSERT sin dar error). Se abrió INSERT/UPDATE/DELETE a `auth.role() = 'authenticated'`, entendiendo el planificador como herramienta operativa de uso general, no restringida a admin.
- **Snapshot de estado en asignaciones** (`043`): guarda el estado de la obra en el momento de crear la asignación.
- **RLS de firma de partes alineada con permisos por rol** (`044`, `045`, sept. 2026): ver postmortem completo en §19.2.
- **Fix del histórico del planificador** (sept. 2026, sin migración SQL): ver postmortem completo en §19.1 — el cambio más reciente y más delicado del repo a fecha de este documento.

---

## 11. Errores históricos y soluciones aplicadas

Resumen de patrones recurrentes que ya han costado tiempo de debugging una vez y no deberían volver a costarlo. El detalle completo de los tres bugs de septiembre 2026 está en §19 (son los más recientes y los mejor documentados con causa raíz confirmada).

- **RLS sin `WITH CHECK` explícito** → Postgres reutiliza `USING` para validar también la fila resultante de un UPDATE. Si `USING` exige una condición que la fila *después* del cambio ya no cumple (p.ej. "estado en X" cuando el update cambia justamente el estado a Y), la política bloquea el 100% de los intentos, para el 100% de los usuarios no-admin, sin ningún error visible. Pasó con `partes_update` (§19.2).
- **RLS circular entre tablas relacionadas** (p.ej. A visible si B es visible, y B visible si A es visible) → devuelve conjuntos vacíos para roles no-admin de forma intermitente/confusa. Pasó entre `asignaciones` y `obras` (§10).
- **`.limit(N)` del cliente no protege contra el límite del servidor.** PostgREST/Supabase trunca a `max_rows` (1000 en este proyecto, `supabase/config.toml`) **sin error visible**, y sin `ORDER BY` qué filas sobreviven es esencialmente aleatorio. Pasó en el planificador (§19.1); **sigue sin corregir** en `dashboard/page.tsx` (mismo patrón, ver §19).
- **Escrituras que fallan por RLS no lanzan excepción** — un `.update()`/`.insert()` bloqueado por una política devuelve éxito con 0 filas afectadas, no un error. Cualquier código que no compruebe el recuento de filas devuelto puede dar por hecho que algo se guardó cuando no se guardó nada. `logAuditErrorClient`/`logAuditErrorServer` existen específicamente para registrar estos casos cuando se detectan.
- **SWC (compilador de Next 14) falla en comentarios con caracteres no-ASCII** situados antes de un `return()` JSX (acentos, tildes, em-dash). Después del `return` no da problema. Ha causado errores de build crípticos más de una vez.
- **Peculiaridades de Android con `<input type="file">`**: `display:none` bloquea el selector de archivos en Chrome para Android — hace falta `opacity:0; position:absolute`. Y el componente puede re-renderizarse durante el tiempo que el selector está abierto, perdiendo valores de estado capturados por closure — de ahí la regla de hacer *snapshot* de `obra_id` (y guardarlo en Supabase) antes del primer `await` del flujo de subida.
- **Entregas por `.ps1` que no llegaban completas a GitHub** (ver §19.3): un script puede pasar sus propias comprobaciones de tamaño/contenido en disco y aun así no subir todos los archivos a git si algún comando de git falla en silencio a mitad del script. Ya no aplica con Claude Code (acceso directo a git), pero es la causa raíz de al menos una rotura de build en producción.

---

## 12. Restricciones que nunca deben romperse

Estas son, literalmente, las reglas de la sección "Reglas obligatorias" de `CLAUDE.md` — se repiten aquí con el porqué para que no se pierdan si alguien solo lee este documento:

1. Toda política RLS de `UPDATE`/`INSERT` lleva `USING` y `WITH CHECK` separados y pensados de forma independiente.
2. Ninguna query a Supabase que pueda devolver >1000 filas va sin `ORDER BY` + paginación (`fetchAllPaginated`).
3. Comentarios ASCII-only antes de `return()` JSX.
4. `useSearchParams()` en componente hijo bajo `<Suspense>`.
5. Todos los hooks antes de cualquier `return` condicional.
6. Nombres de archivo saneados (sin acentos/caracteres no-ASCII) antes de subir a Storage.
7. `sharp` con `require()` perezoso, nunca `import` estático a nivel de módulo.
8. Snapshot de `obra_id` (y persistencia temprana) antes de cualquier `await` en subida de partes en Android.
9. Migraciones SQL nunca se aplican solas — siempre a mano en el SQL Editor de Supabase.
10. Vercel Hobby exige "Promote to Production" manual tras cada push a `main`.
11. El criterio de "es admin" (`users.role='admin'` O `roles.is_admin=true`) debe mantenerse idéntico en `usePermissions()` (frontend) y `user_has_permiso()` (SQL) — tocar uno sin el otro genera un desajuste de permisos entre lo que el usuario ve y lo que realmente puede hacer.
12. El histórico de asignaciones de un recurso (pasado) no se filtra nunca por su disponibilidad *actual* — solo la disponibilidad decide si se le puede asignar algo nuevo hoy.

---

## 13. Integraciones externas

| Servicio | Uso | Dónde |
|---|---|---|
| Supabase | BD, Auth, Storage (buckets `documentos`, `audios`) | En todo el proyecto |
| Resend | Email transaccional (parte firmado, alertas de stock) | `src/app/api/partes/email/route.ts`, `src/app/api/almacen/alertas-email/` |
| OpenAI (Whisper) | Transcripción de audio de partes | `src/app/api/transcribe/` |
| OpenAI / Anthropic | Análisis IA en Georadar V2 | `src/app/api/aplicaciones/georadar/` — claves también gestionables por el usuario desde un panel en `localStorage` del propio Georadar V2, además de las variables de entorno de servidor |
| Google Maps | Mapas en Georadar (`NEXT_PUBLIC_GMAPS_KEY`) — Leaflet se usa para el heatmap, Google Maps para otra parte de la visualización | `src/app/aplicaciones/georadar*` |
| Vercel | Hosting, build, deploy | — |

No hay webhooks entrantes de terceros ni colas/jobs en background — todo es síncrono dentro de request/response de Next.

---

## 14. Variables de entorno necesarias

Ninguna vive en el repo (`.env*.local` está en `.gitignore`; no hay `.env.example` — **pendiente de crear**, ver §20). Confirmadas por uso real en código (`grep process.env`):

| Variable | Dónde se usa | Notas |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | cliente browser, server, middleware, admin | pública, va al bundle del cliente |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | cliente browser, server, middleware | pública |
| `SUPABASE_SERVICE_ROLE_KEY` | `src/lib/supabase/admin.ts` | **secreta** — solo en API routes, nunca exponer al cliente |
| `RESEND_API_KEY` | envío de email (partes firmados, alertas almacén) | secreta |
| `OPENAI_API_KEY` | transcripción Whisper | secreta |
| `GEORADAR_OPENAI_API_KEY` | análisis IA Georadar V2 (clave por defecto del servidor, distinta de la de Whisper) | secreta |
| `GEORADAR_ANTHROPIC_API_KEY` | análisis IA Georadar V2 | secreta |
| `NEXT_PUBLIC_GMAPS_KEY` | mapas en Georadar | pública |

Para desarrollo local además hace falta Docker (Supabase CLI local: `npm run db:start`).

---

## 15. GitHub / Vercel / Supabase — operativa

- **GitHub:** un único repo, una única rama (`main`). Sin ramas de feature, sin PRs en el historial reciente — el flujo hasta ahora ha sido commit directo a `main` (script `.ps1` → `git add/commit/push`). Sin `.github/workflows`: no hay tests ni build corriendo en CI antes de mergear/pushear nada.
- **Vercel:** plan Hobby, importado directo del repo de GitHub (deploy automático en cada push a `main`, pero **sin auto-promote** — hay que entrar a Deployments → ⋮ → "Promote to Production" a mano). Sin `vercel.json`, configuración 100% por defecto de Next.js. Build con `ignoreBuildErrors`/`ignoreDuringBuilds`, así que un push con errores de TypeScript o de ESLint **sí despliega**.
- **Supabase:** proyecto único (`jpyffhiqqrseelootdhg`), sin entorno de staging separado. Migraciones versionadas en `supabase/migrations/` pero **nunca aplicadas automáticamente** — hay que copiarlas a mano en el SQL Editor del dashboard de Supabase tras cada push que las incluya. `max_rows = 1000` en `supabase/config.toml` (límite de filas por respuesta de PostgREST) — relevante para cualquier query nueva que no pagine (ver §11, §19.1).

---

## 16. Estrategia de testing

Mínima y reciente — nació en septiembre de 2026 junto con el fix del histórico del planificador, no como práctica establecida desde el principio.

- **Framework:** Vitest, configuración mínima (`vitest.config.mts`): `environment: "node"`, sin `jsdom`, sin alias `@/...` de `tsconfig` resuelto. Solo cubre **lógica pura** (funciones sin DOM/React) — no hay tests de componentes ni de integración.
- **Tests existentes (17 en total, en 2 archivos):**
  - `src/lib/utils/planificadorRango.test.ts` (9 tests) — cálculo del rango de fechas a pedir al planificador.
  - `src/lib/utils/fetchAllPaginated.test.ts` (8 tests, incluye una reproducción exacta del caso real de producción: 1314 filas / tamaño de página 1000).
- **Sin cobertura:** ningún componente React, ninguna API route, ninguna política RLS tiene test automatizado. La verificación de políticas RLS se hace con bloques `DO $$ ... RAISE EXCEPTION $$` dentro de las propias migraciones (ver `045` como ejemplo) — es una verificación de que la política *se aplicó* como se esperaba, no un test de comportamiento con distintos roles.
- **`tsc --noEmit` no forma parte de ningún flujo automatizado** (no hay CI, y el build de Vercel ignora sus errores). Al añadir la suite de Vitest (sept. 2026) se confirmó que el proyecto arrastraba ~90 errores de TypeScript preexistentes (sobre todo tipos `never` originados por el desfase entre `database.ts` mantenido a mano y el esquema real) — no relacionados con los cambios de ese momento, pero sí una fuente de riesgo real: cualquier error de tipos nuevo se mezcla con el ruido y no hay manera automática de distinguirlo.

Para cualquier cambio de lógica pura (cálculos, validaciones, helpers), el patrón esperado a partir de ahora es: extraer la lógica a una función pura en `src/lib/utils/`, y acompañarla de un `.test.ts`. Es el patrón que se siguió en el fix de septiembre y es replicable sin más infraestructura.

---

## 17. Comandos

```bash
npm run dev            # localhost:3000
npm run build
npm run start
npm run lint
npm run test            # vitest run
npm run test:watch

npm run db:start        # supabase start — stack local vía Docker
npm run db:stop
npm run db:reset        # supabase db reset — reaplica todas las migraciones en local
npm run db:migrate      # supabase migration new <nombre>
npm run db:types        # regenera src/lib/types/database.ts desde el esquema LOCAL (requiere db:start antes)
```

Para desplegar un cambio de esquema en producción: aplicar la migración manualmente en el SQL Editor del dashboard de Supabase (no hay paso automatizado). Para desplegar un cambio de código: push a `main` (Vercel construye solo) + "Promote to Production" manual en el dashboard de Vercel.

---

## 18. Funcionalidades pendientes

Según lo último registrado (memoria de proyecto + nota final del informe de septiembre 2026):

- Ampliación continua de módulos: checklists, informes, refinamiento de maestros.
- Posible sincronización Trello → ObrasPlan (existe un script Python exploratorio, no integrado).
- Mejoras de PWA (iconos ya corregidos a PNG cuadrado correcto).
- Ideas discutidas sin implementar: mostrar fecha completa en el planificador, fases personalizadas por obra, pestaña de tareas pendientes por obra, widget de tareas pendientes en el dashboard filtrado por el usuario conectado.
- Revisar si el límite de `max_rows` (1000) de Supabase se quiere mantener o subir — el fix de paginación funciona con cualquier valor, pero conviene decidirlo conscientemente para futuras queries que no paginen.
- No se ha añadido infraestructura de tests de componentes (React Testing Library) — evaluado y descartado por ahora como cambio mayor frente al alcance del fix de septiembre.

---

## 19. Bugs conocidos (abiertos o recién cerrados — detalle completo)

### 19.1 — Planificador no mostraba asignaciones históricas (cerrado, sept. 2026 — patrón repetido en otro sitio, ver más abajo)

**Síntoma:** en Planificación (Vista Obras y Vista Personas), al navegar a julio 2026 o meses anteriores, las asignaciones de RRHH/vehículos dejaban de aparecer, aunque seguían existiendo en Supabase. Ficha de Obra y Ficha de RRHH (que no filtran por fecha) sí mostraban el histórico completo.

**Causa raíz #1:** `fetchData` en `src/app/planificacion/page.tsx` estaba envuelta en `useCallback(..., [])` — el `useEffect` que la dispara solo corría una vez al montar, capturando el `startDate` de ese instante y calculando una ventana fija de 84 días (`[startDate-28d, startDate+56d]`). Navegar (flechas, "Hoy", cambiar de vista) actualizaba `startDate` en el estado pero nunca volvía a llamar a `fetchData` — el array de asignaciones en memoria quedaba congelado a la ventana inicial. Efecto colateral: la vista "Año" pinta 364 días pero la ventana solo cubría 84.

**Fix:** `src/lib/utils/planificadorRango.ts` — `getRangoFetchAsignaciones(startDate, diasVisibles)`, función pura. `fetchData` ahora depende de `[startDate, viewMode]` y se refetchea en cada navegación. 9 tests en `planificadorRango.test.ts`.

**Hallazgo colateral confirmado con Eneko antes de tocarlo:** en Vista Personas se ocultaba el histórico si el trabajador no cumplía su disponibilidad *actual* (`checkRrhhDisponibilidad`) — contradice la regla de que desasignar/dar de baja un recurso no debe borrar visualmente su histórico (§8, §12). Se quitó ese filtro solo para la visualización del histórico; sigue aplicándose correctamente para decidir si HOY se puede asignar a alguien.

**Causa raíz #2 (descubierta al verificar el fix #1 en producción):** con el rango de fechas ya corregido, la query de `asignaciones` para un rango típico superaba fácilmente las 1000 filas en toda la empresa. PostgREST/Supabase limita cada respuesta a `max_rows` (1000 en este proyecto) **sin avisar** — el `.limit(5000)` del cliente no tiene efecto por encima de ese tope del servidor. Sin `ORDER BY`, qué filas se descartaban al truncar era esencialmente arbitrario. Confirmado en producción vía API REST directa: para un rango con 1314 filas reales, la API sin paginar devolvía solo 1000.

**Fix:** `src/lib/utils/fetchAllPaginated.ts` — pagina en bloques de 1000 con `.range()` hasta agotar resultados; `page.tsx` usa `fetchAllPaginated(...)` con `.order("fecha_inicio")`. 8 tests, incluida la reproducción exacta del caso real.

**⚠️ Sin corregir todavía en el resto del código:** `src/app/dashboard/page.tsx` (líneas ~66 y ~213) hace exactamente el mismo patrón — `.gte("fecha_fin", from).lte("fecha_inicio", to).limit(5000)` sobre `asignaciones`, sin paginar. Mismo riesgo de truncado silencioso si el rango consultado supera 1000 filas. No estaba en el alcance del fix de septiembre; queda pendiente de aplicar el mismo `fetchAllPaginated`.

### 19.2 — RLS bloqueaba la firma de partes para roles no-admin (cerrado, sept. 2026)

**Síntoma reportado:** un usuario con rol "Jefe de obra" y permiso `editar=true` en la pantalla `partes` no podía firmar partes que él no había creado — error visible: `new row violates row-level security policy for table partes_diarios`.

**Causa raíz:** la política `partes_update` (creada en la migración `024`, sin tocar desde entonces) solo permitía escritura a `admin` o al `created_by` del parte — ignoraba por completo `rol_permisos`/`canDo("partes","editar")` del frontend. Un usuario con permiso de edición explícito pero que no era el creador quedaba bloqueado por RLS de forma **silenciosa** (0 filas afectadas, sin error) en cualquier UPDATE que no pasara por la firma; el error de RLS explícito aparecía específicamente al firmar porque ahí sí violaba también el `WITH CHECK` implícito (ver debajo).

**Causa raíz más profunda:** la política original (migración `024`) no definía `WITH CHECK` explícito. En Postgres, un `UPDATE` sin `WITH CHECK` reutiliza la expresión de `USING` también para validar la fila *resultante*. Como `USING` exigía `estado IN ('borrador','pendiente','rechazado')`, esa misma condición se aplicaba también al *nuevo* valor de `estado` — y firmar pone `estado='firmado'`, que **nunca** cumple esa condición. Resultado: ningún usuario no-admin pudo firmar un parte por esta vía nunca, ni siquiera el propio creador, independientemente de sus permisos.

**Fix (migración `044`):** función `user_has_permiso(pantalla, accion)` — replica exactamente `usePermissions().canDo()` del frontend (sin hardcodear ningún rol ni email). Política `partes_update` reescrita separando `USING` (qué filas se pueden tocar: deben estar en un estado editable) de `WITH CHECK` (quién puede dejar la fila así: dueño o con permiso `editar` en Partes) — se mantiene la vía "creador" para que un Operario (que solo tiene `crear`, no `editar`) pueda seguir completando su propio borrador, y se añade la vía por permiso explícito para que cualquier rol con `editar` en Partes pueda firmar partes de otros.

**Migración `045`:** re-aplicación 100% idempotente de la `044` (por si no llegó a ejecutarse completa) más un bloque de verificación automática (`DO $$ ... RAISE EXCEPTION $$`) que confirma en el propio SQL Editor que la política queda activa con la definición correcta, y una consulta de diagnóstico comentada para comprobar qué resuelve Supabase realmente para un usuario concreto (rol, `is_admin`, fila de `rol_permisos` para `partes`).

### 19.3 — Deploy roto en Vercel porque un commit no subió sus propios archivos (cerrado, causa raíz de proceso, no de código — sept. 2026)

Tras el fix de `fetchAllPaginated`, el build de Vercel falló con `Module not found: Can't resolve '@/lib/utils/planificadorRango'`. Comparando commits en GitHub: el script `.ps1` de la primera entrega solo subió 1 archivo (el propio `.ps1`, 176 líneas); los 4 archivos que debía escribir y confirmar (`page.tsx`, `planificadorRango.ts`, `planificadorRango.test.ts`, `vitest.config.mts` + cambios en `package.json`) sí se escribieron correctamente en disco local (el script pasó sus comprobaciones de tamaño/contenido) pero `git add -A` no los recogió en el commit — causa exacta no reproducible a posteriori (posibles explicaciones: el `git pull` inicial falló y el script no comprobaba el código de salida antes de continuar; o `$RepoPath` no coincidía con la raíz real del repo en ese momento).

Diagnóstico hecho comparando `git show <commit> --stat`, `git log --all -- <archivo>` y `git diff origin/main -- <archivo>` contra el estado real en GitHub, sin depender de suposiciones sobre qué se había ejecutado localmente. `page.tsx` en GitHub ya incluía correctamente ambos fixes (porque la segunda entrega reescribió el archivo entero); el problema era exclusivamente que el módulo que importaba nunca llegó a subirse.

**Fix:** commit separado que añade únicamente los 4 elementos faltantes, sin volver a tocar los archivos que ya estaban correctos (para no arriesgar pisarlos). Mejora de proceso: cada comando git del script comprobaba `$LASTEXITCODE` explícitamente y detenía la ejecución con mensaje claro si fallaba, en vez de continuar en silencio.

**Relevancia para Claude Code:** esta clase de bug es específica del flujo de entrega por script `.ps1` sobre una máquina remota sin visibilidad directa del estado de git. Con acceso directo al repo y a git (como en Claude Code), esta categoría de fallo desaparece por diseño — pero conviene no perder la costumbre de confirmar con `git log --oneline` / `git status` que un cambio realmente llegó a `origin/main`, en vez de fiarse solo de que el comando no diera error.

---

## 20. Deuda técnica conocida

- **`src/lib/types/database.ts` mantenido a mano y desfasado del esquema real.** Origen de ~90 errores de TypeScript preexistentes (muchos tipos `never`), enmascarados en el build por `ignoreBuildErrors: true`. La solución correcta (`npm run db:types` contra un Supabase local con todas las migraciones aplicadas) existe como script pero no hay evidencia de que se use de forma habitual. Recomendación para quien continúe: `supabase start` + `supabase db reset` + `npm run db:types`, y resolver la deriva de una vez, no arrastrarla.
- **~140 scripts `.ps1` de despliegue commiteados en la raíz del repo**, restos del flujo de trabajo anterior (Claude Chat/Cowork sin acceso directo al repo). No se ejecutan en producción, no son documentación activa, y ensucian considerablemente la raíz del proyecto. No borrar sin que Eneko lo confirme explícitamente (pueden tener valor como archivo histórico de qué se cambió y cuándo, a falta de un CHANGELOG real), pero no hace falta mantenerlos ni seguir generándolos.
- **`supabase/migrations/` mezcla migraciones numeradas con scripts de diagnóstico sueltos** (`diagnostico-usuarios-huerfanos.sql`, `diagnostico_asignaciones.sql`, `investigar-huerfanos-masivo.sql`, `fix-usuarios-roles.sql` — sin número, no forman parte de la secuencia aplicada por `supabase db reset`) y **tiene números de migración duplicados** (`032_almacen_mejoras.sql` / `032_almacen_mejoras_fix.sql`; `039_contactos_leyna.sql` / `039_contactos_leyna_v2.sql` / `039_importar_contactos.sql`). Esto hace que `supabase db reset` en local pueda no reproducir fielmente el estado real de producción, y dificulta saber a simple vista cuál es "la" migración 032 o 039. Recomendable: mover los scripts de diagnóstico a una carpeta separada (`supabase/scripts/` o similar) y renumerar/consolidar los duplicados antes de que haya más.
- **`.audit-fix-backup-20260619-134526/` commiteado en el repo** — directorio de backup de una corrección de auditoría concreta, con subcarpetas `src/` y `supabase/` propias. Ruido en el repo; candidato a limpieza si Eneko confirma que ya no hace falta.
- **Sin `.env.example`.** No hay forma de saber qué variables de entorno hacen falta sin grepear el código (que es como se ha construido §14 de este documento). Crear uno es trabajo de minutos y elimina una fuente de fricción para cualquier nuevo entorno de desarrollo.
- **Sin CI.** Nada corre automáticamente (`test`, `lint`, `tsc --noEmit`) antes de que un cambio llegue a `main` o se despliegue. Con la suite de Vitest ya existente, un workflow mínimo de GitHub Actions (`npm ci && npm run test`) sería una mejora de bajo esfuerzo y alto valor.
- **Sin entorno de staging** — todo cambio de esquema se prueba en local (si acaso) o directamente en producción.
- **Patrón de query sin paginar repetido fuera del planificador** (§19.1): `dashboard/page.tsx` tiene el mismo `.limit(5000)` sin `fetchAllPaginated` que causó el bug ya corregido en `planificacion/page.tsx`. Vale la pena auditar sistemáticamente todas las queries a `asignaciones` (y cualquier otra tabla que pueda crecer de forma similar) en busca del mismo patrón.
- **Email de notificación de partes firmados hardcodeado** (`lauroba.eneko@gmail.com` en `src/app/api/partes/email/route.ts:16`) en vez de configurable desde `/configuracion`.
- **`@tanstack/react-query` está en `package.json` pero no se usa en ningún sitio** (confirmado: cero referencias a `useQuery`/`useMutation`/`QueryClient` en `src/`). Dependencia muerta — candidata a retirar, o a adoptar conscientemente si se decide migrar la capa de datos hacia ahí en el futuro.
- **BOM UTF-8 al inicio de `database.ts`** — inofensivo en runtime, pero puede romper herramientas que esperen UTF-8 sin BOM.
