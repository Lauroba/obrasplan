# ObrasPlan — Contexto completo para ChatGPT

## ¿Qué es ObrasPlan?

Aplicación web de gestión de obras y recursos para **Loynek Soluciones Técnicas**.  
~15 usuarios, desplegada en producción.

- **URL producción:** `obrasplan.vercel.app`
- **Repo:** `github.com/Lauroba/obrasplan` (rama `main`)
- **Ruta local:** `C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan`
- **Admin:** `eneko@loynek.com`

---

## Stack técnico

| Capa | Tecnología |
|---|---|
| Framework | Next.js 14.2.18 (App Router, `"use client"`) |
| Lenguaje | TypeScript |
| Estilos | Tailwind CSS |
| Base de datos | Supabase Cloud (PostgreSQL + RLS) |
| Autenticación | Supabase Auth |
| Hosting | Vercel Hobby (deploy manual: Promote to Production) |
| Estado global | Zustand (`useAuthStore`) |
| Drag & Drop | @dnd-kit/core + @dnd-kit/sortable |
| PDF | jsPDF 2.5.2 + jspdf-autotable 3.8.3 |
| Word/docx | docx 9.7.1 |
| Email | Resend |
| Imágenes | sharp (lazy via `require`) |
| Mapas | Leaflet |
| Formularios | React nativo |
| Tablas | @tanstack/react-table |
| Iconos | lucide-react |
| Firmas | react-signature-canvas |
| Audio | Whisper API (transcripción) |
| QR | qrcode |
| Excel | xlsx |

**Supabase proyecto:** `https://jpyffhiqqrseelootdhg.supabase.co`

---

## Estructura de carpetas

```
src/
  app/                     # Rutas Next.js (App Router)
    dashboard/             # Dashboard principal
    planificacion/         # Planificador Gantt semanal
    obras/                 # Listado y detalle de obras
      [id]/                # Detalle obra (pestañas: General, Recursos, Tareas, Partes, Docs, Checklists, Logs)
      nueva/               # Crear/editar obra
    partes/                # Partes diarios
      [id]/                # Detalle parte (firma, documentos, audio)
      nuevo/               # Crear parte
    almacen/               # Módulo almacén
      articulos/           # CRUD artículos
      tipos-articulo/      # Tipos de artículo
      almacenes/           # Almacenes físicos
      proveedores/         # Proveedores
      movimientos/         # Movimientos de stock
      etiquetas/           # Diseñador de etiquetas QR
    maestros/              # Tablas maestras
      recursos-humanos/    # RRHH (con ficha de detalle modal)
      vehiculos/
      clientes/
      estados-obra/
      tipos-trabajo/
      tipos-obra/
      contactos-leyna/
      maquinaria/
      materiales/
    aplicaciones/
      georadar/            # Georadar V1 (CSV + heatmap Leaflet)
      georadar-v2/         # Georadar V2 (IA: Anthropic + OpenAI)
    configuracion/         # Roles, permisos, partes/email, almacén, general
    logs/                  # Audit log
    usuarios/              # Gestión de usuarios
    login/
    api/                   # API Routes (server-side)
      asignaciones/validar/   # Validación disponibilidad RRHH
      partes/email/           # Envío email parte firmado
      partes/pdf/             # Generación PDF parte
      obras/pdf/              # PDF de obra
      informes/planificador/  # Informe planificador PDF
      informes/rrhh/          # Informe RRHH PDF
      informes/clientes/      # Informe clientes PDF
      almacen/alertas-email/  # Alertas stock
      transcribe/             # Whisper transcripción audio
      users/                  # Gestión usuarios
      audit/log-error/        # Log errores cliente
      aplicaciones/georadar/  # Análisis e informe Georadar
  components/
    layout/
      AppLayout.tsx        # Layout principal con sidebar + topbar
      Sidebar.tsx          # Menú lateral con permisos
      AuthProvider.tsx
      Topbar.tsx
    shared/
      DataTable.tsx        # Tabla reutilizable con paginación y búsqueda
      Modal.tsx            # Modal (sizes: sm, md, lg, xl)
      PhotoUpload.tsx
      ResourceAvatar.tsx
      SignatureCanvas.tsx (partes/)
      AudioRecorder.tsx (partes/)
      ChecklistPanel.tsx (obras/)
  hooks/
    useAuth.ts             # Zustand store: user, session
    usePermissions.ts      # Hook de permisos por rol
    useRouteGuard.ts       # Guard de rutas
    useLayout.ts
  lib/
    supabase/
      client.ts            # createClient() para navegador
      server.ts            # createClient() para servidor
      admin.ts             # createAdminClient() con service_role
    types/
      database.ts          # Todos los tipos TypeScript del esquema
    utils/
      cn.ts                # classnames helper
      disponibilidadRrhh.ts  # Función centralizada disponibilidad RRHH
      obrasVisiblesOperario.ts
    pdf/
      generatePartePdf.ts  # Genera PDF del parte diario
    logo.ts                # LOGO_BASE64 (logo Loynek en base64)
    audit/
      logAuditError.ts     # Helper para registrar errores en audit_log
```

---

## Base de datos — Tablas principales

### Usuarios y roles

```
users
  id (uuid, FK auth.users)
  email, nombre, role (admin|lectura|partes)
  rol_id (FK roles)
  recurso_id (FK recursos_humanos — vincula usuario a trabajador)
  activo, avatar_url, created_at, updated_at

roles
  id, nombre, descripcion, is_admin, created_at

rol_permisos
  id, rol_id (FK roles), pantalla (string)
  visible, crear, editar, eliminar (boolean)
  -- Pantallas: dashboard, planificacion, obras, partes,
  --   almacen_articulos, almacen_tipos_articulo, almacen_almacenes,
  --   almacen_proveedores, almacen_movimientos, almacen_etiquetas,
  --   maestros_rrhh, maestros_vehiculos, maestros_clientes,
  --   maestros_estados, maestros_tipos_trabajo, maestros_tipos_obra,
  --   maestros_contactos_leyna, apps_georadar, apps_georadar_v2,
  --   logs, configuracion
```

### Obras y planificación

```
obras
  id, nombre, cliente_id (FK clientes)
  fecha_inicio (DATE), fecha_fin (DATE, nullable)
  estado (planificada|en_curso|pausada|finalizada|cerrada)
  estado_obra_id (FK estados_obra — estado personalizado con color)
  tipo_obra_id (FK tipos_obra)
  num_presupuesto, num_factura
  contacto_obra_nombre/telefono/email
  direccion, localidad, provincia
  observaciones, color (hex), archivada (bool)
  orden_gantt (int), created_by (FK users)

estados_obra
  id, nombre, color (hex), activo

tipos_obra
  id, nombre, activo

clientes
  id, nombre, contacto, telefono, email, direccion, activo
  -- contactos: tabla contactos (id, cliente_id, nombre, cargo, telefono, email)

obra_fases
  id, obra_id, nombre, fecha_inicio, fecha_fin
  estado (pendiente|en_curso|completada), orden

asignaciones  ← tabla central del planificador
  id, obra_id (FK obras), fase_id (nullable)
  recurso_tipo (humano|maquinaria|vehiculo|material)
  recurso_id (uuid — apunta a la tabla del recurso_tipo)
  fecha_inicio (DATE), fecha_fin (DATE)
  cantidad, unidad, observaciones, created_by

-- Función RPC: check_asignacion_conflictos(recurso_tipo, recurso_id, fecha_inicio, fecha_fin, exclude_id?)
-- Devuelve conflictos de solapamiento de asignaciones
```

### Recursos (RRHH, Vehículos, Maquinaria, Materiales)

```
recursos_humanos
  id, nombre, perfil (puesto), telefono, email, observaciones
  foto_url, activo (bool), asignable (bool)
  fecha_inicio (DATE — inicio disponibilidad en planificador)
  fecha_fin (DATE, nullable — fin disponibilidad, null = indefinido)

vehiculos
  id, nombre, matricula, tipo, estado, observaciones, foto_url, activo, asignable

maquinaria
  id, nombre, tipo, estado, observaciones, foto_url, activo

materiales
  id, nombre, tipo, unidad, observaciones, foto_url, activo
```

### Partes diarios

```
partes_diarios
  id, obra_id (FK obras, nullable), fecha (DATE)
  created_by (FK users)
  descripcion, incidencias, observaciones
  estado (borrador|pendiente|aprobado|rechazado|firmado)
  firma_data (base64 firma operario), firma_cliente (base64 firma cliente)
  jefe_obra, encargado_obra, responsable_empresa
  direccion, localidad, provincia
  aprobado_by, aprobado_at, motivo_rechazo

parte_lineas (líneas de trabajo del parte)
  id, parte_id, orden, concepto, tipo_trabajo_id, fabricante, producto
  unidades, cantidad, observaciones

parte_trabajadores  (RRHH asignados al parte)
  id, parte_id, recurso_id, hora_entrada, hora_salida, observaciones

parte_maquinaria, parte_vehiculos, parte_materiales
  (entidades similares para otros recursos)

parte_audios (transcripciones Whisper)
  id, parte_id, nombre_archivo, storage_path, duracion, tamano, uploaded_by

documentos  (fotos y archivos adjuntos)
  id, obra_id, parte_id (nullable), nombre_archivo, tipo, categoria
  storage_path, tamano, mime_type, uploaded_by
  -- Storage bucket: "documentos"
  -- Nombres normalizados: NFD + replace no-ASCII → _
```

### Almacén

```
articulos
  id, nombre, descripcion, tipo_id (FK tipos_articulo), proveedor_id
  unidad, precio_unitario, stock_minimo, codigo_barras
  foto_url, activo

tipos_articulo
  id, nombre, activo

proveedores
  id, nombre, contacto, telefono, email, activo

almacenes
  id, nombre, ubicacion, descripcion, activo

ubicaciones_stock
  id, articulo_id, almacen_id, cantidad (stock actual)

movimientos_almacen
  id, articulo_id, almacen_id, tipo (entrada|salida|ajuste|traslado)
  cantidad, cantidad_anterior, cantidad_nueva
  referencia, motivo, created_by

stock_cache
  id, articulo_id, total_stock, ultima_actualizacion

etiquetas_plantillas
  id, nombre, configuracion (jsonb), created_by
```

### Otros módulos

```
tareas  (tareas pendientes por obra)
  id, obra_id, descripcion, tipo_tarea_id, prioridad (alta|media|baja)
  estado (pendiente|completada), fecha_limite
  asignado_a (FK recursos_humanos), created_by

checklists  (via ChecklistPanel en obra)
  -- tablas: obra_checklists, obra_checklist_items

contactos_leyna
  id, nombre, cargo, empresa, telefono, email, notas, activo

georadar_pasadas
  id, nombre_archivo, datos (jsonb), created_by

audit_log  (log de auditoría — TODAS las acciones)
  id, user_id, user_rol, accion, entidad, entidad_id, modulo
  descripcion, resultado, error_detalle
  origen (trigger_db|api_route|rpc_manual|client_catch)
  valor_anterior (jsonb), valor_nuevo (jsonb), ip_address, user_agent
```

---

## Sistema de permisos

### Flujo completo

1. Usuario inicia sesión → Supabase Auth → `useAuthStore` (Zustand) guarda `user`
2. `usePermissions()` hook carga desde BD:
   - `users.rol_id` → obtiene `roles.is_admin`
   - Si `is_admin=true` → acceso total sin comprobar permisos
   - Si no → carga `rol_permisos WHERE rol_id = users.rol_id`
3. Comprobaciones en componentes:
   - `isAdmin` → acceso total
   - `canDo("pantalla", "crear"|"editar"|"eliminar")` → permiso específico
   - `canAccess("pantalla")` → permiso "Ver" (visible)
4. `visibleScreens()` → Set de pantallas para el Sidebar

### Roles predefinidos

- **admin** → `is_admin=true`, acceso total
- **Operario** → acceso por defecto (dashboard, partes, obras read-only, planificación read-only)
- **Encargado** → configurable
- **Oficina** → configurable (ejemplo: todo excepto eliminar obras y partes)
- **Jefe de almacén** → configurable

### Regla de disponibilidad RRHH (`src/lib/utils/disponibilidadRrhh.ts`)

```typescript
// Un RRHH está disponible si:
activo === true
&& asignable !== false
&& fecha >= fecha_inicio   // comparación string YYYY-MM-DD (sin UTC)
&& (fecha_fin == null || fecha <= fecha_fin)
```

---

## Módulos principales

### Dashboard (`/dashboard`)
- Vista día y semana de asignaciones
- Panel "Sin asignar" (filtra por activo + asignable + fechas)
- Botón refresh para recargar datos
- Resumen de obras activas, partes pendientes, tareas

### Planificador (`/planificacion`)
- Gantt semanal (Vista Obras y Vista Personas)
- Drag & drop con @dnd-kit
- Fila "SIN ASIGNAR" con recursos sin asignación ese día
- Conflictos marcados con `ring-2 ring-red-400`
- Notas por celda (tabla `planificacion_notas`)
- Orden de filas guardado (`orden_gantt` en obras y recursos)
- Modal de asignación manual (rango de fechas)
- Validación de disponibilidad RRHH en drag & drop y modal
- Vista móvil con cards por obra
- `puedeAsignar = canDo("planificacion", "crear")`

### Obras (`/obras`)
- Listado con filtro activas/archivadas/todas
- Pestañas: General, Recursos (asignaciones), Tareas, Partes, Documentos, Checklists, Logs
- Estado personalizado con color (via `estados_obra`)
- PDF de obra con logo, datos, checklist
- Subida de documentos (normalización de nombres para Supabase Storage)

### Partes Diarios (`/partes`)
- Creación con auto-asignación de obra desde planificador
- Doble firma: operario + cliente (canvas)
- Upload de fotos/docs (Android: createElement + appendChild + opacity:0)
- PDF automático con fotos comprimidas (sharp: max 1200px JPEG 72%)
- Email automático al firmar → Resend → `lauroba.eneko@gmail.com`
- Transcripción de audio con Whisper API
- `obra_id` guardado en Supabase ANTES del primer await para evitar pérdida en Android

### Georadar V2 (`/aplicaciones/georadar-v2`)
- Carga CSV de pasadas
- Heatmap sobre mapa Leaflet
- Panel de API Keys (Anthropic + OpenAI, guardadas en localStorage)
- Informe Word profesional (7 secciones) sin referencias a "riesgo"

---

## Patrones técnicos críticos

### PowerShell / scripts de despliegue
- **NUNCA usar Here-strings** (`@' ... '@`) — truncan archivos TS/TSX
- Usar **base64**: `[System.Convert]::FromBase64String()` + `WriteAllBytes`
- Siempre `git pull` antes de escribir archivos

### Next.js 14 / SWC
- SWC falla con UTF-8 no-ASCII (acentos, tildes, em-dash) en comentarios **antes del `return()`**
- `ignoreBuildErrors: true` y `ignoreDuringBuilds: true` en `next.config.js`
- `useSearchParams()` debe estar en componente hijo envuelto en `<Suspense>`
- Todos los hooks antes de cualquier `return` condicional (React error #310)

### Supabase
- Nombres de archivo: `.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-zA-Z0-9.\-_]/g, "_")`
- Fechas: helper `toDS(date)` → `YYYY-MM-DD` (evita UTC offset España UTC+2)
- RLS activo en todas las tablas
- `createAdminClient()` con service_role para operaciones server-side

### Android / móvil
- `display:none` bloquea el file picker en Android Chrome → usar `opacity:0; position:absolute`
- `document.createElement("input") + appendChild + inp.multiple = true + click()` para file picker
- Capturar `obra_id` ANTES del primer `await` (snapshot) — Android puede re-renderizar durante file picker
- Guardar `obra_id` en Supabase al inicio del upload

### sharp (compresión imágenes)
- Carga lazy: `try { sharp = require("sharp") } catch { sharp = null }`
- No declarar a nivel de módulo (Webpack warning)
- PDF: max 1200px JPEG 72% → de ~5MB a ~150KB por foto

### Auditoría
- Tabla `audit_log` obligatoria en todos los módulos
- Cada nueva tabla/endpoint debe incluir trigger o entrada de log
- `src/lib/audit/logAuditError.ts` para errores de cliente

### Vercel Hobby
- Deploy manual: Deployments → ⋮ → **Promote to Production**
- Sin auto-promote en Hobby

---

## Convenciones de código

```typescript
// Permisos en componentes
const { isAdmin, canDo, canAccess, loaded } = usePermissions();
const puedeVer     = isAdmin || canDo("obras", "visible");
const puedeCrear   = isAdmin || canDo("obras", "crear");
const puedeEditar  = isAdmin || canDo("obras", "editar");
const puedeEliminar = isAdmin || canDo("obras", "eliminar");

// Fechas (sin UTC offset)
const toDS = (d: Date): string =>
  `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;

// Disponibilidad RRHH
import { checkRrhhDisponibilidad, filtrarRrhhDisponibles } from "@/lib/utils/disponibilidadRrhh";
const result = checkRrhhDisponibilidad(rrhh, "2026-07-14");
// → { disponible: true } | { disponible: false, motivo: "mensaje legible" }

// Logo en PDF
import { LOGO_BASE64 } from "@/lib/logo";
doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", 15, 8, 30, 20);
```

---

## API Routes principales

| Ruta | Método | Descripción |
|---|---|---|
| `/api/partes/pdf` | POST | Genera PDF del parte diario (jsPDF + sharp) |
| `/api/partes/email` | POST | Envía email con PDF y adjuntos (Resend) |
| `/api/obras/pdf` | POST | Genera PDF de obra |
| `/api/informes/planificador` | POST | Informe planificador PDF/Word |
| `/api/informes/rrhh` | POST | Informe RRHH PDF |
| `/api/informes/clientes` | POST | Informe clientes PDF |
| `/api/asignaciones/validar` | POST | Valida disponibilidad RRHH server-side |
| `/api/transcribe` | POST | Transcripción audio Whisper |
| `/api/almacen/alertas-email` | POST | Alertas stock mínimo |
| `/api/audit/log-error` | POST | Log errores cliente |
| `/api/users` | GET/POST/PATCH | Gestión usuarios (admin) |
| `/api/aplicaciones/georadar/analizar` | POST | Análisis IA Georadar |
| `/api/aplicaciones/georadar/informe` | POST | Informe Word Georadar |

---

## Funciones RPC de Supabase

```sql
check_asignacion_conflictos(
  p_recurso_tipo, p_recurso_id,
  p_fecha_inicio, p_fecha_fin, p_exclude_id?
) → Conflicto[]
-- Detecta solapamiento de asignaciones para un recurso

get_user_role() → UserRole
get_user_recurso_id() → string
```

---

## Estado actual del proyecto (julio 2026)

**En producción:**
- Planificador Gantt con disponibilidad RRHH por fecha_inicio/fecha_fin
- Partes diarios con firma dual, PDF comprimido, email automático
- Ficha de detalle RRHH (modal con pestañas Detalle y Asignaciones + PDF filtrable)
- Dashboard con sin-asignar por ID (no por nombre)
- Módulo almacén completo
- Georadar V2 con IA
- Sistema de permisos por rol (sin columna "Asignar" — eliminada)
- PWA activa

**Bugs conocidos resueltos:**
- Android: file picker no abría galería → `createElement + appendChild`
- Android: obra_id se borraba al adjuntar → `obraIdSnapshot` + save en Supabase
- SWC: acentos en comentarios antes del `return()` → comentarios ASCII-only
- Planificador: `dateStrs` no en deps de `useMemo` → Bikerlan aparecía en semanas incorrectas
- Obras: `isAdmin` hardcodeado en lugar de `canDo` → Oficina no podía crear/editar

---

*Generado el 16/07/2026 desde el código fuente de ObrasPlan (commit principal: rama main)*
