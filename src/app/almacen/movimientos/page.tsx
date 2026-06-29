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