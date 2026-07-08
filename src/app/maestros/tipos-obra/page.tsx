"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";
import { Building2, Loader2 } from "lucide-react";

export default function TiposObraPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<any[]>([]); const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false); const [form, setForm] = useState({ nombre: "" });
  const [editingId, setEditingId] = useState<string | null>(null); const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("maestros_tipos_obra", "crear");
  const puedeEditar   = isAdmin || canDo("maestros_tipos_obra", "editar");
  const puedeEliminar = isAdmin || canDo("maestros_tipos_obra", "eliminar");
  const supabase = createClient();
  const fetchData = useCallback(async () => { setLoading(true); const { data: r } = await supabase.from("tipos_obra").select("*").eq("activo", true).order("nombre"); setData(r || []); setLoading(false); }, []);
  useEffect(() => { fetchData(); }, [fetchData]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setFormError(null);
    try {
      if (editingId) {
        const { error } = await (supabase.from("tipos_obra") as any).update(form).eq("id", editingId);
        if (error) throw error;
      } else {
        const { error } = await (supabase.from("tipos_obra") as any).insert(form);
        if (error) throw error;
      }
      setModalOpen(false);
      fetchData();
    } catch (err: any) {
      const mensaje = err?.message || "Error desconocido al guardar el tipo de obra";
      setFormError(mensaje);
      // El éxito ya queda auditado automáticamente por el trigger de BD
      // (audit_tipos_obra, migración 026). Aquí solo registramos el FALLO,
      // que el trigger nunca llega a ver porque la transacción no se completó.
      await logAuditErrorClient({
        modulo: "maestros.tipos_obra",
        entidad: "tipos_obra",
        entidadId: editingId,
        accion: editingId ? "editar" : "crear",
        descripcion: editingId
          ? `Intentó editar el tipo de obra "${form.nombre}"`
          : `Intentó crear el tipo de obra "${form.nombre}"`,
        errorDetalle: mensaje,
      });
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (item: any) => {
    try {
      const { error } = await (supabase.from("tipos_obra") as any).update({ activo: false }).eq("id", item.id);
      if (error) throw error;
      fetchData();
    } catch (err: any) {
      const mensaje = err?.message || "Error desconocido al desactivar el tipo de obra";
      await logAuditErrorClient({
        modulo: "maestros.tipos_obra",
        entidad: "tipos_obra",
        entidadId: item.id,
        accion: "editar",
        descripcion: `Intentó desactivar el tipo de obra "${item.nombre}"`,
        errorDetalle: mensaje,
      });
      alert(`No se pudo desactivar: ${mensaje}`);
    }
  };

  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  const columns: Column<any>[] = [
    { key: "nombre", header: "Tipo de obra", render: (item) => <span className="font-medium text-surface-900">{item.nombre}</span> },
  ];
  return (
    <AppLayout><div className="max-w-7xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6"><div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center"><Building2 className="w-5 h-5 text-brand-600" /></div><div><h1 className="text-xl font-display font-bold text-surface-900">Tipos de Obra</h1><p className="text-sm text-surface-500">Categorías de obras</p></div></div>
      <DataTable data={data} columns={columns} title="Tipos de obra" loading={loading} searchPlaceholder="Buscar..." searchKeys={["nombre"]}
        onAdd={isAdmin ? () => { setForm({ nombre: "" }); setEditingId(null); setFormError(null); setModalOpen(true); } : undefined}
        onEdit={isAdmin ? (i) => { setForm({ nombre: i.nombre }); setEditingId(i.id); setFormError(null); setModalOpen(true); } : undefined}
        onDelete={isAdmin ? handleDelete : undefined}
        addLabel="Nuevo tipo" canAdd={isAdmin} canEdit={isAdmin} canDelete={isAdmin} />
      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar tipo" : "Nuevo tipo"} size="sm">
        <form onSubmit={handleSubmit} className="space-y-4">
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre *</label><input type="text" required value={form.nombre} onChange={(e) => setForm({ nombre: e.target.value })} placeholder="Ej: Reforma" className={ic} /></div>
          {formError && <p className="text-sm text-red-600">{formError}</p>}
          <div className="flex justify-end gap-2"><button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button><button type="submit" disabled={saving || !form.nombre} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingId ? "Guardar" : "Crear"}</button></div>
        </form>
      </Modal>
    </div></AppLayout>
  );
}