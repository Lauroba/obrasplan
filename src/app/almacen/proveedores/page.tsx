"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import { Users2, Loader2, Search, Plus, Pencil, Mail, Phone } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";

const empty = { codigo_proveedor: "", nombre: "", contacto: "", telefono: "", email: "", observaciones: "" };
const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

export default function ProveedoresPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("almacen_proveedores", "crear");
  const puedeEditar   = isAdmin || canDo("almacen_proveedores", "editar");
  const puedeEliminar = isAdmin || canDo("almacen_proveedores", "eliminar");
  const [data, setData] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [modalOpen, setModalOpen] = useState(false);
  const [form, setForm] = useState(empty);
  const [editId, setEditId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const { data: r } = await (supabase.from("proveedores") as any).select("*").eq("activo", true).order("nombre");
    setData(r || []);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const filtered = data.filter((p) =>
    p.nombre?.toLowerCase().includes(search.toLowerCase()) ||
    p.codigo_proveedor?.toLowerCase().includes(search.toLowerCase())
  );

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true); setError(null);
    try {
      const payload = { ...form };
      Object.keys(payload).forEach((k) => { if (!(payload as any)[k]) (payload as any)[k] = null; });
      if (editId) {
        const { error: err } = await (supabase.from("proveedores") as any).update(payload).eq("id", editId);
        if (err) throw err;
      } else {
        const { error: err } = await (supabase.from("proveedores") as any).insert({ ...payload, activo: true });
        if (err) throw err;
      }
      setModalOpen(false); fetchData();
    } catch (err: any) {
      setError(err.message || "Error al guardar");
      await logAuditErrorClient({ modulo: "almacen.proveedores", entidad: "proveedores", accion: editId ? "editar" : "crear", descripcion: "Error al guardar proveedor", errorDetalle: err.message || "" });
    } finally { setSaving(false); }
  };

  const openNew = () => { setForm(empty); setEditId(null); setError(null); setModalOpen(true); };
  const openEdit = (p: any) => { setForm({ codigo_proveedor: p.codigo_proveedor || "", nombre: p.nombre || "", contacto: p.contacto || "", telefono: p.telefono || "", email: p.email || "", observaciones: p.observaciones || "" }); setEditId(p.id); setError(null); setModalOpen(true); };

  return (
    <AppLayout>
      <div className="max-w-5xl mx-auto animate-fade-in">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <Users2 className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">Proveedores</h1>
              <p className="text-sm text-surface-500">{data.length} proveedores</p>
            </div>
          </div>
          {isAdmin && <button onClick={openNew} className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-4 h-4" />Nuevo proveedor</button>}
        </div>

        <div className="card overflow-hidden">
          <div className="p-3 border-b border-surface-100">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
              <input className="w-full pl-9 pr-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20" placeholder="Buscar proveedor..." value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
          </div>
          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="w-6 h-6 text-brand-500 animate-spin" /></div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-12 text-sm text-surface-400">Sin proveedores</div>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 bg-surface-50">
                  <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Código</th>
                  <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Nombre</th>
                  <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Contacto</th>
                  <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Teléfono</th>
                  <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Email</th>
                  {isAdmin && <th className="w-10"></th>}
                </tr>
              </thead>
              <tbody>
                {filtered.map((p) => (
                  <tr key={p.id} className="border-b border-surface-50 hover:bg-surface-50/50 transition-colors">
                    <td className="px-4 py-2.5 font-mono text-xs text-surface-500">{p.codigo_proveedor}</td>
                    <td className="px-4 py-2.5 font-medium text-surface-900">{p.nombre}</td>
                    <td className="px-4 py-2.5 text-surface-600 hidden md:table-cell">{p.contacto || "—"}</td>
                    <td className="px-4 py-2.5 hidden lg:table-cell">
                      {p.telefono && <a href={"tel:" + p.telefono} className="flex items-center gap-1 text-surface-600 hover:text-brand-600"><Phone className="w-3 h-3" />{p.telefono}</a>}
                      {!p.telefono && <span className="text-surface-300">—</span>}
                    </td>
                    <td className="px-4 py-2.5 hidden lg:table-cell">
                      {p.email && <a href={"mailto:" + p.email} className="flex items-center gap-1 text-surface-600 hover:text-brand-600"><Mail className="w-3 h-3" />{p.email}</a>}
                      {!p.email && <span className="text-surface-300">—</span>}
                    </td>
                    {isAdmin && <td className="px-4 py-2.5"><button onClick={() => openEdit(p)} className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100"><Pencil className="w-3.5 h-3.5" /></button></td>}
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editId ? "Editar proveedor" : "Nuevo proveedor"} size="md">
        <form onSubmit={handleSave} className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Código proveedor</label><input className={ic} value={form.codigo_proveedor} onChange={(e) => setForm({ ...form, codigo_proveedor: e.target.value })} placeholder="Auto-generado si vacío" /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Nombre *</label><input required className={ic} value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} /></div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Contacto</label><input className={ic} value={form.contacto} onChange={(e) => setForm({ ...form, contacto: e.target.value })} /></div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Teléfono</label><input className={ic} value={form.telefono} onChange={(e) => setForm({ ...form, telefono: e.target.value })} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Email</label><input type="email" className={ic} value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Observaciones</label><textarea className={cn(ic, "h-16 resize-none")} value={form.observaciones} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} /></div>
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