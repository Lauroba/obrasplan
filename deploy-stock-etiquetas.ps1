#Requires -Version 5.1
# deploy-stock-etiquetas.ps1
# Stock cache + Diseñador de etiquetas
#
# IMPORTANTE: ejecutar primero 040_stock_cache_etiquetas.sql en Supabase
# (crea stock_cache, funciones recalcular, trigger, etiquetas_plantillas,
#  4 plantillas por defecto y backfill inicial del stock de todos los articulos)

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Escribiendo archivos" -ForegroundColor Cyan

$dst = "src\app\almacen\articulos\page.tsx"
$content = @'
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
  Warehouse, RefreshCw, TrendingUp,
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
  const [detalleTab, setDetalleTab] = useState<"info" | "movimientos" | "auditoria" | "stock_almacenes">("info");
  const [stockAlmacenes, setStockAlmacenes] = useState<any[]>([]);
  const [stockTotal, setStockTotal] = useState<number | null>(null);
  const [recalculando, setRecalculando] = useState(false);
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
    const [mR, audR, stockR] = await Promise.all([
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
      (supabase.from("stock_cache") as any)
        .select("*, almacen:almacenes(nombre, codigo_almacen, ubicacion)")
        .eq("articulo_id", a.id)
        .gt("stock_qty", 0)
        .order("stock_qty", { ascending: false }),
    ]);
    setMovArticulo(mR.data || []);
    setAudArticulo(audR.data || []);
    const stockRows = stockR.data || [];
    setStockAlmacenes(stockRows);
    setStockTotal(stockRows.reduce((acc: number, r: any) => acc + Number(r.stock_qty), 0));
    setLoadingDetalle(false);
  };

  const handleRecalcular = async (soloEsteArticulo: boolean) => {
    setRecalculando(true);
    try {
      if (soloEsteArticulo && detalleArticulo) {
        await (supabase.rpc as any)("recalcular_stock_articulo", { p_articulo_id: detalleArticulo.id });
        // Recargar stock
        const { data } = await (supabase.from("stock_cache") as any)
          .select("*, almacen:almacenes(nombre, codigo_almacen, ubicacion)")
          .eq("articulo_id", detalleArticulo.id)
          .gt("stock_qty", 0)
          .order("stock_qty", { ascending: false });
        const rows = data || [];
        setStockAlmacenes(rows);
        setStockTotal(rows.reduce((acc: number, r: any) => acc + Number(r.stock_qty), 0));
      } else {
        await (supabase.rpc as any)("recalcular_stock_todos");
      }
    } catch (err: any) {
      alert("Error al recalcular: " + (err?.message || err));
    } finally { setRecalculando(false); }
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
                { id: "stock_almacenes", label: "Stock almacenes", icon: Warehouse },
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
                        <div>
                          <p className="text-[10px] text-surface-400 uppercase font-semibold mb-0.5 flex items-center gap-1"><TrendingUp className="w-3 h-3" />Stock total empresa</p>
                          <div className="flex items-center gap-2">
                            {stockTotal !== null ? (
                              <span className={cn("font-mono text-sm font-bold", stockTotal < 0 ? "text-red-600" : stockTotal === 0 ? "text-surface-400" : "text-emerald-700")}>
                                {Number(stockTotal).toFixed(2)} {detalleArticulo.unidad}
                              </span>
                            ) : <span className="text-surface-400 text-xs">Sin movimientos</span>}
                            <button onClick={() => handleRecalcular(true)} disabled={recalculando} title="Recalcular stock"
                              className="p-1 rounded text-surface-400 hover:text-brand-600 hover:bg-brand-50 disabled:opacity-50">
                              <RefreshCw className={cn("w-3.5 h-3.5", recalculando && "animate-spin")} />
                            </button>
                          </div>
                        </div>
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

                {/* Tab: Stock por almacén */}
                {detalleTab === "stock_almacenes" && (
                  <div className="space-y-3">
                    <div className="flex items-center justify-between">
                      <p className="text-xs text-surface-500">
                        Stock en {stockAlmacenes.length} almacén{stockAlmacenes.length !== 1 ? "es" : ""} ·
                        Total: <span className="font-bold font-mono">{stockTotal !== null ? Number(stockTotal).toFixed(2) : "—"} {detalleArticulo?.unidad}</span>
                      </p>
                      <button onClick={() => handleRecalcular(true)} disabled={recalculando}
                        className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-brand-600 bg-brand-50 rounded-lg hover:bg-brand-100 disabled:opacity-60">
                        <RefreshCw className={cn("w-3.5 h-3.5", recalculando && "animate-spin")} />
                        Recalcular
                      </button>
                    </div>
                    {stockAlmacenes.length === 0 ? (
                      <div className="text-center py-8 text-sm text-surface-400">
                        <Warehouse className="w-8 h-8 mx-auto mb-2 opacity-30" />
                        Este artículo no tiene stock en ningún almacén
                      </div>
                    ) : (
                      <div className="overflow-x-auto">
                        <table className="w-full text-sm">
                          <thead>
                            <tr className="border-b border-surface-100 bg-surface-50">
                              <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-3">Almacén</th>
                              <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-3 hidden sm:table-cell">Ubicación</th>
                              <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-3">Stock</th>
                              <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-3 hidden md:table-cell">Actualizado</th>
                            </tr>
                          </thead>
                          <tbody>
                            {stockAlmacenes.map((s: any) => (
                              <tr key={s.almacen_id} className="border-b border-surface-50 hover:bg-surface-50/50">
                                <td className="px-3 py-2.5">
                                  <div className="font-medium text-surface-900 text-xs">{s.almacen?.nombre || "—"}</div>
                                  <div className="text-[10px] text-surface-400 font-mono">{s.almacen?.codigo_almacen}</div>
                                </td>
                                <td className="px-3 py-2.5 text-xs text-surface-500 hidden sm:table-cell">
                                  {s.almacen?.ubicacion || "—"}
                                </td>
                                <td className="px-3 py-2.5 text-right">
                                  <span className={cn("font-mono text-sm font-bold",
                                    Number(s.stock_qty) < 0 ? "text-red-600" : "text-surface-900")}>
                                    {Number(s.stock_qty).toFixed(2)}
                                  </span>
                                  <span className="text-[10px] text-surface-400 ml-1">{detalleArticulo?.unidad}</span>
                                </td>
                                <td className="px-3 py-2.5 text-[10px] text-surface-400 hidden md:table-cell">
                                  {new Date(s.updated_at).toLocaleDateString("es-ES")}
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
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
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\almacen\articulos\page.tsx" -ForegroundColor Green

$dst = "src\app\almacen\etiquetas\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback, useRef } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import {
  Tag, Loader2, Plus, Pencil, Trash2, Eye, Printer,
  Copy, Package, RefreshCw, ChevronDown, Check,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import QRCode from "qrcode";

const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

const CAMPOS_DISPONIBLES = [
  { id: "nombre",               label: "Nombre artículo" },
  { id: "codigo_articulo",      label: "Código artículo" },
  { id: "codigo_barras",        label: "Código de barras (texto)" },
  { id: "referencia_proveedor", label: "Ref. proveedor" },
  { id: "proveedor",            label: "Proveedor" },
  { id: "tipo",                 label: "Tipo" },
  { id: "unidad",               label: "Unidad" },
  { id: "stock_minimo",         label: "Stock mínimo" },
  { id: "qr",                   label: "Código QR (imagen)" },
];

const TAMANIOS_PRESET = [
  { label: "Avery L7160 (3×7 = 21/hoja)", ancho: 63.5, alto: 38.1, cols: 3, filas: 7 },
  { label: "Avery L7163 (2×7 = 14/hoja)", ancho: 99.1, alto: 38.1, cols: 2, filas: 7 },
  { label: "Grande (2×4 = 8/hoja)",        ancho: 105,  alto: 74.25, cols: 2, filas: 4 },
  { label: "A6 individual",                ancho: 140,  alto: 97,   cols: 1, filas: 1 },
  { label: "Personalizado",                ancho: 0,    alto: 0,    cols: 0, filas: 0 },
];

const emptyPlantilla = {
  nombre: "", descripcion: "",
  hoja_ancho_mm: 210, hoja_alto_mm: 297,
  etiq_ancho_mm: 63.5, etiq_alto_mm: 38.1,
  etiq_cols: 3, etiq_filas: 7,
  margen_h_mm: 0, margen_v_mm: 0,
  espacio_h_mm: 0, espacio_v_mm: 0,
  campos: ["qr", "nombre", "codigo_articulo", "referencia_proveedor"],
  qr_size_pct: 45, font_size: 7, mostrar_borde: true,
};

// ============================================================
// Componente de previsualización de una etiqueta
// ============================================================
function EtiquetaPreview({ plantilla, articulo, qrDataUrl }: {
  plantilla: typeof emptyPlantilla;
  articulo: any;
  qrDataUrl: string;
}) {
  const mm2px = (mm: number) => mm * 3.7795; // 1mm ≈ 3.7795px a 96dpi
  const w = mm2px(plantilla.etiq_ancho_mm);
  const h = mm2px(plantilla.etiq_alto_mm);
  const qrPx = mm2px(plantilla.etiq_ancho_mm * plantilla.qr_size_pct / 100);

  const textFields = plantilla.campos.filter((c) => c !== "qr");
  const showQr = plantilla.campos.includes("qr") && qrDataUrl;

  const getVal = (field: string) => {
    const map: Record<string, string> = {
      nombre: articulo?.nombre || "Nombre artículo",
      codigo_articulo: articulo?.codigo_articulo || "COD-001",
      codigo_barras: articulo?.codigo_barras || "1234567890",
      referencia_proveedor: articulo?.referencia_proveedor || "REF-001",
      proveedor: articulo?.proveedor?.nombre || "Proveedor",
      tipo: articulo?.tipo || "Material",
      unidad: articulo?.unidad || "ud",
      stock_minimo: `Mín: ${articulo?.stock_minimo ?? 0}`,
    };
    return map[field] || field;
  };

  return (
    <div
      style={{
        width: w, height: h,
        border: plantilla.mostrar_borde ? "1px solid #ccc" : "none",
        borderRadius: 2,
        display: "flex",
        flexDirection: "row",
        alignItems: "stretch",
        overflow: "hidden",
        backgroundColor: "white",
        fontFamily: "Arial, sans-serif",
        fontSize: plantilla.font_size,
      }}>
      {/* QR a la izquierda */}
      {showQr && (
        <div style={{ width: qrPx, display: "flex", alignItems: "center", justifyContent: "center", padding: 3, flexShrink: 0 }}>
          <img src={qrDataUrl} alt="QR" style={{ width: "100%", height: "auto" }} />
        </div>
      )}
      {/* Campos de texto a la derecha */}
      <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", padding: "3px 4px", gap: 1, overflow: "hidden" }}>
        {textFields.map((field) => (
          <div key={field} style={{ fontSize: plantilla.font_size, lineHeight: 1.2, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
            {getVal(field)}
          </div>
        ))}
      </div>
    </div>
  );
}

// ============================================================
// PÁGINA PRINCIPAL
// ============================================================
export default function EtiquetasPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const isAdmin = user?.role === "admin";

  const [plantillas, setPlantillas] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [articulos, setArticulos] = useState<any[]>([]);
  const [articuloSel, setArticuloSel] = useState<any>(null);
  const [qrDataUrl, setQrDataUrl] = useState("");

  // Modal de editor de plantilla
  const [editorOpen, setEditorOpen] = useState(false);
  const [form, setForm] = useState(emptyPlantilla);
  const [editId, setEditId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [presetIdx, setPresetIdx] = useState(0);

  // Modal de impresión
  const [printOpen, setPrintOpen] = useState(false);
  const [printPlantilla, setPrintPlantilla] = useState<any>(null);
  const [printCantidad, setPrintCantidad] = useState(1);
  const printRef = useRef<HTMLDivElement>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [pR, aR] = await Promise.all([
      (supabase.from("etiquetas_plantillas") as any).select("*").eq("activo", true).order("created_at"),
      (supabase.from("articulos") as any).select("id, nombre, codigo_articulo, codigo_barras, referencia_proveedor, tipo, unidad, stock_minimo, proveedor:proveedores(nombre)").eq("activo", true).order("nombre").limit(500),
    ]);
    setPlantillas(pR.data || []);
    setArticulos(aR.data || []);
    if (aR.data?.[0]) setArticuloSel(aR.data[0]);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  // Generar QR cuando cambia el artículo seleccionado
  useEffect(() => {
    const codigo = articuloSel?.codigo_articulo || articuloSel?.codigo_barras || "SIN-CODIGO";
    QRCode.toDataURL(codigo, { width: 200, margin: 1 }).then(setQrDataUrl).catch(console.error);
  }, [articuloSel]);

  const openNew = () => {
    setForm(emptyPlantilla); setEditId(null); setError(null);
    setPresetIdx(0); setEditorOpen(true);
  };

  const openEdit = (p: any) => {
    setForm({
      nombre: p.nombre, descripcion: p.descripcion || "",
      hoja_ancho_mm: p.hoja_ancho_mm, hoja_alto_mm: p.hoja_alto_mm,
      etiq_ancho_mm: p.etiq_ancho_mm, etiq_alto_mm: p.etiq_alto_mm,
      etiq_cols: p.etiq_cols, etiq_filas: p.etiq_filas,
      margen_h_mm: p.margen_h_mm, margen_v_mm: p.margen_v_mm,
      espacio_h_mm: p.espacio_h_mm, espacio_v_mm: p.espacio_v_mm,
      campos: p.campos || [],
      qr_size_pct: p.qr_size_pct, font_size: p.font_size,
      mostrar_borde: p.mostrar_borde,
    });
    setEditId(p.id); setError(null); setPresetIdx(4); setEditorOpen(true);
  };

  const openDuplicate = (p: any) => {
    openEdit({ ...p, id: undefined });
    setEditId(null);
    setForm((f) => ({ ...f, nombre: f.nombre + " (copia)" }));
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.nombre.trim()) { setError("El nombre es obligatorio"); return; }
    setSaving(true); setError(null);
    try {
      const payload = { ...form, created_by: user?.id };
      if (editId) {
        const { error: err } = await (supabase.from("etiquetas_plantillas") as any).update(payload).eq("id", editId);
        if (err) throw err;
      } else {
        const { error: err } = await (supabase.from("etiquetas_plantillas") as any).insert(payload);
        if (err) throw err;
      }
      setEditorOpen(false); fetchData();
    } catch (err: any) { setError(err.message); }
    finally { setSaving(false); }
  };

  const handleDelete = async (p: any) => {
    if (!confirm(`¿Eliminar la plantilla "${p.nombre}"?`)) return;
    await (supabase.from("etiquetas_plantillas") as any).update({ activo: false }).eq("id", p.id);
    fetchData();
  };

  const applyPreset = (idx: number) => {
    setPresetIdx(idx);
    const preset = TAMANIOS_PRESET[idx];
    if (preset.ancho > 0) {
      setForm((f) => ({
        ...f,
        etiq_ancho_mm: preset.ancho, etiq_alto_mm: preset.alto,
        etiq_cols: preset.cols, etiq_filas: preset.filas,
      }));
    }
  };

  const toggleCampo = (campo: string) => {
    setForm((f) => ({
      ...f,
      campos: f.campos.includes(campo)
        ? f.campos.filter((c) => c !== campo)
        : [...f.campos, campo],
    }));
  };

  const handlePrint = (p: any) => {
    setPrintPlantilla(p);
    setPrintCantidad(p.etiq_cols * p.etiq_filas);
    setPrintOpen(true);
  };

  const doPrint = async () => {
    if (!printRef.current || !printPlantilla || !articuloSel) return;

    const mm2px = (mm: number) => mm * 3.7795;
    const plantilla = { ...emptyPlantilla, ...printPlantilla };

    // Generar QR para el artículo seleccionado
    const codigo = articuloSel.codigo_articulo || articuloSel.codigo_barras || "SIN-CODIGO";
    const qr = await QRCode.toDataURL(codigo, { width: 300, margin: 1 });

    // Construir HTML de impresión
    const etiqW = mm2px(plantilla.etiq_ancho_mm);
    const etiqH = mm2px(plantilla.etiq_alto_mm);
    const qrPx  = mm2px(plantilla.etiq_ancho_mm * plantilla.qr_size_pct / 100);
    const showQr = plantilla.campos.includes("qr");
    const textFields = plantilla.campos.filter((c: string) => c !== "qr");

    const getVal = (field: string) => {
      const map: Record<string, string> = {
        nombre: articuloSel.nombre || "",
        codigo_articulo: articuloSel.codigo_articulo || "",
        codigo_barras: articuloSel.codigo_barras || "",
        referencia_proveedor: articuloSel.referencia_proveedor || "",
        proveedor: articuloSel.proveedor?.nombre || "",
        tipo: articuloSel.tipo || "",
        unidad: articuloSel.unidad || "",
        stock_minimo: `Mín: ${articuloSel.stock_minimo ?? 0}`,
      };
      return map[field] || field;
    };

    const etiqHTML = `
      <div style="width:${etiqW}px;height:${etiqH}px;display:flex;flex-direction:row;align-items:stretch;overflow:hidden;border:${plantilla.mostrar_borde ? "1px solid #999" : "none"};box-sizing:border-box;">
        ${showQr ? `<div style="width:${qrPx}px;display:flex;align-items:center;justify-content:center;padding:2px;flex-shrink:0;"><img src="${qr}" style="width:100%;height:auto;" /></div>` : ""}
        <div style="flex:1;display:flex;flex-direction:column;justify-content:center;padding:2px 4px;gap:1px;overflow:hidden;font-family:Arial,sans-serif;font-size:${plantilla.font_size}px;">
          ${textFields.map((f: string) => `<div style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:1.2;">${getVal(f)}</div>`).join("")}
        </div>
      </div>`;

    const marginH = mm2px(plantilla.margen_h_mm);
    const marginV = mm2px(plantilla.margen_v_mm);
    const gapH    = mm2px(plantilla.espacio_h_mm);
    const gapV    = mm2px(plantilla.espacio_v_mm);
    const total   = Math.min(printCantidad, plantilla.etiq_cols * plantilla.etiq_filas);

    let grid = `<div style="display:grid;grid-template-columns:repeat(${plantilla.etiq_cols},${etiqW}px);gap:${gapV}px ${gapH}px;padding:${marginV}px ${marginH}px;width:${mm2px(plantilla.hoja_ancho_mm)}px;">`;
    for (let i = 0; i < total; i++) grid += etiqHTML;
    grid += "</div>";

    const win = window.open("", "_blank", "width=900,height=700");
    if (!win) return;
    win.document.write(`<!DOCTYPE html><html><head><title>Etiquetas</title><style>@page{margin:0}body{margin:0;padding:0}</style></head><body>${grid}</body></html>`);
    win.document.close();
    setTimeout(() => { win.print(); }, 500);
  };

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <Tag className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">Diseñador de etiquetas</h1>
              <p className="text-sm text-surface-500">{plantillas.length} plantillas guardadas</p>
            </div>
          </div>
          {isAdmin && (
            <button onClick={openNew}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
              <Plus className="w-4 h-4" />Nueva plantilla
            </button>
          )}
        </div>

        {/* Selector de artículo para previsualización */}
        <div className="card p-4 mb-4 flex items-center gap-4 flex-wrap">
          <span className="text-sm font-medium text-surface-700 shrink-0">Previsualizar con:</span>
          <select className={cn(ic, "flex-1 min-w-48")}
            value={articuloSel?.id || ""}
            onChange={(e) => setArticuloSel(articulos.find((a) => a.id === e.target.value) || null)}>
            {articulos.map((a) => (
              <option key={a.id} value={a.id}>{a.nombre} — {a.codigo_articulo}</option>
            ))}
          </select>
        </div>

        {/* Lista de plantillas */}
        {loading ? (
          <div className="flex justify-center py-12"><Loader2 className="w-6 h-6 text-brand-500 animate-spin" /></div>
        ) : plantillas.length === 0 ? (
          <div className="card text-center py-12 text-sm text-surface-400">
            <Tag className="w-8 h-8 mx-auto mb-2 opacity-30" />
            Sin plantillas. Crea una nueva para empezar.
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {plantillas.map((p) => (
              <div key={p.id} className="card p-4 flex flex-col gap-3">
                {/* Cabecera */}
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <p className="font-semibold text-surface-900 text-sm">{p.nombre}</p>
                    {p.descripcion && <p className="text-xs text-surface-500 mt-0.5">{p.descripcion}</p>}
                  </div>
                  {isAdmin && (
                    <div className="flex items-center gap-1 shrink-0">
                      <button onClick={() => openEdit(p)} title="Editar"
                        className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100"><Pencil className="w-3.5 h-3.5" /></button>
                      <button onClick={() => openDuplicate(p)} title="Duplicar"
                        className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100"><Copy className="w-3.5 h-3.5" /></button>
                      <button onClick={() => handleDelete(p)} title="Eliminar"
                        className="p-1.5 rounded-lg text-surface-400 hover:bg-red-50 hover:text-red-500"><Trash2 className="w-3.5 h-3.5" /></button>
                    </div>
                  )}
                </div>

                {/* Info tamaño */}
                <div className="text-[11px] text-surface-500 flex flex-wrap gap-2">
                  <span>{p.etiq_ancho_mm}×{p.etiq_alto_mm}mm</span>
                  <span>·</span>
                  <span>{p.etiq_cols}×{p.etiq_filas} = {p.etiq_cols * p.etiq_filas} etiq./hoja</span>
                  <span>·</span>
                  <span>QR {p.qr_size_pct}%</span>
                </div>

                {/* Previsualización */}
                <div className="flex justify-center py-2 bg-surface-50 rounded-lg overflow-hidden">
                  <div style={{ transform: "scale(0.9)", transformOrigin: "center" }}>
                    <EtiquetaPreview
                      plantilla={{ ...emptyPlantilla, ...p }}
                      articulo={articuloSel}
                      qrDataUrl={qrDataUrl}
                    />
                  </div>
                </div>

                {/* Campos incluidos */}
                <div className="flex flex-wrap gap-1">
                  {(p.campos || []).map((c: string) => {
                    const def = CAMPOS_DISPONIBLES.find((d) => d.id === c);
                    return <span key={c} className="badge text-[9px] bg-brand-50 text-brand-600">{def?.label || c}</span>;
                  })}
                </div>

                {/* Botón imprimir */}
                <button onClick={() => handlePrint(p)}
                  className="flex items-center justify-center gap-2 w-full py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
                  <Printer className="w-4 h-4" />Imprimir etiquetas
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* ============================================================
          MODAL EDITOR DE PLANTILLA
      ============================================================ */}
      <Modal open={editorOpen} onClose={() => setEditorOpen(false)}
        title={editId ? "Editar plantilla" : "Nueva plantilla"} size="lg">
        <form onSubmit={handleSave} className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2">
              <label className="block text-xs font-medium text-surface-600 mb-1">Nombre de la plantilla *</label>
              <input required className={ic} value={form.nombre}
                onChange={(e) => setForm({ ...form, nombre: e.target.value })} />
            </div>
            <div className="col-span-2">
              <label className="block text-xs font-medium text-surface-600 mb-1">Descripción</label>
              <input className={ic} value={form.descripcion}
                onChange={(e) => setForm({ ...form, descripcion: e.target.value })} />
            </div>
          </div>

          {/* Tamaño preset */}
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-2">Tamaño de etiqueta</label>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
              {TAMANIOS_PRESET.map((preset, idx) => (
                <button key={idx} type="button" onClick={() => applyPreset(idx)}
                  className={cn("flex items-center gap-2 px-3 py-2 rounded-lg border text-xs text-left transition-colors",
                    presetIdx === idx ? "border-brand-500 bg-brand-50 text-brand-700" : "border-surface-200 text-surface-600 hover:bg-surface-50")}>
                  {presetIdx === idx && <Check className="w-3.5 h-3.5 shrink-0" />}
                  {preset.label}
                </button>
              ))}
            </div>
          </div>

          {/* Dimensiones manuales */}
          <div className="grid grid-cols-4 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Ancho etiq. (mm)</label>
              <input type="number" step="0.1" className={ic} value={form.etiq_ancho_mm}
                onChange={(e) => { setPresetIdx(4); setForm({ ...form, etiq_ancho_mm: parseFloat(e.target.value) || 0 }); }} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Alto etiq. (mm)</label>
              <input type="number" step="0.1" className={ic} value={form.etiq_alto_mm}
                onChange={(e) => { setPresetIdx(4); setForm({ ...form, etiq_alto_mm: parseFloat(e.target.value) || 0 }); }} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Columnas</label>
              <input type="number" min="1" max="10" className={ic} value={form.etiq_cols}
                onChange={(e) => { setPresetIdx(4); setForm({ ...form, etiq_cols: parseInt(e.target.value) || 1 }); }} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Filas</label>
              <input type="number" min="1" max="20" className={ic} value={form.etiq_filas}
                onChange={(e) => { setPresetIdx(4); setForm({ ...form, etiq_filas: parseInt(e.target.value) || 1 }); }} /></div>
          </div>

          {/* Márgenes y espaciados */}
          <div className="grid grid-cols-4 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Margen H (mm)</label>
              <input type="number" step="0.1" className={ic} value={form.margen_h_mm}
                onChange={(e) => setForm({ ...form, margen_h_mm: parseFloat(e.target.value) || 0 })} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Margen V (mm)</label>
              <input type="number" step="0.1" className={ic} value={form.margen_v_mm}
                onChange={(e) => setForm({ ...form, margen_v_mm: parseFloat(e.target.value) || 0 })} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Espacio H (mm)</label>
              <input type="number" step="0.1" className={ic} value={form.espacio_h_mm}
                onChange={(e) => setForm({ ...form, espacio_h_mm: parseFloat(e.target.value) || 0 })} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Espacio V (mm)</label>
              <input type="number" step="0.1" className={ic} value={form.espacio_v_mm}
                onChange={(e) => setForm({ ...form, espacio_v_mm: parseFloat(e.target.value) || 0 })} /></div>
          </div>

          {/* Campos a incluir */}
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-2">Campos a mostrar</label>
            <div className="grid grid-cols-2 gap-1.5">
              {CAMPOS_DISPONIBLES.map((campo) => (
                <label key={campo.id}
                  className={cn("flex items-center gap-2 px-3 py-2 rounded-lg border cursor-pointer text-xs transition-colors",
                    form.campos.includes(campo.id) ? "border-brand-500 bg-brand-50 text-brand-700" : "border-surface-200 text-surface-600 hover:bg-surface-50")}>
                  <input type="checkbox" className="hidden" checked={form.campos.includes(campo.id)}
                    onChange={() => toggleCampo(campo.id)} />
                  {form.campos.includes(campo.id) && <Check className="w-3.5 h-3.5 shrink-0" />}
                  {campo.label}
                </label>
              ))}
            </div>
          </div>

          {/* Opciones visuales */}
          <div className="grid grid-cols-3 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Tamaño QR (%)</label>
              <input type="number" min="20" max="80" className={ic} value={form.qr_size_pct}
                onChange={(e) => setForm({ ...form, qr_size_pct: parseInt(e.target.value) || 40 })} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Tamaño texto (px)</label>
              <input type="number" min="5" max="14" className={ic} value={form.font_size}
                onChange={(e) => setForm({ ...form, font_size: parseInt(e.target.value) || 8 })} /></div>
            <div className="flex items-end pb-1">
              <label className="flex items-center gap-2 cursor-pointer text-xs text-surface-700">
                <input type="checkbox" className="w-4 h-4" checked={form.mostrar_borde}
                  onChange={(e) => setForm({ ...form, mostrar_borde: e.target.checked })} />
                Mostrar borde
              </label>
            </div>
          </div>

          {/* Previsualización en tiempo real */}
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-2">Previsualización</label>
            <div className="flex justify-center py-4 bg-surface-50 rounded-lg">
              <EtiquetaPreview plantilla={form} articulo={articuloSel} qrDataUrl={qrDataUrl} />
            </div>
          </div>

          {error && <p className="text-xs text-red-600">{error}</p>}
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setEditorOpen(false)}
              className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {saving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}Guardar plantilla
            </button>
          </div>
        </form>
      </Modal>

      {/* ============================================================
          MODAL DE IMPRESIÓN
      ============================================================ */}
      <Modal open={printOpen} onClose={() => setPrintOpen(false)} title="Imprimir etiquetas" size="md">
        {printPlantilla && articuloSel && (
          <div className="space-y-4">
            <div>
              <label className="block text-xs font-medium text-surface-600 mb-1">Artículo</label>
              <select className={ic} value={articuloSel.id}
                onChange={(e) => setArticuloSel(articulos.find((a) => a.id === e.target.value))}>
                {articulos.map((a) => <option key={a.id} value={a.id}>{a.nombre} — {a.codigo_articulo}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-600 mb-1">
                Cantidad de etiquetas (máx. {printPlantilla.etiq_cols * printPlantilla.etiq_filas}/hoja)
              </label>
              <input type="number" min="1" max={printPlantilla.etiq_cols * printPlantilla.etiq_filas}
                className={ic} value={printCantidad}
                onChange={(e) => setPrintCantidad(Math.min(parseInt(e.target.value) || 1, printPlantilla.etiq_cols * printPlantilla.etiq_filas))} />
            </div>
            <div className="flex justify-center py-4 bg-surface-50 rounded-lg">
              <EtiquetaPreview plantilla={{ ...emptyPlantilla, ...printPlantilla }} articulo={articuloSel} qrDataUrl={qrDataUrl} />
            </div>
            <div className="flex justify-end gap-2">
              <button onClick={() => setPrintOpen(false)}
                className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
              <button onClick={doPrint}
                className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
                <Printer className="w-4 h-4" />Abrir para imprimir
              </button>
            </div>
          </div>
        )}
      </Modal>
    </AppLayout>
  );
}
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\almacen\etiquetas\page.tsx" -ForegroundColor Green

$dst = "src\components\layout\Sidebar.tsx"
$content = @'
"use client";

import { usePathname } from "next/navigation";
import Link from "next/link";
import Image from "next/image";
import {
  LayoutDashboard, CalendarRange, Building2, ClipboardList,
  Users, Truck, Package, Contact, Settings,
  ScrollText, ChevronLeft, ChevronRight,
  Tag, Hammer, X, LayoutGrid, Radar, Warehouse, Users2, ArrowLeftRight,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { useAuthStore } from "@/hooks/useAuth";
import { useLayoutStore } from "@/hooks/useLayout";
import { usePermissions } from "@/hooks/usePermissions";

const navigation = [
  { name: "Dashboard", href: "/dashboard", icon: LayoutDashboard, screen: "dashboard" },
  { name: "Planificación", href: "/planificacion", icon: CalendarRange, screen: "planificacion" },
  { name: "Obras", href: "/obras", icon: Building2, screen: "obras" },
  { name: "Partes Diarios", href: "/partes", icon: ClipboardList, screen: "partes" },
];

// Catálogo de apps internas del módulo "Aplicaciones". Añadir una app
// nueva en el futuro es tan simple como añadir una entrada aquí (con su
// propio `screen` dado de alta en rol_permisos) -- no requiere tocar
// ninguna otra parte del Sidebar ni del sistema de permisos.
const aplicaciones = [
  { name: "Interpretación de Georradar", href: "/aplicaciones/georadar", icon: Radar, screen: "apps_georadar" },
];

const almacen = [
  { name: "Artículos", href: "/almacen/articulos", icon: Package, screen: "almacen_articulos" },
  { name: "Tipos de artículo", href: "/almacen/tipos-articulo", icon: Tag, screen: "almacen_tipos_articulo" },
  { name: "Almacenes", href: "/almacen/almacenes", icon: Warehouse, screen: "almacen_almacenes" },
  { name: "Proveedores", href: "/almacen/proveedores", icon: Users2, screen: "almacen_proveedores" },
  { name: "Movimientos", href: "/almacen/movimientos", icon: ArrowLeftRight, screen: "almacen_movimientos" },
  { name: "Etiquetas", href: "/almacen/etiquetas", icon: Tag, screen: "almacen_etiquetas" },
];

const maestros = [
  { name: "Recursos Humanos", href: "/maestros/recursos-humanos", icon: Users, screen: "maestros_rrhh" },
  { name: "Vehículos", href: "/maestros/vehiculos", icon: Truck, screen: "maestros_vehiculos" },
  { name: "Clientes", href: "/maestros/clientes", icon: Contact, screen: "maestros_clientes" },
  { name: "Estados de Obra", href: "/maestros/estados-obra", icon: Tag, screen: "maestros_estados" },
  { name: "Tipos de Trabajo", href: "/maestros/tipos-trabajo", icon: Hammer, screen: "maestros_tipos_trabajo" },
  { name: "Tipos de Obra", href: "/maestros/tipos-obra", icon: Building2, screen: "maestros_tipos_obra" },
];

const admin = [
  { name: "Logs", href: "/logs", icon: ScrollText, screen: "logs" },
  { name: "Configuración", href: "/configuracion", icon: Settings, screen: "configuracion" },
];

export default function Sidebar() {
  const pathname = usePathname();
  const { user } = useAuthStore();
  const { sidebarCollapsed: collapsed, toggleSidebar, mobileMenuOpen, setMobileMenu } = useLayoutStore();
  const { isAdmin, visibleScreens } = usePermissions();
  const screens = visibleScreens();

  const isActive = (href: string) => {
    if (href === "/dashboard") return pathname === "/dashboard";
    return pathname.startsWith(href);
  };

  const NavItem = ({ item }: { item: (typeof navigation)[0] }) => (
    <Link href={item.href} onClick={() => setMobileMenu(false)}
      className={cn("nav-link group", isActive(item.href) && "active")} title={collapsed ? item.name : undefined}>
      <item.icon className={cn("w-5 h-5 shrink-0 transition-colors", isActive(item.href) ? "text-brand-600" : "text-surface-400 group-hover:text-surface-600")} />
      {(!collapsed || mobileMenuOpen) && <span className="truncate">{item.name}</span>}
    </Link>
  );

  // Filter items by permission
  const visibleNav = navigation.filter((item) => screens.has(item.screen));
  const visibleApps = aplicaciones.filter((item) => screens.has(item.screen));
  const visibleAlmacen = almacen.filter((item) => screens.has(item.screen));
  const visibleMaestros = maestros.filter((item) => screens.has(item.screen));
  const visibleAdmin = admin.filter((item) => screens.has(item.screen));

  const sidebarContent = (
    <>
      {/* Logo only */}
      <div className="flex items-center justify-between px-4 h-16 border-b border-surface-200 shrink-0">
        <Link href="/dashboard" className="flex items-center justify-center w-full">
          <div className={cn("relative shrink-0", collapsed && !mobileMenuOpen ? "w-10 h-10" : "w-36 h-12")}>
            <Image src="/logo-loynek.png" alt="Loynek" fill className="object-contain" />
          </div>
        </Link>
        {mobileMenuOpen && (
          <button onClick={() => setMobileMenu(false)} className="p-1 rounded-lg text-surface-400 hover:bg-surface-100 lg:hidden absolute right-3">
            <X className="w-5 h-5" />
          </button>
        )}
      </div>

      {/* Navigation */}
      <nav className="flex-1 overflow-y-auto px-3 py-4 space-y-6">
        {visibleNav.length > 0 && (
          <div className="space-y-1">
            {(!collapsed || mobileMenuOpen) && <p className="px-3 mb-2 text-[11px] font-semibold text-surface-400 uppercase tracking-wider">Principal</p>}
            {visibleNav.map((item) => <NavItem key={item.href} item={item} />)}
          </div>
        )}
        {visibleApps.length > 0 && (
          <div className="space-y-1">
            {(!collapsed || mobileMenuOpen) && <p className="px-3 mb-2 text-[11px] font-semibold text-surface-400 uppercase tracking-wider">Aplicaciones</p>}
            {visibleApps.map((item) => <NavItem key={item.href} item={item} />)}
          </div>
        )}
        {visibleAlmacen.length > 0 && (
          <div className="space-y-1">
            {(!collapsed || mobileMenuOpen) && <p className="px-3 mb-2 text-[11px] font-semibold text-surface-400 uppercase tracking-wider">Almacén</p>}
            {visibleAlmacen.map((item) => <NavItem key={item.href} item={item} />)}
          </div>
        )}
        {visibleMaestros.length > 0 && (
          <div className="space-y-1">
            {(!collapsed || mobileMenuOpen) && <p className="px-3 mb-2 text-[11px] font-semibold text-surface-400 uppercase tracking-wider">Maestros</p>}
            {visibleMaestros.map((item) => <NavItem key={item.href} item={item} />)}
          </div>
        )}
        {visibleAdmin.length > 0 && (
          <div className="space-y-1">
            {(!collapsed || mobileMenuOpen) && <p className="px-3 mb-2 text-[11px] font-semibold text-surface-400 uppercase tracking-wider">Administración</p>}
            {visibleAdmin.map((item) => <NavItem key={item.href} item={item} />)}
          </div>
        )}
      </nav>

      {/* Collapse button - desktop only */}
      <div className="hidden lg:block px-3 py-3 border-t border-surface-200 shrink-0">
        <button onClick={() => toggleSidebar()}
          className="w-full flex items-center justify-center gap-2 px-3 py-2 rounded-lg text-sm text-surface-400 hover:bg-surface-100 hover:text-surface-600 transition-colors">
          {collapsed ? <ChevronRight className="w-4 h-4" /> : <><ChevronLeft className="w-4 h-4" /><span>Colapsar</span></>}
        </button>
      </div>
    </>
  );

  return (
    <>
      <aside className={cn(
        "hidden lg:flex fixed left-0 top-0 z-40 h-screen bg-white border-r border-surface-200 flex-col transition-all duration-300",
        collapsed ? "w-[72px]" : "w-[260px]"
      )}>
        {sidebarContent}
      </aside>

      {mobileMenuOpen && (
        <div className="lg:hidden fixed inset-0 z-50">
          <div className="absolute inset-0 bg-black/50" onClick={() => setMobileMenu(false)} />
          <aside className="absolute left-0 top-0 h-full w-[280px] bg-white flex flex-col shadow-xl animate-slide-in">
            {sidebarContent}
          </aside>
        </div>
      )}
    </>
  );
}
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\components\layout\Sidebar.tsx" -ForegroundColor Green

$dst = "src\hooks\usePermissions.ts"
$content = @'
"use client";

import { useState, useEffect, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";

interface Permisos {
  pantalla: string;
  visible: boolean;
  crear: boolean;
  editar: boolean;
  eliminar: boolean;
  asignar: boolean;
}

// Default permissions per screen for non-configured roles
const DEFAULT_OPERARIO: Record<string, Partial<Permisos>> = {
  dashboard: { visible: true },
  partes: { visible: true, crear: true, editar: true },
  obras: { visible: true },
  planificacion: { visible: true },
};

export function usePermissions() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const [permisos, setPermisos] = useState<Permisos[]>([]);
  const [isAdminFromRole, setIsAdminFromRole] = useState(false);
  const [loaded, setLoaded] = useState(false);

  // Admin si el campo role = "admin" O si el rol vinculado tiene is_admin = true
  const isAdmin = user?.role === "admin" || isAdminFromRole;

  useEffect(() => {
    if (!user?.id) return;

    const fetchPermisos = async () => {
      // Leer rol_id y role actualizados desde la BD (no solo desde el store cacheado)
      const { data: userData } = await supabase
        .from("users")
        .select("rol_id, role")
        .eq("id", user.id)
        .single();

      if (!userData) { setLoaded(true); return; }

      // Comprobar si el rol vinculado es admin aunque users.role no diga "admin"
      if (userData.rol_id) {
        const { data: rolData } = await supabase
          .from("roles")
          .select("is_admin")
          .eq("id", userData.rol_id)
          .single();
        if (rolData?.is_admin) {
          setIsAdminFromRole(true);
          setLoaded(true);
          return;
        }
        // Si no es admin, cargar permisos granulares
        const { data } = await supabase
          .from("rol_permisos")
          .select("*")
          .eq("rol_id", userData.rol_id);
        setPermisos(data || []);
      }

      // Fallback: users.role = "admin" ya lo cubre isAdmin arriba
      setLoaded(true);
    };

    fetchPermisos();
  }, [user?.id]);

  const canAccess = useCallback((pantalla: string): boolean => {
    if (isAdmin) return true;
    const perm = permisos.find((p) => p.pantalla === pantalla);
    if (perm) return perm.visible;
    // Fallback to defaults for operario
    return DEFAULT_OPERARIO[pantalla]?.visible || false;
  }, [isAdmin, permisos]);

  const canDo = useCallback((pantalla: string, action: "crear" | "editar" | "eliminar" | "asignar"): boolean => {
    if (isAdmin) return true;
    const perm = permisos.find((p) => p.pantalla === pantalla);
    if (perm) return !!(perm as any)[action];
    return !!(DEFAULT_OPERARIO[pantalla] as any)?.[action] || false;
  }, [isAdmin, permisos]);

  // Screens that should appear in the sidebar
  const visibleScreens = useCallback((): Set<string> => {
    if (isAdmin) return new Set(["dashboard", "planificacion", "obras", "partes",
      "apps_georadar",
      "almacen_articulos", "almacen_tipos_articulo", "almacen_almacenes", "almacen_proveedores", "almacen_movimientos", "almacen_etiquetas",
      "maestros_rrhh", "maestros_vehiculos",
      "maestros_clientes", "maestros_estados", "maestros_tipos_trabajo", "maestros_tipos_obra",
      "logs", "configuracion"]);

    const screens = new Set<string>();
    // From DB permissions
    permisos.forEach((p) => { if (p.visible) screens.add(p.pantalla); });
    // Always add defaults
    Object.entries(DEFAULT_OPERARIO).forEach(([k, v]) => { if (v.visible) screens.add(k); });
    return screens;
  }, [isAdmin, permisos]);

  return { isAdmin, canAccess, canDo, visibleScreens, loaded };
}
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\hooks\usePermissions.ts" -ForegroundColor Green

$dst = "src\hooks\useRouteGuard.ts"
$content = @'
"use client";

import { useEffect } from "react";
import { useRouter, usePathname } from "next/navigation";
import { usePermissions } from "@/hooks/usePermissions";
import { useAuthStore } from "@/hooks/useAuth";

// Map URL paths to screen names
const PATH_TO_SCREEN: Record<string, string> = {
  "/dashboard": "dashboard",
  "/planificacion": "planificacion",
  "/obras": "obras",
  "/partes": "partes",
  "/aplicaciones/georadar": "apps_georadar",
  "/maestros/recursos-humanos": "maestros_rrhh",
  "/almacen/articulos": "almacen_articulos",
  "/almacen/tipos-articulo": "almacen_tipos_articulo",
  "/almacen/almacenes": "almacen_almacenes",
  "/almacen/proveedores": "almacen_proveedores",
  "/almacen/movimientos": "almacen_movimientos",
  "/almacen/etiquetas": "almacen_etiquetas",
  "/maestros/vehiculos": "maestros_vehiculos",
  "/maestros/clientes": "maestros_clientes",
  "/maestros/estados-obra": "maestros_estados",
  "/maestros/tipos-trabajo": "maestros_tipos_trabajo",
  "/maestros/tipos-obra": "maestros_tipos_obra",
  "/logs": "logs",
  "/configuracion": "configuracion",
};

export function useRouteGuard() {
  const router = useRouter();
  const pathname = usePathname();
  const { user } = useAuthStore();
  const { canAccess, loaded } = usePermissions();

  useEffect(() => {
    if (!loaded || !user) return;

    // Find matching screen for current path
    const screen = Object.entries(PATH_TO_SCREEN).find(([path]) => pathname.startsWith(path))?.[1];
    if (!screen) return; // Unknown path, allow

    if (!canAccess(screen)) {
      router.replace("/dashboard");
    }
  }, [pathname, loaded, user, canAccess, router]);
}
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\hooks\useRouteGuard.ts" -ForegroundColor Green

$dst = "src\app\configuracion\page.tsx"
$content = @'
"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { Settings, Loader2, Save, ShieldCheck, Check, X, Plus, Pencil, Trash2, Mail } from "lucide-react";
import { cn } from "@/lib/utils/cn";

type ConfigTab = "roles" | "partes" | "almacen" | "general";

const PANTALLAS = [
  { id: "dashboard", label: "Dashboard" },
  { id: "planificacion", label: "Planificación" },
  { id: "obras", label: "Obras" },
  { id: "partes", label: "Partes" },
  { id: "almacen_articulos", label: "Almacén - Artículos" },
  { id: "almacen_tipos_articulo", label: "Almacén - Tipos de artículo" },
  { id: "almacen_almacenes", label: "Almacén - Almacenes" },
  { id: "almacen_proveedores", label: "Almacén - Proveedores" },
  { id: "almacen_movimientos", label: "Almacén - Movimientos" },
  { id: "almacen_etiquetas", label: "Almacén - Diseñador de etiquetas" },
  { id: "maestros_rrhh", label: "RRHH" },
  { id: "maestros_vehiculos", label: "Vehículos" },
  { id: "maestros_clientes", label: "Clientes" },
  { id: "maestros_estados", label: "Estados obra" },
  { id: "maestros_tipos_trabajo", label: "Tipos trabajo" },
  { id: "maestros_tipos_obra", label: "Tipos de obra" },
  { id: "apps_georadar", label: "Georadar" },
  { id: "logs", label: "Logs" },
  { id: "configuracion", label: "Configuración" },
];

const PERMISOS = ["visible", "crear", "editar", "eliminar", "asignar"] as const;
const PERMISO_LABELS: Record<string, string> = { visible: "Ver", crear: "Crear", editar: "Editar", eliminar: "Eliminar", asignar: "Asignar" };

interface RolData {
  id: string;
  nombre: string;
  descripcion: string;
  is_admin: boolean;
  permisos: Record<string, Record<string, boolean>>;
}

export default function ConfiguracionPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const [tab, setTab] = useState<ConfigTab>("roles");
  const [roles, setRoles] = useState<RolData[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedRol, setSelectedRol] = useState<string>("");
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  // Create/edit modal
  const [rolModal, setRolModal] = useState(false);
  const [rolForm, setRolForm] = useState({ nombre: "", descripcion: "", is_admin: false });
  const [editingRolId, setEditingRolId] = useState<string | null>(null);
  const [rolSaving, setRolSaving] = useState(false);
  // Partes config
  const [partesConfig, setPartesConfig] = useState({ cc_emails: [] as string[], empresa_nombre: "LOYNEK Soluciones Técnicas", footer_text: "Este email ha sido enviado automáticamente desde ObrasPlan", color_primario: "#DC2626" });
  const [newCcEmail, setNewCcEmail] = useState("");
  const [partesSaving, setPartesSaving] = useState(false);
  const [partesSaved, setPartesSaved] = useState(false);
  const [almacenConfig, setAlmacenConfig] = useState({ emails: [] as string[], activo: true, asunto: "Alertas de almacen - ObrasPlan", dias_aviso_caducidad: 30 });
  const [newAlmacenEmail, setNewAlmacenEmail] = useState("");
  const [almacenSaving, setAlmacenSaving] = useState(false);
  const [almacenSaved, setAlmacenSaved] = useState(false);
  const [almacenTestSending, setAlmacenTestSending] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [rolesR, permR] = await Promise.all([
      supabase.from("roles").select("*").order("is_admin", { ascending: false }).order("nombre"),
      supabase.from("rol_permisos").select("*"),
    ]);
    const rolesData = (rolesR.data || []) as any[];
    const permsData = (permR.data || []) as any[];

    const result: RolData[] = rolesData.map((r: any) => {
      const permisos: Record<string, Record<string, boolean>> = {};
      PANTALLAS.forEach((p) => {
        const existing = permsData.find((perm: any) => perm.rol_id === r.id && perm.pantalla === p.id);
        permisos[p.id] = {
          visible: existing?.visible ?? r.is_admin,
          crear: existing?.crear ?? r.is_admin,
          editar: existing?.editar ?? r.is_admin,
          eliminar: existing?.eliminar ?? r.is_admin,
          asignar: existing?.asignar ?? r.is_admin,
        };
      });
      return { id: r.id, nombre: r.nombre, descripcion: r.descripcion || "", is_admin: r.is_admin, permisos };
    });

    setRoles(result);
    if (result.length > 0 && !selectedRol) setSelectedRol(result[0].id);
    // Fetch partes config
    const { data: settingsData } = await supabase.from("app_settings").select("*").eq("key", "partes_email").single();
    const { data: almacenSettingsData } = await (supabase.from("app_settings") as any).select("*").eq("key", "almacen_alertas").single();
    if (almacenSettingsData?.value) setAlmacenConfig((prev) => ({ ...prev, ...almacenSettingsData.value }));
    if (settingsData?.value) setPartesConfig({ ...partesConfig, ...settingsData.value });
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const togglePerm = (rolId: string, pantalla: string, permiso: string) => {
    setRoles((prev) => prev.map((r) => {
      if (r.id !== rolId || r.is_admin) return r;
      return { ...r, permisos: { ...r.permisos, [pantalla]: { ...r.permisos[pantalla], [permiso]: !r.permisos[pantalla][permiso] } } };
    }));
    setSaved(false);
  };

  const toggleAll = (rolId: string, value: boolean) => {
    setRoles((prev) => prev.map((r) => {
      if (r.id !== rolId || r.is_admin) return r;
      const permisos: Record<string, Record<string, boolean>> = {};
      PANTALLAS.forEach((p) => { permisos[p.id] = {}; PERMISOS.forEach((perm) => { permisos[p.id][perm] = value; }); });
      return { ...r, permisos };
    }));
    setSaved(false);
  };

  const handleSavePermisos = async () => {
    setSaving(true);
    const rol = roles.find((r) => r.id === selectedRol);
    if (!rol || rol.is_admin) { setSaving(false); return; }

    for (const pantalla of PANTALLAS) {
      const perms = rol.permisos[pantalla.id];
      await (supabase.from("rol_permisos") as any).upsert({
        rol_id: rol.id, pantalla: pantalla.id,
        visible: perms.visible ?? false, crear: perms.crear ?? false,
        editar: perms.editar ?? false, eliminar: perms.eliminar ?? false,
        asignar: perms.asignar ?? false,
      }, { onConflict: "rol_id,pantalla" });
    }
    setSaving(false); setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  const handleCreateRol = async (e: React.FormEvent) => {
    e.preventDefault(); setRolSaving(true);
    if (editingRolId) {
      await (supabase.from("roles") as any).update({ nombre: rolForm.nombre, descripcion: rolForm.descripcion }).eq("id", editingRolId);
    } else {
      await (supabase.from("roles") as any).insert({ nombre: rolForm.nombre, descripcion: rolForm.descripcion, is_admin: false });
    }
    setRolSaving(false); setRolModal(false); fetchData();
  };

  const handleDeleteRol = async (rolId: string) => {
    const rol = roles.find((r) => r.id === rolId);
    if (rol?.is_admin) return;
    if (!confirm(`¿Eliminar el rol "${rol?.nombre}"? Los usuarios con este rol quedarán sin rol asignado.`)) return;
    await (supabase.from("roles") as any).delete().eq("id", rolId);
    if (selectedRol === rolId) setSelectedRol("");
    fetchData();
  };

  if (user && user.role !== "admin") {
    return <AppLayout><div className="text-center py-20"><ShieldCheck className="w-10 h-10 text-surface-300 mx-auto mb-3" /><p className="text-sm text-surface-500">Solo administradores</p></div></AppLayout>;
  }

  const selectedRolData = roles.find((r) => r.id === selectedRol);
  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  return (
    <AppLayout>
      <div className="max-w-6xl mx-auto animate-fade-in">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-lg bg-surface-100 flex items-center justify-center"><Settings className="w-5 h-5 text-surface-600" /></div>
          <div><h1 className="text-xl font-display font-bold text-surface-900">Configuración</h1><p className="text-sm text-surface-500">Roles, permisos y ajustes</p></div>
        </div>

        {/* Tabs */}
        <div className="flex gap-1 mb-6 border-b border-surface-200">
          {[{ id: "roles" as ConfigTab, label: "Roles y permisos" }, { id: "partes" as ConfigTab, label: "Partes / Email" }, { id: "almacen" as ConfigTab, label: "Almacén" }, { id: "general" as ConfigTab, label: "General" }].map((t) => (
            <button key={t.id} onClick={() => setTab(t.id)}
              className={cn("px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-all",
                tab === t.id ? "border-brand-500 text-brand-600" : "border-transparent text-surface-500")}>
              {t.label}
            </button>
          ))}
        </div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div> : (
          <>
            {/* ROLES TAB */}
            {tab === "roles" && (
              <div className="space-y-4">
                {/* Rol selector + actions */}
                <div className="card p-4">
                  <div className="flex items-center justify-between flex-wrap gap-3">
                    <div className="flex items-center gap-3">
                      <label className="text-sm font-medium text-surface-700">Rol:</label>
                      <select value={selectedRol} onChange={(e) => { setSelectedRol(e.target.value); setSaved(false); }}
                        className="px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20 min-w-[200px]">
                        {roles.map((r) => <option key={r.id} value={r.id}>{r.nombre}{r.is_admin ? " (Admin)" : ""}</option>)}
                      </select>
                      {selectedRolData && !selectedRolData.is_admin && (
                        <>
                          <button onClick={() => { setRolForm({ nombre: selectedRolData.nombre, descripcion: selectedRolData.descripcion, is_admin: false }); setEditingRolId(selectedRolData.id); setRolModal(true); }}
                            className="p-2 rounded-lg text-surface-400 hover:bg-surface-100 hover:text-surface-600"><Pencil className="w-4 h-4" /></button>
                          <button onClick={() => handleDeleteRol(selectedRolData.id)}
                            className="p-2 rounded-lg text-surface-400 hover:bg-red-50 hover:text-red-500"><Trash2 className="w-4 h-4" /></button>
                        </>
                      )}
                    </div>
                    <div className="flex items-center gap-2">
                      <button onClick={() => { setRolForm({ nombre: "", descripcion: "", is_admin: false }); setEditingRolId(null); setRolModal(true); }}
                        className="flex items-center gap-1.5 px-3 py-2 text-sm font-medium text-brand-600 bg-brand-50 rounded-lg hover:bg-brand-100">
                        <Plus className="w-4 h-4" /> Nuevo rol
                      </button>
                      {selectedRolData && !selectedRolData.is_admin && (
                        <>
                          <button onClick={() => toggleAll(selectedRol, true)} className="px-3 py-1.5 text-xs font-medium text-emerald-700 bg-emerald-50 rounded-lg hover:bg-emerald-100">Todo</button>
                          <button onClick={() => toggleAll(selectedRol, false)} className="px-3 py-1.5 text-xs font-medium text-red-700 bg-red-50 rounded-lg hover:bg-red-100">Nada</button>
                          <button onClick={handleSavePermisos} disabled={saving}
                            className={cn("flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg",
                              saved ? "text-emerald-700 bg-emerald-100" : "text-white bg-brand-500 hover:bg-brand-600 disabled:opacity-60")}>
                            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : saved ? <Check className="w-4 h-4" /> : <Save className="w-4 h-4" />}
                            {saved ? "Guardado" : "Guardar"}
                          </button>
                        </>
                      )}
                    </div>
                  </div>
                  {selectedRolData?.descripcion && <p className="text-xs text-surface-400 mt-2">{selectedRolData.descripcion}</p>}
                </div>

                {/* Permissions table */}
                {selectedRolData && (
                  <div className="card overflow-hidden">
                    {selectedRolData.is_admin ? (
                      <div className="p-8 text-center"><ShieldCheck className="w-8 h-8 text-emerald-500 mx-auto mb-2" /><p className="text-sm text-surface-600">El rol Administrador tiene acceso total. No se puede modificar.</p></div>
                    ) : (
                      <table className="w-full text-sm">
                        <thead>
                          <tr className="bg-surface-50 border-b border-surface-200">
                            <th className="text-left py-3 px-4 text-[10px] font-semibold text-surface-400 uppercase w-[180px]">Menú / Pantalla</th>
                            {PERMISOS.map((p) => (
                              <th key={p} className="text-center py-3 px-3 text-[10px] font-semibold text-surface-400 uppercase">{PERMISO_LABELS[p]}</th>
                            ))}
                          </tr>
                        </thead>
                        <tbody>
                          {PANTALLAS.map((pantalla) => (
                            <tr key={pantalla.id} className="border-b border-surface-50 hover:bg-surface-50/50">
                              <td className="py-3 px-4 font-medium text-surface-900">{pantalla.label}</td>
                              {PERMISOS.map((perm) => {
                                const checked = selectedRolData.permisos[pantalla.id]?.[perm] ?? false;
                                return (
                                  <td key={perm} className="text-center py-3 px-3">
                                    <button onClick={() => togglePerm(selectedRolData.id, pantalla.id, perm)}
                                      className={cn("w-8 h-8 rounded-lg flex items-center justify-center mx-auto transition-all",
                                        checked ? "bg-emerald-100 text-emerald-600 hover:bg-emerald-200" : "bg-red-50 text-red-400 hover:bg-red-100")}>
                                      {checked ? <Check className="w-4 h-4" /> : <X className="w-4 h-4" />}
                                    </button>
                                  </td>
                                );
                              })}
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    )}
                  </div>
                )}
              </div>
            )}

            {/* PARTES TAB */}
            {tab === "partes" && (
              <div className="space-y-6">
                <div className="card p-6 space-y-4">
                  <h2 className="text-sm font-semibold text-surface-900">Emails en copia (CC)</h2>
                  <p className="text-xs text-surface-400">Estas direcciones recibirán una copia de todos los partes que se envíen por email.</p>
                  <div className="flex flex-wrap gap-2">
                    {partesConfig.cc_emails.map((email, i) => (
                      <span key={i} className="flex items-center gap-1 px-3 py-1.5 bg-blue-50 text-blue-700 rounded-full text-xs font-medium border border-blue-200">
                        {email}
                        <button onClick={() => setPartesConfig({ ...partesConfig, cc_emails: partesConfig.cc_emails.filter((_, j) => j !== i) })} className="ml-1 hover:text-red-500"><X className="w-3 h-3" /></button>
                      </span>
                    ))}
                  </div>
                  <div className="flex gap-2">
                    <input type="email" value={newCcEmail} onChange={(e) => setNewCcEmail(e.target.value)} placeholder="email@ejemplo.com" onKeyDown={(e) => { if (e.key === "Enter" && newCcEmail.includes("@")) { e.preventDefault(); setPartesConfig({ ...partesConfig, cc_emails: [...partesConfig.cc_emails, newCcEmail] }); setNewCcEmail(""); } }}
                      className="flex-1 px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500" />
                    <button onClick={() => { if (newCcEmail.includes("@")) { setPartesConfig({ ...partesConfig, cc_emails: [...partesConfig.cc_emails, newCcEmail] }); setNewCcEmail(""); } }}
                      className="flex items-center gap-1 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-4 h-4" />Añadir</button>
                  </div>
                </div>

                <div className="card p-6 space-y-4">
                  <h2 className="text-sm font-semibold text-surface-900">Diseño del email y PDF</h2>
                  <div className="grid grid-cols-2 gap-4">
                    <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre de empresa</label><input type="text" value={partesConfig.empresa_nombre} onChange={(e) => setPartesConfig({ ...partesConfig, empresa_nombre: e.target.value })} className="w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500" /></div>
                    <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Color primario</label>
                      <div className="flex items-center gap-2">
                        <input type="color" value={partesConfig.color_primario} onChange={(e) => setPartesConfig({ ...partesConfig, color_primario: e.target.value })} className="w-10 h-10 rounded cursor-pointer border border-surface-200" />
                        <input type="text" value={partesConfig.color_primario} onChange={(e) => setPartesConfig({ ...partesConfig, color_primario: e.target.value })} className="flex-1 px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500/20 font-mono" />
                      </div>
                    </div>
                  </div>
                  <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Texto del footer</label><input type="text" value={partesConfig.footer_text} onChange={(e) => setPartesConfig({ ...partesConfig, footer_text: e.target.value })} className="w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500" /></div>
                </div>

                <div className="flex justify-end">
                  <button onClick={async () => {
                    setPartesSaving(true);
                    await (supabase.from("app_settings") as any).upsert({ key: "partes_email", value: partesConfig, updated_at: new Date().toISOString() }, { onConflict: "key" });
                    setPartesSaving(false); setPartesSaved(true); setTimeout(() => setPartesSaved(false), 2000);
                  }} disabled={partesSaving}
                    className={cn("flex items-center gap-1.5 px-5 py-2.5 text-sm font-medium rounded-lg",
                      partesSaved ? "text-emerald-700 bg-emerald-100" : "text-white bg-brand-500 hover:bg-brand-600 disabled:opacity-60")}>
                    {partesSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : partesSaved ? <Check className="w-4 h-4" /> : <Save className="w-4 h-4" />}
                    {partesSaved ? "Guardado" : "Guardar configuración"}
                  </button>
                </div>
              </div>
            )}

            {/* ALMACEN TAB */}
            {tab === "almacen" && (
              <div className="space-y-6">
                <div className="card p-6 space-y-4">
                  <h2 className="text-sm font-semibold text-surface-900">Emails para alertas de almacen</h2>
                  <p className="text-xs text-surface-400">Estas direcciones recibiran alertas de stock bajo y caducidades proximas.</p>
                  <div className="flex flex-wrap gap-2">
                    {almacenConfig.emails.map((email, i) => (
                      <span key={i} className="flex items-center gap-1 px-3 py-1.5 bg-amber-50 text-amber-700 rounded-full text-xs font-medium border border-amber-200">
                        {email}
                        <button onClick={() => setAlmacenConfig({ ...almacenConfig, emails: almacenConfig.emails.filter((_, j) => j !== i) })} className="ml-1 hover:text-red-500"><X className="w-3 h-3" /></button>
                      </span>
                    ))}
                  </div>
                  <div className="flex gap-2">
                    <input type="email" value={newAlmacenEmail} onChange={(e) => setNewAlmacenEmail(e.target.value)}
                      placeholder="email@ejemplo.com"
                      onKeyDown={(e) => { if (e.key === "Enter" && newAlmacenEmail.includes("@")) { e.preventDefault(); setAlmacenConfig({ ...almacenConfig, emails: [...almacenConfig.emails, newAlmacenEmail] }); setNewAlmacenEmail(""); } }}
                      className="flex-1 px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500/20" />
                    <button onClick={() => { if (newAlmacenEmail.includes("@")) { setAlmacenConfig({ ...almacenConfig, emails: [...almacenConfig.emails, newAlmacenEmail] }); setNewAlmacenEmail(""); } }}
                      className="flex items-center gap-1 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-4 h-4" />Añadir</button>
                  </div>
                </div>
                <div className="card p-6 space-y-4">
                  <h2 className="text-sm font-semibold text-surface-900">Configuracion del email</h2>
                  <div className="grid grid-cols-2 gap-4">
                    <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Asunto del email</label>
                      <input type="text" value={almacenConfig.asunto} onChange={(e) => setAlmacenConfig({ ...almacenConfig, asunto: e.target.value })} className={ic} />
                    </div>
                    <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Dias de aviso antes de caducidad</label>
                      <input type="number" min="1" max="365" value={almacenConfig.dias_aviso_caducidad} onChange={(e) => setAlmacenConfig({ ...almacenConfig, dias_aviso_caducidad: parseInt(e.target.value) || 30 })} className={ic} />
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <input type="checkbox" id="alm_activo" checked={almacenConfig.activo} onChange={(e) => setAlmacenConfig({ ...almacenConfig, activo: e.target.checked })} className="w-4 h-4" />
                    <label htmlFor="alm_activo" className="text-sm text-surface-700">Alertas automaticas activas (email diario)</label>
                  </div>
                </div>
                <div className="flex items-center justify-between">
                  <button onClick={async () => {
                    if (!almacenConfig.emails.length) { alert("Añade al menos un email de destino"); return; }
                    setAlmacenTestSending(true);
                    const res = await fetch("/api/almacen/alertas-email", { method: "POST" });
                    const d = await res.json();
                    setAlmacenTestSending(false);
                    alert(d.sent ? `Email enviado. ${d.alertas} alertas a ${d.destinatarios} destinatarios.` : "Sin alertas activas o error: " + (d.reason || d.error));
                  }} disabled={almacenTestSending}
                    className="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200 disabled:opacity-60">
                    {almacenTestSending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Mail className="w-4 h-4" />}
                    Enviar email de prueba ahora
                  </button>
                  <button onClick={async () => {
                    setAlmacenSaving(true);
                    await (supabase.from("app_settings") as any).upsert({ key: "almacen_alertas", value: almacenConfig, updated_at: new Date().toISOString() }, { onConflict: "key" });
                    setAlmacenSaving(false); setAlmacenSaved(true); setTimeout(() => setAlmacenSaved(false), 2000);
                  }} disabled={almacenSaving}
                    className={cn("flex items-center gap-1.5 px-5 py-2.5 text-sm font-medium rounded-lg",
                      almacenSaved ? "text-emerald-700 bg-emerald-100" : "text-white bg-brand-500 hover:bg-brand-600 disabled:opacity-60")}>
                    {almacenSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : almacenSaved ? <Check className="w-4 h-4" /> : <Save className="w-4 h-4" />}
                    {almacenSaved ? "Guardado" : "Guardar configuracion"}
                  </button>
                </div>
              </div>
            )}

            {/* GENERAL TAB */}
            {tab === "general" && (
              <div className="card p-6">
                <h2 className="text-sm font-semibold text-surface-900 mb-4">Ajustes generales</h2>
                <p className="text-sm text-surface-500">Próximamente: configuración de empresa, logo, notificaciones, y más.</p>
              </div>
            )}
          </>
        )}
      </div>

      {/* Create/Edit rol modal */}
      <Modal open={rolModal} onClose={() => setRolModal(false)} title={editingRolId ? "Editar rol" : "Nuevo rol"} size="sm">
        <form onSubmit={handleCreateRol} className="space-y-4">
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre del rol *</label><input type="text" required value={rolForm.nombre} onChange={(e) => setRolForm({ ...rolForm, nombre: e.target.value })} placeholder="Ej: Jefe de obra" className={ic} /></div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Descripción</label><input type="text" value={rolForm.descripcion} onChange={(e) => setRolForm({ ...rolForm, descripcion: e.target.value })} placeholder="Descripción del rol" className={ic} /></div>
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setRolModal(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={rolSaving || !rolForm.nombre} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {rolSaving && <Loader2 className="w-4 h-4 animate-spin" />}{editingRolId ? "Guardar" : "Crear"}
            </button>
          </div>
        </form>
      </Modal>
    </AppLayout>
  );
}
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\configuracion\page.tsx" -ForegroundColor Green

Write-Host ""
Write-Host "==> Verificando" -ForegroundColor Cyan
$ok1 = Test-Path (Join-Path $RepoPath "src\app\almacen\etiquetas\page.tsx")
$ok2 = Select-String -Path "src\app\almacen\articulos\page.tsx" -Pattern "stock_almacenes" -Quiet
$ok3 = Select-String -Path "src\components\layout\Sidebar.tsx" -Pattern "almacen_etiquetas" -Quiet
if ($ok1) { Write-Host "    OK: diseñador de etiquetas creado" -ForegroundColor Green } else { Write-Host "    ERROR" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: pestaña stock_almacenes en articulos" -ForegroundColor Green } else { Write-Host "    ERROR" -ForegroundColor Red }
if ($ok3) { Write-Host "    OK: Sidebar con etiquetas" -ForegroundColor Green } else { Write-Host "    ERROR" -ForegroundColor Red }
Write-Host ""
Write-Host "DEPENDENCIAS npm necesarias:" -ForegroundColor Yellow
Write-Host "  npm install qrcode @types/qrcode"
Write-Host ""
Write-Host '  git add -A'
Write-Host '  git commit -m "feat: stock cache por almacen, pestaña Stock_Almacenes, diseñador de etiquetas con QR"'
Write-Host '  git push'
