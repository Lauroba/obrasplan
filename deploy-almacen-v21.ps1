#Requires -Version 5.1
# deploy-almacen-v2.ps1
# Almacen de obra completo:
#   - Nueva pantalla /obras/[id]/almacen con stock + movimientos en tabs
#   - Pestaña Almacen en ficha de obra mejorada (alertas, link a nueva pantalla)
#   - obras/nueva: crea almacen automaticamente al crear obra
#
# IMPORTANTE: ejecutar primero 034_backfill_almacenes_obras.sql en Supabase

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR: repo no encontrado" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Escribiendo archivos" -ForegroundColor Cyan

$dst = "src\app\obras\[id]\almacen\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback } from "react";
import { useParams, useRouter } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import { createClient } from "@/lib/supabase/client";
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
      const { data: stockData } = await (supabase.from("v_stock_actual") as any)
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
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\obras\[id]\almacen\page.tsx" -ForegroundColor Green

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
                {user?.role === "admin" && (
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
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\obras\[id]\obra-detail.tsx" -ForegroundColor Green

$dst = "src\app\obras\nueva\page.tsx"
$content = @'
"use client";
import { useState, useEffect, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import type { Cliente, EstadoObra } from "@/lib/types/database";
import { Building2, Loader2, ArrowLeft, X } from "lucide-react";
import Link from "next/link";

const COLORS = [
  "#DC2626","#EF4444","#F97316","#F59E0B","#EAB308","#84CC16","#22C55E","#16A34A",
  "#10B981","#14B8A6","#06B6D4","#0EA5E9","#3B82F6","#2563EB","#6366F1","#4F46E5",
  "#8B5CF6","#7C3AED","#A855F7","#9333EA","#C026D3","#D946EF","#EC4899","#E11D48",
  "#B45309","#92400E","#78716C","#57534E","#374151","#1F2937","#0F172A","#065F46",
];

function NuevaObraContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const editId = searchParams.get("edit");
  const { user } = useAuthStore();
  const supabase = createClient();
  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [estados, setEstados] = useState<EstadoObra[]>([]);
  const [tiposObra, setTiposObra] = useState<any[]>([]);
  const [rrhhList, setRrhhList] = useState<any[]>([]);
  const [tiposSeleccionados, setTiposSeleccionados] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [loadingEdit, setLoadingEdit] = useState(!!editId);
  const [form, setForm] = useState({
    nombre: "", cliente_id: "", estado_obra_id: "",
    direccion: "", localidad: "", provincia: "",
    num_presupuesto: "", num_factura: "",
    contacto_obra_nombre: "", contacto_obra_telefono: "", contacto_obra_email: "",
    responsable_obra_id: "",

    observaciones: "", color: COLORS[Math.floor(Math.random() * COLORS.length)]
  });

  useEffect(() => {
    Promise.all([
      supabase.from("clientes").select("*").eq("activo", true).order("nombre"),
      supabase.from("estados_obra").select("*").eq("activo", true).order("nombre"),
      supabase.from("tipos_obra").select("*").eq("activo", true).order("nombre").then(r => r).catch(() => ({ data: [] })),
      supabase.from("recursos_humanos").select("id, nombre").eq("activo", true).order("nombre"),
    ]).then(([c, e, t, r]) => {
      setClientes(c.data || []);
      setEstados(e.data || []);
      setTiposObra(t.data || []);
      setRrhhList(r.data || []);
      if (!editId) {
        const pendiente = (e.data || []).find((es: EstadoObra) => es.nombre.toLowerCase().includes("pendiente"));
        if (pendiente) setForm((f) => ({ ...f, estado_obra_id: pendiente.id }));
      }
    });
    if (editId) {
      supabase.from("obras").select("*, cliente:clientes(*)").eq("id", editId).single().then(async ({ data }) => {
        if (data) {
          setForm({
            nombre: data.nombre, cliente_id: data.cliente_id || "", estado_obra_id: data.estado_obra_id || "",
            direccion: data.direccion || "", localidad: data.localidad || "", provincia: data.provincia || "",
            num_presupuesto: data.num_presupuesto || "", num_factura: data.num_factura || "",
            contacto_obra_nombre: data.contacto_obra_nombre || "", contacto_obra_telefono: data.contacto_obra_telefono || "",
            contacto_obra_email: data.contacto_obra_email || "",
            responsable_obra_id: data.responsable_obra_id || "",

            observaciones: data.observaciones || "", color: data.color || COLORS[0],
          });
          const { data: tipos } = await supabase.from("obra_tipos_obra").select("tipo_obra_id").eq("obra_id", editId);
          if (tipos) setTiposSeleccionados(tipos.map((t: any) => t.tipo_obra_id));
        }
        setLoadingEdit(false);
      });
    }
  }, [editId]);

  const handleClienteChange = (clienteId: string) => {
    const cliente = clientes.find((c) => c.id === clienteId);
    setForm((f) => ({
      ...f, cliente_id: clienteId,
      contacto_obra_nombre: f.contacto_obra_nombre || cliente?.contacto || "",
      contacto_obra_telefono: f.contacto_obra_telefono || cliente?.telefono || "",
      contacto_obra_email: f.contacto_obra_email || (cliente as any)?.email || "",
    }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); if (!form.nombre) return; setSaving(true);
    try {
      const payload: any = {
        nombre: form.nombre, cliente_id: form.cliente_id || null,
        ubicacion: form.direccion || null, estado_obra_id: form.estado_obra_id || null,
        observaciones: form.observaciones || null, color: form.color,
        responsable_obra_id: form.responsable_obra_id || null,

      };
      if (form.direccion) payload.direccion = form.direccion;
      if (form.localidad) payload.localidad = form.localidad;
      if (form.provincia) payload.provincia = form.provincia;
      if (form.num_presupuesto) payload.num_presupuesto = form.num_presupuesto;
      if (form.num_factura) payload.num_factura = form.num_factura;
      if (form.contacto_obra_nombre) payload.contacto_obra_nombre = form.contacto_obra_nombre;
      if (form.contacto_obra_telefono) payload.contacto_obra_telefono = form.contacto_obra_telefono;
      if (form.contacto_obra_email) payload.contacto_obra_email = form.contacto_obra_email;

      let obraId = editId;
      if (editId) {
        const { error } = await (supabase.from("obras") as any).update(payload).eq("id", editId);
        if (error) throw error;
      } else {
        const { data: obra, error } = await (supabase.from("obras") as any)
          .insert({ ...payload, created_by: user?.id, estado: "planificada", orden_gantt: 9999 })
          .select().single();
        if (error) throw error;
        obraId = obra.id;
        // Crear almacen automaticamente (silencioso si el trigger ya lo hizo o si falla)
        try {
          await (supabase.rpc as any)("crear_almacen_obra", { p_obra_id: obra.id });
        } catch {
          // El trigger ya lo habrá creado, o se creará manualmente desde la ficha
        }
      }

      if (obraId) {
        await (supabase.from("obra_tipos_obra") as any).delete().eq("obra_id", obraId);
        if (tiposSeleccionados.length > 0) {
          await (supabase.from("obra_tipos_obra") as any).insert(
            tiposSeleccionados.map((tipoId) => ({ obra_id: obraId, tipo_obra_id: tipoId }))
          );
        }
      }
      router.push(`/obras/${obraId}`);
    } catch (err: any) {
      alert("Error al guardar: " + (err?.message || err));
      setSaving(false);
    }
  };

  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  if (loadingEdit) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;

  const selectedCliente = clientes.find((c) => c.id === form.cliente_id);

  return (
    <AppLayout><div className="max-w-3xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6">
        <Link href={editId ? `/obras/${editId}` : "/obras"} className="p-2 rounded-lg text-surface-400 hover:bg-surface-100"><ArrowLeft className="w-5 h-5" /></Link>
        <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center"><Building2 className="w-5 h-5 text-brand-600" /></div>
        <h1 className="text-xl font-display font-bold text-surface-900">{editId ? "Editar Obra" : "Nueva Obra"}</h1>
      </div>
      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="card p-6 space-y-4">
          <h2 className="text-sm font-semibold text-surface-900">Datos generales</h2>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre *</label><input type="text" required value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="Ej: Reforma Local" className={ic} /></div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Cliente</label><select value={form.cliente_id} onChange={(e) => handleClienteChange(e.target.value)} className={ic}><option value="">Sin cliente</option>{clientes.map((c) => <option key={c.id} value={c.id}>{c.nombre}</option>)}</select></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Estado</label><select value={form.estado_obra_id} onChange={(e) => setForm({ ...form, estado_obra_id: e.target.value })} className={ic}><option value="">Sin estado</option>{estados.map((e) => <option key={e.id} value={e.id}>{e.nombre}</option>)}</select></div>
          </div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Responsable de obra</label>
            <select value={form.responsable_obra_id} onChange={(e) => setForm({ ...form, responsable_obra_id: e.target.value })} className={ic}>
              <option value="">Sin responsable</option>
              {rrhhList.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-surface-700 mb-1.5">Tipos de obra</label>
            <div className="flex flex-wrap gap-1.5">
              {tiposObra.map((t) => {
                const selected = tiposSeleccionados.includes(t.id);
                return (
                  <button key={t.id} type="button" onClick={() => setTiposSeleccionados(selected ? tiposSeleccionados.filter((x: string) => x !== t.id) : [...tiposSeleccionados, t.id])}
                    className={`flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-medium transition-all border ${selected ? "bg-brand-500 text-white border-brand-500" : "bg-white text-surface-600 border-surface-200 hover:border-brand-300"}`}>
                    {t.nombre}
                    {selected && <X className="w-3 h-3" />}
                  </button>
                );
              })}
              {tiposObra.length === 0 && <p className="text-xs text-surface-400">Créalos en Maestros → Tipos de Obra</p>}
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nº Presupuesto</label><input type="text" value={form.num_presupuesto} onChange={(e) => setForm({ ...form, num_presupuesto: e.target.value })} placeholder="P-2026-001" className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nº Factura</label><input type="text" value={form.num_factura} onChange={(e) => setForm({ ...form, num_factura: e.target.value })} placeholder="F-2026-001" className={ic} /></div>
          </div>
        </div>

        <div className="card p-6 space-y-4">
          <h2 className="text-sm font-semibold text-surface-900">Dirección de la obra</h2>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Dirección</label><input type="text" value={form.direccion} onChange={(e) => setForm({ ...form, direccion: e.target.value })} placeholder="Calle, número..." className={ic} /></div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Localidad</label><input type="text" value={form.localidad} onChange={(e) => setForm({ ...form, localidad: e.target.value })} placeholder="Ciudad" className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Provincia</label><input type="text" value={form.provincia} onChange={(e) => setForm({ ...form, provincia: e.target.value })} placeholder="Provincia" className={ic} /></div>
          </div>
        </div>

        <div className="card p-6 space-y-4">
          <h2 className="text-sm font-semibold text-surface-900">Contacto</h2>
          {selectedCliente && (
            <div className="p-3 bg-surface-50 rounded-lg border border-surface-100">
              <p className="text-[10px] font-semibold text-surface-400 uppercase mb-1">Datos del cliente (del maestro)</p>
              <p className="text-sm text-surface-700">{selectedCliente.nombre} · {selectedCliente.telefono || "—"} · {(selectedCliente as any).email || "—"}</p>
            </div>
          )}
          <p className="text-xs text-surface-400">El contacto de obra se copia del cliente pero se puede cambiar:</p>
          <div className="grid grid-cols-3 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Contacto obra</label><input type="text" value={form.contacto_obra_nombre} onChange={(e) => setForm({ ...form, contacto_obra_nombre: e.target.value })} placeholder="Nombre" className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Teléfono</label><input type="tel" value={form.contacto_obra_telefono} onChange={(e) => setForm({ ...form, contacto_obra_telefono: e.target.value })} placeholder="Teléfono" className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Email</label><input type="email" value={form.contacto_obra_email} onChange={(e) => setForm({ ...form, contacto_obra_email: e.target.value })} placeholder="email@..." className={ic} /></div>
          </div>
        </div>

        {/* Flags especiales */}
        

        <div className="card p-6 space-y-4">
          <h2 className="text-sm font-semibold text-surface-900">Apariencia</h2>
          <div>
            <label className="block text-sm font-medium text-surface-700 mb-1.5">Color en el Gantt</label>
            <div className="flex items-center gap-1.5 flex-wrap">{COLORS.map((c) => (<button key={c} type="button" onClick={() => setForm({ ...form, color: c })} className="w-7 h-7 rounded-full border-2 transition-all hover:scale-110" style={{ backgroundColor: c, borderColor: form.color === c ? c : "transparent", transform: form.color === c ? "scale(1.25)" : "", boxShadow: form.color === c ? `0 0 0 3px ${c}30` : "none" }} />))}</div>
          </div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Observaciones</label><textarea value={form.observaciones} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} rows={3} placeholder="Notas..." className={ic + " resize-none"} /></div>
        </div>

        <div className="flex items-center justify-end gap-3">
          <Link href={editId ? `/obras/${editId}` : "/obras"} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</Link>
          <button type="submit" disabled={saving || !form.nombre} className="flex items-center gap-2 px-6 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editId ? "Guardar" : "Crear obra"}</button>
        </div>
      </form>
    </div></AppLayout>
  );
}

export default function NuevaObraPage() {
  return <Suspense><NuevaObraContent /></Suspense>;
}
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\obras\nueva\page.tsx" -ForegroundColor Green

Write-Host ""
Write-Host "==> Verificando" -ForegroundColor Cyan
$ok1 = Test-Path -LiteralPath (Join-Path $RepoPath "src\app\obras\[id]\almacen\page.tsx")
$ok2 = Select-String -Path "src\app\obras\[id]\obra-detail.tsx" -Pattern "almacen completo con movimientos" -Quiet
$ok3 = Select-String -Path "src\app\obras\nueva\page.tsx" -Pattern "crear_almacen_obra" -Quiet
if ($ok1) { Write-Host "    OK: pantalla /obras/[id]/almacen creada" -ForegroundColor Green }
else { Write-Host "    ERROR: falta pantalla almacen de obra" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: obra-detail con enlace a pantalla completa" -ForegroundColor Green }
else { Write-Host "    AVISO: revisar obra-detail" -ForegroundColor Yellow }
if ($ok3) { Write-Host "    OK: obras/nueva llama a crear_almacen_obra" -ForegroundColor Green }
else { Write-Host "    AVISO: revisar obras/nueva" -ForegroundColor Yellow }
Write-Host ""
Write-Host "RECORDATORIO:" -ForegroundColor Yellow
Write-Host "  1. Ejecutar 034_backfill_almacenes_obras.sql en Supabase SQL Editor"
Write-Host "  2. Verificar resultado: la query al final del SQL muestra obras_sin_almacen = 0"
Write-Host ""
Write-Host '  git add -A'
Write-Host '  git commit -m "feat: pantalla almacen de obra con stock y movimientos"'
Write-Host '  git push'
