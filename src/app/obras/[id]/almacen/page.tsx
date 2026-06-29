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