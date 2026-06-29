"use client";
import { useState, useEffect, useCallback, useRef } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { FotoArticulo } from "@/components/shared/FotoArticulo";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import {
  Package, Loader2, Search, Plus, Pencil, Upload, Download,
  AlertTriangle, Calendar, Wrench, History, ClipboardList,
  ArrowLeftRight, SlidersHorizontal, ArrowDownToLine, ArrowUpFromLine,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";

const TIPOS = ["material", "maquinaria", "vehiculo", "otro"];
const empty = {
  referencia_proveedor: "", codigo_articulo: "", codigo_barras: "",
  nombre: "", tipo: "material", tipo_articulo_id: "",
  proveedor_id: "", unidad: "ud", stock_minimo: "0",
  caducidad: "", descripcion: "", foto_url: "",
  proximo_mantenimiento: "",
};
const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

const TIPO_MOV_BADGE: Record<string, string> = {
  entrada: "bg-emerald-100 text-emerald-700",
  salida: "bg-red-100 text-red-700",
  ajuste: "bg-amber-100 text-amber-700",
  traslado_salida: "bg-blue-100 text-blue-700",
  traslado_entrada: "bg-indigo-100 text-indigo-700",
};

export default function ArticulosPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const isAdmin = user?.role === "admin";
  const fileRef = useRef<HTMLInputElement>(null);
  const fotoRef = useRef<HTMLInputElement>(null);

  const [data, setData] = useState<any[]>([]);
  const [proveedores, setProveedores] = useState<any[]>([]);
  const [tiposArticulo, setTiposArticulo] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [tipoFilter, setTipoFilter] = useState("");
  const [uploadingFoto, setUploadingFoto] = useState(false);

  // Modal editar
  const [editOpen, setEditOpen] = useState(false);
  const [form, setForm] = useState(empty);
  const [editId, setEditId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Modal detalle (click en fila)
  const [detalleOpen, setDetalleOpen] = useState(false);
  const [detalleArticulo, setDetalleArticulo] = useState<any>(null);
  const [detalleTab, setDetalleTab] = useState<"info" | "movimientos" | "auditoria">("info");
  const [movArticulo, setMovArticulo] = useState<any[]>([]);
  const [audArticulo, setAudArticulo] = useState<any[]>([]);
  const [loadingDetalle, setLoadingDetalle] = useState(false);

  // Import
  const [importResult, setImportResult] = useState<string | null>(null);
  const [importing, setImporting] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [aR, pR, tR] = await Promise.all([
      (supabase.from("articulos") as any)
        .select("*, proveedor:proveedores(nombre), tipo_art:tipos_articulo(id,nombre,activo,orden)")
        .eq("activo", true).order("nombre"),
      (supabase.from("proveedores") as any).select("id, nombre").eq("activo", true).order("nombre"),
      (supabase.from("tipos_articulo") as any).select("id, nombre, activo, orden").order("orden").order("nombre"),
    ]);
    setData(aR.data || []);
    setProveedores(pR.data || []);
    const allTipos: any[] = tR.data || [];
    const tiposConArt = new Set((aR.data || []).map((a: any) => a.tipo_articulo_id).filter(Boolean));
    setTiposArticulo(allTipos.filter((t) => t.activo || tiposConArt.has(t.id)));
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const filtered = data.filter((a) => {
    const matchSearch =
      a.nombre?.toLowerCase().includes(search.toLowerCase()) ||
      a.codigo_articulo?.toLowerCase().includes(search.toLowerCase()) ||
      a.referencia_proveedor?.toLowerCase().includes(search.toLowerCase()) ||
      a.codigo_barras?.toLowerCase().includes(search.toLowerCase());
    const matchTipo = !tipoFilter || a.tipo_articulo_id === tipoFilter;
    return matchSearch && matchTipo;
  });

  // Abrir detalle al click en fila
  const openDetalle = async (a: any) => {
    setDetalleArticulo(a);
    setDetalleTab("info");
    setDetalleOpen(true);
    setLoadingDetalle(true);
    const [mR, audR] = await Promise.all([
      (supabase.from("movimientos_almacen") as any)
        .select("*, almacen_origen:almacenes!almacen_origen_id(nombre), almacen_destino:almacenes!almacen_destino_id(nombre), user:users(nombre)")
        .eq("articulo_id", a.id)
        .order("created_at", { ascending: false })
        .limit(100),
      (supabase.from("audit_log") as any)
        .select("*")
        .eq("entidad", "articulos")
        .eq("entidad_id", a.id)
        .order("created_at", { ascending: false })
        .limit(50),
    ]);
    setMovArticulo(mR.data || []);
    setAudArticulo(audR.data || []);
    setLoadingDetalle(false);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true); setError(null);
    try {
      const payload: any = {
        ...form,
        codigo_articulo: form.codigo_articulo || undefined,
        codigo_barras: form.codigo_barras || undefined,
        proveedor_id: form.proveedor_id || null,
        tipo_articulo_id: form.tipo_articulo_id || null,
        caducidad: form.caducidad || null,
        stock_minimo: parseFloat(form.stock_minimo) || 0,
        foto_url: form.foto_url || null,
        proximo_mantenimiento: form.proximo_mantenimiento || null,
      };
      if (editId) {
        const { error: err } = await (supabase.from("articulos") as any).update(payload).eq("id", editId);
        if (err) throw err;
      } else {
        const { error: err } = await (supabase.from("articulos") as any).insert({ ...payload, activo: true });
        if (err) throw err;
      }
      setEditOpen(false);
      fetchData();
    } catch (err: any) {
      setError(err.message || "Error al guardar");
      await logAuditErrorClient({ modulo: "almacen.articulos", entidad: "articulos", accion: editId ? "editar" : "crear", descripcion: "Error al guardar artículo", errorDetalle: err.message || "" });
    } finally { setSaving(false); }
  };

  const openEdit = (a: any, e: React.MouseEvent) => {
    e.stopPropagation(); // No abrir detalle al pinchar editar
    setForm({
      referencia_proveedor: a.referencia_proveedor || "",
      codigo_articulo: a.codigo_articulo || "",
      codigo_barras: a.codigo_barras || "",
      nombre: a.nombre || "",
      tipo: a.tipo || "material",
      tipo_articulo_id: a.tipo_articulo_id || "",
      proveedor_id: a.proveedor_id || "",
      unidad: a.unidad || "ud",
      stock_minimo: String(a.stock_minimo ?? 0),
      caducidad: a.caducidad || "",
      descripcion: a.descripcion || "",
      foto_url: a.foto_url || "",
      proximo_mantenimiento: a.proximo_mantenimiento || "",
    });
    setEditId(a.id); setError(null); setEditOpen(true);
  };

  const openNew = () => { setForm(empty); setEditId(null); setError(null); setEditOpen(true); };

  const uploadFoto = async (file: File) => {
    setUploadingFoto(true);
    try {
      const ext = file.name.split(".").pop();
      const path = `articulos/${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage.from("fotos").upload(path, file, { upsert: true });
      if (upErr) throw upErr;
      const { data: urlData } = supabase.storage.from("fotos").getPublicUrl(path);
      setForm((f) => ({ ...f, foto_url: urlData.publicUrl }));
    } catch (err: any) {
      setError("Error al subir foto: " + (err.message || err));
    } finally {
      setUploadingFoto(false);
      if (fotoRef.current) fotoRef.current.value = "";
    }
  };

  // ---- EXPORTAR CSV ----
  const exportCSV = () => {
    const cols = ["referencia_proveedor","codigo_articulo","codigo_barras","nombre","tipo","unidad","stock_minimo","caducidad","descripcion"];
    const header = cols.join(",");
    const rows = filtered.map((a) =>
      cols.map((c) => {
        const v = a[c] ?? "";
        return typeof v === "string" && v.includes(",") ? `"${v}"` : v;
      }).join(",")
    );
    const csv = [header, ...rows].join("\n");
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8;" }));
    const link = document.createElement("a"); link.href = url; link.download = "articulos.csv"; link.click();
    URL.revokeObjectURL(url);
  };

  // ---- IMPORTAR CSV ----
  const handleImport = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]; if (!file) return;
    setImporting(true); setImportResult(null);
    try {
      const text = await file.text();
      const lines = text.split("\n").map((l) => l.trim()).filter(Boolean);
      if (lines.length < 2) throw new Error("CSV vacío");
      const headers = lines[0].split(",").map((h) => h.trim().toLowerCase());
      const required = ["referencia_proveedor", "nombre"];
      const missing = required.filter((r) => !headers.includes(r));
      if (missing.length) throw new Error("Faltan columnas: " + missing.join(", "));
      const idx = (name: string) => headers.indexOf(name);
      let ok = 0; let errors = 0;
      for (let i = 1; i < lines.length; i++) {
        const cols: string[] = [];
        let cur = ""; let inQ = false;
        for (const ch of lines[i]) {
          if (ch === '"') { inQ = !inQ; } else if (ch === "," && !inQ) { cols.push(cur.trim()); cur = ""; } else { cur += ch; }
        }
        cols.push(cur.trim());
        const get = (name: string) => idx(name) >= 0 ? cols[idx(name)] || null : null;
        const payload: any = {
          referencia_proveedor: get("referencia_proveedor") || "",
          nombre: get("nombre") || "",
          codigo_articulo: get("codigo_articulo") || undefined,
          tipo: get("tipo") || "material",
          unidad: get("unidad") || "ud",
          stock_minimo: parseFloat(get("stock_minimo") || "0") || 0,
          caducidad: get("caducidad") || null,
          descripcion: get("descripcion") || null,
          activo: true,
        };
        if (!payload.referencia_proveedor || !payload.nombre) { errors++; continue; }
        const { error: err } = await (supabase.from("articulos") as any)
          .upsert(payload, { onConflict: "codigo_articulo", ignoreDuplicates: false });
        if (err) { errors++; } else { ok++; }
      }
      setImportResult(`Importados: ${ok}. Errores: ${errors}.`);
      fetchData();
    } catch (err: any) {
      setImportResult("Error: " + (err.message || "CSV inválido"));
    } finally {
      setImporting(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  };

  const hoy = new Date();
  const isExpired = (d: string | null) => d && new Date(d) < hoy;
  const isExpiringSoon = (d: string | null) => {
    if (!d) return false;
    const diff = (new Date(d).getTime() - hoy.getTime()) / 86400000;
    return diff >= 0 && diff <= 30;
  };

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="flex items-center justify-between mb-6 flex-wrap gap-3">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <Package className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">Artículos</h1>
              <p className="text-sm text-surface-500">{data.length} artículos · click en fila para ver detalle</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {isAdmin && (
              <>
                <button onClick={() => fileRef.current?.click()} disabled={importing}
                  className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200 disabled:opacity-60">
                  {importing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Upload className="w-4 h-4" />}Importar CSV
                </button>
                <input ref={fileRef} type="file" accept=".csv" className="hidden" onChange={handleImport} />
              </>
            )}
            <button onClick={exportCSV} className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200">
              <Download className="w-4 h-4" />Exportar
            </button>
            {isAdmin && (
              <button onClick={openNew} className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
                <Plus className="w-4 h-4" />Nuevo artículo
              </button>
            )}
          </div>
        </div>

        {importResult && (
          <div className={cn("px-4 py-2 rounded-lg text-sm mb-4", importResult.startsWith("Error") ? "bg-red-50 text-red-700" : "bg-emerald-50 text-emerald-700")}>
            {importResult}
          </div>
        )}

        <div className="card overflow-hidden">
          <div className="p-3 border-b border-surface-100 flex gap-2 flex-wrap">
            <div className="relative flex-1 min-w-48">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
              <input className="w-full pl-9 pr-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none"
                placeholder="Buscar por nombre, código, referencia..." value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
            <select value={tipoFilter} onChange={(e) => setTipoFilter(e.target.value)}
              className="px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg">
              <option value="">Todos los tipos</option>
              {tiposArticulo.map((t) => <option key={t.id} value={t.id}>{t.nombre}{!t.activo ? " (inactivo)" : ""}</option>)}
            </select>
          </div>

          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="w-6 h-6 text-brand-500 animate-spin" /></div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-12 text-sm text-surface-400">Sin artículos</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-surface-100 bg-surface-50">
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Artículo</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Ref. proveedor</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Tipo</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Proveedor</th>
                    <th className="text-center text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Unidad</th>
                    <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Stk. mín.</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Caducidad</th>
                    {isAdmin && <th className="w-10"></th>}
                  </tr>
                </thead>
                <tbody>
                  {filtered.map((a) => (
                    <tr key={a.id}
                      onClick={() => openDetalle(a)}
                      className="border-b border-surface-50 hover:bg-brand-50/30 cursor-pointer transition-colors">
                      <td className="px-4 py-2.5">
                        <div className="flex items-center gap-2">
                          <FotoArticulo url={a.foto_url} nombre={a.nombre} size="md" />
                          <div>
                            <div className="font-medium text-surface-900 text-xs">{a.nombre}</div>
                            <div className="text-[10px] text-surface-400 font-mono">{a.codigo_articulo}</div>
                          </div>
                        </div>
                      </td>
                      <td className="px-4 py-2.5 text-xs text-surface-500 hidden md:table-cell">{a.referencia_proveedor}</td>
                      <td className="px-4 py-2.5">
                        <span className={cn("badge text-[10px]",
                          a.tipo === "material" ? "bg-blue-100 text-blue-700" :
                          a.tipo === "maquinaria" ? "bg-orange-100 text-orange-700" :
                          a.tipo === "vehiculo" ? "bg-purple-100 text-purple-700" : "bg-surface-100 text-surface-600")}>
                          {a.tipo_art?.nombre || a.tipo}
                        </span>
                      </td>
                      <td className="px-4 py-2.5 text-xs text-surface-600 hidden lg:table-cell">{a.proveedor?.nombre || "—"}</td>
                      <td className="px-4 py-2.5 text-center text-xs text-surface-500">{a.unidad}</td>
                      <td className="px-4 py-2.5 text-right text-xs font-mono">{a.stock_minimo}</td>
                      <td className="px-4 py-2.5 hidden md:table-cell">
                        {a.caducidad ? (
                          <span className={cn("flex items-center gap-1 text-xs",
                            isExpired(a.caducidad) ? "text-red-600" : isExpiringSoon(a.caducidad) ? "text-amber-600" : "text-surface-500")}>
                            {(isExpired(a.caducidad) || isExpiringSoon(a.caducidad)) && <AlertTriangle className="w-3 h-3" />}
                            {new Date(a.caducidad).toLocaleDateString("es-ES")}
                          </span>
                        ) : <span className="text-surface-300 text-xs">—</span>}
                      </td>
                      {isAdmin && (
                        <td className="px-4 py-2.5">
                          <button onClick={(e) => openEdit(a, e)}
                            className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-200 hover:text-brand-600 transition-colors">
                            <Pencil className="w-3.5 h-3.5" />
                          </button>
                        </td>
                      )}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
        <p className="text-[11px] text-surface-400 mt-3">
          CSV: <code className="bg-surface-100 px-1 rounded">referencia_proveedor, nombre</code> obligatorios.
          Opcionales: <code className="bg-surface-100 px-1 rounded">codigo_articulo, tipo, unidad, stock_minimo, caducidad, descripcion</code>
        </p>
      </div>

      {/* ============================================================
          MODAL DETALLE (click en fila)
          Con pestañas: Info · Movimientos · Auditoría
      ============================================================ */}
      <Modal open={detalleOpen} onClose={() => setDetalleOpen(false)}
        title={detalleArticulo?.nombre || "Detalle artículo"} size="lg">
        {detalleArticulo && (
          <div>
            {/* Tabs */}
            <div className="flex gap-1 mb-4 bg-surface-100 rounded-lg p-1 w-fit">
              {([
                { id: "info", label: "Información", icon: Package },
                { id: "movimientos", label: "Movimientos", icon: ArrowLeftRight },
                { id: "auditoria", label: "Auditoría", icon: ClipboardList },
              ] as const).map((t) => (
                <button key={t.id} onClick={() => setDetalleTab(t.id)}
                  className={cn("flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-md transition-colors",
                    detalleTab === t.id ? "bg-white shadow-sm text-surface-900" : "text-surface-500 hover:text-surface-700")}>
                  <t.icon className="w-3.5 h-3.5" />{t.label}
                </button>
              ))}
            </div>

            {loadingDetalle ? (
              <div className="flex justify-center py-8"><Loader2 className="w-5 h-5 text-brand-500 animate-spin" /></div>
            ) : (
              <>
                {/* Tab: Info */}
                {detalleTab === "info" && (
                  <div className="space-y-4">
                    <div className="flex gap-4 items-start">
                      {detalleArticulo.foto_url ? (
                        <img src={detalleArticulo.foto_url} alt={detalleArticulo.nombre}
                          className="w-28 h-28 rounded-xl object-contain bg-surface-50 border border-surface-200 shrink-0" />
                      ) : (
                        <div className="w-28 h-28 rounded-xl bg-surface-100 flex items-center justify-center border border-surface-200 shrink-0">
                          <Package className="w-10 h-10 text-surface-300" />
                        </div>
                      )}
                      <div className="flex-1 grid grid-cols-2 gap-3 text-sm">
                        <div><p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Código artículo</p><p className="font-mono text-xs">{detalleArticulo.codigo_articulo}</p></div>
                        <div><p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Código barras</p><p className="font-mono text-xs">{detalleArticulo.codigo_barras || "—"}</p></div>
                        <div><p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Ref. proveedor</p><p className="text-xs">{detalleArticulo.referencia_proveedor}</p></div>
                        <div><p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Tipo</p>
                          <span className={cn("badge text-[10px]",
                            detalleArticulo.tipo === "maquinaria" ? "bg-orange-100 text-orange-700" :
                            detalleArticulo.tipo === "vehiculo" ? "bg-purple-100 text-purple-700" :
                            "bg-blue-100 text-blue-700")}>
                            {detalleArticulo.tipo_art?.nombre || detalleArticulo.tipo}
                          </span>
                        </div>
                        <div><p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Proveedor</p><p className="text-xs">{detalleArticulo.proveedor?.nombre || "—"}</p></div>
                        <div><p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Unidad</p><p className="text-xs">{detalleArticulo.unidad}</p></div>
                        <div><p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Stock mínimo</p><p className="font-mono text-xs">{detalleArticulo.stock_minimo}</p></div>
                        <div><p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5">Caducidad</p>
                          <p className={cn("text-xs", isExpired(detalleArticulo.caducidad) ? "text-red-600 font-semibold" : isExpiringSoon(detalleArticulo.caducidad) ? "text-amber-600" : "")}>
                            {detalleArticulo.caducidad ? new Date(detalleArticulo.caducidad).toLocaleDateString("es-ES") : "—"}
                          </p>
                        </div>
                        {detalleArticulo.tipo === "maquinaria" && (
                          <div><p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5 flex items-center gap-1"><Wrench className="w-3 h-3" />Próx. mantenimiento</p>
                            <p className={cn("text-xs", isExpired(detalleArticulo.proximo_mantenimiento) ? "text-red-600 font-semibold" : isExpiringSoon(detalleArticulo.proximo_mantenimiento) ? "text-amber-600" : "")}>
                              {detalleArticulo.proximo_mantenimiento ? new Date(detalleArticulo.proximo_mantenimiento).toLocaleDateString("es-ES") : "—"}
                            </p>
                          </div>
                        )}
                      </div>
                    </div>
                    {detalleArticulo.descripcion && (
                      <div className="px-3 py-2 bg-surface-50 rounded-lg text-xs text-surface-600">{detalleArticulo.descripcion}</div>
                    )}
                    {isAdmin && (
                      <div className="flex justify-end">
                        <button onClick={(e) => { setDetalleOpen(false); openEdit(detalleArticulo, e); }}
                          className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
                          <Pencil className="w-3.5 h-3.5" />Editar artículo
                        </button>
                      </div>
                    )}
                  </div>
                )}

                {/* Tab: Movimientos */}
                {detalleTab === "movimientos" && (
                  <div>
                    {movArticulo.length === 0 ? (
                      <div className="text-center py-8 text-sm text-surface-400">Sin movimientos registrados</div>
                    ) : (
                      <div className="max-h-[55vh] overflow-y-auto">
                        <table className="w-full text-sm">
                          <thead className="sticky top-0 bg-white z-10">
                            <tr className="border-b border-surface-100 bg-surface-50">
                              <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-3">Fecha</th>
                              <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-3">Tipo</th>
                              <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-3">Cantidad</th>
                              <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-3 hidden sm:table-cell">Origen</th>
                              <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-3 hidden sm:table-cell">Destino</th>
                              <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-3 hidden md:table-cell">Usuario</th>
                            </tr>
                          </thead>
                          <tbody>
                            {movArticulo.map((m) => {
                              const esSalida = m.tipo === "salida" || m.tipo === "traslado_salida";
                              return (
                                <tr key={m.id} className="border-b border-surface-50 hover:bg-surface-50/50">
                                  <td className="px-3 py-2 text-[10px] font-mono text-surface-500 whitespace-nowrap">
                                    {new Date(m.fecha).toLocaleDateString("es-ES")}
                                  </td>
                                  <td className="px-3 py-2">
                                    <span className={cn("badge text-[9px]", TIPO_MOV_BADGE[m.tipo] || "bg-surface-100 text-surface-600")}>
                                      {m.tipo.replace(/_/g, " ")}
                                    </span>
                                  </td>
                                  <td className="px-3 py-2 text-right">
                                    <span className={cn("font-mono text-xs font-semibold", esSalida ? "text-red-600" : "text-emerald-700")}>
                                      {esSalida ? "−" : "+"}{m.cantidad}
                                    </span>
                                  </td>
                                  <td className="px-3 py-2 text-[10px] text-surface-500 hidden sm:table-cell">{m.almacen_origen?.nombre || "—"}</td>
                                  <td className="px-3 py-2 text-[10px] text-surface-500 hidden sm:table-cell">{m.almacen_destino?.nombre || "—"}</td>
                                  <td className="px-3 py-2 text-[10px] text-surface-500 hidden md:table-cell">{m.user?.nombre || "—"}</td>
                                </tr>
                              );
                            })}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </div>
                )}

                {/* Tab: Auditoría */}
                {detalleTab === "auditoria" && (
                  <div>
                    {audArticulo.length === 0 ? (
                      <div className="text-center py-8 text-sm text-surface-400">Sin registros de auditoría</div>
                    ) : (
                      <div className="max-h-[55vh] overflow-y-auto space-y-1.5">
                        {audArticulo.map((a) => (
                          <div key={a.id} className="flex items-start gap-3 px-3 py-2 rounded-lg bg-surface-50 border border-surface-100">
                            <div className="shrink-0 mt-0.5">
                              <span className={cn("badge text-[9px]",
                                a.accion === "crear" ? "bg-emerald-100 text-emerald-700" :
                                a.accion === "eliminar" ? "bg-red-100 text-red-700" : "bg-amber-100 text-amber-700")}>
                                {a.accion}
                              </span>
                            </div>
                            <div className="flex-1 min-w-0">
                              <p className="text-xs text-surface-700">{a.descripcion}</p>
                              <p className="text-[10px] text-surface-400 mt-0.5">
                                {new Date(a.created_at).toLocaleString("es-ES")}
                                {a.user_rol && ` · ${a.user_rol}`}
                              </p>
                            </div>
                            <span className={cn("badge text-[9px] shrink-0", a.resultado === "exito" ? "bg-emerald-100 text-emerald-700" : "bg-red-100 text-red-700")}>
                              {a.resultado}
                            </span>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </>
            )}
          </div>
        )}
      </Modal>

      {/* ============================================================
          MODAL EDITAR / CREAR
      ============================================================ */}
      <Modal open={editOpen} onClose={() => setEditOpen(false)}
        title={editId ? "Editar artículo" : "Nuevo artículo"} size="lg">
        <form onSubmit={handleSave} className="space-y-3">
          {/* Foto */}
          <div className="flex flex-col items-center gap-2">
            {form.foto_url ? (
              <img src={form.foto_url} alt="foto"
                className="w-28 h-28 rounded-xl object-contain bg-surface-50 border border-surface-200" />
            ) : (
              <div className="w-28 h-28 rounded-xl bg-surface-100 flex items-center justify-center border border-surface-200">
                <Package className="w-10 h-10 text-surface-300" />
              </div>
            )}
            <div className="flex items-center gap-2">
              <button type="button" disabled={uploadingFoto}
                onClick={() => fotoRef.current?.click()}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200 disabled:opacity-60">
                {uploadingFoto ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Upload className="w-3.5 h-3.5" />}
                {form.foto_url ? "Cambiar foto" : "Subir foto"}
              </button>
              {form.foto_url && (
                <button type="button" onClick={() => setForm({ ...form, foto_url: "" })}
                  className="text-[11px] text-red-500 hover:text-red-700">Quitar</button>
              )}
            </div>
            <input ref={fotoRef} type="file" accept="image/*" className="hidden"
              onChange={(e) => { const f = e.target.files?.[0]; if (f) uploadFoto(f); }} />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Referencia proveedor *</label>
              <input required className={ic} value={form.referencia_proveedor} onChange={(e) => setForm({ ...form, referencia_proveedor: e.target.value })} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Código artículo</label>
              <input className={ic} value={form.codigo_articulo} onChange={(e) => setForm({ ...form, codigo_articulo: e.target.value })} placeholder="Auto-generado si vacío" /></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Código de barras (EAN)</label>
              <input className={ic} value={form.codigo_barras} onChange={(e) => setForm({ ...form, codigo_barras: e.target.value })} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Nombre *</label>
              <input required className={ic} value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} /></div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Tipo de artículo</label>
              <select className={ic} value={form.tipo_articulo_id} onChange={(e) => setForm({ ...form, tipo_articulo_id: e.target.value })}>
                <option value="">Sin tipo</option>
                {tiposArticulo.filter((t) => t.activo).map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}
              </select>
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Unidad</label>
              <input className={ic} value={form.unidad} onChange={(e) => setForm({ ...form, unidad: e.target.value })} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Stock mínimo</label>
              <input type="number" min="0" step="0.01" className={ic} value={form.stock_minimo} onChange={(e) => setForm({ ...form, stock_minimo: e.target.value })} /></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Proveedor</label>
              <select className={ic} value={form.proveedor_id} onChange={(e) => setForm({ ...form, proveedor_id: e.target.value })}>
                <option value="">Sin proveedor</option>
                {proveedores.map((p) => <option key={p.id} value={p.id}>{p.nombre}</option>)}
              </select>
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Caducidad</label>
              <input type="date" className={ic} value={form.caducidad} onChange={(e) => setForm({ ...form, caducidad: e.target.value })} /></div>
          </div>
          {/* Campo mantenimiento: solo para maquinaria */}
          {(form.tipo === "maquinaria" || tiposArticulo.find((t) => t.id === form.tipo_articulo_id)?.nombre?.toLowerCase().includes("maquinaria")) && (
            <div><label className="block text-xs font-medium text-surface-600 mb-1 flex items-center gap-1">
              <Wrench className="w-3.5 h-3.5 text-orange-500" />Próximo mantenimiento
            </label>
              <input type="date" className={ic} value={form.proximo_mantenimiento} onChange={(e) => setForm({ ...form, proximo_mantenimiento: e.target.value })} />
            </div>
          )}
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Descripción</label>
            <textarea className={cn(ic, "h-16 resize-none")} value={form.descripcion} onChange={(e) => setForm({ ...form, descripcion: e.target.value })} /></div>
          {error && <p className="text-xs text-red-600">{error}</p>}
          <div className="flex justify-end gap-2 pt-1">
            <button type="button" onClick={() => setEditOpen(false)} className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving} className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {saving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}Guardar
            </button>
          </div>
        </form>
      </Modal>
    </AppLayout>
  );
}