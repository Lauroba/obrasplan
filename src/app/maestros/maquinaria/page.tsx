"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import PhotoUpload from "@/components/shared/PhotoUpload";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { Maquinaria } from "@/lib/types/database";
import { Wrench, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils/cn";

const emptyForm: Partial<Maquinaria> = { nombre: "", tipo: "", estado: "disponible", observaciones: "", foto_url: "" };
const estadoColors: Record<string, string> = { disponible: "badge-en_curso", en_uso: "badge-pendiente", mantenimiento: "badge-rechazado", baja: "badge-cerrada" };

export default function MaquinariaPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<Maquinaria[]>([]); const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false); const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null); const [saving, setSaving] = useState(false);
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("maestros_maquinaria", "crear");
  const puedeEditar   = isAdmin || canDo("maestros_maquinaria", "editar");
  const puedeEliminar = isAdmin || canDo("maestros_maquinaria", "eliminar");
  const supabase = createClient();
  const fetchData = useCallback(async () => { setLoading(true); const { data: r } = await supabase.from("maquinaria").select("*").eq("activo", true).order("nombre"); setData(r || []); setLoading(false); }, []);
  useEffect(() => { fetchData(); }, [fetchData]);
  const handleSubmit = async (e: React.FormEvent) => { e.preventDefault(); setSaving(true); if (editingId) await supabase.from("maquinaria").update(form as any).eq("id", editingId); else await supabase.from("maquinaria").insert(form as any); setSaving(false); setModalOpen(false); fetchData(); };
  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  const columns: Column<Maquinaria>[] = [
    { key: "nombre", header: "Nombre", render: (item) => (
      <div className="flex items-center gap-3">
        {item.foto_url ? <img src={item.foto_url} alt="" className="w-8 h-8 rounded-full object-cover shrink-0" /> : <div className="w-8 h-8 rounded-full bg-amber-100 flex items-center justify-center shrink-0"><Wrench className="w-4 h-4 text-amber-600" /></div>}
        <span className="font-medium text-surface-900">{item.nombre}</span>
      </div>)},
    { key: "tipo", header: "Tipo" },
    { key: "estado", header: "Estado", render: (item) => <span className={cn("badge", estadoColors[item.estado])}>{item.estado.replace("_", " ")}</span> },
  ];
  return (
    <AppLayout><div className="max-w-7xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6"><div className="w-10 h-10 rounded-lg bg-amber-50 flex items-center justify-center"><Wrench className="w-5 h-5 text-amber-600" /></div><div><h1 className="text-xl font-display font-bold text-surface-900">Maquinaria</h1><p className="text-sm text-surface-500">Gestión de máquinas y equipos</p></div></div>
      <DataTable data={data} columns={columns} title="Maquinaria" loading={loading} searchPlaceholder="Buscar..." searchKeys={["nombre", "tipo"]}
        onAdd={isAdmin ? () => { setForm(emptyForm); setEditingId(null); setModalOpen(true); } : undefined}
        onEdit={isAdmin ? (i) => { setForm({ nombre: i.nombre, tipo: i.tipo || "", estado: i.estado, observaciones: i.observaciones || "", foto_url: i.foto_url || "" }); setEditingId(i.id); setModalOpen(true); } : undefined}
        onDelete={isAdmin ? async (i) => { await supabase.from("maquinaria").update({ activo: false } as any).eq("id", i.id); fetchData(); } : undefined}
        addLabel="Nueva máquina" canAdd={isAdmin} canEdit={isAdmin} canDelete={isAdmin} />
      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar máquina" : "Nueva máquina"}>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="flex items-start gap-4">
            <PhotoUpload currentUrl={form.foto_url || null} folder="maquinaria" entityId={editingId || undefined} size="md" onUploaded={(url) => setForm({ ...form, foto_url: url })} onRemoved={() => setForm({ ...form, foto_url: "" })} />
            <div className="flex-1 space-y-4">
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre *</label><input type="text" required value={form.nombre || ""} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="Ej: Retroexcavadora CAT 420F" className={ic} /></div>
              <div className="grid grid-cols-2 gap-4">
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Tipo</label><input type="text" value={form.tipo || ""} onChange={(e) => setForm({ ...form, tipo: e.target.value })} className={ic} /></div>
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Estado</label><select value={form.estado || "disponible"} onChange={(e) => setForm({ ...form, estado: e.target.value as any })} className={ic}><option value="disponible">Disponible</option><option value="en_uso">En uso</option><option value="mantenimiento">Mantenimiento</option><option value="baja">Baja</option></select></div>
              </div>
            </div>
          </div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Observaciones</label><textarea value={form.observaciones || ""} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} rows={2} className={ic + " resize-none"} /></div>
          <div className="flex justify-end gap-2 pt-2"><button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button><button type="submit" disabled={saving || !form.nombre} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingId ? "Guardar" : "Crear"}</button></div>
        </form>
      </Modal>
    </div></AppLayout>);
}