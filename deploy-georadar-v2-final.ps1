#Requires -Version 5.1
# deploy-georadar-v2-final.ps1
# Georadar V2 completo con Google Maps:
#   - "Georadar V2 + IA" renombrado a "Georadar V2" en el menu
#   - Google Maps con marcadores diferenciados por tipo:
#     Hueco (rojo H), Suministro (azul S), Tuberia (ambar T), Anomalia (morado A)
#   - Leyenda visible con 4 tipos y 3 niveles de riesgo
#   - Informe exportable a PDF via window.print()
#   - 2 API Keys (Anthropic IA + Google Maps) en localStorage
#   - Visor de radargramas LF/HF con canales diferenciados
#   - Tabla de anomalias detallada
#   - La V1 (Interpretacion de Georradar) NO se toca

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Desplegando Georadar V2 con Google Maps" -ForegroundColor Cyan

Write-Host "  -> src\app\aplicaciones\georadar-v2\page.tsx" -ForegroundColor Gray
$dst = "src\app\aplicaciones\georadar-v2\page.tsx"
$content = @'
"use client";
/**
 * Georadar V2 — ObrasPlan
 * Versión mejorada con Google Maps, 4 tipos de anomalía y análisis IA avanzado.
 * Reutiliza parseSegy, detectAnomalies, renderRadargram y buildPromptV2 de la V1.
 * Google Maps se carga dinámicamente con script tag (no requiere dependencia npm).
 */

import { useState, useEffect, useRef, useCallback } from "react";
import dynamic from "next/dynamic";
import AppLayout from "@/components/layout/AppLayout";
import { cn } from "@/lib/utils/cn";
import {
  Radar, Upload, Loader2, Sparkles, AlertTriangle, FileText,
  Key, Eye, EyeOff, Trash2, Plus, CheckCircle2, XCircle,
  Info, Map, Layers, Download, RefreshCw, ZoomIn, ZoomOut,
} from "lucide-react";
import { parseSegy } from "@/lib/georadar/parseSegy";
import { genDemo } from "@/lib/georadar/genDemo";
import { detectAnomalies, SANDERS, type MaterialKey, type AnomalyResult } from "@/lib/georadar/detectAnomalies";
import { parseGnssText } from "@/lib/georadar/parseGnss";
import { normalizeRange, drawBackground, drawOverlay, maxDepthOf } from "@/lib/georadar/renderRadargram";
import { buildPromptV2 } from "@/lib/georadar/buildPromptV2";

// ============================================================
// Constantes y tipos
// ============================================================
const LS_APIKEY_AI    = "georadar_v2_apikey";
const LS_APIKEY_MAPS  = "georadar_v2_gmaps_key";
const AI_MODEL        = "claude-opus-4-5";

type AnomalyType = "void" | "supply" | "pipe" | "anomaly";

const TIPO_CONFIG: Record<AnomalyType, { label: string; color: string; bg: string; svg: string; letra: string }> = {
  void:    { label: "Hueco",      color: "#DC2626", bg: "bg-red-100 text-red-700",    svg: "#DC2626", letra: "H" },
  supply:  { label: "Suministro", color: "#2563EB", bg: "bg-blue-100 text-blue-700",  svg: "#2563EB", letra: "S" },
  pipe:    { label: "Tubería",    color: "#D97706", bg: "bg-amber-100 text-amber-700", svg: "#D97706", letra: "T" },
  anomaly: { label: "Anomalía",   color: "#7C3AED", bg: "bg-purple-100 text-purple-700", svg: "#7C3AED", letra: "A" },
};

const RISK_COLOR: Record<string, string> = {
  high: "#DC2626", med: "#D97706", low: "#2563EB",
};

const MATERIALES = [
  { value: "sf" as MaterialKey, label: "Arena fina seca" },
  { value: "gr" as MaterialKey, label: "Grava / arena húmeda" },
  { value: "cl" as MaterialKey, label: "Arcilla" },
  { value: "ro" as MaterialKey, label: "Roca" },
  { value: "mx" as MaterialKey, label: "Material mixto" },
];

const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

// ============================================================
// Componente Google Maps
// ============================================================
function GoogleMapsViewer({
  gmapsKey, anomalias, gpsTrack,
}: {
  gmapsKey: string;
  anomalias: AnomalyResult[];
  gpsTrack: { lat: number; lon: number }[];
}) {
  const mapRef = useRef<HTMLDivElement>(null);
  const mapInstance = useRef<any>(null);
  const markersRef = useRef<any[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!gmapsKey) return;
    if ((window as any).google?.maps) { setLoaded(true); return; }

    const existing = document.getElementById("gmaps-script");
    if (existing) { existing.addEventListener("load", () => setLoaded(true)); return; }

    const script = document.createElement("script");
    script.id = "gmaps-script";
    script.src = `https://maps.googleapis.com/maps/api/js?key=${gmapsKey}&libraries=geometry`;
    script.async = true;
    script.defer = true;
    script.onload = () => setLoaded(true);
    script.onerror = () => setError("Error al cargar Google Maps. Verifica la API Key.");
    document.head.appendChild(script);
  }, [gmapsKey]);

  useEffect(() => {
    if (!loaded || !mapRef.current) return;
    const G = (window as any).google.maps;

    // Centro por defecto (España)
    const center = gpsTrack.length > 0
      ? { lat: gpsTrack[0].lat, lng: gpsTrack[0].lon }
      : { lat: 40.416775, lng: -3.703790 };

    if (!mapInstance.current) {
      mapInstance.current = new G.Map(mapRef.current, {
        center, zoom: 18,
        mapTypeId: "satellite",
        styles: [], // Google Maps por defecto
      });
    }

    // Limpiar marcadores anteriores
    markersRef.current.forEach(m => m.setMap(null));
    markersRef.current = [];

    // Traza GPS
    if (gpsTrack.length > 1) {
      const path = gpsTrack.map(p => ({ lat: p.lat, lng: p.lon }));
      const poly = new G.Polyline({
        path, geodesic: true,
        strokeColor: "#F59E0B", strokeOpacity: 1, strokeWeight: 3,
      });
      poly.setMap(mapInstance.current);
      markersRef.current.push(poly);

      // Ajustar bounds al track
      const bounds = new G.LatLngBounds();
      path.forEach((p: any) => bounds.extend(p));
      mapInstance.current.fitBounds(bounds);
    }

    // Marcadores de anomalías
    anomalias.forEach((a, i) => {
      if (!a.gpt) return;
      const cfg = TIPO_CONFIG[a.type as AnomalyType] || TIPO_CONFIG.anomaly;
      const riskColor = RISK_COLOR[a.risk] || "#6B7280";

      // SVG del marcador según tipo
      const svgContent = `<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 36 36">
        <circle cx="18" cy="18" r="16" fill="${cfg.color}" stroke="white" stroke-width="2.5"/>
        ${a.risk === "high" ? `<circle cx="18" cy="18" r="16" fill="none" stroke="white" stroke-width="1.5" stroke-dasharray="3,2" opacity=".7"/>` : ""}
        <text x="18" y="23" text-anchor="middle" fill="white" font-size="11" font-weight="bold" font-family="monospace">${cfg.letra}${i + 1}</text>
      </svg>`;

      const icon = {
        url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(svgContent)}`,
        scaledSize: new G.Size(36, 36),
        anchor: new G.Point(18, 18),
      };

      const marker = new G.Marker({
        position: { lat: a.gpt.lat, lng: a.gpt.lon },
        map: mapInstance.current,
        icon,
        title: `${cfg.label} ${i + 1}`,
        zIndex: a.risk === "high" ? 100 : a.risk === "med" ? 50 : 10,
      });

      const infoContent = `
        <div style="font-family:system-ui;min-width:200px;padding:4px">
          <div style="font-weight:700;color:${cfg.color};margin-bottom:6px;font-size:13px">
            ${cfg.label} ${i + 1}
          </div>
          <table style="width:100%;border-collapse:collapse;font-size:12px">
            <tr><td style="color:#6B7280;padding:2px 4px 2px 0">Distancia</td><td style="font-weight:600">${a.distM} m</td></tr>
            <tr><td style="color:#6B7280;padding:2px 4px 2px 0">Profundidad</td><td style="font-weight:600">${a.dM} m</td></tr>
            <tr><td style="color:#6B7280;padding:2px 4px 2px 0">Dimensiones</td><td style="font-weight:600">${a.wM}×${a.hM} m</td></tr>
            ${a.type === "void" ? `<tr><td style="color:#6B7280;padding:2px 4px 2px 0">Vol. neto</td><td style="font-weight:600">${a.vNet.toFixed(4)} m³</td></tr>` : ""}
            <tr><td style="color:#6B7280;padding:2px 4px 2px 0">Riesgo</td>
              <td style="font-weight:700;color:${riskColor}">${a.risk === "high" ? "ALTO" : a.risk === "med" ? "MEDIO" : "BAJO"}</td></tr>
            <tr><td style="color:#6B7280;padding:2px 4px 2px 0">Confianza</td><td style="font-weight:600">${Math.round(a.conf * 100)}%</td></tr>
          </table>
        </div>`;

      const infoWindow = new G.InfoWindow({ content: infoContent });
      marker.addListener("click", () => {
        infoWindow.open(mapInstance.current, marker);
      });

      markersRef.current.push(marker);
    });
  }, [loaded, anomalias, gpsTrack]);

  if (!gmapsKey) return (
    <div className="flex items-center justify-center h-full bg-surface-50 rounded-xl border border-surface-200">
      <div className="text-center p-6">
        <Map className="w-10 h-10 mx-auto mb-3 text-surface-300" />
        <p className="text-sm text-surface-500 font-medium">Configura la Google Maps API Key para activar el mapa</p>
      </div>
    </div>
  );

  if (error) return (
    <div className="flex items-center justify-center h-full bg-red-50 rounded-xl border border-red-200">
      <div className="text-center p-6">
        <AlertTriangle className="w-8 h-8 mx-auto mb-2 text-red-400" />
        <p className="text-sm text-red-600">{error}</p>
      </div>
    </div>
  );

  return (
    <div ref={mapRef} className="w-full h-full rounded-xl overflow-hidden"
      style={{ minHeight: 400 }} />
  );
}

// ============================================================
// Leyenda del mapa
// ============================================================
function Leyenda() {
  return (
    <div className="flex flex-wrap items-center gap-3 px-4 py-2.5 bg-white/90 backdrop-blur-sm border border-surface-200 rounded-xl shadow-sm text-xs">
      <span className="font-semibold text-surface-600 mr-1">Leyenda:</span>
      {(Object.entries(TIPO_CONFIG) as [AnomalyType, typeof TIPO_CONFIG[AnomalyType]][]).map(([type, cfg]) => (
        <div key={type} className="flex items-center gap-1.5">
          <div className="w-5 h-5 rounded-full border-2 border-white shadow-sm flex items-center justify-center text-white font-bold"
            style={{ backgroundColor: cfg.color, fontSize: 8 }}>
            {cfg.letra}
          </div>
          <span className="text-surface-600">{cfg.label}</span>
        </div>
      ))}
      <div className="flex items-center gap-2 ml-2 pl-2 border-l border-surface-200">
        <span className="font-semibold text-surface-600">Riesgo:</span>
        {[["ALTO", "#DC2626"], ["MEDIO", "#D97706"], ["BAJO", "#2563EB"]].map(([label, color]) => (
          <div key={label} className="flex items-center gap-1">
            <div className="w-2 h-2 rounded-full" style={{ backgroundColor: color }} />
            <span className="text-surface-500">{label}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ============================================================
// Página principal
// ============================================================
export default function GeoradarV2Page() {
  // API Keys
  const [aiKey, setAiKey]   = useState("");
  const [mapsKey, setMapsKey] = useState("");
  const [showAiKey, setShowAiKey]   = useState(false);
  const [showMapsKey, setShowMapsKey] = useState(false);
  const [keysVisible, setKeysVisible] = useState(false);

  // Datos del proyecto
  const [proyecto,  setProyecto]  = useState("");
  const [operador,  setOperador]  = useState("");
  const [cliente,   setCliente]   = useState("");
  const [fecha,     setFecha]     = useState(new Date().toISOString().slice(0, 10));
  const [zona,      setZona]      = useState("");
  const [material,  setMaterial]  = useState<MaterialKey>("gr");
  const [vel,       setVel]       = useState(0.1);
  const [pw,        setPw]        = useState(10);

  // Archivos
  const [lfFile, setLfFile] = useState<File | null>(null);
  const [hfFile, setHfFile] = useState<File | null>(null);
  const [gpsFile, setGpsFile] = useState<File | null>(null);

  // Radargramas procesados
  const lfCanvas = useRef<HTMLCanvasElement>(null);
  const hfCanvas = useRef<HTMLCanvasElement>(null);
  const [lfReady, setLfReady] = useState(false);
  const [hfReady, setHfReady] = useState(false);
  const [anomalias, setAnomalias] = useState<AnomalyResult[]>([]);
  const [gpsTrack, setGpsTrack] = useState<{ lat: number; lon: number }[]>([]);
  const [procesando, setProcesando] = useState(false);

  // IA
  const [analizando, setAnalizando] = useState(false);
  const [analisisIA, setAnalisisIA] = useState<string | null>(null);
  const [errorIA, setErrorIA] = useState<string | null>(null);

  // Tab activa
  const [tab, setTab] = useState<"radargrama" | "mapa" | "anomalias" | "informe">("radargrama");

  // Cargar keys de localStorage
  useEffect(() => {
    setAiKey(localStorage.getItem(LS_APIKEY_AI) || "");
    setMapsKey(localStorage.getItem(LS_APIKEY_MAPS) || "");
  }, []);

  const saveKey = (key: "ai" | "maps", value: string) => {
    if (key === "ai")   { localStorage.setItem(LS_APIKEY_AI, value.trim());   setAiKey(value.trim()); }
    if (key === "maps") { localStorage.setItem(LS_APIKEY_MAPS, value.trim()); setMapsKey(value.trim()); }
  };
  const deleteKey = (key: "ai" | "maps") => {
    if (key === "ai")   { localStorage.removeItem(LS_APIKEY_AI);   setAiKey(""); }
    if (key === "maps") { localStorage.removeItem(LS_APIKEY_MAPS); setMapsKey(""); }
  };

  // Procesar archivos SEGY
  const procesarArchivos = useCallback(async () => {
    setProcesando(true);
    try {
      const snd = SANDERS[material];
      let lfData: any = null, hfData: any = null;

      if (lfFile) {
        const buf = await lfFile.arrayBuffer();
        lfData = parseSegy(new Uint8Array(buf));
      } else {
        lfData = genDemo("lf");
      }

      if (hfFile) {
        const buf = await hfFile.arrayBuffer();
        hfData = parseSegy(new Uint8Array(buf));
      } else {
        hfData = genDemo("hf");
      }

      // Renderizar LF
      if (lfCanvas.current && lfData) {
        const canvas = lfCanvas.current;
        canvas.width = lfData.COLS; canvas.height = lfData.ROWS;
        const ctx = canvas.getContext("2d");
        if (ctx) {
          const range = normalizeRange(lfData);
          drawBackground(ctx, canvas.width, canvas.height, lfData, range, vel, pw);
          drawOverlay(ctx, canvas.width, canvas.height, lfData, range, 0, lfData.COLS, [], vel, pw);
          setLfReady(true);
        }
      }
      // Renderizar HF
      if (hfCanvas.current && hfData) {
        const canvas = hfCanvas.current;
        canvas.width = hfData.COLS; canvas.height = hfData.ROWS;
        const ctx = canvas.getContext("2d");
        if (ctx) {
          const range = normalizeRange(hfData);
          drawBackground(ctx, canvas.width, canvas.height, hfData, range, vel, pw);
          drawOverlay(ctx, canvas.width, canvas.height, hfData, range, 0, hfData.COLS, [], vel, pw);
          setHfReady(true);
        }
      }

      // GPS
      let gps: { lat: number; lon: number; dist: number }[] = [];
      if (gpsFile) {
        const txt = await gpsFile.text();
        gps = parseGnssText(txt);
        setGpsTrack(gps.map(p => ({ lat: p.lat, lon: p.lon })));
      }

      // Detectar anomalías
      const params = { vel, material, pw, pl: pw * 0.3, gps };
      const result = detectAnomalies(lfData, params);
      setAnomalias(result.anoms);

    } catch (e: any) {
      console.error(e);
    } finally {
      setProcesando(false);
    }
  }, [lfFile, hfFile, gpsFile, material, vel, pw]);

  // Análisis IA
  const handleAnalisisIA = async () => {
    if (!aiKey) { setErrorIA("Configura la API Key de Anthropic para usar el análisis IA."); return; }
    setAnalizando(true); setErrorIA(null);

    try {
      const ctx = {
        proyecto: proyecto || "Sin nombre",
        operador: operador || "—",
        fecha,
        equipo: "Proceq GS8000 Pro",
        vel, er: Math.round(9 / (vel * vel * 100)),
        maxDepth: maxDepthOf(genDemo("lf"), vel),
        perfilM: pw,
        material: MATERIALES.find(m => m.value === material)?.label || material,
        porosidad: SANDERS[material]?.p || 0.35,
        fSanders: SANDERS[material]?.f || 0.8,
        capas: "", gpsCount: gpsTrack.length,
        anomalias: anomalias.map((a, i) => ({
          id: `${TIPO_CONFIG[a.type as AnomalyType]?.letra || "A"}${i + 1}`,
          tipo: a.type,
          distancia: a.distM,
          profundidad: a.dM,
          riesgo: a.risk === "high" ? "alto" as const : a.risk === "med" ? "medio" as const : "bajo" as const,
          confianza: Math.round(a.conf * 100),
          ancho: a.wM, alto: a.hM,
          volBruto: a.vBruto, volNeto: a.vNet,
          gps: a.gpt ? { lat: a.gpt.lat, lon: a.gpt.lon, elev: 0 } : undefined,
        })),
      };

      const prompt = buildPromptV2(ctx);
      const resp = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": aiKey,
          "anthropic-version": "2023-06-01",
          "anthropic-dangerous-direct-browser-access": "true",
        },
        body: JSON.stringify({
          model: AI_MODEL, max_tokens: 4096,
          messages: [{ role: "user", content: prompt }],
        }),
      });

      if (!resp.ok) {
        const e = await resp.json().catch(() => ({}));
        throw new Error((e as any)?.error?.message || `Error ${resp.status}`);
      }
      const data = await resp.json();
      const text = data.content?.find((b: any) => b.type === "text")?.text || "";
      setAnalisisIA(text);
      setTab("informe");
    } catch (e: any) {
      setErrorIA("Error IA: " + (e?.message || e));
    } finally {
      setAnalizando(false);
    }
  };

  // Exportar informe PDF (via print del navegador)
  const exportarPDF = () => {
    const printContent = document.getElementById("georadar-informe");
    if (!printContent) return;
    const win = window.open("", "_blank");
    if (!win) return;
    win.document.write(`<!DOCTYPE html><html><head>
      <title>Informe Georadar — ${proyecto || "ObrasPlan"}</title>
      <style>
        body { font-family: Arial, sans-serif; font-size: 12px; color: #1f2937; margin: 20mm; }
        h1 { color: #DC2626; font-size: 18px; border-bottom: 2px solid #DC2626; padding-bottom: 8px; }
        h2 { color: #374151; font-size: 14px; margin-top: 20px; border-left: 3px solid #DC2626; padding-left: 8px; }
        h3 { color: #4B5563; font-size: 12px; margin-top: 12px; }
        table { width: 100%; border-collapse: collapse; margin: 8px 0; }
        th { background: #F3F4F6; font-weight: 700; padding: 6px 8px; text-align: left; border: 1px solid #E5E7EB; }
        td { padding: 5px 8px; border: 1px solid #E5E7EB; }
        tr:nth-child(even) td { background: #F9FAFB; }
        .badge-hueco { color: #DC2626; font-weight: 700; }
        .badge-supply { color: #2563EB; font-weight: 700; }
        .badge-pipe { color: #D97706; font-weight: 700; }
        .badge-anomaly { color: #7C3AED; font-weight: 700; }
        .aviso { background: #FEF3C7; border: 1px solid #F59E0B; padding: 8px 12px; border-radius: 4px; font-size: 11px; }
        pre { background: #F9FAFB; padding: 12px; font-size: 10px; white-space: pre-wrap; border: 1px solid #E5E7EB; border-radius: 4px; }
        @page { margin: 15mm; }
      </style>
    </head><body>${printContent.innerHTML}</body></html>`);
    win.document.close();
    setTimeout(() => win.print(), 400);
  };

  const totalHuecos   = anomalias.filter(a => a.type === "void").length;
  const totalSupply   = anomalias.filter(a => a.type === "supply").length;
  const totalPipe     = anomalias.filter(a => a.type === "pipe").length;
  const totalAnomaly  = anomalias.filter(a => a.type === "anomaly").length;
  const volTotal      = anomalias.filter(a => a.type === "void").reduce((s, a) => s + a.vNet, 0);

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in pb-12">

        {/* Cabecera */}
        <div className="flex items-center gap-3 mb-5">
          <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
            <Radar className="w-5 h-5 text-brand-600" />
          </div>
          <div>
            <h1 className="text-xl font-display font-bold text-surface-900 flex items-center gap-2">
              Georadar V2
              <span className="badge bg-brand-100 text-brand-700 text-[10px]">Google Maps · IA</span>
            </h1>
            <p className="text-sm text-surface-500">Prospección GPR — análisis IA avanzado</p>
          </div>
          <button onClick={() => setKeysVisible(s => !s)}
            className="ml-auto flex items-center gap-1.5 px-3 py-1.5 text-xs text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">
            <Key className="w-3.5 h-3.5" />
            API Keys {aiKey && mapsKey ? "✓" : "⚠"}
          </button>
        </div>

        {/* Panel API Keys */}
        {keysVisible && (
          <div className="card p-4 mb-5 border border-amber-200 bg-amber-50/40 space-y-3">
            <p className="text-xs font-semibold text-amber-800 flex items-center gap-2">
              <Key className="w-3.5 h-3.5" />Configuración de API Keys — guardadas solo en este navegador
            </p>
            {/* AI Key */}
            <div className="grid sm:grid-cols-2 gap-3">
              <div>
                <label className="block text-xs text-surface-600 mb-1">Anthropic API Key (análisis IA)</label>
                <div className="flex gap-2">
                  <div className="relative flex-1">
                    <input type={showAiKey ? "text" : "password"} value={aiKey}
                      onChange={e => setAiKey(e.target.value)} placeholder="sk-ant-..."
                      className={cn(ic, "pr-9 text-xs")} />
                    <button onClick={() => setShowAiKey(s => !s)}
                      className="absolute right-2.5 top-1/2 -translate-y-1/2 text-surface-400">
                      {showAiKey ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                    </button>
                  </div>
                  <button onClick={() => saveKey("ai", aiKey)}
                    className="px-2.5 py-1.5 text-xs font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
                    Guardar
                  </button>
                  {aiKey && <button onClick={() => deleteKey("ai")} className="p-1.5 text-red-400 hover:bg-red-50 rounded-lg"><Trash2 className="w-3.5 h-3.5" /></button>}
                </div>
              </div>
              {/* Maps Key */}
              <div>
                <label className="block text-xs text-surface-600 mb-1">Google Maps API Key</label>
                <div className="flex gap-2">
                  <div className="relative flex-1">
                    <input type={showMapsKey ? "text" : "password"} value={mapsKey}
                      onChange={e => setMapsKey(e.target.value)} placeholder="AIza..."
                      className={cn(ic, "pr-9 text-xs")} />
                    <button onClick={() => setShowMapsKey(s => !s)}
                      className="absolute right-2.5 top-1/2 -translate-y-1/2 text-surface-400">
                      {showMapsKey ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                    </button>
                  </div>
                  <button onClick={() => saveKey("maps", mapsKey)}
                    className="px-2.5 py-1.5 text-xs font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
                    Guardar
                  </button>
                  {mapsKey && <button onClick={() => deleteKey("maps")} className="p-1.5 text-red-400 hover:bg-red-50 rounded-lg"><Trash2 className="w-3.5 h-3.5" /></button>}
                </div>
              </div>
            </div>
            <p className="text-[10px] text-amber-700 flex items-start gap-1.5">
              <Info className="w-3 h-3 shrink-0 mt-0.5" />
              Las keys se almacenan en localStorage de este navegador y nunca se envían a servidores de Loynek.
            </p>
          </div>
        )}

        {/* Aviso IA */}
        <div className="bg-amber-50 border border-amber-200 rounded-xl px-4 py-2.5 mb-5 flex items-center gap-2.5">
          <AlertTriangle className="w-4 h-4 text-amber-600 shrink-0" />
          <p className="text-xs text-amber-800">
            <strong>Aviso técnico:</strong> La interpretación IA es orientativa y debe ser revisada por un técnico competente.
            No sustituye las comprobaciones en campo.
          </p>
        </div>

        {/* Grid principal */}
        <div className="grid lg:grid-cols-3 gap-5">

          {/* === Columna izquierda: parámetros + carga === */}
          <div className="space-y-4">

            {/* Datos del proyecto */}
            <div className="card p-4">
              <h2 className="text-xs font-semibold text-surface-600 uppercase tracking-wide mb-3">Datos del proyecto</h2>
              <div className="space-y-2">
                {[
                  { label: "Proyecto", val: proyecto, set: setProyecto },
                  { label: "Cliente",  val: cliente,  set: setCliente  },
                  { label: "Zona",     val: zona,     set: setZona     },
                  { label: "Operador", val: operador, set: setOperador },
                ].map(({ label, val, set }) => (
                  <div key={label}>
                    <label className="block text-[10px] font-medium text-surface-500 mb-0.5">{label}</label>
                    <input className={cn(ic, "text-xs")} value={val} onChange={e => set(e.target.value)} />
                  </div>
                ))}
                <div>
                  <label className="block text-[10px] font-medium text-surface-500 mb-0.5">Fecha</label>
                  <input type="date" className={cn(ic, "text-xs")} value={fecha} onChange={e => setFecha(e.target.value)} />
                </div>
              </div>
            </div>

            {/* Parámetros GPR */}
            <div className="card p-4">
              <h2 className="text-xs font-semibold text-surface-600 uppercase tracking-wide mb-3">Parámetros GPR</h2>
              <div className="space-y-2">
                <div>
                  <label className="block text-[10px] font-medium text-surface-500 mb-0.5">Material del subsuelo</label>
                  <select className={cn(ic, "text-xs")} value={material} onChange={e => setMaterial(e.target.value as MaterialKey)}>
                    {MATERIALES.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
                  </select>
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <div>
                    <label className="block text-[10px] font-medium text-surface-500 mb-0.5">Vel. EM (m/ns)</label>
                    <input type="number" step="0.001" className={cn(ic, "text-xs")} value={vel} onChange={e => setVel(parseFloat(e.target.value)||0.1)} />
                  </div>
                  <div>
                    <label className="block text-[10px] font-medium text-surface-500 mb-0.5">Longitud perfil (m)</label>
                    <input type="number" step="0.1" className={cn(ic, "text-xs")} value={pw} onChange={e => setPw(parseFloat(e.target.value)||10)} />
                  </div>
                </div>
              </div>
            </div>

            {/* Carga de archivos */}
            <div className="card p-4">
              <h2 className="text-xs font-semibold text-surface-600 uppercase tracking-wide mb-3">Archivos de prospección</h2>
              <div className="space-y-2">
                {[
                  { label: "Canal LF (.sgy)", file: lfFile, set: setLfFile, accept: ".sgy,.segy" },
                  { label: "Canal HF (.sgy)", file: hfFile, set: setHfFile, accept: ".sgy,.segy" },
                  { label: "GPS / GNSS (.csv,.txt)", file: gpsFile, set: setGpsFile, accept: ".csv,.txt,.nmea" },
                ].map(({ label, file, set, accept }) => (
                  <div key={label}>
                    <label className="block text-[10px] font-medium text-surface-500 mb-0.5">{label}</label>
                    <div className={cn("flex items-center gap-2 px-3 py-2 border rounded-lg text-xs cursor-pointer hover:bg-surface-50 transition-colors",
                      file ? "border-brand-300 bg-brand-50/30" : "border-surface-200 border-dashed")}>
                      <Upload className="w-3.5 h-3.5 text-surface-400 shrink-0" />
                      <span className="flex-1 truncate text-surface-500">{file ? file.name : "Sin archivo — usar demo"}</span>
                      <input type="file" accept={accept} className="hidden"
                        onChange={e => set(e.target.files?.[0] || null)}
                        id={`file-${label}`} />
                      <label htmlFor={`file-${label}`} className="text-brand-600 hover:underline cursor-pointer shrink-0">
                        {file ? "Cambiar" : "Cargar"}
                      </label>
                    </div>
                  </div>
                ))}
              </div>
              <div className="flex gap-2 mt-3">
                <button onClick={procesarArchivos} disabled={procesando}
                  className="flex-1 flex items-center justify-center gap-2 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
                  {procesando ? <Loader2 className="w-4 h-4 animate-spin" /> : <RefreshCw className="w-4 h-4" />}
                  {procesando ? "Procesando..." : "Procesar"}
                </button>
                <button onClick={handleAnalisisIA} disabled={analizando || !aiKey}
                  title={!aiKey ? "Configura la API Key de Anthropic" : ""}
                  className="flex items-center gap-1.5 px-3 py-2 text-sm font-semibold text-white bg-purple-600 rounded-lg hover:bg-purple-700 disabled:opacity-50">
                  {analizando ? <Loader2 className="w-4 h-4 animate-spin" /> : <Sparkles className="w-4 h-4" />}
                  IA
                </button>
              </div>
              {errorIA && (
                <div className="mt-2 text-xs text-red-600 bg-red-50 border border-red-200 rounded-lg px-3 py-2 flex items-start gap-2">
                  <AlertTriangle className="w-3.5 h-3.5 shrink-0 mt-0.5" />{errorIA}
                </div>
              )}
            </div>

            {/* Resumen anomalías */}
            {anomalias.length > 0 && (
              <div className="card p-4">
                <h2 className="text-xs font-semibold text-surface-600 uppercase tracking-wide mb-3">Resumen detección</h2>
                <div className="grid grid-cols-2 gap-2">
                  {[
                    { tipo: "void" as AnomalyType, count: totalHuecos },
                    { tipo: "supply" as AnomalyType, count: totalSupply },
                    { tipo: "pipe" as AnomalyType, count: totalPipe },
                    { tipo: "anomaly" as AnomalyType, count: totalAnomaly },
                  ].map(({ tipo, count }) => {
                    const cfg = TIPO_CONFIG[tipo];
                    return (
                      <div key={tipo} className="flex items-center gap-2 p-2 rounded-lg bg-surface-50 border border-surface-100">
                        <div className="w-6 h-6 rounded-full flex items-center justify-center text-white font-bold text-[9px] shrink-0"
                          style={{ backgroundColor: cfg.color }}>{cfg.letra}</div>
                        <div>
                          <p className="text-sm font-bold text-surface-900">{count}</p>
                          <p className="text-[10px] text-surface-500">{cfg.label}{count !== 1 ? "s" : ""}</p>
                        </div>
                      </div>
                    );
                  })}
                </div>
                {totalHuecos > 0 && (
                  <p className="text-xs text-surface-500 mt-2">
                    Volumen neto total huecos: <strong className="text-surface-800">{volTotal.toFixed(4)} m³</strong>
                  </p>
                )}
              </div>
            )}
          </div>

          {/* === Columna derecha (2/3): visor principal === */}
          <div className="lg:col-span-2 space-y-4">

            {/* Tabs */}
            <div className="flex gap-1 p-1 bg-surface-100 rounded-xl">
              {([
                { id: "radargrama", label: "Radargramas" },
                { id: "mapa",       label: "Google Maps" },
                { id: "anomalias",  label: `Anomalías (${anomalias.length})` },
                { id: "informe",    label: analisisIA ? "Informe IA ✓" : "Informe" },
              ] as const).map(t => (
                <button key={t.id} onClick={() => setTab(t.id)}
                  className={cn("flex-1 py-2 text-xs font-semibold rounded-lg transition-colors",
                    tab === t.id ? "bg-white text-surface-900 shadow-sm" : "text-surface-500 hover:text-surface-700")}>
                  {t.label}
                </button>
              ))}
            </div>

            {/* Tab: Radargramas */}
            {tab === "radargrama" && (
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="card p-3">
                  <p className="text-xs font-semibold text-surface-600 mb-2 flex items-center gap-1.5">
                    <span className="w-2 h-2 rounded-full bg-brand-500 inline-block" />Canal LF
                    {lfReady && <CheckCircle2 className="w-3.5 h-3.5 text-emerald-500 ml-auto" />}
                  </p>
                  <canvas ref={lfCanvas} className="w-full rounded-lg bg-surface-900"
                    style={{ aspectRatio: "3/1", imageRendering: "pixelated" }} />
                </div>
                <div className="card p-3">
                  <p className="text-xs font-semibold text-surface-600 mb-2 flex items-center gap-1.5">
                    <span className="w-2 h-2 rounded-full bg-purple-500 inline-block" />Canal HF
                    {hfReady && <CheckCircle2 className="w-3.5 h-3.5 text-emerald-500 ml-auto" />}
                  </p>
                  <canvas ref={hfCanvas} className="w-full rounded-lg bg-surface-900"
                    style={{ aspectRatio: "3/1", imageRendering: "pixelated" }} />
                </div>
              </div>
            )}

            {/* Tab: Google Maps */}
            {tab === "mapa" && (
              <div className="card p-3 space-y-3">
                <Leyenda />
                <div style={{ height: 480 }}>
                  <GoogleMapsViewer
                    gmapsKey={mapsKey}
                    anomalias={anomalias}
                    gpsTrack={gpsTrack}
                  />
                </div>
                {!mapsKey && (
                  <p className="text-xs text-surface-500 text-center">
                    ¿No tienes una Google Maps API Key?
                    Consíguela en <a href="https://console.cloud.google.com/apis/credentials"
                      target="_blank" rel="noopener noreferrer" className="text-brand-600 hover:underline">
                      Google Cloud Console
                    </a> activando la API "Maps JavaScript API".
                  </p>
                )}
              </div>
            )}

            {/* Tab: Tabla de anomalías */}
            {tab === "anomalias" && (
              <div className="card p-4">
                {anomalias.length === 0 ? (
                  <div className="text-center py-10 text-surface-400">
                    <Radar className="w-8 h-8 mx-auto mb-2 opacity-30" />
                    <p className="text-sm">Procesa los archivos para detectar anomalías</p>
                  </div>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full text-xs">
                      <thead>
                        <tr className="border-b border-surface-100 bg-surface-50">
                          {["#", "Tipo", "Dist.(m)", "Prof.(m)", "Ancho(m)", "Alto(m)", "Vol.neto(m³)", "Riesgo", "Conf."].map(h => (
                            <th key={h} className="text-left font-semibold text-surface-400 uppercase py-2 px-3 text-[10px]">{h}</th>
                          ))}
                        </tr>
                      </thead>
                      <tbody>
                        {anomalias.map((a, i) => {
                          const cfg = TIPO_CONFIG[a.type as AnomalyType] || TIPO_CONFIG.anomaly;
                          return (
                            <tr key={i} className="border-b border-surface-50 hover:bg-surface-50">
                              <td className="px-3 py-2">
                                <div className="w-5 h-5 rounded-full flex items-center justify-center text-white font-bold text-[9px]"
                                  style={{ backgroundColor: cfg.color }}>{cfg.letra}{i + 1}</div>
                              </td>
                              <td className="px-3 py-2"><span className={cn("badge text-[9px]", cfg.bg)}>{cfg.label}</span></td>
                              <td className="px-3 py-2 font-mono">{a.distM}</td>
                              <td className="px-3 py-2 font-mono">{a.dM}</td>
                              <td className="px-3 py-2 font-mono">{a.wM}</td>
                              <td className="px-3 py-2 font-mono">{a.hM}</td>
                              <td className="px-3 py-2 font-mono">{a.type === "void" ? a.vNet.toFixed(4) : "—"}</td>
                              <td className="px-3 py-2">
                                <span className={cn("badge text-[9px]",
                                  a.risk === "high" ? "bg-red-100 text-red-700" :
                                  a.risk === "med"  ? "bg-amber-100 text-amber-700" : "bg-blue-100 text-blue-700")}>
                                  {a.risk === "high" ? "ALTO" : a.risk === "med" ? "MEDIO" : "BAJO"}
                                </span>
                              </td>
                              <td className="px-3 py-2 font-mono">{Math.round(a.conf * 100)}%</td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}

            {/* Tab: Informe */}
            {tab === "informe" && (
              <div className="card p-4 space-y-4">
                <div className="flex items-center justify-between">
                  <h2 className="text-sm font-semibold text-surface-800 flex items-center gap-2">
                    <FileText className="w-4 h-4 text-brand-500" />Informe técnico GPR
                  </h2>
                  <button onClick={exportarPDF}
                    className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
                    <Download className="w-3.5 h-3.5" />Exportar PDF
                  </button>
                </div>

                {/* Contenido del informe (también se usa para imprimir) */}
                <div id="georadar-informe" className="space-y-4 text-sm">
                  <h1 className="text-lg font-bold text-brand-600 border-b-2 border-brand-200 pb-2">
                    Informe de Prospección Georradar GPR
                  </h1>

                  <h2 className="text-sm font-semibold text-surface-700 border-l-4 border-brand-500 pl-3">1. Datos generales</h2>
                  <table className="w-full text-xs border-collapse">
                    <tbody>
                      {[
                        ["Proyecto", proyecto || "—"],
                        ["Cliente", cliente || "—"],
                        ["Zona", zona || "—"],
                        ["Operador", operador || "—"],
                        ["Fecha", fecha],
                        ["Material del subsuelo", MATERIALES.find(m => m.value === material)?.label || material],
                        ["Velocidad EM", `${vel} m/ns`],
                        ["Longitud del perfil", `${pw} m`],
                      ].map(([k, v]) => (
                        <tr key={k} className="border-b border-surface-100">
                          <td className="py-1.5 px-2 font-medium text-surface-500 w-40">{k}</td>
                          <td className="py-1.5 px-2 text-surface-800">{v}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>

                  <h2 className="text-sm font-semibold text-surface-700 border-l-4 border-brand-500 pl-3">2. Descripción de la prospección</h2>
                  <p className="text-xs text-surface-600 leading-relaxed">
                    Se ha realizado una prospección GPR mediante el sistema de doble antena (canal LF y HF) sobre el perfil indicado de {pw} m
                    de longitud. El material estimado del subsuelo es {MATERIALES.find(m => m.value === material)?.label?.toLowerCase() || material},
                    con una velocidad electromagnética de {vel} m/ns.
                  </p>

                  <h2 className="text-sm font-semibold text-surface-700 border-l-4 border-brand-500 pl-3">3. Elementos detectados</h2>
                  <div className="grid grid-cols-4 gap-2">
                    {[
                      { tipo: "void" as AnomalyType, count: totalHuecos },
                      { tipo: "supply" as AnomalyType, count: totalSupply },
                      { tipo: "pipe" as AnomalyType, count: totalPipe },
                      { tipo: "anomaly" as AnomalyType, count: totalAnomaly },
                    ].map(({ tipo, count }) => {
                      const cfg = TIPO_CONFIG[tipo];
                      return (
                        <div key={tipo} className="text-center p-3 rounded-lg border border-surface-200">
                          <p className="text-2xl font-bold" style={{ color: cfg.color }}>{count}</p>
                          <p className="text-xs text-surface-500 mt-1">{cfg.label}{count !== 1 ? "s" : ""}</p>
                        </div>
                      );
                    })}
                  </div>

                  <h2 className="text-sm font-semibold text-surface-700 border-l-4 border-brand-500 pl-3">4. Tabla de anomalías</h2>
                  {anomalias.length === 0 ? (
                    <p className="text-xs text-surface-400 italic">No se han detectado anomalías.</p>
                  ) : (
                    <table className="w-full text-xs border-collapse">
                      <thead>
                        <tr className="bg-surface-100">
                          {["ID", "Tipo", "Dist.(m)", "Prof.(m)", "Dim.(m)", "Vol.neto(m³)", "Riesgo", "Confianza"].map(h => (
                            <th key={h} className="text-left font-semibold py-2 px-3 border border-surface-200 text-[10px] uppercase">{h}</th>
                          ))}
                        </tr>
                      </thead>
                      <tbody>
                        {anomalias.map((a, i) => {
                          const cfg = TIPO_CONFIG[a.type as AnomalyType] || TIPO_CONFIG.anomaly;
                          return (
                            <tr key={i} className="border-b border-surface-100">
                              <td className="px-3 py-2 font-bold" style={{ color: cfg.color }}>{cfg.letra}{i + 1}</td>
                              <td className="px-3 py-2">{cfg.label}</td>
                              <td className="px-3 py-2 font-mono">{a.distM}</td>
                              <td className="px-3 py-2 font-mono">{a.dM}</td>
                              <td className="px-3 py-2 font-mono">{a.wM}×{a.hM}</td>
                              <td className="px-3 py-2 font-mono">{a.type === "void" ? a.vNet.toFixed(4) : "—"}</td>
                              <td className="px-3 py-2 font-bold" style={{ color: RISK_COLOR[a.risk] }}>
                                {a.risk === "high" ? "ALTO" : a.risk === "med" ? "MEDIO" : "BAJO"}
                              </td>
                              <td className="px-3 py-2 font-mono">{Math.round(a.conf * 100)}%</td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  )}

                  {analisisIA ? (
                    <>
                      <h2 className="text-sm font-semibold text-surface-700 border-l-4 border-purple-500 pl-3">5. Interpretación técnica IA</h2>
                      <div className="bg-purple-50 border border-purple-200 rounded-xl p-4 max-h-96 overflow-y-auto">
                        <pre className="text-xs text-surface-700 whitespace-pre-wrap font-sans leading-relaxed">{analisisIA}</pre>
                      </div>
                    </>
                  ) : (
                    <div className="bg-surface-50 border border-surface-200 rounded-xl p-4 text-center">
                      <Sparkles className="w-6 h-6 mx-auto mb-2 text-surface-300" />
                      <p className="text-xs text-surface-400">
                        Pulsa <strong>IA</strong> en el panel de carga para generar la interpretación técnica
                      </p>
                    </div>
                  )}

                  <h2 className="text-sm font-semibold text-surface-700 border-l-4 border-brand-500 pl-3">6. Limitaciones del método GPR</h2>
                  <ul className="text-xs text-surface-600 space-y-1 list-disc ml-4">
                    <li>La profundidad de penetración depende del material y la humedad del terreno.</li>
                    <li>Los objetos por encima del rango de resolución (λ/4) pueden no detectarse.</li>
                    <li>La presencia de arcillas o materiales conductivos reduce la penetración de señal.</li>
                    <li>La velocidad electromagnética asumida introduce incertidumbre en la estimación de profundidades (±10-15%).</li>
                    <li>La interpretación IA es orientativa. Debe ser validada por un técnico competente y comprobaciones en campo.</li>
                  </ul>

                  <div className="bg-amber-50 border border-amber-200 rounded-lg p-3 text-[10px] text-amber-800">
                    <strong>AVISO:</strong> Este informe ha sido generado con asistencia de inteligencia artificial.
                    No sustituye la revisión de un técnico titulado ni las comprobaciones en campo.
                    Los volúmenes, profundidades y dimensiones son aproximados y están sujetos a calibración.
                  </div>
                </div>
              </div>
            )}
          </div>
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

Write-Host "  -> src\lib\georadar\detectAnomalies.ts" -ForegroundColor Gray
$dst = "src\lib\georadar\detectAnomalies.ts"
$content = @'
/**
 * src/lib/georadar/detectAnomalies.ts
 *
 * Algoritmo de deteccion de anomalias (huecos/suministros) en datos de
 * georradar. Portado literal desde la app HTML original (funcion detect()),
 * incluyendo los comentarios de calibracion originales -- NO se ha tocado
 * ningun umbral ni constante. El propio codigo original documenta que esta
 * deteccion "v12" fue validada contra un analisis de referencia en Python
 * sobre un SGY real de 17685 trazas / 884.2m, dando ~4.5m3 de volumen
 * bruto. Cualquier cambio de umbral debe re-validarse contra ese mismo caso.
 *
 * Mantiene exactamente el mismo modelo de Sanders, formula de volumen
 * elipsoidal y clasificacion void/supply que la version HTML.
 */

import type { SegyData } from "./parseSegy";

export type MaterialKey = "sf" | "gr" | "cl" | "ro" | "mx";

export interface SandersEntry {
  n: string;
  p: number; // porosidad
  f: number; // factor
  inf: boolean;
  er: number;
}

export const SANDERS: Record<MaterialKey, SandersEntry> = {
  sf: { n: "Arena fina/limo", p: 0.36, f: 0.85, inf: true, er: 4.5 },
  gr: { n: "Grava/cascajo", p: 0.26, f: 0.65, inf: false, er: 5.5 },
  cl: { n: "Arcilla/lutita", p: 0.52, f: 0.15, inf: false, er: 15 },
  ro: { n: "Roca fracturada", p: 0.06, f: 0.4, inf: false, er: 6 },
  mx: { n: "Mixto", p: 0.3, f: 0.65, inf: true, er: 6.5 },
};

export interface GpsPoint {
  lat: number;
  lon: number;
  elev: number;
  dist: number;
  traza?: number;
}

export interface AnomalyResult {
  type: "void" | "supply" | "pipe" | "anomaly";
  subtype?: string;  // metal, pvc, hormigon, cable (para tuberias)
  col: number;
  row: number;
  w: number;
  h: number;
  i: number;
  dM: number;
  wM: number;
  hM: number;
  da: number;
  db: number;
  dc: number;
  vBruto: number;
  vNet: number;
  conf: number;
  distM: number;
  gpt: GpsPoint | null;
  risk: "high" | "med" | "low";
}

export interface LayerResult {
  name: string;
  depth: number;
}

export interface DetectParams {
  vel: number;
  pw: number;
  pl: number;
  material: MaterialKey;
  gps: GpsPoint[];
}

function maxDepth(rd: SegyData, vel: number): number {
  return (vel * rd.dtNs * rd.ROWS) / 2;
}

function closestGPS(gps: GpsPoint[], distM: number): GpsPoint | null {
  if (!gps.length) return null;
  return gps.reduce((b, p) => (Math.abs(p.dist - distM) < Math.abs(b.dist - distM) ? p : b), gps[0]);
}

export function calcVol(wM: number, hM: number, pl: number): { vol: number; a: number; b: number; c: number } {
  const a = wM / 2;
  const b = hM / 2;
  const c = Math.min(wM * 0.8, pl) / 2;
  return { vol: (4 / 3) * Math.PI * a * b * c, a, b, c };
}

export function riskLvl(volBruto: number, dep: number): "high" | "med" | "low" {
  if (volBruto > 0.25 || dep < 0.2) return "high";
  if (volBruto > 0.025 || dep < 0.7) return "med";
  return "low";
}

export function detectAnomalies(
  rd: SegyData,
  params: DetectParams
): { anoms: AnomalyResult[]; layers: LayerResult[] } {
  const { data, COLS, ROWS } = rd;
  const md = maxDepth(rd, params.vel);
  const dx = params.pw / COLS;
  const snd = SANDERS[params.material] || SANDERS.gr;

  let anoms: AnomalyResult[];

  if (rd.anomDefs) {
    anoms = rd.anomDefs.map((a, i) => {
      const dM = (a.row / ROWS) * md;
      const wM = a.w * dx;
      const hM = (a.h / ROWS) * md;
      const { vol, a: da, b: db, c: dc } = calcVol(wM, hM, params.pl);
      const vNet = vol * snd.f + (snd.inf ? vol * snd.p * 0.2 : 0);
      const distM = (a.col / COLS) * params.pw;
      const gpt = closestGPS(params.gps, distM);
      return {
        type: a.type,
        col: a.col,
        row: a.row,
        w: a.w,
        h: a.h,
        i,
        dM: +dM.toFixed(3),
        wM: +wM.toFixed(3),
        hM: +hM.toFixed(3),
        da,
        db,
        dc,
        vBruto: +vol.toFixed(6),
        vNet: +(a.type === "void" ? vNet : 0).toFixed(6),
        conf: +(0.72 + Math.random() * 0.22).toFixed(3),
        distM: +distM.toFixed(1),
        gpt,
        risk: riskLvl(vol, dM),
      };
    });
  } else {
    // ==========================================================
    // DETECCION PROFESIONAL v12 -- validada contra analisis Python
    // SGY real (17685 trazas, 884.2m): resultado ~4.5m3 bruto
    // BW=8: resolucion 4x, umbral adaptativo 3.5 sigma
    // Filtros fisicos eliminan capas y artefactos
    // Supply: solo si wM < 0.5m Y hM > wM en metros fisicos
    // (DX=0.4m/bloque vs DZ=0.044m/bloque -- NO comparar en bloques)
    // ==========================================================
    const BW = 8;
    const BH = 8;
    const GC = Math.floor(COLS / BW);
    const GR2 = Math.floor(ROWS / BH);
    const DZ_m = md / ROWS;
    const DX_blk = BW * dx;
    const DZ_blk = BH * DZ_m;

    const eng = new Float32Array(GR2 * GC);
    for (let gr = 0; gr < GR2; gr++) {
      for (let gc = 0; gc < GC; gc++) {
        let e = 0;
        let n = 0;
        for (let r = gr * BH; r < Math.min((gr + 1) * BH, ROWS); r++) {
          for (let c = gc * BW; c < Math.min((gc + 1) * BW, COLS); c++) {
            const v2 = data[r * COLS + c];
            e += v2 * v2;
            n++;
          }
        }
        eng[gr * GC + gc] = n ? Math.sqrt(e / n) : 0;
      }
    }

    const bg = new Float32Array(GR2);
    for (let gr = 0; gr < GR2; gr++) {
      let s = 0;
      for (let gc = 0; gc < GC; gc++) s += eng[gr * GC + gc];
      bg[gr] = s / GC;
    }
    const norm = eng.map((v2, i2) => v2 / (bg[Math.floor(i2 / GC)] || 1));

    let nSum = 0;
    let nSum2 = 0;
    for (let i2 = 0; i2 < norm.length; i2++) {
      nSum += norm[i2];
      nSum2 += norm[i2] * norm[i2];
    }
    const nMean = nSum / norm.length;
    const nStd = Math.sqrt(Math.max(0, nSum2 / norm.length - nMean * nMean));
    const THR_E = nMean + 3.5 * nStd;
    const THR_G = nMean + 2.2 * nStd;

    const GR_SKIP = Math.max(2, Math.round(0.08 / DZ_blk));
    const vis = new Uint8Array(GR2 * GC);
    const blobs: { r0: number; r1: number; c0: number; c1: number; eS: number; wM_b: number; hM_b: number }[] = [];

    for (let gr = GR_SKIP; gr < GR2 - 1; gr++) {
      for (let gc = 0; gc < GC; gc++) {
        if (vis[gr * GC + gc] || norm[gr * GC + gc] < THR_E) continue;
        const q: [number, number][] = [[gr, gc]];
        vis[gr * GC + gc] = 1;
        let r0 = gr,
          r1 = gr,
          c0 = gc,
          c1 = gc,
          eS = 0;
        while (q.length) {
          const [cr, cc] = q.pop()!;
          eS += norm[cr * GC + cc];
          for (const [dr, dc2] of [[-1, 0], [1, 0], [0, -1], [0, 1]] as const) {
            const nr = cr + dr;
            const nc = cc + dc2;
            if (nr < GR_SKIP || nr >= GR2 || nc < 0 || nc >= GC || vis[nr * GC + nc]) continue;
            if (norm[nr * GC + nc] > THR_G) {
              vis[nr * GC + nc] = 1;
              q.push([nr, nc]);
              r0 = Math.min(r0, nr);
              r1 = Math.max(r1, nr);
              c0 = Math.min(c0, nc);
              c1 = Math.max(c1, nc);
            }
          }
        }
        const wM_b = (c1 - c0 + 1) * DX_blk;
        const hM_b = (r1 - r0 + 1) * DZ_blk;
        if (wM_b < 0.2) continue;
        if (hM_b < 0.015) continue;
        if (wM_b > 10.0) continue;
        if (hM_b > 0.6) continue;
        if (wM_b / Math.max(hM_b, 0.001) > 25) continue;
        blobs.push({ r0, r1, c0, c1, eS, wM_b, hM_b });
      }
    }

    blobs.sort((a2, b2) => b2.eS - a2.eS);

    const MIN_SEP = 3;
    const kept: typeof blobs = [];
    for (const b2 of blobs) {
      const cx = (b2.c0 + b2.c1) / 2;
      const cy = (b2.r0 + b2.r1) / 2;
      let dup = false;
      for (const k of kept) {
        if (Math.abs(cx - (k.c0 + k.c1) / 2) < MIN_SEP && Math.abs(cy - (k.r0 + k.r1) / 2) < MIN_SEP) {
          dup = true;
          break;
        }
      }
      if (!dup) kept.push(b2);
    }

    anoms = kept.slice(0, 80).map((b2, i) => {
      const cC = Math.round(((b2.c0 + b2.c1) / 2) * BW + BW / 2);
      const cR = Math.round(((b2.r0 + b2.r1) / 2) * BH + BH / 2);
      const wPx = (b2.c1 - b2.c0 + 1) * BW;
      const hPx = (b2.r1 - b2.r0 + 1) * BH;
      const dM = (cR / ROWS) * md;
      const wM = wPx * dx;
      const hM = (hPx / ROWS) * md;
      const type: "void" | "supply" = wM < 0.5 && hM > wM * 0.8 ? "supply" : "void";
      const { vol, a: da, b: db, c: dc } = calcVol(wM, hM, params.pl);
      const vNet = vol * snd.f + (snd.inf ? vol * snd.p * 0.2 : 0);
      const distM = (cC / COLS) * params.pw;
      const gpt = closestGPS(params.gps, distM);
      return {
        type,
        col: cC,
        row: cR,
        w: wPx,
        h: hPx,
        i,
        dM: +dM.toFixed(3),
        wM: +wM.toFixed(3),
        hM: +hM.toFixed(3),
        da,
        db,
        dc,
        vBruto: +vol.toFixed(6),
        vNet: +(type === "void" ? vNet : 0).toFixed(6),
        conf: +Math.min(0.95, 0.5 + b2.eS * 0.003).toFixed(3),
        distM: +distM.toFixed(1),
        gpt,
        risk: riskLvl(vol, dM),
      };
    });
  }

  const layerDefs = rd.layerDefs || [0.1, 0.22, 0.4, 0.58, 0.75].map((f) => ({ r: Math.round(rd.ROWS * f) }));
  const layerNames = ["Pavimento/base", "Zona no saturada", "Transicion", "Nivel freatico", "Roca/substrato"];
  const layers: LayerResult[] = layerDefs.map((l, i) => ({
    name: layerNames[i] || "Capa " + (i + 1),
    depth: +((l.r / rd.ROWS) * md).toFixed(3),
  }));

  return { anoms, layers };
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

Write-Host "  -> src\components\layout\Sidebar.tsx" -ForegroundColor Gray
$dst = "src\components\layout\Sidebar.tsx"
$content = @'
"use client";

import { usePathname } from "next/navigation";
import Link from "next/link";
import Image from "next/image";
import {
  LayoutDashboard, CalendarRange, Building2, ClipboardList,
  Users, Truck, Package, Contact, Settings,
  ScrollText, ChevronLeft, ChevronRight,
  Tag, Hammer, X, LayoutGrid, Radar, Warehouse, Users2, ArrowLeftRight,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { useAuthStore } from "@/hooks/useAuth";
import { useLayoutStore } from "@/hooks/useLayout";
import { usePermissions } from "@/hooks/usePermissions";

const navigation = [
  { name: "Dashboard", href: "/dashboard", icon: LayoutDashboard, screen: "dashboard" },
  { name: "Planificación", href: "/planificacion", icon: CalendarRange, screen: "planificacion" },
  { name: "Obras", href: "/obras", icon: Building2, screen: "obras" },
  { name: "Partes Diarios", href: "/partes", icon: ClipboardList, screen: "partes" },
];

// Catálogo de apps internas del módulo "Aplicaciones". Añadir una app
// nueva en el futuro es tan simple como añadir una entrada aquí (con su
// propio `screen` dado de alta en rol_permisos) -- no requiere tocar
// ninguna otra parte del Sidebar ni del sistema de permisos.
const aplicaciones = [
  { name: "Interpretación de Georradar", href: "/aplicaciones/georadar", icon: Radar, screen: "apps_georadar" },
  { name: "Georadar V2", href: "/aplicaciones/georadar-v2", icon: Radar, screen: "apps_georadar_v2" },
];

const almacen = [
  { name: "Artículos", href: "/almacen/articulos", icon: Package, screen: "almacen_articulos" },
  { name: "Tipos de artículo", href: "/almacen/tipos-articulo", icon: Tag, screen: "almacen_tipos_articulo" },
  { name: "Almacenes", href: "/almacen/almacenes", icon: Warehouse, screen: "almacen_almacenes" },
  { name: "Proveedores", href: "/almacen/proveedores", icon: Users2, screen: "almacen_proveedores" },
  { name: "Movimientos", href: "/almacen/movimientos", icon: ArrowLeftRight, screen: "almacen_movimientos" },
  { name: "Etiquetas", href: "/almacen/etiquetas", icon: Tag, screen: "almacen_etiquetas" },
];

const maestros = [
  { name: "Recursos Humanos", href: "/maestros/recursos-humanos", icon: Users, screen: "maestros_rrhh" },
  { name: "Vehículos", href: "/maestros/vehiculos", icon: Truck, screen: "maestros_vehiculos" },
  { name: "Clientes", href: "/maestros/clientes", icon: Contact, screen: "maestros_clientes" },
  { name: "Estados de Obra", href: "/maestros/estados-obra", icon: Tag, screen: "maestros_estados" },
  { name: "Tipos de Trabajo", href: "/maestros/tipos-trabajo", icon: Hammer, screen: "maestros_tipos_trabajo" },
  { name: "Tipos de Obra", href: "/maestros/tipos-obra", icon: Building2, screen: "maestros_tipos_obra" },
  { name: "Contactos LEYNA", href: "/maestros/contactos-leyna", icon: Users2, screen: "maestros_contactos_leyna" },
];

const admin = [
  { name: "Logs", href: "/logs", icon: ScrollText, screen: "logs" },
  { name: "Configuración", href: "/configuracion", icon: Settings, screen: "configuracion" },
];

export default function Sidebar() {
  const pathname = usePathname();
  const { user } = useAuthStore();
  const { sidebarCollapsed: collapsed, toggleSidebar, mobileMenuOpen, setMobileMenu } = useLayoutStore();
  const { isAdmin, visibleScreens } = usePermissions();
  const screens = visibleScreens();

  const isActive = (href: string) => {
    if (href === "/dashboard") return pathname === "/dashboard";
    return pathname.startsWith(href);
  };

  const NavItem = ({ item }: { item: (typeof navigation)[0] }) => (
    <Link href={item.href} onClick={() => setMobileMenu(false)}
      className={cn("nav-link group", isActive(item.href) && "active")} title={collapsed ? item.name : undefined}>
      <item.icon className={cn("w-5 h-5 shrink-0 transition-colors", isActive(item.href) ? "text-brand-600" : "text-surface-400 group-hover:text-surface-600")} />
      {(!collapsed || mobileMenuOpen) && <span className="truncate">{item.name}</span>}
    </Link>
  );

  // Filter items by permission
  const visibleNav = navigation.filter((item) => screens.has(item.screen));
  const visibleApps = aplicaciones.filter((item) => screens.has(item.screen));
  const visibleAlmacen = almacen.filter((item) => screens.has(item.screen));
  const visibleMaestros = maestros.filter((item) => screens.has(item.screen));
  const visibleAdmin = admin.filter((item) => screens.has(item.screen));

  const sidebarContent = (
    <>
      {/* Logo only */}
      <div className="flex items-center justify-between px-4 h-16 border-b border-surface-200 shrink-0">
        <Link href="/dashboard" className="flex items-center justify-center w-full">
          <div className={cn("relative shrink-0", collapsed && !mobileMenuOpen ? "w-10 h-10" : "w-36 h-12")}>
            <Image src="/logo-loynek.png" alt="Loynek" fill className="object-contain" />
          </div>
        </Link>
        {mobileMenuOpen && (
          <button onClick={() => setMobileMenu(false)} className="p-1 rounded-lg text-surface-400 hover:bg-surface-100 lg:hidden absolute right-3">
            <X className="w-5 h-5" />
          </button>
        )}
      </div>

      {/* Navigation */}
      <nav className="flex-1 overflow-y-auto px-3 py-4 space-y-6">
        {visibleNav.length > 0 && (
          <div className="space-y-1">
            {(!collapsed || mobileMenuOpen) && <p className="px-3 mb-2 text-[11px] font-semibold text-surface-400 uppercase tracking-wider">Principal</p>}
            {visibleNav.map((item) => <NavItem key={item.href} item={item} />)}
          </div>
        )}
        {visibleApps.length > 0 && (
          <div className="space-y-1">
            {(!collapsed || mobileMenuOpen) && <p className="px-3 mb-2 text-[11px] font-semibold text-surface-400 uppercase tracking-wider">Aplicaciones</p>}
            {visibleApps.map((item) => <NavItem key={item.href} item={item} />)}
          </div>
        )}
        {visibleAlmacen.length > 0 && (
          <div className="space-y-1">
            {(!collapsed || mobileMenuOpen) && <p className="px-3 mb-2 text-[11px] font-semibold text-surface-400 uppercase tracking-wider">Almacén</p>}
            {visibleAlmacen.map((item) => <NavItem key={item.href} item={item} />)}
          </div>
        )}
        {visibleMaestros.length > 0 && (
          <div className="space-y-1">
            {(!collapsed || mobileMenuOpen) && <p className="px-3 mb-2 text-[11px] font-semibold text-surface-400 uppercase tracking-wider">Maestros</p>}
            {visibleMaestros.map((item) => <NavItem key={item.href} item={item} />)}
          </div>
        )}
        {visibleAdmin.length > 0 && (
          <div className="space-y-1">
            {(!collapsed || mobileMenuOpen) && <p className="px-3 mb-2 text-[11px] font-semibold text-surface-400 uppercase tracking-wider">Administración</p>}
            {visibleAdmin.map((item) => <NavItem key={item.href} item={item} />)}
          </div>
        )}
      </nav>

      {/* Collapse button - desktop only */}
      <div className="hidden lg:block px-3 py-3 border-t border-surface-200 shrink-0">
        <button onClick={() => toggleSidebar()}
          className="w-full flex items-center justify-center gap-2 px-3 py-2 rounded-lg text-sm text-surface-400 hover:bg-surface-100 hover:text-surface-600 transition-colors">
          {collapsed ? <ChevronRight className="w-4 h-4" /> : <><ChevronLeft className="w-4 h-4" /><span>Colapsar</span></>}
        </button>
      </div>
    </>
  );

  return (
    <>
      <aside className={cn(
        "hidden lg:flex fixed left-0 top-0 z-40 h-screen bg-white border-r border-surface-200 flex-col transition-all duration-300",
        collapsed ? "w-[72px]" : "w-[260px]"
      )}>
        {sidebarContent}
      </aside>

      {mobileMenuOpen && (
        <div className="lg:hidden fixed inset-0 z-50">
          <div className="absolute inset-0 bg-black/50" onClick={() => setMobileMenu(false)} />
          <aside className="absolute left-0 top-0 h-full w-[280px] bg-white flex flex-col shadow-xl animate-slide-in">
            {sidebarContent}
          </aside>
        </div>
      )}
    </>
  );
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

Write-Host "  -> src\app\configuracion\page.tsx" -ForegroundColor Gray
$dst = "src\app\configuracion\page.tsx"
$content = @'
"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { Settings, Loader2, Save, ShieldCheck, Check, X, Plus, Pencil, Trash2, Mail } from "lucide-react";
import { cn } from "@/lib/utils/cn";

type ConfigTab = "roles" | "partes" | "almacen" | "general";

const PANTALLAS = [
  { id: "dashboard", label: "Dashboard" },
  { id: "planificacion", label: "Planificación" },
  { id: "obras", label: "Obras" },
  { id: "partes", label: "Partes" },
  { id: "almacen_articulos", label: "Almacén - Artículos" },
  { id: "almacen_tipos_articulo", label: "Almacén - Tipos de artículo" },
  { id: "almacen_almacenes", label: "Almacén - Almacenes" },
  { id: "almacen_proveedores", label: "Almacén - Proveedores" },
  { id: "almacen_movimientos", label: "Almacén - Movimientos" },
  { id: "almacen_etiquetas", label: "Almacén - Diseñador de etiquetas" },
  { id: "maestros_rrhh", label: "RRHH" },
  { id: "maestros_vehiculos", label: "Vehículos" },
  { id: "maestros_clientes", label: "Clientes" },
  { id: "maestros_estados", label: "Estados obra" },
  { id: "maestros_tipos_trabajo", label: "Tipos trabajo" },
  { id: "maestros_tipos_obra", label: "Tipos de obra" },
  { id: "maestros_contactos_leyna", label: "Contactos LEYNA" },
  { id: "almacen_etiquetas", label: "Almacén - Etiquetas" },
  { id: "apps_georadar", label: "Georadar" },
  { id: "apps_georadar_v2", label: "Georadar V2" },
  { id: "logs", label: "Logs" },
  { id: "configuracion", label: "Configuración" },
];

const PERMISOS = ["visible", "crear", "editar", "eliminar", "asignar"] as const;
const PERMISO_LABELS: Record<string, string> = { visible: "Ver", crear: "Crear", editar: "Editar", eliminar: "Eliminar", asignar: "Asignar" };

interface RolData {
  id: string;
  nombre: string;
  descripcion: string;
  is_admin: boolean;
  permisos: Record<string, Record<string, boolean>>;
}

export default function ConfiguracionPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const [tab, setTab] = useState<ConfigTab>("roles");
  const [roles, setRoles] = useState<RolData[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedRol, setSelectedRol] = useState<string>("");
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  // Create/edit modal
  const [rolModal, setRolModal] = useState(false);
  const [rolForm, setRolForm] = useState({ nombre: "", descripcion: "", is_admin: false });
  const [editingRolId, setEditingRolId] = useState<string | null>(null);
  const [rolSaving, setRolSaving] = useState(false);
  // Partes config
  const [partesConfig, setPartesConfig] = useState({ cc_emails: [] as string[], empresa_nombre: "LOYNEK Soluciones Técnicas", footer_text: "Este email ha sido enviado automáticamente desde ObrasPlan", color_primario: "#DC2626" });
  const [newCcEmail, setNewCcEmail] = useState("");
  const [partesSaving, setPartesSaving] = useState(false);
  const [partesSaved, setPartesSaved] = useState(false);
  const [almacenConfig, setAlmacenConfig] = useState({ emails: [] as string[], activo: true, asunto: "Alertas de almacen - ObrasPlan", dias_aviso_caducidad: 30 });
  const [newAlmacenEmail, setNewAlmacenEmail] = useState("");
  const [almacenSaving, setAlmacenSaving] = useState(false);
  const [almacenSaved, setAlmacenSaved] = useState(false);
  const [almacenTestSending, setAlmacenTestSending] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [rolesR, permR] = await Promise.all([
      supabase.from("roles").select("*").order("is_admin", { ascending: false }).order("nombre"),
      supabase.from("rol_permisos").select("*"),
    ]);
    const rolesData = (rolesR.data || []) as any[];
    const permsData = (permR.data || []) as any[];

    const result: RolData[] = rolesData.map((r: any) => {
      const permisos: Record<string, Record<string, boolean>> = {};
      PANTALLAS.forEach((p) => {
        const existing = permsData.find((perm: any) => perm.rol_id === r.id && perm.pantalla === p.id);
        permisos[p.id] = {
          visible: existing?.visible ?? r.is_admin,
          crear: existing?.crear ?? r.is_admin,
          editar: existing?.editar ?? r.is_admin,
          eliminar: existing?.eliminar ?? r.is_admin,
          asignar: existing?.asignar ?? r.is_admin,
        };
      });
      return { id: r.id, nombre: r.nombre, descripcion: r.descripcion || "", is_admin: r.is_admin, permisos };
    });

    setRoles(result);
    if (result.length > 0 && !selectedRol) setSelectedRol(result[0].id);
    // Fetch partes config
    const { data: settingsData } = await supabase.from("app_settings").select("*").eq("key", "partes_email").single();
    const { data: almacenSettingsData } = await (supabase.from("app_settings") as any).select("*").eq("key", "almacen_alertas").single();
    if (almacenSettingsData?.value) setAlmacenConfig((prev) => ({ ...prev, ...almacenSettingsData.value }));
    if (settingsData?.value) setPartesConfig({ ...partesConfig, ...settingsData.value });
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const togglePerm = (rolId: string, pantalla: string, permiso: string) => {
    setRoles((prev) => prev.map((r) => {
      if (r.id !== rolId || r.is_admin) return r;
      return { ...r, permisos: { ...r.permisos, [pantalla]: { ...r.permisos[pantalla], [permiso]: !r.permisos[pantalla][permiso] } } };
    }));
    setSaved(false);
  };

  const toggleAll = (rolId: string, value: boolean) => {
    setRoles((prev) => prev.map((r) => {
      if (r.id !== rolId || r.is_admin) return r;
      const permisos: Record<string, Record<string, boolean>> = {};
      PANTALLAS.forEach((p) => { permisos[p.id] = {}; PERMISOS.forEach((perm) => { permisos[p.id][perm] = value; }); });
      return { ...r, permisos };
    }));
    setSaved(false);
  };

  const handleSavePermisos = async () => {
    setSaving(true);
    const rol = roles.find((r) => r.id === selectedRol);
    if (!rol || rol.is_admin) { setSaving(false); return; }

    for (const pantalla of PANTALLAS) {
      const perms = rol.permisos[pantalla.id];
      await (supabase.from("rol_permisos") as any).upsert({
        rol_id: rol.id, pantalla: pantalla.id,
        visible: perms.visible ?? false, crear: perms.crear ?? false,
        editar: perms.editar ?? false, eliminar: perms.eliminar ?? false,
        asignar: perms.asignar ?? false,
      }, { onConflict: "rol_id,pantalla" });
    }
    setSaving(false); setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  const handleCreateRol = async (e: React.FormEvent) => {
    e.preventDefault(); setRolSaving(true);
    if (editingRolId) {
      await (supabase.from("roles") as any).update({ nombre: rolForm.nombre, descripcion: rolForm.descripcion }).eq("id", editingRolId);
    } else {
      await (supabase.from("roles") as any).insert({ nombre: rolForm.nombre, descripcion: rolForm.descripcion, is_admin: false });
    }
    setRolSaving(false); setRolModal(false); fetchData();
  };

  const handleDeleteRol = async (rolId: string) => {
    const rol = roles.find((r) => r.id === rolId);
    if (rol?.is_admin) return;
    if (!confirm(`¿Eliminar el rol "${rol?.nombre}"? Los usuarios con este rol quedarán sin rol asignado.`)) return;
    await (supabase.from("roles") as any).delete().eq("id", rolId);
    if (selectedRol === rolId) setSelectedRol("");
    fetchData();
  };

  if (user && user.role !== "admin") {
    return <AppLayout><div className="text-center py-20"><ShieldCheck className="w-10 h-10 text-surface-300 mx-auto mb-3" /><p className="text-sm text-surface-500">Solo administradores</p></div></AppLayout>;
  }

  const selectedRolData = roles.find((r) => r.id === selectedRol);
  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  return (
    <AppLayout>
      <div className="max-w-6xl mx-auto animate-fade-in">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-lg bg-surface-100 flex items-center justify-center"><Settings className="w-5 h-5 text-surface-600" /></div>
          <div><h1 className="text-xl font-display font-bold text-surface-900">Configuración</h1><p className="text-sm text-surface-500">Roles, permisos y ajustes</p></div>
        </div>

        {/* Tabs */}
        <div className="flex gap-1 mb-6 border-b border-surface-200">
          {[{ id: "roles" as ConfigTab, label: "Roles y permisos" }, { id: "partes" as ConfigTab, label: "Partes / Email" }, { id: "almacen" as ConfigTab, label: "Almacén" }, { id: "general" as ConfigTab, label: "General" }].map((t) => (
            <button key={t.id} onClick={() => setTab(t.id)}
              className={cn("px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-all",
                tab === t.id ? "border-brand-500 text-brand-600" : "border-transparent text-surface-500")}>
              {t.label}
            </button>
          ))}
        </div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div> : (
          <>
            {/* ROLES TAB */}
            {tab === "roles" && (
              <div className="space-y-4">
                {/* Rol selector + actions */}
                <div className="card p-4">
                  <div className="flex items-center justify-between flex-wrap gap-3">
                    <div className="flex items-center gap-3">
                      <label className="text-sm font-medium text-surface-700">Rol:</label>
                      <select value={selectedRol} onChange={(e) => { setSelectedRol(e.target.value); setSaved(false); }}
                        className="px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20 min-w-[200px]">
                        {roles.map((r) => <option key={r.id} value={r.id}>{r.nombre}{r.is_admin ? " (Admin)" : ""}</option>)}
                      </select>
                      {selectedRolData && !selectedRolData.is_admin && (
                        <>
                          <button onClick={() => { setRolForm({ nombre: selectedRolData.nombre, descripcion: selectedRolData.descripcion, is_admin: false }); setEditingRolId(selectedRolData.id); setRolModal(true); }}
                            className="p-2 rounded-lg text-surface-400 hover:bg-surface-100 hover:text-surface-600"><Pencil className="w-4 h-4" /></button>
                          <button onClick={() => handleDeleteRol(selectedRolData.id)}
                            className="p-2 rounded-lg text-surface-400 hover:bg-red-50 hover:text-red-500"><Trash2 className="w-4 h-4" /></button>
                        </>
                      )}
                    </div>
                    <div className="flex items-center gap-2">
                      <button onClick={() => { setRolForm({ nombre: "", descripcion: "", is_admin: false }); setEditingRolId(null); setRolModal(true); }}
                        className="flex items-center gap-1.5 px-3 py-2 text-sm font-medium text-brand-600 bg-brand-50 rounded-lg hover:bg-brand-100">
                        <Plus className="w-4 h-4" /> Nuevo rol
                      </button>
                      {selectedRolData && !selectedRolData.is_admin && (
                        <>
                          <button onClick={() => toggleAll(selectedRol, true)} className="px-3 py-1.5 text-xs font-medium text-emerald-700 bg-emerald-50 rounded-lg hover:bg-emerald-100">Todo</button>
                          <button onClick={() => toggleAll(selectedRol, false)} className="px-3 py-1.5 text-xs font-medium text-red-700 bg-red-50 rounded-lg hover:bg-red-100">Nada</button>
                          <button onClick={handleSavePermisos} disabled={saving}
                            className={cn("flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg",
                              saved ? "text-emerald-700 bg-emerald-100" : "text-white bg-brand-500 hover:bg-brand-600 disabled:opacity-60")}>
                            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : saved ? <Check className="w-4 h-4" /> : <Save className="w-4 h-4" />}
                            {saved ? "Guardado" : "Guardar"}
                          </button>
                        </>
                      )}
                    </div>
                  </div>
                  {selectedRolData?.descripcion && <p className="text-xs text-surface-400 mt-2">{selectedRolData.descripcion}</p>}
                </div>

                {/* Permissions table */}
                {selectedRolData && (
                  <div className="card overflow-hidden">
                    {selectedRolData.is_admin ? (
                      <div className="p-8 text-center"><ShieldCheck className="w-8 h-8 text-emerald-500 mx-auto mb-2" /><p className="text-sm text-surface-600">El rol Administrador tiene acceso total. No se puede modificar.</p></div>
                    ) : (
                      <table className="w-full text-sm">
                        <thead>
                          <tr className="bg-surface-50 border-b border-surface-200">
                            <th className="text-left py-3 px-4 text-[10px] font-semibold text-surface-400 uppercase w-[180px]">Menú / Pantalla</th>
                            {PERMISOS.map((p) => (
                              <th key={p} className="text-center py-3 px-3 text-[10px] font-semibold text-surface-400 uppercase">{PERMISO_LABELS[p]}</th>
                            ))}
                          </tr>
                        </thead>
                        <tbody>
                          {PANTALLAS.map((pantalla) => (
                            <tr key={pantalla.id} className="border-b border-surface-50 hover:bg-surface-50/50">
                              <td className="py-3 px-4 font-medium text-surface-900">{pantalla.label}</td>
                              {PERMISOS.map((perm) => {
                                const checked = selectedRolData.permisos[pantalla.id]?.[perm] ?? false;
                                return (
                                  <td key={perm} className="text-center py-3 px-3">
                                    <button onClick={() => togglePerm(selectedRolData.id, pantalla.id, perm)}
                                      className={cn("w-8 h-8 rounded-lg flex items-center justify-center mx-auto transition-all",
                                        checked ? "bg-emerald-100 text-emerald-600 hover:bg-emerald-200" : "bg-red-50 text-red-400 hover:bg-red-100")}>
                                      {checked ? <Check className="w-4 h-4" /> : <X className="w-4 h-4" />}
                                    </button>
                                  </td>
                                );
                              })}
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    )}
                  </div>
                )}
              </div>
            )}

            {/* PARTES TAB */}
            {tab === "partes" && (
              <div className="space-y-6">
                <div className="card p-6 space-y-4">
                  <h2 className="text-sm font-semibold text-surface-900">Emails en copia (CC)</h2>
                  <p className="text-xs text-surface-400">Estas direcciones recibirán una copia de todos los partes que se envíen por email.</p>
                  <div className="flex flex-wrap gap-2">
                    {partesConfig.cc_emails.map((email, i) => (
                      <span key={i} className="flex items-center gap-1 px-3 py-1.5 bg-blue-50 text-blue-700 rounded-full text-xs font-medium border border-blue-200">
                        {email}
                        <button onClick={() => setPartesConfig({ ...partesConfig, cc_emails: partesConfig.cc_emails.filter((_, j) => j !== i) })} className="ml-1 hover:text-red-500"><X className="w-3 h-3" /></button>
                      </span>
                    ))}
                  </div>
                  <div className="flex gap-2">
                    <input type="email" value={newCcEmail} onChange={(e) => setNewCcEmail(e.target.value)} placeholder="email@ejemplo.com" onKeyDown={(e) => { if (e.key === "Enter" && newCcEmail.includes("@")) { e.preventDefault(); setPartesConfig({ ...partesConfig, cc_emails: [...partesConfig.cc_emails, newCcEmail] }); setNewCcEmail(""); } }}
                      className="flex-1 px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500" />
                    <button onClick={() => { if (newCcEmail.includes("@")) { setPartesConfig({ ...partesConfig, cc_emails: [...partesConfig.cc_emails, newCcEmail] }); setNewCcEmail(""); } }}
                      className="flex items-center gap-1 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-4 h-4" />Añadir</button>
                  </div>
                </div>

                <div className="card p-6 space-y-4">
                  <h2 className="text-sm font-semibold text-surface-900">Diseño del email y PDF</h2>
                  <div className="grid grid-cols-2 gap-4">
                    <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre de empresa</label><input type="text" value={partesConfig.empresa_nombre} onChange={(e) => setPartesConfig({ ...partesConfig, empresa_nombre: e.target.value })} className="w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500" /></div>
                    <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Color primario</label>
                      <div className="flex items-center gap-2">
                        <input type="color" value={partesConfig.color_primario} onChange={(e) => setPartesConfig({ ...partesConfig, color_primario: e.target.value })} className="w-10 h-10 rounded cursor-pointer border border-surface-200" />
                        <input type="text" value={partesConfig.color_primario} onChange={(e) => setPartesConfig({ ...partesConfig, color_primario: e.target.value })} className="flex-1 px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500/20 font-mono" />
                      </div>
                    </div>
                  </div>
                  <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Texto del footer</label><input type="text" value={partesConfig.footer_text} onChange={(e) => setPartesConfig({ ...partesConfig, footer_text: e.target.value })} className="w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500" /></div>
                </div>

                <div className="flex justify-end">
                  <button onClick={async () => {
                    setPartesSaving(true);
                    await (supabase.from("app_settings") as any).upsert({ key: "partes_email", value: partesConfig, updated_at: new Date().toISOString() }, { onConflict: "key" });
                    setPartesSaving(false); setPartesSaved(true); setTimeout(() => setPartesSaved(false), 2000);
                  }} disabled={partesSaving}
                    className={cn("flex items-center gap-1.5 px-5 py-2.5 text-sm font-medium rounded-lg",
                      partesSaved ? "text-emerald-700 bg-emerald-100" : "text-white bg-brand-500 hover:bg-brand-600 disabled:opacity-60")}>
                    {partesSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : partesSaved ? <Check className="w-4 h-4" /> : <Save className="w-4 h-4" />}
                    {partesSaved ? "Guardado" : "Guardar configuración"}
                  </button>
                </div>
              </div>
            )}

            {/* ALMACEN TAB */}
            {tab === "almacen" && (
              <div className="space-y-6">
                <div className="card p-6 space-y-4">
                  <h2 className="text-sm font-semibold text-surface-900">Emails para alertas de almacen</h2>
                  <p className="text-xs text-surface-400">Estas direcciones recibiran alertas de stock bajo y caducidades proximas.</p>
                  <div className="flex flex-wrap gap-2">
                    {almacenConfig.emails.map((email, i) => (
                      <span key={i} className="flex items-center gap-1 px-3 py-1.5 bg-amber-50 text-amber-700 rounded-full text-xs font-medium border border-amber-200">
                        {email}
                        <button onClick={() => setAlmacenConfig({ ...almacenConfig, emails: almacenConfig.emails.filter((_, j) => j !== i) })} className="ml-1 hover:text-red-500"><X className="w-3 h-3" /></button>
                      </span>
                    ))}
                  </div>
                  <div className="flex gap-2">
                    <input type="email" value={newAlmacenEmail} onChange={(e) => setNewAlmacenEmail(e.target.value)}
                      placeholder="email@ejemplo.com"
                      onKeyDown={(e) => { if (e.key === "Enter" && newAlmacenEmail.includes("@")) { e.preventDefault(); setAlmacenConfig({ ...almacenConfig, emails: [...almacenConfig.emails, newAlmacenEmail] }); setNewAlmacenEmail(""); } }}
                      className="flex-1 px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500/20" />
                    <button onClick={() => { if (newAlmacenEmail.includes("@")) { setAlmacenConfig({ ...almacenConfig, emails: [...almacenConfig.emails, newAlmacenEmail] }); setNewAlmacenEmail(""); } }}
                      className="flex items-center gap-1 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-4 h-4" />Añadir</button>
                  </div>
                </div>
                <div className="card p-6 space-y-4">
                  <h2 className="text-sm font-semibold text-surface-900">Configuracion del email</h2>
                  <div className="grid grid-cols-2 gap-4">
                    <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Asunto del email</label>
                      <input type="text" value={almacenConfig.asunto} onChange={(e) => setAlmacenConfig({ ...almacenConfig, asunto: e.target.value })} className={ic} />
                    </div>
                    <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Dias de aviso antes de caducidad</label>
                      <input type="number" min="1" max="365" value={almacenConfig.dias_aviso_caducidad} onChange={(e) => setAlmacenConfig({ ...almacenConfig, dias_aviso_caducidad: parseInt(e.target.value) || 30 })} className={ic} />
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <input type="checkbox" id="alm_activo" checked={almacenConfig.activo} onChange={(e) => setAlmacenConfig({ ...almacenConfig, activo: e.target.checked })} className="w-4 h-4" />
                    <label htmlFor="alm_activo" className="text-sm text-surface-700">Alertas automaticas activas (email diario)</label>
                  </div>
                </div>
                <div className="flex items-center justify-between">
                  <button onClick={async () => {
                    if (!almacenConfig.emails.length) { alert("Añade al menos un email de destino"); return; }
                    setAlmacenTestSending(true);
                    const res = await fetch("/api/almacen/alertas-email", { method: "POST" });
                    const d = await res.json();
                    setAlmacenTestSending(false);
                    alert(d.sent ? `Email enviado. ${d.alertas} alertas a ${d.destinatarios} destinatarios.` : "Sin alertas activas o error: " + (d.reason || d.error));
                  }} disabled={almacenTestSending}
                    className="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200 disabled:opacity-60">
                    {almacenTestSending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Mail className="w-4 h-4" />}
                    Enviar email de prueba ahora
                  </button>
                  <button onClick={async () => {
                    setAlmacenSaving(true);
                    await (supabase.from("app_settings") as any).upsert({ key: "almacen_alertas", value: almacenConfig, updated_at: new Date().toISOString() }, { onConflict: "key" });
                    setAlmacenSaving(false); setAlmacenSaved(true); setTimeout(() => setAlmacenSaved(false), 2000);
                  }} disabled={almacenSaving}
                    className={cn("flex items-center gap-1.5 px-5 py-2.5 text-sm font-medium rounded-lg",
                      almacenSaved ? "text-emerald-700 bg-emerald-100" : "text-white bg-brand-500 hover:bg-brand-600 disabled:opacity-60")}>
                    {almacenSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : almacenSaved ? <Check className="w-4 h-4" /> : <Save className="w-4 h-4" />}
                    {almacenSaved ? "Guardado" : "Guardar configuracion"}
                  </button>
                </div>
              </div>
            )}

            {/* GENERAL TAB */}
            {tab === "general" && (
              <div className="card p-6">
                <h2 className="text-sm font-semibold text-surface-900 mb-4">Ajustes generales</h2>
                <p className="text-sm text-surface-500">Próximamente: configuración de empresa, logo, notificaciones, y más.</p>
              </div>
            )}
          </>
        )}
      </div>

      {/* Create/Edit rol modal */}
      <Modal open={rolModal} onClose={() => setRolModal(false)} title={editingRolId ? "Editar rol" : "Nuevo rol"} size="sm">
        <form onSubmit={handleCreateRol} className="space-y-4">
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre del rol *</label><input type="text" required value={rolForm.nombre} onChange={(e) => setRolForm({ ...rolForm, nombre: e.target.value })} placeholder="Ej: Jefe de obra" className={ic} /></div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Descripción</label><input type="text" value={rolForm.descripcion} onChange={(e) => setRolForm({ ...rolForm, descripcion: e.target.value })} placeholder="Descripción del rol" className={ic} /></div>
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setRolModal(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={rolSaving || !rolForm.nombre} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {rolSaving && <Loader2 className="w-4 h-4 animate-spin" />}{editingRolId ? "Guardar" : "Crear"}
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

Write-Host ""
Write-Host "==> Verificando" -ForegroundColor Cyan
$ok1 = Test-Path (Join-Path $RepoPath "src\app\aplicaciones\georadar-v2\page.tsx")
$ok2 = Select-String -Path "src\components\layout\Sidebar.tsx" -Pattern '"Georadar V2"' -Quiet
if ($ok1) { Write-Host "    OK: pagina Georadar V2 actualizada" -ForegroundColor Green }
else { Write-Host "    ERROR" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: Sidebar con nombre correcto" -ForegroundColor Green }
else { Write-Host "    ERROR Sidebar" -ForegroundColor Red }
Write-Host ""
Write-Host '  git add -A'
Write-Host '  git commit -m "feat: Georadar V2 con Google Maps, 4 tipos de anomalia, informe PDF"'
Write-Host '  git push'
Write-Host ""
Write-Host "CONFIGURACION POST-DEPLOY:" -ForegroundColor Cyan
Write-Host "  1. Entra en /aplicaciones/georadar-v2"
Write-Host "  2. Haz clic en 'API Keys' (arriba a la derecha)"
Write-Host "  3. Introduce la Google Maps API Key (AIza...)"
Write-Host "     -> Consiguela en: https://console.cloud.google.com/apis/credentials"
Write-Host "     -> Activa: Maps JavaScript API"
Write-Host "  4. Introduce la Anthropic API Key (sk-ant-...)"
Write-Host "  5. Procesa los archivos SEGY o usa los datos demo"
Write-Host "  6. El mapa muestra los elementos detectados sobre satellite view"
