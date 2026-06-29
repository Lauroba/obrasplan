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
  ArrowUpFromLine, ArrowLeftRight, Package, Building2, Pencil,
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
  const [editOpen, setEditOpen] = useState(false);
  const [editForm, setEditForm] = useState({ codigo_almacen: "", nombre: "", ubicacion: "" });
  const [editSaving, setEditSaving] = useState(false);
  const [editError, setEditError] = useState<string | null>(null);

  const openEdit = () => {
    if (!almacen) return;
    setEditForm({
      codigo_almacen: almacen.codigo_almacen || "",
      nombre: almacen.nombre || "",
      ubicacion: almacen.ubicacion || "",
    });
    setEditError(null);
    setEditOpen(true);
  };

  const handleEditSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setEditSaving(true); setEditError(null);
    try {
      const { error: err } = await (supabase.from("almacenes") as any)
        .update({
          nombre: editForm.nombre.trim(),
          ubicacion: editForm.ubicacion.trim() || null,
          codigo_almacen: editForm.codigo_almacen.trim().toUpperCase(),
        })
        .eq("id", id);
      if (err) throw err;
      setEditOpen(false);
      fetchData();
    } catch (err: any) {
      setEditError(err.message || "Error al guardar");
    } finally { setEditSaving(false); }
  };

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
          {isAdmin && (
            <button onClick={openEdit}
              className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200">
              <Pencil className="w-4 h-4" />Editar
            </button>
          )}
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
      {/* Modal edición */}
      <Modal open={editOpen} onClose={() => setEditOpen(false)} title="Editar almacén" size="sm">
        <form onSubmit={handleEditSave} className="space-y-3">
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-1">Código almacén *</label>
            <input required
              className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20"
              value={editForm.codigo_almacen}
              onChange={(e) => setEditForm({ ...editForm, codigo_almacen: e.target.value.toUpperCase() })}
              disabled={almacen?.es_almacen_obra}
              title={almacen?.es_almacen_obra ? "El código de almacenes de obra no se puede cambiar" : ""}
            />
            {almacen?.es_almacen_obra && (
              <p className="text-[10px] text-surface-400 mt-1">El código de almacenes de obra no es editable.</p>
            )}
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-1">Nombre *</label>
            <input required
              className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20"
              value={editForm.nombre}
              onChange={(e) => setEditForm({ ...editForm, nombre: e.target.value })}
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-1">Ubicación</label>
            <input
              className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20"
              value={editForm.ubicacion}
              onChange={(e) => setEditForm({ ...editForm, ubicacion: e.target.value })}
              placeholder="Dirección, nave, sección..."
            />
          </div>
          {editError && <p className="text-xs text-red-600">{editError}</p>}
          <div className="flex justify-end gap-2 pt-1">
            <button type="button" onClick={() => setEditOpen(false)}
              className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={editSaving}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {editSaving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}Guardar
            </button>
          </div>
        </form>
      </Modal>
    </AppLayout>
  );
}