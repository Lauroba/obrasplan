"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { Warehouse, Loader2, Search, Plus, Pencil, Building2 } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";

const empty = { codigo_almacen: "", nombre: "", ubicacion: "", es_almacen_obra: false, obra_id: "" };
const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

export default function AlmacenesPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const isAdmin = user?.role === "admin";
  const [data, setData] = useState<any[]>([]);
  const [obras, setObras] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [modalOpen, setModalOpen] = useState(false);
  const [form, setForm] = useState(empty);
  const [editId, setEditId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [aR, oR] = await Promise.all([
      (supabase.from("almacenes") as any).select("*, obra:obras(nombre)").eq("activo", true).order("nombre"),
      (supabase.from("obras") as any).select("id, nombre").order("nombre"),
    ]);
    setData(aR.data || []);
    setObras(oR.data || []);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const filtered = data.filter((a) =>
    a.nombre?.toLowerCase().includes(search.toLowerCase()) ||
    a.codigo_almacen?.toLowerCase().includes(search.toLowerCase())
  );

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true); setError(null);
    try {
      const payload: any = { ...form, obra_id: form.obra_id || null };
      if (editId) {
        const { error: err } = await (supabase.from("almacenes") as any).update(payload).eq("id", editId);
        if (err) throw err;
      } else {
        const { error: err } = await (supabase.from("almacenes") as any).insert({ ...payload, activo: true });
        if (err) throw err;
      }
      setModalOpen(false); fetchData();
    } catch (err: any) {
      setError(err.message || "Error al guardar");
      await logAuditErrorClient({ modulo: "almacen.almacenes", entidad: "almacenes", accion: editId ? "editar" : "crear", descripcion: "Error al guardar almacén", errorDetalle: err.message || "" });
    } finally { setSaving(false); }
  };

  const openNew = () => { setForm(empty); setEditId(null); setError(null); setModalOpen(true); };
  const openEdit = (a: any) => {
    setForm({ codigo_almacen: a.codigo_almacen || "", nombre: a.nombre || "", ubicacion: a.ubicacion || "", es_almacen_obra: a.es_almacen_obra || false, obra_id: a.obra_id || "" });
    setEditId(a.id); setError(null); setModalOpen(true);
  };

  return (
    <AppLayout>
      <div className="max-w-5xl mx-auto animate-fade-in">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <Warehouse className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">Almacenes</h1>
              <p className="text-sm text-surface-500">{data.length} almacenes</p>
            </div>
          </div>
          {isAdmin && <button onClick={openNew} className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-4 h-4" />Nuevo almacén</button>}
        </div>

        <div className="card overflow-hidden">
          <div className="p-3 border-b border-surface-100">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
              <input className="w-full pl-9 pr-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20" placeholder="Buscar almacén..." value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
          </div>
          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="w-6 h-6 text-brand-500 animate-spin" /></div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-12 text-sm text-surface-400">Sin almacenes</div>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 bg-surface-50">
                  <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Código</th>
                  <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Nombre</th>
                  <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Ubicación</th>
                  <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Tipo</th>
                  {isAdmin && <th className="w-10"></th>}
                </tr>
              </thead>
              <tbody>
                {filtered.map((a) => (
                  <tr key={a.id} className="border-b border-surface-50 hover:bg-surface-50/50 transition-colors">
                    <td className="px-4 py-2.5 font-mono text-xs text-surface-500">{a.codigo_almacen}</td>
                    <td className="px-4 py-2.5 font-medium text-surface-900">{a.nombre}</td>
                    <td className="px-4 py-2.5 text-surface-600 hidden md:table-cell">{a.ubicacion || "—"}</td>
                    <td className="px-4 py-2.5">
                      {a.es_almacen_obra
                        ? <span className="flex items-center gap-1 text-xs text-brand-600"><Building2 className="w-3 h-3" />{a.obra?.nombre || "Obra"}</span>
                        : <span className="text-xs text-surface-500">General</span>
                      }
                    </td>
                    {isAdmin && <td className="px-4 py-2.5"><button onClick={() => openEdit(a)} className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100"><Pencil className="w-3.5 h-3.5" /></button></td>}
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editId ? "Editar almacén" : "Nuevo almacén"} size="md">
        <form onSubmit={handleSave} className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Código almacén *</label><input required className={ic} value={form.codigo_almacen} onChange={(e) => setForm({ ...form, codigo_almacen: e.target.value.toUpperCase() })} placeholder="ALM01" /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Nombre *</label><input required className={ic} value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} /></div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Ubicación</label><input className={ic} value={form.ubicacion} onChange={(e) => setForm({ ...form, ubicacion: e.target.value })} /></div>
          <div className="flex items-center gap-2">
            <input type="checkbox" id="es_obra" checked={form.es_almacen_obra} onChange={(e) => setForm({ ...form, es_almacen_obra: e.target.checked, obra_id: e.target.checked ? form.obra_id : "" })} className="w-4 h-4" />
            <label htmlFor="es_obra" className="text-sm text-surface-700">Es almacén de obra</label>
          </div>
          {form.es_almacen_obra && (
            <div>
              <label className="block text-xs font-medium text-surface-600 mb-1">Obra asociada</label>
              <select className={ic} value={form.obra_id} onChange={(e) => setForm({ ...form, obra_id: e.target.value })}>
                <option value="">Sin obra</option>
                {obras.map((o) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
              </select>
            </div>
          )}
          {error && <p className="text-xs text-red-600">{error}</p>}
          <div className="flex justify-end gap-2 pt-1">
            <button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving} className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}Guardar</button>
          </div>
        </form>
      </Modal>
    </AppLayout>
  );
}