#Requires -Version 5.1
# deploy-movimientos-foto-articulo.ps1
# 1. Movimientos: solo 2 tipos (Movimiento + Ajuste), elimina Entrada/Salida
# 2. Articulos: campo foto_url con subida a Storage, miniatura en listado
# IMPORTANTE: ejecutar 035_articulos_foto.sql en Supabase primero

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Escribiendo archivos" -ForegroundColor Cyan

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
    cantidad: "1", obra_id: "", observaciones: "",
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
    setMovForm({ articulo_id: "", almacen_origen_id: "", almacen_destino_id: "", cantidad: "1", obra_id: "", observaciones: "" });
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
          p_obra_id:            movForm.obra_id || null,
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
                            {m.articulo?.foto_url ? (
                              <img src={m.articulo.foto_url} alt={m.articulo.nombre}
                                className="w-7 h-7 rounded object-cover shrink-0 border border-surface-200" />
                            ) : (
                              <div className="w-7 h-7 rounded bg-surface-100 flex items-center justify-center shrink-0">
                                <Package className="w-3.5 h-3.5 text-surface-400" />
                              </div>
                            )}
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
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Cantidad *</label>
              <input required type="number" min="0.001" step="0.001" className={ic}
                value={movForm.cantidad} onChange={(e) => setMovForm({ ...movForm, cantidad: e.target.value })} />
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Obra (opcional)</label>
              <select className={ic} value={movForm.obra_id}
                onChange={(e) => setMovForm({ ...movForm, obra_id: e.target.value })}>
                <option value="">Sin obra</option>
                {obras.map((o) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
              </select>
            </div>
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
                    {item.articulo.foto_url ? (
                      <img src={item.articulo.foto_url} alt={item.articulo.nombre}
                        className="w-7 h-7 rounded object-cover shrink-0 border border-surface-200" />
                    ) : (
                      <div className="w-7 h-7 rounded bg-surface-100 flex items-center justify-center shrink-0">
                        <Package className="w-3.5 h-3.5 text-surface-400" />
                      </div>
                    )}
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

$dst = "src\app\almacen\articulos\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback, useRef } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import {
  Package, Loader2, Search, Plus, Pencil, Upload, Download,
  AlertTriangle, Calendar, Filter,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";

const empty = {
  referencia_proveedor: "", codigo_articulo: "", codigo_barras: "",
  nombre: "", tipo: "material", tipo_articulo_id: "",
  proveedor_id: "",
  unidad: "ud", stock_minimo: "0", caducidad: "", descripcion: "", foto_url: "",
};
const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

export default function ArticulosPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const isAdmin = user?.role === "admin";
  const fileRef = useRef<HTMLInputElement>(null);
  const fotoRef = useRef<HTMLInputElement>(null);
  const [uploadingFoto, setUploadingFoto] = useState(false);

  const [data, setData] = useState<any[]>([]);
  const [proveedores, setProveedores] = useState<any[]>([]);
  const [tiposArticulo, setTiposArticulo] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [tipoFilter, setTipoFilter] = useState("");
  const [modalOpen, setModalOpen] = useState(false);
  const [form, setForm] = useState(empty);
  const [editId, setEditId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [importResult, setImportResult] = useState<string | null>(null);
  const [importing, setImporting] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [aR, pR, tR] = await Promise.all([
      (supabase.from("articulos") as any).select("*, proveedor:proveedores(nombre), tipo_art:tipos_articulo(id,nombre,activo,orden), foto_url").eq("activo", true).order("nombre"),
      (supabase.from("proveedores") as any).select("id, nombre").eq("activo", true).order("nombre"),
      // Tipos activos + los inactivos que tengan articulos asociados
      (supabase.from("tipos_articulo") as any).select("id, nombre, activo, orden").order("orden").order("nombre"),
    ]);
    setData(aR.data || []);
    setProveedores(pR.data || []);
    // Mostrar tipos activos + tipos inactivos con articulos asociados
    const allTipos: any[] = tR.data || [];
    const tiposConArticulos = new Set((aR.data || []).map((a: any) => a.tipo_articulo_id).filter(Boolean));
    setTiposArticulo(allTipos.filter((t) => t.activo || tiposConArticulos.has(t.id)));
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
      };
      if (editId) {
        const { error: err } = await (supabase.from("articulos") as any).update(payload).eq("id", editId);
        if (err) throw err;
      } else {
        const { error: err } = await (supabase.from("articulos") as any).insert({ ...payload, activo: true });
        if (err) throw err;
      }
      setModalOpen(false); fetchData();
    } catch (err: any) {
      setError(err.message || "Error al guardar");
      await logAuditErrorClient({ modulo: "almacen.articulos", entidad: "articulos", accion: editId ? "editar" : "crear", descripcion: "Error al guardar artículo", errorDetalle: err.message || "" });
    } finally { setSaving(false); }
  };

  const openNew = () => { setForm(empty); setEditId(null); setError(null); setModalOpen(true); };
  const openEdit = (a: any) => {
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
    });
    setEditId(a.id); setError(null); setModalOpen(true);
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
    const a = document.createElement("a"); a.href = url; a.download = "articulos.csv"; a.click();
    URL.revokeObjectURL(url);
  };

  // ---- IMPORTAR CSV ----
  const handleImport = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setImporting(true); setImportResult(null);
    try {
      const text = await file.text();
      const lines = text.split("\n").map((l) => l.trim()).filter(Boolean);
      if (lines.length < 2) throw new Error("CSV vacío o sin datos");
      const headers = lines[0].split(",").map((h) => h.trim().toLowerCase());

      const required = ["referencia_proveedor", "nombre"];
      const missing = required.filter((r) => !headers.includes(r));
      if (missing.length) throw new Error("Faltan columnas: " + missing.join(", "));

      const idx = (name: string) => headers.indexOf(name);
      let ok = 0; let errors = 0;

      for (let i = 1; i < lines.length; i++) {
        // Parseo básico que respeta campos entre comillas
        const cols: string[] = [];
        let cur = ""; let inQ = false;
        for (const ch of lines[i]) {
          if (ch === '"') { inQ = !inQ; }
          else if (ch === "," && !inQ) { cols.push(cur.trim()); cur = ""; }
          else { cur += ch; }
        }
        cols.push(cur.trim());

        const get = (name: string) => idx(name) >= 0 ? cols[idx(name)] || null : null;

        const payload: any = {
          referencia_proveedor: get("referencia_proveedor") || "",
          nombre: get("nombre") || "",
          codigo_articulo: get("codigo_articulo") || undefined,
          codigo_barras: get("codigo_barras") || undefined,
          tipo: get("tipo") || "material",  // campo legacy, se mantiene para compatibilidad
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

      setImportResult(`Importados: ${ok} artículos. Errores: ${errors}.`);
      fetchData();
    } catch (err: any) {
      setImportResult("Error: " + (err.message || "Formato CSV inválido"));
    } finally {
      setImporting(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  };

  // Caducidad proxima (30 días)
  const hoy = new Date();
  const isExpiringSoon = (cad: string | null) => {
    if (!cad) return false;
    const d = new Date(cad);
    const diff = (d.getTime() - hoy.getTime()) / 86400000;
    return diff <= 30;
  };
  const isExpired = (cad: string | null) => {
    if (!cad) return false;
    return new Date(cad) < hoy;
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
              <p className="text-sm text-surface-500">{data.length} artículos</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {isAdmin && (
              <>
                <button onClick={() => fileRef.current?.click()} disabled={importing}
                  className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200 disabled:opacity-60">
                  {importing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Upload className="w-4 h-4" />}
                  Importar CSV
                </button>
                <input ref={fileRef} type="file" accept=".csv" className="hidden" onChange={handleImport} />
              </>
            )}
            <button onClick={exportCSV} className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200">
              <Download className="w-4 h-4" />Exportar CSV
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
              <input className="w-full pl-9 pr-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20" placeholder="Buscar por nombre, código, referencia..." value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
            <select value={tipoFilter} onChange={(e) => setTipoFilter(e.target.value)}
              className="px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none">
              <option value="">Todos los tipos</option>
              {tiposArticulo.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.nombre}{!t.activo ? " (inactivo)" : ""}
                </option>
              ))}
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
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Ref. proveedor</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Cód. artículo</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Nombre</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Tipo</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Proveedor</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Unidad</th>
                    <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Stk. mín.</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Caducidad</th>
                    {isAdmin && <th className="w-10"></th>}
                  </tr>
                </thead>
                <tbody>
                  {filtered.map((a) => (
                    <tr key={a.id} className="border-b border-surface-50 hover:bg-surface-50/50 transition-colors">
                      <td className="px-4 py-2.5 font-mono text-xs text-surface-500">{a.referencia_proveedor}</td>
                      <td className="px-4 py-2.5 font-mono text-xs text-surface-600">{a.codigo_articulo}</td>
                      <td className="px-4 py-2.5">
                        <div className="flex items-center gap-2">
                          {a.foto_url ? (
                            <img src={a.foto_url} alt={a.nombre} className="w-8 h-8 rounded object-cover shrink-0 border border-surface-200" />
                          ) : (
                            <div className="w-8 h-8 rounded bg-surface-100 flex items-center justify-center shrink-0">
                              <Package className="w-4 h-4 text-surface-300" />
                            </div>
                          )}
                          <span className="font-medium text-surface-900">{a.nombre}</span>
                        </div>
                      </td>
                      <td className="px-4 py-2.5">
                        <span className={cn("badge text-[10px]",
                          a.tipo === "material" ? "bg-blue-100 text-blue-700" :
                          a.tipo === "maquinaria" ? "bg-orange-100 text-orange-700" :
                          a.tipo === "vehiculo" ? "bg-purple-100 text-purple-700" :
                          "bg-surface-100 text-surface-600"
                        )}>{a.tipo_art?.nombre || a.tipo}</span>
                      </td>
                      <td className="px-4 py-2.5 text-surface-600 hidden lg:table-cell text-xs">{a.proveedor?.nombre || "—"}</td>
                      <td className="px-4 py-2.5 text-xs text-surface-500">{a.unidad}</td>
                      <td className="px-4 py-2.5 text-right text-xs font-mono">{a.stock_minimo}</td>
                      <td className="px-4 py-2.5 hidden md:table-cell">
                        {a.caducidad ? (
                          <span className={cn("flex items-center gap-1 text-xs",
                            isExpired(a.caducidad) ? "text-red-600" :
                            isExpiringSoon(a.caducidad) ? "text-amber-600" : "text-surface-500"
                          )}>
                            {(isExpired(a.caducidad) || isExpiringSoon(a.caducidad)) && <AlertTriangle className="w-3 h-3" />}
                            <Calendar className="w-3 h-3" />
                            {new Date(a.caducidad).toLocaleDateString("es-ES")}
                          </span>
                        ) : <span className="text-surface-300 text-xs">—</span>}
                      </td>
                      {isAdmin && <td className="px-4 py-2.5"><button onClick={() => openEdit(a)} className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100"><Pencil className="w-3.5 h-3.5" /></button></td>}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Nota de ayuda CSV */}
        <p className="text-[11px] text-surface-400 mt-3">
          CSV de importación: columnas <code className="bg-surface-100 px-1 rounded">referencia_proveedor, nombre</code> obligatorias.
          Opcionales: <code className="bg-surface-100 px-1 rounded">codigo_articulo, codigo_barras, tipo, unidad, stock_minimo, caducidad, descripcion</code>.
          Si <code className="bg-surface-100 px-1 rounded">codigo_articulo</code> ya existe, se actualiza el registro.
        </p>
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editId ? "Editar artículo" : "Nuevo artículo"} size="lg">
        <form onSubmit={handleSave} className="space-y-3">
          {/* Foto del artículo */}
          <div className="flex items-center gap-4">
            {form.foto_url ? (
              <img src={form.foto_url} alt="foto" className="w-16 h-16 rounded-lg object-cover border border-surface-200" />
            ) : (
              <div className="w-16 h-16 rounded-lg bg-surface-100 flex items-center justify-center border border-surface-200">
                <Package className="w-7 h-7 text-surface-300" />
              </div>
            )}
            <div className="flex-1">
              <label className="block text-xs font-medium text-surface-600 mb-1">Foto del artículo</label>
              <button type="button" disabled={uploadingFoto}
                onClick={() => fotoRef.current?.click()}
                className="flex items-center gap-2 px-3 py-2 text-xs font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200 disabled:opacity-60">
                {uploadingFoto ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Upload className="w-3.5 h-3.5" />}
                {form.foto_url ? "Cambiar foto" : "Subir foto"}
              </button>
              {form.foto_url && (
                <button type="button" onClick={() => setForm({ ...form, foto_url: "" })}
                  className="ml-2 text-[10px] text-red-500 hover:text-red-700">Quitar</button>
              )}
              <input ref={fotoRef} type="file" accept="image/*" className="hidden"
                onChange={async (e) => {
                  const file = e.target.files?.[0];
                  if (!file) return;
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
                }}
              />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Referencia proveedor *</label><input required className={ic} value={form.referencia_proveedor} onChange={(e) => setForm({ ...form, referencia_proveedor: e.target.value })} placeholder="REF-001" /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Código artículo</label><input className={ic} value={form.codigo_articulo} onChange={(e) => setForm({ ...form, codigo_articulo: e.target.value })} placeholder="Auto-generado si vacío" /></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Código de barras (EAN)</label><input className={ic} value={form.codigo_barras} onChange={(e) => setForm({ ...form, codigo_barras: e.target.value })} placeholder="= código artículo si vacío" /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Nombre *</label><input required className={ic} value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} /></div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Tipo de artículo</label>
              <select className={ic} value={form.tipo_articulo_id} onChange={(e) => setForm({ ...form, tipo_articulo_id: e.target.value })}>
                <option value="">Sin tipo</option>
                {tiposArticulo.filter((t) => t.activo).map((t) => (
                  <option key={t.id} value={t.id}>{t.nombre}</option>
                ))}
              </select>
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Unidad</label><input className={ic} value={form.unidad} onChange={(e) => setForm({ ...form, unidad: e.target.value })} placeholder="ud, kg, m..." /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Stock mínimo</label><input type="number" min="0" step="0.01" className={ic} value={form.stock_minimo} onChange={(e) => setForm({ ...form, stock_minimo: e.target.value })} /></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Proveedor</label>
              <select className={ic} value={form.proveedor_id} onChange={(e) => setForm({ ...form, proveedor_id: e.target.value })}>
                <option value="">Sin proveedor</option>
                {proveedores.map((p) => <option key={p.id} value={p.id}>{p.nombre}</option>)}
              </select>
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Caducidad</label><input type="date" className={ic} value={form.caducidad} onChange={(e) => setForm({ ...form, caducidad: e.target.value })} /></div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Descripción</label><textarea className={cn(ic, "h-16 resize-none")} value={form.descripcion} onChange={(e) => setForm({ ...form, descripcion: e.target.value })} /></div>
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
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\almacen\articulos\page.tsx" -ForegroundColor Green

Write-Host ""
Write-Host "==> Verificando" -ForegroundColor Cyan
$ok1 = Select-String -Path "src\app\almacen\movimientos\page.tsx" -Pattern "TipoForm.*movimiento.*ajuste" -Quiet
$ok2 = Select-String -Path "src\app\almacen\articulos\page.tsx" -Pattern "foto_url" -Quiet
if ($ok1) { Write-Host "    OK: movimientos con 2 tipos" -ForegroundColor Green }
else { Write-Host "    ERROR: revisar movimientos" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: articulos con foto_url" -ForegroundColor Green }
else { Write-Host "    ERROR: revisar articulos" -ForegroundColor Red }
Write-Host ""
Write-Host "RECORDATORIO: ejecutar 035_articulos_foto.sql en Supabase" -ForegroundColor Yellow
Write-Host ""
Write-Host '  git add src\app\almacen\movimientos\page.tsx src\app\almacen\articulos\page.tsx'
Write-Host '  git commit -m "feat: movimientos simplificados (Movimiento+Ajuste), foto de articulo"'
Write-Host '  git push'
