# ObrasPlan — Loynek Soluciones Técnicas

Aplicación de planificación y gestión de obras.

## Requisitos previos

- **Node.js** 18+ → [nodejs.org](https://nodejs.org)
- **Docker Desktop** → [docker.com](https://www.docker.com/products/docker-desktop)
- **Supabase CLI** → Se instala como dependencia del proyecto

## Instalación paso a paso

### 1. Instalar dependencias

```bash
cd obrasplan
npm install
```

### 2. Instalar Supabase CLI (si no lo tienes)

```bash
npm install -g supabase
```

### 3. Arrancar Supabase local (requiere Docker)

```bash
# Asegúrate de que Docker Desktop esté corriendo
supabase start
```

Esto levantará:
- **PostgreSQL** en `localhost:54322`
- **API REST** en `localhost:54321`
- **Studio** (panel admin) en `localhost:54323`
- **Auth** con email/contraseña

La terminal mostrará las claves (anon key, service role key, etc.).
Verifica que coinciden con `.env.local`.

### 4. Crear las tablas de la base de datos

```bash
supabase db reset
```

Esto ejecutará la migración `001_initial_schema.sql` y el `seed.sql` con datos de prueba.

### 5. Crear el primer usuario

Abre Supabase Studio en **http://localhost:54323** y:

1. Ve a **Authentication** → **Users** → **Add User**
2. Email: `admin@loynek.es`
3. Password: `admin123456`
4. Marca "Auto Confirm User"
5. Click en **Create User**

El primer usuario que se registre será automáticamente **administrador**.

### 6. Arrancar la aplicación

```bash
npm run dev
```

Abre **http://localhost:3000** en tu navegador.

## Credenciales de prueba

| Email | Password | Rol |
|---|---|---|
| admin@loynek.es | admin123456 | Administrador (automático, primer usuario) |

## Estructura del proyecto

```
obrasplan/
├── supabase/
│   ├── migrations/001_initial_schema.sql   ← Esquema completo de BD
│   └── seed.sql                            ← Datos de prueba
├── src/
│   ├── app/                                ← Páginas (Next.js App Router)
│   │   ├── login/                          ← ✅ Login con branding Loynek
│   │   ├── dashboard/                      ← ✅ Dashboard con estadísticas
│   │   ├── obras/                          ← ✅ Listado de obras
│   │   ├── planificacion/                  ← 🚧 Fase 3
│   │   ├── partes/                         ← 🚧 Fase 4
│   │   └── maestros/
│   │       ├── recursos-humanos/           ← ✅ CRUD completo
│   │       ├── maquinaria/                 ← ✅ CRUD completo
│   │       ├── vehiculos/                  ← ✅ CRUD completo
│   │       ├── materiales/                 ← ✅ CRUD completo
│   │       └── clientes/                   ← ✅ CRUD completo
│   ├── components/
│   │   ├── layout/                         ← Sidebar, Topbar, AuthProvider
│   │   └── shared/                         ← DataTable, Modal (reutilizables)
│   ├── hooks/                              ← useAuth (Zustand store)
│   └── lib/
│       ├── supabase/                       ← Clientes browser/server
│       ├── types/                          ← Tipos TypeScript
│       └── utils/                          ← Utilidades (cn, etc.)
```

## Estado del MVP

| Fase | Estado | Descripción |
|---|---|---|
| 0. Setup | ✅ Completada | Proyecto, DB, auth, layout |
| 1. Maestros | ✅ Completada | 5 CRUDs: RRHH, maquinaria, vehículos, materiales, clientes |
| 2. Obras | 🔶 Parcial | Listado funcional, crear/editar pendiente |
| 3. Planificación | 🚧 Siguiente | Gantt, Timeline, drag & drop, conflictos |
| 4. Partes Diarios | 🚧 Pendiente | Formulario, aprobación, firma |
| 5. Documentos | 🚧 Pendiente | Upload, galería, categorías |
| 6. Exportaciones | 🚧 Pendiente | PDF, Excel |
| 7. Usuarios/Permisos | 🚧 Pendiente | Gestión, roles, RLS |
| 8. PWA/Offline | 🚧 Pendiente | Service Worker, cache |

## Comandos útiles

```bash
# Desarrollo
npm run dev                    # Arrancar app en localhost:3000
supabase start                 # Arrancar Supabase local
supabase stop                  # Parar Supabase local
supabase db reset              # Resetear BD con migración + seed

# Base de datos
supabase migration new mi_cambio    # Crear nueva migración
supabase db push                    # Aplicar migraciones

# Tipos TypeScript
npm run db:types                    # Regenerar tipos desde esquema
```

## Migración a producción

Cuando el MVP esté listo:

1. Crear proyecto en [supabase.com](https://supabase.com)
2. `supabase link --project-ref <ref>`
3. `supabase db push`
4. Deploy en [vercel.com](https://vercel.com) con las variables de producción
5. Cambiar `.env.production` con las claves de Supabase Cloud
