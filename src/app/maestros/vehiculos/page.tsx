"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import PhotoUpload from "@/components/shared/PhotoUpload";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import type { Vehiculo } from "@/lib/types/database";
import { Truck, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils/cn";

const emptyForm = { nombre: "", matricula: "", tipo: "", estado: "disponible", observaciones: "", foto_url: "", asignable: true };
const estadoColors: Record<string, string> = { disponible: "badge-en_curso", en_uso: "badge-pendiente", mantenimiento: "badge-rechazado", baja: "badge-cerrada" };

export default function VehiculosPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<Vehiculo[]>([]); const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false); const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null); const [saving, setSaving] = useState(false);
  const isAdmin = user?.role === "admin"; const supabase = createClient();
  const fetchData = useCallback(async () => { setLoading(true); const { data: r } = await supabase.from("vehiculos").select("*").eq("activo", true).order("nombre"); setData(r || []); setLoading(false); }, []);
  useEffect(() => { fetchData(); }, [fetchData]);
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); setSaving(true);
    const payload = { nombre: form.nombre, matricula: form.matricula || null, tipo: form.tipo || null, estado: form.estado, observaciones: form.observaciones || null, foto_url: form.foto_url || null, asignable: form.asignable };
    if (editingId) await (supabase.from("vehiculos") as any).update(payload).eq("id", editingId);
    else await (supabase.from("vehiculos") as any).insert(payload);
    setSaving(false); setModalOpen(false); fetchData();
  };
  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  const columns: Column<Vehiculo>[] = [
    { key: "nombre", header: "Nombre", render: (item) => (
      <div className="flex items-center gap-3">
        {item.foto_url ? <img src={item.foto_url} alt="" className="w-8 h-8 rounded-full object-cover shrink-0" /> : <div className="w-8 h-8 rounded-full bg-teal-100 flex items-center justify-center shrink-0"><Truck className="w-4 h-4 text-teal-600" /></div>}
        <div>
          <span className="font-medium text-surface-900">{item.nombre}</span>
          {(item as any).asignable === false && <span className="ml-1 text-[10px] text-amber-500 font-medium">NO PLANIF.</span>}
        </div>
      </div>)},
    { key: "matricula", header: "Matrícula", render: (item) => <span className="font-mono text-xs bg-surface-100 px-2 py-1 rounded">{item.matricula || "—"}</span> },
    { key: "tipo", header: "Tipo" },
    { key: "estado", header: "Estado", render: (item) => <span className={cn("badge", estadoColors[item.estado])}>{item.estado.replace("_", " ")}</span> },
  ];
  return (
    <AppLayout><div className="max-w-7xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6"><div className="w-10 h-10 rounded-lg bg-teal-50 flex items-center justify-center"><Truck className="w-5 h-5 text-teal-600" /></div><div><h1 className="text-xl font-display font-bold text-surface-900">Vehículos</h1><p className="text-sm text-surface-500">Gestión de vehículos</p></div></div>
      <DataTable data={data} columns={columns} title="Vehículos" loading={loading} searchPlaceholder="Buscar..." searchKeys={["nombre", "matricula", "tipo"]}
        onAdd={isAdmin ? () => { setForm(emptyForm); setEditingId(null); setModalOpen(true); } : undefined}
        onEdit={isAdmin ? (i) => { setForm({ nombre: i.nombre, matricula: i.matricula || "", tipo: i.tipo || "", estado: i.estado, observaciones: i.observaciones || "", foto_url: i.foto_url || "", asignable: (i as any).asignable !== false }); setEditingId(i.id); setModalOpen(true); } : undefined}
        onDelete={isAdmin ? async (i) => { await (supabase.from("vehiculos") as any).update({ activo: false }).eq("id", i.id); fetchData(); } : undefined}
        addLabel="Nuevo vehículo" canAdd={isAdmin} canEdit={isAdmin} canDelete={isAdmin} />
      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar vehículo" : "Nuevo vehículo"}>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="flex items-start gap-4">
            <PhotoUpload currentUrl={form.foto_url || null} folder="vehiculo" entityId={editingId || undefined} size="md" onUploaded={(url) => setForm({ ...form, foto_url: url })} onRemoved={() => setForm({ ...form, foto_url: "" })} />
            <div className="flex-1 space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre *</label><input type="text" required value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="Ej: Furgón Ford Transit" className={ic} /></div>
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Matrícula</label><input type="text" value={form.matricula} onChange={(e) => setForm({ ...form, matricula: e.target.value })} placeholder="1234 ABC" className={ic} /></div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Tipo</label><select value={form.tipo} onChange={(e) => setForm({ ...form, tipo: e.target.value })} className={ic}><option value="">Seleccionar...</option><option value="Furgoneta">Furgoneta</option><option value="Camión">Camión</option><option value="Pick-up">Pick-up</option><option value="Turismo">Turismo</option></select></div>
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Estado</label><select value={form.estado} onChange={(e) => setForm({ ...form, estado: e.target.value })} className={ic}><option value="disponible">Disponible</option><option value="en_uso">En uso</option><option value="mantenimiento">Mantenimiento</option><option value="baja">Baja</option></select></div>
              </div>
            </div>
          </div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Observaciones</label><textarea value={form.observaciones} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} rows={2} className={ic + " resize-none"} /></div>
          {/* Asignable flag */}
          <label className="flex items-center gap-3 cursor-pointer border-t border-surface-200 pt-4">
            <input type="checkbox" checked={form.asignable} onChange={(e) => setForm({ ...form, asignable: e.target.checked })} className="w-4 h-4 rounded border-surface-300 text-brand-600 focus:ring-brand-500" />
            <div>
              <span className="text-sm font-medium text-surface-900">Asignable en planificación</span>
              <p className="text-xs text-surface-400">Si está desactivado, no aparecerá en el planificador</p>
            </div>
          </label>
          <div className="flex justify-end gap-2 pt-2"><button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button><button type="submit" disabled={saving || !form.nombre} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingId ? "Guardar" : "Crear"}</button></div>
        </form>
      </Modal>
    </div></AppLayout>);
}
