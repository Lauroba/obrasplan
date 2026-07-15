"use client";

import { useState, useEffect, useCallback, Suspense, useRef } from "react";
import type React from "react";
import { useSearchParams } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import PhotoUpload from "@/components/shared/PhotoUpload";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { RecursoHumano } from "@/lib/types/database";
import { Users, Loader2, ShieldCheck, UserX, UserCheck, Eye, EyeOff, CalendarOff } from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils/cn";

interface RHWithUser extends RecursoHumano { user_role?: string; user_activo?: boolean; user_id?: string; }

const emptyForm = { nombre: "", perfil: "", telefono: "", email: "", password: "", role: "partes", rol_id: "", foto_url: "", asignable: true, fecha_inicio: new Date().toISOString().slice(0, 10), fecha_fin: "" };

// Componente interno que usa useSearchParams — envuelto en Suspense
function EditFromURL({ data, puedeEditar, setForm, setEditingId, setEditingActivo, setError, setModalOpen, emptyFormRef }: {
  data: RHWithUser[]; puedeEditar: boolean;
  setForm: (f: any) => void; setEditingId: (id: string | null) => void;
  setEditingActivo: (v: boolean) => void; setError: (e: string) => void;
  setModalOpen: (v: boolean) => void; emptyFormRef: React.MutableRefObject<typeof emptyForm>;
}) {
  const searchParams = useSearchParams();
  useEffect(() => {
    const editId = searchParams.get("edit");
    if (!editId || !puedeEditar || data.length === 0) return;
    const item = data.find((r) => r.id === editId);
    if (!item) return;
    setForm({ nombre: item.nombre, perfil: item.perfil || "", telefono: item.telefono || "", email: item.email || "", password: "", role: item.user_role || "partes", rol_id: (item as any).user_rol_id || "", foto_url: item.foto_url || "", asignable: (item as any).asignable !== false, fecha_inicio: (item as any).fecha_inicio || new Date().toISOString().slice(0, 10), fecha_fin: (item as any).fecha_fin || "" });
    setEditingId(editId); setEditingActivo(item.user_activo !== false); setError(""); setModalOpen(true);
  }, [searchParams, data, puedeEditar]);
  return null;
}

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
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("maestros_rrhh", "crear");
  const puedeEditar   = isAdmin || canDo("maestros_rrhh", "editar");
  const puedeEliminar = isAdmin || canDo("maestros_rrhh", "eliminar");
  const supabase = createClient();
  const emptyFormRef = { current: emptyForm };

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
      await (supabase.from("recursos_humanos") as any).update({ asignable: form.asignable, fecha_inicio: form.fecha_inicio || null, fecha_fin: form.fecha_fin || null }).eq("id", editingId);
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
      if (newR?.[0]) {
        const updatePayload: any = { fecha_inicio: form.fecha_inicio || new Date().toISOString().slice(0, 10) };
        if (!form.asignable) updatePayload.asignable = false;
        if (form.fecha_fin) updatePayload.fecha_fin = form.fecha_fin;
        await (supabase.from("recursos_humanos") as any).update(updatePayload).eq("id", newR[0].id);
      }
    }
    setSaving(false); setModalOpen(false); fetchData();
  };

  const handleToggleAccess = async (recursoId: string, currentlyActive: boolean) => {
    const res = await fetch("/api/users", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "toggle_access", recurso_id: recursoId, activo: !currentlyActive }) });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      setDeleteBlockedMsg(json.error || "No se pudo cambiar el acceso");
      return;
    }
    fetchData();
  };

  const handleToggleAccessInModal = async () => {
    if (!editingId) return;
    setTogglingAccess(true);
    setDeleteBlockedMsg(null);
    try {
      const nuevoEstado = !editingActivo;
      const res = await fetch("/api/users", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "toggle_access", recurso_id: editingId, activo: nuevoEstado }),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        setDeleteBlockedMsg(json.error || "No se pudo cambiar el acceso");
        return;
      }
      // Si se desactiva, fijar fecha_fin = hoy en recursos_humanos
      const hoy = new Date().toISOString().slice(0, 10);
      if (!nuevoEstado) {
        await (createClient().from("recursos_humanos") as any)
          .update({ fecha_fin: hoy, activo: false })
          .eq("id", editingId);
        setForm((f: any) => ({ ...f, fecha_fin: hoy }));
      } else {
        await (createClient().from("recursos_humanos") as any)
          .update({ fecha_fin: null, activo: true })
          .eq("id", editingId);
        setForm((f: any) => ({ ...f, fecha_fin: "" }));
      }
      setEditingActivo(nuevoEstado);
      fetchData();
    } catch (err: any) {
      setDeleteBlockedMsg(err.message || "Error al cambiar el acceso");
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
      <Link href={`/maestros/recursos-humanos/${item.id}`} className="flex items-center gap-3 group">
        {item.foto_url ? <img src={item.foto_url} alt="" className="w-8 h-8 rounded-full object-cover shrink-0" /> :
          <div className="w-8 h-8 rounded-full bg-brand-100 flex items-center justify-center text-brand-700 text-xs font-semibold shrink-0">{item.nombre.split(" ").map(w => w[0]).join("").slice(0, 2).toUpperCase()}</div>}
        <div>
          <span className="font-medium text-surface-900 group-hover:text-brand-600 transition-colors">{item.nombre}</span>
          {!item.user_activo && <span className="ml-2 text-[10px] text-red-500 font-medium">SIN ACCESO</span>}
          {(item as any).asignable === false && <span className="ml-1 text-[10px] text-amber-500 font-medium">NO PLANIF.</span>}
        </div>
      </Link>
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
      <Suspense fallback={null}>
        <EditFromURL data={data} puedeEditar={puedeEditar} setForm={setForm} setEditingId={setEditingId} setEditingActivo={setEditingActivo} setError={setError} setModalOpen={setModalOpen} emptyFormRef={emptyFormRef} />
      </Suspense>
      <DataTable data={data} columns={columns} title="Trabajadores" loading={loading} searchPlaceholder="Buscar por nombre, perfil, email..." searchKeys={["nombre", "perfil", "email", "telefono"]}
        onAdd={isAdmin ? () => { setForm(emptyForm); setEditingId(null); setError(""); setModalOpen(true); } : undefined}
        onEdit={isAdmin ? (item) => { setForm({ nombre: item.nombre, perfil: item.perfil || "", telefono: item.telefono || "", email: item.email || "", password: "", role: item.user_role || "partes", rol_id: (item as any).user_rol_id || "", foto_url: item.foto_url || "", asignable: (item as any).asignable !== false, fecha_inicio: (item as any).fecha_inicio || new Date().toISOString().slice(0, 10), fecha_fin: (item as any).fecha_fin || "" }); setEditingId(item.id); setEditingActivo(item.user_activo !== false); setError(""); setModalOpen(true); } : undefined}
        addLabel="Nuevo trabajador" canAdd={isAdmin} canEdit={isAdmin} canDelete={isAdmin} onDelete={handleDelete} />
      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar trabajador" : "Nuevo trabajador"} size="lg">
        <form onSubmit={handleSubmit} className="space-y-4">
          {error && <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">{error}</div>}
          {deleteBlockedMsg && <div className="p-3 bg-amber-50 border border-amber-200 rounded-lg text-sm text-amber-800">{deleteBlockedMsg}</div>}
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
          {/* Fechas de disponibilidad */}
          <div className="border-t border-surface-200 pt-4">
            <p className="text-sm font-medium text-surface-900 mb-3">Disponibilidad en planificador</p>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-surface-600 mb-1">Fecha inicio *</label>
                <input type="date" className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none"
                  value={form.fecha_inicio}
                  onChange={(e) => setForm({ ...form, fecha_inicio: e.target.value })} />
                <p className="text-[10px] text-surface-400 mt-1">Desde cuándo aparece en el planificador</p>
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-600 mb-1">Fecha fin</label>
                <input type="date" className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none"
                  value={form.fecha_fin}
                  onChange={(e) => setForm({ ...form, fecha_fin: e.target.value })} />
                <p className="text-[10px] text-surface-400 mt-1">Vacío = disponible indefinidamente</p>
              </div>
            </div>
          </div>
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