#Requires -Version 5.1
# fix-auth-permisos.ps1
# Corrige 4 bugs del sistema de autenticacion y permisos:
#
#   1. AppLayout: usaba 'loading' en vez de 'isLoading' del store Zustand
#      -> la pantalla de carga nunca terminaba correctamente
#
#   2. usePermissions: solo comprobaba users.role === "admin"
#      -> si rol_id apunta a un rol con is_admin=true pero role no dice "admin",
#         el usuario no veia todas las opciones. Ahora comprueba ambos.
#
#   3. API /api/users - sync: el mensaje mostraba "Contrasena por defecto: Loynek2026!"
#      confundiendo al usuario. Ahora:
#      - sync NUNCA toca contrasenas de usuarios existentes
#      - Mensaje claro sin exponer contrasenas
#      - Cambio de contrasena con validacion de error y auditoria
#      - Nueva accion send_reset para enviar email de recuperacion
#
#   IMPORTANTE: ejecutar tambien fix-usuarios-roles.sql en Supabase SQL Editor
#   para sincronizar el campo users.role de Sergio y cualquier otro admin.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR: repo no encontrado" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Escribiendo archivos" -ForegroundColor Cyan

$dst = "src\components\layout\AppLayout.tsx"
$content = @'
"use client";

import { useAuthStore } from "@/hooks/useAuth";
import { useRouteGuard } from "@/hooks/useRouteGuard";
import { useLayoutStore } from "@/hooks/useLayout";
import Sidebar from "./Sidebar";
import Topbar from "./Topbar";
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { cn } from "@/lib/utils/cn";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { user, isLoading } = useAuthStore();
  const { sidebarCollapsed } = useLayoutStore();
  const router = useRouter();

  // Route guard - redirects if no permission
  useRouteGuard();

  useEffect(() => {
    if (!isLoading && !user) router.push("/login");
  }, [isLoading, user, router]);

  if (isLoading) return <div className="flex items-center justify-center h-screen"><div className="w-8 h-8 border-4 border-brand-500 border-t-transparent rounded-full animate-spin" /></div>;
  if (!user) return null;

  return (
    <div className="min-h-screen bg-surface-50">
      <Sidebar />
      <div className={cn("transition-all duration-300", sidebarCollapsed ? "lg:ml-[72px]" : "lg:ml-[260px]")}>
        <Topbar />
        <main className="p-4 lg:p-6">{children}</main>
      </div>
    </div>
  );
}
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\components\layout\AppLayout.tsx" -ForegroundColor Green

$dst = "src\hooks\usePermissions.ts"
$content = @'
"use client";

import { useState, useEffect, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";

interface Permisos {
  pantalla: string;
  visible: boolean;
  crear: boolean;
  editar: boolean;
  eliminar: boolean;
  asignar: boolean;
}

// Default permissions per screen for non-configured roles
const DEFAULT_OPERARIO: Record<string, Partial<Permisos>> = {
  dashboard: { visible: true },
  partes: { visible: true, crear: true, editar: true },
  obras: { visible: true },
  planificacion: { visible: true },
};

export function usePermissions() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const [permisos, setPermisos] = useState<Permisos[]>([]);
  const [isAdminFromRole, setIsAdminFromRole] = useState(false);
  const [loaded, setLoaded] = useState(false);

  // Admin si el campo role = "admin" O si el rol vinculado tiene is_admin = true
  const isAdmin = user?.role === "admin" || isAdminFromRole;

  useEffect(() => {
    if (!user?.id) return;

    const fetchPermisos = async () => {
      // Leer rol_id y role actualizados desde la BD (no solo desde el store cacheado)
      const { data: userData } = await supabase
        .from("users")
        .select("rol_id, role")
        .eq("id", user.id)
        .single();

      if (!userData) { setLoaded(true); return; }

      // Comprobar si el rol vinculado es admin aunque users.role no diga "admin"
      if (userData.rol_id) {
        const { data: rolData } = await supabase
          .from("roles")
          .select("is_admin")
          .eq("id", userData.rol_id)
          .single();
        if (rolData?.is_admin) {
          setIsAdminFromRole(true);
          setLoaded(true);
          return;
        }
        // Si no es admin, cargar permisos granulares
        const { data } = await supabase
          .from("rol_permisos")
          .select("*")
          .eq("rol_id", userData.rol_id);
        setPermisos(data || []);
      }

      // Fallback: users.role = "admin" ya lo cubre isAdmin arriba
      setLoaded(true);
    };

    fetchPermisos();
  }, [user?.id]);

  const canAccess = useCallback((pantalla: string): boolean => {
    if (isAdmin) return true;
    const perm = permisos.find((p) => p.pantalla === pantalla);
    if (perm) return perm.visible;
    // Fallback to defaults for operario
    return DEFAULT_OPERARIO[pantalla]?.visible || false;
  }, [isAdmin, permisos]);

  const canDo = useCallback((pantalla: string, action: "crear" | "editar" | "eliminar" | "asignar"): boolean => {
    if (isAdmin) return true;
    const perm = permisos.find((p) => p.pantalla === pantalla);
    if (perm) return !!(perm as any)[action];
    return !!(DEFAULT_OPERARIO[pantalla] as any)?.[action] || false;
  }, [isAdmin, permisos]);

  // Screens that should appear in the sidebar
  const visibleScreens = useCallback((): Set<string> => {
    if (isAdmin) return new Set(["dashboard", "planificacion", "obras", "partes",
      "apps_georadar",
      "almacen_articulos", "almacen_tipos_articulo", "almacen_almacenes", "almacen_proveedores", "almacen_movimientos",
      "maestros_rrhh", "maestros_vehiculos",
      "maestros_clientes", "maestros_estados", "maestros_tipos_trabajo", "maestros_tipos_obra",
      "logs", "configuracion"]);

    const screens = new Set<string>();
    // From DB permissions
    permisos.forEach((p) => { if (p.visible) screens.add(p.pantalla); });
    // Always add defaults
    Object.entries(DEFAULT_OPERARIO).forEach(([k, v]) => { if (v.visible) screens.add(k); });
    return screens;
  }, [isAdmin, permisos]);

  return { isAdmin, canAccess, canDo, visibleScreens, loaded };
}
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\hooks\usePermissions.ts" -ForegroundColor Green

$dst = "src\app\api\users\route.ts"
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { action } = body;
    const supabase = createAdminClient();

    // ---- CREATE USER ----
    if (action === "create") {
      const { nombre, perfil, telefono, email, password, role, rol_id, foto_url } = body;
      if (!nombre || !email || !password) {
        return NextResponse.json({ error: "Nombre, email y contraseña son obligatorios" }, { status: 400 });
      }

      // 1. Create auth user
      const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email, password, email_confirm: true,
      });
      if (authError) return NextResponse.json({ error: `Error auth: ${authError.message}` }, { status: 400 });
      const authId = authData.user.id;

      // 2. Create recurso_humano
      const { data: recurso, error: recursoError } = await supabase
        .from("recursos_humanos")
        .insert({ nombre, perfil: perfil || null, telefono: telefono || null, email, foto_url: foto_url || null, activo: true } as any)
        .select().single();
      if (recursoError) {
        await supabase.auth.admin.deleteUser(authId);
        return NextResponse.json({ error: `Error recurso: ${recursoError.message}` }, { status: 400 });
      }

      // 3. Create users profile — incluir role correcto segun rol_id si es admin
      const { error: profileError } = await (supabase.from("users") as any)
        .insert({ id: authId, email, nombre, role: role || "partes", rol_id: rol_id || null, recurso_id: recurso.id, activo: true });
      if (profileError) {
        await (supabase.from("recursos_humanos") as any).delete().eq("id", recurso.id);
        await supabase.auth.admin.deleteUser(authId);
        return NextResponse.json({ error: `Error perfil: ${profileError.message}` }, { status: 400 });
      }

      // 4. Auditoria
      await (supabase.from("audit_log") as any).insert({
        accion: "crear", entidad: "users", modulo: "usuarios",
        descripcion: `Usuario creado: ${email}`, resultado: "exito", origen: "api_route",
      });

      return NextResponse.json({ success: true, recurso_id: recurso.id, user_id: authId });
    }

    // ---- UPDATE USER ----
    if (action === "update") {
      const { recurso_id, nombre, perfil, telefono, email, password, role, rol_id, foto_url } = body;
      if (!recurso_id) return NextResponse.json({ error: "recurso_id obligatorio" }, { status: 400 });

      // Update recurso_humano
      await (supabase.from("recursos_humanos") as any).update({
        nombre, perfil: perfil || null, telefono: telefono || null, email, foto_url: foto_url || null,
      }).eq("id", recurso_id);

      // Find linked user
      const { data: userRow } = await supabase.from("users").select("id").eq("recurso_id", recurso_id).single();
      if (userRow) {
        // Actualizar perfil (role + rol_id siempre juntos)
        await (supabase.from("users") as any).update({
          nombre,
          email,
          role: role || "partes",
          rol_id: rol_id || null,
        }).eq("id", userRow.id);

        // Actualizar email en Auth si cambio
        await supabase.auth.admin.updateUserById(userRow.id, { email });

        // Cambiar contraseña SOLO si se proporcionó una nueva (minimo 6 chars)
        if (password && password.trim().length >= 6) {
          const { error: pwErr } = await supabase.auth.admin.updateUserById(userRow.id, { password: password.trim() });
          if (pwErr) {
            return NextResponse.json({ error: `Error al cambiar contraseña: ${pwErr.message}` }, { status: 400 });
          }
          // Auditoria de cambio de contraseña — SIN guardar la contraseña
          await (supabase.from("audit_log") as any).insert({
            accion: "editar", entidad: "users", modulo: "usuarios",
            entidad_id: userRow.id,
            descripcion: `Contraseña cambiada por admin para: ${email}`,
            resultado: "exito", origen: "api_route",
          });
        }

        // Auditoria de actualización general
        await (supabase.from("audit_log") as any).insert({
          accion: "editar", entidad: "users", modulo: "usuarios",
          entidad_id: userRow.id,
          descripcion: `Perfil actualizado: ${email} — rol: ${role || "partes"}`,
          resultado: "exito", origen: "api_route",
        });

      } else if (email && password && password.trim().length >= 6) {
        // No auth user exists — crear uno nuevo
        const { data: authData, error: authError } = await supabase.auth.admin.createUser({
          email, password: password.trim(), email_confirm: true,
        });
        if (!authError && authData?.user) {
          await (supabase.from("users") as any).insert({
            id: authData.user.id, email, nombre,
            role: role || "partes",
            rol_id: rol_id || null,
            recurso_id, activo: true,
          });
        }
      }

      return NextResponse.json({ success: true });
    }

    // ---- RESET PASSWORD (enviar email de recuperación) ----
    // Accion alternativa: el admin puede enviar un email de reset en vez de cambiar directamente
    if (action === "send_reset") {
      const { email } = body;
      if (!email) return NextResponse.json({ error: "Email obligatorio" }, { status: 400 });
      // Usamos el cliente de Supabase con la service role pero el reset link
      // se genera para que el usuario lo reciba y cambie por su cuenta
      const { error } = await supabase.auth.resetPasswordForEmail(email);
      if (error) return NextResponse.json({ error: error.message }, { status: 400 });
      await (supabase.from("audit_log") as any).insert({
        accion: "editar", entidad: "users", modulo: "usuarios",
        descripcion: `Email de recuperación de contraseña enviado a: ${email}`,
        resultado: "exito", origen: "api_route",
      });
      return NextResponse.json({ success: true });
    }

    // ---- TOGGLE ACCESS ----
    if (action === "toggle_access") {
      const { recurso_id, activo } = body;
      const { data: userRow } = await supabase.from("users").select("id, email").eq("recurso_id", recurso_id).single();
      if (userRow) {
        await (supabase.from("users") as any).update({ activo }).eq("id", userRow.id);
        // Banear o desbanear en Supabase Auth
        if (!activo) {
          await supabase.auth.admin.updateUserById(userRow.id, { ban_duration: "876600h" });
        } else {
          await supabase.auth.admin.updateUserById(userRow.id, { ban_duration: "none" });
        }
        await (supabase.from("audit_log") as any).insert({
          accion: "editar", entidad: "users", modulo: "usuarios",
          entidad_id: userRow.id,
          descripcion: `Acceso ${activo ? "activado" : "desactivado"} para: ${(userRow as any).email}`,
          resultado: "exito", origen: "api_route",
        });
      }
      await (supabase.from("recursos_humanos") as any).update({ activo }).eq("id", recurso_id);
      return NextResponse.json({ success: true });
    }

    // ---- SYNC ALL USERS ----
    // IMPORTANTE: sync NUNCA cambia contraseñas de usuarios existentes.
    // Solo crea perfiles faltantes o vincula los que no estén enlazados.
    if (action === "sync") {
      const { data: recursos } = await supabase.from("recursos_humanos").select("*");
      const { data: authUsers } = await supabase.auth.admin.listUsers();
      const { data: profiles } = await supabase.from("users").select("id, recurso_id, email, role, rol_id");

      const profileRecursoIds = new Set((profiles || []).map((p: any) => p.recurso_id).filter(Boolean));

      let created = 0;
      let linked = 0;
      let errors: string[] = [];

      for (const recurso of (recursos || [])) {
        if (!recurso.email) continue;
        const email = recurso.email.toLowerCase();

        // Buscar si existe auth user
        const existingAuth = (authUsers?.users || []).find((u: any) => u.email?.toLowerCase() === email);

        if (!existingAuth) {
          // Solo crear si no existe en Auth. Contraseña temporal — el usuario debe cambiarla.
          const tempPass = "TempObrasPlan2024!";
          const { data: newAuth, error: authErr } = await supabase.auth.admin.createUser({
            email: recurso.email,
            password: tempPass,
            email_confirm: true,
          });
          if (authErr) {
            errors.push(`${recurso.nombre}: ${authErr.message}`);
            continue;
          }
          if (!profileRecursoIds.has(recurso.id)) {
            await (supabase.from("users") as any).insert({
              id: newAuth.user.id,
              email: recurso.email,
              nombre: recurso.nombre,
              role: "partes",
              recurso_id: recurso.id,
              activo: recurso.activo,
            });
          }
          created++;
        } else {
          // Auth existe — solo vincular perfil si falta, SIN tocar contraseña
          if (!profileRecursoIds.has(recurso.id)) {
            const existingProfile = (profiles || []).find((p: any) => p.id === existingAuth.id);
            if (existingProfile) {
              await (supabase.from("users") as any).update({ recurso_id: recurso.id }).eq("id", existingAuth.id);
            } else {
              await (supabase.from("users") as any).insert({
                id: existingAuth.id,
                email: recurso.email,
                nombre: recurso.nombre,
                role: "partes",
                recurso_id: recurso.id,
                activo: recurso.activo,
              });
            }
            linked++;
          }
        }
      }

      const msg = `Sincronización completada: ${created} usuarios nuevos creados, ${linked} vinculados${errors.length > 0 ? `, ${errors.length} errores` : ""}.${created > 0 ? " Los nuevos usuarios deben cambiar su contraseña temporal." : ""}`;

      return NextResponse.json({ success: true, created, linked, errors, message: msg });
    }

    return NextResponse.json({ error: "Acción no válida" }, { status: 400 });
  } catch (err: any) {
    return NextResponse.json({ error: err.message || "Error interno" }, { status: 500 });
  }
}
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\api\users\route.ts" -ForegroundColor Green

Write-Host ""
Write-Host "==> Verificando" -ForegroundColor Cyan
$ok1 = Select-String -Path "src\components\layout\AppLayout.tsx" -Pattern "isLoading" -Quiet
$ok2 = Select-String -Path "src\hooks\usePermissions.ts" -Pattern "isAdminFromRole" -Quiet
$ok3 = Select-String -Path "src\app\api\users\route.ts" -Pattern "sync NUNCA" -Quiet
if ($ok1) { Write-Host "    OK: AppLayout usa isLoading correctamente" -ForegroundColor Green }
else { Write-Host "    ERROR: AppLayout aun usa 'loading'" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: usePermissions comprueba is_admin del rol" -ForegroundColor Green }
else { Write-Host "    ERROR: usePermissions sin doble check admin" -ForegroundColor Red }
if ($ok3) { Write-Host "    OK: API sync corregida" -ForegroundColor Green }
else { Write-Host "    ERROR: API sync no actualizada" -ForegroundColor Red }

Write-Host ""
Write-Host "PASO SIGUIENTE OBLIGATORIO:" -ForegroundColor Yellow
Write-Host "  Ejecutar fix-usuarios-roles.sql en Supabase SQL Editor"
Write-Host "  Esto sincroniza users.role='admin' para Sergio y cualquier otro admin"
Write-Host ""
Write-Host '  git add src\components\layout\AppLayout.tsx src\hooks\usePermissions.ts src\app\api\users\route.ts'
Write-Host '  git commit -m "fix: auth - isLoading, admin doble check, sync sin contrasenas"'
Write-Host '  git push'
