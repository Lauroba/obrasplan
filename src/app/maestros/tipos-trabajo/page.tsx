"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import type { TipoTrabajo } from "@/lib/types/database";
import { Hammer, Loader2 } from "lucide-react";

export default function TiposTrabajoPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<TipoTrabajo[]>([]); const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false); const [form, setForm] = useState({ nombre: "" });
  const [editingId, setEditingId] = useState<string | null>(null); const [saving, setSaving] = useState(false);
  const isAdmin = user?.role === "admin"; const supabase = createClient();
  const fetchData = useCallback(async () => { setLoading(true); const { data: r } = await supabase.from("tipos_trabajo").select("*").eq("activo", true).order("nombre"); setData(r || []); setLoading(false); }, []);
  useEffect(() => { fetchData(); }, [fetchData]);
  const handleSubmit = async (e: React.FormEvent) => { e.preventDefault(); setSaving(true); if (editingId) await supabase.from("tipos_trabajo").update(form as any).eq("id", editingId); else await supabase.from("tipos_trabajo").insert(form as any); setSaving(false); setModalOpen(false); fetchData(); };
  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  const columns: Column<TipoTrabajo>[] = [
    { key: "nombre", header: "Tipo de trabajo", render: (item) => <span className="font-medium text-surface-900">{item.nombre}</span> },
  ];
  return (
    <AppLayout><div className="max-w-7xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6"><div className="w-10 h-10 rounded-lg bg-orange-50 flex items-center justify-center"><Hammer className="w-5 h-5 text-orange-600" /></div><div><h1 className="text-xl font-display font-bold text-surface-900">Tipos de Trabajo</h1><p className="text-sm text-surface-500">Categorías de trabajos para partes</p></div></div>
      <DataTable data={data} columns={columns} title="Tipos de trabajo" loading={loading} searchPlaceholder="Buscar..." searchKeys={["nombre"]}
        onAdd={isAdmin ? () => { setForm({ nombre: "" }); setEditingId(null); setModalOpen(true); } : undefined}
        onEdit={isAdmin ? (i) => { setForm({ nombre: i.nombre }); setEditingId(i.id); setModalOpen(true); } : undefined}
        onDelete={isAdmin ? async (i) => { await supabase.from("tipos_trabajo").update({ activo: false } as any).eq("id", i.id); fetchData(); } : undefined}
        addLabel="Nuevo tipo" canAdd={isAdmin} canEdit={isAdmin} canDelete={isAdmin} />
      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar tipo" : "Nuevo tipo"} size="sm">
        <form onSubmit={handleSubmit} className="space-y-4">
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre *</label><input type="text" required value={form.nombre} onChange={(e) => setForm({ nombre: e.target.value })} placeholder="Ej: Inyección" className={ic} /></div>
          <div className="flex justify-end gap-2"><button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button><button type="submit" disabled={saving || !form.nombre} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingId ? "Guardar" : "Crear"}</button></div>
        </form>
      </Modal>
    </div></AppLayout>
  );
}
