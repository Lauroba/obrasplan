#Requires -Version 5.1
# fix-isadmin-masivo-v2.ps1
# Generado sobre el repo actual (commit d573d94) — SEGURO de ejecutar.
# Corrige 18 archivos con isAdmin hardcodeado, sin tocar los 5 que
# ya estaban bien (contactos-leyna, vehiculos, obras/page, planificacion,
# almacen/almacenes/[id]).
#
# CAMBIO: user?.role === "admin" -> usePermissions() -> isAdmin/canDo()
# Cada pantalla tiene puedeCrear/puedeEditar/puedeEliminar basados en
# los permisos configurados en Configuracion -> Roles y permisos.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR: No se encuentra el repo" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host ""
Write-Host "==> Aplicando fix isAdmin masivo (18 archivos)" -ForegroundColor Cyan
Write-Host "    Basado en commit actual d573d94 - seguro de ejecutar"
Write-Host ""
Write-Host "  -> src\app\almacen\almacenes\page.tsx" -ForegroundColor Gray
$dst = "src\app\almacen\almacenes\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import {
  Warehouse, Loader2, Search, Plus, Pencil, Building2,
  ChevronRight, AlertTriangle, TrendingDown, Package,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";

const empty = { codigo_almacen: "", nombre: "", ubicacion: "", es_almacen_obra: false, obra_id: "" };
const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

function StockBadge({ label, value, warn }: { label: string; value: number; warn?: boolean }) {
  if (value === 0) return null;
  return (
    <span className={cn(
      "inline-flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-mono font-medium",
      warn ? "bg-red-100 text-red-700" : "bg-surface-100 text-surface-600"
    )}>
      {warn && <AlertTriangle className="w-2.5 h-2.5" />}
      {label}: {Number(value).toFixed(0)}
    </span>
  );
}

export default function AlmacenesPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("almacen_almacenes", "crear");
  const puedeEditar   = isAdmin || canDo("almacen_almacenes", "editar");
  const puedeEliminar = isAdmin || canDo("almacen_almacenes", "eliminar");

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
    const [rRes, oRes] = await Promise.all([
      // Usamos v_resumen_almacenes para obtener sumatorios directamente
      (supabase.from("v_resumen_almacenes") as any).select("*").order("nombre"),
      (supabase.from("obras") as any).select("id, nombre").order("nombre"),
    ]);
    setData(rRes.data || []);
    setObras(oRes.data || []);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const filtered = data.filter((a) =>
    a.nombre?.toLowerCase().includes(search.toLowerCase()) ||
    a.codigo_almacen?.toLowerCase().includes(search.toLowerCase()) ||
    a.obra_nombre?.toLowerCase().includes(search.toLowerCase())
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

  const toggleActivo = async (almacen: any) => {
    if (!confirm(`¿${almacen.activo ? "Desactivar" : "Activar"} el almacén "${almacen.nombre}"?`)) return;
    await (supabase.from("almacenes") as any).update({ activo: !almacen.activo }).eq("id", almacen.almacen_id);
    fetchData();
  };

  const openNew = () => { setForm(empty); setEditId(null); setError(null); setModalOpen(true); };
  const openEdit = (a: any) => {
    setForm({ codigo_almacen: a.codigo_almacen || "", nombre: a.nombre || "", ubicacion: a.ubicacion || "", es_almacen_obra: a.es_almacen_obra || false, obra_id: a.obra_id || "" });
    setEditId(a.almacen_id); setError(null); setModalOpen(true);
  };

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
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
          {isAdmin && (
            <button onClick={openNew} className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
              <Plus className="w-4 h-4" />Nuevo almacén
            </button>
          )}
        </div>

        <div className="card overflow-hidden">
          <div className="p-3 border-b border-surface-100">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
              <input className="w-full pl-9 pr-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20" placeholder="Buscar almacén u obra..." value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
          </div>

          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="w-6 h-6 text-brand-500 animate-spin" /></div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-12 text-sm text-surface-400">Sin almacenes</div>
          ) : (
            <div className="divide-y divide-surface-50">
              {filtered.map((a) => {
                const hasAlerts = a.num_negativos > 0 || a.num_bajo_minimo > 0;
                return (
                  <div key={a.almacen_id} className={cn(
                    "flex items-center gap-4 px-4 py-3 hover:bg-surface-50/50 transition-colors",
                    !a.activo && "opacity-50"
                  )}>
                    {/* Icono tipo */}
                    <div className={cn("w-9 h-9 rounded-lg flex items-center justify-center shrink-0",
                      a.es_almacen_obra ? "bg-brand-50" : "bg-surface-100")}>
                      {a.es_almacen_obra
                        ? <Building2 className="w-4 h-4 text-brand-600" />
                        : <Warehouse className="w-4 h-4 text-surface-500" />}
                    </div>

                    {/* Info principal */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-medium text-surface-900 text-sm">{a.nombre}</span>
                        <span className="font-mono text-[10px] text-surface-400">{a.codigo_almacen}</span>
                        {a.es_almacen_obra && (
                          <span className="badge text-[10px] bg-brand-50 text-brand-600">{a.obra_nombre || "Obra"}</span>
                        )}
                        {!a.activo && <span className="badge text-[10px] bg-surface-100 text-surface-400">Inactivo</span>}
                      </div>
                      {a.ubicacion && <p className="text-xs text-surface-500 mt-0.5">{a.ubicacion}</p>}

                      {/* Sumatorios de stock */}
                      {a.num_articulos > 0 && (
                        <div className="flex items-center gap-1.5 mt-1.5 flex-wrap">
                          <span className="text-[10px] text-surface-400">{a.num_articulos} artículos</span>
                          <span className="text-surface-200">·</span>
                          <StockBadge label="Mat" value={a.stock_material} />
                          <StockBadge label="Maq" value={a.stock_maquinaria} />
                          <StockBadge label="Veh" value={a.stock_vehiculo} />
                          <StockBadge label="Otros" value={a.stock_otro} />
                          {hasAlerts && (
                            <span className="flex items-center gap-1 text-[10px] text-red-600 font-medium">
                              <AlertTriangle className="w-2.5 h-2.5" />
                              {a.num_negativos > 0 && `${a.num_negativos} neg.`}
                              {a.num_negativos > 0 && a.num_bajo_minimo > 0 && " · "}
                              {a.num_bajo_minimo > 0 && `${a.num_bajo_minimo} bajo mín.`}
                            </span>
                          )}
                        </div>
                      )}
                      {a.num_articulos === 0 && (
                        <p className="text-[10px] text-surface-300 mt-1">Sin stock registrado</p>
                      )}
                    </div>

                    {/* Stock total */}
                    {a.num_articulos > 0 && (
                      <div className="text-right shrink-0 hidden sm:block">
                        <div className={cn("text-lg font-bold font-mono",
                          a.stock_total < 0 ? "text-red-600" : "text-surface-900")}>
                          {Number(a.stock_total).toFixed(0)}
                        </div>
                        <div className="text-[10px] text-surface-400">total uds</div>
                      </div>
                    )}

                    {/* Acciones */}
                    <div className="flex items-center gap-1 shrink-0">
                      {isAdmin && (
                        <>
                          <button onClick={() => openEdit(a)} title="Editar" className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100">
                            <Pencil className="w-3.5 h-3.5" />
                          </button>
                          <button onClick={() => toggleActivo(a)} title={a.activo ? "Desactivar" : "Activar"}
                            className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100 text-xs font-medium">
                            {a.activo ? "·" : "○"}
                          </button>
                        </>
                      )}
                      <Link href={`/almacen/almacenes/${a.almacen_id}`}
                        className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100 hover:text-brand-600 transition-colors">
                        <ChevronRight className="w-4 h-4" />
                      </Link>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editId ? "Editar almacén" : "Nuevo almacén"} size="md">
        <form onSubmit={handleSave} className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Código almacén *</label>
              <input required className={ic} value={form.codigo_almacen} onChange={(e) => setForm({ ...form, codigo_almacen: e.target.value.toUpperCase() })} placeholder="ALM01" />
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Nombre *</label>
              <input required className={ic} value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} />
            </div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Ubicación</label>
            <input className={ic} value={form.ubicacion} onChange={(e) => setForm({ ...form, ubicacion: e.target.value })} />
          </div>
          <div className="flex items-center gap-2">
            <input type="checkbox" id="es_obra" checked={form.es_almacen_obra}
              onChange={(e) => setForm({ ...form, es_almacen_obra: e.target.checked, obra_id: e.target.checked ? form.obra_id : "" })} className="w-4 h-4" />
            <label htmlFor="es_obra" className="text-sm text-surface-700">Es almacén de obra</label>
          </div>
          {form.es_almacen_obra && (
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Obra asociada</label>
              <select className={ic} value={form.obra_id} onChange={(e) => setForm({ ...form, obra_id: e.target.value })}>
                <option value="">Sin obra</option>
                {obras.map((o) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
              </select>
            </div>
          )}
          {error && <p className="text-xs text-red-600">{error}</p>}
          <div className="flex justify-end gap-2 pt-1">
            <button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
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
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\almacen\articulos\page.tsx" -ForegroundColor Gray
$dst = "src\app\almacen\articulos\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback, useRef } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { FotoArticulo } from "@/components/shared/FotoArticulo";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
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
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("almacen_articulos", "crear");
  const puedeEditar   = isAdmin || canDo("almacen_articulos", "editar");
  const puedeEliminar = isAdmin || canDo("almacen_articulos", "eliminar");
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
    const [aR, pR, tR, scR] = await Promise.all([
      (supabase.from("articulos") as any)
        .select("*, proveedor:proveedores(nombre), tipo_art:tipos_articulo(id,nombre,activo,orden)")
        .eq("activo", true).order("nombre"),
      (supabase.from("proveedores") as any).select("id, nombre").eq("activo", true).order("nombre"),
      (supabase.from("tipos_articulo") as any).select("id, nombre, activo, orden").order("orden").order("nombre"),
      // Stock total por artículo desde stock_cache (incluye negativos)
      (supabase.from("stock_cache") as any).select("articulo_id, stock_qty"),
    ]);
    // Agrupar stock por articulo_id (sumando todos los almacenes)
    const stockMap: Record<string, number> = {};
    for (const row of (scR.data || [])) {
      stockMap[row.articulo_id] = (stockMap[row.articulo_id] || 0) + Number(row.stock_qty);
    }
    // Inyectar stock_total en cada artículo
    const articulos = (aR.data || []).map((a: any) => ({
      ...a,
      stock_total: stockMap[a.id] !== undefined ? stockMap[a.id] : null,
    }));
    setData(articulos);
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
        .neq("stock_qty", 0)
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
          .neq("stock_qty", 0)
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
                    <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Stock</th>
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
                      <td className="px-4 py-2.5 text-right">
                        {a.stock_total !== null ? (
                          <span className={cn("font-mono text-xs font-semibold",
                            a.stock_total < 0 ? "text-red-600" :
                            a.stock_total === 0 ? "text-surface-300" : "text-emerald-700")}>
                            {Number(a.stock_total).toFixed(2)}
                          </span>
                        ) : (
                          <span className="text-surface-300 text-xs">—</span>
                        )}
                      </td>
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
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\almacen\etiquetas\page.tsx" -ForegroundColor Gray
$dst = "src\app\almacen\etiquetas\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback, useRef } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
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
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("almacen_etiquetas", "crear");
  const puedeEditar   = isAdmin || canDo("almacen_etiquetas", "editar");
  const puedeEliminar = isAdmin || canDo("almacen_etiquetas", "eliminar");

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
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\almacen\proveedores\page.tsx" -ForegroundColor Gray
$dst = "src\app\almacen\proveedores\page.tsx"
$content = @'
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
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\almacen\tipos-articulo\page.tsx" -ForegroundColor Gray
$dst = "src\app\almacen\tipos-articulo\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import { Tag, Loader2, Search, Plus, Pencil, Trash2, AlertTriangle } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";

const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";
const emptyForm = { nombre: "", descripcion: "", activo: true, orden: 0 };

export default function TiposArticuloPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("almacen_tipos_articulo", "crear");
  const puedeEditar   = isAdmin || canDo("almacen_tipos_articulo", "editar");
  const puedeEliminar = isAdmin || canDo("almacen_tipos_articulo", "eliminar");

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
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\maestros\clientes\page.tsx" -ForegroundColor Gray
$dst = "src\app\maestros\clientes\page.tsx"
$content = @'
"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import { Contact, Plus, Loader2, Pencil, Trash2, Users, Phone, Mail, Globe, Building2, ChevronDown, ChevronRight, FileText, Download } from "lucide-react";
import { cn } from "@/lib/utils/cn";

const TIPOS_CLIENTE = ["Empresa", "Comunidad", "Administración", "Constructora", "Particular", "Otro"];
const emptyCliente = { nombre: "", tipo_cliente: "", nif: "", telefono: "", email: "", direccion: "", web: "" };
const emptyContacto = { nombre: "", email: "", telefono: "", cargo: "", notas: "" };

export default function ClientesPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("maestros_clientes", "crear");
  const puedeEditar   = isAdmin || canDo("maestros_clientes", "editar");
  const puedeEliminar = isAdmin || canDo("maestros_clientes", "eliminar");
  const [clientes, setClientes] = useState<any[]>([]);
  const [contactos, setContactos] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  // Modals
  const [clienteModal, setClienteModal] = useState(false);
  const [clienteForm, setClienteForm] = useState(emptyCliente);
  const [editingClienteId, setEditingClienteId] = useState<string | null>(null);
  const [contactoModal, setContactoModal] = useState(false);
  const [contactoForm, setContactoForm] = useState(emptyContacto);
  const [editingContactoId, setEditingContactoId] = useState<string | null>(null);
  const [contactoClienteId, setContactoClienteId] = useState<string>("");
  const [saving, setSaving] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [cR, ctR] = await Promise.all([
      supabase.from("clientes").select("*").eq("activo", true).order("nombre"),
      supabase.from("contactos").select("*").order("nombre"),
    ]);
    setClientes(cR.data || []);
    setContactos(ctR.data || []);
    setLoading(false);
  }, []);
  useEffect(() => { fetchData(); }, [fetchData]);

  const clienteContactos = (clienteId: string) => contactos.filter((c) => c.cliente_id === clienteId);

  const handleSaveCliente = async (e: React.FormEvent) => {
    e.preventDefault(); setSaving(true);
    const payload = { ...clienteForm };
    Object.keys(payload).forEach((k) => { if (!(payload as any)[k]) (payload as any)[k] = null; });
    if (editingClienteId) await (supabase.from("clientes") as any).update(payload).eq("id", editingClienteId);
    else await (supabase.from("clientes") as any).insert({ ...payload, activo: true });
    setSaving(false); setClienteModal(false); fetchData();
  };

  const handleSaveContacto = async (e: React.FormEvent) => {
    e.preventDefault(); setSaving(true);
    const payload = { ...contactoForm, cliente_id: contactoClienteId };
    Object.keys(payload).forEach((k) => { if (!(payload as any)[k]) (payload as any)[k] = null; });
    (payload as any).cliente_id = contactoClienteId; // ensure not null
    if (editingContactoId) await (supabase.from("contactos") as any).update(payload).eq("id", editingContactoId);
    else await (supabase.from("contactos") as any).insert({ ...payload, activo: true });
    setSaving(false); setContactoModal(false); fetchData();
  };

  const handleDeleteCliente = async (id: string) => {
    if (!confirm("¿Desactivar este cliente?")) return;
    await (supabase.from("clientes") as any).update({ activo: false }).eq("id", id);
    fetchData();
  };

  const handleToggleContacto = async (id: string, activo: boolean) => {
    await (supabase.from("contactos") as any).update({ activo: !activo }).eq("id", id);
    fetchData();
  };

  const filtered = clientes.filter((c) => !search || c.nombre?.toLowerCase().includes(search.toLowerCase()) || c.nif?.toLowerCase().includes(search.toLowerCase()));

  const ic = "w-full px-3 py-2 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500";

  if (loading) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;

  return (
    <AppLayout>
      <div className="max-w-5xl mx-auto animate-fade-in">
        {/* Header */}
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-blue-50 flex items-center justify-center"><Contact className="w-5 h-5 text-blue-600" /></div>
            <div><h1 className="text-xl font-display font-bold text-surface-900">Clientes</h1><p className="text-sm text-surface-500">{filtered.length} clientes · {contactos.length} contactos</p></div>
          </div>
          <div className="flex gap-2">
            <a href="/api/informes/clientes?format=pdf" target="_blank" className="flex items-center gap-1 px-3 py-2 text-xs font-medium text-violet-700 bg-violet-50 rounded-lg hover:bg-violet-100"><Download className="w-3.5 h-3.5" />PDF</a>
            {isAdmin && <button onClick={() => { setClienteForm(emptyCliente); setEditingClienteId(null); setClienteModal(true); }} className="flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-4 h-4" />Nuevo cliente</button>}
          </div>
        </div>

        {/* Search */}
        <div className="mb-4"><input type="text" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Buscar cliente por nombre o CIF/NIF..." className={ic} /></div>

        {/* Client list with expandable contacts */}
        <div className="space-y-2">
          {filtered.map((cliente) => {
            const cts = clienteContactos(cliente.id);
            const isExpanded = expanded[cliente.id];
            return (
              <div key={cliente.id} className="card overflow-hidden">
                {/* Client row */}
                <div className="flex items-center gap-3 p-4 cursor-pointer hover:bg-surface-50" onClick={() => setExpanded((p) => ({ ...p, [cliente.id]: !isExpanded }))}>
                  <button className="text-surface-400">{isExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}</button>
                  <div className="w-9 h-9 rounded-lg bg-blue-100 flex items-center justify-center shrink-0"><Building2 className="w-4 h-4 text-blue-600" /></div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-surface-900">{cliente.nombre}</span>
                      {cliente.tipo_cliente && <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-surface-100 text-surface-500">{cliente.tipo_cliente}</span>}
                      {cliente.nif && <span className="text-[10px] font-mono text-surface-400">{cliente.nif}</span>}
                    </div>
                    <div className="flex items-center gap-3 text-xs text-surface-500 mt-0.5">
                      {cliente.telefono && <span className="flex items-center gap-0.5"><Phone className="w-3 h-3" />{cliente.telefono}</span>}
                      {cliente.email && <span className="flex items-center gap-0.5"><Mail className="w-3 h-3" />{cliente.email}</span>}
                      {cliente.web && <span className="flex items-center gap-0.5"><Globe className="w-3 h-3" />{cliente.web}</span>}
                    </div>
                  </div>
                  <span className="text-xs text-surface-400">{cts.length} contacto{cts.length !== 1 ? "s" : ""}</span>
                  {isAdmin && (
                    <div className="flex gap-1" onClick={(e) => e.stopPropagation()}>
                      <button onClick={() => { setClienteForm({ nombre: cliente.nombre, tipo_cliente: cliente.tipo_cliente || "", nif: cliente.nif || "", telefono: cliente.telefono || "", email: cliente.email || "", direccion: cliente.direccion || "", web: cliente.web || "" }); setEditingClienteId(cliente.id); setClienteModal(true); }} className="p-1.5 text-surface-400 hover:text-brand-600 rounded-lg hover:bg-surface-100"><Pencil className="w-3.5 h-3.5" /></button>
                      <button onClick={() => handleDeleteCliente(cliente.id)} className="p-1.5 text-surface-400 hover:text-red-600 rounded-lg hover:bg-red-50"><Trash2 className="w-3.5 h-3.5" /></button>
                    </div>
                  )}
                </div>

                {/* Contacts section */}
                {isExpanded && (
                  <div className="border-t border-surface-100 bg-surface-50/50 px-4 py-3">
                    <div className="flex items-center justify-between mb-2">
                      <p className="text-[10px] font-semibold text-surface-400 uppercase">Contactos</p>
                      {isAdmin && <button onClick={() => { setContactoForm(emptyContacto); setEditingContactoId(null); setContactoClienteId(cliente.id); setContactoModal(true); }} className="flex items-center gap-0.5 text-[10px] font-medium text-brand-600 hover:underline"><Plus className="w-3 h-3" />Añadir</button>}
                    </div>
                    {cts.length === 0 ? (
                      <p className="text-xs text-surface-400 py-2">Sin contactos</p>
                    ) : (
                      <div className="space-y-1.5">
                        {cts.map((ct) => (
                          <div key={ct.id} className={cn("flex items-center gap-3 p-2.5 bg-white rounded-lg border border-surface-100 group", !ct.activo && "opacity-50")}>
                            <div className="w-7 h-7 rounded-full bg-violet-100 flex items-center justify-center text-[10px] font-bold text-violet-700 shrink-0">{ct.nombre?.charAt(0)?.toUpperCase()}</div>
                            <div className="flex-1 min-w-0">
                              <span className={cn("text-sm font-medium", ct.activo ? "text-surface-900" : "text-surface-400 line-through")}>{ct.nombre}</span>
                              {ct.cargo && <span className="ml-2 text-[10px] text-surface-400">{ct.cargo}</span>}
                              <div className="flex items-center gap-3 text-[11px] text-surface-500 mt-0.5">
                                {ct.telefono && <span>{ct.telefono}</span>}
                                {ct.email && <span>{ct.email}</span>}
                              </div>
                              {ct.notas && <p className="text-[10px] text-surface-400 mt-0.5 italic">{ct.notas}</p>}
                            </div>
                            {isAdmin && (
                              <div className="flex gap-1 opacity-0 group-hover:opacity-100">
                                <button onClick={() => { setContactoForm({ nombre: ct.nombre, email: ct.email || "", telefono: ct.telefono || "", cargo: ct.cargo || "", notas: ct.notas || "" }); setEditingContactoId(ct.id); setContactoClienteId(ct.cliente_id); setContactoModal(true); }} className="p-1 text-surface-400 hover:text-brand-600"><Pencil className="w-3 h-3" /></button>
                                <button onClick={() => handleToggleContacto(ct.id, ct.activo)} className={cn("p-1", ct.activo ? "text-surface-400 hover:text-red-500" : "text-emerald-400 hover:text-emerald-600")}>{ct.activo ? <Trash2 className="w-3 h-3" /> : <Plus className="w-3 h-3" />}</button>
                              </div>
                            )}
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* Cliente Modal */}
      <Modal open={clienteModal} onClose={() => setClienteModal(false)} title={editingClienteId ? "Editar cliente" : "Nuevo cliente"}>
        <form onSubmit={handleSaveCliente} className="space-y-4">
          <div><label className="block text-sm font-medium text-surface-700 mb-1">Nombre *</label><input required value={clienteForm.nombre} onChange={(e) => setClienteForm({ ...clienteForm, nombre: e.target.value })} className={ic} /></div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Tipo</label><select value={clienteForm.tipo_cliente} onChange={(e) => setClienteForm({ ...clienteForm, tipo_cliente: e.target.value })} className={ic}><option value="">Sin tipo</option>{TIPOS_CLIENTE.map((t) => <option key={t} value={t}>{t}</option>)}</select></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1">CIF/NIF</label><input value={clienteForm.nif} onChange={(e) => setClienteForm({ ...clienteForm, nif: e.target.value })} placeholder="B12345678" className={ic} /></div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Teléfono</label><input value={clienteForm.telefono} onChange={(e) => setClienteForm({ ...clienteForm, telefono: e.target.value })} className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Email</label><input type="email" value={clienteForm.email} onChange={(e) => setClienteForm({ ...clienteForm, email: e.target.value })} className={ic} /></div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Dirección</label><input value={clienteForm.direccion} onChange={(e) => setClienteForm({ ...clienteForm, direccion: e.target.value })} className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Web</label><input value={clienteForm.web} onChange={(e) => setClienteForm({ ...clienteForm, web: e.target.value })} placeholder="www.ejemplo.com" className={ic} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <button type="button" onClick={() => setClienteModal(false)} className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving || !clienteForm.nombre} className="flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingClienteId ? "Guardar" : "Crear"}</button>
          </div>
        </form>
      </Modal>

      {/* Contacto Modal */}
      <Modal open={contactoModal} onClose={() => setContactoModal(false)} title={editingContactoId ? "Editar contacto" : "Nuevo contacto"}>
        <form onSubmit={handleSaveContacto} className="space-y-4">
          <div><label className="block text-sm font-medium text-surface-700 mb-1">Nombre *</label><input required value={contactoForm.nombre} onChange={(e) => setContactoForm({ ...contactoForm, nombre: e.target.value })} className={ic} /></div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Email</label><input type="email" value={contactoForm.email} onChange={(e) => setContactoForm({ ...contactoForm, email: e.target.value })} className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Teléfono</label><input value={contactoForm.telefono} onChange={(e) => setContactoForm({ ...contactoForm, telefono: e.target.value })} className={ic} /></div>
          </div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1">Cargo</label><input value={contactoForm.cargo} onChange={(e) => setContactoForm({ ...contactoForm, cargo: e.target.value })} placeholder="Director técnico, Administrador..." className={ic} /></div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1">Notas</label><textarea value={contactoForm.notas} onChange={(e) => setContactoForm({ ...contactoForm, notas: e.target.value })} rows={2} className={ic + " resize-none"} /></div>
          <div className="flex justify-end gap-2 pt-2">
            <button type="button" onClick={() => setContactoModal(false)} className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving || !contactoForm.nombre} className="flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingContactoId ? "Guardar" : "Crear"}</button>
          </div>
        </form>
      </Modal>
    </AppLayout>
  );
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\maestros\estados-obra\page.tsx" -ForegroundColor Gray
$dst = "src\app\maestros\estados-obra\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { EstadoObra } from "@/lib/types/database";
import { Tag, Loader2 } from "lucide-react";

const COLORS = ["#3B82F6","#F59E0B","#8B5CF6","#EF4444","#22C55E","#EC4899","#06B6D4","#F97316","#6366F1","#14B8A6","#A855F7","#84CC16","#E11D48","#0EA5E9","#D946EF"];
const emptyForm = { nombre: "", color: "#3B82F6" };

export default function EstadosObraPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<EstadoObra[]>([]); const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false); const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null); const [saving, setSaving] = useState(false);
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("maestros_estados", "crear");
  const puedeEditar   = isAdmin || canDo("maestros_estados", "editar");
  const puedeEliminar = isAdmin || canDo("maestros_estados", "eliminar");
  const supabase = createClient();

  const fetchData = useCallback(async () => {
    setLoading(true);
    const { data: r } = await supabase.from("estados_obra").select("*").eq("activo", true).order("nombre");
    setData(r || []); setLoading(false);
  }, []);
  useEffect(() => { fetchData(); }, [fetchData]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); setSaving(true);
    if (editingId) await supabase.from("estados_obra").update(form as any).eq("id", editingId);
    else await supabase.from("estados_obra").insert(form as any);
    setSaving(false); setModalOpen(false); fetchData();
  };

  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  const columns: Column<EstadoObra>[] = [
    { key: "nombre", header: "Estado", render: (item) => (
      <div className="flex items-center gap-3">
        <div className="w-4 h-4 rounded-full shrink-0" style={{ backgroundColor: item.color }} />
        <span className="font-medium text-surface-900">{item.nombre}</span>
      </div>
    )},
    { key: "color", header: "Color", render: (item) => (
      <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium text-white" style={{ backgroundColor: item.color }}>{item.nombre}</span>
    )},
  ];

  return (
    <AppLayout><div className="max-w-7xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6">
        <div className="w-10 h-10 rounded-lg bg-violet-50 flex items-center justify-center"><Tag className="w-5 h-5 text-violet-600" /></div>
        <div><h1 className="text-xl font-display font-bold text-surface-900">Estados de Obra</h1><p className="text-sm text-surface-500">Personaliza los estados de tus obras</p></div>
      </div>
      <DataTable data={data} columns={columns} title="Estados" loading={loading}
        searchPlaceholder="Buscar..." searchKeys={["nombre"]}
        onAdd={isAdmin ? () => { setForm(emptyForm); setEditingId(null); setModalOpen(true); } : undefined}
        onEdit={isAdmin ? (i) => { setForm({ nombre: i.nombre, color: i.color }); setEditingId(i.id); setModalOpen(true); } : undefined}
        onDelete={isAdmin ? async (i) => { await supabase.from("estados_obra").update({ activo: false } as any).eq("id", i.id); fetchData(); } : undefined}
        addLabel="Nuevo estado" canAdd={isAdmin} canEdit={isAdmin} canDelete={isAdmin} />
      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar estado" : "Nuevo estado"} size="sm">
        <form onSubmit={handleSubmit} className="space-y-4">
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre *</label><input type="text" required value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="Ej: En reparo" className={ic} /></div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Color</label>
            <div className="flex flex-wrap gap-2">
              {COLORS.map((c) => (
                <button key={c} type="button" onClick={() => setForm({ ...form, color: c })}
                  className="w-8 h-8 rounded-full border-2 transition-all"
                  style={{ backgroundColor: c, borderColor: form.color === c ? c : "transparent", transform: form.color === c ? "scale(1.2)" : "scale(1)", boxShadow: form.color === c ? `0 0 0 3px ${c}30` : "none" }} />
              ))}
            </div>
            <div className="mt-2 flex items-center gap-2">
              <div className="w-6 h-6 rounded-full" style={{ backgroundColor: form.color }} />
              <span className="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium text-white" style={{ backgroundColor: form.color }}>{form.nombre || "Preview"}</span>
            </div>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving || !form.nombre} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingId ? "Guardar" : "Crear"}</button>
          </div>
        </form>
      </Modal>
    </div></AppLayout>
  );
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\maestros\maquinaria\page.tsx" -ForegroundColor Gray
$dst = "src\app\maestros\maquinaria\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import PhotoUpload from "@/components/shared/PhotoUpload";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { Maquinaria } from "@/lib/types/database";
import { Wrench, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils/cn";

const emptyForm: Partial<Maquinaria> = { nombre: "", tipo: "", estado: "disponible", observaciones: "", foto_url: "" };
const estadoColors: Record<string, string> = { disponible: "badge-en_curso", en_uso: "badge-pendiente", mantenimiento: "badge-rechazado", baja: "badge-cerrada" };

export default function MaquinariaPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<Maquinaria[]>([]); const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false); const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null); const [saving, setSaving] = useState(false);
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("maestros_maquinaria", "crear");
  const puedeEditar   = isAdmin || canDo("maestros_maquinaria", "editar");
  const puedeEliminar = isAdmin || canDo("maestros_maquinaria", "eliminar");
  const supabase = createClient();
  const fetchData = useCallback(async () => { setLoading(true); const { data: r } = await supabase.from("maquinaria").select("*").eq("activo", true).order("nombre"); setData(r || []); setLoading(false); }, []);
  useEffect(() => { fetchData(); }, [fetchData]);
  const handleSubmit = async (e: React.FormEvent) => { e.preventDefault(); setSaving(true); if (editingId) await supabase.from("maquinaria").update(form as any).eq("id", editingId); else await supabase.from("maquinaria").insert(form as any); setSaving(false); setModalOpen(false); fetchData(); };
  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  const columns: Column<Maquinaria>[] = [
    { key: "nombre", header: "Nombre", render: (item) => (
      <div className="flex items-center gap-3">
        {item.foto_url ? <img src={item.foto_url} alt="" className="w-8 h-8 rounded-full object-cover shrink-0" /> : <div className="w-8 h-8 rounded-full bg-amber-100 flex items-center justify-center shrink-0"><Wrench className="w-4 h-4 text-amber-600" /></div>}
        <span className="font-medium text-surface-900">{item.nombre}</span>
      </div>)},
    { key: "tipo", header: "Tipo" },
    { key: "estado", header: "Estado", render: (item) => <span className={cn("badge", estadoColors[item.estado])}>{item.estado.replace("_", " ")}</span> },
  ];
  return (
    <AppLayout><div className="max-w-7xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6"><div className="w-10 h-10 rounded-lg bg-amber-50 flex items-center justify-center"><Wrench className="w-5 h-5 text-amber-600" /></div><div><h1 className="text-xl font-display font-bold text-surface-900">Maquinaria</h1><p className="text-sm text-surface-500">Gestión de máquinas y equipos</p></div></div>
      <DataTable data={data} columns={columns} title="Maquinaria" loading={loading} searchPlaceholder="Buscar..." searchKeys={["nombre", "tipo"]}
        onAdd={isAdmin ? () => { setForm(emptyForm); setEditingId(null); setModalOpen(true); } : undefined}
        onEdit={isAdmin ? (i) => { setForm({ nombre: i.nombre, tipo: i.tipo || "", estado: i.estado, observaciones: i.observaciones || "", foto_url: i.foto_url || "" }); setEditingId(i.id); setModalOpen(true); } : undefined}
        onDelete={isAdmin ? async (i) => { await supabase.from("maquinaria").update({ activo: false } as any).eq("id", i.id); fetchData(); } : undefined}
        addLabel="Nueva máquina" canAdd={isAdmin} canEdit={isAdmin} canDelete={isAdmin} />
      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar máquina" : "Nueva máquina"}>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="flex items-start gap-4">
            <PhotoUpload currentUrl={form.foto_url || null} folder="maquinaria" entityId={editingId || undefined} size="md" onUploaded={(url) => setForm({ ...form, foto_url: url })} onRemoved={() => setForm({ ...form, foto_url: "" })} />
            <div className="flex-1 space-y-4">
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre *</label><input type="text" required value={form.nombre || ""} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="Ej: Retroexcavadora CAT 420F" className={ic} /></div>
              <div className="grid grid-cols-2 gap-4">
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Tipo</label><input type="text" value={form.tipo || ""} onChange={(e) => setForm({ ...form, tipo: e.target.value })} className={ic} /></div>
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Estado</label><select value={form.estado || "disponible"} onChange={(e) => setForm({ ...form, estado: e.target.value as any })} className={ic}><option value="disponible">Disponible</option><option value="en_uso">En uso</option><option value="mantenimiento">Mantenimiento</option><option value="baja">Baja</option></select></div>
              </div>
            </div>
          </div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Observaciones</label><textarea value={form.observaciones || ""} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} rows={2} className={ic + " resize-none"} /></div>
          <div className="flex justify-end gap-2 pt-2"><button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button><button type="submit" disabled={saving || !form.nombre} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingId ? "Guardar" : "Crear"}</button></div>
        </form>
      </Modal>
    </div></AppLayout>);
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\maestros\materiales\page.tsx" -ForegroundColor Gray
$dst = "src\app\maestros\materiales\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import PhotoUpload from "@/components/shared/PhotoUpload";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { Material } from "@/lib/types/database";
import { Package, Loader2 } from "lucide-react";

const emptyForm: Partial<Material> = { nombre: "", tipo: "", unidad: "", observaciones: "", foto_url: "" };

export default function MaterialesPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<Material[]>([]); const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false); const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null); const [saving, setSaving] = useState(false);
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("maestros_materiales", "crear");
  const puedeEditar   = isAdmin || canDo("maestros_materiales", "editar");
  const puedeEliminar = isAdmin || canDo("maestros_materiales", "eliminar");
  const supabase = createClient();
  const fetchData = useCallback(async () => { setLoading(true); const { data: r } = await supabase.from("materiales").select("*").eq("activo", true).order("nombre"); setData(r || []); setLoading(false); }, []);
  useEffect(() => { fetchData(); }, [fetchData]);
  const handleSubmit = async (e: React.FormEvent) => { e.preventDefault(); setSaving(true); if (editingId) await supabase.from("materiales").update(form as any).eq("id", editingId); else await supabase.from("materiales").insert(form as any); setSaving(false); setModalOpen(false); fetchData(); };
  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  const columns: Column<Material>[] = [
    { key: "nombre", header: "Nombre", render: (item) => (
      <div className="flex items-center gap-3">
        {item.foto_url ? <img src={item.foto_url} alt="" className="w-8 h-8 rounded-full object-cover shrink-0" /> : <div className="w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center shrink-0"><Package className="w-4 h-4 text-blue-600" /></div>}
        <span className="font-medium text-surface-900">{item.nombre}</span>
      </div>)},
    { key: "tipo", header: "Tipo" },
    { key: "unidad", header: "Unidad", render: (item) => item.unidad ? <span className="font-mono text-xs bg-surface-100 px-2 py-1 rounded">{item.unidad}</span> : "—" },
  ];
  return (
    <AppLayout><div className="max-w-7xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6"><div className="w-10 h-10 rounded-lg bg-blue-50 flex items-center justify-center"><Package className="w-5 h-5 text-blue-600" /></div><div><h1 className="text-xl font-display font-bold text-surface-900">Materiales</h1><p className="text-sm text-surface-500">Catálogo de materiales</p></div></div>
      <DataTable data={data} columns={columns} title="Materiales" loading={loading} searchPlaceholder="Buscar..." searchKeys={["nombre", "tipo", "unidad"]}
        onAdd={isAdmin ? () => { setForm(emptyForm); setEditingId(null); setModalOpen(true); } : undefined}
        onEdit={isAdmin ? (i) => { setForm({ nombre: i.nombre, tipo: i.tipo || "", unidad: i.unidad || "", observaciones: i.observaciones || "", foto_url: i.foto_url || "" }); setEditingId(i.id); setModalOpen(true); } : undefined}
        onDelete={isAdmin ? async (i) => { await supabase.from("materiales").update({ activo: false } as any).eq("id", i.id); fetchData(); } : undefined}
        addLabel="Nuevo material" canAdd={isAdmin} canEdit={isAdmin} canDelete={isAdmin} />
      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar material" : "Nuevo material"}>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="flex items-start gap-4">
            <PhotoUpload currentUrl={form.foto_url || null} folder="material" entityId={editingId || undefined} size="md" onUploaded={(url) => setForm({ ...form, foto_url: url })} onRemoved={() => setForm({ ...form, foto_url: "" })} />
            <div className="flex-1 space-y-4">
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre *</label><input type="text" required value={form.nombre || ""} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="Ej: Cemento Portland" className={ic} /></div>
              <div className="grid grid-cols-2 gap-4">
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Tipo</label><input type="text" value={form.tipo || ""} onChange={(e) => setForm({ ...form, tipo: e.target.value })} placeholder="Ej: Cementante" className={ic} /></div>
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Unidad</label><select value={form.unidad || ""} onChange={(e) => setForm({ ...form, unidad: e.target.value })} className={ic}><option value="">Seleccionar...</option><option value="kg">kg</option><option value="m³">m³</option><option value="ml">ml</option><option value="ud">ud</option><option value="l">l</option><option value="m²">m²</option><option value="t">t</option></select></div>
              </div>
            </div>
          </div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Observaciones</label><textarea value={form.observaciones || ""} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} rows={2} className={ic + " resize-none"} /></div>
          <div className="flex justify-end gap-2 pt-2"><button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button><button type="submit" disabled={saving || !form.nombre} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingId ? "Guardar" : "Crear"}</button></div>
        </form>
      </Modal>
    </div></AppLayout>);
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\maestros\recursos-humanos\page.tsx" -ForegroundColor Gray
$dst = "src\app\maestros\recursos-humanos\page.tsx"
$content = @'
"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import PhotoUpload from "@/components/shared/PhotoUpload";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { RecursoHumano } from "@/lib/types/database";
import { Users, Loader2, ShieldCheck, UserX, UserCheck, Eye, EyeOff, CalendarOff } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface RHWithUser extends RecursoHumano { user_role?: string; user_activo?: boolean; user_id?: string; }

const emptyForm = { nombre: "", perfil: "", telefono: "", email: "", password: "", role: "partes", rol_id: "", foto_url: "", asignable: true, fecha_inicio: new Date().toISOString().slice(0, 10), fecha_fin: "" };

export default function RecursosHumanosPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<RHWithUser[]>([]); const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false); const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null); const [saving, setSaving] = useState(false);
  const [error, setError] = useState(""); const [showPassword, setShowPassword] = useState(false);
  const [syncing, setSyncing] = useState(false); const [syncResult, setSyncResult] = useState("");
  const [deleteBlockedMsg, setDeleteBlockedMsg] = useState<string | null>(null);
  const [editingActivo, setEditingActivo] = useState(true);
  const [togglingAccess, setTogglingAccess] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [dbRoles, setDbRoles] = useState<{ id: string; nombre: string; is_admin: boolean }[]>([]);
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("maestros_rrhh", "crear");
  const puedeEditar   = isAdmin || canDo("maestros_rrhh", "editar");
  const puedeEliminar = isAdmin || canDo("maestros_rrhh", "eliminar");
  const supabase = createClient();

  const fetchData = useCallback(async () => {
    setLoading(true);
    const { data: recursos } = await supabase.from("recursos_humanos").select("*").order("nombre");
    const { data: users } = await supabase.from("users").select("id, recurso_id, role, activo, rol_id");
    const { data: rolesData } = await supabase.from("roles").select("id, nombre, is_admin").order("nombre");
    setDbRoles(rolesData || []);
    const userMap: Record<string, { role: string; activo: boolean; id: string; rol_id: string | null }> = {};
    (users || []).forEach((u: any) => { if (u.recurso_id) userMap[u.recurso_id] = { role: u.role, activo: u.activo, id: u.id, rol_id: u.rol_id }; });
    const rolesMap: Record<string, string> = {};
    (rolesData || []).forEach((r: any) => { rolesMap[r.id] = r.nombre; });
    const enriched = (recursos || []).map((r: any) => ({
      ...r,
      user_role: userMap[r.id]?.role, user_activo: userMap[r.id]?.activo ?? r.activo, user_id: userMap[r.id]?.id,
      user_rol_id: userMap[r.id]?.rol_id,
      user_rol_nombre: userMap[r.id]?.rol_id ? rolesMap[userMap[r.id]?.rol_id!] || "Sin rol" : "Sin rol",
    }));
    setData(enriched); setLoading(false);
  }, []);
  useEffect(() => { fetchData(); }, [fetchData]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); setError(""); setSaving(true);
    // Update asignable flag directly on recurso
    if (editingId) {
      await (supabase.from("recursos_humanos") as any).update({ asignable: form.asignable, fecha_inicio: form.fecha_inicio || null, fecha_fin: form.fecha_fin || null }).eq("id", editingId);
    }
    try {
      const res = await fetch("/api/users", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: editingId ? "update" : "create", recurso_id: editingId,
          nombre: form.nombre, perfil: form.perfil, telefono: form.telefono, email: form.email,
          password: form.password, role: form.role, rol_id: form.rol_id, foto_url: form.foto_url,
        }),
      });
      const result = await res.json();
      if (!res.ok) { setError(result.error || "Error"); setSaving(false); return; }
    } catch (err: any) { setError(err.message || "Error"); setSaving(false); return; }
    // If creating new, also set asignable
    if (!editingId) {
      // Find the newly created recurso by name+email
      const { data: newR } = await supabase.from("recursos_humanos").select("id").eq("email", form.email).order("created_at", { ascending: false }).limit(1);
      if (newR?.[0]) {
        const updatePayload: any = { fecha_inicio: form.fecha_inicio || new Date().toISOString().slice(0, 10) };
        if (!form.asignable) updatePayload.asignable = false;
        if (form.fecha_fin) updatePayload.fecha_fin = form.fecha_fin;
        await (supabase.from("recursos_humanos") as any).update(updatePayload).eq("id", newR[0].id);
      }
    }
    setSaving(false); setModalOpen(false); fetchData();
  };

  const handleToggleAccess = async (recursoId: string, currentlyActive: boolean) => {
    const res = await fetch("/api/users", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "toggle_access", recurso_id: recursoId, activo: !currentlyActive }) });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      setDeleteBlockedMsg(json.error || "No se pudo cambiar el acceso");
      return;
    }
    fetchData();
  };

  const handleToggleAccessInModal = async () => {
    if (!editingId) return;
    setTogglingAccess(true);
    setDeleteBlockedMsg(null);
    try {
      const nuevoEstado = !editingActivo;
      const res = await fetch("/api/users", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "toggle_access", recurso_id: editingId, activo: nuevoEstado }),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        setDeleteBlockedMsg(json.error || "No se pudo cambiar el acceso");
        return;
      }
      // Si se desactiva, fijar fecha_fin = hoy en recursos_humanos
      const hoy = new Date().toISOString().slice(0, 10);
      if (!nuevoEstado) {
        await (createClient().from("recursos_humanos") as any)
          .update({ fecha_fin: hoy, activo: false })
          .eq("id", editingId);
        setForm((f: any) => ({ ...f, fecha_fin: hoy }));
      } else {
        await (createClient().from("recursos_humanos") as any)
          .update({ fecha_fin: null, activo: true })
          .eq("id", editingId);
        setForm((f: any) => ({ ...f, fecha_fin: "" }));
      }
      setEditingActivo(nuevoEstado);
      fetchData();
    } catch (err: any) {
      setDeleteBlockedMsg(err.message || "Error al cambiar el acceso");
    } finally { setTogglingAccess(false); }
  };

  const handleDelete = async (item: RHWithUser) => {
    setDeleteBlockedMsg(null);
    setDeleting(true);
    try {
      const res = await fetch("/api/users", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "delete", recurso_id: item.id }),
      });
      const json = await res.json();
      if (!res.ok) {
        setDeleteBlockedMsg(json.error || "No se pudo eliminar el usuario");
        return;
      }
      fetchData();
    } catch (err: any) {
      setDeleteBlockedMsg(err.message || "Error al eliminar");
    } finally { setDeleting(false); }
  };

  const handleSync = async () => {
    setSyncing(true); setSyncResult("");
    try { const res = await fetch("/api/users", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "sync" }) }); const result = await res.json(); setSyncResult(result.message || "Sincronización completada"); fetchData(); }
    catch (err: any) { setSyncResult("Error: " + err.message); }
    setSyncing(false); setTimeout(() => setSyncResult(""), 8000);
  };

  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  const columns: Column<RHWithUser>[] = [
    { key: "nombre", header: "Nombre", render: (item) => (
      <div className="flex items-center gap-3">
        {item.foto_url ? <img src={item.foto_url} alt="" className="w-8 h-8 rounded-full object-cover shrink-0" /> :
          <div className="w-8 h-8 rounded-full bg-brand-100 flex items-center justify-center text-brand-700 text-xs font-semibold shrink-0">{item.nombre.split(" ").map(w => w[0]).join("").slice(0, 2).toUpperCase()}</div>}
        <div>
          <span className="font-medium text-surface-900">{item.nombre}</span>
          {!item.user_activo && <span className="ml-2 text-[10px] text-red-500 font-medium">SIN ACCESO</span>}
          {(item as any).asignable === false && <span className="ml-1 text-[10px] text-amber-500 font-medium">NO PLANIF.</span>}
        </div>
      </div>
    )},
    { key: "perfil", header: "Perfil" },
    { key: "email", header: "Email" },
    { key: "user_role", header: "Rol", render: (item) => (
      <span className={cn("badge text-[10px]", (item as any).user_rol_nombre === "Administrador" ? "bg-brand-100 text-brand-700" : "bg-surface-100 text-surface-600")}>{(item as any).user_rol_nombre || "Sin rol"}</span>
    )},
    { key: "user_activo", header: "Acceso", render: (item) => (
      <button onClick={() => isAdmin && handleToggleAccess(item.id, !!item.user_activo)}
        className={cn("flex items-center gap-1 text-[11px] font-medium px-2 py-1 rounded-lg", item.user_activo ? "text-emerald-700 bg-emerald-50 hover:bg-emerald-100" : "text-red-700 bg-red-50 hover:bg-red-100")} disabled={!isAdmin}>
        {item.user_activo ? <UserCheck className="w-3.5 h-3.5" /> : <UserX className="w-3.5 h-3.5" />}{item.user_activo ? "Activo" : "Inactivo"}
      </button>
    )},
  ];

  return (
    <AppLayout><div className="max-w-7xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6">
        <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center"><Users className="w-5 h-5 text-brand-600" /></div>
        <div><h1 className="text-xl font-display font-bold text-surface-900">Recursos Humanos</h1><p className="text-sm text-surface-500">Trabajadores y usuarios de la aplicación</p></div>
        {isAdmin && <button onClick={handleSync} disabled={syncing} className="flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-white bg-violet-500 rounded-lg hover:bg-violet-600 disabled:opacity-60 ml-auto shrink-0">{syncing ? <Loader2 className="w-4 h-4 animate-spin" /> : <UserCheck className="w-4 h-4" />}Sincronizar usuarios</button>}
      </div>
      {syncResult && <div className="mb-4 p-3 bg-violet-50 border border-violet-200 rounded-lg text-sm text-violet-700">{syncResult}</div>}
      {deleteBlockedMsg && (
        <div className="mb-4 p-3 bg-amber-50 border border-amber-200 rounded-lg text-sm text-amber-800 flex items-start justify-between gap-3">
          <span>{deleteBlockedMsg}</span>
          <button onClick={() => setDeleteBlockedMsg(null)} className="text-amber-500 hover:text-amber-700 shrink-0">✕</button>
        </div>
      )}
      <DataTable data={data} columns={columns} title="Trabajadores" loading={loading} searchPlaceholder="Buscar por nombre, perfil, email..." searchKeys={["nombre", "perfil", "email", "telefono"]}
        onAdd={isAdmin ? () => { setForm(emptyForm); setEditingId(null); setError(""); setModalOpen(true); } : undefined}
        onEdit={isAdmin ? (item) => { setForm({ nombre: item.nombre, perfil: item.perfil || "", telefono: item.telefono || "", email: item.email || "", password: "", role: item.user_role || "partes", rol_id: (item as any).user_rol_id || "", foto_url: item.foto_url || "", asignable: (item as any).asignable !== false, fecha_inicio: (item as any).fecha_inicio || new Date().toISOString().slice(0, 10), fecha_fin: (item as any).fecha_fin || "" }); setEditingId(item.id); setEditingActivo(item.user_activo !== false); setError(""); setModalOpen(true); } : undefined}
        addLabel="Nuevo trabajador" canAdd={isAdmin} canEdit={isAdmin} canDelete={isAdmin} onDelete={handleDelete} />
      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar trabajador" : "Nuevo trabajador"} size="lg">
        <form onSubmit={handleSubmit} className="space-y-4">
          {error && <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">{error}</div>}
          {deleteBlockedMsg && <div className="p-3 bg-amber-50 border border-amber-200 rounded-lg text-sm text-amber-800">{deleteBlockedMsg}</div>}
          <div className="flex items-start gap-5">
            <PhotoUpload currentUrl={form.foto_url || null} folder="humano" entityId={editingId || undefined} size="lg" onUploaded={(url) => setForm({ ...form, foto_url: url })} onRemoved={() => setForm({ ...form, foto_url: "" })} />
            <div className="flex-1 space-y-4">
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre completo *</label><input type="text" required value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="Ej: Juan García Pérez" className={ic} /></div>
              <div className="grid grid-cols-2 gap-4">
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Perfil / Puesto</label>
                  <select value={form.perfil} onChange={(e) => setForm({ ...form, perfil: e.target.value })} className={ic}><option value="">Seleccionar...</option><option value="Encargado de obra">Encargado de obra</option><option value="Oficial 1ª">Oficial 1ª</option><option value="Oficial 2ª">Oficial 2ª</option><option value="Peón especialista">Peón especialista</option><option value="Peón">Peón</option><option value="Administrativo">Administrativo</option><option value="Técnico">Técnico</option></select>
                </div>
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Teléfono</label><input type="tel" value={form.telefono} onChange={(e) => setForm({ ...form, telefono: e.target.value })} placeholder="600 000 000" className={ic} /></div>
              </div>
            </div>
          </div>
          <div className="border-t border-surface-200 pt-4">
            <div className="flex items-center gap-2 mb-3"><ShieldCheck className="w-4 h-4 text-brand-600" /><h3 className="text-sm font-semibold text-surface-900">Acceso a la aplicación</h3></div>
            <div className="grid grid-cols-3 gap-4">
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Email de acceso *</label><input type="email" required value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} placeholder="trabajador@loynek.es" className={ic} /></div>
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">{editingId ? "Nueva contraseña" : "Contraseña *"}</label>
                <div className="relative"><input type={showPassword ? "text" : "password"} value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} placeholder={editingId ? "Dejar vacío para no cambiar" : "Mínimo 6 caracteres"} required={!editingId} minLength={editingId ? 0 : 6} className={ic + " pr-10"} />
                  <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-3 top-1/2 -translate-y-1/2 text-surface-400">{showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}</button>
                </div>
              </div>
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Rol</label>
                <select value={form.rol_id} onChange={(e) => { const rol = dbRoles.find((r) => r.id === e.target.value); setForm({ ...form, rol_id: e.target.value, role: rol?.is_admin ? "admin" : "partes" }); }} className={ic}><option value="">Sin rol</option>{dbRoles.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select>
              </div>
            </div>
          </div>
          {/* Activar/Desactivar acceso (solo al editar) */}
          {editingId && (
            <div className="border-t border-surface-200 pt-4">
              <div className="flex items-center justify-between">
                <div>
                  <span className="text-sm font-medium text-surface-900">Acceso a la aplicación</span>
                  <p className="text-xs text-surface-400">{editingActivo ? "Este usuario puede iniciar sesión." : "Este usuario NO puede iniciar sesión."}</p>
                </div>
                <button type="button" onClick={handleToggleAccessInModal} disabled={togglingAccess}
                  className={cn("flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg disabled:opacity-60",
                    editingActivo ? "text-red-700 bg-red-50 hover:bg-red-100" : "text-emerald-700 bg-emerald-50 hover:bg-emerald-100")}>
                  {togglingAccess && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
                  {!togglingAccess && (editingActivo ? <UserX className="w-3.5 h-3.5" /> : <UserCheck className="w-3.5 h-3.5" />)}
                  {editingActivo ? "Desactivar acceso" : "Activar acceso"}
                </button>
              </div>
            </div>
          )}
          {/* Fechas de disponibilidad */}
          <div className="border-t border-surface-200 pt-4">
            <p className="text-sm font-medium text-surface-900 mb-3">Disponibilidad en planificador</p>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-surface-600 mb-1">Fecha inicio *</label>
                <input type="date" className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none"
                  value={form.fecha_inicio}
                  onChange={(e) => setForm({ ...form, fecha_inicio: e.target.value })} />
                <p className="text-[10px] text-surface-400 mt-1">Desde cuándo aparece en el planificador</p>
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-600 mb-1">Fecha fin</label>
                <input type="date" className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none"
                  value={form.fecha_fin}
                  onChange={(e) => setForm({ ...form, fecha_fin: e.target.value })} />
                <p className="text-[10px] text-surface-400 mt-1">Vacío = disponible indefinidamente</p>
              </div>
            </div>
          </div>
          {/* Asignable flag */}
          <div className="border-t border-surface-200 pt-4">
            <label className="flex items-center gap-3 cursor-pointer">
              <input type="checkbox" checked={form.asignable} onChange={(e) => setForm({ ...form, asignable: e.target.checked })} className="w-4 h-4 rounded border-surface-300 text-brand-600 focus:ring-brand-500" />
              <div>
                <span className="text-sm font-medium text-surface-900">Asignable en planificación</span>
                <p className="text-xs text-surface-400">Si está desactivado, no aparecerá en el panel de recursos del planificador</p>
              </div>
            </label>
          </div>
          <div className="flex items-center justify-end gap-2 pt-2">
            <button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving || !form.nombre || !form.email || (!editingId && !form.password)} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingId ? "Guardar cambios" : "Crear trabajador"}</button>
          </div>
        </form>
      </Modal>
    </div></AppLayout>
  );
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\maestros\tipos-obra\page.tsx" -ForegroundColor Gray
$dst = "src\app\maestros\tipos-obra\page.tsx"
$content = @'
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
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\maestros\tipos-trabajo\page.tsx" -ForegroundColor Gray
$dst = "src\app\maestros\tipos-trabajo\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { TipoTrabajo } from "@/lib/types/database";
import { Hammer, Loader2 } from "lucide-react";

export default function TiposTrabajoPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<TipoTrabajo[]>([]); const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false); const [form, setForm] = useState({ nombre: "" });
  const [editingId, setEditingId] = useState<string | null>(null); const [saving, setSaving] = useState(false);
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("maestros_tipos_trabajo", "crear");
  const puedeEditar   = isAdmin || canDo("maestros_tipos_trabajo", "editar");
  const puedeEliminar = isAdmin || canDo("maestros_tipos_trabajo", "eliminar");
  const supabase = createClient();
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
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\obras\[id]\page.tsx" -ForegroundColor Gray
$dst = "src\app\obras\[id]\page.tsx"
$content = @'
"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { useParams, useRouter } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import ResourceAvatar from "@/components/shared/ResourceAvatar";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { Obra, Asignacion, RecursoHumano, Maquinaria, Tarea, TipoTarea, EstadoObra, Documento, ParteDiario } from "@/lib/types/database";
import {
  Building2, ArrowLeft, MapPin, Users, Wrench, Truck, ClipboardList, FileText,
  Loader2, Plus, Trash2, CheckCircle2, Clock, ListTodo, Upload, History,
  File, Image as ImageIcon, Save, MessageSquare, ExternalLink, Pencil,
  FileSignature, Archive, Eye, AlertTriangle, Download
} from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils/cn";
import ChecklistPanel from "@/components/obras/ChecklistPanel";

type Tab = "general" | "recursos" | "tareas" | "partes" | "documentos" | "checklists" | "logs";

export default function ObraDetallePage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { user } = useAuthStore();
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("obras", "crear");
  const puedeEditar   = isAdmin || canDo("obras", "editar");
  const puedeEliminar = isAdmin || canDo("obras", "eliminar");
  const supabase = createClient();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [obra, setObra] = useState<Obra | null>(null);
  const [asignaciones, setAsignaciones] = useState<Asignacion[]>([]);
  const [tareas, setTareas] = useState<Tarea[]>([]);
  const [tiposTarea, setTiposTarea] = useState<TipoTarea[]>([]);
  const [estados, setEstados] = useState<EstadoObra[]>([]);
  const [rrhh, setRrhh] = useState<RecursoHumano[]>([]);
  const [maq, setMaq] = useState<Record<string, Maquinaria>>({});
  const [veh, setVeh] = useState<Record<string, any>>({});
  const [documentos, setDocumentos] = useState<Documento[]>([]);
  const [partes, setPartes] = useState<any[]>([]);
  const [tiposObra, setTiposObra] = useState<any[]>([]);
  const [obraTipos, setObraTipos] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<Tab>("general");
  const [logs, setLogs] = useState<any[]>([]);
  const [loadingLogs, setLoadingLogs] = useState(false);
  const [observaciones, setObservaciones] = useState("");
  const [obsSaving, setObsSaving] = useState(false);
  const [obsChanged, setObsChanged] = useState(false);
  const [downloadingPdf, setDownloadingPdf] = useState(false);
  const [taskModal, setTaskModal] = useState(false);
  const [taskForm, setTaskForm] = useState({ descripcion: "", tipo_tarea_id: "", prioridad: "media" as any, fecha_limite: "", asignado_a: "" });
  const [taskSaving, setTaskSaving] = useState(false);
  const [completeModal, setCompleteModal] = useState<Tarea | null>(null);
  const [completeComment, setCompleteComment] = useState("");
  const [editTask, setEditTask] = useState<Tarea | null>(null);
  const [editTaskForm, setEditTaskForm] = useState({ descripcion: "", tipo_tarea_id: "", prioridad: "media" as any, fecha_limite: "", asignado_a: "" });
  const [editTaskSaving, setEditTaskSaving] = useState(false);
  const [uploading, setUploading] = useState(false);

  const fetchLogs = useCallback(async () => {
    if (!id) return;
    setLoadingLogs(true);
    const { data } = await (supabase.from("audit_log") as any)
      .select("id, accion, entidad, modulo, descripcion, user_rol, created_at, valor_anterior, valor_nuevo, user:users(nombre)")
      .eq("obra_id", id)
      .order("created_at", { ascending: false })
      .limit(200);
    setLogs(data || []);
    setLoadingLogs(false);
  }, [id]);

  // Cargar logs al abrir la pestaña (hook antes de cualquier return condicional)
  useEffect(() => { if (tab === "logs") fetchLogs(); }, [tab, fetchLogs]);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [obraRes, asigRes, tareasRes, tiposRes, estadosRes, rrhhRes, maqRes, vehRes, docsRes, partesRes, tiposObraRes, obraTiposRes] = await Promise.all([
      supabase.from("obras").select("*, cliente:clientes(*), estado_custom:estados_obra(*)").eq("id", id).single(),
      supabase.from("asignaciones").select("*").eq("obra_id", id),
      supabase.from("tareas").select("*, tipo_tarea:tipo_tarea(nombre), recurso_asignado:recursos_humanos(nombre, foto_url)").eq("obra_id", id).order("created_at", { ascending: false }),
      supabase.from("tipo_tarea").select("*").eq("activo", true).order("nombre"),
      supabase.from("estados_obra").select("*").eq("activo", true).order("nombre"),
      supabase.from("recursos_humanos").select("*").eq("activo", true),
      supabase.from("maquinaria").select("*").eq("activo", true),
      supabase.from("vehiculos").select("*").eq("activo", true),
      supabase.from("documentos").select("*").eq("obra_id", id).is("parte_id", null).order("created_at", { ascending: false }),
      supabase.from("partes_diarios").select("*, creator:users!partes_diarios_created_by_fkey(nombre)").eq("obra_id", id).order("fecha", { ascending: false }),
      supabase.from("tipos_obra").select("*").eq("activo", true).order("nombre"),
      supabase.from("obra_tipos_obra").select("tipo_obra_id").eq("obra_id", id),
    ]);
    const obraData = obraRes.data as Obra | null;
    setObra(obraData); setObservaciones(obraData?.observaciones || ""); setObsChanged(false);
    setAsignaciones(asigRes.data || []); setTareas((tareasRes.data as any[]) || []);
    setTiposTarea(tiposRes.data || []); setEstados(estadosRes.data || []);
    setRrhh(rrhhRes.data || []); setDocumentos((docsRes.data as Documento[]) || []);
    setPartes(partesRes.data || []); setTiposObra(tiposObraRes.data || []);
    setObraTipos((obraTiposRes.data || []).map((t: any) => t.tipo_obra_id));
    const maqMap: Record<string, any> = {}; (maqRes.data || []).forEach((r: any) => maqMap[r.id] = r); setMaq(maqMap);
    const vehMap: Record<string, any> = {}; (vehRes.data || []).forEach((r: any) => vehMap[r.id] = r); setVeh(vehMap);
    setLoading(false);
  }, [id]);
  useEffect(() => { fetchData(); }, [fetchData]);

  const handleChangeEstado = async (estadoId: string) => { await (supabase.from("obras") as any).update({ estado_obra_id: estadoId || null }).eq("id", id); fetchData(); };
  const handleSaveObservaciones = async () => { setObsSaving(true); await (supabase.from("obras") as any).update({ observaciones }).eq("id", id); setObsSaving(false); setObsChanged(false); };
  const handleArchive = async () => {
    const newArchived = !obra?.archivada;
    const update: any = { archivada: newArchived };
    if (newArchived) { const cerrada = estados.find((e) => e.nombre.toLowerCase().includes("terminada") || e.nombre.toLowerCase().includes("cerrada")); if (cerrada) update.estado_obra_id = cerrada.id; }
    const { error } = await (supabase.from("obras") as any).update(update).eq("id", id);
    if (error) { alert("Error al archivar: " + error.message); return; }
    fetchData();
  };
  const handleDelete = async () => {
    if (!confirm(`¿Seguro que quieres ELIMINAR la obra "${obra?.nombre}"?\n\nSe borrarán todas las asignaciones, tareas, partes y documentos asociados.\n\nEsta acción no se puede deshacer.`)) return;
    const { error } = await (supabase.from("obras") as any).delete().eq("id", id);
    if (error) { alert("Error al eliminar la obra: " + error.message + "\n\nSi persiste, comprueba si hay registros vinculados que bloquean el borrado."); return; }
    router.push("/obras");
  };
  const handleCreateTask = async (e: React.FormEvent) => { e.preventDefault(); setTaskSaving(true); await (supabase.from("tareas") as any).insert({ obra_id: id, descripcion: taskForm.descripcion, tipo_tarea_id: taskForm.tipo_tarea_id || null, prioridad: taskForm.prioridad, fecha_limite: taskForm.fecha_limite || null, asignado_a: taskForm.asignado_a || null, created_by: user?.id }); setTaskSaving(false); setTaskModal(false); setTaskForm({ descripcion: "", tipo_tarea_id: "", prioridad: "media", fecha_limite: "", asignado_a: "" }); fetchData(); };
  const handleCompleteTask = async () => { if (!completeModal) return; await (supabase.from("tareas") as any).update({ estado: "completada", comentario_cierre: completeComment || null, completada_at: new Date().toISOString(), completada_by: user?.id }).eq("id", completeModal.id); setCompleteModal(null); setCompleteComment(""); fetchData(); };
  const handleDeleteTask = async (taskId: string) => { await (supabase.from("tareas") as any).delete().eq("id", taskId); fetchData(); };
  const handleReopenTask = async (taskId: string) => { await (supabase.from("tareas") as any).update({ estado: "pendiente" }).eq("id", taskId); setEditTask(null); fetchData(); };
  const handleOpenEditTask = (t: Tarea) => { setEditTask(t); setEditTaskForm({ descripcion: t.descripcion, tipo_tarea_id: t.tipo_tarea_id || "", prioridad: t.prioridad, fecha_limite: t.fecha_limite || "", asignado_a: t.asignado_a || "" }); };
  const handleSaveEditTask = async (e: React.FormEvent) => { e.preventDefault(); if (!editTask) return; setEditTaskSaving(true); await (supabase.from("tareas") as any).update({ descripcion: editTaskForm.descripcion, tipo_tarea_id: editTaskForm.tipo_tarea_id || null, prioridad: editTaskForm.prioridad, fecha_limite: editTaskForm.fecha_limite || null, asignado_a: editTaskForm.asignado_a || null }).eq("id", editTask.id); setEditTaskSaving(false); setEditTask(null); fetchData(); };
  const handleOpenDoc = async (doc: Documento) => { const { data } = await supabase.storage.from("documentos").createSignedUrl(doc.storage_path, 300); if (data?.signedUrl) window.open(data.signedUrl, "_blank"); };
  const handleDeleteDoc = async (doc: Documento) => { await supabase.storage.from("documentos").remove([doc.storage_path]); await (supabase.from("documentos") as any).delete().eq("id", doc.id); fetchData(); };
  const handleUploadFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    setUploading(true);
    let errors: string[] = [];
    const sanitize = (name: string) => name.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-zA-Z0-9._-]/g, "_");
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const safeName = sanitize(file.name);
      const path = `obras/${id}/${Date.now()}_${safeName}`;
      const { error: uploadErr } = await supabase.storage.from("documentos").upload(path, file);
      if (uploadErr) { errors.push(`${file.name}: ${uploadErr.message}`); continue; }
      const { error: insertErr } = await (supabase.from("documentos") as any).insert({
        obra_id: id, nombre_archivo: file.name,
        tipo: file.type.startsWith("image/") ? "foto" : file.type === "application/pdf" ? "pdf" : "documento",
        categoria: "general", storage_path: path, tamano: file.size, mime_type: file.type, uploaded_by: user?.id,
      });
      if (insertErr) errors.push(`${file.name} (DB): ${insertErr.message}`);
    }
    setUploading(false);
    if (fileInputRef.current) fileInputRef.current.value = "";
    if (errors.length > 0) alert("Errores al subir:\n" + errors.join("\n"));
    fetchData();
  };
  const getTaskDateColor = (f: string | null) => { if (!f) return ""; const d = (new Date(f).getTime() - Date.now()) / 86400000; if (d < 0) return "text-red-600 bg-red-50"; if (d < 3) return "text-amber-600 bg-amber-50"; return "text-surface-600"; };
  const formatBytes = (b: number | null) => { if (!b) return ""; if (b < 1024) return b + " B"; if (b < 1048576) return (b / 1024).toFixed(0) + " KB"; return (b / 1048576).toFixed(1) + " MB"; };

  if (loading) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;
  if (!obra) return <AppLayout><div className="text-center py-20"><p className="text-surface-500">Obra no encontrada</p></div></AppLayout>;


  const tabs: { id: Tab; label: string; icon: typeof Building2; count?: number }[] = [
    { id: "general", label: "General", icon: Building2 },
    { id: "recursos", label: "Recursos", icon: Users, count: asignaciones.length },
    { id: "tareas", label: "Tareas", icon: ListTodo, count: tareas.filter((t) => t.estado === "pendiente").length },
    { id: "partes", label: "Partes", icon: ClipboardList, count: partes.length },
    { id: "documentos", label: "Documentos", icon: FileText, count: documentos.length },
    { id: "checklists", label: "Checklists", icon: CheckCircle2 },
    { id: "logs", label: "Logs", icon: History },
  ];
  const humanos = asignaciones.filter((a) => a.recurso_tipo === "humano");
  const maquinas = asignaciones.filter((a) => a.recurso_tipo === "maquinaria");
  const vehiculos = asignaciones.filter((a) => a.recurso_tipo === "vehiculo");
  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  const prioColors: Record<string, string> = { alta: "bg-red-100 text-red-700", media: "bg-amber-100 text-amber-700", baja: "bg-blue-100 text-blue-700" };
  const estadoBadgeParte: Record<string, { label: string; class: string }> = { pendiente: { label: "Pendiente", class: "bg-amber-100 text-amber-700" }, firmado: { label: "Firmado", class: "bg-emerald-100 text-emerald-700" }, borrador: { label: "Borrador", class: "bg-surface-100 text-surface-600" } };
  const obraTipoNames = obraTipos.map((tid) => tiposObra.find((t: any) => t.id === tid)?.nombre).filter(Boolean);

  return (
    <AppLayout>
      <div className="max-w-5xl mx-auto animate-fade-in">
        {/* Header */}
        <div className="flex items-start gap-4 mb-6">
          <Link href="/obras" className="p-2 mt-1 rounded-lg text-surface-400 hover:bg-surface-100"><ArrowLeft className="w-5 h-5" /></Link>
          <div className="flex-1">
            <div className="flex items-center gap-3">
              <div className="w-3 h-10 rounded-full" style={{ backgroundColor: obra.color || "#DC2626" }} />
              <div>
                <div className="flex items-center gap-2">
                  <h1 className="text-xl font-display font-bold text-surface-900">{obra.nombre}</h1>
                  {obra.archivada && <span className="badge bg-surface-200 text-surface-600 text-[10px]">Archivada</span>}
                </div>
                <div className="flex items-center gap-3 mt-1 text-sm text-surface-500">
                  {obra.direccion && <span className="flex items-center gap-1"><MapPin className="w-3.5 h-3.5" />{obra.direccion}{obra.localidad ? `, ${obra.localidad}` : ""}</span>}
                  {(obra as any).cliente?.nombre && <span>· {(obra as any).cliente.nombre}</span>}
                </div>
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <button onClick={async () => {
              setDownloadingPdf(true);
              try {
                const res = await fetch("/api/obras/pdf", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ obraId: id }) });
                const data = await res.json();
                if (data.pdf) { const link = document.createElement("a"); link.href = `data:application/pdf;base64,${data.pdf}`; link.download = data.filename; link.click(); }
                else alert("Error: " + (data.error || ""));
              } catch (err: any) { alert("Error: " + err.message); }
              setDownloadingPdf(false);
            }} disabled={downloadingPdf} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-violet-700 bg-violet-50 rounded-lg hover:bg-violet-100 disabled:opacity-60">
              {downloadingPdf ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Download className="w-3.5 h-3.5" />} PDF
            </button>
            {isAdmin && (
              <>
                <button onClick={handleArchive} className={cn("flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg", obra.archivada ? "text-blue-700 bg-blue-50 hover:bg-blue-100" : "text-amber-700 bg-amber-50 hover:bg-amber-100")}>
                  {obra.archivada ? <Eye className="w-3.5 h-3.5" /> : <Archive className="w-3.5 h-3.5" />}
                  {obra.archivada ? "Desarchivar" : "Archivar"}
                </button>
                <button onClick={handleDelete} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-red-700 bg-red-50 rounded-lg hover:bg-red-100">
                  <Trash2 className="w-3.5 h-3.5" /> Eliminar
                </button>
                <Link href={`/obras/nueva?edit=${id}`} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">
                  <Pencil className="w-3.5 h-3.5" /> Editar
                </Link>
              </>
            )}
            {isAdmin ? (
              <select value={obra.estado_obra_id || ""} onChange={(e) => handleChangeEstado(e.target.value)}
                className="px-3 py-1.5 rounded-full text-sm font-medium text-white border-0 cursor-pointer focus:outline-none"
                style={{ backgroundColor: (obra as any).estado_custom?.color || "#6B7280" }}>
                <option value="">Sin estado</option>
                {estados.map((es) => <option key={es.id} value={es.id}>{es.nombre}</option>)}
              </select>
            ) : (
              <span className="px-3 py-1.5 rounded-full text-sm font-medium text-white" style={{ backgroundColor: (obra as any).estado_custom?.color || "#6B7280" }}>
                {(obra as any).estado_custom?.nombre || "Sin estado"}
              </span>
            )}
          </div>
        </div>

        {/* Tabs */}
        <div className="flex gap-1 mb-6 border-b border-surface-200 overflow-x-auto">
          {tabs.map((t) => (
            <button key={t.id} onClick={() => setTab(t.id)}
              className={cn("flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 transition-all -mb-px whitespace-nowrap",
                tab === t.id ? "border-brand-500 text-brand-600" : "border-transparent text-surface-500 hover:text-surface-700")}>
              <t.icon className="w-4 h-4" />{t.label}
              {t.count !== undefined && t.count > 0 && <span className="text-[10px] bg-brand-100 text-brand-700 px-1.5 py-0.5 rounded-full">{t.count}</span>}
            </button>
          ))}
        </div>

        {/* GENERAL - all fields */}
        {tab === "general" && (
          <div className="space-y-6">
            <div className="card p-6">
              <h3 className="text-sm font-semibold text-surface-900 mb-4">Datos generales</h3>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Cliente</p><p className="text-sm text-surface-900 mt-1">{(obra as any).cliente?.nombre || "—"}</p></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Tipos de obra</p><div className="flex flex-wrap gap-1 mt-1.5">{obraTipoNames.length > 0 ? obraTipoNames.map((n, i) => <span key={i} className="text-xs px-2 py-0.5 rounded-full bg-brand-50 text-brand-700 border border-brand-200">{n}</span>) : <span className="text-sm text-surface-400">—</span>}</div></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Estado</p><div className="mt-1">{(obra as any).estado_custom ? <span className="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium text-white" style={{ backgroundColor: (obra as any).estado_custom.color }}>{(obra as any).estado_custom.nombre}</span> : <span className="text-sm text-surface-400">Sin estado</span>}</div></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Nº Presupuesto</p><p className="text-sm text-surface-900 mt-1">{(obra as any).num_presupuesto || "—"}</p></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Nº Factura</p><p className="text-sm text-surface-900 mt-1">{(obra as any).num_factura || "—"}</p></div>
              </div>
            </div>

            <div className="card p-6">
              <h3 className="text-sm font-semibold text-surface-900 mb-4">Dirección</h3>
              <div className="grid grid-cols-3 gap-4">
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Dirección</p><p className="text-sm text-surface-900 mt-1">{obra.direccion || "—"}</p></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Localidad</p><p className="text-sm text-surface-900 mt-1">{obra.localidad || "—"}</p></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Provincia</p><p className="text-sm text-surface-900 mt-1">{obra.provincia || "—"}</p></div>
              </div>
            </div>

            <div className="card p-6">
              <h3 className="text-sm font-semibold text-surface-900 mb-4">Contacto</h3>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-[10px] font-semibold text-surface-400 uppercase mb-2">Cliente</p>
                  <p className="text-sm text-surface-900">{(obra as any).cliente?.nombre || "—"}</p>
                  <p className="text-xs text-surface-500">{(obra as any).cliente?.telefono || ""} {(obra as any).cliente?.email ? `· ${(obra as any).cliente.email}` : ""}</p>
                </div>
                <div>
                  <p className="text-[10px] font-semibold text-surface-400 uppercase mb-2">Contacto obra</p>
                  <p className="text-sm text-surface-900">{(obra as any).contacto_obra_nombre || "—"}</p>
                  <p className="text-xs text-surface-500">{(obra as any).contacto_obra_telefono || ""} {(obra as any).contacto_obra_email ? `· ${(obra as any).contacto_obra_email}` : ""}</p>
                </div>
              </div>
            </div>

            <div className="card p-6">
              <div className="flex items-center justify-between mb-3">
                <h3 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><MessageSquare className="w-4 h-4 text-surface-400" />Comentarios</h3>
                {isAdmin && obsChanged && <button onClick={handleSaveObservaciones} disabled={obsSaving} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{obsSaving ? <Loader2 className="w-3 h-3 animate-spin" /> : <Save className="w-3 h-3" />}Guardar</button>}
              </div>
              <textarea value={observaciones} onChange={(e) => { setObservaciones(e.target.value); setObsChanged(true); }} rows={4} placeholder="Notas, comentarios..." disabled={!isAdmin} className={ic + " resize-y" + (!isAdmin ? " bg-surface-50 cursor-not-allowed" : "")} />
            </div>
          </div>
        )}

        {/* RECURSOS */}
        {tab === "recursos" && (
          <div className="space-y-4">
            {[{ title: "Personas", icon: Users, tipo: "humano" as const, items: humanos, getName: (rid: string) => rrhh.find((r) => r.id === rid)?.nombre || "?" },
              { title: "Maquinaria", icon: Wrench, tipo: "maquinaria" as const, items: maquinas, getName: (rid: string) => maq[rid]?.nombre || "?" },
              { title: "Vehículos", icon: Truck, tipo: "vehiculo" as const, items: vehiculos, getName: (rid: string) => veh[rid]?.nombre || "?" },
            ].map((g) => {
              // Group by resource, collect date ranges
              const grouped: Record<string, { nombre: string; ranges: { inicio: string; fin: string }[] }> = {};
              g.items.forEach((a) => {
                if (!grouped[a.recurso_id]) grouped[a.recurso_id] = { nombre: g.getName(a.recurso_id), ranges: [] };
                grouped[a.recurso_id].ranges.push({ inicio: a.fecha_inicio, fin: a.fecha_fin });
              });
              // Sort ranges and merge
              Object.values(grouped).forEach((v) => v.ranges.sort((a, b) => a.inicio.localeCompare(b.inicio)));
              const sortedResources = Object.entries(grouped).sort((a, b) => a[1].nombre.localeCompare(b[1].nombre, "es"));

              return (
                <div key={g.title} className="card p-6">
                  <h3 className="flex items-center gap-2 text-sm font-semibold text-surface-900 mb-3"><g.icon className="w-4 h-4 text-surface-400" />{g.title} ({sortedResources.length})</h3>
                  {sortedResources.length === 0 ? <p className="text-sm text-surface-400">Sin asignaciones</p> : (
                    <table className="w-full text-sm">
                      <thead><tr className="border-b border-surface-200">
                        <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2 w-[200px]">Recurso</th>
                        <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Fechas</th>
                        <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-2 w-[80px]">Días</th>
                      </tr></thead>
                      <tbody>{sortedResources.map(([rid, v]) => {
                        const totalDays = v.ranges.reduce((sum, r) => {
                          const s = new Date(r.inicio + "T12:00:00"); const e = new Date(r.fin + "T12:00:00");
                          return sum + Math.round((e.getTime() - s.getTime()) / 86400000) + 1;
                        }, 0);
                        return (
                          <tr key={rid} className="border-b border-surface-50 hover:bg-surface-50/50">
                            <td className="py-2 px-2 font-medium text-surface-900">{v.nombre}</td>
                            <td className="py-2 px-2">
                              <div className="flex flex-wrap gap-1">
                                {v.ranges.map((r, i) => {
                                  const s = new Date(r.inicio + "T12:00:00");
                                  const e = new Date(r.fin + "T12:00:00");
                                  const same = r.inicio === r.fin;
                                  const label = same
                                    ? s.toLocaleDateString("es-ES", { weekday: "short", day: "numeric", month: "short" })
                                    : `${s.toLocaleDateString("es-ES", { day: "numeric", month: "short" })} → ${e.toLocaleDateString("es-ES", { day: "numeric", month: "short" })}`;
                                  return <span key={i} className="text-[10px] px-2 py-0.5 rounded bg-brand-50 text-brand-700">{label}</span>;
                                })}
                              </div>
                            </td>
                            <td className="py-2 px-2 text-right text-surface-600 font-medium">{totalDays}</td>
                          </tr>
                        );
                      })}</tbody>
                    </table>
                  )}
                </div>
              );
            })}
          </div>
        )}

        {/* TAREAS */}
        {tab === "tareas" && (
          <div className="card p-6">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-sm font-semibold text-surface-900">Tareas</h3>
              <button onClick={() => setTaskModal(true)} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-3.5 h-3.5" />Nueva</button>
            </div>
            {tareas.length === 0 ? <p className="text-sm text-surface-500 text-center py-8">Sin tareas</p> : (
              <div className="space-y-2">
                {tareas.map((t) => (
                  <div key={t.id} className={cn("flex items-start gap-3 p-3 rounded-lg border", t.estado === "completada" ? "bg-surface-50 border-surface-100 opacity-60" : "bg-white border-surface-200")}>
                    <button onClick={() => t.estado === "pendiente" ? setCompleteModal(t) : null} className={cn("mt-0.5 shrink-0", t.estado === "completada" ? "text-emerald-500" : "text-surface-300 hover:text-emerald-500")}><CheckCircle2 className="w-5 h-5" /></button>
                    <div className="flex-1 min-w-0 cursor-pointer" onClick={() => handleOpenEditTask(t)}>
                      <p className={cn("text-sm hover:text-brand-600", t.estado === "completada" ? "line-through text-surface-400" : "text-surface-900")}>{t.descripcion}</p>
                      <div className="flex items-center gap-2 mt-1 flex-wrap">
                        <span className={cn("badge text-[10px]", prioColors[t.prioridad])}>{t.prioridad}</span>
                        {(t as any).tipo_tarea?.nombre && <span className="badge bg-surface-100 text-surface-600 text-[10px]">{(t as any).tipo_tarea.nombre}</span>}
                        {(t as any).recurso_asignado?.nombre && <ResourceAvatar nombre={(t as any).recurso_asignado.nombre} foto_url={(t as any).recurso_asignado.foto_url} tipo="humano" size="xs" />}
                        {t.fecha_limite && <span className={cn("text-[10px] px-1.5 py-0.5 rounded", getTaskDateColor(t.fecha_limite))}><Clock className="w-3 h-3 inline mr-0.5" />{new Date(t.fecha_limite).toLocaleDateString("es-ES")}</span>}
                      </div>
                      {t.comentario_cierre && <p className="text-[11px] text-surface-400 mt-1 italic">"{t.comentario_cierre}"</p>}
                    </div>
                    {t.estado === "pendiente" && <button onClick={() => handleDeleteTask(t.id)} className="p-1 rounded text-surface-300 hover:text-red-500"><Trash2 className="w-3.5 h-3.5" /></button>}
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* PARTES */}
        {tab === "partes" && (
          <div className="card p-6">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-sm font-semibold text-surface-900">Partes diarios</h3>
              <button onClick={async () => {
                const toDS = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
                const { data: p } = await (supabase.from("partes_diarios") as any).insert({
                  fecha: toDS(new Date()), created_by: user?.id, estado: "pendiente", obra_id: id,
                  direccion: obra?.direccion || null, localidad: obra?.localidad || null, provincia: obra?.provincia || null,
                  responsable_empresa: user?.nombre || "",
                }).select().single();
                if (p) router.push(`/partes/${p.id}`);
              }} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-3.5 h-3.5" />Nuevo parte</button>
            </div>
            {partes.length === 0 ? <p className="text-sm text-surface-500 text-center py-8">Sin partes</p> : (
              <div className="space-y-2">{partes.map((p) => {
                const est = estadoBadgeParte[p.estado] || estadoBadgeParte.pendiente;
                return (
                  <Link key={p.id} href={`/partes/${p.id}`} className="flex items-center gap-4 p-3 bg-surface-50 rounded-lg border border-surface-100 hover:border-surface-300 group">
                    <div className="text-center shrink-0 w-12"><p className="text-lg font-display font-bold text-surface-900">{new Date(p.fecha + "T12:00:00").getDate()}</p><p className="text-[9px] text-surface-400 uppercase">{new Date(p.fecha + "T12:00:00").toLocaleDateString("es-ES", { month: "short" })}</p></div>
                    <div className="flex-1 min-w-0"><p className="text-sm font-medium text-surface-900 group-hover:text-brand-600">{p.creator?.nombre || "?"}</p><p className="text-xs text-surface-400 truncate">{p.observaciones || ""}</p></div>
                    <div className="flex items-center gap-2 shrink-0">
                      {p.firma_data && <FileSignature className="w-3.5 h-3.5 text-emerald-500" />}
                      {p.firma_cliente && <FileSignature className="w-3.5 h-3.5 text-blue-500" />}
                    </div>
                    <span className={cn("badge text-[10px]", est.class)}>{est.label}</span>
                  </Link>
                );
              })}</div>
            )}
          </div>
        )}

        {/* DOCUMENTOS */}
        {tab === "documentos" && (
          <div className="card p-6">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-sm font-semibold text-surface-900">Documentos</h3>
              {isAdmin && <button onClick={() => fileInputRef.current?.click()} disabled={uploading} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{uploading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Upload className="w-3.5 h-3.5" />}Subir</button>}
            </div>
            <input ref={fileInputRef} type="file" multiple accept="image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt" className="hidden" onChange={handleUploadFile} />
            {documentos.length === 0 ? <div className="text-center py-12 border-2 border-dashed border-surface-200 rounded-xl"><Upload className="w-8 h-8 text-surface-300 mx-auto mb-2" /><p className="text-sm text-surface-500">Sin documentos</p></div> : (
              <div className="space-y-2">{documentos.map((doc) => {
                const isImage = doc.tipo === "foto"; const isPdf = doc.tipo === "pdf";
                return (
                  <div key={doc.id} className="flex items-center gap-3 p-3 bg-surface-50 rounded-lg border border-surface-100 group hover:border-surface-200">
                    <div className={cn("w-10 h-10 rounded-lg flex items-center justify-center shrink-0", isImage ? "bg-violet-100 text-violet-600" : isPdf ? "bg-red-100 text-red-600" : "bg-blue-100 text-blue-600")}>{isImage ? <ImageIcon className="w-5 h-5" /> : isPdf ? <FileText className="w-5 h-5" /> : <File className="w-5 h-5" />}</div>
                    <div className="flex-1 min-w-0 cursor-pointer" onClick={() => handleOpenDoc(doc)}><p className="text-sm font-medium text-surface-900 hover:text-brand-600 truncate">{doc.nombre_archivo}</p><p className="text-[11px] text-surface-400">{formatBytes(doc.tamano)}</p></div>
                    <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100"><button onClick={() => handleOpenDoc(doc)} className="p-1.5 rounded-md text-surface-400 hover:text-brand-600"><ExternalLink className="w-4 h-4" /></button>{isAdmin && <button onClick={() => handleDeleteDoc(doc)} className="p-1.5 rounded-md text-surface-400 hover:text-red-600"><Trash2 className="w-4 h-4" /></button>}</div>
                  </div>
                );
              })}</div>
            )}
          </div>
        )}

        {tab === "logs" && (
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <p className="text-xs text-surface-500">Historial de acciones de esta obra</p>
                    <button onClick={fetchLogs} className="text-xs text-brand-600 hover:underline flex items-center gap-1">
                      <History className="w-3 h-3" />Actualizar
                    </button>
                  </div>
                  {loadingLogs ? (
                    <div className="flex justify-center py-8"><Loader2 className="w-5 h-5 text-brand-500 animate-spin" /></div>
                  ) : logs.length === 0 ? (
                    <div className="text-center py-8 text-sm text-surface-400">Sin registros de actividad para esta obra</div>
                  ) : (
                    <div className="space-y-1.5 max-h-[60vh] overflow-y-auto">
                      {logs.map((log: any) => (
                        <div key={log.id} className="flex items-start gap-3 px-3 py-2.5 rounded-lg bg-surface-50 border border-surface-100 hover:bg-surface-100/60">
                          <div className="shrink-0 mt-0.5">
                            <span className={cn("badge text-[9px]",
                              log.accion === "crear"    ? "bg-emerald-100 text-emerald-700" :
                              log.accion === "eliminar" ? "bg-red-100 text-red-700" :
                              "bg-amber-100 text-amber-700")}>
                              {log.accion}
                            </span>
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className="text-xs text-surface-800 font-medium">
                              {log.descripcion || `${log.accion} en ${log.entidad}`}
                            </p>
                            {/* Mostrar cambios concretos si existen */}
                            {log.valor_anterior && log.valor_nuevo && (() => {
                              const ant = log.valor_anterior as Record<string, any>;
                              const nue = log.valor_nuevo as Record<string, any>;
                              const campos = Object.keys(nue).filter(k =>
                                JSON.stringify(ant[k]) !== JSON.stringify(nue[k]) &&
                                nue[k] !== null && ant[k] !== undefined
                              );
                              if (campos.length === 0) return null;
                              return (
                                <div className="mt-1.5 space-y-0.5">
                                  {campos.map(campo => (
                                    <div key={campo} className="flex items-center gap-1.5 text-[10px]">
                                      <span className="text-surface-400 font-mono">{campo}:</span>
                                      <span className="line-through text-red-400">{String(ant[campo] ?? "—")}</span>
                                      <span className="text-surface-400">→</span>
                                      <span className="text-emerald-600 font-medium">{String(nue[campo] ?? "—")}</span>
                                    </div>
                                  ))}
                                </div>
                              );
                            })()}
                            <p className="text-[10px] text-surface-400 mt-1">
                              {new Date(log.created_at).toLocaleString("es-ES")}
                              {log.user?.nombre && ` · ${log.user.nombre}`}
                              {log.user_rol && ` · ${log.user_rol}`}
                            </p>
                          </div>
                          {log.modulo && (
                            <span className="text-[9px] text-surface-400 shrink-0 font-mono bg-surface-100 px-1.5 py-0.5 rounded">
                              {log.modulo}
                            </span>
                          )}
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}

        {tab === "checklists" && (
          <ChecklistPanel obraId={id} rrhh={rrhh.map((r) => ({ id: r.id, nombre: r.nombre }))} />
        )}
      </div>

      {/* Task modals */}
      <Modal open={taskModal} onClose={() => setTaskModal(false)} title="Nueva tarea">
        <form onSubmit={handleCreateTask} className="space-y-4">
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Descripción *</label><textarea required value={taskForm.descripcion} onChange={(e) => setTaskForm({ ...taskForm, descripcion: e.target.value })} rows={3} placeholder="¿Qué hay que hacer?" className={ic + " resize-none"} /></div>
          <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Tipo</label><select value={taskForm.tipo_tarea_id} onChange={(e) => setTaskForm({ ...taskForm, tipo_tarea_id: e.target.value })} className={ic}><option value="">Sin tipo</option>{tiposTarea.map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}</select></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Prioridad</label><select value={taskForm.prioridad} onChange={(e) => setTaskForm({ ...taskForm, prioridad: e.target.value })} className={ic}><option value="alta">Alta</option><option value="media">Media</option><option value="baja">Baja</option></select></div></div>
          <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Fecha límite</label><input type="date" value={taskForm.fecha_limite} onChange={(e) => setTaskForm({ ...taskForm, fecha_limite: e.target.value })} className={ic} /></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Asignar a</label><select value={taskForm.asignado_a} onChange={(e) => setTaskForm({ ...taskForm, asignado_a: e.target.value })} className={ic}><option value="">Sin asignar</option>{rrhh.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select></div></div>
          <div className="flex justify-end gap-2 pt-2"><button type="button" onClick={() => setTaskModal(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button><button type="submit" disabled={taskSaving || !taskForm.descripcion} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{taskSaving && <Loader2 className="w-4 h-4 animate-spin" />}Crear</button></div>
        </form>
      </Modal>
      <Modal open={!!completeModal} onClose={() => setCompleteModal(null)} title="Completar tarea" size="sm">
        <div className="space-y-4"><p className="text-sm text-surface-700">{completeModal?.descripcion}</p><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Comentario</label><textarea value={completeComment} onChange={(e) => setCompleteComment(e.target.value)} rows={2} placeholder="Opcional" className={ic + " resize-none"} /></div><div className="flex justify-end gap-2"><button onClick={() => setCompleteModal(null)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button><button onClick={handleCompleteTask} className="px-4 py-2.5 text-sm font-medium text-white bg-emerald-500 rounded-lg hover:bg-emerald-600">Completar</button></div></div>
      </Modal>
      <Modal open={!!editTask} onClose={() => setEditTask(null)} title={editTask?.estado === "completada" ? "Tarea completada" : "Editar tarea"}>
        <form onSubmit={handleSaveEditTask} className="space-y-4">
          {editTask?.estado === "completada" && <div className="p-3 bg-emerald-50 border border-emerald-200 rounded-lg"><p className="text-xs font-semibold text-emerald-700 mb-1">Completada el {editTask.completada_at ? new Date(editTask.completada_at).toLocaleDateString("es-ES") : ""}</p>{editTask.comentario_cierre && <p className="text-sm text-emerald-800 italic">"{editTask.comentario_cierre}"</p>}</div>}
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Descripción *</label><textarea required value={editTaskForm.descripcion} onChange={(e) => setEditTaskForm({ ...editTaskForm, descripcion: e.target.value })} rows={3} className={ic + " resize-none"} disabled={editTask?.estado === "completada"} /></div>
          <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Tipo</label><select value={editTaskForm.tipo_tarea_id} onChange={(e) => setEditTaskForm({ ...editTaskForm, tipo_tarea_id: e.target.value })} className={ic} disabled={editTask?.estado === "completada"}><option value="">Sin tipo</option>{tiposTarea.map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}</select></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Prioridad</label><select value={editTaskForm.prioridad} onChange={(e) => setEditTaskForm({ ...editTaskForm, prioridad: e.target.value })} className={ic} disabled={editTask?.estado === "completada"}><option value="alta">Alta</option><option value="media">Media</option><option value="baja">Baja</option></select></div></div>
          <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Fecha límite</label><input type="date" value={editTaskForm.fecha_limite} onChange={(e) => setEditTaskForm({ ...editTaskForm, fecha_limite: e.target.value })} className={ic} disabled={editTask?.estado === "completada"} /></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Asignar a</label><select value={editTaskForm.asignado_a} onChange={(e) => setEditTaskForm({ ...editTaskForm, asignado_a: e.target.value })} className={ic} disabled={editTask?.estado === "completada"}><option value="">Sin asignar</option>{rrhh.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select></div></div>
          <div className="flex items-center justify-between pt-2">
            {editTask?.estado === "completada" ? <button type="button" onClick={() => editTask && handleReopenTask(editTask.id)} className="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium text-amber-700 bg-amber-50 rounded-lg hover:bg-amber-100"><Clock className="w-4 h-4" />Reabrir</button> :
              <button type="button" onClick={() => { setEditTask(null); setCompleteModal(editTask); }} className="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium text-emerald-700 bg-emerald-50 rounded-lg hover:bg-emerald-100"><CheckCircle2 className="w-4 h-4" />Hecha</button>}
            <div className="flex items-center gap-2"><button type="button" onClick={() => setEditTask(null)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cerrar</button>
              {editTask?.estado !== "completada" && <button type="submit" disabled={editTaskSaving || !editTaskForm.descripcion} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{editTaskSaving && <Loader2 className="w-4 h-4 animate-spin" />}Guardar</button>}</div>
          </div>
        </form>
      </Modal>
    </AppLayout>
  );
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\obras\[id]\obra-detail.tsx" -ForegroundColor Gray
$dst = "src\app\obras\[id]\obra-detail.tsx"
$content = @'
"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { useParams, useRouter } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import ResourceAvatar from "@/components/shared/ResourceAvatar";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { Obra, Asignacion, RecursoHumano, Maquinaria, Tarea, TipoTarea, EstadoObra, Documento, ParteDiario } from "@/lib/types/database";
import {
  Building2, ArrowLeft, MapPin, Users, Wrench, Truck, ClipboardList, FileText,
  Loader2, Plus, Trash2, CheckCircle2, Clock, ListTodo, Upload,
  File, Image as ImageIcon, Save, MessageSquare, ExternalLink, Pencil,
  FileSignature, Archive, Eye, AlertTriangle, Download
, Package2 } from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils/cn";
import ChecklistPanel from "@/components/obras/ChecklistPanel";

type Tab = "general" | "recursos" | "tareas" | "partes" | "documentos" | "checklists" | "almacen";

export default function ObraDetallePage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { user } = useAuthStore();
  const { isAdmin } = usePermissions();
  const supabase = createClient();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [obra, setObra] = useState<Obra | null>(null);
  const [asignaciones, setAsignaciones] = useState<Asignacion[]>([]);
  const [tareas, setTareas] = useState<Tarea[]>([]);
  const [tiposTarea, setTiposTarea] = useState<TipoTarea[]>([]);
  const [estados, setEstados] = useState<EstadoObra[]>([]);
  const [rrhh, setRrhh] = useState<RecursoHumano[]>([]);
  const [maq, setMaq] = useState<Record<string, Maquinaria>>({});
  const [veh, setVeh] = useState<Record<string, any>>({});
  const [documentos, setDocumentos] = useState<Documento[]>([]);
  const [partes, setPartes] = useState<any[]>([]);
  const [stockObra, setStockObra] = useState<any[]>([]);
  const [almacenObraId, setAlmacenObraId] = useState<string | null>(null);
  const [creandoAlmacen, setCreandoAlmacen] = useState(false);
  const [tiposObra, setTiposObra] = useState<any[]>([]);
  const [obraTipos, setObraTipos] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<Tab>("general");
  const [observaciones, setObservaciones] = useState("");
  const [obsSaving, setObsSaving] = useState(false);
  const [obsChanged, setObsChanged] = useState(false);
  const [downloadingPdf, setDownloadingPdf] = useState(false);
  const [taskModal, setTaskModal] = useState(false);
  const [taskForm, setTaskForm] = useState({ descripcion: "", tipo_tarea_id: "", prioridad: "media" as any, fecha_limite: "", asignado_a: "" });
  const [taskSaving, setTaskSaving] = useState(false);
  const [completeModal, setCompleteModal] = useState<Tarea | null>(null);
  const [completeComment, setCompleteComment] = useState("");
  const [editTask, setEditTask] = useState<Tarea | null>(null);
  const [editTaskForm, setEditTaskForm] = useState({ descripcion: "", tipo_tarea_id: "", prioridad: "media" as any, fecha_limite: "", asignado_a: "" });
  const [editTaskSaving, setEditTaskSaving] = useState(false);
  const [uploading, setUploading] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [obraRes, asigRes, tareasRes, tiposRes, estadosRes, rrhhRes, maqRes, vehRes, docsRes, partesRes, tiposObraRes, obraTiposRes] = await Promise.all([
      supabase.from("obras").select("*, cliente:clientes(*), estado_custom:estados_obra(*)").eq("id", id).single(),
      supabase.from("asignaciones").select("*").eq("obra_id", id),
      supabase.from("tareas").select("*, tipo_tarea:tipo_tarea(nombre), recurso_asignado:recursos_humanos(nombre, foto_url)").eq("obra_id", id).order("created_at", { ascending: false }),
      supabase.from("tipo_tarea").select("*").eq("activo", true).order("nombre"),
      supabase.from("estados_obra").select("*").eq("activo", true).order("nombre"),
      supabase.from("recursos_humanos").select("*").eq("activo", true),
      supabase.from("maquinaria").select("*").eq("activo", true),
      supabase.from("vehiculos").select("*").eq("activo", true),
      supabase.from("documentos").select("*").eq("obra_id", id).is("parte_id", null).order("created_at", { ascending: false }),
      supabase.from("partes_diarios").select("*, creator:users!partes_diarios_created_by_fkey(nombre)").eq("obra_id", id).order("fecha", { ascending: false }),
      supabase.from("tipos_obra").select("*").eq("activo", true).order("nombre"),
      supabase.from("obra_tipos_obra").select("tipo_obra_id").eq("obra_id", id),
    ]);
    const obraData = obraRes.data as Obra | null;
    setObra(obraData); setObservaciones(obraData?.observaciones || ""); setObsChanged(false);
    setAsignaciones(asigRes.data || []); setTareas((tareasRes.data as any[]) || []);
    setTiposTarea(tiposRes.data || []); setEstados(estadosRes.data || []);
    setRrhh(rrhhRes.data || []); setDocumentos((docsRes.data as Documento[]) || []);
    setPartes(partesRes.data || []); setTiposObra(tiposObraRes.data || []);
    // Stock del almacen de la obra
    try {
      const { data: almacenObraR } = await (supabase.from("almacenes") as any).select("id").eq("obra_id", id).eq("activo", true).maybeSingle();
      if (almacenObraR?.id) {
        setAlmacenObraId(almacenObraR.id);
        const { data: stockR } = await (supabase.from("v_stock_actual") as any).select("*").eq("almacen_id", almacenObraR.id);
        setStockObra(stockR || []);
      } else {
        setAlmacenObraId(null);
        setStockObra([]);
      }
    } catch { /* tabla almacen puede no existir aun */ }
    setObraTipos((obraTiposRes.data || []).map((t: any) => t.tipo_obra_id));
    const maqMap: Record<string, any> = {}; (maqRes.data || []).forEach((r: any) => maqMap[r.id] = r); setMaq(maqMap);
    const vehMap: Record<string, any> = {}; (vehRes.data || []).forEach((r: any) => vehMap[r.id] = r); setVeh(vehMap);
    setLoading(false);
  }, [id]);
  useEffect(() => { fetchData(); }, [fetchData]);

  const handleChangeEstado = async (estadoId: string) => { await (supabase.from("obras") as any).update({ estado_obra_id: estadoId || null }).eq("id", id); fetchData(); };
  const handleSaveObservaciones = async () => { setObsSaving(true); await (supabase.from("obras") as any).update({ observaciones }).eq("id", id); setObsSaving(false); setObsChanged(false); };
  const handleArchive = async () => {
    const newArchived = !obra?.archivada;
    const update: any = { archivada: newArchived };
    if (newArchived) { const cerrada = estados.find((e) => e.nombre.toLowerCase().includes("terminada") || e.nombre.toLowerCase().includes("cerrada")); if (cerrada) update.estado_obra_id = cerrada.id; }
    await (supabase.from("obras") as any).update(update).eq("id", id); fetchData();
  };
  const handleDelete = async () => {
    if (!confirm(`¿Seguro que quieres ELIMINAR la obra "${obra?.nombre}"?\n\nSe borrarán todas las asignaciones, tareas, partes y documentos asociados.\n\nEsta acción no se puede deshacer.`)) return;
    await (supabase.from("obras") as any).delete().eq("id", id);
    router.push("/obras");
  };
  const handleCreateTask = async (e: React.FormEvent) => { e.preventDefault(); setTaskSaving(true); await (supabase.from("tareas") as any).insert({ obra_id: id, descripcion: taskForm.descripcion, tipo_tarea_id: taskForm.tipo_tarea_id || null, prioridad: taskForm.prioridad, fecha_limite: taskForm.fecha_limite || null, asignado_a: taskForm.asignado_a || null, created_by: user?.id }); setTaskSaving(false); setTaskModal(false); setTaskForm({ descripcion: "", tipo_tarea_id: "", prioridad: "media", fecha_limite: "", asignado_a: "" }); fetchData(); };
  const handleCompleteTask = async () => { if (!completeModal) return; await (supabase.from("tareas") as any).update({ estado: "completada", comentario_cierre: completeComment || null, completada_at: new Date().toISOString(), completada_by: user?.id }).eq("id", completeModal.id); setCompleteModal(null); setCompleteComment(""); fetchData(); };
  const handleDeleteTask = async (taskId: string) => { await (supabase.from("tareas") as any).delete().eq("id", taskId); fetchData(); };
  const handleReopenTask = async (taskId: string) => { await (supabase.from("tareas") as any).update({ estado: "pendiente" }).eq("id", taskId); setEditTask(null); fetchData(); };
  const handleOpenEditTask = (t: Tarea) => { setEditTask(t); setEditTaskForm({ descripcion: t.descripcion, tipo_tarea_id: t.tipo_tarea_id || "", prioridad: t.prioridad, fecha_limite: t.fecha_limite || "", asignado_a: t.asignado_a || "" }); };
  const handleSaveEditTask = async (e: React.FormEvent) => { e.preventDefault(); if (!editTask) return; setEditTaskSaving(true); await (supabase.from("tareas") as any).update({ descripcion: editTaskForm.descripcion, tipo_tarea_id: editTaskForm.tipo_tarea_id || null, prioridad: editTaskForm.prioridad, fecha_limite: editTaskForm.fecha_limite || null, asignado_a: editTaskForm.asignado_a || null }).eq("id", editTask.id); setEditTaskSaving(false); setEditTask(null); fetchData(); };
  const handleOpenDoc = async (doc: Documento) => { const { data } = await supabase.storage.from("documentos").createSignedUrl(doc.storage_path, 300); if (data?.signedUrl) window.open(data.signedUrl, "_blank"); };
  const handleDeleteDoc = async (doc: Documento) => { await supabase.storage.from("documentos").remove([doc.storage_path]); await (supabase.from("documentos") as any).delete().eq("id", doc.id); fetchData(); };
  const handleUploadFile = async (e: React.ChangeEvent<HTMLInputElement>) => { const files = e.target.files; if (!files) return; setUploading(true); for (let i = 0; i < files.length; i++) { const file = files[i]; const path = `obras/${id}/${Date.now()}_${file.name}`; const { error } = await supabase.storage.from("documentos").upload(path, file); if (error) continue; await (supabase.from("documentos") as any).insert({ obra_id: id, nombre_archivo: file.name, tipo: file.type.startsWith("image/") ? "foto" : file.type === "application/pdf" ? "pdf" : "documento", categoria: "general", storage_path: path, tamano: file.size, mime_type: file.type, uploaded_by: user?.id }); } setUploading(false); if (fileInputRef.current) fileInputRef.current.value = ""; fetchData(); };
  const getTaskDateColor = (f: string | null) => { if (!f) return ""; const d = (new Date(f).getTime() - Date.now()) / 86400000; if (d < 0) return "text-red-600 bg-red-50"; if (d < 3) return "text-amber-600 bg-amber-50"; return "text-surface-600"; };
  const formatBytes = (b: number | null) => { if (!b) return ""; if (b < 1024) return b + " B"; if (b < 1048576) return (b / 1024).toFixed(0) + " KB"; return (b / 1048576).toFixed(1) + " MB"; };

  if (loading) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;
  if (!obra) return <AppLayout><div className="text-center py-20"><p className="text-surface-500">Obra no encontrada</p></div></AppLayout>;

  const tabs: { id: Tab; label: string; icon: typeof Building2; count?: number }[] = [
    { id: "general", label: "General", icon: Building2 },
    { id: "recursos", label: "Recursos", icon: Users, count: asignaciones.length },
    { id: "tareas", label: "Tareas", icon: ListTodo, count: tareas.filter((t) => t.estado === "pendiente").length },
    { id: "partes", label: "Partes", icon: ClipboardList, count: partes.length },
    { id: "documentos", label: "Documentos", icon: FileText, count: documentos.length },
    { id: "checklists", label: "Checklists", icon: CheckCircle2 },
    { id: "almacen", label: "Almacén", icon: Package2, count: stockObra.length },
  ];
  const humanos = asignaciones.filter((a) => a.recurso_tipo === "humano");
  const maquinas = asignaciones.filter((a) => a.recurso_tipo === "maquinaria");
  const vehiculos = asignaciones.filter((a) => a.recurso_tipo === "vehiculo");
  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  const prioColors: Record<string, string> = { alta: "bg-red-100 text-red-700", media: "bg-amber-100 text-amber-700", baja: "bg-blue-100 text-blue-700" };
  const estadoBadgeParte: Record<string, { label: string; class: string }> = { pendiente: { label: "Pendiente", class: "bg-amber-100 text-amber-700" }, firmado: { label: "Firmado", class: "bg-emerald-100 text-emerald-700" }, borrador: { label: "Borrador", class: "bg-surface-100 text-surface-600" } };
  const obraTipoNames = obraTipos.map((tid) => tiposObra.find((t: any) => t.id === tid)?.nombre).filter(Boolean);

  return (
    <AppLayout>
      <div className="max-w-5xl mx-auto animate-fade-in">
        {/* Header */}
        <div className="flex items-start gap-4 mb-6">
          <Link href="/obras" className="p-2 mt-1 rounded-lg text-surface-400 hover:bg-surface-100"><ArrowLeft className="w-5 h-5" /></Link>
          <div className="flex-1">
            <div className="flex items-center gap-3">
              <div className="w-3 h-10 rounded-full" style={{ backgroundColor: obra.color || "#DC2626" }} />
              <div>
                <div className="flex items-center gap-2">
                  <h1 className="text-xl font-display font-bold text-surface-900">{obra.nombre}</h1>
                  {obra.archivada && <span className="badge bg-surface-200 text-surface-600 text-[10px]">Archivada</span>}
                </div>
                <div className="flex items-center gap-3 mt-1 text-sm text-surface-500">
                  {obra.direccion && <span className="flex items-center gap-1"><MapPin className="w-3.5 h-3.5" />{obra.direccion}{obra.localidad ? `, ${obra.localidad}` : ""}</span>}
                  {(obra as any).cliente?.nombre && <span>· {(obra as any).cliente.nombre}</span>}
                </div>
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <button onClick={async () => {
              setDownloadingPdf(true);
              try {
                const res = await fetch("/api/obras/pdf", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ obraId: id }) });
                const data = await res.json();
                if (data.pdf) { const link = document.createElement("a"); link.href = `data:application/pdf;base64,${data.pdf}`; link.download = data.filename; link.click(); }
                else alert("Error: " + (data.error || ""));
              } catch (err: any) { alert("Error: " + err.message); }
              setDownloadingPdf(false);
            }} disabled={downloadingPdf} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-violet-700 bg-violet-50 rounded-lg hover:bg-violet-100 disabled:opacity-60">
              {downloadingPdf ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Download className="w-3.5 h-3.5" />} PDF
            </button>
            <button onClick={handleArchive} className={cn("flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg", obra.archivada ? "text-blue-700 bg-blue-50 hover:bg-blue-100" : "text-amber-700 bg-amber-50 hover:bg-amber-100")}>
              {obra.archivada ? <Eye className="w-3.5 h-3.5" /> : <Archive className="w-3.5 h-3.5" />}
              {obra.archivada ? "Desarchivar" : "Archivar"}
            </button>
            <button onClick={handleDelete} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-red-700 bg-red-50 rounded-lg hover:bg-red-100">
              <Trash2 className="w-3.5 h-3.5" /> Eliminar
            </button>
            <Link href={`/obras/nueva?edit=${id}`} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">
              <Pencil className="w-3.5 h-3.5" /> Editar
            </Link>
            <select value={obra.estado_obra_id || ""} onChange={(e) => handleChangeEstado(e.target.value)}
              className="px-3 py-1.5 rounded-full text-sm font-medium text-white border-0 cursor-pointer focus:outline-none"
              style={{ backgroundColor: (obra as any).estado_custom?.color || "#6B7280" }}>
              <option value="">Sin estado</option>
              {estados.map((es) => <option key={es.id} value={es.id}>{es.nombre}</option>)}
            </select>
          </div>
        </div>

        {/* Tabs */}
        <div className="flex gap-1 mb-6 border-b border-surface-200 overflow-x-auto">
          {tabs.map((t) => (
            <button key={t.id} onClick={() => setTab(t.id)}
              className={cn("flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 transition-all -mb-px whitespace-nowrap",
                tab === t.id ? "border-brand-500 text-brand-600" : "border-transparent text-surface-500 hover:text-surface-700")}>
              <t.icon className="w-4 h-4" />{t.label}
              {t.count !== undefined && t.count > 0 && <span className="text-[10px] bg-brand-100 text-brand-700 px-1.5 py-0.5 rounded-full">{t.count}</span>}
            </button>
          ))}
        </div>

        {/* GENERAL - all fields */}
        {tab === "general" && (
          <div className="space-y-6">
            <div className="card p-6">
              <h3 className="text-sm font-semibold text-surface-900 mb-4">Datos generales</h3>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Cliente</p><p className="text-sm text-surface-900 mt-1">{(obra as any).cliente?.nombre || "—"}</p></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Tipos de obra</p><div className="flex flex-wrap gap-1 mt-1.5">{obraTipoNames.length > 0 ? obraTipoNames.map((n, i) => <span key={i} className="text-xs px-2 py-0.5 rounded-full bg-brand-50 text-brand-700 border border-brand-200">{n}</span>) : <span className="text-sm text-surface-400">—</span>}</div></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Estado</p><div className="mt-1">{(obra as any).estado_custom ? <span className="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium text-white" style={{ backgroundColor: (obra as any).estado_custom.color }}>{(obra as any).estado_custom.nombre}</span> : <span className="text-sm text-surface-400">Sin estado</span>}</div></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Nº Presupuesto</p><p className="text-sm text-surface-900 mt-1">{(obra as any).num_presupuesto || "—"}</p></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Nº Factura</p><p className="text-sm text-surface-900 mt-1">{(obra as any).num_factura || "—"}</p></div>
              </div>
            </div>

            <div className="card p-6">
              <h3 className="text-sm font-semibold text-surface-900 mb-4">Dirección</h3>
              <div className="grid grid-cols-3 gap-4">
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Dirección</p><p className="text-sm text-surface-900 mt-1">{obra.direccion || "—"}</p></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Localidad</p><p className="text-sm text-surface-900 mt-1">{obra.localidad || "—"}</p></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Provincia</p><p className="text-sm text-surface-900 mt-1">{obra.provincia || "—"}</p></div>
              </div>
            </div>

            <div className="card p-6">
              <h3 className="text-sm font-semibold text-surface-900 mb-4">Contacto</h3>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-[10px] font-semibold text-surface-400 uppercase mb-2">Cliente</p>
                  <p className="text-sm text-surface-900">{(obra as any).cliente?.nombre || "—"}</p>
                  <p className="text-xs text-surface-500">{(obra as any).cliente?.telefono || ""} {(obra as any).cliente?.email ? `· ${(obra as any).cliente.email}` : ""}</p>
                </div>
                <div>
                  <p className="text-[10px] font-semibold text-surface-400 uppercase mb-2">Contacto obra</p>
                  <p className="text-sm text-surface-900">{(obra as any).contacto_obra_nombre || "—"}</p>
                  <p className="text-xs text-surface-500">{(obra as any).contacto_obra_telefono || ""} {(obra as any).contacto_obra_email ? `· ${(obra as any).contacto_obra_email}` : ""}</p>
                </div>
              </div>
            </div>

            <div className="card p-6">
              <div className="flex items-center justify-between mb-3">
                <h3 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><MessageSquare className="w-4 h-4 text-surface-400" />Comentarios</h3>
                {obsChanged && <button onClick={handleSaveObservaciones} disabled={obsSaving} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{obsSaving ? <Loader2 className="w-3 h-3 animate-spin" /> : <Save className="w-3 h-3" />}Guardar</button>}
              </div>
              <textarea value={observaciones} onChange={(e) => { setObservaciones(e.target.value); setObsChanged(true); }} rows={4} placeholder="Notas, comentarios..." className={ic + " resize-y"} />
            </div>
          </div>
        )}

        {/* RECURSOS */}
        {tab === "recursos" && (
          <div className="space-y-4">
            {[{ title: "Personas", icon: Users, tipo: "humano" as const, items: humanos, getName: (rid: string) => rrhh.find((r) => r.id === rid)?.nombre || "?" },
              { title: "Maquinaria", icon: Wrench, tipo: "maquinaria" as const, items: maquinas, getName: (rid: string) => maq[rid]?.nombre || "?" },
              { title: "Vehículos", icon: Truck, tipo: "vehiculo" as const, items: vehiculos, getName: (rid: string) => veh[rid]?.nombre || "?" },
            ].map((g) => {
              // Group by resource, collect date ranges
              const grouped: Record<string, { nombre: string; ranges: { inicio: string; fin: string }[] }> = {};
              g.items.forEach((a) => {
                if (!grouped[a.recurso_id]) grouped[a.recurso_id] = { nombre: g.getName(a.recurso_id), ranges: [] };
                grouped[a.recurso_id].ranges.push({ inicio: a.fecha_inicio, fin: a.fecha_fin });
              });
              // Sort ranges and merge
              Object.values(grouped).forEach((v) => v.ranges.sort((a, b) => a.inicio.localeCompare(b.inicio)));
              const sortedResources = Object.entries(grouped).sort((a, b) => a[1].nombre.localeCompare(b[1].nombre, "es"));

              return (
                <div key={g.title} className="card p-6">
                  <h3 className="flex items-center gap-2 text-sm font-semibold text-surface-900 mb-3"><g.icon className="w-4 h-4 text-surface-400" />{g.title} ({sortedResources.length})</h3>
                  {sortedResources.length === 0 ? <p className="text-sm text-surface-400">Sin asignaciones</p> : (
                    <table className="w-full text-sm">
                      <thead><tr className="border-b border-surface-200">
                        <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2 w-[200px]">Recurso</th>
                        <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Fechas</th>
                        <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-2 w-[80px]">Días</th>
                      </tr></thead>
                      <tbody>{sortedResources.map(([rid, v]) => {
                        const totalDays = v.ranges.reduce((sum, r) => {
                          const s = new Date(r.inicio + "T12:00:00"); const e = new Date(r.fin + "T12:00:00");
                          return sum + Math.round((e.getTime() - s.getTime()) / 86400000) + 1;
                        }, 0);
                        return (
                          <tr key={rid} className="border-b border-surface-50 hover:bg-surface-50/50">
                            <td className="py-2 px-2 font-medium text-surface-900">{v.nombre}</td>
                            <td className="py-2 px-2">
                              <div className="flex flex-wrap gap-1">
                                {v.ranges.map((r, i) => {
                                  const s = new Date(r.inicio + "T12:00:00");
                                  const e = new Date(r.fin + "T12:00:00");
                                  const same = r.inicio === r.fin;
                                  const label = same
                                    ? s.toLocaleDateString("es-ES", { weekday: "short", day: "numeric", month: "short" })
                                    : `${s.toLocaleDateString("es-ES", { day: "numeric", month: "short" })} → ${e.toLocaleDateString("es-ES", { day: "numeric", month: "short" })}`;
                                  return <span key={i} className="text-[10px] px-2 py-0.5 rounded bg-brand-50 text-brand-700">{label}</span>;
                                })}
                              </div>
                            </td>
                            <td className="py-2 px-2 text-right text-surface-600 font-medium">{totalDays}</td>
                          </tr>
                        );
                      })}</tbody>
                    </table>
                  )}
                </div>
              );
            })}
          </div>
        )}

        {/* TAREAS */}
        {tab === "tareas" && (
          <div className="card p-6">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-sm font-semibold text-surface-900">Tareas</h3>
              <button onClick={() => setTaskModal(true)} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-3.5 h-3.5" />Nueva</button>
            </div>
            {tareas.length === 0 ? <p className="text-sm text-surface-500 text-center py-8">Sin tareas</p> : (
              <div className="space-y-2">
                {tareas.map((t) => (
                  <div key={t.id} className={cn("flex items-start gap-3 p-3 rounded-lg border", t.estado === "completada" ? "bg-surface-50 border-surface-100 opacity-60" : "bg-white border-surface-200")}>
                    <button onClick={() => t.estado === "pendiente" ? setCompleteModal(t) : null} className={cn("mt-0.5 shrink-0", t.estado === "completada" ? "text-emerald-500" : "text-surface-300 hover:text-emerald-500")}><CheckCircle2 className="w-5 h-5" /></button>
                    <div className="flex-1 min-w-0 cursor-pointer" onClick={() => handleOpenEditTask(t)}>
                      <p className={cn("text-sm hover:text-brand-600", t.estado === "completada" ? "line-through text-surface-400" : "text-surface-900")}>{t.descripcion}</p>
                      <div className="flex items-center gap-2 mt-1 flex-wrap">
                        <span className={cn("badge text-[10px]", prioColors[t.prioridad])}>{t.prioridad}</span>
                        {(t as any).tipo_tarea?.nombre && <span className="badge bg-surface-100 text-surface-600 text-[10px]">{(t as any).tipo_tarea.nombre}</span>}
                        {(t as any).recurso_asignado?.nombre && <ResourceAvatar nombre={(t as any).recurso_asignado.nombre} foto_url={(t as any).recurso_asignado.foto_url} tipo="humano" size="xs" />}
                        {t.fecha_limite && <span className={cn("text-[10px] px-1.5 py-0.5 rounded", getTaskDateColor(t.fecha_limite))}><Clock className="w-3 h-3 inline mr-0.5" />{new Date(t.fecha_limite).toLocaleDateString("es-ES")}</span>}
                      </div>
                      {t.comentario_cierre && <p className="text-[11px] text-surface-400 mt-1 italic">"{t.comentario_cierre}"</p>}
                    </div>
                    {t.estado === "pendiente" && <button onClick={() => handleDeleteTask(t.id)} className="p-1 rounded text-surface-300 hover:text-red-500"><Trash2 className="w-3.5 h-3.5" /></button>}
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* PARTES */}
        {tab === "partes" && (
          <div className="card p-6">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-sm font-semibold text-surface-900">Partes diarios</h3>
              <button onClick={async () => {
                const toDS = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
                const { data: p } = await (supabase.from("partes_diarios") as any).insert({
                  fecha: toDS(new Date()), created_by: user?.id, estado: "pendiente", obra_id: id,
                  direccion: obra?.direccion || null, localidad: obra?.localidad || null, provincia: obra?.provincia || null,
                  responsable_empresa: user?.nombre || "",
                }).select().single();
                if (p) router.push(`/partes/${p.id}`);
              }} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-3.5 h-3.5" />Nuevo parte</button>
            </div>
            {partes.length === 0 ? <p className="text-sm text-surface-500 text-center py-8">Sin partes</p> : (
              <div className="space-y-2">{partes.map((p) => {
                const est = estadoBadgeParte[p.estado] || estadoBadgeParte.pendiente;
                return (
                  <Link key={p.id} href={`/partes/${p.id}`} className="flex items-center gap-4 p-3 bg-surface-50 rounded-lg border border-surface-100 hover:border-surface-300 group">
                    <div className="text-center shrink-0 w-12"><p className="text-lg font-display font-bold text-surface-900">{new Date(p.fecha + "T12:00:00").getDate()}</p><p className="text-[9px] text-surface-400 uppercase">{new Date(p.fecha + "T12:00:00").toLocaleDateString("es-ES", { month: "short" })}</p></div>
                    <div className="flex-1 min-w-0"><p className="text-sm font-medium text-surface-900 group-hover:text-brand-600">{p.creator?.nombre || "?"}</p><p className="text-xs text-surface-400 truncate">{p.observaciones || ""}</p></div>
                    <div className="flex items-center gap-2 shrink-0">
                      {p.firma_data && <FileSignature className="w-3.5 h-3.5 text-emerald-500" />}
                      {p.firma_cliente && <FileSignature className="w-3.5 h-3.5 text-blue-500" />}
                    </div>
                    <span className={cn("badge text-[10px]", est.class)}>{est.label}</span>
                  </Link>
                );
              })}</div>
            )}
          </div>
        )}

        {/* DOCUMENTOS */}
        {tab === "documentos" && (
          <div className="card p-6">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-sm font-semibold text-surface-900">Documentos</h3>
              <button onClick={() => fileInputRef.current?.click()} disabled={uploading} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{uploading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Upload className="w-3.5 h-3.5" />}Subir</button>
              <input ref={fileInputRef} type="file" multiple accept="image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt" className="hidden" onChange={handleUploadFile} />
            </div>
            {documentos.length === 0 ? <div className="text-center py-12 border-2 border-dashed border-surface-200 rounded-xl"><Upload className="w-8 h-8 text-surface-300 mx-auto mb-2" /><p className="text-sm text-surface-500">Sin documentos</p></div> : (
              <div className="space-y-2">{documentos.map((doc) => {
                const isImage = doc.tipo === "foto"; const isPdf = doc.tipo === "pdf";
                return (
                  <div key={doc.id} className="flex items-center gap-3 p-3 bg-surface-50 rounded-lg border border-surface-100 group hover:border-surface-200">
                    <div className={cn("w-10 h-10 rounded-lg flex items-center justify-center shrink-0", isImage ? "bg-violet-100 text-violet-600" : isPdf ? "bg-red-100 text-red-600" : "bg-blue-100 text-blue-600")}>{isImage ? <ImageIcon className="w-5 h-5" /> : isPdf ? <FileText className="w-5 h-5" /> : <File className="w-5 h-5" />}</div>
                    <div className="flex-1 min-w-0 cursor-pointer" onClick={() => handleOpenDoc(doc)}><p className="text-sm font-medium text-surface-900 hover:text-brand-600 truncate">{doc.nombre_archivo}</p><p className="text-[11px] text-surface-400">{formatBytes(doc.tamano)}</p></div>
                    <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100"><button onClick={() => handleOpenDoc(doc)} className="p-1.5 rounded-md text-surface-400 hover:text-brand-600"><ExternalLink className="w-4 h-4" /></button><button onClick={() => handleDeleteDoc(doc)} className="p-1.5 rounded-md text-surface-400 hover:text-red-600"><Trash2 className="w-4 h-4" /></button></div>
                  </div>
                );
              })}</div>
            )}
          </div>
        )}

        {tab === "checklists" && (
          <ChecklistPanel obraId={id} rrhh={rrhh.map((r) => ({ id: r.id, nombre: r.nombre }))} />
        )}

        {tab === "almacen" && (
          <div className="space-y-4">
            {!almacenObraId ? (
              <div className="card p-8 text-center">
                <Package2 className="w-10 h-10 mx-auto mb-3 text-surface-300" />
                <p className="text-sm text-surface-600 mb-1 font-medium">Esta obra no tiene almacén asociado</p>
                <p className="text-xs text-surface-400 mb-5">
                  El código se generará como OBRA-{(obra as any)?.num_presupuesto || (id as string).slice(0, 8).toUpperCase()}.
                </p>
                {isAdmin && (
                  <button
                    disabled={creandoAlmacen}
                    onClick={async () => {
                      setCreandoAlmacen(true);
                      try {
                        const { error } = await (supabase.rpc as any)("crear_almacen_obra", { p_obra_id: id });
                        if (error) throw error;
                        fetchData();
                      } catch (err: any) {
                        alert("Error: " + (err?.message || err));
                      } finally { setCreandoAlmacen(false); }
                    }}
                    className="flex items-center gap-2 mx-auto px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
                    {creandoAlmacen ? <Loader2 className="w-4 h-4 animate-spin" /> : <Package2 className="w-4 h-4" />}
                    Crear almacén de esta obra
                  </button>
                )}
              </div>
            ) : (
              <div className="card overflow-hidden">
                <div className="px-4 py-3 border-b border-surface-100 bg-surface-50 flex items-center justify-between">
                  <h3 className="text-sm font-semibold text-surface-700">
                    Stock del almacén · resumen
                    {stockObra.filter((s: any) => s.stock_negativo).length > 0 && (
                      <span className="ml-2 badge text-[10px] bg-red-100 text-red-700">
                        {stockObra.filter((s: any) => s.stock_negativo).length} negativos
                      </span>
                    )}
                    {stockObra.filter((s: any) => s.bajo_minimo && !s.stock_negativo).length > 0 && (
                      <span className="ml-1 badge text-[10px] bg-amber-100 text-amber-700">
                        {stockObra.filter((s: any) => s.bajo_minimo && !s.stock_negativo).length} bajo mín.
                      </span>
                    )}
                  </h3>
                  <a href={"/obras/" + id + "/almacen"}
                    className="flex items-center gap-1 text-xs text-brand-600 hover:text-brand-700 font-medium">
                    Ver almacén completo con movimientos →
                  </a>
                </div>
                {stockObra.length === 0 ? (
                  <div className="text-center py-8 text-sm text-surface-400">Sin stock registrado todavía</div>
                ) : (
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-surface-100">
                        <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Artículo</th>
                        <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Cód. artículo</th>
                        <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Tipo</th>
                        <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Stock</th>
                        <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden sm:table-cell">Mín.</th>
                        <th className="text-center text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Estado</th>
                      </tr>
                    </thead>
                    <tbody>
                      {stockObra.slice(0, 15).map((s: any, i: number) => (
                        <tr key={i} className={cn("border-b border-surface-50",
                          s.stock_negativo ? "bg-red-50/40" : s.bajo_minimo ? "bg-amber-50/20" : "hover:bg-surface-50/50")}>
                          <td className="px-4 py-2.5 font-medium text-surface-900 text-xs">{s.nombre}</td>
                          <td className="px-4 py-2.5 font-mono text-[10px] text-surface-500 hidden md:table-cell">{s.codigo_articulo}</td>
                          <td className="px-4 py-2.5 text-xs text-surface-500">{s.tipo}</td>
                          <td className={cn("px-4 py-2.5 text-right font-mono text-sm font-semibold",
                            s.stock_negativo ? "text-red-600" : s.bajo_minimo ? "text-amber-600" : "text-surface-900")}>
                            {s.stock_negativo && "⚠ "}
                            {Number(s.stock_qty).toFixed(2)} <span className="text-[10px] font-normal">{s.unidad}</span>
                          </td>
                          <td className="px-4 py-2.5 text-right font-mono text-xs text-surface-400 hidden sm:table-cell">
                            {s.stock_minimo_def > 0 ? Number(s.stock_minimo_def).toFixed(2) : "—"}
                          </td>
                          <td className="px-4 py-2.5 text-center hidden lg:table-cell">
                            {s.stock_negativo && <span className="badge text-[9px] bg-red-100 text-red-700">Negativo</span>}
                            {s.bajo_minimo && !s.stock_negativo && <span className="badge text-[9px] bg-amber-100 text-amber-700">Bajo mín.</span>}
                            {!s.stock_negativo && !s.bajo_minimo && <span className="badge text-[9px] bg-emerald-100 text-emerald-700">OK</span>}
                          </td>
                        </tr>
                      ))}
                      {stockObra.length > 15 && (
                        <tr>
                          <td colSpan={6} className="px-4 py-3 text-center text-xs text-surface-400">
                            Mostrando 15 de {stockObra.length} artículos.{" "}
                            <a href={"/obras/" + id + "/almacen"} className="text-brand-600 hover:underline font-medium">
                              Ver todos →
                            </a>
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                )}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Task modals */}
      <Modal open={taskModal} onClose={() => setTaskModal(false)} title="Nueva tarea">
        <form onSubmit={handleCreateTask} className="space-y-4">
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Descripción *</label><textarea required value={taskForm.descripcion} onChange={(e) => setTaskForm({ ...taskForm, descripcion: e.target.value })} rows={3} placeholder="¿Qué hay que hacer?" className={ic + " resize-none"} /></div>
          <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Tipo</label><select value={taskForm.tipo_tarea_id} onChange={(e) => setTaskForm({ ...taskForm, tipo_tarea_id: e.target.value })} className={ic}><option value="">Sin tipo</option>{tiposTarea.map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}</select></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Prioridad</label><select value={taskForm.prioridad} onChange={(e) => setTaskForm({ ...taskForm, prioridad: e.target.value })} className={ic}><option value="alta">Alta</option><option value="media">Media</option><option value="baja">Baja</option></select></div></div>
          <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Fecha límite</label><input type="date" value={taskForm.fecha_limite} onChange={(e) => setTaskForm({ ...taskForm, fecha_limite: e.target.value })} className={ic} /></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Asignar a</label><select value={taskForm.asignado_a} onChange={(e) => setTaskForm({ ...taskForm, asignado_a: e.target.value })} className={ic}><option value="">Sin asignar</option>{rrhh.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select></div></div>
          <div className="flex justify-end gap-2 pt-2"><button type="button" onClick={() => setTaskModal(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button><button type="submit" disabled={taskSaving || !taskForm.descripcion} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{taskSaving && <Loader2 className="w-4 h-4 animate-spin" />}Crear</button></div>
        </form>
      </Modal>
      <Modal open={!!completeModal} onClose={() => setCompleteModal(null)} title="Completar tarea" size="sm">
        <div className="space-y-4"><p className="text-sm text-surface-700">{completeModal?.descripcion}</p><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Comentario</label><textarea value={completeComment} onChange={(e) => setCompleteComment(e.target.value)} rows={2} placeholder="Opcional" className={ic + " resize-none"} /></div><div className="flex justify-end gap-2"><button onClick={() => setCompleteModal(null)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button><button onClick={handleCompleteTask} className="px-4 py-2.5 text-sm font-medium text-white bg-emerald-500 rounded-lg hover:bg-emerald-600">Completar</button></div></div>
      </Modal>
      <Modal open={!!editTask} onClose={() => setEditTask(null)} title={editTask?.estado === "completada" ? "Tarea completada" : "Editar tarea"}>
        <form onSubmit={handleSaveEditTask} className="space-y-4">
          {editTask?.estado === "completada" && <div className="p-3 bg-emerald-50 border border-emerald-200 rounded-lg"><p className="text-xs font-semibold text-emerald-700 mb-1">Completada el {editTask.completada_at ? new Date(editTask.completada_at).toLocaleDateString("es-ES") : ""}</p>{editTask.comentario_cierre && <p className="text-sm text-emerald-800 italic">"{editTask.comentario_cierre}"</p>}</div>}
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Descripción *</label><textarea required value={editTaskForm.descripcion} onChange={(e) => setEditTaskForm({ ...editTaskForm, descripcion: e.target.value })} rows={3} className={ic + " resize-none"} disabled={editTask?.estado === "completada"} /></div>
          <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Tipo</label><select value={editTaskForm.tipo_tarea_id} onChange={(e) => setEditTaskForm({ ...editTaskForm, tipo_tarea_id: e.target.value })} className={ic} disabled={editTask?.estado === "completada"}><option value="">Sin tipo</option>{tiposTarea.map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}</select></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Prioridad</label><select value={editTaskForm.prioridad} onChange={(e) => setEditTaskForm({ ...editTaskForm, prioridad: e.target.value })} className={ic} disabled={editTask?.estado === "completada"}><option value="alta">Alta</option><option value="media">Media</option><option value="baja">Baja</option></select></div></div>
          <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Fecha límite</label><input type="date" value={editTaskForm.fecha_limite} onChange={(e) => setEditTaskForm({ ...editTaskForm, fecha_limite: e.target.value })} className={ic} disabled={editTask?.estado === "completada"} /></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Asignar a</label><select value={editTaskForm.asignado_a} onChange={(e) => setEditTaskForm({ ...editTaskForm, asignado_a: e.target.value })} className={ic} disabled={editTask?.estado === "completada"}><option value="">Sin asignar</option>{rrhh.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select></div></div>
          <div className="flex items-center justify-between pt-2">
            {editTask?.estado === "completada" ? <button type="button" onClick={() => editTask && handleReopenTask(editTask.id)} className="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium text-amber-700 bg-amber-50 rounded-lg hover:bg-amber-100"><Clock className="w-4 h-4" />Reabrir</button> :
              <button type="button" onClick={() => { setEditTask(null); setCompleteModal(editTask); }} className="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium text-emerald-700 bg-emerald-50 rounded-lg hover:bg-emerald-100"><CheckCircle2 className="w-4 h-4" />Hecha</button>}
            <div className="flex items-center gap-2"><button type="button" onClick={() => setEditTask(null)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cerrar</button>
              {editTask?.estado !== "completada" && <button type="submit" disabled={editTaskSaving || !editTaskForm.descripcion} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{editTaskSaving && <Loader2 className="w-4 h-4 animate-spin" />}Guardar</button>}</div>
          </div>
        </form>
      </Modal>
    </AppLayout>
  );
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\obras\page.tsx" -ForegroundColor Gray
$dst = "src\app\obras\page.tsx"
$content = @'
"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { Obra, EstadoObra } from "@/lib/types/database";
import { Building2, Plus, Archive, ArchiveRestore, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import Link from "next/link";
import { filtrarObrasVisiblesOperario } from "@/lib/utils/obrasVisiblesOperario";

export default function ObrasPage() {
  const { user } = useAuthStore();
  const { isAdmin, canDo, loaded: permisosLoaded } = usePermissions();
  // Solo filtrar por asignaciones si es operario puro (sin permisos crear/editar obras)
  // Guard: mientras cargan los permisos, no filtrar (evita race condition)
  const esSoloOperario = permisosLoaded && !isAdmin && !canDo("obras", "crear") && !canDo("obras", "editar");
  const [archivando, setArchivando] = useState<string | null>(null);
  const [confirmArchive, setConfirmArchive] = useState<string | null>(null);
  const [data, setData] = useState<Obra[]>([]);
  const [estados, setEstados] = useState<EstadoObra[]>([]);
  const [estadoFilter, setEstadoFilter] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const supabase = createClient();

  const fetchData = useCallback(async () => {
    setLoading(true);
    const { data: rows } = await supabase
      .from("obras")
      .select("*, cliente:clientes(*), estado_custom:estados_obra(*)")
      .order("fecha_inicio", { ascending: false });

    let visibleRows = (rows as Obra[]) || [];
    // Solo filtrar si es operario puro Y los permisos ya cargaron
    if (esSoloOperario && user?.recurso_id) {
      const [asigR, partesR] = await Promise.all([
        supabase.from("asignaciones").select("obra_id, fecha_inicio, fecha_fin").eq("recurso_tipo", "humano").eq("recurso_id", user.recurso_id),
        supabase.from("partes_diarios").select("obra_id, fecha, estado").eq("created_by", user.id),
      ]);
      visibleRows = filtrarObrasVisiblesOperario(visibleRows, (asigR.data || []) as any, (partesR.data || []) as any);
    }

    setData(visibleRows);
    const { data: est } = await supabase.from("estados_obra").select("*").eq("activo", true).order("nombre");
    setEstados(est || []);
    setLoading(false);
  }, [user, esSoloOperario]);

  // Esperar a que los permisos carguen antes de hacer el fetch inicial
  useEffect(() => {
    if (permisosLoaded) fetchData();
  }, [fetchData, permisosLoaded]);

  const columns: Column<Obra>[] = [
    {
      key: "nombre", header: "Obra",
      render: (item) => (
        <Link href={`/obras/${item.id}`} className="group">
          <div className="flex items-center gap-3">
            <div className="w-2 h-8 rounded-full" style={{ backgroundColor: item.color || "#DC2626" }} />
            <div>
              <span className="font-medium text-surface-900 group-hover:text-brand-600 transition-colors">{item.nombre}</span>
              <p className="text-xs text-surface-400">{item.ubicacion || "Sin ubicación"}</p>
            </div>
          </div>
        </Link>
      ),
    },
    { key: "cliente_id", header: "Cliente", render: (item) => (item as any).cliente?.nombre || "—" },
    {
      key: "archivada" as any, header: "",
      render: (item) => {
        if (!isAdmin) return null;
        const estaArchivada = !!(item as any).archivada;
        const isConfirming = confirmArchive === item.id;
        const isLoading = archivando === item.id;
        return (
          <div className="flex items-center justify-end gap-1">
            {isConfirming && (
              <span className="text-xs text-amber-600 font-medium mr-1">¿Confirmar?</span>
            )}
            <button
              onClick={(e) => { e.preventDefault(); e.stopPropagation(); handleArchivar(item); }}
              disabled={isLoading}
              title={estaArchivada ? "Restaurar obra" : "Archivar obra"}
              className={cn(
                "p-1.5 rounded-lg transition-colors disabled:opacity-50",
                isConfirming
                  ? "bg-amber-100 text-amber-700 hover:bg-amber-200"
                  : estaArchivada
                  ? "text-surface-400 hover:bg-emerald-50 hover:text-emerald-600"
                  : "text-surface-400 hover:bg-amber-50 hover:text-amber-600"
              )}
            >
              {isLoading
                ? <Loader2 className="w-4 h-4 animate-spin" />
                : estaArchivada
                ? <ArchiveRestore className="w-4 h-4" />
                : <Archive className="w-4 h-4" />
              }
            </button>
          </div>
        );
      },
    },
    {
      key: "estado_obra_id", header: "Estado",
      render: (item) => {
        const est = (item as any).estado_custom;
        return est ? (
          <span className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-medium text-white" style={{ backgroundColor: est.color }}>{est.nombre}</span>
        ) : <span className="text-xs text-surface-400">Sin estado</span>;
      },
    },
  ];

  const handleArchivar = async (obra: Obra) => {
    if (confirmArchive !== obra.id) { setConfirmArchive(obra.id); return; }
    setArchivando(obra.id); setConfirmArchive(null);
    const { error } = await (supabase.from("obras") as any)
      .update({ archivada: !(obra as any).archivada })
      .eq("id", obra.id);
    if (error) alert("Error al archivar: " + error.message);
    else fetchData();
    setArchivando(null);
  };

  const filteredData = estadoFilter ? data.filter((o) => o.estado_obra_id === estadoFilter) : data;

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <Building2 className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">Obras</h1>
              <p className="text-sm text-surface-500">Listado de todas las obras</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <select value={estadoFilter} onChange={(e) => setEstadoFilter(e.target.value)} className="px-3 py-2 text-sm bg-surface-100 border-0 rounded-lg text-surface-600 focus:outline-none focus:ring-2 focus:ring-brand-500/20">
              <option value="">Todos los estados</option>
              {estados.map((e) => <option key={e.id} value={e.id}>{e.nombre}</option>)}
            </select>
            {isAdmin && (
              <Link href="/obras/nueva" className="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 transition-colors">
                <Plus className="w-4 h-4" /> Nueva obra
              </Link>
            )}
          </div>
        </div>
        <div onClick={() => { if (confirmArchive) setConfirmArchive(null); }}>
        <DataTable data={filteredData} columns={columns} title="Todas las obras" loading={loading}
          searchPlaceholder="Buscar por nombre, cliente, dirección, localidad, presupuesto..."
          searchKeys={["nombre", "ubicacion", "estado", (o: any) => o.cliente?.nombre || "", (o: any) => o.direccion || "", (o: any) => o.localidad || "", (o: any) => o.num_presupuesto || ""]}
          canAdd={false} canEdit={false} canDelete={false} />
        </div>
      </div>
    </AppLayout>
  );
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\partes\page.tsx" -ForegroundColor Gray
$dst = "src\app\partes\page.tsx"
$content = @'
"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import type { Obra, RecursoHumano } from "@/lib/types/database";
import { ClipboardList, Plus, Loader2, CheckCircle2, Clock, FileSignature, X, AlertTriangle } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";

const toDS = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

export default function PartesPage() {
  const supabase = createClient();
  const router = useRouter();
  const { user } = useAuthStore();
  const [partes, setPartes] = useState<any[]>([]);
  const [obras, setObras] = useState<Obra[]>([]);
  const [personas, setPersonas] = useState<RecursoHumano[]>([]);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [filterEstado, setFilterEstado] = useState("");
  const [filterObra, setFilterObra] = useState("");
  const [filterFecha, setFilterFecha] = useState("");
  const [filterPersona, setFilterPersona] = useState("");
  // Obra selector modal for multiple assignments
  const [obraSelectModal, setObraSelectModal] = useState(false);
  const [obraOptions, setObraOptions] = useState<{ id: string; nombre: string; color: string; fecha: string }[]>([]);
  const [noObraError, setNoObraError] = useState("");

  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("partes", "crear");
  const puedeEditar   = isAdmin || canDo("partes", "editar");
  const puedeEliminar = isAdmin || canDo("partes", "eliminar");

  // Selector de fecha (paso 1 para operario)
  const [dateModal, setDateModal] = useState(false);
  const [selectedFecha, setSelectedFecha] = useState(toDS(new Date()));

  const abrirOCrearParte = async (obraId: string, fecha: string) => {
    setCreating(true);
    setNoObraError("");

    // ¿Ya existe un parte para esta obra+fecha+usuario? Abrirlo, nunca duplicar.
    const { data: existentes } = await supabase.from("partes_diarios").select("id").eq("obra_id", obraId).eq("fecha", fecha).eq("created_by", user?.id);
    if (existentes && existentes.length > 0) {
      router.push(`/partes/${existentes[0].id}`);
      return;
    }

    let direccion = null, localidad = null, provincia = null;
    const { data: obraData } = await supabase.from("obras").select("direccion, localidad, provincia").eq("id", obraId).single();
    if (obraData) { direccion = obraData.direccion; localidad = obraData.localidad; provincia = obraData.provincia; }

    const { data: parte, error } = await (supabase.from("partes_diarios") as any).insert({
      fecha, created_by: user?.id, estado: "pendiente", obra_id: obraId,
      responsable_empresa: user?.nombre || "", direccion, localidad, provincia,
    }).select().single();

    if (parte) {
      router.push(`/partes/${parte.id}`);
    } else if (error?.code === "23505") {
      // Carrera con otra creación simultánea: el parte ya existe, abrirlo
      const { data: ahora } = await supabase.from("partes_diarios").select("id").eq("obra_id", obraId).eq("fecha", fecha).eq("created_by", user?.id);
      if (ahora && ahora.length > 0) { router.push(`/partes/${ahora[0].id}`); return; }
      alert("Ya existe un parte para esa obra y fecha.");
      setCreating(false);
    } else {
      alert("Error al crear parte: " + (error?.message || ""));
      setCreating(false);
    }
  };

  const handleNuevoParte = () => {
    if (isAdmin) { createDraftAdmin(); return; }
    setSelectedFecha(toDS(new Date()));
    setNoObraError("");
    setDateModal(true);
  };

  const handleFechaConfirmada = async () => {
    setDateModal(false);
    setCreating(true);
    setNoObraError("");
    const recursoId = user?.recurso_id;
    if (!recursoId) {
      setNoObraError("Tu usuario no está vinculado a un recurso humano. Contacta con el administrador.");
      setCreating(false);
      return;
    }

    const { data: asigs, error: asigError } = await supabase.from("asignaciones").select("obra_id, fecha_inicio, fecha_fin").eq("recurso_tipo", "humano").eq("recurso_id", recursoId);
    console.log("[parte] recursoId:", recursoId, "selectedFecha:", selectedFecha, "asigs:", asigs, "error:", asigError);
    if (asigError) {
      setNoObraError(`Error consultando asignaciones: ${asigError.message}`);
      setCreating(false);
      return;
    }
    const delDia = (asigs || []).filter((a: any) => a.fecha_inicio <= selectedFecha && a.fecha_fin >= selectedFecha);
    const obraIds = Array.from(new Set(delDia.map((a: any) => a.obra_id)));

    if (obraIds.length === 0) {
      const fechaLabel = new Date(selectedFecha + "T12:00:00").toLocaleDateString("es-ES", { day: "numeric", month: "long" });
      setNoObraError(`No tienes ninguna obra asignada el ${fechaLabel}. (recurso: ${recursoId}, total asignaciones encontradas: ${(asigs || []).length})`);
      setCreating(false);
      return;
    }

    if (obraIds.length === 1) {
      await abrirOCrearParte(obraIds[0], selectedFecha);
      return;
    }

    const { data: obrasData } = await supabase.from("obras").select("id, nombre, color").in("id", obraIds);
    const options = (obrasData || []).map((o: any) => ({ ...o, fecha: selectedFecha })).sort((a: any, b: any) => a.nombre.localeCompare(b.nombre));
    setObraOptions(options);
    setObraSelectModal(true);
    setCreating(false);
  };

  // Admin: crea un parte en blanco directamente (sin pasar por asignaciones)
  const createDraftAdmin = async () => {
    setCreating(true);
    setNoObraError("");
    const { data: parte, error } = await (supabase.from("partes_diarios") as any).insert({
      fecha: toDS(new Date()), created_by: user?.id, estado: "pendiente", obra_id: null,
      responsable_empresa: user?.nombre || "",
    }).select().single();
    if (parte) router.push(`/partes/${parte.id}`);
    else { alert("Error al crear parte: " + (error?.message || "")); setCreating(false); }
  };

  const handleObraSelected = (obraId: string, fecha: string) => {
    setObraSelectModal(false);
    abrirOCrearParte(obraId, fecha);
  };

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [partesR, obrasR, persR] = await Promise.all([
      supabase.from("partes_diarios")
        .select("*, obra:obras(id, nombre, color), creator:users!partes_diarios_created_by_fkey(nombre, recurso_id)")
        .order("fecha", { ascending: false })
        .limit(200),
      supabase.from("obras").select("id, nombre").eq("archivada", false).order("nombre"),
      supabase.from("recursos_humanos").select("id, nombre").eq("activo", true).order("nombre"),
    ]);
    setPartes(partesR.data || []);
    setObras((obrasR.data as Obra[]) || []);
    setPersonas((persR.data as RecursoHumano[]) || []);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const filtered = partes.filter((p) => {
    if (filterEstado && p.estado !== filterEstado) return false;
    if (filterObra && p.obra_id !== filterObra) return false;
    if (filterFecha && p.fecha !== filterFecha) return false;
    if (filterPersona && p.creator?.recurso_id !== filterPersona) return false;
    return true;
  });

  const hasFilters = filterEstado || filterObra || filterFecha || filterPersona;
  const estadoBadge: Record<string, { label: string; class: string; icon: typeof Clock }> = {
    borrador: { label: "Borrador", class: "bg-surface-100 text-surface-600", icon: Clock },
    pendiente: { label: "Pendiente", class: "bg-amber-100 text-amber-700", icon: Clock },
    firmado: { label: "Firmado", class: "bg-emerald-100 text-emerald-700", icon: CheckCircle2 },
  };

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-orange-50 flex items-center justify-center"><ClipboardList className="w-5 h-5 text-orange-600" /></div>
            <div><h1 className="text-xl font-display font-bold text-surface-900">Partes Diarios</h1><p className="text-sm text-surface-500">{filtered.length} partes</p></div>
          </div>
          <button onClick={handleNuevoParte} disabled={creating} className="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
            {creating ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />} Nuevo parte
          </button>
        </div>

        {/* Error message */}
        {noObraError && (
          <div className="mb-4 p-3 bg-amber-50 border border-amber-200 rounded-lg flex items-start gap-2">
            <AlertTriangle className="w-4 h-4 text-amber-600 mt-0.5 shrink-0" />
            <div>
              <p className="text-sm text-amber-800 font-medium">{noObraError}</p>
              <button onClick={() => setNoObraError("")} className="text-xs text-amber-600 hover:underline mt-1">Cerrar</button>
            </div>
          </div>
        )}

        {/* Filters */}
        <div className="card p-3 mb-4">
          <div className="flex items-center gap-3 flex-wrap">
            <select value={filterEstado} onChange={(e) => setFilterEstado(e.target.value)} className="px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20">
              <option value="">Todos los estados</option><option value="pendiente">Pendiente</option><option value="firmado">Firmado</option><option value="borrador">Borrador</option>
            </select>
            <select value={filterObra} onChange={(e) => setFilterObra(e.target.value)} className="px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20">
              <option value="">Todas las obras</option>{obras.map((o) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
            </select>
            <input type="date" value={filterFecha} onChange={(e) => setFilterFecha(e.target.value)} className="px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20" />
            <select value={filterPersona} onChange={(e) => setFilterPersona(e.target.value)} className="px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20">
              <option value="">Todas las personas</option>{personas.map((p) => <option key={p.id} value={p.id}>{p.nombre}</option>)}
            </select>
            {hasFilters && <button onClick={() => { setFilterEstado(""); setFilterObra(""); setFilterFecha(""); setFilterPersona(""); }} className="flex items-center gap-1 px-2.5 py-1.5 text-xs text-red-600 bg-red-50 rounded-lg hover:bg-red-100"><X className="w-3 h-3" />Limpiar</button>}
          </div>
        </div>

        {/* List */}
        {loading ? (
          <div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div>
        ) : filtered.length === 0 ? (
          <div className="card text-center py-16">
            <ClipboardList className="w-10 h-10 text-surface-300 mx-auto mb-3" />
            <p className="text-sm text-surface-500">{hasFilters ? "Sin resultados" : "No hay partes"}</p>
            <button onClick={handleNuevoParte} className="text-sm text-brand-600 hover:underline mt-1">Crear primer parte</button>
          </div>
        ) : (
          <div className="space-y-2">
            {filtered.map((p) => {
              const est = estadoBadge[p.estado] || estadoBadge.pendiente;
              const EstIcon = est.icon;
              return (
                <Link key={p.id} href={`/partes/${p.id}`} className="card flex items-center gap-4 p-4 hover:shadow-md hover:border-surface-300 transition-all group">
                  <div className="w-1.5 h-14 rounded-full shrink-0" style={{ backgroundColor: p.obra?.color || "#D4D4D4" }} />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3 mb-1 flex-wrap">
                      <span className="text-base font-display font-bold text-surface-900 group-hover:text-brand-600">{p.creator?.nombre || "Usuario"}</span>
                      <span className="text-base font-medium text-surface-700">{p.obra?.nombre || "Sin obra"}</span>
                      <span className="text-sm text-surface-500">{new Date(p.fecha + "T12:00:00").toLocaleDateString("es-ES", { weekday: "short", day: "numeric", month: "short", year: "numeric" })}</span>
                    </div>
                    <div className="flex items-center gap-3">
                      {p.direccion && <span className="text-xs text-surface-400">{p.direccion}{p.localidad ? `, ${p.localidad}` : ""}</span>}
                      {p.observaciones && <span className="text-xs text-surface-500 truncate max-w-[300px]">{p.observaciones}</span>}
                    </div>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    {p.firma_data && <span className="text-[10px] text-emerald-600 flex items-center gap-0.5"><FileSignature className="w-3 h-3" />Resp.</span>}
                    {p.firma_cliente && <span className="text-[10px] text-blue-600 flex items-center gap-0.5"><FileSignature className="w-3 h-3" />Cliente</span>}
                  </div>
                  <span className={cn("badge text-[10px] shrink-0 flex items-center gap-1", est.class)}><EstIcon className="w-3 h-3" />{est.label}</span>
                </Link>
              );
            })}
          </div>
        )}
      </div>

      {/* Selector de fecha (paso 1 para operario) */}
      <Modal open={dateModal} onClose={() => setDateModal(false)} title="¿Qué día es el parte?" size="sm">
        <p className="text-sm text-surface-500 mb-4">Indica la fecha del parte. Te asignaremos la obra correspondiente según tu planificación.</p>
        <input type="date" value={selectedFecha} max={toDS(new Date())}
          onChange={(e) => e.target.value && setSelectedFecha(e.target.value)}
          className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20 mb-4" />
        <button onClick={handleFechaConfirmada} disabled={creating}
          className="w-full flex items-center justify-center gap-1.5 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
          {creating ? <Loader2 className="w-4 h-4 animate-spin" /> : "Continuar"}
        </button>
      </Modal>

      {/* Obra selector modal (cuando hay 2+ obras asignadas ese día) */}
      <Modal open={obraSelectModal} onClose={() => setObraSelectModal(false)} title="Selecciona la obra" size="sm">
        <p className="text-sm text-surface-500 mb-4">
          Ese día tienes varias obras asignadas{obraOptions[0] ? ` (${new Date(obraOptions[0].fecha + "T12:00:00").toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "short" })})` : ""}. ¿En cuál quieres crear el parte?
        </p>
        <div className="space-y-2">
          {obraOptions.map((o, i) => (
            <button key={`${o.id}-${i}`} onClick={() => handleObraSelected(o.id, o.fecha)}
              className="w-full flex items-center gap-3 p-3 bg-surface-50 rounded-lg border border-surface-200 hover:border-brand-400 hover:bg-brand-50 transition-all text-left">
              <div className="w-3 h-8 rounded-full shrink-0" style={{ backgroundColor: o.color || "#DC2626" }} />
              <span className="text-sm font-medium text-surface-900">{o.nombre}</span>
            </button>
          ))}
        </div>
      </Modal>
    </AppLayout>
  );
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\partes\[id]\page.tsx" -ForegroundColor Gray
$dst = "src\app\partes\[id]\page.tsx"
$content = @'
"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { useParams } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import SignatureCanvas from "@/components/partes/SignatureCanvas";
import AudioRecorder from "@/components/partes/AudioRecorder";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { ParteDiario, ParteLinea, Documento, ParteAudio, TipoTrabajo, RecursoHumano } from "@/lib/types/database";
import {
  ClipboardList, ArrowLeft, Loader2, Upload, Trash2, FileText,
  Image as ImageIcon, File, CheckCircle2, Clock, Save, ExternalLink,
  Plus, Mail, Download
} from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils/cn";

interface LineaForm { id?: string; concepto: string; tipo_trabajo_id: string; fabricante: string; producto: string; unidades: string; cantidad: string }
const emptyLinea: LineaForm = { concepto: "", tipo_trabajo_id: "", fabricante: "", producto: "", unidades: "", cantidad: "" };

export default function ParteDetallePage() {
  const { id } = useParams<{ id: string }>();
  const { user } = useAuthStore();
  const supabase = createClient();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [parte, setParte] = useState<ParteDiario | null>(null);
  const [documentos, setDocumentos] = useState<Documento[]>([]);
  const [audios, setAudios] = useState<ParteAudio[]>([]);
  const [tiposTrabajo, setTiposTrabajo] = useState<TipoTrabajo[]>([]);
  const [rrhh, setRrhh] = useState<RecursoHumano[]>([]);
  const [obras, setObras] = useState<any[]>([]);
  const [allUsers, setAllUsers] = useState<any[]>([]);
  const [createdBy, setCreatedBy] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [misAsignaciones, setMisAsignaciones] = useState<{ obra_id: string; fecha_inicio: string; fecha_fin: string }[]>([]);
  const fechaChangedManually = useRef(false);

  // Editable form state
  const [form, setForm] = useState({ fecha: "", obra_id: "", jefe_obra: "", encargado_obra: "", responsable_empresa: "", direccion: "", localidad: "", provincia: "", observaciones: "" });
  const [lineas, setLineas] = useState<LineaForm[]>([]);
  const [firmaResp, setFirmaResp] = useState<string | null>(null);
  const [firmaCliente, setFirmaCliente] = useState<string | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const isAdminUser = isAdmin;
    const [parteR, lineasR, docsR, audiosR, tiposR, rrhhR, obrasR, usersR, misAsigR] = await Promise.all([
      supabase.from("partes_diarios").select("*, obra:obras(*), creator:users!partes_diarios_created_by_fkey(nombre)").eq("id", id).single(),
      supabase.from("parte_lineas").select("*, tipo_trabajo:tipos_trabajo(nombre)").eq("parte_id", id).order("orden"),
      supabase.from("documentos").select("*").eq("parte_id", id).order("created_at", { ascending: false }),
      supabase.from("parte_audios").select("*").eq("parte_id", id).order("created_at", { ascending: false }),
      supabase.from("tipos_trabajo").select("*").eq("activo", true).order("nombre"),
      supabase.from("recursos_humanos").select("*").eq("activo", true).order("nombre"),
      supabase.from("obras").select("*").eq("archivada", false).order("nombre"),
      supabase.from("users").select("id, nombre").order("nombre"),
      !isAdminUser && user?.recurso_id
        ? supabase.from("asignaciones").select("obra_id, fecha_inicio, fecha_fin").eq("recurso_tipo", "humano").eq("recurso_id", user.recurso_id)
        : Promise.resolve({ data: [] as any[] }),
    ]);
    const p = parteR.data as ParteDiario | null;
    setParte(p);
    setCreatedBy(p?.created_by || "");
    setForm({
      fecha: p?.fecha || "", obra_id: p?.obra_id || "",
      jefe_obra: p?.jefe_obra || "", encargado_obra: p?.encargado_obra || "",
      responsable_empresa: p?.responsable_empresa || "",
      direccion: p?.direccion || "", localidad: p?.localidad || "", provincia: p?.provincia || "",
      observaciones: p?.observaciones || "",
    });
    setLineas((lineasR.data || []).map((l: any) => ({
      id: l.id, concepto: l.concepto || "", tipo_trabajo_id: l.tipo_trabajo_id || "",
      fabricante: l.fabricante || "", producto: l.producto || "",
      unidades: l.unidades || "", cantidad: l.cantidad?.toString() || "",
    })));
    setFirmaResp(p?.firma_data || null);
    setFirmaCliente(p?.firma_cliente || null);
    setDocumentos((docsR.data as Documento[]) || []);
    setAudios((audiosR.data as ParteAudio[]) || []);
    setTiposTrabajo(tiposR.data || []);
    setRrhh(rrhhR.data || []);
    setObras(obrasR.data || []);
    setAllUsers(usersR.data || []);
    setMisAsignaciones((misAsigR.data || []) as any);
    setLoading(false);
  }, [id, user]);
  useEffect(() => { fetchData(); }, [fetchData]);

  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("partes", "crear");
  const puedeEditar   = isAdmin || canDo("partes", "editar");
  const puedeEliminar = isAdmin || canDo("partes", "eliminar");
  const isEditable = parte?.estado === "pendiente" || parte?.estado === "borrador";
  const hasObra = !!form.obra_id;

  const handleObraChange = (obraId: string) => {
    const obra = obras.find((o: any) => o.id === obraId);
    setForm((f) => ({ ...f, obra_id: obraId, direccion: obra?.direccion || "", localidad: obra?.localidad || "", provincia: obra?.provincia || "" }));
  };

  // Obras a las que el operario está asignado en la fecha actual del parte
  const obrasDelDia = isAdmin ? obras : obras.filter((o: any) =>
    misAsignaciones.some((a) => a.obra_id === o.id && a.fecha_inicio <= form.fecha && a.fecha_fin >= form.fecha)
  );

  // Si el operario cambia la fecha manualmente, resolver/forzar la obra según su asignación de ese día
  useEffect(() => {
    if (isAdmin || !fechaChangedManually.current) return;
    if (obrasDelDia.length === 1) {
      handleObraChange(obrasDelDia[0].id);
    } else if (!obrasDelDia.some((o: any) => o.id === form.obra_id)) {
      setForm((f) => ({ ...f, obra_id: "", direccion: "", localidad: "", provincia: "" }));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [form.fecha, misAsignaciones]);

  const addLinea = () => setLineas([...lineas, { ...emptyLinea }]);
  const removeLinea = (idx: number) => setLineas(lineas.filter((_, i) => i !== idx));
  const updateLinea = (idx: number, field: keyof LineaForm, value: string) => setLineas(lineas.map((l, i) => i === idx ? { ...l, [field]: value } : l));

  const handleSave = async () => {
    setSaving(true);
    await (supabase.from("partes_diarios") as any).update({
      fecha: form.fecha, obra_id: form.obra_id || null,
      jefe_obra: form.jefe_obra || null, encargado_obra: form.encargado_obra || null,
      responsable_empresa: form.responsable_empresa || null,
      direccion: form.direccion || null, localidad: form.localidad || null, provincia: form.provincia || null,
      observaciones: form.observaciones || null,
      firma_data: firmaResp, firma_cliente: firmaCliente,
      created_by: createdBy || undefined,
    }).eq("id", id);

    // Delete old lines and insert new ones
    await (supabase.from("parte_lineas") as any).delete().eq("parte_id", id);
    const valid = lineas.filter((l) => l.concepto.trim());
    if (valid.length > 0) {
      await (supabase.from("parte_lineas") as any).insert(valid.map((l, i) => ({
        parte_id: id, orden: i, concepto: l.concepto, tipo_trabajo_id: l.tipo_trabajo_id || null,
        fabricante: l.fabricante || null, producto: l.producto || null,
        unidades: l.unidades || null, cantidad: l.cantidad ? parseFloat(l.cantidad) : null,
      })));
    }
    setSaving(false); fetchData();
  };

  const handleFirmar = async () => {
    setSaving(true);
    await (supabase.from("partes_diarios") as any).update({
      firma_data: firmaResp, firma_cliente: firmaCliente, estado: "firmado",
      fecha: form.fecha, obra_id: form.obra_id || null,
      jefe_obra: form.jefe_obra || null, encargado_obra: form.encargado_obra || null,
      responsable_empresa: form.responsable_empresa || null,
      direccion: form.direccion || null, localidad: form.localidad || null, provincia: form.provincia || null,
      observaciones: form.observaciones || null,
    }).eq("id", id);
    await (supabase.from("parte_lineas") as any).delete().eq("parte_id", id);
    const valid = lineas.filter((l) => l.concepto.trim());
    if (valid.length > 0) {
      await (supabase.from("parte_lineas") as any).insert(valid.map((l, i) => ({
        parte_id: id, orden: i, concepto: l.concepto, tipo_trabajo_id: l.tipo_trabajo_id || null,
        fabricante: l.fabricante || null, producto: l.producto || null,
        unidades: l.unidades || null, cantidad: l.cantidad ? parseFloat(l.cantidad) : null,
      })));
    }
    setSaving(false);
    await fetchData();
    // Prompt email
    if (form.obra_id) {
      try {
        const { data: obraEmail } = await supabase.from("obras").select("*").eq("id", form.obra_id).single();
        if (obraEmail?.contacto_obra_email && confirm(`Parte firmado.\n\n¿Enviar por email a ${obraEmail.contacto_obra_email}?`)) {
          const email = obraEmail.contacto_obra_email;
          setSendingEmail(true);
          const res = await fetch("/api/partes/email", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ parteId: id, toEmail: email }) });
          const data = await res.json();
          if (data.success) alert("Email enviado a " + email);
          else alert("Error: " + (data.error || ""));
          setSendingEmail(false);
        }
      } catch { /* ignore */ }
    }
  };

  const handleTranscription = async (label: string, text: string) => {
    const newObs = form.observaciones ? `${form.observaciones}\n\n[${label}]: ${text}` : `[${label}]: ${text}`;
    setForm((f) => ({ ...f, observaciones: newObs }));
    await (supabase.from("partes_diarios") as any).update({ observaciones: newObs }).eq("id", id);
  };

  const [sendingEmail, setSendingEmail] = useState(false);
  const [downloadingPdf, setDownloadingPdf] = useState(false);

  const handleDownloadPdf = async () => {
    setDownloadingPdf(true);
    try {
      const res = await fetch("/api/partes/pdf", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ parteId: id }) });
      const data = await res.json();
      if (data.pdf) {
        const link = document.createElement("a");
        link.href = `data:application/pdf;base64,${data.pdf}`;
        link.download = data.filename;
        link.click();
      } else { alert("Error: " + (data.error || "No PDF")); }
    } catch (err: any) { alert("Error: " + err.message); }
    setDownloadingPdf(false);
  };

  const handleSendEmail = async () => {
    const obraData = parte as any;
    const contactEmail = obraData?.obra?.contacto_obra_email || "";
    const email = prompt("Enviar parte por email a:", contactEmail);
    if (!email) return;

    setSendingEmail(true);
    try {
      const res = await fetch("/api/partes/email", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ parteId: id, toEmail: email }),
      });
      const data = await res.json();
      if (data.success) alert("Email enviado correctamente a " + email);
      else alert("Error: " + (data.error || "Error desconocido"));
    } catch (err: any) { alert("Error: " + err.message); }
    setSendingEmail(false);
  };

  const handleUploadFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    // Save form first if obra changed
    if (form.obra_id && form.obra_id !== parte?.obra_id) {
      await (supabase.from("partes_diarios") as any).update({
        obra_id: form.obra_id || null, fecha: form.fecha,
        jefe_obra: form.jefe_obra || null, encargado_obra: form.encargado_obra || null,
        responsable_empresa: form.responsable_empresa || null,
        direccion: form.direccion || null, localidad: form.localidad || null, provincia: form.provincia || null,
        observaciones: form.observaciones || null,
      }).eq("id", id);
    }
    setUploading(true);
    let errors: string[] = [];
    let success = 0;
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const path = `partes/${id}/${Date.now()}_${file.name}`;
      const { error: uploadErr } = await supabase.storage.from("documentos").upload(path, file);
      if (uploadErr) { errors.push(`${file.name}: ${uploadErr.message}`); continue; }
      const insertData: any = {
        parte_id: id, nombre_archivo: file.name,
        tipo: file.type.startsWith("image/") ? "foto" : file.type === "application/pdf" ? "pdf" : "documento",
        categoria: "general", storage_path: path, tamano: file.size, mime_type: file.type, uploaded_by: user?.id,
      };
      if (form.obra_id) insertData.obra_id = form.obra_id;
      const { error: insertErr } = await (supabase.from("documentos") as any).insert(insertData);
      if (insertErr) errors.push(`${file.name} (DB): ${insertErr.message}`);
      else success++;
    }
    setUploading(false);
    if (fileInputRef.current) fileInputRef.current.value = "";
    if (errors.length > 0) alert("Errores al subir:\n" + errors.join("\n"));
    fetchData();
  };
  const handleOpenDoc = async (doc: Documento) => { const { data } = await supabase.storage.from("documentos").createSignedUrl(doc.storage_path, 300); if (data?.signedUrl) window.open(data.signedUrl, "_blank"); };
  const handleDeleteDoc = async (doc: Documento) => { await supabase.storage.from("documentos").remove([doc.storage_path]); await (supabase.from("documentos") as any).delete().eq("id", doc.id); fetchData(); };
  const formatBytes = (b: number | null) => { if (!b) return ""; if (b < 1024) return b + " B"; if (b < 1048576) return (b / 1024).toFixed(0) + " KB"; return (b / 1048576).toFixed(1) + " MB"; };

  if (loading) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;
  if (!parte) return <AppLayout><div className="text-center py-20"><p className="text-surface-500">Parte no encontrado</p></div></AppLayout>;

  const estBadge: Record<string, { label: string; class: string }> = { borrador: { label: "Borrador", class: "bg-surface-200 text-surface-700" }, pendiente: { label: "Pendiente", class: "bg-amber-100 text-amber-700" }, firmado: { label: "Firmado", class: "bg-emerald-100 text-emerald-700" } };
  const est = estBadge[parte.estado] || estBadge.pendiente;
  const ic = "w-full px-3 py-2 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  const icLocked = ic + " bg-surface-100 text-surface-500 cursor-not-allowed";
  const icDisabled = ic + " bg-surface-100 text-surface-500 cursor-not-allowed";
  const icSm = "w-full px-2.5 py-1.5 bg-white border border-surface-200 rounded-md text-xs placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  return (
    <AppLayout><div className="max-w-4xl mx-auto animate-fade-in">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <Link href="/partes" className="p-2 rounded-lg text-surface-400 hover:bg-surface-100"><ArrowLeft className="w-5 h-5" /></Link>
          <div className="w-10 h-10 rounded-lg bg-orange-50 flex items-center justify-center"><ClipboardList className="w-5 h-5 text-orange-600" /></div>
          <div>
            <h1 className="text-xl font-display font-bold text-surface-900">Parte — {new Date(parte.fecha + "T12:00:00").toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" })}</h1>
            <p className="text-sm text-surface-500">{(parte as any).obra?.nombre || "Sin obra"} · {(parte as any).creator?.nombre}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {parte.estado === "firmado" && (
            <>
              <button onClick={handleDownloadPdf} disabled={downloadingPdf}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200 disabled:opacity-60">
                {downloadingPdf ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Download className="w-3.5 h-3.5" />} PDF
              </button>
              <button onClick={handleSendEmail} disabled={sendingEmail}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-blue-700 bg-blue-50 rounded-lg hover:bg-blue-100 disabled:opacity-60">
                {sendingEmail ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Mail className="w-3.5 h-3.5" />} Enviar
              </button>
            </>
          )}
          <span className={cn("badge text-sm", est.class)}>{est.label}</span>
        </div>
      </div>

      <div className="space-y-6">
        {/* Cabecera */}
        <div className="card p-6">
          <h2 className="text-sm font-semibold text-surface-900 mb-4">Datos del parte</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Fecha</label><input type="date" value={form.fecha} onChange={(e) => { fechaChangedManually.current = true; setForm({ ...form, fecha: e.target.value }); }} disabled={!isEditable} className={isEditable ? ic : icDisabled} /></div>
            <div>
              <label className="block text-xs font-medium text-surface-700 mb-1">Obra</label>
              {!isAdmin && obrasDelDia.length <= 1 ? (
                <select value={form.obra_id} disabled className={icDisabled}>
                  {obrasDelDia.length === 1
                    ? <option value={obrasDelDia[0].id}>{obrasDelDia[0].nombre}</option>
                    : <option value="">Sin obra asignada ese día</option>}
                </select>
              ) : (
                <select value={form.obra_id} onChange={(e) => handleObraChange(e.target.value)} disabled={!isEditable} className={isEditable ? ic : icDisabled}>
                  <option value="">{isAdmin ? "Sin obra" : "Selecciona la obra"}</option>
                  {(isAdmin ? obras : obrasDelDia).map((o: any) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
                </select>
              )}
            </div>
          </div>
          <div className="grid grid-cols-3 gap-4 mt-4">
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Dirección <span className="text-[10px] text-surface-400">(de la obra)</span></label><input type="text" value={form.direccion} readOnly className={icLocked} /></div>
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Localidad</label><input type="text" value={form.localidad} readOnly className={icLocked} /></div>
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Provincia</label><input type="text" value={form.provincia} readOnly className={icLocked} /></div>
          </div>
          <div className="grid grid-cols-3 gap-4 mt-4">
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Jefe de obra</label><select value={form.jefe_obra} onChange={(e) => setForm({ ...form, jefe_obra: e.target.value })} disabled={!isEditable} className={isEditable ? ic : icDisabled}><option value="">Seleccionar...</option>{rrhh.map((r) => <option key={r.id} value={r.nombre}>{r.nombre}</option>)}</select></div>
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Encargado</label><select value={form.encargado_obra} onChange={(e) => setForm({ ...form, encargado_obra: e.target.value })} disabled={!isEditable} className={isEditable ? ic : icDisabled}><option value="">Seleccionar...</option>{rrhh.map((r) => <option key={r.id} value={r.nombre}>{r.nombre}</option>)}</select></div>
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Responsable</label><input type="text" value={form.responsable_empresa} onChange={(e) => setForm({ ...form, responsable_empresa: e.target.value })} disabled={!isEditable} className={isEditable ? ic : icDisabled} /></div>
          </div>
          <div className="mt-4">
            <label className="block text-xs font-medium text-surface-700 mb-1">Creado por</label>
            {isAdmin && isEditable ? (
              <select value={createdBy} onChange={(e) => setCreatedBy(e.target.value)} className={ic}>
                {allUsers.map((u: any) => <option key={u.id} value={u.id}>{u.nombre}</option>)}
              </select>
            ) : (
              <p className="text-sm text-surface-600 py-2">{(parte as any).creator?.nombre || "—"}</p>
            )}
          </div>
        </div>

        {/* Líneas */}
        <div className="card p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-surface-900">Trabajos / Materiales</h2>
            {isEditable && <button type="button" onClick={addLinea} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-brand-600 bg-brand-50 rounded-lg hover:bg-brand-100"><Plus className="w-3.5 h-3.5" />Línea</button>}
          </div>
          {lineas.length === 0 ? <p className="text-sm text-surface-400 text-center py-4">Sin líneas</p> : isEditable ? (
            <div className="space-y-2">
              <div className="grid grid-cols-12 gap-2 px-2">
                <div className="col-span-2 text-[10px] font-semibold text-surface-400 uppercase">Tipo</div>
                <div className="col-span-3 text-[10px] font-semibold text-surface-400 uppercase">Concepto</div>
                <div className="col-span-2 text-[10px] font-semibold text-surface-400 uppercase">Fabricante</div>
                <div className="col-span-2 text-[10px] font-semibold text-surface-400 uppercase">Producto</div>
                <div className="col-span-1 text-[10px] font-semibold text-surface-400 uppercase">Cant.</div>
                <div className="col-span-1 text-[10px] font-semibold text-surface-400 uppercase">Uds.</div>
                <div className="col-span-1"></div>
              </div>
              {lineas.map((l, idx) => (
                <div key={idx} className="grid grid-cols-12 gap-2 items-center bg-surface-50 rounded-lg p-2 border border-surface-100">
                  <div className="col-span-2"><select value={l.tipo_trabajo_id} onChange={(e) => { updateLinea(idx, "tipo_trabajo_id", e.target.value); const t = tiposTrabajo.find((tt) => tt.id === e.target.value); if (t && !l.concepto) updateLinea(idx, "concepto", t.nombre); }} className={icSm}><option value="">Tipo...</option>{tiposTrabajo.map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}</select></div>
                  <div className="col-span-3"><input type="text" value={l.concepto} onChange={(e) => updateLinea(idx, "concepto", e.target.value)} placeholder="Descripción" className={icSm} /></div>
                  <div className="col-span-2"><input type="text" value={l.fabricante} onChange={(e) => updateLinea(idx, "fabricante", e.target.value)} placeholder="Fabricante" className={icSm} /></div>
                  <div className="col-span-2"><input type="text" value={l.producto} onChange={(e) => updateLinea(idx, "producto", e.target.value)} placeholder="Producto" className={icSm} /></div>
                  <div className="col-span-1"><input type="number" value={l.cantidad} onChange={(e) => updateLinea(idx, "cantidad", e.target.value)} step="any" className={icSm} /></div>
                  <div className="col-span-1"><input type="text" value={l.unidades} onChange={(e) => updateLinea(idx, "unidades", e.target.value)} placeholder="uds" className={icSm} /></div>
                  <div className="col-span-1 flex justify-center"><button type="button" onClick={() => removeLinea(idx)} className="p-1 rounded text-surface-400 hover:text-red-500"><Trash2 className="w-3.5 h-3.5" /></button></div>
                </div>
              ))}
            </div>
          ) : (
            <table className="w-full text-sm">
              <thead><tr className="border-b border-surface-200">
                <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Concepto</th>
                <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Tipo</th>
                <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Fabricante</th>
                <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Producto</th>
                <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Cant.</th>
                <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Uds.</th>
              </tr></thead>
              <tbody>{lineas.map((l, i) => {
                const tipo = tiposTrabajo.find((t) => t.id === l.tipo_trabajo_id);
                return (
                  <tr key={i} className="border-b border-surface-50">
                    <td className="py-2 px-2 font-medium text-surface-900">{l.concepto}</td>
                    <td className="py-2 px-2 text-surface-600">{tipo?.nombre || "—"}</td>
                    <td className="py-2 px-2 text-surface-600">{l.fabricante || "—"}</td>
                    <td className="py-2 px-2 text-surface-600">{l.producto || "—"}</td>
                    <td className="py-2 px-2 text-right text-surface-900 font-medium">{l.cantidad || "—"}</td>
                    <td className="py-2 px-2 text-surface-600">{l.unidades || "—"}</td>
                  </tr>
                );
              })}</tbody>
            </table>
          )}
        </div>

        {/* Observaciones */}
        <div className="card p-6">
          <h2 className="text-sm font-semibold text-surface-900 mb-3">Observaciones</h2>
          <textarea value={form.observaciones} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} disabled={!isEditable}
            rows={5} placeholder="Observaciones, transcripciones de audio..." className={(isEditable ? ic : icDisabled) + " resize-y font-mono text-xs"} />
        </div>

        {/* Firmas */}
        <div className="card p-6">
          <h2 className="text-sm font-semibold text-surface-900 mb-4">Firmas</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <SignatureCanvas label="Cliente" value={firmaCliente} onChange={setFirmaCliente} disabled={!isEditable} />
            <SignatureCanvas label={`Responsable — ${form.responsable_empresa || "Empresa"}`} value={firmaResp} onChange={setFirmaResp} disabled={!isEditable} />
          </div>
        </div>

        {/* Documentos */}
        <div className="card p-6">
          <input ref={fileInputRef} type="file" multiple accept="image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt" className="hidden" onChange={handleUploadFile} />
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-surface-900">Documentos</h2>
            <button onClick={() => { console.log("Click subir"); fileInputRef.current?.click(); }} disabled={uploading} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {uploading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Upload className="w-3.5 h-3.5" />}Subir
            </button>
          </div>
          {documentos.length === 0 ? <p className="text-xs text-surface-400 text-center py-4">Sin documentos</p> : (
            <div className="space-y-1.5">{documentos.map((doc) => {
              const isImage = doc.tipo === "foto"; const isPdf = doc.tipo === "pdf";
              return (
                <div key={doc.id} className="flex items-center gap-3 p-2.5 bg-surface-50 rounded-lg border border-surface-100 group">
                  <div className={cn("w-8 h-8 rounded-lg flex items-center justify-center shrink-0", isImage ? "bg-violet-100 text-violet-600" : isPdf ? "bg-red-100 text-red-600" : "bg-blue-100 text-blue-600")}>
                    {isImage ? <ImageIcon className="w-4 h-4" /> : isPdf ? <FileText className="w-4 h-4" /> : <File className="w-4 h-4" />}
                  </div>
                  <div className="flex-1 min-w-0 cursor-pointer" onClick={() => handleOpenDoc(doc)}>
                    <p className="text-xs font-medium text-surface-900 hover:text-brand-600 truncate">{doc.nombre_archivo}</p>
                    <p className="text-[10px] text-surface-400">{formatBytes(doc.tamano)}</p>
                  </div>
                  <div className="flex gap-1 opacity-0 group-hover:opacity-100">
                    <button onClick={() => handleOpenDoc(doc)} className="p-1 rounded text-surface-400 hover:text-brand-600"><ExternalLink className="w-3.5 h-3.5" /></button>
                    <button onClick={() => handleDeleteDoc(doc)} className="p-1 rounded text-surface-400 hover:text-red-600"><Trash2 className="w-3.5 h-3.5" /></button>
                  </div>
                </div>
              );
            })}</div>
          )}
        </div>

        {/* Audios */}
        <div className="card p-6">
          <AudioRecorder parteId={id} audios={audios} onChanged={fetchData} onTranscription={handleTranscription} disabled={false} />
        </div>

        {/* Actions */}
        {isEditable && (
          <div className="flex items-center justify-between pb-6">
            {(!firmaResp || !firmaCliente) && (
              <p className="text-xs text-amber-600 flex items-center gap-1">
                ⚠ Para firmar se necesitan ambas firmas{!firmaResp ? " (falta responsable)" : ""}{!firmaCliente ? " (falta cliente)" : ""}
              </p>
            )}
            {firmaResp && firmaCliente && <div />}
            <div className="flex items-center gap-3 ml-auto">
            <button onClick={handleSave} disabled={saving} className="flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-surface-700 bg-surface-200 rounded-lg hover:bg-surface-300 disabled:opacity-60">
              {saving && <Loader2 className="w-4 h-4 animate-spin" />}<Save className="w-4 h-4" />Guardar
            </button>
            <button onClick={handleFirmar} disabled={saving || !firmaResp || !firmaCliente} title={!firmaResp || !firmaCliente ? "Ambas firmas son obligatorias" : ""} className="flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-white bg-emerald-500 rounded-lg hover:bg-emerald-600 disabled:opacity-60">
              {saving && <Loader2 className="w-4 h-4 animate-spin" />}<CheckCircle2 className="w-4 h-4" />Firmar
            </button>
            </div>
          </div>
        )}
      </div>
    </div></AppLayout>
  );
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "  -> src\app\partes\nuevo\page.tsx" -ForegroundColor Gray
$dst = "src\app\partes\nuevo\page.tsx"
$content = @'
"use client";

import { useState, useEffect, useRef, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import SignatureCanvas from "@/components/partes/SignatureCanvas";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { TipoTrabajo, RecursoHumano } from "@/lib/types/database";
import { ClipboardList, ArrowLeft, Loader2, Plus, Trash2, Save } from "lucide-react";
import Link from "next/link";

interface LineaForm { concepto: string; tipo_trabajo_id: string; fabricante: string; producto: string; unidades: string; cantidad: string }
const emptyLinea: LineaForm = { concepto: "", tipo_trabajo_id: "", fabricante: "", producto: "", unidades: "", cantidad: "" };

function NuevoParteContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const presetObra = searchParams.get("obra");
  const { user } = useAuthStore();
  const { isAdmin } = usePermissions();
  const supabase = createClient();

  const [obras, setObras] = useState<any[]>([]);
  const [tiposTrabajo, setTiposTrabajo] = useState<TipoTrabajo[]>([]);
  const [rrhh, setRrhh] = useState<RecursoHumano[]>([]);
  const [saving, setSaving] = useState(false);

  const [form, setForm] = useState({
    obra_id: presetObra || "", fecha: new Date().toISOString().split("T")[0],
    jefe_obra: "", encargado_obra: "", responsable_empresa: user?.nombre || "",
    direccion: "", localidad: "", provincia: "", observaciones: "",
  });
  const [lineas, setLineas] = useState<LineaForm[]>([{ ...emptyLinea }]);
  const [firmaResponsable, setFirmaResponsable] = useState<string | null>(null);
  const [firmaCliente, setFirmaCliente] = useState<string | null>(null);
  const [allUsers, setAllUsers] = useState<any[]>([]);
  const [createdBy, setCreatedBy] = useState(user?.id || "");

  useEffect(() => {
    Promise.all([
      supabase.from("obras").select("*").eq("archivada", false).order("nombre"),
      supabase.from("tipos_trabajo").select("*").eq("activo", true).order("nombre"),
      supabase.from("recursos_humanos").select("*").eq("activo", true).order("nombre"),
      supabase.from("users").select("id, nombre").order("nombre"),
    ]).then(([o, t, r, u]) => {
      setObras(o.data || []);
      setTiposTrabajo(t.data || []);
      setRrhh(r.data || []);
      setAllUsers(u.data || []);
      // Auto-fill from preset obra
      if (presetObra) {
        const obra = (o.data || []).find((ob: any) => ob.id === presetObra);
        if (obra) setForm((f) => ({ ...f, direccion: obra.direccion || "", localidad: obra.localidad || "", provincia: obra.provincia || "" }));
      }
    });
  }, []);

  // When obra changes, auto-fill address
  const handleObraChange = (obraId: string) => {
    const obra = obras.find((o) => o.id === obraId);
    setForm((f) => ({
      ...f, obra_id: obraId,
      direccion: obra?.direccion || "", localidad: obra?.localidad || "", provincia: obra?.provincia || "",
    }));
  };

  const addLinea = () => setLineas([...lineas, { ...emptyLinea }]);
  const removeLinea = (idx: number) => setLineas(lineas.filter((_, i) => i !== idx));
  const updateLinea = (idx: number, field: keyof LineaForm, value: string) => {
    setLineas(lineas.map((l, i) => i === idx ? { ...l, [field]: value } : l));
  };
  const handleTipoChange = (idx: number, tipoId: string) => {
    const tipo = tiposTrabajo.find((t) => t.id === tipoId);
    updateLinea(idx, "tipo_trabajo_id", tipoId);
    if (tipo && !lineas[idx].concepto) updateLinea(idx, "concepto", tipo.nombre);
  };

  const handleSubmit = async (estado: "pendiente" | "firmado") => {
    if (!form.fecha) return; setSaving(true);
    const finalEstado = (firmaResponsable || firmaCliente) && estado === "firmado" ? "firmado" : "pendiente";
    const { data: parte, error } = await (supabase.from("partes_diarios") as any).insert({
      obra_id: form.obra_id || null, fecha: form.fecha, created_by: createdBy || user?.id,
      jefe_obra: form.jefe_obra || null, encargado_obra: form.encargado_obra || null,
      responsable_empresa: form.responsable_empresa || null, direccion: form.direccion || null,
      localidad: form.localidad || null, provincia: form.provincia || null,
      observaciones: form.observaciones || null, firma_data: firmaResponsable, firma_cliente: firmaCliente, estado: finalEstado,
    }).select().single();
    if (error || !parte) { alert("Error: " + (error?.message || "")); setSaving(false); return; }
    const lineasValidas = lineas.filter((l) => l.concepto.trim());
    if (lineasValidas.length > 0) {
      await (supabase.from("parte_lineas") as any).insert(lineasValidas.map((l, i) => ({
        parte_id: parte.id, orden: i, concepto: l.concepto, tipo_trabajo_id: l.tipo_trabajo_id || null,
        fabricante: l.fabricante || null, producto: l.producto || null, unidades: l.unidades || null,
        cantidad: l.cantidad ? parseFloat(l.cantidad) : null,
      })));
    }
    router.push(`/partes/${parte.id}`);
  };

  const hasObra = !!form.obra_id;
  const ic = "w-full px-3 py-2 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  const icLocked = ic + " bg-surface-100 text-surface-500 cursor-not-allowed";
  const icSm = "w-full px-2.5 py-1.5 bg-white border border-surface-200 rounded-md text-xs placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  return (
    <AppLayout><div className="max-w-4xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/partes" className="p-2 rounded-lg text-surface-400 hover:bg-surface-100"><ArrowLeft className="w-5 h-5" /></Link>
        <div className="w-10 h-10 rounded-lg bg-orange-50 flex items-center justify-center"><ClipboardList className="w-5 h-5 text-orange-600" /></div>
        <div><h1 className="text-xl font-display font-bold text-surface-900">Nuevo Parte</h1></div>
      </div>
      <div className="space-y-6">
        <div className="card p-6">
          <h2 className="text-sm font-semibold text-surface-900 mb-4">Datos del parte</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Fecha *</label><input type="date" value={form.fecha} onChange={(e) => setForm({ ...form, fecha: e.target.value })} required className={ic} /></div>
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Obra</label><select value={form.obra_id} onChange={(e) => handleObraChange(e.target.value)} className={ic}><option value="">Sin obra</option>{obras.map((o) => <option key={o.id} value={o.id}>{o.nombre}</option>)}</select></div>
          </div>
          <div className="grid grid-cols-3 gap-4 mt-4">
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Dirección {hasObra && <span className="text-[10px] text-surface-400">(de la obra)</span>}</label><input type="text" value={form.direccion} readOnly={hasObra} className={hasObra ? icLocked : ic} onChange={hasObra ? undefined : (e) => setForm({ ...form, direccion: e.target.value })} /></div>
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Localidad {hasObra && <span className="text-[10px] text-surface-400">(de la obra)</span>}</label><input type="text" value={form.localidad} readOnly={hasObra} className={hasObra ? icLocked : ic} onChange={hasObra ? undefined : (e) => setForm({ ...form, localidad: e.target.value })} /></div>
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Provincia {hasObra && <span className="text-[10px] text-surface-400">(de la obra)</span>}</label><input type="text" value={form.provincia} readOnly={hasObra} className={hasObra ? icLocked : ic} onChange={hasObra ? undefined : (e) => setForm({ ...form, provincia: e.target.value })} /></div>
          </div>
          <div className="grid grid-cols-3 gap-4 mt-4">
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Jefe de obra</label><select value={form.jefe_obra} onChange={(e) => setForm({ ...form, jefe_obra: e.target.value })} className={ic}><option value="">Seleccionar...</option>{rrhh.map((r) => <option key={r.id} value={r.nombre}>{r.nombre}</option>)}</select></div>
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Encargado</label><select value={form.encargado_obra} onChange={(e) => setForm({ ...form, encargado_obra: e.target.value })} className={ic}><option value="">Seleccionar...</option>{rrhh.map((r) => <option key={r.id} value={r.nombre}>{r.nombre}</option>)}</select></div>
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Responsable</label><input type="text" value={form.responsable_empresa} onChange={(e) => setForm({ ...form, responsable_empresa: e.target.value })} className={ic} /></div>
          </div>
          <div className="mt-4">
            <label className="block text-xs font-medium text-surface-700 mb-1">Creado por</label>
            {isAdmin ? (
              <select value={createdBy} onChange={(e) => setCreatedBy(e.target.value)} className={ic}>
                {allUsers.map((u: any) => <option key={u.id} value={u.id}>{u.nombre}</option>)}
              </select>
            ) : (
              <p className="text-sm text-surface-600 py-2">{user?.nombre || "—"}</p>
            )}
          </div>
        </div>

        <div className="card p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-surface-900">Trabajos / Materiales</h2>
            <button type="button" onClick={addLinea} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-brand-600 bg-brand-50 rounded-lg hover:bg-brand-100"><Plus className="w-3.5 h-3.5" />Línea</button>
          </div>
          <div className="grid grid-cols-12 gap-2 px-2 mb-2">
            <div className="col-span-2 text-[10px] font-semibold text-surface-400 uppercase">Tipo</div>
            <div className="col-span-3 text-[10px] font-semibold text-surface-400 uppercase">Concepto</div>
            <div className="col-span-2 text-[10px] font-semibold text-surface-400 uppercase">Fabricante</div>
            <div className="col-span-2 text-[10px] font-semibold text-surface-400 uppercase">Producto</div>
            <div className="col-span-1 text-[10px] font-semibold text-surface-400 uppercase">Cant.</div>
            <div className="col-span-1 text-[10px] font-semibold text-surface-400 uppercase">Uds.</div>
            <div className="col-span-1"></div>
          </div>
          <div className="space-y-2">
            {lineas.map((linea, idx) => (
              <div key={idx} className="grid grid-cols-12 gap-2 items-center bg-surface-50 rounded-lg p-2 border border-surface-100">
                <div className="col-span-2"><select value={linea.tipo_trabajo_id} onChange={(e) => handleTipoChange(idx, e.target.value)} className={icSm}><option value="">Tipo...</option>{tiposTrabajo.map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}</select></div>
                <div className="col-span-3"><input type="text" value={linea.concepto} onChange={(e) => updateLinea(idx, "concepto", e.target.value)} placeholder="Descripción" className={icSm} /></div>
                <div className="col-span-2"><input type="text" value={linea.fabricante} onChange={(e) => updateLinea(idx, "fabricante", e.target.value)} placeholder="Fabricante" className={icSm} /></div>
                <div className="col-span-2"><input type="text" value={linea.producto} onChange={(e) => updateLinea(idx, "producto", e.target.value)} placeholder="Producto" className={icSm} /></div>
                <div className="col-span-1"><input type="number" value={linea.cantidad} onChange={(e) => updateLinea(idx, "cantidad", e.target.value)} placeholder="0" step="any" className={icSm} /></div>
                <div className="col-span-1"><input type="text" value={linea.unidades} onChange={(e) => updateLinea(idx, "unidades", e.target.value)} placeholder="uds" className={icSm} /></div>
                <div className="col-span-1 flex justify-center">{lineas.length > 1 && <button type="button" onClick={() => removeLinea(idx)} className="p-1 rounded text-surface-400 hover:text-red-500"><Trash2 className="w-3.5 h-3.5" /></button>}</div>
              </div>
            ))}
          </div>
        </div>

        <div className="card p-6">
          <h2 className="text-sm font-semibold text-surface-900 mb-3">Observaciones</h2>
          <textarea value={form.observaciones} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} rows={4} placeholder="Observaciones, incidencias..." className={ic + " resize-y"} />
        </div>

        <div className="card p-6">
          <h2 className="text-sm font-semibold text-surface-900 mb-4">Firmas</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <SignatureCanvas label="Cliente" value={firmaCliente} onChange={setFirmaCliente} />
            <SignatureCanvas label={`Responsable — ${form.responsable_empresa || "Empresa"}`} value={firmaResponsable} onChange={setFirmaResponsable} />
          </div>
        </div>

        <div className="flex items-center justify-between">
          <Link href="/partes" className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</Link>
          <div className="flex items-center gap-3">
            <button onClick={() => handleSubmit("pendiente")} disabled={saving || !form.fecha} className="flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-surface-700 bg-surface-200 rounded-lg hover:bg-surface-300 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}<Save className="w-4 h-4" />Pendiente</button>
            <button onClick={() => handleSubmit("firmado")} disabled={saving || !form.fecha || (!firmaResponsable && !firmaCliente)} className="flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-white bg-emerald-500 rounded-lg hover:bg-emerald-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}Firmar</button>
          </div>
        </div>
      </div>
    </div></AppLayout>
  );
}

export default function NuevoPartePage() {
  return <Suspense><NuevoParteContent /></Suspense>;
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

Write-Host ""
Write-Host "==> Verificando ausencia de hardcodeados" -ForegroundColor Cyan
$found = Get-ChildItem -Path (Join-Path $RepoPath "src\app") -Recurse -Filter "*.tsx" |
    Select-String -Pattern 'user\?\.role\s*===\s*"admin"' -List |
    Where-Object { $_.Path -notmatch "\\api\\" }
if ($found) {
    Write-Host "    ATENCION: quedan hardcodeados en:" -ForegroundColor Yellow
    $found | ForEach-Object { Write-Host "    $($_.Path)" -ForegroundColor Yellow }
} else {
    Write-Host "    OK: ningun isAdmin hardcodeado en src/app" -ForegroundColor Green
}
Write-Host ""
Write-Host '  git add -A'
Write-Host '  git commit -m "fix: eliminar todos los isAdmin hardcodeados - usar usePermissions()"'
Write-Host '  git push'
