#Requires -Version 5.1
# fix-georadar-csv-utf16.ps1
# Fix del crash al cargar el CSV de parametros:
#   - Los CSV exportados por la app Proceq estan en UTF-16 LE con BOM (FF FE)
#   - file.text() en el navegador usa UTF-8 por defecto y corrompe el texto
#   - Fix: detectar BOM y usar TextDecoder con la codificacion correcta
#   - Incluye tambien las mejoras anteriores (heatmap, Anomalia, informe)

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Aplicando fix CSV UTF-16 + mejoras" -ForegroundColor Cyan

Write-Host "  -> src\app\aplicaciones\georadar-v2\page.tsx" -ForegroundColor Gray
$dst = "src\app\aplicaciones\georadar-v2\page.tsx"
$content = @'
"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import dynamic from "next/dynamic";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import {
  Radar, Upload, Zap, Loader2, FileText, Sparkles, AlertTriangle, CheckCircle2,
  Maximize2, Minimize2, ZoomIn, ZoomOut, RotateCcw, Map as MapIcon, Flame,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";

import { parseSegy } from "@/lib/georadar/parseSegy";
import { genDemo } from "@/lib/georadar/genDemo";
import { detectAnomalies, SANDERS, type MaterialKey } from "@/lib/georadar/detectAnomalies";
import { parseGnssText, parseParamsText } from "@/lib/georadar/parseGnss";
import { normalizeRange, drawBackground, drawOverlay, maxDepthOf } from "@/lib/georadar/renderRadargram";
import { useGeoradarStore, type LayoutMode } from "@/lib/georadar/useGeoradarStore";
import type { PromptContext } from "@/lib/georadar/buildPrompt";

const RISK_LABEL: Record<string, { label: string; color: string }> = {
  high: { label: "Alto", color: "bg-red-100 text-red-700" },
  med: { label: "Medio", color: "bg-amber-100 text-amber-700" },
  low: { label: "Bajo", color: "bg-blue-100 text-blue-700" },
};

const LAYOUT_OPTIONS: { value: LayoutMode; label: string }[] = [
  { value: "all", label: "Todo (4 paneles)" },
  { value: "lf", label: "Radar LF" },
  { value: "hf", label: "Radar HF" },
  { value: "mapa", label: "Mapa" },
  { value: "calor", label: "Mapa de calor" },
  { value: "radares", label: "Radar LF + HF" },
  { value: "mapas", label: "Mapa + Calor" },
];

// Mapas Leaflet requieren window/document: se cargan solo en cliente.
const MapsPanel = dynamic(() => import("./MapsPanelV2"), { ssr: false });

export default function GeoradarV2Page() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const store = useGeoradarStore();

  const canvasLF = useRef<HTMLCanvasElement>(null);
  const overlayLF = useRef<HTMLCanvasElement>(null);
  const canvasHF = useRef<HTMLCanvasElement>(null);
  const overlayHF = useRef<HTMLCanvasElement>(null);
  const wrapLF = useRef<HTMLDivElement>(null);
  const wrapHF = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  const [loadingFile, setLoadingFile] = useState<"lf" | "hf" | "gnss" | "params" | null>(null);
  const [reportModalOpen, setReportModalOpen] = useState(false);
  const [reportUrl, setReportUrl] = useState<string | null>(null);
  const [generatingReport, setGeneratingReport] = useState(false);
  const [analysisError, setAnalysisError] = useState<string | null>(null);
  const [pasadaId, setPasadaId] = useState<string | null>(null);

  const runDetection = useCallback(() => {
    const rd = store.rdLF || store.rdHF;
    if (!rd) return;
    const { anoms, layers } = detectAnomalies(rd, {
      vel: store.velocidadEm,
      pw: store.anchuraM > 0 ? store.anchuraM : store.longitudPerfilM,
      pl: store.longitudSeccionM,
      material: store.material,
      gps: store.gps,
    });
    store.setAnoms(anoms, layers);
  }, [store]);

  const handleLoadSgy = async (file: File, ch: "lf" | "hf") => {
    setLoadingFile(ch);
    try {
      const buf = await file.arrayBuffer();
      const rd = parseSegy(buf);
      if (ch === "lf") store.setRdLF(rd);
      else store.setRdHF(rd);
    } finally {
      setLoadingFile(null);
      setTimeout(runDetection, 50);
    }
  };

  const handleLoadGnss = async (file: File) => {
    setLoadingFile("gnss");
    try {
      // Soportar UTF-16 LE/BE (formato Proceq)
      let txt: string;
      try {
        const buf = await file.arrayBuffer();
        const bytes = new Uint8Array(buf);
        if (bytes[0] === 0xFF && bytes[1] === 0xFE) {
          txt = new TextDecoder("utf-16le").decode(buf);
        } else if (bytes[0] === 0xFE && bytes[1] === 0xFF) {
          txt = new TextDecoder("utf-16be").decode(buf);
        } else {
          txt = new TextDecoder("utf-8").decode(buf);
        }
      } catch {
        txt = await file.text();
      }
      const pts = parseGnssText(txt);
      store.setGps(pts);
      if (pts.length > 0) {
        const last = pts[pts.length - 1];
        if (last.dist > 0) store.setLongitudPerfilM(+last.dist.toFixed(1));
      }
    } finally {
      setLoadingFile(null);
    }
  };

  const handleLoadParams = async (file: File) => {
    setLoadingFile("params");
    try {
      // Proceq exporta CSV en UTF-16 LE con BOM — intentar ambas codificaciones
      let txt: string;
      try {
        const buf = await file.arrayBuffer();
        // Detectar BOM UTF-16 LE (FF FE)
        const bytes = new Uint8Array(buf);
        if (bytes[0] === 0xFF && bytes[1] === 0xFE) {
          txt = new TextDecoder("utf-16le").decode(buf);
        } else if (bytes[0] === 0xFE && bytes[1] === 0xFF) {
          txt = new TextDecoder("utf-16be").decode(buf);
        } else {
          txt = new TextDecoder("utf-8").decode(buf);
        }
      } catch {
        txt = await file.text();
      }
      const r = parseParamsText(txt);
      if (r) store.setAnchuraM(r.longitudM);
    } catch (err) {
      console.error("Error al cargar CSV de parámetros:", err);
    } finally {
      setLoadingFile(null);
      setTimeout(runDetection, 50);
    }
  };

  const handleDemo = () => {
    if (!store.rdLF && !store.rdHF) {
      store.setRdLF(genDemo("lf"));
      store.setRdHF(genDemo("hf"));
      setTimeout(runDetection, 50);
    } else {
      runDetection();
    }
  };

  const renderChannel = useCallback(
    (ch: "lf" | "hf") => {
      const rd = ch === "lf" ? store.rdLF : store.rdHF;
      const canvas = ch === "lf" ? canvasLF.current : canvasHF.current;
      const overlay = ch === "lf" ? overlayLF.current : overlayHF.current;
      const wrap = ch === "lf" ? wrapLF.current : wrapHF.current;
      if (!canvas || !overlay || !wrap) return;

      const W = wrap.clientWidth || 2;
      const H = wrap.clientHeight || 2;
      canvas.width = W;
      canvas.height = H;
      overlay.width = W;
      overlay.height = H;

      const ctx = canvas.getContext("2d");
      const octx = overlay.getContext("2d");
      if (!ctx || !octx) return;

      if (!rd) {
        drawBackground(ctx, W, H, null, { mn: 0, mx: 1 }, store.velocidadEm, store.longitudPerfilM);
        octx.clearRect(0, 0, W, H);
        return;
      }

      const range = normalizeRange(rd);
      const level = store.zoomLevel[ch];
      const startFrac = store.zoomStart[ch];
      const cS = Math.floor(startFrac * (rd.COLS * (1 - 1 / level)));
      const cE = Math.min(rd.COLS, cS + Math.ceil(rd.COLS / level));

      drawBackground(ctx, W, H, rd, range, store.velocidadEm, store.anchuraM > 0 ? store.anchuraM : store.longitudPerfilM, cS, cE);
      drawOverlay(octx, W, H, rd, store.velocidadEm, store.layers, store.anoms, store.selectedIndex, cS, cE);
    },
    [store]
  );

  useEffect(() => {
    renderChannel("lf");
    renderChannel("hf");
  }, [renderChannel, store.layoutMode, store.fullscreen]);

  useEffect(() => {
    const onResize = () => {
      renderChannel("lf");
      renderChannel("hf");
    };
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, [renderChannel]);

  // Modo pantalla completa: usa la Fullscreen API del navegador sobre el
  // contenedor del modulo, sin ocultar el sidebar/topbar de ObrasPlan via
  // CSS (evita interferir con el resto de la app) -- al salir de
  // fullscreen (boton, Esc, F11) el estado se sincroniza automaticamente.
  useEffect(() => {
    const handleFsChange = () => {
      const isFs = !!document.fullscreenElement;
      if (isFs !== store.fullscreen) store.setFullscreen(isFs);
    };
    document.addEventListener("fullscreenchange", handleFsChange);
    return () => document.removeEventListener("fullscreenchange", handleFsChange);
  }, [store]);

  const toggleFullscreen = async () => {
    try {
      if (!document.fullscreenElement) {
        await containerRef.current?.requestFullscreen();
      } else {
        await document.exitFullscreen();
      }
    } catch {
      // Algunos navegadores/iframes bloquean Fullscreen API; degradar en
      // silencio a un toggle de estado solo visual.
      store.toggleFullscreen();
    }
  };

  const zoomIn = (ch: "lf" | "hf") => {
    const next = Math.min(30, store.zoomLevel[ch] * 1.35);
    store.setZoom(ch, next, store.zoomStart[ch]);
  };
  const zoomOut = (ch: "lf" | "hf") => {
    const next = Math.max(1, store.zoomLevel[ch] / 1.35);
    store.setZoom(ch, next, store.zoomStart[ch]);
  };
  const zoomReset = (ch: "lf" | "hf") => store.setZoom(ch, 1, 0);

  const savePasada = async (): Promise<string | null> => {
    const voids = store.anoms.filter((a) => a.type === "void");
    const totBruto = voids.reduce((t, a) => t + a.vBruto, 0);
    const totNeto = voids.reduce((t, a) => t + a.vNet, 0);
    const payload = {
      cliente_nombre: store.clienteNombre || null,
      proyecto: store.proyecto || null,
      zona_nombre: store.zonaNombre,
      operador: user?.nombre || null,
      longitud_m: store.anchuraM > 0 ? store.anchuraM : store.longitudPerfilM,
      velocidad_em: store.velocidadEm,
      material: store.material,
      num_anomalias: store.anoms.length,
      num_suministros: store.anoms.filter((a) => a.type === "supply").length,
      volumen_bruto_m3: totBruto,
      volumen_neto_m3: totNeto,
      riesgo_alto: voids.filter((a) => a.risk === "high").length,
      riesgo_medio: voids.filter((a) => a.risk === "med").length,
      riesgo_bajo: voids.filter((a) => a.risk === "low").length,
      anomalias_json: store.anoms,
      analisis_ia_texto: store.analisisTexto,
      analisis_ia_modelo: store.analisisModelo,
      created_by: user?.id || null,
    };
    try {
      if (pasadaId) {
        await (supabase.from("georadar_pasadas") as any).update(payload).eq("id", pasadaId);
        return pasadaId;
      }
      const { data, error } = await (supabase.from("georadar_pasadas") as any).insert(payload).select().single();
      if (error) throw error;
      setPasadaId(data.id);
      return data.id;
    } catch (err: any) {
      try {
        await fetch("/api/audit/log-error", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            modulo: "aplicaciones.georadar",
            entidad: "georadar_pasadas",
            accion: pasadaId ? "editar" : "crear",
            descripcion: "Intento guardar pasada de georradar",
            errorDetalle: err?.message || "Error desconocido",
          }),
        });
      } catch {
        // No debe romper el flujo del usuario.
      }
      return null;
    }
  };

  const runAnalysis = async (proveedor: "claude" | "gpt") => {
    if (store.anoms.length === 0) {
      setAnalysisError("Carga un SGY o pulsa Demo antes de analizar.");
      return;
    }
    setAnalysisError(null);
    store.setAnalizando(true);
    try {
      const id = await savePasada();
      const rd = store.rdLF || store.rdHF;
      const sand = SANDERS[store.material];
      const promptContext: PromptContext = {
        sand,
        maxDepthM: rd ? maxDepthOf(rd, store.velocidadEm) : 0,
        anoms: store.anoms,
        layers: store.layers,
        vel: store.velocidadEm,
        pw: store.anchuraM > 0 ? store.anchuraM : store.longitudPerfilM,
        dispositivoSn: "GS80-101-0091",
        dispositivoFw: "5.7.6",
        operador: user?.nombre || "-",
        fecha: new Date().toISOString().slice(0, 10),
        proyecto: store.proyecto || "-",
        lfDtNs: store.rdLF?.dtNs,
        lfRows: store.rdLF?.ROWS,
        lfCols: store.rdLF?.COLS,
        hfDtNs: store.rdHF?.dtNs,
        hfRows: store.rdHF?.ROWS,
        hfCols: store.rdHF?.COLS,
        gpsCount: store.gps.length,
      };

      const res = await fetch("/api/aplicaciones/georadar/analizar", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ proveedor, promptContext, pasadaId: id }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Error en el analisis");
      store.setAnalisis(data.texto, data.modelo);
    } catch (err: any) {
      setAnalysisError(err?.message || "Error desconocido al analizar");
    } finally {
      store.setAnalizando(false);
    }
  };

  const generateReport = async () => {
    setGeneratingReport(true);
    setReportModalOpen(true);
    setReportUrl(null);
    try {
      const id = await savePasada();
      const sand = SANDERS[store.material];
      const res = await fetch("/api/aplicaciones/georadar/informe", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          pasadaId: id,
          informeData: {
            clienteNombre: store.clienteNombre,
            proyecto: store.proyecto,
            zonaNombre: store.zonaNombre,
            fecha: new Date().toISOString().slice(0, 10),
            operador: user?.nombre || "-",
            dispositivoSn: "GS80-101-0091",
            dispositivoFw: "5.7.6",
            longitudM: store.anchuraM > 0 ? store.anchuraM : store.longitudPerfilM,
            velocidadEm: store.velocidadEm,
            material: sand,
            anoms: store.anoms,
            layers: store.layers,
            analisisTexto: store.analisisTexto || undefined,
            analisisModelo: store.analisisModelo || undefined,
          },
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Error generando el informe");
      setReportUrl(data.url);
    } catch (err: any) {
      setAnalysisError(err?.message || "Error generando el informe");
      setReportModalOpen(false);
    } finally {
      setGeneratingReport(false);
    }
  };

  const voids = store.anoms.filter((a) => a.type === "void");
  const supplies = store.anoms.filter((a) => a.type === "supply");
  const totBruto = voids.reduce((t, a) => t + a.vBruto, 0);
  const totNeto = voids.reduce((t, a) => t + a.vNet, 0);

  // Visibilidad de cada panel logico segun el modo de layout activo
  // (equivalente a LAYOUTS del HTML original).
  const showLF = ["all", "lf", "radares"].includes(store.layoutMode);
  const showHF = ["all", "hf", "radares"].includes(store.layoutMode);
  const showMapa = ["all", "mapa", "mapas"].includes(store.layoutMode);
  const showCalor = ["all", "calor", "mapas"].includes(store.layoutMode);
  const panelCount = [showLF, showHF, showMapa, showCalor].filter(Boolean).length;

  const gridClass =
    panelCount === 1
      ? "grid-cols-1 grid-rows-1"
      : panelCount === 2
      ? "grid-cols-1 sm:grid-cols-2 grid-rows-1"
      : "grid-cols-1 sm:grid-cols-2 grid-rows-2";

  return (
    <AppLayout>
      <style>{`
        #georadar-container:fullscreen,
        #georadar-container:-webkit-full-screen,
        #georadar-container:-moz-full-screen {
          width: 100vw !important;
          height: 100vh !important;
          overflow: hidden;
          background: white;
          display: flex;
          flex-direction: column;
          padding: 12px;
          box-sizing: border-box;
        }
        #georadar-container:fullscreen .georadar-visor,
        #georadar-container:-webkit-full-screen .georadar-visor,
        #georadar-container:-moz-full-screen .georadar-visor {
          flex: 1;
          min-height: 0;
        }
      `}</style>
      <div id="georadar-container" ref={containerRef} className={cn(store.fullscreen ? "bg-white p-3 flex flex-col w-full h-full" : "max-w-[1600px] mx-auto animate-fade-in")}>
        {!store.fullscreen && (
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <Radar className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900 flex items-center gap-2">Georadar V2 <span className="badge bg-brand-100 text-brand-700 text-[10px]">Google Maps</span></h1>
              <p className="text-sm text-surface-500">Análisis de radargramas Proceq GS8000 Pro</p>
            </div>
          </div>
        )}

        <div className={cn("grid gap-4", store.fullscreen ? "grid-cols-1 flex-1 min-h-0" : "grid-cols-1 lg:grid-cols-[260px_1fr_280px]")}>
          {!store.fullscreen && (
            <div className="space-y-4 overflow-y-auto">
              <div className="card p-4">
                <h2 className="text-xs font-semibold text-surface-400 uppercase tracking-wider mb-3">Cliente / Proyecto</h2>
                <div className="space-y-2">
                  <input
                    className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20"
                    placeholder="Cliente"
                    value={store.clienteNombre}
                    onChange={(e) => store.setClienteNombre(e.target.value)}
                  />
                  <input
                    className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20"
                    placeholder="Proyecto"
                    value={store.proyecto}
                    onChange={(e) => store.setProyecto(e.target.value)}
                  />
                  <input
                    className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20"
                    placeholder="Zona"
                    value={store.zonaNombre}
                    onChange={(e) => store.setZonaNombre(e.target.value)}
                  />
                </div>
              </div>

              <div className="card p-4">
                <h2 className="text-xs font-semibold text-surface-400 uppercase tracking-wider mb-3">Cargar archivos</h2>
                <div className="space-y-2">
                  <FileDropZone label="SGY Canal LF (45ns)" loading={loadingFile === "lf"} loaded={!!store.rdLF} accept=".sgy,.segy" onFile={(f) => handleLoadSgy(f, "lf")} />
                  <FileDropZone label="SGY Canal HF (40ns)" loading={loadingFile === "hf"} loaded={!!store.rdHF} accept=".sgy,.segy" onFile={(f) => handleLoadSgy(f, "hf")} />
                  <FileDropZone label="GNSS CSV (RTK)" loading={loadingFile === "gnss"} loaded={store.gps.length > 0} accept=".csv" onFile={handleLoadGnss} />
                  <FileDropZone label="Parámetros CSV" loading={loadingFile === "params"} loaded={store.anchuraM > 0} accept=".csv" onFile={handleLoadParams} />
                </div>
                <button onClick={handleDemo} className="mt-3 w-full flex items-center justify-center gap-2 px-3 py-2 text-sm font-medium text-brand-600 bg-brand-50 rounded-lg hover:bg-brand-100">
                  <Zap className="w-4 h-4" /> Probar con datos demo
                </button>
              </div>

              <div className="card p-4">
                <h2 className="text-xs font-semibold text-surface-400 uppercase tracking-wider mb-3">Parámetros GPR</h2>
                <div className="space-y-2 text-sm">
                  <div className="flex items-center justify-between">
                    <span className="text-surface-600">Vel. EM (m/ns)</span>
                    <input type="number" step="0.005" className="w-20 px-2 py-1 text-right bg-surface-50 border border-surface-200 rounded text-xs"
                      value={store.velocidadEm}
                      onChange={(e) => { store.setVelocidadEm(parseFloat(e.target.value) || 0.09); setTimeout(runDetection, 50); }} />
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-surface-600">Longitud sección (m)</span>
                    <input type="number" step="0.1" className="w-20 px-2 py-1 text-right bg-surface-50 border border-surface-200 rounded text-xs"
                      value={store.longitudSeccionM}
                      onChange={(e) => { store.setLongitudSeccionM(parseFloat(e.target.value) || 1.5); setTimeout(runDetection, 50); }} />
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-surface-600">Material</span>
                    <select className="px-2 py-1 text-xs bg-surface-50 border border-surface-200 rounded"
                      value={store.material}
                      onChange={(e) => { store.setMaterial(e.target.value as MaterialKey); setTimeout(runDetection, 50); }}>
                      <option value="sf">Arena fina</option>
                      <option value="gr">Grava</option>
                      <option value="cl">Arcilla</option>
                      <option value="ro">Roca fract.</option>
                      <option value="mx">Mixto</option>
                    </select>
                  </div>
                </div>
              </div>
            </div>
          )}

          <div className={cn("card overflow-hidden flex flex-col georadar-visor", store.fullscreen ? "min-h-0 flex-1" : "")} style={store.fullscreen ? undefined : { minHeight: 560 }}>
            {/* Topbar de instrumento: contadores + selector de vista + acciones, replica compacta del original */}
            <div className="flex flex-wrap items-center gap-x-3 gap-y-2 px-3 py-2 border-b border-surface-100 bg-surface-50">
              <div className="flex items-center gap-3 text-[11px] font-mono text-surface-500">
                <span>LF <b className="text-surface-800">{store.rdLF ? store.rdLF.dtNs.toFixed(2) + "ns" : "—"}</b></span>
                <span>HF <b className="text-surface-800">{store.rdHF ? store.rdHF.dtNs.toFixed(2) + "ns" : "—"}</b></span>
                <span>PROF <b className="text-surface-800">{(store.rdLF || store.rdHF) ? maxDepthOf((store.rdLF || store.rdHF)!, store.velocidadEm).toFixed(2) + "m" : "—"}</b></span>
                <span className="text-emerald-600">HUECOS <b>{voids.length}</b></span>
              </div>

              <select
                value={store.layoutMode}
                onChange={(e) => store.setLayoutMode(e.target.value as LayoutMode)}
                className="ml-auto px-2.5 py-1.5 text-xs font-medium bg-white border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20"
              >
                {LAYOUT_OPTIONS.map((o) => (
                  <option key={o.value} value={o.value}>{o.label}</option>
                ))}
              </select>

              <button
                onClick={toggleFullscreen}
                title={store.fullscreen ? "Salir de pantalla completa" : "Pantalla completa"}
                className="p-1.5 rounded-lg text-surface-500 hover:bg-surface-200 transition-colors"
              >
                {store.fullscreen ? <Minimize2 className="w-4 h-4" /> : <Maximize2 className="w-4 h-4" />}
              </button>
            </div>

            <div className={cn("grid gap-px bg-surface-200 flex-1 min-h-0", gridClass)}>
              {showLF && (
                <RadarPanel
                  title="Radar LF"
                  tag={store.rdLF ? `LF · ${store.rdLF.dtNs.toFixed(2)}ns · ${store.rdLF.ROWS}s` : "Sin datos"}
                  hasData={!!store.rdLF}
                  wrapRef={wrapLF}
                  canvasRef={canvasLF}
                  overlayRef={overlayLF}
                  zoomLevel={store.zoomLevel.lf}
                  onZoomIn={() => zoomIn("lf")}
                  onZoomOut={() => zoomOut("lf")}
                  onZoomReset={() => zoomReset("lf")}
                  emptyLabel="Carga un SGY LF o pulsa &quot;Probar con datos demo&quot;"
                />
              )}
              {showHF && (
                <RadarPanel
                  title="Radar HF"
                  tag={store.rdHF ? `HF · ${store.rdHF.dtNs.toFixed(2)}ns · ${store.rdHF.ROWS}s` : "Sin datos"}
                  hasData={!!store.rdHF}
                  wrapRef={wrapHF}
                  canvasRef={canvasHF}
                  overlayRef={overlayHF}
                  zoomLevel={store.zoomLevel.hf}
                  onZoomIn={() => zoomIn("hf")}
                  onZoomOut={() => zoomOut("hf")}
                  onZoomReset={() => zoomReset("hf")}
                  emptyLabel="Carga un SGY HF o pulsa &quot;Probar con datos demo&quot;"
                />
              )}
              {(showMapa || showCalor) && (
                <MapsPanel />
              )}
            </div>
          </div>

          {!store.fullscreen && (
            <div className="space-y-4 overflow-y-auto">
              <div className="card p-4">
                <h2 className="text-xs font-semibold text-surface-400 uppercase tracking-wider mb-3">Resultados</h2>
                <div className="space-y-1.5 text-sm">
                  <Row label="Anomalías detectadas" value={String(voids.length)} />
                  <Row label="Suministros" value={String(supplies.length)} />
                  <Row label="Vol. bruto" value={totBruto.toFixed(4) + " m³"} />
                  <Row label="Vol. neto" value={totNeto.toFixed(4) + " m³"} bold />
                  <div className="border-t border-surface-100 my-2" />
                  <Row label="Riesgo alto" value={String(voids.filter((a) => a.risk === "high").length)} color="text-red-600" />
                  <Row label="Riesgo medio" value={String(voids.filter((a) => a.risk === "med").length)} color="text-amber-600" />
                  <Row label="Riesgo bajo" value={String(voids.filter((a) => a.risk === "low").length)} color="text-blue-600" />
                </div>
              </div>

              <div className="card p-4 max-h-64 overflow-y-auto">
                <h2 className="text-xs font-semibold text-surface-400 uppercase tracking-wider mb-3">Anomalías ({store.anoms.length})</h2>
                {store.anoms.length === 0 ? (
                  <p className="text-xs text-surface-400 text-center py-4">Sin anomalías detectadas todavía</p>
                ) : (
                  <div className="space-y-1">
                    {store.anoms.map((a, i) => (
                      <button key={i} onClick={() => store.setSelectedIndex(i)}
                        className={cn("w-full text-left px-2.5 py-1.5 rounded-lg text-xs border-l-2 transition-colors",
                          a.type === "void" ? "border-red-400" : "border-amber-400",
                          store.selectedIndex === i ? "bg-brand-50" : "hover:bg-surface-50")}>
                        <div className="flex items-center justify-between">
                          <span className="font-semibold">{(a.type === "void" ? "A" : a.type === "supply" ? "S" : "T") + (i + 1)}</span>
                          {a.risk && <span className={cn("badge text-[9px]", RISK_LABEL[a.risk].color)}>{RISK_LABEL[a.risk].label}</span>}
                        </div>
                        <span className="text-surface-500 font-mono">{a.dM}m · {a.wM}×{a.hM}m</span>
                      </button>
                    ))}
                  </div>
                )}
              </div>

              <div className="card p-4">
                <h2 className="text-xs font-semibold text-surface-400 uppercase tracking-wider mb-3">Análisis IA</h2>
                {analysisError && <p className="text-xs text-red-600 mb-2">{analysisError}</p>}
                <div className="flex gap-2">
                  <button onClick={() => runAnalysis("claude")} disabled={store.analizando}
                    className="flex-1 flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
                    {store.analizando ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Sparkles className="w-3.5 h-3.5" />}
                    Claude
                  </button>
                  <button onClick={() => runAnalysis("gpt")} disabled={store.analizando}
                    className="flex-1 flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-semibold text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200 disabled:opacity-60">
                    {store.analizando ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Sparkles className="w-3.5 h-3.5" />}
                    GPT-4o
                  </button>
                </div>
                {store.analisisTexto && (
                  <div className="mt-3 max-h-48 overflow-y-auto bg-surface-50 rounded-lg p-3">
                    <p className="text-[10px] text-surface-400 mb-1">Generado con {store.analisisModelo}</p>
                    <p className="text-xs text-surface-700 whitespace-pre-wrap">{store.analisisTexto}</p>
                  </div>
                )}
                <button onClick={generateReport} disabled={store.anoms.length === 0}
                  className="mt-3 w-full flex items-center justify-center gap-2 px-3 py-2 text-xs font-semibold text-surface-700 border border-surface-200 rounded-lg hover:bg-surface-50 disabled:opacity-50">
                  <FileText className="w-4 h-4" /> Generar informe Word
                </button>
              </div>
            </div>
          )}
        </div>
      </div>

      <Modal open={reportModalOpen} onClose={() => setReportModalOpen(false)} title="Informe Word" size="sm">
        {generatingReport ? (
          <div className="flex flex-col items-center gap-3 py-8">
            <Loader2 className="w-8 h-8 text-brand-500 animate-spin" />
            <p className="text-sm text-surface-500">Generando informe…</p>
          </div>
        ) : reportUrl ? (
          <div className="flex flex-col items-center gap-3 py-6">
            <CheckCircle2 className="w-8 h-8 text-emerald-500" />
            <p className="text-sm text-surface-700">Informe generado correctamente</p>
            <a href={reportUrl} target="_blank" rel="noopener noreferrer" className="px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
              Descargar informe
            </a>
          </div>
        ) : (
          <div className="flex flex-col items-center gap-3 py-8">
            <AlertTriangle className="w-8 h-8 text-amber-500" />
            <p className="text-sm text-surface-500">No se pudo generar el informe</p>
          </div>
        )}
      </Modal>
    </AppLayout>
  );
}

function Row({ label, value, bold, color }: { label: string; value: string; bold?: boolean; color?: string }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-surface-500">{label}</span>
      <span className={cn("font-mono", bold ? "font-bold text-surface-900" : "text-surface-700", color)}>{value}</span>
    </div>
  );
}

function FileDropZone({ label, loading, loaded, accept, onFile }: { label: string; loading: boolean; loaded: boolean; accept: string; onFile: (f: File) => void }) {
  const inputRef = useRef<HTMLInputElement>(null);
  return (
    <button type="button" onClick={() => inputRef.current?.click()}
      className={cn("w-full flex items-center gap-2 px-3 py-2.5 text-xs rounded-lg border border-dashed transition-colors text-left",
        loaded ? "border-brand-300 bg-brand-50 text-brand-700" : "border-surface-200 hover:border-surface-300 text-surface-500")}>
      {loading ? <Loader2 className="w-4 h-4 animate-spin shrink-0" /> : <Upload className="w-4 h-4 shrink-0" />}
      <span className="truncate">{loaded ? "✓ " + label : label}</span>
      <input ref={inputRef} type="file" accept={accept} className="hidden"
        onChange={(e) => { const f = e.target.files?.[0]; if (f) onFile(f); e.target.value = ""; }} />
    </button>
  );
}

function RadarPanel({
  title, tag, hasData, wrapRef, canvasRef, overlayRef, zoomLevel, onZoomIn, onZoomOut, onZoomReset, emptyLabel,
}: {
  title: string;
  tag: string;
  hasData: boolean;
  wrapRef: React.RefObject<HTMLDivElement>;
  canvasRef: React.RefObject<HTMLCanvasElement>;
  overlayRef: React.RefObject<HTMLCanvasElement>;
  zoomLevel: number;
  onZoomIn: () => void;
  onZoomOut: () => void;
  onZoomReset: () => void;
  emptyLabel: string;
}) {
  return (
    <div className="bg-white flex flex-col min-h-0">
      <div className="flex items-center gap-2 px-2 py-1 border-b border-surface-100 text-[10px]">
        <span className="font-semibold text-surface-700">{title}</span>
        <span className="text-surface-400 font-mono">{tag}</span>
        <div className="ml-auto flex items-center gap-0.5">
          <button onClick={onZoomOut} className="p-1 rounded hover:bg-surface-100 text-surface-500"><ZoomOut className="w-3 h-3" /></button>
          <span className="font-mono text-surface-500 w-8 text-center">{zoomLevel.toFixed(1)}×</span>
          <button onClick={onZoomIn} className="p-1 rounded hover:bg-surface-100 text-surface-500"><ZoomIn className="w-3 h-3" /></button>
          <button onClick={onZoomReset} className="p-1 rounded hover:bg-surface-100 text-surface-500"><RotateCcw className="w-3 h-3" /></button>
        </div>
      </div>
      <div ref={wrapRef} className="relative flex-1 min-h-[200px] bg-surface-900">
        {!hasData && (
          <div className="absolute inset-0 flex items-center justify-center text-surface-400 text-[11px] px-6 text-center" dangerouslySetInnerHTML={{ __html: emptyLabel }} />
        )}
        <canvas ref={canvasRef} className="absolute inset-0 w-full h-full" />
        <canvas ref={overlayRef} className="absolute inset-0 w-full h-full pointer-events-none" />
      </div>
    </div>
  );
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

Write-Host "  -> src\app\aplicaciones\georadar-v2\MapsPanelV2.tsx" -ForegroundColor Gray
$dst = "src\app\aplicaciones\georadar-v2\MapsPanelV2.tsx"
$content = @'
"use client";
/**
 * MapsPanelV2.tsx — Google Maps con heatmap canvas para Georadar V2.
 *
 * Mejoras respecto a la versión anterior:
 *  - "Hueco" renombrado a "Anomalía" en toda la UI
 *  - Mapa de calor implementado con Canvas 2D sobre el mapa de Google
 *    (equivalente al heatmap de la V1 con Leaflet, sin dependencias extra)
 *  - Toggle mapa/heatmap
 *  - Fix: store.gps (no store.gpsPoints)
 *  - Fix: race condition al guardar API Key con callback= en la URL del script
 */

import { useEffect, useRef, useState, useCallback } from "react";
import { useGeoradarStore } from "@/lib/georadar/useGeoradarStore";
import { Eye, EyeOff, AlertTriangle, Flame, Map } from "lucide-react";
import { cn } from "@/lib/utils/cn";

// ─────────────────────────────────────────────────────────────
// Tipos y config visual — "void" se muestra como "Anomalía"
// ─────────────────────────────────────────────────────────────
type AnomalyTypeV2 = "anomaly" | "supply" | "pipe";

const TIPO_V2: Record<AnomalyTypeV2, { label: string; color: string; letra: string }> = {
  anomaly: { label: "Anomalía",   color: "#DC2626", letra: "A" },
  supply:  { label: "Suministro", color: "#2563EB", letra: "S" },
  pipe:    { label: "Tubería",    color: "#D97706", letra: "T" },
};

const RISK_COLOR: Record<string, string> = {
  high: "#DC2626", med: "#D97706", low: "#2563EB",
};
const RISK_LABEL: Record<string, string> = {
  high: "ALTO", med: "MEDIO", low: "BAJO",
};

const LS_KEY    = "georadar_v2_gmaps_key";
const GMAPS_CB  = "__gmapsV2Ready__";

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────
function classifyType(a: any): AnomalyTypeV2 {
  // void y anomaly → "Anomalía". supply estrecho → tubería
  if (a.type === "pipe")    return "pipe";
  if (a.type === "supply")  return (a.wM ?? 0.5) < 0.15 ? "pipe" : "supply";
  return "anomaly"; // void, anomaly y cualquier otro
}

function markerSVG(tipo: AnomalyTypeV2, label: string, risk: string): string {
  const cfg = TIPO_V2[tipo];
  const dot = risk === "high"
    ? `<circle cx="17" cy="17" r="15" fill="none" stroke="white" stroke-width="1.5" stroke-dasharray="3,2" opacity=".6"/>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" width="34" height="34" viewBox="0 0 34 34">
    <circle cx="17" cy="17" r="15" fill="${cfg.color}" stroke="white" stroke-width="2.5"/>
    ${dot}
    <text x="17" y="21" text-anchor="middle" fill="white" font-size="10"
      font-weight="700" font-family="monospace,sans-serif">${label}</text>
  </svg>`;
}

function popupHTML(a: any, tipo: AnomalyTypeV2, idx: number): string {
  const cfg = TIPO_V2[tipo];
  const rc  = RISK_COLOR[a.risk] || "#6B7280";
  return `<div style="font-family:system-ui,sans-serif;min-width:200px;padding:2px">
    <b style="color:${cfg.color};font-size:13px">${cfg.label} ${idx + 1}</b>
    <hr style="margin:6px 0;border-color:${cfg.color}30"/>
    <table style="width:100%;font-size:11.5px;border-collapse:collapse">
      <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Distancia</td>
          <td><b>${a.distM ?? "—"} m</b></td></tr>
      <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Profundidad</td>
          <td><b>${a.dM ?? "—"} m</b></td></tr>
      <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Dimensiones</td>
          <td><b>${a.wM ?? "—"}×${a.hM ?? "—"} m</b></td></tr>
      ${(a.type === "void" || a.type === "anomaly")
        ? `<tr><td style="color:#6B7280;padding:2px 8px 2px 0">Vol. neto</td>
           <td><b>${typeof a.vNet === "number" ? a.vNet.toFixed(4) : "—"} m³</b></td></tr>` : ""}
      <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Riesgo</td>
          <td><b style="color:${rc}">${RISK_LABEL[a.risk] || a.risk}</b></td></tr>
      <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Confianza</td>
          <td><b>${Math.round((a.conf ?? 0.7) * 100)}%</b></td></tr>
      ${a.gpt ? `<tr><td style="color:#6B7280;padding:2px 8px 2px 0">GPS</td>
          <td style="font-size:10px"><b>${a.gpt.lat.toFixed(6)}, ${a.gpt.lon.toFixed(6)}</b></td></tr>` : ""}
    </table>
  </div>`;
}

// ─────────────────────────────────────────────────────────────
// Mapa de calor Canvas sobre Google Maps
// ─────────────────────────────────────────────────────────────
function drawHeatmap(
  canvas: HTMLCanvasElement,
  map: any,
  anoms: any[],
  radiusPx = 40
) {
  const W = canvas.width;
  const H = canvas.height;
  const ctx = canvas.getContext("2d");
  if (!ctx) return;
  ctx.clearRect(0, 0, W, H);
  if (!anoms.length) return;

  // Solo anomalías con GPS
  const pts = anoms
    .filter(a => a.gpt && (a.type === "void" || a.type === "anomaly"))
    .map(a => {
      try {
        const G    = (window as any).google.maps;
        const proj = map.getProjection();
        const bounds = map.getBounds();
        if (!proj || !bounds) return null;
        const ne   = bounds.getNorthEast();
        const sw   = bounds.getSouthWest();
        const neP  = proj.fromLatLngToPoint(ne);
        const swP  = proj.fromLatLngToPoint(sw);
        const scale = Math.pow(2, map.getZoom());
        const worldPt = proj.fromLatLngToPoint(new G.LatLng(a.gpt.lat, a.gpt.lon));
        const x = (worldPt.x - swP.x) * scale;
        const y = (worldPt.y - neP.y) * scale;
        return { x, y, w: (a.vBruto || 0.01) };
      } catch { return null; }
    })
    .filter((p): p is { x: number; y: number; w: number } =>
      !!p && isFinite(p.x) && isFinite(p.y));

  if (!pts.length) return;

  const maxW = Math.max(...pts.map(p => p.w), 1e-12);
  const field = new Float32Array(W * H);

  pts.forEach(pt => {
    const weight = (pt.w / maxW) + 0.15;
    const x0 = Math.max(0, Math.round(pt.x - radiusPx));
    const x1 = Math.min(W - 1, Math.round(pt.x + radiusPx));
    const y0 = Math.max(0, Math.round(pt.y - radiusPx));
    const y1 = Math.min(H - 1, Math.round(pt.y + radiusPx));
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const d = Math.sqrt((x - pt.x) ** 2 + (y - pt.y) ** 2);
        if (d < radiusPx) {
          field[y * W + x] += weight * (1 - d / radiusPx) ** 2;
        }
      }
    }
  });

  const maxF = Math.max(...Array.from(field));
  if (maxF === 0) return;

  const img = ctx.createImageData(W, H);
  for (let i = 0; i < field.length; i++) {
    const t = field[i] / maxF;
    if (t < 0.01) continue;
    const [r, g, b] = t < 0.33
      ? [0, Math.round(t * 3 * 255), 255]               // azul→cyan
      : t < 0.66
      ? [Math.round((t - 0.33) * 3 * 255), 255, Math.round((0.66 - t) * 3 * 255)] // cyan→verde→amarillo
      : [255, Math.round((1 - t) * 255), 0];             // amarillo→rojo
    const a = Math.round(t * 0.8 * 255);
    const idx = i * 4;
    img.data[idx] = r; img.data[idx+1] = g; img.data[idx+2] = b; img.data[idx+3] = a;
  }
  ctx.putImageData(img, 0, 0);
}

// ─────────────────────────────────────────────────────────────
// Componente principal
// ─────────────────────────────────────────────────────────────
export default function MapsPanelV2() {
  const store = useGeoradarStore();

  const mapDivRef  = useRef<HTMLDivElement>(null);
  const heatCanvas = useRef<HTMLCanvasElement>(null);
  const mapInst    = useRef<any>(null);
  const markers    = useRef<any[]>([]);
  const polyRef    = useRef<any>(null);
  const infoRef    = useRef<any>(null);
  const heatListener = useRef<any>(null);

  const [apiKey,    setApiKey]    = useState("");
  const [draft,     setDraft]     = useState("");
  const [showKey,   setShowKey]   = useState(false);
  const [mapsReady, setMapsReady] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [viewMode,  setViewMode]  = useState<"map" | "heat" | "both">("map");
  const [filters,   setFilters]   = useState<Record<AnomalyTypeV2, boolean>>(
    { anomaly: true, supply: true, pipe: true }
  );

  // Cargar key
  useEffect(() => {
    const k = process.env.NEXT_PUBLIC_GMAPS_KEY || localStorage.getItem(LS_KEY) || "";
    setApiKey(k); setDraft(k);
  }, []);

  // Cargar script Google Maps
  useEffect(() => {
    if (!apiKey) return;
    if ((window as any).google?.maps) { setMapsReady(true); return; }

    (window as any)[GMAPS_CB] = () => {
      setMapsReady(true);
      delete (window as any)[GMAPS_CB];
    };

    if (document.getElementById("gmaps-v2")) {
      const t = setInterval(() => {
        if ((window as any).google?.maps) { setMapsReady(true); clearInterval(t); }
      }, 150);
      return () => clearInterval(t);
    }

    const s = document.createElement("script");
    s.id    = "gmaps-v2";
    s.src   = `https://maps.googleapis.com/maps/api/js?key=${apiKey}&callback=${GMAPS_CB}`;
    s.async = true; s.defer = true;
    s.onerror = () => {
      setLoadError("No se pudo cargar Google Maps. Verifica la API Key y activa Maps JavaScript API.");
      delete (window as any)[GMAPS_CB];
    };
    document.head.appendChild(s);
  }, [apiKey]);

  // Inicializar mapa
  useEffect(() => {
    if (!mapsReady || !mapDivRef.current || mapInst.current) return;
    const G = (window as any).google.maps;
    const gps = store.gps as { lat: number; lon: number; dist?: number }[];
    const center = gps.length > 0
      ? { lat: gps[0].lat, lng: gps[0].lon }
      : { lat: 42.82, lng: -1.64 };

    mapInst.current = new G.Map(mapDivRef.current, {
      center, zoom: 18, mapTypeId: "satellite",
      mapTypeControl: true, fullscreenControl: false, streetViewControl: false,
    });

    // Registrar overlay del heatmap canvas
    class HeatOverlay extends G.OverlayView {
      onAdd() {}
      draw() {
        if (!heatCanvas.current || !this.getProjection()) return;
        const cvs = heatCanvas.current;
        cvs.width  = mapDivRef.current?.clientWidth  || 600;
        cvs.height = mapDivRef.current?.clientHeight || 400;
        drawHeatmap(cvs, mapInst.current, store.anoms);
      }
      onRemove() {}
    }
    const overlay = new HeatOverlay();
    overlay.setMap(mapInst.current);

    // Re-dibujar heatmap en cada movimiento del mapa
    heatListener.current = mapInst.current.addListener("idle", () => {
      if (heatCanvas.current) {
        heatCanvas.current.width  = mapDivRef.current?.clientWidth  || 600;
        heatCanvas.current.height = mapDivRef.current?.clientHeight || 400;
        drawHeatmap(heatCanvas.current, mapInst.current, store.anoms);
      }
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mapsReady]);

  // Redibujar marcadores y heatmap cuando cambian datos o filtros
  useEffect(() => {
    if (!mapsReady || !mapInst.current) return;
    const G = (window as any).google.maps;

    // Limpiar marcadores
    markers.current.forEach(m => m.setMap(null));
    markers.current = [];
    if (infoRef.current) { infoRef.current.close(); infoRef.current = null; }
    if (polyRef.current) { polyRef.current.setMap(null); polyRef.current = null; }

    // Traza GPS
    const gps = store.gps as { lat: number; lon: number; dist?: number }[];
    if (gps.length > 1) {
      polyRef.current = new G.Polyline({
        path: gps.map(p => ({ lat: p.lat, lng: p.lon })),
        strokeColor: "#F59E0B", strokeOpacity: 0.9, strokeWeight: 3, geodesic: true,
      });
      polyRef.current.setMap(mapInst.current);
      const b = new G.LatLngBounds();
      gps.forEach(p => b.extend({ lat: p.lat, lng: p.lon }));
      mapInst.current.fitBounds(b);
    }

    // Marcadores de anomalías
    (store.anoms as any[]).forEach((a, i) => {
      if (!a.gpt) return;
      const tipo = classifyType(a);
      if (!filters[tipo]) return;

      const cfg   = TIPO_V2[tipo];
      const label = `${cfg.letra}${i + 1}`;
      const icon  = {
        url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(markerSVG(tipo, label, a.risk))}`,
        scaledSize: new G.Size(34, 34),
        anchor:     new G.Point(17, 17),
      };
      const mk = new G.Marker({
        position: { lat: a.gpt.lat, lng: a.gpt.lon },
        map: mapInst.current, icon,
        title: `${cfg.label} ${i + 1}`,
        zIndex: a.risk === "high" ? 100 : a.risk === "med" ? 50 : 10,
        visible: viewMode !== "heat",
      });
      const iw = new G.InfoWindow({ content: popupHTML(a, tipo, i) });
      mk.addListener("click", () => {
        if (infoRef.current) infoRef.current.close();
        iw.open(mapInst.current, mk);
        infoRef.current = iw;
      });
      markers.current.push(mk);
    });

    // Redibujar heatmap
    if (heatCanvas.current) {
      heatCanvas.current.width  = mapDivRef.current?.clientWidth  || 600;
      heatCanvas.current.height = mapDivRef.current?.clientHeight || 400;
      drawHeatmap(heatCanvas.current, mapInst.current, store.anoms);
    }
  }, [mapsReady, store.anoms, store.gps, filters, viewMode]);

  // Mostrar/ocultar heatmap canvas y marcadores según modo
  useEffect(() => {
    if (heatCanvas.current) {
      heatCanvas.current.style.display = viewMode === "map" ? "none" : "block";
      heatCanvas.current.style.opacity = viewMode === "both" ? "0.75" : "1";
    }
    markers.current.forEach(m => {
      m.setVisible?.(viewMode !== "heat");
    });
  }, [viewMode]);

  const saveKey = () => {
    const k = draft.trim(); if (!k) return;
    localStorage.setItem(LS_KEY, k);
    setApiKey(k); setLoadError(""); setMapsReady(false);
    mapInst.current = null;
    const old = document.getElementById("gmaps-v2");
    if (old) old.remove();
    if ((window as any).google) delete (window as any).google;
  };
  const clearKey = () => {
    localStorage.removeItem(LS_KEY);
    setApiKey(""); setDraft(""); setLoadError(""); setMapsReady(false);
    mapInst.current = null;
    const old = document.getElementById("gmaps-v2");
    if (old) old.remove();
  };

  // ── Sin key ────────────────────────────────────────────────
  if (!apiKey) return (
    <div className="flex flex-col items-center justify-center h-full bg-surface-50 rounded-xl border border-surface-200 gap-4 p-8">
      <div className="w-12 h-12 rounded-xl bg-brand-50 flex items-center justify-center">
        <Map className="w-6 h-6 text-brand-500" />
      </div>
      <div className="text-center">
        <p className="text-sm font-semibold text-surface-800 mb-1">Google Maps API Key requerida</p>
        <p className="text-xs text-surface-500 max-w-xs">
          Consíguela en{" "}
          <a href="https://console.cloud.google.com/apis/credentials" target="_blank"
            rel="noopener noreferrer" className="text-brand-600 hover:underline">
            Google Cloud Console
          </a>{" "}
          activando <em>Maps JavaScript API</em>.
        </p>
      </div>
      <div className="flex gap-2 w-full max-w-sm">
        <div className="relative flex-1">
          <input type={showKey ? "text" : "password"} value={draft}
            onChange={e => setDraft(e.target.value)}
            onKeyDown={e => e.key === "Enter" && saveKey()}
            placeholder="AIzaSy..."
            className="w-full px-3 py-2 text-sm border border-surface-200 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-brand-500/20 pr-9" />
          <button onClick={() => setShowKey(s => !s)}
            className="absolute right-2.5 top-1/2 -translate-y-1/2 text-surface-400">
            {showKey ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
          </button>
        </div>
        <button onClick={saveKey} disabled={!draft.trim()}
          className="px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-50">
          Activar
        </button>
      </div>
      <p className="text-[10px] text-surface-400 text-center">La clave se guarda solo en este navegador.</p>
    </div>
  );

  if (loadError) return (
    <div className="flex flex-col items-center justify-center h-full bg-red-50 rounded-xl border border-red-200 gap-3 p-6">
      <AlertTriangle className="w-8 h-8 text-red-400" />
      <p className="text-sm font-semibold text-red-700">Error al cargar Google Maps</p>
      <p className="text-xs text-red-600 text-center max-w-sm">{loadError}</p>
      <button onClick={clearKey} className="px-4 py-2 text-xs font-semibold text-red-600 border border-red-300 rounded-lg hover:bg-red-100">
        Cambiar API Key
      </button>
    </div>
  );

  if (!mapsReady) return (
    <div className="flex items-center justify-center h-full bg-surface-50 rounded-xl border border-surface-200">
      <div className="text-center">
        <div className="w-8 h-8 border-2 border-brand-500 border-t-transparent rounded-full animate-spin mx-auto mb-3" />
        <p className="text-sm text-surface-500">Cargando Google Maps...</p>
      </div>
    </div>
  );

  return (
    <div className="relative w-full h-full">
      {/* Mapa */}
      <div ref={mapDivRef} className="w-full h-full rounded-xl overflow-hidden" />

      {/* Canvas heatmap (superpuesto al mapa, pointer-events:none) */}
      <canvas ref={heatCanvas}
        style={{
          position: "absolute", top: 0, left: 0, pointerEvents: "none",
          borderRadius: "0.75rem", display: "none",
        }} />

      {/* Toggle mapa/calor/ambos */}
      <div className="absolute top-3 right-3 z-10 flex gap-1 bg-white/90 backdrop-blur-sm
                      border border-surface-200 rounded-xl p-1 shadow-sm">
        {([
          { id: "map",  icon: <Map className="w-3.5 h-3.5" />,   label: "Mapa" },
          { id: "both", icon: <><Map className="w-3 h-3" /><Flame className="w-3 h-3" /></>, label: "Ambos" },
          { id: "heat", icon: <Flame className="w-3.5 h-3.5" />, label: "Calor" },
        ] as const).map(({ id, icon, label }) => (
          <button key={id} onClick={() => setViewMode(id)}
            title={label}
            className={cn("flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs font-semibold transition-all",
              viewMode === id
                ? "bg-brand-500 text-white shadow-sm"
                : "text-surface-500 hover:bg-surface-100")}>
            {icon}
            <span className="hidden sm:inline">{label}</span>
          </button>
        ))}
      </div>

      {/* Filtros (esquina superior izquierda) */}
      <div className="absolute top-3 left-3 z-10 flex flex-col gap-1.5">
        {(Object.entries(TIPO_V2) as [AnomalyTypeV2, typeof TIPO_V2[AnomalyTypeV2]][]).map(([tipo, cfg]) => (
          <button key={tipo}
            onClick={() => setFilters(f => ({ ...f, [tipo]: !f[tipo] }))}
            className={cn(
              "flex items-center gap-2 px-2.5 py-1.5 rounded-lg text-xs font-semibold",
              "shadow-sm border backdrop-blur-sm transition-all",
              filters[tipo]
                ? "bg-white/95 text-surface-800 border-surface-200"
                : "bg-white/60 text-surface-400 border-surface-100"
            )}>
            <span className="w-4 h-4 rounded-full flex items-center justify-center text-white shrink-0"
              style={{ backgroundColor: filters[tipo] ? cfg.color : "#9CA3AF", fontSize: 8, fontWeight: 700 }}>
              {cfg.letra}
            </span>
            <span className={filters[tipo] ? "" : "line-through"}>{cfg.label}</span>
            {filters[tipo]
              ? <Eye className="w-3 h-3 text-surface-300 ml-auto" />
              : <EyeOff className="w-3 h-3 text-surface-300 ml-auto" />}
          </button>
        ))}
      </div>

      {/* Leyenda */}
      <div className="absolute bottom-3 left-3 z-10 bg-white/92 backdrop-blur-sm
                      border border-surface-200 rounded-xl px-3 py-2.5 shadow-sm">
        <p className="text-[9px] font-bold text-surface-500 uppercase tracking-wide mb-2">Leyenda</p>
        <div className="space-y-1.5 mb-2">
          {(Object.entries(TIPO_V2) as [AnomalyTypeV2, typeof TIPO_V2[AnomalyTypeV2]][]).map(([tipo, cfg]) => (
            <div key={tipo} className="flex items-center gap-2">
              <div className="w-5 h-5 rounded-full border-2 border-white shadow-sm
                              flex items-center justify-center text-white font-bold"
                style={{ backgroundColor: cfg.color, fontSize: 8 }}>
                {cfg.letra}
              </div>
              <span className="text-[10px] text-surface-700 font-medium">{cfg.label}</span>
            </div>
          ))}
        </div>
        <div className="border-t border-surface-100 pt-2">
          <p className="text-[9px] font-bold text-surface-500 uppercase tracking-wide mb-1.5">Riesgo</p>
          {[["ALTO","#DC2626"],["MEDIO","#D97706"],["BAJO","#2563EB"]].map(([l, c]) => (
            <div key={l} className="flex items-center gap-1.5 mb-1">
              <div className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: c }} />
              <span className="text-[10px] text-surface-600">{l}</span>
            </div>
          ))}
        </div>
        {viewMode !== "map" && (
          <div className="border-t border-surface-100 pt-2 mt-1">
            <p className="text-[9px] font-bold text-surface-500 uppercase tracking-wide mb-1">Mapa de calor</p>
            <div className="flex gap-1 items-center">
              {[["#2563EB","Bajo"],["#22c55e",""],["#DC2626","Alto"]].map(([c, l]) => (
                <div key={c} className="flex items-center gap-1">
                  <div className="w-3 h-3 rounded-sm" style={{ backgroundColor: c }} />
                  {l && <span className="text-[9px] text-surface-500">{l}</span>}
                </div>
              ))}
            </div>
          </div>
        )}
        <button onClick={clearKey}
          className="text-[9px] text-surface-400 hover:text-brand-500 mt-2 block">
          ⚙ Cambiar API Key
        </button>
      </div>
    </div>
  );
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

Write-Host "  -> src\lib\georadar\generateInformeDocx.ts" -ForegroundColor Gray
$dst = "src\lib\georadar\generateInformeDocx.ts"
$content = @'
/**
 * src/lib/georadar/generateInformeDocx.ts
 *
 * Genera el informe Word de una pasada de georradar usando docx-js,
 * siguiendo la skill de docx de ObrasPlan (no el generador XML manual de
 * la app HTML original -- decision confirmada explicitamente: se prioriza
 * mantenibilidad sobre fidelidad exacta de formato).
 *
 * Contenido del informe: datos de la pasada, tabla resumen de resultados,
 * tabla de anomalias detectadas, y el texto del analisis IA si existe.
 */

import {
  Document,
  Packer,
  Paragraph,
  TextRun,
  Table,
  TableRow,
  TableCell,
  HeadingLevel,
  AlignmentType,
  BorderStyle,
  WidthType,
  ShadingType,
} from "docx";
import type { AnomalyResult, LayerResult, SandersEntry } from "./detectAnomalies";

export interface InformeData {
  clienteNombre: string;
  proyecto: string;
  zonaNombre: string;
  fecha: string;
  operador: string;
  dispositivoSn: string;
  dispositivoFw: string;
  longitudM: number;
  velocidadEm: number;
  material: SandersEntry;
  anoms: AnomalyResult[];
  layers: LayerResult[];
  analisisTexto?: string;
  analisisModelo?: string;
}

const border = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const borders = { top: border, bottom: border, left: border, right: border };
const CONTENT_WIDTH = 9360;

function headerCell(text: string, width: number) {
  return new TableCell({
    borders,
    width: { size: width, type: WidthType.DXA },
    shading: { fill: "1A2438", type: ShadingType.CLEAR },
    margins: { top: 80, bottom: 80, left: 120, right: 120 },
    children: [new Paragraph({ children: [new TextRun({ text, bold: true, color: "FFFFFF", size: 18 })] })],
  });
}

function dataCell(text: string, width: number) {
  return new TableCell({
    borders,
    width: { size: width, type: WidthType.DXA },
    margins: { top: 80, bottom: 80, left: 120, right: 120 },
    children: [new Paragraph({ children: [new TextRun({ text, size: 18 })] })],
  });
}

export async function generateInformeDocx(d: InformeData): Promise<Buffer> {
  const voids = d.anoms.filter((a) => a.type === "void");
  const supplies = d.anoms.filter((a) => a.type === "supply");
  const hi = voids.filter((a) => a.risk === "high").length;
  const me = voids.filter((a) => a.risk === "med").length;
  const lo = voids.filter((a) => a.risk === "low").length;
  const totBruto = voids.reduce((t, a) => t + a.vBruto, 0);
  const totNeto = voids.reduce((t, a) => t + a.vNet, 0);

  const riskLabel: Record<string, string> = { high: "ALTO", med: "MEDIO", low: "BAJO" };
  const typeLabel: Record<string, string> = { void: "Anomalía", supply: "Suministro", pipe: "Tubería", anomaly: "Anomalía" };

  const resumenRows: [string, string][] = [
    ["Cliente", d.clienteNombre || "-"],
    ["Proyecto", d.proyecto || "-"],
    ["Zona", d.zonaNombre],
    ["Fecha", d.fecha],
    ["Operador", d.operador || "-"],
    ["Equipo", "Proceq GS8000 Pro (S/N " + d.dispositivoSn + ", FW " + d.dispositivoFw + ")"],
    ["Longitud de perfil", d.longitudM.toFixed(1) + " m"],
    ["Velocidad EM", d.velocidadEm + " m/ns"],
    ["Material", d.material.n + " (porosidad " + (d.material.p * 100).toFixed(0) + "%, factor Sanders " + d.material.f + ")"],
  ];

  const resumenTable = new Table({
    width: { size: CONTENT_WIDTH, type: WidthType.DXA },
    columnWidths: [3120, 6240],
    rows: resumenRows.map(
      ([k, v]) =>
        new TableRow({
          children: [
            new TableCell({
              borders,
              width: { size: 3120, type: WidthType.DXA },
              shading: { fill: "F0F2F5", type: ShadingType.CLEAR },
              margins: { top: 80, bottom: 80, left: 120, right: 120 },
              children: [new Paragraph({ children: [new TextRun({ text: k, bold: true, size: 18 })] })],
            }),
            dataCell(v, 6240),
          ],
        })
    ),
  });

  const resultadosRows: [string, string][] = [
    ["Anomalías detectadas", String(voids.length)],
    ["Numero de suministros detectados", String(supplies.length)],
    ["Riesgo ALTO", String(hi)],
    ["Riesgo MEDIO", String(me)],
    ["Riesgo BAJO", String(lo)],
    ["Volumen bruto total", totBruto.toFixed(4) + " m3"],
    ["Volumen neto total", totNeto.toFixed(4) + " m3"],
  ];

  const resultadosTable = new Table({
    width: { size: CONTENT_WIDTH, type: WidthType.DXA },
    columnWidths: [5360, 4000],
    rows: resultadosRows.map(
      ([k, v]) =>
        new TableRow({
          children: [
            new TableCell({
              borders,
              width: { size: 5360, type: WidthType.DXA },
              shading: { fill: "F0F2F5", type: ShadingType.CLEAR },
              margins: { top: 80, bottom: 80, left: 120, right: 120 },
              children: [new Paragraph({ children: [new TextRun({ text: k, bold: true, size: 18 })] })],
            }),
            dataCell(v, 4000),
          ],
        })
    ),
  });

  const anomColWidths = [700, 1400, 1400, 1400, 1860, 2000];
  const anomHeaderRow = new TableRow({
    children: ["ID", "Tipo", "Riesgo", "Profundidad", "Dimensiones", "Vol. bruto / neto"].map((t, i) =>
      headerCell(t, anomColWidths[i])
    ),
  });
  const anomRows = d.anoms.map(
    (a, i) =>
      new TableRow({
        children: [
          dataCell((a.type === "void" || a.type === "anomaly" ? "A" : a.type === "supply" ? "S" : "T") + (i + 1), anomColWidths[0]),
          dataCell(typeLabel[a.type], anomColWidths[1]),
          dataCell(a.risk ? riskLabel[a.risk] : "-", anomColWidths[2]),
          dataCell(a.dM + " m", anomColWidths[3]),
          dataCell(a.wM + " x " + a.hM + " m", anomColWidths[4]),
          dataCell(a.type === "void" ? a.vBruto.toFixed(4) + " / " + a.vNet.toFixed(4) + " m3" : "-", anomColWidths[5]),
        ],
      })
  );
  const anomTable = new Table({
    width: { size: CONTENT_WIDTH, type: WidthType.DXA },
    columnWidths: anomColWidths,
    rows: [anomHeaderRow, ...anomRows],
  });

  const analisisParagraphs: Paragraph[] = [];
  if (d.analisisTexto) {
    analisisParagraphs.push(
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Analisis tecnico (IA)")] })
    );
    analisisParagraphs.push(
      new Paragraph({
        children: [
          new TextRun({ text: "Generado con " + (d.analisisModelo || "modelo IA"), italics: true, size: 16, color: "667085" }),
        ],
        spacing: { after: 200 },
      })
    );
    d.analisisTexto.split("\n").forEach((line) => {
      if (line.trim().startsWith("## ")) {
        analisisParagraphs.push(
          new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(line.replace(/^##\s*/, ""))] })
        );
      } else if (line.trim().length > 0) {
        analisisParagraphs.push(new Paragraph({ children: [new TextRun(line)] }));
      }
    });
  }

  const doc = new Document({
    styles: {
      default: { document: { run: { font: "Arial", size: 22 } } },
      paragraphStyles: [
        {
          id: "Heading1",
          name: "Heading 1",
          basedOn: "Normal",
          next: "Normal",
          quickFormat: true,
          run: { size: 28, bold: true, font: "Arial", color: "1A2438" },
          paragraph: { spacing: { before: 280, after: 160 }, outlineLevel: 0 },
        },
        {
          id: "Heading2",
          name: "Heading 2",
          basedOn: "Normal",
          next: "Normal",
          quickFormat: true,
          run: { size: 24, bold: true, font: "Arial", color: "CC1010" },
          paragraph: { spacing: { before: 200, after: 120 }, outlineLevel: 1 },
        },
      ],
    },
    sections: [
      {
        properties: {
          page: { size: { width: 12240, height: 15840 }, margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } },
        },
        children: [
          new Paragraph({
            alignment: AlignmentType.CENTER,
            children: [new TextRun({ text: "INFORME DE INTERPRETACION DE GEORRADAR", bold: true, size: 36, color: "CC1010" })],
            spacing: { after: 60 },
          }),
          new Paragraph({
            alignment: AlignmentType.CENTER,
            children: [new TextRun({ text: "LOYNEK Soluciones Tecnicas", size: 20, color: "667085" })],
            spacing: { after: 360 },
          }),

          new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Datos de la inspeccion")] }),
          resumenTable,

          new Paragraph({ children: [new TextRun("")], spacing: { after: 200 } }),
          new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Resultados")] }),
          resultadosTable,

          new Paragraph({ children: [new TextRun("")], spacing: { after: 200 } }),
          new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Anomalias detectadas")] }),
          anomTable,

          new Paragraph({ children: [new TextRun("")], spacing: { after: 200 } }),
          ...analisisParagraphs,
        ],
      },
    ],
  });

  return Packer.toBuffer(doc);
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

$ok = Select-String -Path "src\app\aplicaciones\georadar-v2\page.tsx" -Pattern "utf-16le" -Quiet
if ($ok) { Write-Host "    OK: soporte UTF-16 anadido" -ForegroundColor Green }
else { Write-Host "    ERROR" -ForegroundColor Red }
Write-Host ""
Write-Host '  git add -A'
Write-Host '  git commit -m "fix: CSV Proceq UTF-16 en Georadar V2, heatmap, Anomalia"'
Write-Host '  git push'
