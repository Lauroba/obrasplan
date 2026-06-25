"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { Tag, Loader2, Search, Plus, Pencil, Trash2, AlertTriangle } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";

const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";
const emptyForm = { nombre: "", descripcion: "", activo: true, orden: 0 };

export default function TiposArticuloPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const isAdmin = user?.role === "admin";

  const [data, setData] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [modalOpen, setModalOpen] = useState(false);
  const [form, setForm] = useState(emptyForm);
  const [editId, setEditId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [deleteModal, setDeleteModal] = useState<{ id: string; nombre: string; count: number } | null>(null);
  const [deleting, setDeleting] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const { data: rows } = await (supabase.from("tipos_articulo") as any)
      .select("*, articulos:articulos(count)")
      .order("orden", { ascending: true })
      .order("nombre", { ascending: true });
    setData(rows || []);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const filtered = data.filter((t) =>
    t.nombre?.toLowerCase().includes(search.toLowerCase()) ||
    t.descripcion?.toLowerCase().includes(search.toLowerCase())
  );

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true); setError(null);
    try {
      const payload = {
        nombre: form.nombre.trim(),
        descripcion: form.descripcion.trim() || null,
        activo: form.activo,
        orden: form.orden || 0,
      };
      if (editId) {
        const { error: err } = await (supabase.from("tipos_articulo") as any)
          .update(payload).eq("id", editId);
        if (err) throw err;
      } else {
        const { error: err } = await (supabase.from("tipos_articulo") as any)
          .insert(payload);
        if (err) throw err;
      }
      setModalOpen(false);
      fetchData();
    } catch (err: any) {
      // Violacion de UNIQUE -> mensaje claro
      if (err?.code === "23505") {
        setError(`Ya existe un tipo con el nombre "${form.nombre}".`);
      } else {
        setError(err?.message || "Error al guardar");
      }
      await logAuditErrorClient({
        modulo: "almacen.tipos_articulo",
        entidad: "tipos_articulo",
        accion: editId ? "editar" : "crear",
        descripcion: "Error al guardar tipo de artículo",
        errorDetalle: err?.message || "",
      });
    } finally { setSaving(false); }
  };

  // Antes de eliminar: cuenta cuántos artículos tienen este tipo
  const openDelete = async (t: any) => {
    const { count } = await (supabase.from("articulos") as any)
      .select("id", { count: "exact", head: true })
      .eq("tipo_articulo_id", t.id);
    setDeleteModal({ id: t.id, nombre: t.nombre, count: count || 0 });
  };

  const handleDelete = async () => {
    if (!deleteModal) return;
    setDeleting(true);
    try {
      // Desvincular artículos: poner tipo_articulo_id a null
      if (deleteModal.count > 0) {
        const { error: unlinkErr } = await (supabase.from("articulos") as any)
          .update({ tipo_articulo_id: null })
          .eq("tipo_articulo_id", deleteModal.id);
        if (unlinkErr) throw unlinkErr;
      }
      // Eliminar el tipo
      const { error: delErr } = await (supabase.from("tipos_articulo") as any)
        .delete().eq("id", deleteModal.id);
      if (delErr) throw delErr;
      setDeleteModal(null);
      fetchData();
    } catch (err: any) {
      setError(err?.message || "Error al eliminar");
      await logAuditErrorClient({
        modulo: "almacen.tipos_articulo",
        entidad: "tipos_articulo",
        accion: "eliminar",
        descripcion: "Error al eliminar tipo de artículo",
        errorDetalle: err?.message || "",
      });
    } finally { setDeleting(false); }
  };

  const openNew = () => {
    setForm(emptyForm);
    setEditId(null);
    setError(null);
    setModalOpen(true);
  };

  const openEdit = (t: any) => {
    setForm({
      nombre: t.nombre || "",
      descripcion: t.descripcion || "",
      activo: t.activo !== false,
      orden: t.orden || 0,
    });
    setEditId(t.id);
    setError(null);
    setModalOpen(true);
  };

  const toggleActivo = async (t: any) => {
    await (supabase.from("tipos_articulo") as any)
      .update({ activo: !t.activo }).eq("id", t.id);
    fetchData();
  };

  return (
    <AppLayout>
      <div className="max-w-4xl mx-auto animate-fade-in">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <Tag className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">Tipos de artículo</h1>
              <p className="text-sm text-surface-500">{data.length} tipos</p>
            </div>
          </div>
          {isAdmin && (
            <button onClick={openNew}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
              <Plus className="w-4 h-4" />Nuevo tipo
            </button>
          )}
        </div>

        <div className="card overflow-hidden">
          <div className="p-3 border-b border-surface-100">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
              <input
                className="w-full pl-9 pr-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20"
                placeholder="Buscar tipo..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
          </div>

          {loading ? (
            <div className="flex justify-center py-12">
              <Loader2 className="w-6 h-6 text-brand-500 animate-spin" />
            </div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-12 text-sm text-surface-400">Sin tipos de artículo</div>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 bg-surface-50">
                  <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Orden</th>
                  <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Nombre</th>
                  <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Descripción</th>
                  <th className="text-center text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Artículos</th>
                  <th className="text-center text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Estado</th>
                  {isAdmin && <th className="w-20"></th>}
                </tr>
              </thead>
              <tbody>
                {filtered.map((t) => {
                  const artCount = t.articulos?.[0]?.count ?? 0;
                  return (
                    <tr key={t.id} className={cn(
                      "border-b border-surface-50 hover:bg-surface-50/50 transition-colors",
                      !t.activo && "opacity-50"
                    )}>
                      <td className="px-4 py-2.5 font-mono text-xs text-surface-400">{t.orden}</td>
                      <td className="px-4 py-2.5 font-medium text-surface-900">{t.nombre}</td>
                      <td className="px-4 py-2.5 text-xs text-surface-500 hidden md:table-cell">
                        {t.descripcion || <span className="text-surface-300">—</span>}
                      </td>
                      <td className="px-4 py-2.5 text-center">
                        <span className="text-xs font-mono text-surface-600">{artCount}</span>
                      </td>
                      <td className="px-4 py-2.5 text-center">
                        {isAdmin ? (
                          <button
                            onClick={() => toggleActivo(t)}
                            className={cn(
                              "px-2 py-0.5 rounded-full text-[10px] font-semibold transition-colors",
                              t.activo
                                ? "bg-emerald-100 text-emerald-700 hover:bg-emerald-200"
                                : "bg-surface-100 text-surface-500 hover:bg-surface-200"
                            )}>
                            {t.activo ? "Activo" : "Inactivo"}
                          </button>
                        ) : (
                          <span className={cn(
                            "px-2 py-0.5 rounded-full text-[10px] font-semibold",
                            t.activo ? "bg-emerald-100 text-emerald-700" : "bg-surface-100 text-surface-500"
                          )}>{t.activo ? "Activo" : "Inactivo"}</span>
                        )}
                      </td>
                      {isAdmin && (
                        <td className="px-4 py-2.5">
                          <div className="flex items-center justify-end gap-1">
                            <button onClick={() => openEdit(t)}
                              className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100">
                              <Pencil className="w-3.5 h-3.5" />
                            </button>
                            <button onClick={() => openDelete(t)}
                              className="p-1.5 rounded-lg text-surface-400 hover:bg-red-50 hover:text-red-500">
                              <Trash2 className="w-3.5 h-3.5" />
                            </button>
                          </div>
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Modal: crear / editar */}
      <Modal open={modalOpen} onClose={() => setModalOpen(false)}
        title={editId ? "Editar tipo de artículo" : "Nuevo tipo de artículo"} size="sm">
        <form onSubmit={handleSave} className="space-y-3">
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-1">Nombre *</label>
            <input required className={ic} value={form.nombre}
              onChange={(e) => setForm({ ...form, nombre: e.target.value })}
              placeholder="Ej: Herramienta, Consumible..." />
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-1">Descripción</label>
            <input className={ic} value={form.descripcion}
              onChange={(e) => setForm({ ...form, descripcion: e.target.value })}
              placeholder="Descripción opcional" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-surface-600 mb-1">Orden</label>
              <input type="number" min="0" className={ic} value={form.orden}
                onChange={(e) => setForm({ ...form, orden: parseInt(e.target.value) || 0 })} />
            </div>
            <div className="flex items-end pb-0.5">
              <label className="flex items-center gap-2 text-sm text-surface-700 cursor-pointer">
                <input type="checkbox" checked={form.activo}
                  onChange={(e) => setForm({ ...form, activo: e.target.checked })}
                  className="w-4 h-4" />
                Activo
              </label>
            </div>
          </div>
          {error && <p className="text-xs text-red-600">{error}</p>}
          <div className="flex justify-end gap-2 pt-1">
            <button type="button" onClick={() => setModalOpen(false)}
              className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">
              Cancelar
            </button>
            <button type="submit" disabled={saving}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {saving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}Guardar
            </button>
          </div>
        </form>
      </Modal>

      {/* Modal: confirmar eliminación */}
      <Modal open={!!deleteModal} onClose={() => setDeleteModal(null)}
        title="Eliminar tipo de artículo" size="sm">
        {deleteModal && (
          <div className="space-y-4">
            {deleteModal.count > 0 && (
              <div className="flex items-start gap-3 p-3 bg-amber-50 border border-amber-200 rounded-lg">
                <AlertTriangle className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" />
                <div className="text-sm text-amber-800">
                  <p className="font-semibold mb-1">
                    {deleteModal.count} artículo{deleteModal.count > 1 ? "s" : ""} usa{deleteModal.count === 1 ? "" : "n"} este tipo.
                  </p>
                  <p className="text-xs">Al eliminar, esos artículos quedarán sin tipo asignado.</p>
                </div>
              </div>
            )}
            <p className="text-sm text-surface-700">
              ¿Eliminar el tipo <span className="font-semibold">"{deleteModal.nombre}"</span>?
              {deleteModal.count === 0 && " No tiene artículos asociados."}
            </p>
            {error && <p className="text-xs text-red-600">{error}</p>}
            <div className="flex justify-end gap-2">
              <button onClick={() => setDeleteModal(null)}
                className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">
                Cancelar
              </button>
              <button onClick={handleDelete} disabled={deleting}
                className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-red-500 rounded-lg hover:bg-red-600 disabled:opacity-60">
                {deleting && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
                Eliminar{deleteModal.count > 0 ? " y desvincular" : ""}
              </button>
            </div>
          </div>
        )}
      </Modal>
    </AppLayout>
  );
}