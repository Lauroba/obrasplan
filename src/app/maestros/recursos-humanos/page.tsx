"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import PhotoUpload from "@/components/shared/PhotoUpload";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import type { RecursoHumano } from "@/lib/types/database";
import { Users, Loader2, ShieldCheck, UserX, UserCheck, Eye, EyeOff } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface RHWithUser extends RecursoHumano {
  user_role?: string;
  user_activo?: boolean;
  user_id?: string;
}

const emptyForm = { nombre: "", perfil: "", telefono: "", email: "", password: "", role: "partes", foto_url: "" };

export default function RecursosHumanosPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<RHWithUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const isAdmin = user?.role === "admin";
  const supabase = createClient();

  const fetchData = useCallback(async () => {
    setLoading(true);
    // Fetch recursos_humanos + linked user info
    const { data: recursos } = await supabase.from("recursos_humanos").select("*").order("nombre");
    const { data: users } = await supabase.from("users").select("id, recurso_id, role, activo");

    const userMap: Record<string, { role: string; activo: boolean; id: string }> = {};
    (users || []).forEach((u: any) => { if (u.recurso_id) userMap[u.recurso_id] = { role: u.role, activo: u.activo, id: u.id }; });

    const enriched = (recursos || []).map((r: RecursoHumano) => ({
      ...r,
      user_role: userMap[r.id]?.role,
      user_activo: userMap[r.id]?.activo ?? r.activo,
      user_id: userMap[r.id]?.id,
    }));

    setData(enriched);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setSaving(true);

    try {
      const res = await fetch("/api/users", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: editingId ? "update" : "create",
          recurso_id: editingId,
          nombre: form.nombre,
          perfil: form.perfil,
          telefono: form.telefono,
          email: form.email,
          password: form.password,
          role: form.role,
          foto_url: form.foto_url,
        }),
      });
      const result = await res.json();
      if (!res.ok) {
        setError(result.error || "Error desconocido");
        setSaving(false);
        return;
      }
    } catch (err: any) {
      setError(err.message || "Error de conexión");
      setSaving(false);
      return;
    }

    setSaving(false);
    setModalOpen(false);
    fetchData();
  };

  const handleToggleAccess = async (recursoId: string, currentlyActive: boolean) => {
    await fetch("/api/users", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "toggle_access", recurso_id: recursoId, activo: !currentlyActive }),
    });
    fetchData();
  };

  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  const columns: Column<RHWithUser>[] = [
    { key: "nombre", header: "Nombre", render: (item) => (
      <div className="flex items-center gap-3">
        {item.foto_url ? <img src={item.foto_url} alt="" className="w-8 h-8 rounded-full object-cover shrink-0" /> :
          <div className="w-8 h-8 rounded-full bg-brand-100 flex items-center justify-center text-brand-700 text-xs font-semibold shrink-0">
            {item.nombre.split(" ").map(w => w[0]).join("").slice(0, 2).toUpperCase()}
          </div>}
        <div>
          <span className="font-medium text-surface-900">{item.nombre}</span>
          {!item.user_activo && <span className="ml-2 text-[10px] text-red-500 font-medium">SIN ACCESO</span>}
        </div>
      </div>
    )},
    { key: "perfil", header: "Perfil" },
    { key: "email", header: "Email" },
    { key: "user_role", header: "Rol", render: (item) => (
      <span className={cn("badge text-[10px]", item.user_role === "admin" ? "bg-brand-100 text-brand-700" : "bg-surface-100 text-surface-600")}>
        {item.user_role === "admin" ? "Admin" : "Estándar"}
      </span>
    )},
    { key: "user_activo", header: "Acceso", render: (item) => (
      <button onClick={() => isAdmin && handleToggleAccess(item.id, !!item.user_activo)}
        className={cn("flex items-center gap-1 text-[11px] font-medium px-2 py-1 rounded-lg transition-colors",
          item.user_activo ? "text-emerald-700 bg-emerald-50 hover:bg-emerald-100" : "text-red-700 bg-red-50 hover:bg-red-100")}
        disabled={!isAdmin}>
        {item.user_activo ? <UserCheck className="w-3.5 h-3.5" /> : <UserX className="w-3.5 h-3.5" />}
        {item.user_activo ? "Activo" : "Inactivo"}
      </button>
    )},
  ];

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center"><Users className="w-5 h-5 text-brand-600" /></div>
          <div>
            <h1 className="text-xl font-display font-bold text-surface-900">Recursos Humanos</h1>
            <p className="text-sm text-surface-500">Trabajadores y usuarios de la aplicación</p>
          </div>
        </div>

        <DataTable data={data} columns={columns} title="Trabajadores" loading={loading}
          searchPlaceholder="Buscar por nombre, perfil, email..." searchKeys={["nombre", "perfil", "email", "telefono"]}
          onAdd={isAdmin ? () => { setForm(emptyForm); setEditingId(null); setError(""); setModalOpen(true); } : undefined}
          onEdit={isAdmin ? (item) => { setForm({ nombre: item.nombre, perfil: item.perfil || "", telefono: item.telefono || "", email: item.email || "", password: "", role: item.user_role || "partes", foto_url: item.foto_url || "" }); setEditingId(item.id); setError(""); setModalOpen(true); } : undefined}
          addLabel="Nuevo trabajador" canAdd={isAdmin} canEdit={isAdmin} canDelete={false} />

        <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar trabajador" : "Nuevo trabajador"} size="lg">
          <form onSubmit={handleSubmit} className="space-y-4">
            {error && (
              <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">{error}</div>
            )}

            <div className="flex items-start gap-5">
              <PhotoUpload currentUrl={form.foto_url || null} folder="humano" entityId={editingId || undefined} size="lg"
                onUploaded={(url) => setForm({ ...form, foto_url: url })} onRemoved={() => setForm({ ...form, foto_url: "" })} />
              <div className="flex-1 space-y-4">
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre completo *</label>
                  <input type="text" required value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="Ej: Juan García Pérez" className={ic} />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Perfil / Puesto</label>
                    <select value={form.perfil} onChange={(e) => setForm({ ...form, perfil: e.target.value })} className={ic}>
                      <option value="">Seleccionar...</option>
                      <option value="Encargado de obra">Encargado de obra</option>
                      <option value="Oficial 1ª">Oficial 1ª</option>
                      <option value="Oficial 2ª">Oficial 2ª</option>
                      <option value="Peón especialista">Peón especialista</option>
                      <option value="Peón">Peón</option>
                      <option value="Administrativo">Administrativo</option>
                      <option value="Técnico">Técnico</option>
                    </select>
                  </div>
                  <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Teléfono</label>
                    <input type="tel" value={form.telefono} onChange={(e) => setForm({ ...form, telefono: e.target.value })} placeholder="600 000 000" className={ic} />
                  </div>
                </div>
              </div>
            </div>

            {/* Acceso a la app */}
            <div className="border-t border-surface-200 pt-4">
              <div className="flex items-center gap-2 mb-3">
                <ShieldCheck className="w-4 h-4 text-brand-600" />
                <h3 className="text-sm font-semibold text-surface-900">Acceso a la aplicación</h3>
              </div>
              <div className="grid grid-cols-3 gap-4">
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Email de acceso *</label>
                  <input type="email" required value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} placeholder="trabajador@loynek.es" className={ic} />
                </div>
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">{editingId ? "Nueva contraseña" : "Contraseña *"}</label>
                  <div className="relative">
                    <input type={showPassword ? "text" : "password"} value={form.password}
                      onChange={(e) => setForm({ ...form, password: e.target.value })}
                      placeholder={editingId ? "Dejar vacío para no cambiar" : "Mínimo 6 caracteres"}
                      required={!editingId} minLength={editingId ? 0 : 6} className={ic + " pr-10"} />
                    <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-3 top-1/2 -translate-y-1/2 text-surface-400">
                      {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                  </div>
                </div>
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Rol</label>
                  <select value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value })} className={ic}>
                    <option value="partes">Estándar</option>
                    <option value="admin">Administrador</option>
                  </select>
                </div>
              </div>
            </div>

            <div className="flex items-center justify-end gap-2 pt-2">
              <button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200 transition-colors">Cancelar</button>
              <button type="submit" disabled={saving || !form.nombre || !form.email || (!editingId && !form.password)}
                className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60 disabled:cursor-not-allowed transition-colors">
                {saving && <Loader2 className="w-4 h-4 animate-spin" />}
                {editingId ? "Guardar cambios" : "Crear trabajador"}
              </button>
            </div>
          </form>
        </Modal>
      </div>
    </AppLayout>
  );
}
