#Requires -Version 5.1
# fix-georadar-v2-csv-crash-definitivo.ps1
# Crash al cargar CSV de parametros — causa raiz: DOMException en createImageData
#
# Flujo del crash:
#   handleLoadParams -> store.setAnchuraM() -> Zustand re-render
#   -> useEffect([renderChannel]) -> renderChannel()
#   -> wrap.clientWidth = 0 (panel no visible o en transicion)
#   -> canvas.width = 0, canvas.height = 0
#   -> ctx.createImageData(0, 0) -> DOMException no capturada
#   -> Next.js lo convierte en "client-side exception" que mata la pagina
#
# Fix en dos capas:
#   1. renderChannel(): guard "if (W < 2 || H < 2) return" antes de cualquier
#      operacion de canvas. Si el panel no es visible, se sale limpiamente.
#   2. drawBackground() en renderRadargram.ts: guard adicional "if (W<1||H<1) return"
#      como segunda linea de defensa en la funcion de bajo nivel.
#   3. GeoradarErrorBoundary (archivo nuevo): ErrorBoundary de React que captura
#      cualquier error que escapa las dos capas anteriores y muestra un panel
#      "Error / Reintentar" en lugar de destruir toda la pagina.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Aplicando fix CSV crash definitivo" -ForegroundColor Cyan

Write-Host "  -> src\app\aplicaciones\georadar-v2\page.tsx" -ForegroundColor Gray
$dst = "src\app\aplicaciones\georadar-v2\page.tsx"
$content = @'
"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import dynamic from "next/dynamic";
import { GeoradarErrorBoundary } from "./GeoradarErrorBoundary";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import {
  Radar, Upload, Zap, Loader2, FileText, Sparkles, AlertTriangle, CheckCircle2,
  Maximize2, Minimize2, ZoomIn, ZoomOut, RotateCcw, Map as MapIcon, Flame, Key,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";

import { parseSegy } from "@/lib/georadar/parseSegy";
import { genDemo } from "@/lib/georadar/genDemo";
import { detectAnomalies, SANDERS, type MaterialKey } from "@/lib/georadar/detectAnomalies";
import { parseGnssText, parseParamsText } from "@/lib/georadar/parseGnss";
import { normalizeRange, drawBackground, drawOverlay, maxDepthOf } from "@/lib/georadar/renderRadargram";
import { useGeoradarStore, type LayoutMode } from "@/lib/georadar/useGeoradarStore";
import { buildPrompt, type PromptContext } from "@/lib/georadar/buildPrompt";



const LS_AI_CLAUDE = "georadar_v2_claude_key";
const LS_AI_OPENAI  = "georadar_v2_openai_key";

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
  const [claudeKey, setClaudeKey] = useState("");
  const [openaiKey, setOpenaiKey] = useState("");
  const [showAIKeys, setShowAIKeys] = useState(false);
  const [reportUrl, setReportUrl] = useState<string | null>(null);
  const [generatingReport, setGeneratingReport] = useState(false);
  const [analysisError, setAnalysisError] = useState<string | null>(null);
  const [pasadaId, setPasadaId] = useState<string | null>(null);

  // Cargar keys de IA del localStorage al montar
  useEffect(() => {
    setClaudeKey(localStorage.getItem(LS_AI_CLAUDE) || "");
    setOpenaiKey(localStorage.getItem(LS_AI_OPENAI) || "");
  }, []);

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

      const W = wrap.clientWidth || 0;
      const H = wrap.clientHeight || 0;
      // Guard: no renderizar con dimensiones 0 (causa DOMException en createImageData)
      if (W < 2 || H < 2) return;
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
    const key = proveedor === "claude" ? claudeKey : openaiKey;
    if (!key) {
      setAnalysisError(`Introduce la API Key de ${proveedor === "claude" ? "Anthropic (Claude)" : "OpenAI"} en la sección IA.`);
      setShowAIKeys(true);
      return;
    }
    setAnalysisError(null);
    store.setAnalizando(true);
    try {
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
      const prompt = buildPrompt(promptContext);
      let texto = "";
      let modelo = "";

      if (proveedor === "claude") {
        modelo = "claude-opus-4-5";
        const r = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
            "anthropic-dangerous-direct-browser-access": "true",
          },
          body: JSON.stringify({ model: modelo, max_tokens: 4000, messages: [{ role: "user", content: prompt }] }),
        });
        if (!r.ok) { const e = await r.json().catch(() => ({})); throw new Error("Claude: " + ((e as any)?.error?.message || r.status)); }
        const j = await r.json();
        texto = j.content?.[0]?.text || "Sin respuesta";
      } else {
        modelo = "gpt-4o";
        const r = await fetch("https://api.openai.com/v1/chat/completions", {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": "Bearer " + key },
          body: JSON.stringify({ model: modelo, max_tokens: 4000, messages: [
            { role: "system", content: "Eres un experto en GPR y geotecnia. Responde en español técnico." },
            { role: "user", content: prompt },
          ]}),
        });
        if (!r.ok) { const e = await r.json().catch(() => ({})); throw new Error("OpenAI: " + ((e as any)?.error?.message || r.status)); }
        const j = await r.json();
        texto = j.choices?.[0]?.message?.content || "Sin respuesta";
      }
      store.setAnalisis(texto, modelo);
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
                <GeoradarErrorBoundary>
                  <MapsPanel />
                </GeoradarErrorBoundary>
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

                        </div>
                        <span className="text-surface-500 font-mono">{a.dM}m · {a.wM}×{a.hM}m</span>
                      </button>
                    ))}
                  </div>
                )}
              </div>

              <div className="card p-4">
                <div className="flex items-center justify-between mb-3">
                  <h2 className="text-xs font-semibold text-surface-400 uppercase tracking-wider">Análisis IA</h2>
                  <button onClick={() => setShowAIKeys(s => !s)}
                    className="text-[10px] text-brand-500 hover:underline flex items-center gap-1">
                    <Key className="w-3 h-3" />{showAIKeys ? "Ocultar" : "API Keys"}
                  </button>
                </div>
                {showAIKeys && (
                  <div className="mb-3 p-3 bg-surface-50 rounded-lg border border-surface-200 space-y-2">
                    <div>
                      <label className="block text-[10px] font-medium text-surface-500 mb-1 flex items-center gap-1">
                        <span className="w-2 h-2 rounded-full bg-brand-500 inline-block" /> Anthropic (Claude)
                        {claudeKey && <span className="text-emerald-500 ml-auto">✓</span>}
                      </label>
                      <div className="flex gap-1.5">
                        <input type="password" value={claudeKey} placeholder="sk-ant-..."
                          onChange={e => setClaudeKey(e.target.value)}
                          className="flex-1 px-2.5 py-1.5 text-xs border border-surface-200 rounded-lg bg-white" />
                        <button onClick={() => localStorage.setItem(LS_AI_CLAUDE, claudeKey)}
                          className="px-2.5 py-1.5 text-xs font-bold text-white bg-brand-500 rounded-lg hover:bg-brand-600">Guardar</button>
                      </div>
                    </div>
                    <div>
                      <label className="block text-[10px] font-medium text-surface-500 mb-1 flex items-center gap-1">
                        <span className="w-2 h-2 rounded-full bg-surface-600 inline-block" /> OpenAI (GPT-4o)
                        {openaiKey && <span className="text-emerald-500 ml-auto">✓</span>}
                      </label>
                      <div className="flex gap-1.5">
                        <input type="password" value={openaiKey} placeholder="sk-..."
                          onChange={e => setOpenaiKey(e.target.value)}
                          className="flex-1 px-2.5 py-1.5 text-xs border border-surface-200 rounded-lg bg-white" />
                        <button onClick={() => localStorage.setItem(LS_AI_OPENAI, openaiKey)}
                          className="px-2.5 py-1.5 text-xs font-bold text-white bg-surface-700 rounded-lg hover:bg-surface-800">Guardar</button>
                      </div>
                    </div>
                    <p className="text-[9px] text-surface-400">Las keys se guardan solo en este navegador.</p>
                  </div>
                )}
                {analysisError && (
                  <p className="text-xs text-red-600 mb-2 bg-red-50 px-2.5 py-2 rounded-lg">{analysisError}</p>
                )}
                <div className="flex gap-2">
                  <button onClick={() => runAnalysis("claude")} disabled={store.analizando}
                    title={!claudeKey ? "Configura la API Key de Claude" : "Analizar con Claude"}
                    className={cn("flex-1 flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-semibold rounded-lg disabled:opacity-60",
                      claudeKey ? "text-white bg-brand-500 hover:bg-brand-600" : "text-surface-400 bg-surface-100 cursor-not-allowed")}>
                    {store.analizando ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Sparkles className="w-3.5 h-3.5" />}
                    Claude {!claudeKey && "(sin key)"}
                  </button>
                  <button onClick={() => runAnalysis("gpt")} disabled={store.analizando}
                    title={!openaiKey ? "Configura la API Key de OpenAI" : "Analizar con GPT-4o"}
                    className={cn("flex-1 flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-semibold rounded-lg disabled:opacity-60",
                      openaiKey ? "text-surface-700 bg-surface-200 hover:bg-surface-300" : "text-surface-400 bg-surface-100 cursor-not-allowed")}>
                    {store.analizando ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Zap className="w-3.5 h-3.5" />}
                    GPT-4o {!openaiKey && "(sin key)"}
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

Write-Host "  -> src\app\aplicaciones\georadar-v2\GeoradarErrorBoundary.tsx" -ForegroundColor Gray
$dst = "src\app\aplicaciones\georadar-v2\GeoradarErrorBoundary.tsx"
$content = @'
"use client";
import React from "react";
import { AlertTriangle } from "lucide-react";

interface State { error: string | null }

export class GeoradarErrorBoundary extends React.Component<
  { children: React.ReactNode },
  State
> {
  constructor(props: { children: React.ReactNode }) {
    super(props);
    this.state = { error: null };
  }
  static getDerivedStateFromError(err: Error): State {
    return { error: err.message || "Error inesperado en el módulo" };
  }
  componentDidCatch(err: Error) {
    console.error("[GeoradarV2 Error]", err);
  }
  render() {
    if (this.state.error) {
      return (
        <div className="flex flex-col items-center justify-center h-full bg-red-50 rounded-xl border border-red-200 gap-3 p-6 min-h-[120px]">
          <AlertTriangle className="w-6 h-6 text-red-400" />
          <p className="text-xs font-semibold text-red-700 text-center max-w-xs">{this.state.error}</p>
          <button
            onClick={() => this.setState({ error: null })}
            className="px-3 py-1.5 text-xs text-red-600 border border-red-300 rounded-lg hover:bg-red-100"
          >
            Reintentar
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

Write-Host "  -> src\lib\georadar\renderRadargram.ts" -ForegroundColor Gray
$dst = "src\lib\georadar\renderRadargram.ts"
$content = @'
/**
 * src/lib/georadar/renderRadargram.ts
 *
 * Render del radargrama en canvas: imagen de fondo en escala de grises
 * (drawBackground, equivalente a drawBW del original) y overlay de capas
 * geologicas + anomalias detectadas (drawOverlay, equivalente a drawOver).
 *
 * Portado de la logica original, pero las funciones reciben directamente
 * el contexto de canvas y los datos en vez de buscar elementos por
 * document.getElementById, para poder usarlas desde refs de React.
 */

import type { SegyData } from "./parseSegy";
import type { AnomalyResult, LayerResult } from "./detectAnomalies";

export interface MinMax {
  mn: number;
  mx: number;
}

/** Calcula el rango min/max de un canal, necesario para normalizar a gris. */
export function normalizeRange(rd: SegyData): MinMax {
  let mn = 1e9;
  let mx = -1e9;
  for (let i = 0; i < rd.data.length; i++) {
    if (rd.data[i] < mn) mn = rd.data[i];
    if (rd.data[i] > mx) mx = rd.data[i];
  }
  return { mn, mx };
}

function getGray(v: number, range: MinMax): [number, number, number] {
  const n = Math.max(0, Math.min(1, (v - range.mn) / (range.mx - range.mn || 1)));
  const a = Math.max(0, Math.min(1, (n - 0.5) * 1.8 + 0.5));
  const g = Math.round(a * 255);
  return [g, g, g];
}

export function maxDepthOf(rd: SegyData, vel: number): number {
  return (vel * rd.dtNs * rd.ROWS) / 2;
}

/**
 * Dibuja el radargrama de fondo en escala de grises con reglas de
 * profundidad y distancia. cS/cE acotan el rango de columnas visible
 * (para zoom horizontal).
 */
export function drawBackground(
  ctx: CanvasRenderingContext2D,
  W: number,
  H: number,
  rd: SegyData | null,
  range: MinMax,
  vel: number,
  pw: number,
  cS = 0,
  cE?: number
) {
  if (!rd) {
    ctx.fillStyle = "#0a0c12";
    ctx.fillRect(0, 0, W, H);
    return;
  }
  const { data, COLS, ROWS } = rd;
  const colS = cS;
  const colE = cE ?? COLS;
  // Guard: createImageData lanza DOMException si W o H es 0
  if (W < 1 || H < 1) return;
  const img = ctx.createImageData(W, H);
  for (let y = 0; y < H; y++) {
    const ri = Math.min(Math.floor((y / H) * ROWS), ROWS - 1);
    for (let x = 0; x < W; x++) {
      const ci = Math.min(Math.floor(colS + (x / W) * (colE - colS)), COLS - 1);
      const [r, g, b] = getGray(data[ri * COLS + ci], range);
      const idx = (y * W + x) * 4;
      img.data[idx] = r;
      img.data[idx + 1] = g;
      img.data[idx + 2] = b;
      img.data[idx + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);

  const md = maxDepthOf(rd, vel);
  ctx.fillStyle = "rgba(8,10,18,.88)";
  ctx.fillRect(0, 0, 38, H);
  ctx.font = "7px IBM Plex Mono, monospace";
  ctx.fillStyle = "#668";
  for (let i = 0; i <= 8; i++) {
    const yy = (i / 8) * H;
    ctx.fillText(((md * i) / 8).toFixed(2) + "m", 2, yy + 8);
    ctx.strokeStyle = "rgba(255,255,255,.05)";
    ctx.lineWidth = 0.5;
    ctx.beginPath();
    ctx.moveTo(38, yy);
    ctx.lineTo(W, yy);
    ctx.stroke();
  }

  const sD = (colS / COLS) * pw;
  const spD = ((colE - colS) / COLS) * pw;
  ctx.fillStyle = "rgba(8,10,18,.88)";
  ctx.fillRect(38, 0, W, 15);
  for (let i = 0; i <= 10; i++) {
    const xr = 38 + (i / 10) * (W - 38);
    ctx.fillText((sD + (spD * i) / 10).toFixed(0) + "m", xr, 11);
  }
}

/**
 * Dibuja el overlay: lineas de capas geologicas con etiqueta, y marcas
 * de anomalias (elipses void/supply) con su volumen.
 */
export function drawOverlay(
  ctx: CanvasRenderingContext2D,
  W: number,
  H: number,
  rd: SegyData | null,
  vel: number,
  layers: LayerResult[],
  anoms: AnomalyResult[],
  selectedIndex: number,
  cS = 0,
  cE?: number
) {
  ctx.clearRect(0, 0, W, H);
  if (!rd) return;
  const { COLS, ROWS } = rd;
  const md = maxDepthOf(rd, vel);
  const colSpan = (cE ?? COLS) - cS;
  const colS2 = cS;

  layers.forEach((l) => {
    const yy = (l.depth / md) * H;
    ctx.strokeStyle = "rgba(0,0,0,.7)";
    ctx.lineWidth = 1.2;
    ctx.setLineDash([6, 4]);
    ctx.beginPath();
    ctx.moveTo(38, yy);
    ctx.lineTo(W, yy);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = "rgba(0,0,0,.85)";
    ctx.font = "bold 8px IBM Plex Mono, monospace";
    ctx.fillText(l.name.substring(0, 16), 40, yy - 2);
  });

  anoms.forEach((a, i) => {
    if (a.col < colS2 - 20 || a.col > colS2 + colSpan + 20) return;
    const relC = (a.col - colS2) / colSpan;
    const x = relC * W;
    const y = (a.row / ROWS) * H;
    const aw = Math.max((a.w / colSpan) * W, 10);
    const ah = Math.max((a.h / ROWS) * H, 7);
    const isV = a.type === "void";
    const col = isV ? "#ff2d5e" : "#ffbe00";
    const sel = selectedIndex === i;
    ctx.save();
    ctx.strokeStyle = col;
    ctx.lineWidth = sel ? 2.5 : 1.5;
    ctx.setLineDash(sel ? [] : [4, 3]);
    ctx.beginPath();
    ctx.ellipse(x, y, aw / 2, ah / 2, 0, 0, Math.PI * 2);
    ctx.fillStyle = isV ? "rgba(255,45,94,.1)" : "rgba(255,190,0,.08)";
    ctx.fill();
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = col;
    ctx.font = "bold 9px IBM Plex Mono, monospace";
    ctx.fillText((isV ? "H" : "S") + (i + 1) + " " + a.dM + "m", x + 8, y - 6);
    if (isV && a.vBruto > 0) {
      ctx.fillStyle = "rgba(8,10,18,.82)";
      ctx.fillRect(x + 8, y + 3, 70, 11);
      ctx.fillStyle = col;
      ctx.font = "7px IBM Plex Mono, monospace";
      ctx.fillText(a.vBruto.toFixed(4) + "m3", x + 10, y + 12);
    }
    if (sel) {
      ctx.strokeStyle = "rgba(204,16,16,.5)";
      ctx.lineWidth = 0.8;
      ctx.setLineDash([2, 2]);
      ctx.beginPath();
      ctx.moveTo(x, 16);
      ctx.lineTo(x, H);
      ctx.stroke();
      ctx.setLineDash([]);
    }
    ctx.restore();
  });
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

Write-Host ""
Write-Host "==> Verificando" -ForegroundColor Cyan
$ok1 = Select-String -LiteralPath (Join-Path $RepoPath "src\app\aplicaciones\georadar-v2\page.tsx") -Pattern "W < 2 \|\| H < 2" -Quiet
$ok2 = Select-String -LiteralPath (Join-Path $RepoPath "src\lib\georadar\renderRadargram.ts") -Pattern "W < 1 \|\| H < 1" -Quiet
$ok3 = Test-Path (Join-Path $RepoPath "src\app\aplicaciones\georadar-v2\GeoradarErrorBoundary.tsx")
if ($ok1) { Write-Host "    OK: guard W/H en renderChannel" -ForegroundColor Green }
else { Write-Host "    ERROR: falta guard en renderChannel" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: guard W/H en drawBackground" -ForegroundColor Green }
else { Write-Host "    ERROR: falta guard en drawBackground" -ForegroundColor Red }
if ($ok3) { Write-Host "    OK: GeoradarErrorBoundary.tsx creado" -ForegroundColor Green }
else { Write-Host "    ERROR: falta GeoradarErrorBoundary.tsx" -ForegroundColor Red }
Write-Host ""
Write-Host '  git add -A'
Write-Host '  git commit -m "fix: Georadar V2 crash CSV - guard W/H canvas + ErrorBoundary"'
Write-Host '  git push'
