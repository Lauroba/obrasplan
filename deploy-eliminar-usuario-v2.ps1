#Requires -Version 5.1
# deploy-eliminar-usuario-v2.ps1
#
# 1. FALLBACK AUTOMATICO al eliminar: si Supabase Auth no permite el borrado
#    fisico (error interno tipo "Database error deleting user", causado por
#    tablas internas del esquema auth como identities/sessions/mfa_factors
#    que no podemos inspeccionar ni limpiar desde SQL normal), el sistema
#    YA NO deja al usuario en estado de error. En su lugar lo desactiva
#    automaticamente (ban + activo=false), deja constancia en audit_log,
#    y avisa con un mensaje claro de que se uso el fallback.
#
# 2. Boton "Desactivar acceso" / "Activar acceso" ahora tambien dentro
#    del modal de edicion del trabajador (antes solo estaba en la columna
#    de la tabla).

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Escribiendo archivos" -ForegroundColor Cyan

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

    // ---- DELETE USER (fisico) ----
    // Solo permite borrado fisico si el usuario NO tiene historial vinculado
    // (partes_diarios.created_by es RESTRICT -> el DELETE fallaria igualmente,
    // pero comprobamos antes para dar un mensaje claro y no intentar un borrado
    // parcial que deje datos inconsistentes).
    if (action === "delete") {
      const { recurso_id } = body;
      if (!recurso_id) return NextResponse.json({ error: "recurso_id obligatorio" }, { status: 400 });

      const { data: recurso } = await supabase.from("recursos_humanos").select("id, nombre, email").eq("id", recurso_id).single();
      if (!recurso) return NextResponse.json({ error: "Recurso no encontrado" }, { status: 404 });

      const { data: userRow } = await supabase.from("users").select("id, email").eq("recurso_id", recurso_id).maybeSingle();

      // Comprobar historial vinculado antes de borrar nada
      const blocking: string[] = [];

      if (userRow) {
        const { count: partesCount } = await supabase
          .from("partes_diarios").select("id", { count: "exact", head: true }).eq("created_by", userRow.id);
        if ((partesCount || 0) > 0) blocking.push(`${partesCount} parte(s) diario(s) creado(s)`);

        const { count: movCount } = await supabase
          .from("movimientos_almacen").select("id", { count: "exact", head: true }).eq("created_by", userRow.id);
        if ((movCount || 0) > 0) blocking.push(`${movCount} movimiento(s) de almacén registrado(s)`);
      }

      const { count: trabajadorCount } = await supabase
        .from("parte_trabajadores").select("id", { count: "exact", head: true }).eq("recurso_id", recurso_id);
      if ((trabajadorCount || 0) > 0) blocking.push(`${trabajadorCount} presencia(s) en partes diarios`);

      const { count: asigCount } = await supabase
        .from("asignaciones").select("id", { count: "exact", head: true })
        .eq("recurso_tipo", "humano").eq("recurso_id", recurso_id);
      if ((asigCount || 0) > 0) blocking.push(`${asigCount} asignación(es) en el planificador`);

      if (userRow) {
        const { count: checklistCount } = await supabase
          .from("checklists").select("id", { count: "exact", head: true }).eq("created_by", userRow.id);
        if ((checklistCount || 0) > 0) blocking.push(`${checklistCount} checklist(s) creado(s)`);

        const { count: checklistItemCount } = await supabase
          .from("checklist_items").select("id", { count: "exact", head: true }).eq("completado_por", userRow.id);
        if ((checklistItemCount || 0) > 0) blocking.push(`${checklistItemCount} item(s) de checklist completado(s)`);

        const { count: notaCreCount } = await supabase
          .from("planificador_notas").select("id", { count: "exact", head: true }).eq("created_by", userRow.id);
        const { count: notaUpdCount } = await supabase
          .from("planificador_notas").select("id", { count: "exact", head: true }).eq("updated_by", userRow.id);
        if ((notaCreCount || 0) + (notaUpdCount || 0) > 0) blocking.push(`${(notaCreCount || 0) + (notaUpdCount || 0)} nota(s) del planificador`);

        const { count: conflictoCount } = await supabase
          .from("conflictos_revisados").select("id", { count: "exact", head: true }).eq("revisado_por", userRow.id);
        if ((conflictoCount || 0) > 0) blocking.push(`${conflictoCount} conflicto(s) revisado(s)`);

        const { count: tareaCompCount } = await supabase
          .from("tareas").select("id", { count: "exact", head: true }).eq("completada_by", userRow.id);
        if ((tareaCompCount || 0) > 0) blocking.push(`${tareaCompCount} tarea(s) completada(s) por este usuario`);

        const { count: georadarCount } = await supabase
          .from("georadar_pasadas").select("id", { count: "exact", head: true }).eq("created_by", userRow.id);
        if ((georadarCount || 0) > 0) blocking.push(`${georadarCount} pasada(s) de georadar`);
      }

      if (blocking.length > 0) {
        return NextResponse.json({
          error: `No se puede eliminar: este usuario tiene historial vinculado (${blocking.join(", ")}). Usa "Desactivar acceso" en su lugar para conservar la trazabilidad.`,
          blocked: true,
          details: blocking,
        }, { status: 409 });
      }

      // Sin historial vinculado: borrado fisico seguro.
      // Orden importante: primero Auth (lo mas dificil de revertir/mas propenso
      // a fallar por constraints internas de Supabase no siempre visibles
      // desde el esquema public), y solo si funciona se borra el resto.
      if (userRow) {
        const { error: authDelErr } = await supabase.auth.admin.deleteUser(userRow.id);

        if (authDelErr) {
          // FALLBACK AUTOMATICO: si Supabase no permite el borrado fisico
          // (error interno "Database error deleting user", frecuente cuando
          // hay tablas del esquema auth -- identities, sessions, mfa_factors --
          // con registros para ese usuario), no dejamos al usuario en error:
          // lo desactivamos de forma segura, que es el resultado funcional
          // equivalente (pierde acceso por completo).
          await supabase.auth.admin.updateUserById(userRow.id, { ban_duration: "876600h" });
          await (supabase.from("users") as any).update({ activo: false }).eq("id", userRow.id);
          await (supabase.from("recursos_humanos") as any).update({ activo: false }).eq("id", recurso_id);

          await (supabase.from("audit_log") as any).insert({
            accion: "editar", entidad: "users", modulo: "usuarios",
            entidad_id: userRow.id,
            descripcion: `Eliminación física no disponible (${authDelErr.message}). Usuario desactivado como alternativa: ${recurso.email || recurso.nombre}`,
            resultado: "exito", origen: "api_route",
          });

          return NextResponse.json({
            success: true,
            fallback: true,
            message: `No fue posible eliminar físicamente el usuario de Supabase Auth (limitación interna de Supabase). En su lugar, se ha desactivado por completo: ya no puede acceder a la aplicación. Su historial y registro permanecen, pero sin acceso.`,
          });
        }

        // Auth borrado con exito -> el perfil de public.users se borra
        // automaticamente por el ON DELETE CASCADE, pero lo forzamos
        // explicitamente por si acaso.
        await (supabase.from("users") as any).delete().eq("id", userRow.id);
      }

      // Borrar el recurso humano
      const { error: recursoDelErr } = await (supabase.from("recursos_humanos") as any).delete().eq("id", recurso_id);
      if (recursoDelErr) {
        return NextResponse.json({ error: `Usuario eliminado de Auth y de la app, pero no se pudo borrar el recurso humano: ${recursoDelErr.message}` }, { status: 500 });
      }

      // 4. Auditoria
      await (supabase.from("audit_log") as any).insert({
        accion: "eliminar", entidad: "users", modulo: "usuarios",
        descripcion: `Usuario eliminado completamente (app + servidor Auth): ${recurso.email || recurso.nombre}`,
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

$dst = "src\app\maestros\recursos-humanos\page.tsx"
$content = @'
"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import PhotoUpload from "@/components/shared/PhotoUpload";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import type { RecursoHumano } from "@/lib/types/database";
import { Users, Loader2, ShieldCheck, UserX, UserCheck, Eye, EyeOff, CalendarOff } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface RHWithUser extends RecursoHumano { user_role?: string; user_activo?: boolean; user_id?: string; }

const emptyForm = { nombre: "", perfil: "", telefono: "", email: "", password: "", role: "partes", rol_id: "", foto_url: "", asignable: true };

export default function RecursosHumanosPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<RHWithUser[]>([]); const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false); const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null); const [saving, setSaving] = useState(false);
  const [error, setError] = useState(""); const [showPassword, setShowPassword] = useState(false);
  const [syncing, setSyncing] = useState(false); const [syncResult, setSyncResult] = useState("");
  const [deleteBlockedMsg, setDeleteBlockedMsg] = useState<string | null>(null);
  const [editingActivo, setEditingActivo] = useState(true);
  const [togglingAccess, setTogglingAccess] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [dbRoles, setDbRoles] = useState<{ id: string; nombre: string; is_admin: boolean }[]>([]);
  const isAdmin = user?.role === "admin"; const supabase = createClient();

  const fetchData = useCallback(async () => {
    setLoading(true);
    const { data: recursos } = await supabase.from("recursos_humanos").select("*").order("nombre");
    const { data: users } = await supabase.from("users").select("id, recurso_id, role, activo, rol_id");
    const { data: rolesData } = await supabase.from("roles").select("id, nombre, is_admin").order("nombre");
    setDbRoles(rolesData || []);
    const userMap: Record<string, { role: string; activo: boolean; id: string; rol_id: string | null }> = {};
    (users || []).forEach((u: any) => { if (u.recurso_id) userMap[u.recurso_id] = { role: u.role, activo: u.activo, id: u.id, rol_id: u.rol_id }; });
    const rolesMap: Record<string, string> = {};
    (rolesData || []).forEach((r: any) => { rolesMap[r.id] = r.nombre; });
    const enriched = (recursos || []).map((r: any) => ({
      ...r,
      user_role: userMap[r.id]?.role, user_activo: userMap[r.id]?.activo ?? r.activo, user_id: userMap[r.id]?.id,
      user_rol_id: userMap[r.id]?.rol_id,
      user_rol_nombre: userMap[r.id]?.rol_id ? rolesMap[userMap[r.id]?.rol_id!] || "Sin rol" : "Sin rol",
    }));
    setData(enriched); setLoading(false);
  }, []);
  useEffect(() => { fetchData(); }, [fetchData]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); setError(""); setSaving(true);
    // Update asignable flag directly on recurso
    if (editingId) {
      await (supabase.from("recursos_humanos") as any).update({ asignable: form.asignable }).eq("id", editingId);
    }
    try {
      const res = await fetch("/api/users", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: editingId ? "update" : "create", recurso_id: editingId,
          nombre: form.nombre, perfil: form.perfil, telefono: form.telefono, email: form.email,
          password: form.password, role: form.role, rol_id: form.rol_id, foto_url: form.foto_url,
        }),
      });
      const result = await res.json();
      if (!res.ok) { setError(result.error || "Error"); setSaving(false); return; }
    } catch (err: any) { setError(err.message || "Error"); setSaving(false); return; }
    // If creating new, also set asignable
    if (!editingId) {
      // Find the newly created recurso by name+email
      const { data: newR } = await supabase.from("recursos_humanos").select("id").eq("email", form.email).order("created_at", { ascending: false }).limit(1);
      if (newR?.[0] && !form.asignable) {
        await (supabase.from("recursos_humanos") as any).update({ asignable: false }).eq("id", newR[0].id);
      }
    }
    setSaving(false); setModalOpen(false); fetchData();
  };

  const handleToggleAccess = async (recursoId: string, currentlyActive: boolean) => {
    await fetch("/api/users", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "toggle_access", recurso_id: recursoId, activo: !currentlyActive }) });
    fetchData();
  };

  const handleToggleAccessInModal = async () => {
    if (!editingId) return;
    setTogglingAccess(true);
    try {
      await fetch("/api/users", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "toggle_access", recurso_id: editingId, activo: !editingActivo }),
      });
      setEditingActivo(!editingActivo);
      fetchData();
    } finally { setTogglingAccess(false); }
  };

  const handleDelete = async (item: RHWithUser) => {
    setDeleteBlockedMsg(null);
    setDeleting(true);
    try {
      const res = await fetch("/api/users", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "delete", recurso_id: item.id }),
      });
      const json = await res.json();
      if (!res.ok) {
        setDeleteBlockedMsg(json.error || "No se pudo eliminar el usuario");
        return;
      }
      fetchData();
    } catch (err: any) {
      setDeleteBlockedMsg(err.message || "Error al eliminar");
    } finally { setDeleting(false); }
  };

  const handleSync = async () => {
    setSyncing(true); setSyncResult("");
    try { const res = await fetch("/api/users", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "sync" }) }); const result = await res.json(); setSyncResult(result.message || "Sincronización completada"); fetchData(); }
    catch (err: any) { setSyncResult("Error: " + err.message); }
    setSyncing(false); setTimeout(() => setSyncResult(""), 8000);
  };

  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  const columns: Column<RHWithUser>[] = [
    { key: "nombre", header: "Nombre", render: (item) => (
      <div className="flex items-center gap-3">
        {item.foto_url ? <img src={item.foto_url} alt="" className="w-8 h-8 rounded-full object-cover shrink-0" /> :
          <div className="w-8 h-8 rounded-full bg-brand-100 flex items-center justify-center text-brand-700 text-xs font-semibold shrink-0">{item.nombre.split(" ").map(w => w[0]).join("").slice(0, 2).toUpperCase()}</div>}
        <div>
          <span className="font-medium text-surface-900">{item.nombre}</span>
          {!item.user_activo && <span className="ml-2 text-[10px] text-red-500 font-medium">SIN ACCESO</span>}
          {(item as any).asignable === false && <span className="ml-1 text-[10px] text-amber-500 font-medium">NO PLANIF.</span>}
        </div>
      </div>
    )},
    { key: "perfil", header: "Perfil" },
    { key: "email", header: "Email" },
    { key: "user_role", header: "Rol", render: (item) => (
      <span className={cn("badge text-[10px]", (item as any).user_rol_nombre === "Administrador" ? "bg-brand-100 text-brand-700" : "bg-surface-100 text-surface-600")}>{(item as any).user_rol_nombre || "Sin rol"}</span>
    )},
    { key: "user_activo", header: "Acceso", render: (item) => (
      <button onClick={() => isAdmin && handleToggleAccess(item.id, !!item.user_activo)}
        className={cn("flex items-center gap-1 text-[11px] font-medium px-2 py-1 rounded-lg", item.user_activo ? "text-emerald-700 bg-emerald-50 hover:bg-emerald-100" : "text-red-700 bg-red-50 hover:bg-red-100")} disabled={!isAdmin}>
        {item.user_activo ? <UserCheck className="w-3.5 h-3.5" /> : <UserX className="w-3.5 h-3.5" />}{item.user_activo ? "Activo" : "Inactivo"}
      </button>
    )},
  ];

  return (
    <AppLayout><div className="max-w-7xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6">
        <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center"><Users className="w-5 h-5 text-brand-600" /></div>
        <div><h1 className="text-xl font-display font-bold text-surface-900">Recursos Humanos</h1><p className="text-sm text-surface-500">Trabajadores y usuarios de la aplicación</p></div>
        {isAdmin && <button onClick={handleSync} disabled={syncing} className="flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-white bg-violet-500 rounded-lg hover:bg-violet-600 disabled:opacity-60 ml-auto shrink-0">{syncing ? <Loader2 className="w-4 h-4 animate-spin" /> : <UserCheck className="w-4 h-4" />}Sincronizar usuarios</button>}
      </div>
      {syncResult && <div className="mb-4 p-3 bg-violet-50 border border-violet-200 rounded-lg text-sm text-violet-700">{syncResult}</div>}
      {deleteBlockedMsg && (
        <div className="mb-4 p-3 bg-amber-50 border border-amber-200 rounded-lg text-sm text-amber-800 flex items-start justify-between gap-3">
          <span>{deleteBlockedMsg}</span>
          <button onClick={() => setDeleteBlockedMsg(null)} className="text-amber-500 hover:text-amber-700 shrink-0">✕</button>
        </div>
      )}
      <DataTable data={data} columns={columns} title="Trabajadores" loading={loading} searchPlaceholder="Buscar por nombre, perfil, email..." searchKeys={["nombre", "perfil", "email", "telefono"]}
        onAdd={isAdmin ? () => { setForm(emptyForm); setEditingId(null); setError(""); setModalOpen(true); } : undefined}
        onEdit={isAdmin ? (item) => { setForm({ nombre: item.nombre, perfil: item.perfil || "", telefono: item.telefono || "", email: item.email || "", password: "", role: item.user_role || "partes", rol_id: (item as any).user_rol_id || "", foto_url: item.foto_url || "", asignable: (item as any).asignable !== false }); setEditingId(item.id); setEditingActivo(item.user_activo !== false); setError(""); setModalOpen(true); } : undefined}
        addLabel="Nuevo trabajador" canAdd={isAdmin} canEdit={isAdmin} canDelete={isAdmin} onDelete={handleDelete} />
      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar trabajador" : "Nuevo trabajador"} size="lg">
        <form onSubmit={handleSubmit} className="space-y-4">
          {error && <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">{error}</div>}
          <div className="flex items-start gap-5">
            <PhotoUpload currentUrl={form.foto_url || null} folder="humano" entityId={editingId || undefined} size="lg" onUploaded={(url) => setForm({ ...form, foto_url: url })} onRemoved={() => setForm({ ...form, foto_url: "" })} />
            <div className="flex-1 space-y-4">
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre completo *</label><input type="text" required value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="Ej: Juan García Pérez" className={ic} /></div>
              <div className="grid grid-cols-2 gap-4">
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Perfil / Puesto</label>
                  <select value={form.perfil} onChange={(e) => setForm({ ...form, perfil: e.target.value })} className={ic}><option value="">Seleccionar...</option><option value="Encargado de obra">Encargado de obra</option><option value="Oficial 1ª">Oficial 1ª</option><option value="Oficial 2ª">Oficial 2ª</option><option value="Peón especialista">Peón especialista</option><option value="Peón">Peón</option><option value="Administrativo">Administrativo</option><option value="Técnico">Técnico</option></select>
                </div>
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Teléfono</label><input type="tel" value={form.telefono} onChange={(e) => setForm({ ...form, telefono: e.target.value })} placeholder="600 000 000" className={ic} /></div>
              </div>
            </div>
          </div>
          <div className="border-t border-surface-200 pt-4">
            <div className="flex items-center gap-2 mb-3"><ShieldCheck className="w-4 h-4 text-brand-600" /><h3 className="text-sm font-semibold text-surface-900">Acceso a la aplicación</h3></div>
            <div className="grid grid-cols-3 gap-4">
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Email de acceso *</label><input type="email" required value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} placeholder="trabajador@loynek.es" className={ic} /></div>
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">{editingId ? "Nueva contraseña" : "Contraseña *"}</label>
                <div className="relative"><input type={showPassword ? "text" : "password"} value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} placeholder={editingId ? "Dejar vacío para no cambiar" : "Mínimo 6 caracteres"} required={!editingId} minLength={editingId ? 0 : 6} className={ic + " pr-10"} />
                  <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-3 top-1/2 -translate-y-1/2 text-surface-400">{showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}</button>
                </div>
              </div>
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Rol</label>
                <select value={form.rol_id} onChange={(e) => { const rol = dbRoles.find((r) => r.id === e.target.value); setForm({ ...form, rol_id: e.target.value, role: rol?.is_admin ? "admin" : "partes" }); }} className={ic}><option value="">Sin rol</option>{dbRoles.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select>
              </div>
            </div>
          </div>
          {/* Activar/Desactivar acceso (solo al editar) */}
          {editingId && (
            <div className="border-t border-surface-200 pt-4">
              <div className="flex items-center justify-between">
                <div>
                  <span className="text-sm font-medium text-surface-900">Acceso a la aplicación</span>
                  <p className="text-xs text-surface-400">{editingActivo ? "Este usuario puede iniciar sesión." : "Este usuario NO puede iniciar sesión."}</p>
                </div>
                <button type="button" onClick={handleToggleAccessInModal} disabled={togglingAccess}
                  className={cn("flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg disabled:opacity-60",
                    editingActivo ? "text-red-700 bg-red-50 hover:bg-red-100" : "text-emerald-700 bg-emerald-50 hover:bg-emerald-100")}>
                  {togglingAccess && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
                  {!togglingAccess && (editingActivo ? <UserX className="w-3.5 h-3.5" /> : <UserCheck className="w-3.5 h-3.5" />)}
                  {editingActivo ? "Desactivar acceso" : "Activar acceso"}
                </button>
              </div>
            </div>
          )}
          {/* Asignable flag */}
          <div className="border-t border-surface-200 pt-4">
            <label className="flex items-center gap-3 cursor-pointer">
              <input type="checkbox" checked={form.asignable} onChange={(e) => setForm({ ...form, asignable: e.target.checked })} className="w-4 h-4 rounded border-surface-300 text-brand-600 focus:ring-brand-500" />
              <div>
                <span className="text-sm font-medium text-surface-900">Asignable en planificación</span>
                <p className="text-xs text-surface-400">Si está desactivado, no aparecerá en el panel de recursos del planificador</p>
              </div>
            </label>
          </div>
          <div className="flex items-center justify-end gap-2 pt-2">
            <button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving || !form.nombre || !form.email || (!editingId && !form.password)} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingId ? "Guardar cambios" : "Crear trabajador"}</button>
          </div>
        </form>
      </Modal>
    </div></AppLayout>
  );
}
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\maestros\recursos-humanos\page.tsx" -ForegroundColor Green

Write-Host ""
Write-Host "==> Verificando" -ForegroundColor Cyan
$ok1 = Select-String -Path "src\app\api\users\route.ts" -Pattern "fallback: true" -Quiet
$ok2 = Select-String -Path "src\app\maestros\recursos-humanos\page.tsx" -Pattern "handleToggleAccessInModal" -Quiet
if ($ok1) { Write-Host "    OK: fallback automatico en API" -ForegroundColor Green } else { Write-Host "    ERROR" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: boton acceso en modal" -ForegroundColor Green } else { Write-Host "    ERROR" -ForegroundColor Red }
Write-Host ""
Write-Host '  git add src\app\api\users\route.ts src\app\maestros\recursos-humanos\page.tsx'
Write-Host '  git commit -m "feat: fallback automatico al eliminar usuario, desactivar acceso desde modal de edicion"'
Write-Host '  git push'
