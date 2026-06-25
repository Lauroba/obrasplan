"use client";
import { useState, useEffect, useCallback, useRef } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import {
  ArrowDownToLine, ArrowUpFromLine, ArrowLeftRight, SlidersHorizontal,
  Plus, Loader2, Search, Scan, CheckCircle2, X, Package
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";

type TipoMov = "entrada" | "salida" | "ajuste";
const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

const TIPO_CONFIG = {
  entrada:  { label: "Entrada",  icon: ArrowDownToLine,  color: "bg-emerald-100 text-emerald-700" },
  salida:   { label: "Salida",   icon: ArrowUpFromLine,  color: "bg-red-100 text-red-700" },
  ajuste:   { label: "Ajuste",   icon: SlidersHorizontal,color: "bg-amber-100 text-amber-700" },
  traslado_salida:  { label: "Traslado salida",  icon: ArrowLeftRight, color: "bg-blue-100 text-blue-700" },
  traslado_entrada: { label: "Traslado entrada", icon: ArrowLeftRight, color: "bg-blue-100 text-blue-700" },
};

interface ScanItem { articulo: any; cantidad: number; codigoBarras: string; }

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

  // Modal movimiento individual
  const [modalOpen, setModalOpen] = useState(false);
  const [tipo, setTipo] = useState<TipoMov>("entrada");
  const [form, setForm] = useState({ articulo_id: "", almacen_origen_id: "", almacen_destino_id: "", cantidad: "1", obra_id: "", observaciones: "" });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Modal traslado masivo (scan)
  const [trasladoOpen, setTrasladoOpen] = useState(false);
  const [scanInput, setScanInput] = useState("");
  const [scanItems, setScanItems] = useState<ScanItem[]>([]);
  const [trasladoForm, setTrasladoForm] = useState({ almacen_origen_id: "", almacen_destino_id: "", obra_id: "" });
  const [trasladoSaving, setTrasladoSaving] = useState(false);
  const [scanNotFound, setScanNotFound] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [mR, aR, alR, oR] = await Promise.all([
      (supabase.from("movimientos_almacen") as any)
        .select("*, articulo:articulos(nombre,codigo_articulo), almacen_origen:almacenes!almacen_origen_id(nombre), almacen_destino:almacenes!almacen_destino_id(nombre), obra:obras(nombre), user:users(nombre)")
        .order("created_at", { ascending: false }).limit(200),
      (supabase.from("articulos") as any).select("id,nombre,codigo_articulo,codigo_barras").eq("activo", true).order("nombre"),
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

  // Guardar movimiento individual
  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true); setError(null);
    try {
      const payload: any = {
        tipo: tipo === "entrada" ? "entrada" : tipo === "salida" ? "salida" : "ajuste",
        articulo_id: form.articulo_id,
        cantidad: parseFloat(form.cantidad) || 1,
        obra_id: form.obra_id || null,
        observaciones: form.observaciones || null,
        created_by: user?.id,
      };
      if (tipo === "salida" || tipo === "ajuste") payload.almacen_origen_id = form.almacen_origen_id || null;
      if (tipo === "entrada") payload.almacen_destino_id = form.almacen_destino_id || null;

      const { error: err } = await (supabase.from("movimientos_almacen") as any).insert(payload);
      if (err) throw err;
      setModalOpen(false); fetchData();
    } catch (err: any) {
      setError(err.message);
      await logAuditErrorClient({ modulo: "almacen.movimientos", entidad: "movimientos_almacen", accion: "crear", descripcion: "Error al registrar movimiento", errorDetalle: err.message });
    } finally { setSaving(false); }
  };

  // Scan: buscar artículo por código de barras
  const handleScan = (e: React.FormEvent) => {
    e.preventDefault();
    if (!scanInput.trim()) return;
    setScanNotFound(false);
    const found = articulos.find((a) =>
      a.codigo_barras === scanInput.trim() ||
      a.codigo_articulo === scanInput.trim()
    );
    if (!found) { setScanNotFound(true); setScanInput(""); return; }
    setScanItems((prev) => {
      const existing = prev.find((i) => i.articulo.id === found.id);
      if (existing) return prev.map((i) => i.articulo.id === found.id ? { ...i, cantidad: i.cantidad + 1 } : i);
      return [...prev, { articulo: found, cantidad: 1, codigoBarras: scanInput.trim() }];
    });
    setScanInput("");
    setTimeout(() => scanRef.current?.focus(), 50);
  };

  // Confirmar traslado masivo
  const handleTraslado = async () => {
    if (!trasladoForm.almacen_origen_id || !trasladoForm.almacen_destino_id || scanItems.length === 0) return;
    setTrasladoSaving(true);
    try {
      for (const item of scanItems) {
        await (supabase.rpc as any)("registrar_traslado", {
          p_articulo_id: item.articulo.id,
          p_almacen_origen_id: trasladoForm.almacen_origen_id,
          p_almacen_destino_id: trasladoForm.almacen_destino_id,
          p_cantidad: item.cantidad,
          p_obra_id: trasladoForm.obra_id || null,
        });
      }
      setTrasladoOpen(false);
      setScanItems([]);
      setTrasladoForm({ almacen_origen_id: "", almacen_destino_id: "", obra_id: "" });
      fetchData();
    } catch (err: any) {
      setError(err.message);
    } finally { setTrasladoSaving(false); }
  };

  const filtered = movimientos.filter((m) =>
    !search ||
    m.articulo?.nombre?.toLowerCase().includes(search.toLowerCase()) ||
    m.articulo?.codigo_articulo?.toLowerCase().includes(search.toLowerCase()) ||
    m.tipo?.toLowerCase().includes(search.toLowerCase())
  );

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
              <p className="text-sm text-surface-500">Entradas, salidas, ajustes y traslados</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <button onClick={() => { setTrasladoOpen(true); setScanItems([]); setScanInput(""); }}
              className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200">
              <Scan className="w-4 h-4" />Traslado masivo
            </button>
            <button onClick={() => { setModalOpen(true); setTipo("entrada"); setForm({ articulo_id: "", almacen_origen_id: "", almacen_destino_id: "", cantidad: "1", obra_id: "", observaciones: "" }); setError(null); }}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
              <Plus className="w-4 h-4" />Nuevo movimiento
            </button>
          </div>
        </div>

        <div className="card overflow-hidden">
          <div className="p-3 border-b border-surface-100">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
              <input className="w-full pl-9 pr-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg" placeholder="Buscar por artículo, tipo..." value={search} onChange={(e) => setSearch(e.target.value)} />
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
                    const cfg = TIPO_CONFIG[m.tipo as keyof typeof TIPO_CONFIG];
                    const almacen = m.almacen_destino?.nombre || m.almacen_origen?.nombre || "—";
                    return (
                      <tr key={m.id} className="border-b border-surface-50 hover:bg-surface-50/50">
                        <td className="px-4 py-2.5 text-xs text-surface-500 font-mono whitespace-nowrap">
                          {new Date(m.fecha).toLocaleDateString("es-ES")}
                        </td>
                        <td className="px-4 py-2.5">
                          {cfg && <span className={cn("badge text-[10px]", cfg.color)}>{cfg.label}</span>}
                        </td>
                        <td className="px-4 py-2.5">
                          <div className="font-medium text-surface-900 text-xs">{m.articulo?.nombre || "—"}</div>
                          <div className="text-surface-400 text-[10px] font-mono">{m.articulo?.codigo_articulo}</div>
                        </td>
                        <td className="px-4 py-2.5 text-right font-mono text-sm">{m.cantidad}</td>
                        <td className="px-4 py-2.5 text-xs text-surface-600 hidden md:table-cell">{almacen}</td>
                        <td className="px-4 py-2.5 text-xs text-surface-600 hidden lg:table-cell">{m.obra?.nombre || "—"}</td>
                        <td className="px-4 py-2.5 text-xs text-surface-500 hidden lg:table-cell">{m.user?.nombre || "—"}</td>
                      </tr>
                    );
                  })}
                  {filtered.length === 0 && <tr><td colSpan={7} className="text-center py-12 text-sm text-surface-400">Sin movimientos</td></tr>}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {/* Modal: movimiento individual */}
      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title="Nuevo movimiento" size="md">
        <form onSubmit={handleSave} className="space-y-3">
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-1">Tipo de movimiento</label>
            <div className="flex gap-2">
              {(["entrada","salida","ajuste"] as TipoMov[]).map((t) => {
                const cfg = TIPO_CONFIG[t];
                return (
                  <button key={t} type="button"
                    onClick={() => setTipo(t)}
                    className={cn("flex-1 flex items-center justify-center gap-1.5 py-2 text-xs font-semibold rounded-lg border transition-colors",
                      tipo === t ? "border-brand-500 bg-brand-50 text-brand-700" : "border-surface-200 text-surface-600 hover:bg-surface-50")}>
                    <cfg.icon className="w-3.5 h-3.5" />{cfg.label}
                  </button>
                );
              })}
            </div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Artículo *</label>
            <select required className={ic} value={form.articulo_id} onChange={(e) => setForm({ ...form, articulo_id: e.target.value })}>
              <option value="">Seleccionar artículo...</option>
              {articulos.map((a) => <option key={a.id} value={a.id}>{a.nombre} — {a.codigo_articulo}</option>)}
            </select>
          </div>
          {(tipo === "salida" || tipo === "ajuste") && (
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Almacén origen</label>
              <select className={ic} value={form.almacen_origen_id} onChange={(e) => setForm({ ...form, almacen_origen_id: e.target.value })}>
                <option value="">Sin especificar</option>
                {almacenes.map((a) => <option key={a.id} value={a.id}>{a.nombre}</option>)}
              </select>
            </div>
          )}
          {tipo === "entrada" && (
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Almacén destino</label>
              <select className={ic} value={form.almacen_destino_id} onChange={(e) => setForm({ ...form, almacen_destino_id: e.target.value })}>
                <option value="">Sin especificar</option>
                {almacenes.map((a) => <option key={a.id} value={a.id}>{a.nombre}</option>)}
              </select>
            </div>
          )}
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Cantidad *</label>
              <input required type="number" min="0.001" step="0.001" className={ic} value={form.cantidad} onChange={(e) => setForm({ ...form, cantidad: e.target.value })} />
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Obra (opcional)</label>
              <select className={ic} value={form.obra_id} onChange={(e) => setForm({ ...form, obra_id: e.target.value })}>
                <option value="">Sin obra</option>
                {obras.map((o) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
              </select>
            </div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Observaciones</label>
            <input className={ic} value={form.observaciones} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} />
          </div>
          {error && <p className="text-xs text-red-600">{error}</p>}
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving} className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}Registrar</button>
          </div>
        </form>
      </Modal>

      {/* Modal: traslado masivo con scan */}
      <Modal open={trasladoOpen} onClose={() => setTrasladoOpen(false)} title="Traslado masivo" size="lg">
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Almacén origen *</label>
              <select className={ic} value={trasladoForm.almacen_origen_id} onChange={(e) => setTrasladoForm({ ...trasladoForm, almacen_origen_id: e.target.value })}>
                <option value="">Seleccionar...</option>
                {almacenes.map((a) => <option key={a.id} value={a.id}>{a.nombre}</option>)}
              </select>
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Almacén destino *</label>
              <select className={ic} value={trasladoForm.almacen_destino_id} onChange={(e) => setTrasladoForm({ ...trasladoForm, almacen_destino_id: e.target.value })}>
                <option value="">Seleccionar...</option>
                {almacenes.map((a) => <option key={a.id} value={a.id}>{a.nombre}</option>)}
              </select>
            </div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Obra (opcional)</label>
            <select className={ic} value={trasladoForm.obra_id} onChange={(e) => setTrasladoForm({ ...trasladoForm, obra_id: e.target.value })}>
              <option value="">Sin obra</option>
              {obras.map((o) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
            </select>
          </div>

          <div className="border-t border-surface-100 pt-4">
            <p className="text-xs font-semibold text-surface-600 mb-2">Escanear artículos — apunta la pistola y escanea</p>
            <form onSubmit={handleScan} className="flex gap-2">
              <div className="relative flex-1">
                <Scan className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
                <input
                  ref={scanRef}
                  autoFocus
                  className={cn(ic, "pl-9", scanNotFound && "border-red-400 bg-red-50")}
                  placeholder="Código de barras..."
                  value={scanInput}
                  onChange={(e) => { setScanInput(e.target.value); setScanNotFound(false); }}
                />
              </div>
              <button type="submit" className="px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">Añadir</button>
            </form>
            {scanNotFound && <p className="text-xs text-red-600 mt-1">Artículo no encontrado</p>}
          </div>

          {scanItems.length > 0 && (
            <div className="border border-surface-200 rounded-lg overflow-hidden">
              <div className="bg-surface-50 px-3 py-2 text-xs font-semibold text-surface-600">{scanItems.length} artículos en la lista</div>
              <div className="max-h-48 overflow-y-auto">
                {scanItems.map((item, i) => (
                  <div key={i} className="flex items-center gap-3 px-3 py-2 border-b border-surface-50 last:border-0">
                    <Package className="w-4 h-4 text-surface-400 shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="text-xs font-medium text-surface-900 truncate">{item.articulo.nombre}</p>
                      <p className="text-[10px] text-surface-400 font-mono">{item.articulo.codigo_articulo}</p>
                    </div>
                    <div className="flex items-center gap-1">
                      <button onClick={() => setScanItems((prev) => prev.map((s, j) => j === i ? { ...s, cantidad: Math.max(1, s.cantidad - 1) } : s))} className="w-6 h-6 rounded flex items-center justify-center bg-surface-100 hover:bg-surface-200 text-xs font-bold">−</button>
                      <span className="w-8 text-center text-sm font-mono">{item.cantidad}</span>
                      <button onClick={() => setScanItems((prev) => prev.map((s, j) => j === i ? { ...s, cantidad: s.cantidad + 1 } : s))} className="w-6 h-6 rounded flex items-center justify-center bg-surface-100 hover:bg-surface-200 text-xs font-bold">+</button>
                    </div>
                    <button onClick={() => setScanItems((prev) => prev.filter((_, j) => j !== i))} className="p-1 text-surface-300 hover:text-red-500"><X className="w-3.5 h-3.5" /></button>
                  </div>
                ))}
              </div>
            </div>
          )}

          <div className="flex justify-end gap-2">
            <button onClick={() => setTrasladoOpen(false)} className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button
              onClick={handleTraslado}
              disabled={trasladoSaving || scanItems.length === 0 || !trasladoForm.almacen_origen_id || !trasladoForm.almacen_destino_id}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {trasladoSaving ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <CheckCircle2 className="w-3.5 h-3.5" />}
              Confirmar traslado ({scanItems.reduce((s, i) => s + i.cantidad, 0)} uds)
            </button>
          </div>
        </div>
      </Modal>
    </AppLayout>
  );
}