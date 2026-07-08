"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { EstadoObra } from "@/lib/types/database";
import { Tag, Loader2 } from "lucide-react";

const COLORS = ["#3B82F6","#F59E0B","#8B5CF6","#EF4444","#22C55E","#EC4899","#06B6D4","#F97316","#6366F1","#14B8A6","#A855F7","#84CC16","#E11D48","#0EA5E9","#D946EF"];
const emptyForm = { nombre: "", color: "#3B82F6" };

export default function EstadosObraPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<EstadoObra[]>([]); const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false); const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null); const [saving, setSaving] = useState(false);
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("maestros_estados", "crear");
  const puedeEditar   = isAdmin || canDo("maestros_estados", "editar");
  const puedeEliminar = isAdmin || canDo("maestros_estados", "eliminar");
  const supabase = createClient();

  const fetchData = useCallback(async () => {
    setLoading(true);
    const { data: r } = await supabase.from("estados_obra").select("*").eq("activo", true).order("nombre");
    setData(r || []); setLoading(false);
  }, []);
  useEffect(() => { fetchData(); }, [fetchData]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); setSaving(true);
    if (editingId) await supabase.from("estados_obra").update(form as any).eq("id", editingId);
    else await supabase.from("estados_obra").insert(form as any);
    setSaving(false); setModalOpen(false); fetchData();
  };

  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  const columns: Column<EstadoObra>[] = [
    { key: "nombre", header: "Estado", render: (item) => (
      <div className="flex items-center gap-3">
        <div className="w-4 h-4 rounded-full shrink-0" style={{ backgroundColor: item.color }} />
        <span className="font-medium text-surface-900">{item.nombre}</span>
      </div>
    )},
    { key: "color", header: "Color", render: (item) => (
      <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium text-white" style={{ backgroundColor: item.color }}>{item.nombre}</span>
    )},
  ];

  return (
    <AppLayout><div className="max-w-7xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6">
        <div className="w-10 h-10 rounded-lg bg-violet-50 flex items-center justify-center"><Tag className="w-5 h-5 text-violet-600" /></div>
        <div><h1 className="text-xl font-display font-bold text-surface-900">Estados de Obra</h1><p className="text-sm text-surface-500">Personaliza los estados de tus obras</p></div>
      </div>
      <DataTable data={data} columns={columns} title="Estados" loading={loading}
        searchPlaceholder="Buscar..." searchKeys={["nombre"]}
        onAdd={isAdmin ? () => { setForm(emptyForm); setEditingId(null); setModalOpen(true); } : undefined}
        onEdit={isAdmin ? (i) => { setForm({ nombre: i.nombre, color: i.color }); setEditingId(i.id); setModalOpen(true); } : undefined}
        onDelete={isAdmin ? async (i) => { await supabase.from("estados_obra").update({ activo: false } as any).eq("id", i.id); fetchData(); } : undefined}
        addLabel="Nuevo estado" canAdd={isAdmin} canEdit={isAdmin} canDelete={isAdmin} />
      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar estado" : "Nuevo estado"} size="sm">
        <form onSubmit={handleSubmit} className="space-y-4">
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre *</label><input type="text" required value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="Ej: En reparo" className={ic} /></div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Color</label>
            <div className="flex flex-wrap gap-2">
              {COLORS.map((c) => (
                <button key={c} type="button" onClick={() => setForm({ ...form, color: c })}
                  className="w-8 h-8 rounded-full border-2 transition-all"
                  style={{ backgroundColor: c, borderColor: form.color === c ? c : "transparent", transform: form.color === c ? "scale(1.2)" : "scale(1)", boxShadow: form.color === c ? `0 0 0 3px ${c}30` : "none" }} />
              ))}
            </div>
            <div className="mt-2 flex items-center gap-2">
              <div className="w-6 h-6 rounded-full" style={{ backgroundColor: form.color }} />
              <span className="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium text-white" style={{ backgroundColor: form.color }}>{form.nombre || "Preview"}</span>
            </div>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving || !form.nombre} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingId ? "Guardar" : "Crear"}</button>
          </div>
        </form>
      </Modal>
    </div></AppLayout>
  );
}