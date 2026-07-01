"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import {
  Users2, Loader2, Search, Plus, Pencil, Phone, Mail,
  Building2, Filter, X, CheckCircle2,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";

const RELACIONES = ["CLIENTE", "COMERCIAL", "PROVEEDOR", "TRABAJADOR", "OTROS"];

const RELACION_COLOR: Record<string, string> = {
  CLIENTE:    "bg-blue-100 text-blue-700",
  COMERCIAL:  "bg-emerald-100 text-emerald-700",
  PROVEEDOR:  "bg-orange-100 text-orange-700",
  TRABAJADOR: "bg-purple-100 text-purple-700",
  OTROS:      "bg-surface-100 text-surface-600",
};

const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

const emptyForm = {
  empresa: "", apellidos: "", nombre: "", movil: "", telefono: "",
  email: "", relacion: "CLIENTE", es_cliente_desoi: false,
  observaciones: "", activo: true,
};

export default function ContactosLeynaPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const isAdmin = user?.role === "admin";

  const [data, setData] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [relacionFilter, setRelacionFilter] = useState("");
  const [soloDesoi, setSoloDesoi] = useState(false);
  const [soloActivos, setSoloActivos] = useState(true);

  // Modal editar/crear
  const [modalOpen, setModalOpen] = useState(false);
  const [form, setForm] = useState(emptyForm);
  const [editId, setEditId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Modal detalle
  const [detalleOpen, setDetalleOpen] = useState(false);
  const [detalleItem, setDetalleItem] = useState<any>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    let q = (supabase.from("contactos_leyna") as any)
      .select("*")
      .order("empresa", { ascending: true })
      .order("apellidos", { ascending: true });
    if (soloActivos) q = q.eq("activo", true);
    const { data: rows } = await q;
    setData(rows || []);
    setLoading(false);
  }, [soloActivos]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const filtered = data.filter((c) => {
    const q = search.toLowerCase();
    const matchSearch = !q ||
      c.empresa?.toLowerCase().includes(q) ||
      c.apellidos?.toLowerCase().includes(q) ||
      c.nombre?.toLowerCase().includes(q) ||
      c.movil?.includes(q) ||
      c.telefono?.includes(q) ||
      c.email?.toLowerCase().includes(q) ||
      c.relacion?.toLowerCase().includes(q);
    const matchRelacion = !relacionFilter || c.relacion === relacionFilter;
    const matchDesoi = !soloDesoi || c.es_cliente_desoi;
    return matchSearch && matchRelacion && matchDesoi;
  });

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true); setError(null);
    try {
      const payload = {
        empresa: form.empresa.trim(),
        apellidos: form.apellidos.trim(),
        nombre: form.nombre.trim(),
        movil: form.movil.trim(),
        telefono: form.telefono.trim(),
        email: form.email.trim().toLowerCase(),
        relacion: form.relacion,
        es_cliente_desoi: form.es_cliente_desoi,
        observaciones: form.observaciones.trim() || null,
        activo: form.activo,
        origen: editId ? undefined : "manual",
      };
      if (editId) {
        const { error: err } = await (supabase.from("contactos_leyna") as any)
          .update(payload).eq("id", editId);
        if (err) throw err;
      } else {
        const { error: err } = await (supabase.from("contactos_leyna") as any)
          .insert(payload);
        if (err) throw err;
      }
      setModalOpen(false);
      fetchData();
    } catch (err: any) {
      setError(err.message || "Error al guardar");
      await logAuditErrorClient({
        modulo: "contactos_leyna", entidad: "contactos_leyna",
        accion: editId ? "editar" : "crear",
        descripcion: "Error al guardar contacto",
        errorDetalle: err.message || "",
      });
    } finally { setSaving(false); }
  };

  const toggleActivo = async (item: any) => {
    await (supabase.from("contactos_leyna") as any)
      .update({ activo: !item.activo }).eq("id", item.id);
    fetchData();
  };

  const openNew = () => {
    setForm(emptyForm); setEditId(null); setError(null); setModalOpen(true);
  };

  const openEdit = (item: any, e?: React.MouseEvent) => {
    e?.stopPropagation();
    setForm({
      empresa: item.empresa || "", apellidos: item.apellidos || "",
      nombre: item.nombre || "", movil: item.movil || "",
      telefono: item.telefono || "", email: item.email || "",
      relacion: item.relacion || "CLIENTE",
      es_cliente_desoi: item.es_cliente_desoi || false,
      observaciones: item.observaciones || "", activo: item.activo !== false,
    });
    setEditId(item.id); setError(null); setModalOpen(true);
  };

  const openDetalle = (item: any) => {
    setDetalleItem(item); setDetalleOpen(true);
  };

  const totalFiltrados = filtered.length;

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        {/* Cabecera */}
        <div className="flex items-center justify-between mb-6 flex-wrap gap-3">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <Users2 className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">Contactos LEYNA</h1>
              <p className="text-sm text-surface-500">{totalFiltrados} contactos</p>
            </div>
          </div>
          {isAdmin && (
            <button onClick={openNew}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
              <Plus className="w-4 h-4" />Nuevo contacto
            </button>
          )}
        </div>

        {/* Filtros */}
        <div className="card p-3 mb-4 flex flex-wrap gap-2 items-center">
          <div className="relative flex-1 min-w-48">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
            <input className="w-full pl-9 pr-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none"
              placeholder="Empresa, nombre, móvil, email, relación..."
              value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>
          <select value={relacionFilter} onChange={(e) => setRelacionFilter(e.target.value)}
            className="px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg">
            <option value="">Todas las relaciones</option>
            {RELACIONES.map((r) => <option key={r} value={r}>{r}</option>)}
          </select>
          <button onClick={() => setSoloDesoi(!soloDesoi)}
            className={cn("flex items-center gap-1.5 px-3 py-2 text-xs font-medium rounded-lg border transition-colors",
              soloDesoi ? "border-brand-500 bg-brand-50 text-brand-700" : "border-surface-200 text-surface-600 hover:bg-surface-50")}>
            {soloDesoi && <CheckCircle2 className="w-3.5 h-3.5" />}
            Solo DESOI
          </button>
          <button onClick={() => setSoloActivos(!soloActivos)}
            className={cn("flex items-center gap-1.5 px-3 py-2 text-xs font-medium rounded-lg border transition-colors",
              !soloActivos ? "border-amber-500 bg-amber-50 text-amber-700" : "border-surface-200 text-surface-600 hover:bg-surface-50")}>
            {!soloActivos ? "Ver todos" : "Solo activos"}
          </button>
          {(search || relacionFilter || soloDesoi) && (
            <button onClick={() => { setSearch(""); setRelacionFilter(""); setSoloDesoi(false); }}
              className="p-2 text-surface-400 hover:text-surface-600">
              <X className="w-4 h-4" />
            </button>
          )}
        </div>

        {/* Tabla */}
        <div className="card overflow-hidden">
          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="w-6 h-6 text-brand-500 animate-spin" /></div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-12 text-sm text-surface-400">Sin contactos</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-surface-100 bg-surface-50">
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Empresa / Nombre</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Contacto</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Relación</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Teléfonos</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Email</th>
                    <th className="text-center text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden sm:table-cell">DESOI</th>
                    {isAdmin && <th className="w-20"></th>}
                  </tr>
                </thead>
                <tbody>
                  {filtered.map((c) => (
                    <tr key={c.id}
                      onClick={() => openDetalle(c)}
                      className={cn("border-b border-surface-50 hover:bg-brand-50/20 cursor-pointer transition-colors",
                        !c.activo && "opacity-50")}>
                      <td className="px-4 py-2.5">
                        {c.empresa && <div className="font-medium text-surface-900 text-xs flex items-center gap-1">
                          <Building2 className="w-3 h-3 text-surface-400 shrink-0" />{c.empresa}
                        </div>}
                        {(c.apellidos || c.nombre) && (
                          <div className="text-[11px] text-surface-500 mt-0.5">
                            {[c.apellidos, c.nombre].filter(Boolean).join(", ")}
                          </div>
                        )}
                      </td>
                      <td className="px-4 py-2.5 hidden md:table-cell">
                        <div className="text-xs text-surface-600">
                          {[c.apellidos, c.nombre].filter(Boolean).join(" ")}
                        </div>
                      </td>
                      <td className="px-4 py-2.5">
                        {c.relacion && (
                          <span className={cn("badge text-[10px]", RELACION_COLOR[c.relacion] || RELACION_COLOR.OTROS)}>
                            {c.relacion}
                          </span>
                        )}
                      </td>
                      <td className="px-4 py-2.5 hidden lg:table-cell">
                        <div className="space-y-0.5">
                          {c.movil && <div className="flex items-center gap-1 text-xs text-surface-600">
                            <Phone className="w-3 h-3 text-surface-400" />{c.movil}
                          </div>}
                          {c.telefono && <div className="flex items-center gap-1 text-xs text-surface-500">
                            <Phone className="w-3 h-3 text-surface-300" />{c.telefono}
                          </div>}
                        </div>
                      </td>
                      <td className="px-4 py-2.5 hidden lg:table-cell">
                        {c.email && <a href={`mailto:${c.email}`} onClick={(e) => e.stopPropagation()}
                          className="flex items-center gap-1 text-xs text-brand-600 hover:underline">
                          <Mail className="w-3 h-3" />{c.email}
                        </a>}
                      </td>
                      <td className="px-4 py-2.5 text-center hidden sm:table-cell">
                        {c.es_cliente_desoi && (
                          <span className="badge text-[9px] bg-violet-100 text-violet-700">DESOI</span>
                        )}
                      </td>
                      {isAdmin && (
                        <td className="px-4 py-2.5">
                          <div className="flex items-center justify-end gap-1">
                            <button onClick={(e) => openEdit(c, e)}
                              className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100">
                              <Pencil className="w-3.5 h-3.5" />
                            </button>
                            <button onClick={(e) => { e.stopPropagation(); toggleActivo(c); }}
                              title={c.activo ? "Desactivar" : "Activar"}
                              className={cn("p-1.5 rounded-lg text-xs font-bold",
                                c.activo ? "text-surface-400 hover:bg-red-50 hover:text-red-500" : "text-surface-300 hover:bg-emerald-50 hover:text-emerald-500")}>
                              {c.activo ? "●" : "○"}
                            </button>
                          </div>
                        </td>
                      )}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {/* Modal detalle */}
      <Modal open={detalleOpen} onClose={() => setDetalleOpen(false)}
        title={detalleItem?.empresa || [detalleItem?.nombre, detalleItem?.apellidos].filter(Boolean).join(" ") || "Detalle"}
        size="md">
        {detalleItem && (
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-3 text-sm">
              {detalleItem.empresa && <div className="col-span-2">
                <p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Empresa</p>
                <p className="font-medium">{detalleItem.empresa}</p>
              </div>}
              {(detalleItem.apellidos || detalleItem.nombre) && <div className="col-span-2">
                <p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Persona de contacto</p>
                <p>{[detalleItem.apellidos, detalleItem.nombre].filter(Boolean).join(", ")}</p>
              </div>}
              <div>
                <p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Relación</p>
                <span className={cn("badge text-[10px]", RELACION_COLOR[detalleItem.relacion] || RELACION_COLOR.OTROS)}>
                  {detalleItem.relacion || "—"}
                </span>
              </div>
              <div>
                <p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Cliente DESOI</p>
                <p>{detalleItem.es_cliente_desoi ? "Sí" : "No"}</p>
              </div>
              {detalleItem.movil && <div>
                <p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Móvil</p>
                <a href={`tel:${detalleItem.movil}`} className="text-brand-600">{detalleItem.movil}</a>
              </div>}
              {detalleItem.telefono && <div>
                <p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Teléfono</p>
                <a href={`tel:${detalleItem.telefono}`} className="text-brand-600">{detalleItem.telefono}</a>
              </div>}
              {detalleItem.email && <div className="col-span-2">
                <p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Email</p>
                <a href={`mailto:${detalleItem.email}`} className="text-brand-600">{detalleItem.email}</a>
              </div>}
              {detalleItem.observaciones && <div className="col-span-2">
                <p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Observaciones</p>
                <p className="text-xs text-surface-600">{detalleItem.observaciones}</p>
              </div>}
            </div>
            <div className="flex justify-between items-center pt-2 border-t border-surface-100">
              <span className="text-[10px] text-surface-400">
                Origen: {detalleItem.origen} · ID CSV: {detalleItem.csv_id || "—"}
              </span>
              {isAdmin && (
                <button onClick={(e) => { setDetalleOpen(false); openEdit(detalleItem, e); }}
                  className="flex items-center gap-2 px-3 py-1.5 text-xs font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
                  <Pencil className="w-3.5 h-3.5" />Editar
                </button>
              )}
            </div>
          </div>
        )}
      </Modal>

      {/* Modal editar/crear */}
      <Modal open={modalOpen} onClose={() => setModalOpen(false)}
        title={editId ? "Editar contacto" : "Nuevo contacto"} size="md">
        <form onSubmit={handleSave} className="space-y-3">
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Empresa</label>
            <input className={ic} value={form.empresa} onChange={(e) => setForm({ ...form, empresa: e.target.value })} placeholder="Nombre de la empresa" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Apellidos</label>
              <input className={ic} value={form.apellidos} onChange={(e) => setForm({ ...form, apellidos: e.target.value })} />
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Nombre</label>
              <input className={ic} value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Móvil</label>
              <input className={ic} value={form.movil} onChange={(e) => setForm({ ...form, movil: e.target.value })} />
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Teléfono</label>
              <input className={ic} value={form.telefono} onChange={(e) => setForm({ ...form, telefono: e.target.value })} />
            </div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Email</label>
            <input type="email" className={ic} value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Relación</label>
              <select className={ic} value={form.relacion} onChange={(e) => setForm({ ...form, relacion: e.target.value })}>
                {RELACIONES.map((r) => <option key={r} value={r}>{r}</option>)}
              </select>
            </div>
            <div className="flex items-end pb-1">
              <label className="flex items-center gap-2 cursor-pointer text-sm text-surface-700">
                <input type="checkbox" checked={form.es_cliente_desoi}
                  onChange={(e) => setForm({ ...form, es_cliente_desoi: e.target.checked })}
                  className="w-4 h-4" />
                Cliente DESOI
              </label>
            </div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Observaciones</label>
            <textarea className={cn(ic, "h-16 resize-none")} value={form.observaciones}
              onChange={(e) => setForm({ ...form, observaciones: e.target.value })} />
          </div>
          <div className="flex items-center gap-2">
            <input type="checkbox" id="activo" checked={form.activo}
              onChange={(e) => setForm({ ...form, activo: e.target.checked })} className="w-4 h-4" />
            <label htmlFor="activo" className="text-sm text-surface-700">Activo</label>
          </div>
          {error && <p className="text-xs text-red-600">{error}</p>}
          <div className="flex justify-end gap-2 pt-1">
            <button type="button" onClick={() => setModalOpen(false)}
              className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {saving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}Guardar
            </button>
          </div>
        </form>
      </Modal>
    </AppLayout>
  );
}