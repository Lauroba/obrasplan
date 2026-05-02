"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import type { Cliente } from "@/lib/types/database";
import { Contact, Loader2 } from "lucide-react";

const emptyForm: Partial<Cliente> = { nombre: "", contacto: "", telefono: "", email: "", direccion: "" };

export default function ClientesPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<Cliente[]>([]);
  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const isAdmin = user?.role === "admin";
  const supabase = createClient();

  const fetchData = useCallback(async () => {
    setLoading(true);
    const { data: rows } = await supabase.from("clientes").select("*").eq("activo", true).order("nombre");
    setData(rows || []);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    if (editingId) await supabase.from("clientes").update(form as any).eq("id", editingId);
    else await supabase.from("clientes").insert(form as any);
    setSaving(false); setModalOpen(false); fetchData();
  };

  const columns: Column<Cliente>[] = [
    { key: "nombre", header: "Empresa", render: (item) => <span className="font-medium text-surface-900">{item.nombre}</span> },
    { key: "contacto", header: "Contacto" },
    { key: "telefono", header: "Teléfono" },
    { key: "email", header: "Email" },
    { key: "direccion", header: "Dirección", className: "max-w-[200px] truncate" },
  ];

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-lg bg-blue-50 flex items-center justify-center">
            <Contact className="w-5 h-5 text-blue-600" />
          </div>
          <div>
            <h1 className="text-xl font-display font-bold text-surface-900">Clientes</h1>
            <p className="text-sm text-surface-500">Gestión de clientes y empresas</p>
          </div>
        </div>

        <DataTable data={data} columns={columns} title="Clientes" loading={loading}
          searchPlaceholder="Buscar por nombre, contacto, email..." searchKeys={["nombre", "contacto", "email", "telefono"]}
          onAdd={isAdmin ? () => { setForm(emptyForm); setEditingId(null); setModalOpen(true); } : undefined}
          onEdit={isAdmin ? (item) => { setForm({ nombre: item.nombre, contacto: item.contacto || "", telefono: item.telefono || "", email: item.email || "", direccion: item.direccion || "" }); setEditingId(item.id); setModalOpen(true); } : undefined}
          onDelete={isAdmin ? async (item) => { await supabase.from("clientes").update({ activo: false } as any).eq("id", item.id); fetchData(); } : undefined}
          addLabel="Nuevo cliente" canAdd={isAdmin} canEdit={isAdmin} canDelete={isAdmin} />

        <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar cliente" : "Nuevo cliente"}>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre / Empresa *</label>
              <input type="text" value={form.nombre || ""} onChange={(e) => setForm({ ...form, nombre: e.target.value })} required placeholder="Ej: Ayuntamiento de Madrid" className="w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all" />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-surface-700 mb-1.5">Persona de contacto</label>
                <input type="text" value={form.contacto || ""} onChange={(e) => setForm({ ...form, contacto: e.target.value })} placeholder="Nombre y apellidos" className="w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all" />
              </div>
              <div>
                <label className="block text-sm font-medium text-surface-700 mb-1.5">Teléfono</label>
                <input type="tel" value={form.telefono || ""} onChange={(e) => setForm({ ...form, telefono: e.target.value })} placeholder="911 234 567" className="w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all" />
              </div>
            </div>
            <div>
              <label className="block text-sm font-medium text-surface-700 mb-1.5">Email</label>
              <input type="email" value={form.email || ""} onChange={(e) => setForm({ ...form, email: e.target.value })} placeholder="contacto@empresa.es" className="w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all" />
            </div>
            <div>
              <label className="block text-sm font-medium text-surface-700 mb-1.5">Dirección</label>
              <input type="text" value={form.direccion || ""} onChange={(e) => setForm({ ...form, direccion: e.target.value })} placeholder="Calle, número, ciudad" className="w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all" />
            </div>
            <div className="flex items-center justify-end gap-2 pt-2">
              <button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200 transition-colors">Cancelar</button>
              <button type="submit" disabled={saving || !form.nombre} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60 disabled:cursor-not-allowed transition-colors">
                {saving && <Loader2 className="w-4 h-4 animate-spin" />}
                {editingId ? "Guardar cambios" : "Crear cliente"}
              </button>
            </div>
          </form>
        </Modal>
      </div>
    </AppLayout>
  );
}
