#Requires -Version 5.1
# deploy-articulos-v2.ps1
# 1. FotoArticulo: hover popup corregido (invisible/visible con group/foto)
# 2. Articulos: click en fila -> modal detalle con tabs Info/Movimientos/Auditoria
# 3. Articulos: campo proximo_mantenimiento si tipo=maquinaria
# 4. Almacenes detalle: columna Dias en almacen (desde v_stock_actual_ext)
# 5. Articulos y movimientos: miniatura con FotoArticulo en todos los listados
# IMPORTANTE: ejecutar 036_articulos_mantenimiento.sql en Supabase primero

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Escribiendo archivos" -ForegroundColor Cyan

$dst = "src\components\shared\FotoArticulo.tsx"
$content = @'
/**
 * FotoArticulo — Miniatura con popup hover que muestra la imagen en tamaño medio.
 * Usado en listados de artículos, movimientos e históricos.
 */
"use client";
import { Package } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface Props {
  url?: string | null;
  nombre?: string;
  size?: "sm" | "md";
}

export function FotoArticulo({ url, nombre = "", size = "md" }: Props) {
  const dim = size === "sm" ? "w-7 h-7" : "w-8 h-8";

  return (
    <div className={cn("relative inline-flex shrink-0 group/foto", dim)}>
      {/* Miniatura */}
      {url ? (
        <img
          src={url}
          alt={nombre}
          title={nombre}
          className={cn(dim, "rounded object-cover border border-surface-200 cursor-zoom-in")}
          onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }}
        />
      ) : (
        <div className={cn(dim, "rounded bg-surface-100 flex items-center justify-center border border-surface-100")}>
          <Package className="w-3.5 h-3.5 text-surface-300" />
        </div>
      )}

      {/* Popup hover: solo si hay foto */}
      {url && (
        <div
          className={cn(
            // Posición: encima y centrado
            "absolute z-[9999] bottom-full left-1/2 -translate-x-1/2 mb-2",
            // Tamaño fijo del popup
            "w-44 h-44 rounded-xl overflow-hidden",
            // Estilo visual
            "bg-white shadow-2xl border border-surface-200 ring-1 ring-black/5",
            // Visibilidad controlada con invisible/visible para no ocupar espacio en DOM
            "invisible opacity-0 scale-90 pointer-events-none",
            "group-hover/foto:visible group-hover/foto:opacity-100 group-hover/foto:scale-100",
            "transition-all duration-150 ease-out",
          )}
          style={{ transformOrigin: "bottom center" }}
        >
          <img
            src={url}
            alt={nombre}
            className="w-full h-full object-contain bg-white p-1"
          />
          {nombre && (
            <div className="absolute bottom-0 left-0 right-0 bg-black/50 text-white text-[10px] px-2 py-1 truncate">
              {nombre}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\components\shared\FotoArticulo.tsx" -ForegroundColor Green

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
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\almacen\articulos\page.tsx" -ForegroundColor Green

$dst = "src\app\almacen\almacenes\[id]\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback } from "react";
import { useParams, useRouter } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import { FotoArticulo } from "@/components/shared/FotoArticulo";
import {
  Warehouse, Loader2, ArrowLeft, AlertTriangle, SlidersHorizontal,
  History, TrendingDown, Calendar, Search, ArrowDownToLine,
  ArrowUpFromLine, ArrowLeftRight, Package, Building2,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";

const TIPO_MOV: Record<string, { label: string; color: string }> = {
  entrada:          { label: "Entrada",         color: "bg-emerald-100 text-emerald-700" },
  salida:           { label: "Salida",          color: "bg-red-100 text-red-700" },
  ajuste:           { label: "Ajuste",          color: "bg-amber-100 text-amber-700" },
  traslado_salida:  { label: "Traslado salida", color: "bg-blue-100 text-blue-700" },
  traslado_entrada: { label: "Traslado entrad.", color: "bg-blue-100 text-blue-700" },
};

const TIPO_ART: Record<string, string> = {
  material:   "bg-blue-100 text-blue-700",
  maquinaria: "bg-orange-100 text-orange-700",
  vehiculo:   "bg-purple-100 text-purple-700",
  otro:       "bg-surface-100 text-surface-600",
};

const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

export default function AlmacenDetallePage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { user } = useAuthStore();
  const supabase = createClient();
  const { isAdmin, canDo } = usePermissions();
  const puedeAjustar = isAdmin || canDo("almacen_ajustes", "crear");

  const [almacen, setAlmacen] = useState<any>(null);
  const [stock, setStock] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [tipoFilter, setTipoFilter] = useState("");

  // Modal histórico
  const [historialOpen, setHistorialOpen] = useState(false);
  const [historialItem, setHistorialItem] = useState<any>(null);
  const [historial, setHistorial] = useState<any[]>([]);
  const [historialLoading, setHistorialLoading] = useState(false);

  // Modal ajuste
  const [ajusteOpen, setAjusteOpen] = useState(false);
  const [ajusteItem, setAjusteItem] = useState<any>(null);
  const [ajusteForm, setAjusteForm] = useState({ sentido: "+", cantidad: "1", motivo: "", observaciones: "" });
  const [ajusteSaving, setAjusteSaving] = useState(false);
  const [ajusteError, setAjusteError] = useState<string | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [aRes, sRes] = await Promise.all([
      (supabase.from("almacenes") as any).select("*, obra:obras(nombre,num_presupuesto)").eq("id", id).single(),
      (supabase.from("v_stock_actual_ext") as any).select("*").eq("almacen_id", id),
    ]);
    setAlmacen(aRes.data);
    setStock(sRes.data || []);
    setLoading(false);
  }, [id]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const filteredStock = stock.filter((s) => {
    const matchSearch =
      s.nombre?.toLowerCase().includes(search.toLowerCase()) ||
      s.codigo_articulo?.toLowerCase().includes(search.toLowerCase()) ||
      s.referencia_proveedor?.toLowerCase().includes(search.toLowerCase());
    const matchTipo = !tipoFilter || s.tipo === tipoFilter;
    return matchSearch && matchTipo;
  });

  // Abrir histórico de movimientos de un artículo en este almacén
  const openHistorial = async (item: any) => {
    setHistorialItem(item);
    setHistorialOpen(true);
    setHistorialLoading(true);
    const { data } = await (supabase.from("movimientos_almacen") as any)
      .select("*, origen:almacenes!almacen_origen_id(nombre), destino:almacenes!almacen_destino_id(nombre), obra:obras(nombre), user:users(nombre)")
      .eq("articulo_id", item.articulo_id)
      .or(`almacen_origen_id.eq.${id},almacen_destino_id.eq.${id}`)
      .order("created_at", { ascending: false })
      .limit(100);
    setHistorial(data || []);
    setHistorialLoading(false);
  };

  // Abrir modal de ajuste
  const openAjuste = (item: any) => {
    setAjusteItem(item);
    setAjusteForm({ sentido: "+", cantidad: "1", motivo: "", observaciones: "" });
    setAjusteError(null);
    setAjusteOpen(true);
  };

  // Guardar ajuste
  const handleAjuste = async (e: React.FormEvent) => {
    e.preventDefault();
    setAjusteSaving(true); setAjusteError(null);
    try {
      const cantidad = parseFloat(ajusteForm.cantidad);
      if (!cantidad || cantidad <= 0) throw new Error("La cantidad debe ser mayor que 0");
      if (!ajusteForm.motivo.trim()) throw new Error("El motivo es obligatorio en un ajuste");

      // Sentido: + = entrada al almacén, - = salida del almacén
      const payload: any = {
        tipo: "ajuste",
        articulo_id: ajusteItem.articulo_id,
        cantidad,
        motivo: ajusteForm.motivo.trim(),
        observaciones: ajusteForm.observaciones || null,
        created_by: user?.id,
        fecha: new Date().toLocaleDateString("sv-SE"), // YYYY-MM-DD
      };

      if (ajusteForm.sentido === "+") {
        payload.almacen_destino_id = id;
      } else {
        payload.almacen_origen_id = id;
      }

      const { error: err } = await (supabase.from("movimientos_almacen") as any).insert(payload);
      if (err) throw err;

      setAjusteOpen(false);
      fetchData();
    } catch (err: any) {
      setAjusteError(err.message || "Error al registrar ajuste");
      await logAuditErrorClient({
        modulo: "almacen.ajustes", entidad: "movimientos_almacen", accion: "crear",
        descripcion: "Error al registrar ajuste de stock", errorDetalle: err.message || "",
      });
    } finally { setAjusteSaving(false); }
  };

  const hoy = new Date();
  const isExpired = (cad: string | null) => cad && new Date(cad) < hoy;
  const isExpiringSoon = (cad: string | null) => {
    if (!cad) return false;
    const diff = (new Date(cad).getTime() - hoy.getTime()) / 86400000;
    return diff >= 0 && diff <= 30;
  };

  if (loading) {
    return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;
  }

  if (!almacen) {
    return <AppLayout><div className="text-center py-20 text-sm text-surface-400">Almacén no encontrado</div></AppLayout>;
  }

  const stockNeg = filteredStock.filter((s) => s.stock_negativo).length;
  const stockBM  = filteredStock.filter((s) => s.bajo_minimo).length;

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        {/* Header */}
        <div className="flex items-center gap-3 mb-6">
          <button onClick={() => router.back()} className="p-2 rounded-lg text-surface-400 hover:bg-surface-100">
            <ArrowLeft className="w-4 h-4" />
          </button>
          <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
            {almacen.es_almacen_obra ? <Building2 className="w-5 h-5 text-brand-600" /> : <Warehouse className="w-5 h-5 text-brand-600" />}
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <h1 className="text-xl font-display font-bold text-surface-900">{almacen.nombre}</h1>
              <span className="font-mono text-xs text-surface-400">{almacen.codigo_almacen}</span>
              {almacen.es_almacen_obra && almacen.obra && (
                <span className="badge text-[10px] bg-brand-50 text-brand-600">{almacen.obra.nombre}</span>
              )}
            </div>
            {almacen.ubicacion && <p className="text-sm text-surface-500 mt-0.5">{almacen.ubicacion}</p>}
          </div>
        </div>

        {/* Alertas globales del almacén */}
        {(stockNeg > 0 || stockBM > 0) && (
          <div className="flex gap-3 mb-4 flex-wrap">
            {stockNeg > 0 && (
              <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-red-50 border border-red-200 text-xs text-red-700">
                <AlertTriangle className="w-4 h-4" />
                {stockNeg} artículo{stockNeg > 1 ? "s" : ""} con stock negativo
              </div>
            )}
            {stockBM > 0 && (
              <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-amber-50 border border-amber-200 text-xs text-amber-700">
                <TrendingDown className="w-4 h-4" />
                {stockBM} artículo{stockBM > 1 ? "s" : ""} por debajo del stock mínimo
              </div>
            )}
          </div>
        )}

        {/* Tabla de stock */}
        <div className="card overflow-hidden">
          <div className="p-3 border-b border-surface-100 flex gap-2 flex-wrap items-center">
            <div className="relative flex-1 min-w-40">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
              <input className="w-full pl-9 pr-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg" placeholder="Buscar artículo..." value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
            <select value={tipoFilter} onChange={(e) => setTipoFilter(e.target.value)}
              className="px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg">
              <option value="">Todos los tipos</option>
              <option value="material">Material</option>
              <option value="maquinaria">Maquinaria</option>
              <option value="vehiculo">Vehículo</option>
              <option value="otro">Otro</option>
            </select>
            <span className="text-xs text-surface-400 ml-auto">{filteredStock.length} artículos</span>
          </div>

          {filteredStock.length === 0 ? (
            <div className="text-center py-12 text-sm text-surface-400">
              <Package className="w-8 h-8 mx-auto mb-2 opacity-30" />
              Sin stock registrado en este almacén
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-surface-100 bg-surface-50">
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Artículo</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Ref. proveedor</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Tipo</th>
                    <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Stock</th>
                    <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden sm:table-cell">Mín.</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Caducidad</th>
                    <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden xl:table-cell">Días</th>
                    <th className="w-20 text-center text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredStock.map((s) => {
                    const negativo = s.stock_negativo;
                    const bajoMin  = s.bajo_minimo;
                    const cadExp   = isExpired(s.caducidad);
                    const cadProx  = isExpiringSoon(s.caducidad);
                    return (
                      <tr key={s.articulo_id}
                        className={cn("border-b border-surface-50 hover:bg-surface-50/50 transition-colors",
                          negativo && "bg-red-50/30",
                          bajoMin && !negativo && "bg-amber-50/30")}>
                        <td className="px-4 py-2.5">
                          <div className="flex items-center gap-2">
                            <FotoArticulo url={(s as any).foto_url} nombre={s.nombre} size="sm" />
                            <div>
                              <div className="font-medium text-surface-900 text-xs">{s.nombre}</div>
                              <div className="text-[10px] text-surface-400 font-mono">{s.codigo_articulo}</div>
                            </div>
                          </div>
                        </td>
                        <td className="px-4 py-2.5 text-xs text-surface-500 hidden md:table-cell">{s.referencia_proveedor}</td>
                        <td className="px-4 py-2.5">
                          <span className={cn("badge text-[10px]", TIPO_ART[s.tipo] || TIPO_ART.otro)}>
                            {s.tipo}
                          </span>
                        </td>
                        <td className="px-4 py-2.5 text-right">
                          <span className={cn("font-mono text-sm font-semibold",
                            negativo ? "text-red-600" : bajoMin ? "text-amber-600" : "text-surface-900")}>
                            {negativo && <AlertTriangle className="w-3 h-3 inline mr-1" />}
                            {Number(s.stock_qty).toFixed(2)}
                          </span>
                          <span className="text-[10px] text-surface-400 ml-1">{s.unidad}</span>
                        </td>
                        <td className="px-4 py-2.5 text-right text-xs text-surface-400 hidden sm:table-cell font-mono">
                          {s.stock_minimo_def > 0 ? Number(s.stock_minimo_def).toFixed(2) : "—"}
                        </td>
                        <td className="px-4 py-2.5 hidden lg:table-cell">
                          {s.caducidad ? (
                            <span className={cn("flex items-center gap-1 text-xs",
                              cadExp ? "text-red-600" : cadProx ? "text-amber-600" : "text-surface-500")}>
                              {(cadExp || cadProx) && <AlertTriangle className="w-3 h-3" />}
                              <Calendar className="w-3 h-3" />
                              {new Date(s.caducidad).toLocaleDateString("es-ES")}
                            </span>
                          ) : <span className="text-surface-300 text-xs">—</span>}
                        </td>
                        <td className="px-4 py-2.5 text-right hidden xl:table-cell">
                          {(s as any).dias_en_almacen != null ? (
                            <span className="font-mono text-xs text-surface-600">{(s as any).dias_en_almacen}d</span>
                          ) : <span className="text-surface-300 text-xs">—</span>}
                        </td>
                        <td className="px-4 py-2.5">
                          <div className="flex items-center justify-center gap-1">
                            {puedeAjustar && (
                              <button onClick={() => openAjuste(s)} title="Ajuste de stock"
                                className="p-1.5 rounded-lg text-surface-400 hover:bg-amber-50 hover:text-amber-600 transition-colors">
                                <SlidersHorizontal className="w-3.5 h-3.5" />
                              </button>
                            )}
                            <button onClick={() => openHistorial(s)} title="Ver histórico"
                              className="p-1.5 rounded-lg text-surface-400 hover:bg-brand-50 hover:text-brand-600 transition-colors">
                              <History className="w-3.5 h-3.5" />
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {/* Modal: ajuste de stock */}
      <Modal open={ajusteOpen} onClose={() => setAjusteOpen(false)} title="Ajuste de stock" size="sm">
        {ajusteItem && (
          <form onSubmit={handleAjuste} className="space-y-3">
            <div className="px-3 py-2 bg-surface-50 rounded-lg text-sm">
              <p className="font-medium text-surface-900">{ajusteItem.nombre}</p>
              <p className="text-xs text-surface-500 font-mono">{ajusteItem.codigo_articulo}</p>
              <p className="text-xs mt-1">
                Stock actual:{" "}
                <span className={cn("font-bold font-mono", ajusteItem.stock_negativo ? "text-red-600" : "text-surface-900")}>
                  {Number(ajusteItem.stock_qty).toFixed(2)} {ajusteItem.unidad}
                </span>
              </p>
            </div>

            <div>
              <label className="block text-xs font-medium text-surface-600 mb-1">Sentido del ajuste</label>
              <div className="flex gap-2">
                <button type="button" onClick={() => setAjusteForm({ ...ajusteForm, sentido: "+" })}
                  className={cn("flex-1 flex items-center justify-center gap-2 py-2 text-sm font-semibold rounded-lg border transition-colors",
                    ajusteForm.sentido === "+" ? "border-emerald-500 bg-emerald-50 text-emerald-700" : "border-surface-200 text-surface-600 hover:bg-surface-50")}>
                  <ArrowDownToLine className="w-4 h-4" />+ Aumentar
                </button>
                <button type="button" onClick={() => setAjusteForm({ ...ajusteForm, sentido: "-" })}
                  className={cn("flex-1 flex items-center justify-center gap-2 py-2 text-sm font-semibold rounded-lg border transition-colors",
                    ajusteForm.sentido === "-" ? "border-red-500 bg-red-50 text-red-700" : "border-surface-200 text-surface-600 hover:bg-surface-50")}>
                  <ArrowUpFromLine className="w-4 h-4" />− Reducir
                </button>
              </div>
            </div>

            <div><label className="block text-xs font-medium text-surface-600 mb-1">Cantidad *</label>
              <input required type="number" min="0.001" step="0.001" className={ic}
                value={ajusteForm.cantidad} onChange={(e) => setAjusteForm({ ...ajusteForm, cantidad: e.target.value })}
                placeholder="Cantidad a ajustar (siempre positiva)" />
            </div>

            <div><label className="block text-xs font-medium text-surface-600 mb-1">Motivo del ajuste *</label>
              <input required className={ic} value={ajusteForm.motivo}
                onChange={(e) => setAjusteForm({ ...ajusteForm, motivo: e.target.value })}
                placeholder="Ej: Conteo físico, corrección de error, rotura..." />
            </div>

            <div><label className="block text-xs font-medium text-surface-600 mb-1">Observaciones</label>
              <input className={ic} value={ajusteForm.observaciones}
                onChange={(e) => setAjusteForm({ ...ajusteForm, observaciones: e.target.value })} />
            </div>

            {/* Vista previa del resultado */}
            <div className="px-3 py-2 bg-surface-50 rounded-lg text-xs text-surface-500">
              Stock resultante:{" "}
              <span className={cn("font-bold font-mono",
                (Number(ajusteItem.stock_qty) + (ajusteForm.sentido === "+" ? 1 : -1) * (parseFloat(ajusteForm.cantidad) || 0)) < 0
                  ? "text-red-600" : "text-surface-900")}>
                {(Number(ajusteItem.stock_qty) + (ajusteForm.sentido === "+" ? 1 : -1) * (parseFloat(ajusteForm.cantidad) || 0)).toFixed(2)} {ajusteItem.unidad}
              </span>
              {(Number(ajusteItem.stock_qty) + (ajusteForm.sentido === "+" ? 1 : -1) * (parseFloat(ajusteForm.cantidad) || 0)) < 0 && (
                <span className="text-red-500 ml-2">(quedará negativo)</span>
              )}
            </div>

            {ajusteError && <p className="text-xs text-red-600">{ajusteError}</p>}

            <div className="flex justify-end gap-2 pt-1">
              <button type="button" onClick={() => setAjusteOpen(false)} className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
              <button type="submit" disabled={ajusteSaving}
                className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
                {ajusteSaving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
                Registrar ajuste
              </button>
            </div>
          </form>
        )}
      </Modal>

      {/* Modal: histórico de movimientos del artículo */}
      <Modal open={historialOpen} onClose={() => setHistorialOpen(false)}
        title={historialItem ? `Histórico — ${historialItem.nombre}` : "Histórico"} size="lg">
        {historialLoading ? (
          <div className="flex justify-center py-8"><Loader2 className="w-6 h-6 text-brand-500 animate-spin" /></div>
        ) : historial.length === 0 ? (
          <div className="text-center py-8 text-sm text-surface-400">Sin movimientos registrados</div>
        ) : (
          <div className="space-y-0 max-h-[60vh] overflow-y-auto">
            {historial.map((m) => {
              const cfg = TIPO_MOV[m.tipo] || { label: m.tipo, color: "bg-surface-100 text-surface-600" };
              const almacen_mov = m.tipo.includes("entrada") || m.tipo === "ajuste" && m.almacen_destino_id
                ? m.destino?.nombre : m.origen?.nombre;
              return (
                <div key={m.id} className="flex items-start gap-3 py-3 border-b border-surface-50 last:border-0">
                  <div className="shrink-0 mt-0.5">
                    <span className={cn("badge text-[10px]", cfg.color)}>{cfg.label}</span>
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3 flex-wrap">
                      <span className="font-mono text-sm font-semibold text-surface-900">
                        {m.tipo.includes("salida") || (m.tipo === "ajuste" && m.almacen_origen_id) ? "−" : "+"}
                        {Number(m.cantidad).toFixed(2)}
                      </span>
                      <span className="text-xs text-surface-500">{new Date(m.fecha).toLocaleDateString("es-ES")}</span>
                      {m.obra?.nombre && <span className="text-xs text-brand-600">{m.obra.nombre}</span>}
                    </div>
                    <div className="flex gap-3 mt-0.5 flex-wrap">
                      {m.origen?.nombre && <span className="text-[10px] text-surface-400">De: {m.origen.nombre}</span>}
                      {m.destino?.nombre && <span className="text-[10px] text-surface-400">A: {m.destino.nombre}</span>}
                      {m.user?.nombre && <span className="text-[10px] text-surface-400">{m.user.nombre}</span>}
                    </div>
                    {m.motivo && <p className="text-xs text-amber-700 mt-0.5 font-medium">Motivo: {m.motivo}</p>}
                    {m.observaciones && <p className="text-xs text-surface-500 mt-0.5">{m.observaciones}</p>}
                    {m.lote_ref && <p className="text-[10px] text-surface-400 font-mono mt-0.5">Lote: {m.lote_ref}</p>}
                  </div>
                  <div className="text-[10px] text-surface-300 shrink-0">
                    {new Date(m.created_at).toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" })}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Modal>
    </AppLayout>
  );
}
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\almacen\almacenes\[id]\page.tsx" -ForegroundColor Green

$dst = "src\app\obras\[id]\almacen\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback } from "react";
import { useParams, useRouter } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import { createClient } from "@/lib/supabase/client";
import { FotoArticulo } from "@/components/shared/FotoArticulo";
import {
  ArrowLeft, Loader2, Package, AlertTriangle, TrendingDown,
  Calendar, ArrowDownToLine, ArrowUpFromLine, ArrowLeftRight,
  SlidersHorizontal, Search, Filter,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";

const TIPO_MOV: Record<string, { label: string; color: string; icon: any }> = {
  entrada:          { label: "Entrada",          color: "bg-emerald-100 text-emerald-700", icon: ArrowDownToLine },
  salida:           { label: "Salida",           color: "bg-red-100 text-red-700",         icon: ArrowUpFromLine },
  ajuste:           { label: "Ajuste",           color: "bg-amber-100 text-amber-700",     icon: SlidersHorizontal },
  traslado_salida:  { label: "Traslado salida",  color: "bg-blue-100 text-blue-700",       icon: ArrowLeftRight },
  traslado_entrada: { label: "Traslado entrada", color: "bg-indigo-100 text-indigo-700",   icon: ArrowLeftRight },
};

const TIPO_ART: Record<string, string> = {
  material:   "bg-blue-100 text-blue-700",
  maquinaria: "bg-orange-100 text-orange-700",
  vehiculo:   "bg-purple-100 text-purple-700",
  otro:       "bg-surface-100 text-surface-600",
};

export default function ObraAlmacenPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const supabase = createClient();

  const [obra, setObra] = useState<any>(null);
  const [almacen, setAlmacen] = useState<any>(null);
  const [stock, setStock] = useState<any[]>([]);
  const [movimientos, setMovimientos] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<"stock" | "movimientos">("stock");
  const [searchStock, setSearchStock] = useState("");
  const [searchMov, setSearchMov] = useState("");
  const [tipoMovFilter, setTipoMovFilter] = useState("");
  const [creandoAlmacen, setCreandoAlmacen] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    try {
      // Datos de la obra
      const { data: obraData } = await (supabase.from("obras") as any)
        .select("id, nombre, num_presupuesto, cliente:clientes(nombre)")
        .eq("id", id)
        .single();
      setObra(obraData);

      // Almacén de la obra
      const { data: almacenData } = await (supabase.from("almacenes") as any)
        .select("id, codigo_almacen, nombre, ubicacion")
        .eq("obra_id", id)
        .eq("es_almacen_obra", true)
        .eq("activo", true)
        .maybeSingle();
      setAlmacen(almacenData);

      if (!almacenData?.id) { setLoading(false); return; }

      // Stock actual del almacén
      const { data: stockData } = await (supabase.from("v_stock_actual_ext") as any)
        .select("*")
        .eq("almacen_id", almacenData.id);
      setStock(stockData || []);

      // Movimientos donde participa el almacén de la obra
      const { data: movData } = await (supabase.from("movimientos_almacen") as any)
        .select(`
          id, tipo, cantidad, fecha, observaciones, motivo, lote_ref, created_at,
          articulo:articulos(nombre, codigo_articulo, referencia_proveedor, unidad, tipo),
          origen:almacenes!almacen_origen_id(nombre, codigo_almacen),
          destino:almacenes!almacen_destino_id(nombre, codigo_almacen),
          obra_rel:obras!obra_id(nombre),
          user:users(nombre)
        `)
        .or(`almacen_origen_id.eq.${almacenData.id},almacen_destino_id.eq.${almacenData.id}`)
        .order("created_at", { ascending: false })
        .limit(500);
      setMovimientos(movData || []);
    } catch (err) {
      console.error(err);
    } finally { setLoading(false); }
  }, [id]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const handleCrearAlmacen = async () => {
    setCreandoAlmacen(true);
    try {
      const { error } = await (supabase.rpc as any)("crear_almacen_obra", { p_obra_id: id });
      if (error) throw error;
      fetchData();
    } catch (err: any) {
      alert("Error: " + (err?.message || err));
    } finally { setCreandoAlmacen(false); }
  };

  const hoy = new Date();
  const isExpired = (cad: string | null) => cad && new Date(cad) < hoy;
  const isExpiringSoon = (cad: string | null) => {
    if (!cad) return false;
    const diff = (new Date(cad).getTime() - hoy.getTime()) / 86400000;
    return diff >= 0 && diff <= 30;
  };

  const filteredStock = stock.filter((s) =>
    !searchStock ||
    s.nombre?.toLowerCase().includes(searchStock.toLowerCase()) ||
    s.codigo_articulo?.toLowerCase().includes(searchStock.toLowerCase()) ||
    s.referencia_proveedor?.toLowerCase().includes(searchStock.toLowerCase())
  );

  const filteredMov = movimientos.filter((m) => {
    const matchSearch = !searchMov ||
      m.articulo?.nombre?.toLowerCase().includes(searchMov.toLowerCase()) ||
      m.articulo?.codigo_articulo?.toLowerCase().includes(searchMov.toLowerCase());
    const matchTipo = !tipoMovFilter || m.tipo === tipoMovFilter;
    return matchSearch && matchTipo;
  });

  const stockNeg = stock.filter((s) => s.stock_negativo).length;
  const stockBM  = stock.filter((s) => s.bajo_minimo).length;

  if (loading) {
    return (
      <AppLayout>
        <div className="flex justify-center py-20">
          <Loader2 className="w-8 h-8 text-brand-500 animate-spin" />
        </div>
      </AppLayout>
    );
  }

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">

        {/* Cabecera */}
        <div className="flex items-center gap-3 mb-6">
          <button onClick={() => router.back()}
            className="p-2 rounded-lg text-surface-400 hover:bg-surface-100">
            <ArrowLeft className="w-4 h-4" />
          </button>
          <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
            <Package className="w-5 h-5 text-brand-600" />
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <h1 className="text-xl font-display font-bold text-surface-900">
                Almacén de obra
              </h1>
              {obra && (
                <span className="badge text-[11px] bg-brand-50 text-brand-600">
                  {obra.nombre}
                </span>
              )}
            </div>
            {almacen && (
              <p className="text-sm text-surface-500 mt-0.5">
                {almacen.codigo_almacen} · {almacen.nombre}
                {almacen.ubicacion && ` · ${almacen.ubicacion}`}
              </p>
            )}
          </div>
        </div>

        {/* Sin almacén: aviso y botón */}
        {!almacen && (
          <div className="card p-10 text-center">
            <Package className="w-10 h-10 mx-auto mb-3 text-surface-300" />
            <p className="text-sm text-surface-600 mb-2 font-medium">
              Esta obra no tiene almacén asociado
            </p>
            <p className="text-xs text-surface-400 mb-5">
              El código se generará como OBRA-{obra?.num_presupuesto || "[num_presupuesto]"}.
              {!obra?.num_presupuesto && " La obra necesita un número de presupuesto o se usará el ID interno."}
            </p>
            <button
              onClick={handleCrearAlmacen}
              disabled={creandoAlmacen}
              className="flex items-center gap-2 mx-auto px-5 py-2.5 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {creandoAlmacen ? <Loader2 className="w-4 h-4 animate-spin" /> : <Package className="w-4 h-4" />}
              Crear almacén de esta obra
            </button>
          </div>
        )}

        {almacen && (
          <>
            {/* Alertas globales */}
            {(stockNeg > 0 || stockBM > 0) && (
              <div className="flex gap-3 mb-4 flex-wrap">
                {stockNeg > 0 && (
                  <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-red-50 border border-red-200 text-xs text-red-700">
                    <AlertTriangle className="w-4 h-4" />
                    {stockNeg} artículo{stockNeg > 1 ? "s" : ""} con stock negativo
                  </div>
                )}
                {stockBM > 0 && (
                  <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-amber-50 border border-amber-200 text-xs text-amber-700">
                    <TrendingDown className="w-4 h-4" />
                    {stockBM} artículo{stockBM > 1 ? "s" : ""} por debajo del mínimo
                  </div>
                )}
              </div>
            )}

            {/* Tabs */}
            <div className="flex gap-1 mb-4 bg-surface-100 rounded-lg p-1 w-fit">
              <button onClick={() => setTab("stock")}
                className={cn("px-4 py-2 text-sm font-medium rounded-md transition-colors",
                  tab === "stock" ? "bg-white shadow-sm text-surface-900" : "text-surface-500 hover:text-surface-700")}>
                Stock actual
                {stock.length > 0 && (
                  <span className="ml-1.5 text-[10px] bg-brand-100 text-brand-700 px-1.5 py-0.5 rounded-full font-semibold">
                    {stock.length}
                  </span>
                )}
              </button>
              <button onClick={() => setTab("movimientos")}
                className={cn("px-4 py-2 text-sm font-medium rounded-md transition-colors",
                  tab === "movimientos" ? "bg-white shadow-sm text-surface-900" : "text-surface-500 hover:text-surface-700")}>
                Movimientos
                {movimientos.length > 0 && (
                  <span className="ml-1.5 text-[10px] bg-surface-200 text-surface-600 px-1.5 py-0.5 rounded-full font-semibold">
                    {movimientos.length}
                  </span>
                )}
              </button>
            </div>

            {/* ===== TAB STOCK ===== */}
            {tab === "stock" && (
              <div className="card overflow-hidden">
                <div className="p-3 border-b border-surface-100 flex gap-2 flex-wrap items-center">
                  <div className="relative flex-1 min-w-48">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
                    <input
                      className="w-full pl-9 pr-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none"
                      placeholder="Buscar artículo, código..."
                      value={searchStock}
                      onChange={(e) => setSearchStock(e.target.value)}
                    />
                  </div>
                  <span className="text-xs text-surface-400 ml-auto">{filteredStock.length} artículos</span>
                </div>

                {filteredStock.length === 0 ? (
                  <div className="text-center py-14 text-sm text-surface-400">
                    <Package className="w-8 h-8 mx-auto mb-2 opacity-30" />
                    Sin stock registrado en este almacén
                  </div>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead>
                        <tr className="border-b border-surface-100 bg-surface-50">
                          <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Artículo</th>
                          <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Ref. proveedor</th>
                          <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Tipo</th>
                          <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Stock</th>
                          <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden sm:table-cell">Mín.</th>
                          <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Caducidad</th>
                          <th className="text-center text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Estado</th>
                        </tr>
                      </thead>
                      <tbody>
                        {filteredStock.map((s) => {
                          const cadExp   = isExpired(s.caducidad);
                          const cadProx  = isExpiringSoon(s.caducidad);
                          const negativo = s.stock_negativo;
                          const bajMin   = s.bajo_minimo;
                          const cero     = Number(s.stock_qty) === 0;
                          return (
                            <tr key={s.articulo_id}
                              className={cn("border-b border-surface-50 hover:bg-surface-50/50 transition-colors",
                                negativo && "bg-red-50/30",
                                bajMin && !negativo && "bg-amber-50/20")}>
                              <td className="px-4 py-2.5">
                                <div className="font-medium text-surface-900 text-xs">{s.nombre}</div>
                                <div className="text-[10px] text-surface-400 font-mono">{s.codigo_articulo}</div>
                              </td>
                              <td className="px-4 py-2.5 text-xs text-surface-500 hidden md:table-cell">
                                {s.referencia_proveedor || "—"}
                              </td>
                              <td className="px-4 py-2.5">
                                <span className={cn("badge text-[10px]", TIPO_ART[s.tipo] || TIPO_ART.otro)}>
                                  {s.tipo}
                                </span>
                              </td>
                              <td className="px-4 py-2.5 text-right">
                                <span className={cn("font-mono text-sm font-semibold",
                                  negativo ? "text-red-600" : bajMin ? "text-amber-600" : cero ? "text-surface-400" : "text-surface-900")}>
                                  {negativo && <AlertTriangle className="w-3 h-3 inline mr-1" />}
                                  {Number(s.stock_qty).toFixed(2)}
                                </span>
                                <span className="text-[10px] text-surface-400 ml-1">{s.unidad}</span>
                              </td>
                              <td className="px-4 py-2.5 text-right font-mono text-xs text-surface-400 hidden sm:table-cell">
                                {s.stock_minimo_def > 0 ? Number(s.stock_minimo_def).toFixed(2) : "—"}
                              </td>
                              <td className="px-4 py-2.5 hidden lg:table-cell">
                                {s.caducidad ? (
                                  <span className={cn("flex items-center gap-1 text-xs",
                                    cadExp ? "text-red-600" : cadProx ? "text-amber-600" : "text-surface-500")}>
                                    {(cadExp || cadProx) && <AlertTriangle className="w-3 h-3" />}
                                    <Calendar className="w-3 h-3" />
                                    {new Date(s.caducidad).toLocaleDateString("es-ES")}
                                  </span>
                                ) : <span className="text-surface-300 text-xs">—</span>}
                              </td>
                              <td className="px-4 py-2.5 text-center">
                                <div className="flex items-center justify-center gap-1 flex-wrap">
                                  {negativo && <span className="badge text-[9px] bg-red-100 text-red-700">Negativo</span>}
                                  {bajMin && !negativo && <span className="badge text-[9px] bg-amber-100 text-amber-700">Bajo mín.</span>}
                                  {cero && !negativo && <span className="badge text-[9px] bg-surface-100 text-surface-500">Sin stock</span>}
                                  {cadExp && <span className="badge text-[9px] bg-red-100 text-red-700">Caducado</span>}
                                  {cadProx && !cadExp && <span className="badge text-[9px] bg-amber-100 text-amber-700">Caduca pronto</span>}
                                  {!negativo && !bajMin && !cero && !cadExp && !cadProx && (
                                    <span className="badge text-[9px] bg-emerald-100 text-emerald-700">OK</span>
                                  )}
                                </div>
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}

            {/* ===== TAB MOVIMIENTOS ===== */}
            {tab === "movimientos" && (
              <div className="card overflow-hidden">
                <div className="p-3 border-b border-surface-100 flex gap-2 flex-wrap items-center">
                  <div className="relative flex-1 min-w-48">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
                    <input
                      className="w-full pl-9 pr-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none"
                      placeholder="Buscar artículo, código..."
                      value={searchMov}
                      onChange={(e) => setSearchMov(e.target.value)}
                    />
                  </div>
                  <select value={tipoMovFilter} onChange={(e) => setTipoMovFilter(e.target.value)}
                    className="px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none">
                    <option value="">Todos los tipos</option>
                    {Object.entries(TIPO_MOV).map(([k, v]) => (
                      <option key={k} value={k}>{v.label}</option>
                    ))}
                  </select>
                  <span className="text-xs text-surface-400 ml-auto">{filteredMov.length} movimientos</span>
                </div>

                {filteredMov.length === 0 ? (
                  <div className="text-center py-14 text-sm text-surface-400">
                    <ArrowLeftRight className="w-8 h-8 mx-auto mb-2 opacity-30" />
                    Sin movimientos registrados para este almacén
                  </div>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead>
                        <tr className="border-b border-surface-100 bg-surface-50">
                          <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Fecha</th>
                          <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Tipo</th>
                          <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Artículo</th>
                          <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Cantidad</th>
                          <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Origen</th>
                          <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Destino</th>
                          <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Usuario</th>
                          <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Observaciones</th>
                        </tr>
                      </thead>
                      <tbody>
                        {filteredMov.map((m) => {
                          const cfg = TIPO_MOV[m.tipo] || { label: m.tipo, color: "bg-surface-100 text-surface-600", icon: ArrowLeftRight };
                          const Icon = cfg.icon;
                          const esSalida = m.tipo === "salida" || m.tipo === "traslado_salida";
                          return (
                            <tr key={m.id} className="border-b border-surface-50 hover:bg-surface-50/50 transition-colors">
                              <td className="px-4 py-2.5 text-xs text-surface-500 font-mono whitespace-nowrap">
                                {new Date(m.fecha).toLocaleDateString("es-ES")}
                              </td>
                              <td className="px-4 py-2.5">
                                <span className={cn("badge text-[10px] flex items-center gap-1 w-fit", cfg.color)}>
                                  <Icon className="w-2.5 h-2.5" />
                                  {cfg.label}
                                </span>
                              </td>
                              <td className="px-4 py-2.5">
                                <div className="font-medium text-surface-900 text-xs">{m.articulo?.nombre || "—"}</div>
                                <div className="text-[10px] text-surface-400 font-mono">{m.articulo?.codigo_articulo}</div>
                                {m.articulo?.referencia_proveedor && (
                                  <div className="text-[10px] text-surface-300">{m.articulo.referencia_proveedor}</div>
                                )}
                              </td>
                              <td className="px-4 py-2.5 text-right">
                                <span className={cn("font-mono text-sm font-semibold",
                                  esSalida ? "text-red-600" : "text-emerald-700")}>
                                  {esSalida ? "−" : "+"}{Number(m.cantidad).toFixed(2)}
                                </span>
                                <span className="text-[10px] text-surface-400 ml-1">{m.articulo?.unidad}</span>
                              </td>
                              <td className="px-4 py-2.5 text-xs text-surface-500 hidden md:table-cell">
                                {m.origen ? (
                                  <span className={cn(m.origen.codigo_almacen === almacen?.codigo_almacen && "font-semibold text-brand-600")}>
                                    {m.origen.nombre}
                                  </span>
                                ) : "—"}
                              </td>
                              <td className="px-4 py-2.5 text-xs text-surface-500 hidden md:table-cell">
                                {m.destino ? (
                                  <span className={cn(m.destino.codigo_almacen === almacen?.codigo_almacen && "font-semibold text-brand-600")}>
                                    {m.destino.nombre}
                                  </span>
                                ) : "—"}
                              </td>
                              <td className="px-4 py-2.5 text-xs text-surface-500 hidden lg:table-cell">
                                {m.user?.nombre || "—"}
                              </td>
                              <td className="px-4 py-2.5 text-xs text-surface-500 hidden lg:table-cell max-w-[200px] truncate">
                                {m.motivo && <span className="text-amber-700 font-medium">{m.motivo}</span>}
                                {m.motivo && m.observaciones && " · "}
                                {m.observaciones || (!m.motivo && "—")}
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}
          </>
        )}
      </div>
    </AppLayout>
  );
}
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\obras\[id]\almacen\page.tsx" -ForegroundColor Green

$dst = "src\app\almacen\movimientos\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback, useRef } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import {
  ArrowLeftRight, Loader2, Search, Plus, Scan,
  CheckCircle2, X, Package, SlidersHorizontal,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";
import { FotoArticulo } from "@/components/shared/FotoArticulo";

// Solo 2 tipos en el formulario de nuevo movimiento:
//   movimiento -> traslado_salida + traslado_entrada (via RPC)
//   ajuste     -> ajuste
type TipoForm = "movimiento" | "ajuste";

const TIPO_BADGE: Record<string, { label: string; color: string }> = {
  entrada:          { label: "Entrada",          color: "bg-emerald-100 text-emerald-700" },
  salida:           { label: "Salida",           color: "bg-red-100 text-red-700" },
  ajuste:           { label: "Ajuste",           color: "bg-amber-100 text-amber-700" },
  traslado_salida:  { label: "Traslado salida",  color: "bg-blue-100 text-blue-700" },
  traslado_entrada: { label: "Traslado entrada", color: "bg-indigo-100 text-indigo-700" },
};

const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

interface ScanItem { articulo: any; cantidad: number; }

export default function MovimientosPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const scanRef = useRef<HTMLInputElement>(null);

  const [movimientos, setMovimientos] = useState<any[]>([]);
  const [articulos, setArticulos] = useState<any[]>([]);
  const [almacenes, setAlmacenes] = useState<any[]>([]);
  const [obras, setObras] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");

  // Modal movimiento / ajuste
  const [modalOpen, setModalOpen] = useState(false);
  const [tipoForm, setTipoForm] = useState<TipoForm>("movimiento");
  const [movForm, setMovForm] = useState({
    articulo_id: "", almacen_origen_id: "", almacen_destino_id: "",
    cantidad: "1", observaciones: "",
  });
  const [ajForm, setAjForm] = useState({
    articulo_id: "", almacen_id: "", sentido: "+",
    cantidad: "1", motivo: "", observaciones: "",
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Modal traslado masivo (scan)
  const [trasladoOpen, setTrasladoOpen] = useState(false);
  const [scanInput, setScanInput] = useState("");
  const [scanItems, setScanItems] = useState<ScanItem[]>([]);
  const [trasladoForm, setTrasladoForm] = useState({
    almacen_origen_id: "", almacen_destino_id: "", obra_id: "",
  });
  const [trasladoSaving, setTrasladoSaving] = useState(false);
  const [scanNotFound, setScanNotFound] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [mR, aR, alR, oR] = await Promise.all([
      (supabase.from("movimientos_almacen") as any)
        .select(`*, articulo:articulos(nombre,codigo_articulo,foto_url),
          almacen_origen:almacenes!almacen_origen_id(nombre),
          almacen_destino:almacenes!almacen_destino_id(nombre),
          obra:obras(nombre), user:users(nombre)`)
        .order("created_at", { ascending: false }).limit(200),
      (supabase.from("articulos") as any)
        .select("id,nombre,codigo_articulo,codigo_barras,unidad,foto_url").eq("activo", true).order("nombre"),
      (supabase.from("almacenes") as any).select("id,nombre,codigo_almacen").eq("activo", true).order("nombre"),
      (supabase.from("obras") as any).select("id,nombre").order("nombre"),
    ]);
    setMovimientos(mR.data || []);
    setArticulos(aR.data || []);
    setAlmacenes(alR.data || []);
    setObras(oR.data || []);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const openModal = (tipo: TipoForm) => {
    setTipoForm(tipo);
    setMovForm({ articulo_id: "", almacen_origen_id: "", almacen_destino_id: "", cantidad: "1", observaciones: "" });
    setAjForm({ articulo_id: "", almacen_id: "", sentido: "+", cantidad: "1", motivo: "", observaciones: "" });
    setError(null);
    setModalOpen(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true); setError(null);
    try {
      if (tipoForm === "movimiento") {
        // Traslado: usa RPC registrar_traslado para atomic salida+entrada
        if (!movForm.almacen_origen_id || !movForm.almacen_destino_id)
          throw new Error("Selecciona almacén origen y destino");
        if (movForm.almacen_origen_id === movForm.almacen_destino_id)
          throw new Error("El almacén origen y destino deben ser diferentes");
        const { error: err } = await (supabase.rpc as any)("registrar_traslado", {
          p_articulo_id:        movForm.articulo_id,
          p_almacen_origen_id:  movForm.almacen_origen_id,
          p_almacen_destino_id: movForm.almacen_destino_id,
          p_cantidad:           parseFloat(movForm.cantidad) || 1,
          p_obra_id:            null,
          p_observaciones:      movForm.observaciones || null,
        });
        if (err) throw err;
      } else {
        // Ajuste
        if (!ajForm.motivo.trim()) throw new Error("El motivo es obligatorio en un ajuste");
        const cantidad = parseFloat(ajForm.cantidad) || 1;
        const payload: any = {
          tipo: "ajuste",
          articulo_id: ajForm.articulo_id,
          cantidad,
          motivo: ajForm.motivo.trim(),
          observaciones: ajForm.observaciones || null,
          created_by: user?.id,
          fecha: new Date().toLocaleDateString("sv-SE"),
        };
        if (ajForm.sentido === "+") payload.almacen_destino_id = ajForm.almacen_id;
        else payload.almacen_origen_id = ajForm.almacen_id;
        const { error: err } = await (supabase.from("movimientos_almacen") as any).insert(payload);
        if (err) throw err;
      }
      setModalOpen(false);
      fetchData();
    } catch (err: any) {
      setError(err.message || "Error al registrar");
      await logAuditErrorClient({
        modulo: "almacen.movimientos", entidad: "movimientos_almacen", accion: "crear",
        descripcion: "Error al registrar movimiento", errorDetalle: err.message || "",
      });
    } finally { setSaving(false); }
  };

  // Scan masivo
  const handleScan = (e: React.FormEvent) => {
    e.preventDefault();
    if (!scanInput.trim()) return;
    setScanNotFound(false);
    const found = articulos.find((a) =>
      a.codigo_barras === scanInput.trim() || a.codigo_articulo === scanInput.trim()
    );
    if (!found) { setScanNotFound(true); setScanInput(""); return; }
    setScanItems((prev) => {
      const existing = prev.find((i) => i.articulo.id === found.id);
      if (existing) return prev.map((i) => i.articulo.id === found.id ? { ...i, cantidad: i.cantidad + 1 } : i);
      return [...prev, { articulo: found, cantidad: 1 }];
    });
    setScanInput("");
    setTimeout(() => scanRef.current?.focus(), 50);
  };

  const handleTraslado = async () => {
    if (!trasladoForm.almacen_origen_id || !trasladoForm.almacen_destino_id || !scanItems.length) return;
    setTrasladoSaving(true);
    try {
      for (const item of scanItems) {
        await (supabase.rpc as any)("registrar_traslado", {
          p_articulo_id:        item.articulo.id,
          p_almacen_origen_id:  trasladoForm.almacen_origen_id,
          p_almacen_destino_id: trasladoForm.almacen_destino_id,
          p_cantidad:           item.cantidad,
          p_obra_id:            trasladoForm.obra_id || null,
        });
      }
      setTrasladoOpen(false);
      setScanItems([]);
      setTrasladoForm({ almacen_origen_id: "", almacen_destino_id: "", obra_id: "" });
      fetchData();
    } catch (err: any) { setError(err.message); }
    finally { setTrasladoSaving(false); }
  };

  const filtered = movimientos.filter((m) =>
    !search ||
    m.articulo?.nombre?.toLowerCase().includes(search.toLowerCase()) ||
    m.articulo?.codigo_articulo?.toLowerCase().includes(search.toLowerCase()) ||
    m.tipo?.toLowerCase().includes(search.toLowerCase())
  );

  // Stock resultante preview para ajuste
  const ajResultado = (() => {
    const base = 0; // No tenemos el stock aquí en tiempo real; solo mostramos dirección
    const cant = parseFloat(ajForm.cantidad) || 0;
    return ajForm.sentido === "+" ? `+${cant}` : `-${cant}`;
  })();

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="flex items-center justify-between mb-6 flex-wrap gap-3">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <ArrowLeftRight className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">Movimientos</h1>
              <p className="text-sm text-surface-500">Traslados y ajustes de stock</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <button onClick={() => { setTrasladoOpen(true); setScanItems([]); setScanInput(""); }}
              className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200">
              <Scan className="w-4 h-4" />Traslado masivo
            </button>
            <button onClick={() => openModal("movimiento")}
              className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200">
              <ArrowLeftRight className="w-4 h-4" />Movimiento
            </button>
            <button onClick={() => openModal("ajuste")}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
              <SlidersHorizontal className="w-4 h-4" />Ajuste
            </button>
          </div>
        </div>

        {/* Listado */}
        <div className="card overflow-hidden">
          <div className="p-3 border-b border-surface-100">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
              <input className="w-full pl-9 pr-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg"
                placeholder="Buscar por artículo, tipo..." value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
          </div>
          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="w-6 h-6 text-brand-500 animate-spin" /></div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-surface-100 bg-surface-50">
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Fecha</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Tipo</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Artículo</th>
                    <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Cantidad</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Almacén</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Obra</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Usuario</th>
                  </tr>
                </thead>
                <tbody>
                  {filtered.map((m) => {
                    const badge = TIPO_BADGE[m.tipo] || { label: m.tipo, color: "bg-surface-100 text-surface-600" };
                    const almacen = m.almacen_destino?.nombre || m.almacen_origen?.nombre || "—";
                    const esSalida = m.tipo === "salida" || m.tipo === "traslado_salida";
                    return (
                      <tr key={m.id} className="border-b border-surface-50 hover:bg-surface-50/50">
                        <td className="px-4 py-2.5 text-xs text-surface-500 font-mono whitespace-nowrap">
                          {new Date(m.fecha).toLocaleDateString("es-ES")}
                        </td>
                        <td className="px-4 py-2.5">
                          <span className={cn("badge text-[10px]", badge.color)}>{badge.label}</span>
                        </td>
                        <td className="px-4 py-2.5">
                          <div className="flex items-center gap-2">
                            <FotoArticulo url={m.articulo?.foto_url} nombre={m.articulo?.nombre} size="sm" />
                            <div>
                              <div className="font-medium text-surface-900 text-xs">{m.articulo?.nombre || "—"}</div>
                              <div className="text-surface-400 text-[10px] font-mono">{m.articulo?.codigo_articulo}</div>
                            </div>
                          </div>
                        </td>
                        <td className="px-4 py-2.5 text-right">
                          <span className={cn("font-mono text-sm font-semibold",
                            esSalida ? "text-red-600" : "text-emerald-700")}>
                            {esSalida ? "−" : "+"}{m.cantidad}
                          </span>
                        </td>
                        <td className="px-4 py-2.5 text-xs text-surface-600 hidden md:table-cell">{almacen}</td>
                        <td className="px-4 py-2.5 text-xs text-surface-600 hidden lg:table-cell">{m.obra?.nombre || "—"}</td>
                        <td className="px-4 py-2.5 text-xs text-surface-500 hidden lg:table-cell">{m.user?.nombre || "—"}</td>
                      </tr>
                    );
                  })}
                  {filtered.length === 0 && (
                    <tr><td colSpan={7} className="text-center py-12 text-sm text-surface-400">Sin movimientos</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {/* Modal: Movimiento (traslado entre almacenes) */}
      <Modal open={modalOpen && tipoForm === "movimiento"} onClose={() => setModalOpen(false)} title="Nuevo movimiento" size="md">
        <form onSubmit={handleSave} className="space-y-3">
          <p className="text-xs text-surface-500 bg-surface-50 rounded-lg px-3 py-2">
            El stock se resta del almacén origen y se suma en el almacén destino.
          </p>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Artículo *</label>
            <select required className={ic} value={movForm.articulo_id}
              onChange={(e) => setMovForm({ ...movForm, articulo_id: e.target.value })}>
              <option value="">Seleccionar artículo...</option>
              {articulos.map((a) => (
                <option key={a.id} value={a.id}>{a.nombre} — {a.codigo_articulo}</option>
              ))}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Almacén origen *</label>
              <select required className={ic} value={movForm.almacen_origen_id}
                onChange={(e) => setMovForm({ ...movForm, almacen_origen_id: e.target.value })}>
                <option value="">Seleccionar...</option>
                {almacenes.map((a) => <option key={a.id} value={a.id}>{a.nombre}</option>)}
              </select>
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Almacén destino *</label>
              <select required className={ic} value={movForm.almacen_destino_id}
                onChange={(e) => setMovForm({ ...movForm, almacen_destino_id: e.target.value })}>
                <option value="">Seleccionar...</option>
                {almacenes.filter((a) => a.id !== movForm.almacen_origen_id).map((a) => (
                  <option key={a.id} value={a.id}>{a.nombre}</option>
                ))}
              </select>
            </div>
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-1">Cantidad *</label>
            <input required type="number" min="0.001" step="0.001" className={ic}
              value={movForm.cantidad} onChange={(e) => setMovForm({ ...movForm, cantidad: e.target.value })} />
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Observaciones</label>
            <input className={ic} value={movForm.observaciones}
              onChange={(e) => setMovForm({ ...movForm, observaciones: e.target.value })} />
          </div>
          {error && <p className="text-xs text-red-600">{error}</p>}
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setModalOpen(false)}
              className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {saving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}Registrar movimiento
            </button>
          </div>
        </form>
      </Modal>

      {/* Modal: Ajuste */}
      <Modal open={modalOpen && tipoForm === "ajuste"} onClose={() => setModalOpen(false)} title="Ajuste de stock" size="md">
        <form onSubmit={handleSave} className="space-y-3">
          <p className="text-xs text-surface-500 bg-surface-50 rounded-lg px-3 py-2">
            Corrección de stock. Queda registrado con motivo y usuario.
          </p>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Artículo *</label>
            <select required className={ic} value={ajForm.articulo_id}
              onChange={(e) => setAjForm({ ...ajForm, articulo_id: e.target.value })}>
              <option value="">Seleccionar artículo...</option>
              {articulos.map((a) => <option key={a.id} value={a.id}>{a.nombre} — {a.codigo_articulo}</option>)}
            </select>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Almacén *</label>
            <select required className={ic} value={ajForm.almacen_id}
              onChange={(e) => setAjForm({ ...ajForm, almacen_id: e.target.value })}>
              <option value="">Seleccionar almacén...</option>
              {almacenes.map((a) => <option key={a.id} value={a.id}>{a.nombre}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-1">Tipo de ajuste</label>
            <div className="flex gap-2">
              <button type="button" onClick={() => setAjForm({ ...ajForm, sentido: "+" })}
                className={cn("flex-1 py-2 text-sm font-semibold rounded-lg border transition-colors",
                  ajForm.sentido === "+" ? "border-emerald-500 bg-emerald-50 text-emerald-700" : "border-surface-200 text-surface-600 hover:bg-surface-50")}>
                + Aumentar stock
              </button>
              <button type="button" onClick={() => setAjForm({ ...ajForm, sentido: "-" })}
                className={cn("flex-1 py-2 text-sm font-semibold rounded-lg border transition-colors",
                  ajForm.sentido === "-" ? "border-red-500 bg-red-50 text-red-700" : "border-surface-200 text-surface-600 hover:bg-surface-50")}>
                − Reducir stock
              </button>
            </div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Cantidad *</label>
            <input required type="number" min="0.001" step="0.001" className={ic}
              value={ajForm.cantidad} onChange={(e) => setAjForm({ ...ajForm, cantidad: e.target.value })}
              placeholder="Siempre positiva" />
            <p className="text-[10px] text-surface-400 mt-1">
              El ajuste {ajForm.sentido === "+" ? "sumará" : "restará"} <span className="font-semibold font-mono">{ajResultado}</span> unidades al stock actual.
            </p>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Motivo *</label>
            <input required className={ic} value={ajForm.motivo}
              onChange={(e) => setAjForm({ ...ajForm, motivo: e.target.value })}
              placeholder="Conteo físico, rotura, error de registro..." />
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Observaciones</label>
            <input className={ic} value={ajForm.observaciones}
              onChange={(e) => setAjForm({ ...ajForm, observaciones: e.target.value })} />
          </div>
          {error && <p className="text-xs text-red-600">{error}</p>}
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setModalOpen(false)}
              className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {saving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}Registrar ajuste
            </button>
          </div>
        </form>
      </Modal>

      {/* Modal: traslado masivo con scan */}
      <Modal open={trasladoOpen} onClose={() => setTrasladoOpen(false)} title="Traslado masivo" size="lg">
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Almacén origen *</label>
              <select className={ic} value={trasladoForm.almacen_origen_id}
                onChange={(e) => setTrasladoForm({ ...trasladoForm, almacen_origen_id: e.target.value })}>
                <option value="">Seleccionar...</option>
                {almacenes.map((a) => <option key={a.id} value={a.id}>{a.nombre}</option>)}
              </select>
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Almacén destino *</label>
              <select className={ic} value={trasladoForm.almacen_destino_id}
                onChange={(e) => setTrasladoForm({ ...trasladoForm, almacen_destino_id: e.target.value })}>
                <option value="">Seleccionar...</option>
                {almacenes.filter((a) => a.id !== trasladoForm.almacen_origen_id).map((a) => (
                  <option key={a.id} value={a.id}>{a.nombre}</option>
                ))}
              </select>
            </div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Obra (opcional)</label>
            <select className={ic} value={trasladoForm.obra_id}
              onChange={(e) => setTrasladoForm({ ...trasladoForm, obra_id: e.target.value })}>
              <option value="">Sin obra</option>
              {obras.map((o) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
            </select>
          </div>
          <div className="border-t border-surface-100 pt-4">
            <p className="text-xs font-semibold text-surface-600 mb-2">Escanear artículos</p>
            <form onSubmit={handleScan} className="flex gap-2">
              <div className="relative flex-1">
                <Scan className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
                <input ref={scanRef} autoFocus
                  className={cn(ic, "pl-9", scanNotFound && "border-red-400 bg-red-50")}
                  placeholder="Código de barras..."
                  value={scanInput}
                  onChange={(e) => { setScanInput(e.target.value); setScanNotFound(false); }} />
              </div>
              <button type="submit" className="px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
                Añadir
              </button>
            </form>
            {scanNotFound && <p className="text-xs text-red-600 mt-1">Artículo no encontrado</p>}
          </div>
          {scanItems.length > 0 && (
            <div className="border border-surface-200 rounded-lg overflow-hidden">
              <div className="bg-surface-50 px-3 py-2 text-xs font-semibold text-surface-600">
                {scanItems.length} artículos
              </div>
              <div className="max-h-48 overflow-y-auto">
                {scanItems.map((item, i) => (
                  <div key={i} className="flex items-center gap-3 px-3 py-2 border-b border-surface-50 last:border-0">
                    <FotoArticulo url={item.articulo.foto_url} nombre={item.articulo.nombre} size="sm" />
                    <div className="flex-1 min-w-0">
                      <p className="text-xs font-medium text-surface-900 truncate">{item.articulo.nombre}</p>
                      <p className="text-[10px] text-surface-400 font-mono">{item.articulo.codigo_articulo}</p>
                    </div>
                    <div className="flex items-center gap-1">
                      <button onClick={() => setScanItems((p) => p.map((s, j) => j === i ? { ...s, cantidad: Math.max(1, s.cantidad - 1) } : s))}
                        className="w-6 h-6 rounded flex items-center justify-center bg-surface-100 hover:bg-surface-200 text-xs font-bold">−</button>
                      <span className="w-8 text-center text-sm font-mono">{item.cantidad}</span>
                      <button onClick={() => setScanItems((p) => p.map((s, j) => j === i ? { ...s, cantidad: s.cantidad + 1 } : s))}
                        className="w-6 h-6 rounded flex items-center justify-center bg-surface-100 hover:bg-surface-200 text-xs font-bold">+</button>
                    </div>
                    <button onClick={() => setScanItems((p) => p.filter((_, j) => j !== i))}
                      className="p-1 text-surface-300 hover:text-red-500"><X className="w-3.5 h-3.5" /></button>
                  </div>
                ))}
              </div>
            </div>
          )}
          <div className="flex justify-end gap-2">
            <button onClick={() => setTrasladoOpen(false)}
              className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button onClick={handleTraslado}
              disabled={trasladoSaving || !scanItems.length || !trasladoForm.almacen_origen_id || !trasladoForm.almacen_destino_id}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {trasladoSaving ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <CheckCircle2 className="w-3.5 h-3.5" />}
              Confirmar ({scanItems.reduce((s, i) => s + i.cantidad, 0)} uds)
            </button>
          </div>
        </div>
      </Modal>
    </AppLayout>
  );
}
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\almacen\movimientos\page.tsx" -ForegroundColor Green

Write-Host ""
Write-Host "==> Verificando" -ForegroundColor Cyan
$ok1 = Test-Path (Join-Path $RepoPath "src\components\shared\FotoArticulo.tsx")
$ok2 = Select-String -Path "src\app\almacen\articulos\page.tsx" -Pattern "detalleOpen\|detalleTab" -Quiet
$ok3 = Select-String -Path "src\app\almacen\almacenes\[id]\page.tsx" -Pattern "dias_en_almacen\|v_stock_actual_ext" -Quiet
if ($ok1) { Write-Host "    OK: FotoArticulo.tsx" -ForegroundColor Green } else { Write-Host "    ERROR: FotoArticulo" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: modal detalle en articulos" -ForegroundColor Green } else { Write-Host "    ERROR: modal detalle" -ForegroundColor Red }
if ($ok3) { Write-Host "    OK: dias en almacen" -ForegroundColor Green } else { Write-Host "    ERROR: dias en almacen" -ForegroundColor Red }
Write-Host ""
Write-Host "RECORDATORIO: ejecutar 036_articulos_mantenimiento.sql en Supabase" -ForegroundColor Yellow
Write-Host ""
Write-Host '  git add -A'
Write-Host '  git commit -m "feat: detalle articulo, hover foto, dias en almacen, mantenimiento maquinaria"'
Write-Host '  git push'
