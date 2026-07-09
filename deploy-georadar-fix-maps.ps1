#Requires -Version 5.1
# deploy-georadar-fix-maps.ps1
# 1. Corrige el error "client-side exception" al introducir la API Key de Maps:
#    - Race condition entre el render del div y la inicializacion del mapa
#    - Script de Google Maps con ?callback= en lugar de onload
#    - Deteccion correcta de script ya cargado (polling en lugar de addEventListener)
#    - Boton "Cambiar API Key" en la leyenda y en la pantalla de error
# 2. Renombra en el menu y titulos:
#    - "Interpretacion de Georradar" -> "Georadar"
#    - "Georadar V2 + IA" (con icono)  -> "Georadar V2"

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Aplicando fix Google Maps + rename" -ForegroundColor Cyan

Write-Host "  -> src\app\aplicaciones\georadar-v2\MapsPanelV2.tsx" -ForegroundColor Gray
$dst = "src\app\aplicaciones\georadar-v2\MapsPanelV2.tsx"
$content = @'
"use client";
/**
 * MapsPanelV2.tsx — Panel de mapa Google Maps para Georadar V2.
 * Cargado con dynamic/ssr:false desde page.tsx.
 *
 * Fixes respecto a la versión anterior:
 *  - Race condition al guardar la API Key: se usa un ref para el div del mapa
 *    y se inicializa el mapa con un callback en la URL del script (?callback=)
 *    en lugar de onload, garantizando que google.maps está listo cuando se llama.
 *  - Si el script ya existe en el DOM, se detecta y no se re-inserta.
 *  - Filtros por tipo de anomalía (Hueco, Suministro, Tubería, Anomalía).
 *  - Leyenda siempre visible.
 */

import { useEffect, useRef, useState } from "react";
import { useGeoradarStore } from "@/lib/georadar/useGeoradarStore";
import { Eye, EyeOff, AlertTriangle } from "lucide-react";
import { cn } from "@/lib/utils/cn";

// ============================================================
// Tipos y configuración visual
// ============================================================
type AnomalyTypeV2 = "void" | "supply" | "pipe" | "anomaly";

const TIPO_V2: Record<AnomalyTypeV2, { label: string; color: string; letra: string }> = {
  void:    { label: "Hueco",      color: "#DC2626", letra: "H" },
  supply:  { label: "Suministro", color: "#2563EB", letra: "S" },
  pipe:    { label: "Tubería",    color: "#D97706", letra: "T" },
  anomaly: { label: "Anomalía",   color: "#7C3AED", letra: "A" },
};

const RISK_COLOR: Record<string, string> = {
  high: "#DC2626", med: "#D97706", low: "#2563EB",
};

const RISK_LABEL: Record<string, string> = {
  high: "ALTO", med: "MEDIO", low: "BAJO",
};

const LS_KEY = "georadar_v2_gmaps_key";
// Nombre global del callback para Google Maps
const GMAPS_CB = "__gmapsV2Ready__";

// ============================================================
// Helpers
// ============================================================
function markerSVG(tipo: AnomalyTypeV2, label: string, risk: string): string {
  const cfg = TIPO_V2[tipo];
  return `<svg xmlns="http://www.w3.org/2000/svg" width="34" height="34" viewBox="0 0 34 34">
    <circle cx="17" cy="17" r="15" fill="${cfg.color}" stroke="white" stroke-width="2.5"/>
    ${risk === "high"
      ? `<circle cx="17" cy="17" r="15" fill="none" stroke="white" stroke-width="1.5" stroke-dasharray="3,2" opacity=".6"/>`
      : ""}
    <text x="17" y="21" text-anchor="middle" fill="white" font-size="10"
      font-weight="700" font-family="monospace,sans-serif">${label}</text>
  </svg>`;
}

function popupHTML(a: any, tipo: AnomalyTypeV2, idx: number): string {
  const cfg = TIPO_V2[tipo];
  const rColor = RISK_COLOR[a.risk] || "#6B7280";
  return `
    <div style="font-family:system-ui,sans-serif;min-width:200px;padding:2px">
      <b style="color:${cfg.color};font-size:13px">${cfg.label} ${idx + 1}</b>
      <hr style="margin:6px 0;border-color:${cfg.color}30"/>
      <table style="width:100%;font-size:11.5px;border-collapse:collapse">
        <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Distancia</td>
            <td><b>${a.distM ?? "—"} m</b></td></tr>
        <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Profundidad</td>
            <td><b>${a.dM ?? "—"} m</b></td></tr>
        <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Dimensiones</td>
            <td><b>${a.wM ?? "—"} × ${a.hM ?? "—"} m</b></td></tr>
        ${a.type === "void" ? `<tr><td style="color:#6B7280;padding:2px 8px 2px 0">Vol. neto</td>
            <td><b>${typeof a.vNet === "number" ? a.vNet.toFixed(4) : "—"} m³</b></td></tr>` : ""}
        <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Riesgo</td>
            <td><b style="color:${rColor}">${RISK_LABEL[a.risk] || a.risk}</b></td></tr>
        <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Confianza</td>
            <td><b>${Math.round((a.conf ?? 0.7) * 100)}%</b></td></tr>
        ${a.gpt ? `<tr><td style="color:#6B7280;padding:2px 8px 2px 0">GPS</td>
            <td style="font-size:10px"><b>${a.gpt.lat.toFixed(6)}, ${a.gpt.lon.toFixed(6)}</b></td></tr>` : ""}
      </table>
    </div>`;
}

function classifyType(a: any): AnomalyTypeV2 {
  if (a.type === "void") return "void";
  if (a.type === "pipe") return "pipe";
  if (a.type === "anomaly") return "anomaly";
  // supply: estrecho (<0.15m) → tubería, ancho → suministro
  return (a.wM ?? 0.5) < 0.15 ? "pipe" : "supply";
}

// ============================================================
// Componente
// ============================================================
export default function MapsPanelV2() {
  const store = useGeoradarStore();

  const mapDivRef  = useRef<HTMLDivElement>(null);
  const mapInst    = useRef<any>(null);
  const markers    = useRef<any[]>([]);
  const polyRef    = useRef<any>(null);
  const infoRef    = useRef<any>(null);

  const [apiKey,    setApiKey]   = useState("");
  const [draft,     setDraft]    = useState("");
  const [showKey,   setShowKey]  = useState(false);
  const [mapsReady, setMapsReady] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [filters,   setFilters]  = useState<Record<AnomalyTypeV2, boolean>>(
    { void: true, supply: true, pipe: true, anomaly: true }
  );

  // ── 1. Cargar API Key guardada ─────────────────────────────
  useEffect(() => {
    const env = process.env.NEXT_PUBLIC_GMAPS_KEY || "";
    const ls  = localStorage.getItem(LS_KEY) || "";
    const key = env || ls;
    setApiKey(key);
    setDraft(key);
  }, []);

  // ── 2. Cargar el script de Google Maps ────────────────────
  useEffect(() => {
    if (!apiKey) return;

    // Si Google Maps ya está disponible, listo
    if ((window as any).google?.maps) {
      setMapsReady(true);
      return;
    }

    // Registrar callback global ANTES de insertar el script
    (window as any)[GMAPS_CB] = () => {
      setMapsReady(true);
      delete (window as any)[GMAPS_CB];
    };

    // Evitar doble inserción
    if (document.getElementById("gmaps-v2")) {
      // Script ya en DOM pero Maps aún no disponible: esperar
      const t = setInterval(() => {
        if ((window as any).google?.maps) {
          setMapsReady(true);
          clearInterval(t);
        }
      }, 200);
      return () => clearInterval(t);
    }

    const s = document.createElement("script");
    s.id  = "gmaps-v2";
    // callback= en la URL garantiza que google.maps está inicializado cuando se llama
    s.src = `https://maps.googleapis.com/maps/api/js?key=${apiKey}&callback=${GMAPS_CB}`;
    s.async = true;
    s.defer = true;
    s.onerror = () => {
      setLoadError("No se pudo cargar Google Maps. Verifica la API Key y que Maps JavaScript API está activada.");
      delete (window as any)[GMAPS_CB];
    };
    document.head.appendChild(s);
  }, [apiKey]);

  // ── 3. Inicializar el mapa cuando Google Maps esté listo ──
  useEffect(() => {
    if (!mapsReady || !mapDivRef.current || mapInst.current) return;
    const G = (window as any).google.maps;
    const gps = store.gpsPoints;
    const center = gps.length > 0
      ? { lat: gps[0].lat, lng: gps[0].lon }
      : { lat: 42.82, lng: -1.64 };

    mapInst.current = new G.Map(mapDivRef.current, {
      center, zoom: 18,
      mapTypeId: "satellite",
      mapTypeControl: true,
      fullscreenControl: false,
      streetViewControl: false,
    });
  }, [mapsReady, store.gpsPoints]);

  // ── 4. Redibujar marcadores ────────────────────────────────
  useEffect(() => {
    if (!mapsReady || !mapInst.current) return;
    const G = (window as any).google.maps;

    // Limpiar
    markers.current.forEach(m => m.setMap(null));
    markers.current = [];
    if (infoRef.current) { infoRef.current.close(); infoRef.current = null; }
    if (polyRef.current) { polyRef.current.setMap(null); polyRef.current = null; }

    // Traza GPS
    const gps = store.gpsPoints as { lat: number; lon: number; dist?: number }[];
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

    // Marcadores
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
        map: mapInst.current,
        icon,
        title: `${cfg.label} ${i + 1}`,
        zIndex: a.risk === "high" ? 100 : a.risk === "med" ? 50 : 10,
      });

      const iw = new G.InfoWindow({ content: popupHTML(a, tipo, i) });
      mk.addListener("click", () => {
        if (infoRef.current) infoRef.current.close();
        iw.open(mapInst.current, mk);
        infoRef.current = iw;
      });
      markers.current.push(mk);
    });
  }, [mapsReady, store.anoms, store.gpsPoints, filters]);

  const saveKey = () => {
    const k = draft.trim();
    if (!k) return;
    localStorage.setItem(LS_KEY, k);
    setApiKey(k);
    setLoadError("");
    setMapsReady(false);
    // Forzar recarga del script con la nueva key
    const old = document.getElementById("gmaps-v2");
    if (old) old.remove();
    if ((window as any).google) delete (window as any).google;
    mapInst.current = null;
  };

  const clearKey = () => {
    localStorage.removeItem(LS_KEY);
    setApiKey(""); setDraft(""); setLoadError(""); setMapsReady(false);
    mapInst.current = null;
    const old = document.getElementById("gmaps-v2");
    if (old) old.remove();
  };

  // ── Sin API Key ────────────────────────────────────────────
  if (!apiKey) return (
    <div className="flex flex-col items-center justify-center h-full bg-surface-50 rounded-xl border border-surface-200 gap-4 p-8">
      <div className="w-12 h-12 rounded-xl bg-brand-50 flex items-center justify-center">
        <svg className="w-6 h-6 text-brand-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
        </svg>
      </div>
      <div className="text-center">
        <p className="text-sm font-semibold text-surface-800 mb-1">Google Maps API Key requerida</p>
        <p className="text-xs text-surface-500 max-w-xs">
          Necesitas una clave de{" "}
          <a href="https://console.cloud.google.com/apis/credentials" target="_blank"
            rel="noopener noreferrer" className="text-brand-600 hover:underline">
            Google Cloud Console
          </a>{" "}
          con <em>Maps JavaScript API</em> activada.
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
            className="absolute right-2.5 top-1/2 -translate-y-1/2 text-surface-400 hover:text-surface-600">
            {showKey
              ? <EyeOff className="w-3.5 h-3.5" />
              : <Eye className="w-3.5 h-3.5" />}
          </button>
        </div>
        <button onClick={saveKey} disabled={!draft.trim()}
          className="px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-50">
          Activar
        </button>
      </div>
      <p className="text-[10px] text-surface-400 text-center max-w-xs">
        La clave se guarda solo en este navegador. No se envía a servidores de Loynek.
      </p>
    </div>
  );

  // ── Error de carga ─────────────────────────────────────────
  if (loadError) return (
    <div className="flex flex-col items-center justify-center h-full bg-red-50 rounded-xl border border-red-200 gap-3 p-6">
      <AlertTriangle className="w-8 h-8 text-red-400" />
      <p className="text-sm font-semibold text-red-700">Error al cargar Google Maps</p>
      <p className="text-xs text-red-600 text-center max-w-sm">{loadError}</p>
      <button onClick={clearKey}
        className="px-4 py-2 text-xs font-semibold text-red-600 border border-red-300 rounded-lg hover:bg-red-100">
        Cambiar API Key
      </button>
    </div>
  );

  // ── Cargando ───────────────────────────────────────────────
  if (!mapsReady) return (
    <div className="flex items-center justify-center h-full bg-surface-50 rounded-xl border border-surface-200">
      <div className="text-center">
        <div className="w-8 h-8 border-2 border-brand-500 border-t-transparent rounded-full animate-spin mx-auto mb-3" />
        <p className="text-sm text-surface-500">Cargando Google Maps...</p>
      </div>
    </div>
  );

  // ── Mapa ────────────────────────────────────────────────────
  return (
    <div className="relative w-full h-full">
      {/* Contenedor del mapa */}
      <div ref={mapDivRef} className="w-full h-full rounded-xl overflow-hidden" />

      {/* Filtros (esquina superior izquierda) */}
      <div className="absolute top-3 left-3 z-10 flex flex-col gap-1.5">
        {(Object.entries(TIPO_V2) as [AnomalyTypeV2, typeof TIPO_V2[AnomalyTypeV2]][]).map(([tipo, cfg]) => (
          <button key={tipo}
            onClick={() => setFilters(f => ({ ...f, [tipo]: !f[tipo] }))}
            className={cn(
              "flex items-center gap-2 px-2.5 py-1.5 rounded-lg text-xs font-semibold",
              "shadow-sm transition-all border backdrop-blur-sm",
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

      {/* Leyenda (esquina inferior izquierda) */}
      <div className="absolute bottom-3 left-3 z-10 bg-white/92 backdrop-blur-sm
                      border border-surface-200 rounded-xl px-3 py-2.5 shadow-sm">
        <p className="text-[9px] font-bold text-surface-500 uppercase tracking-wide mb-2">Leyenda</p>
        <div className="space-y-1.5">
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
        <div className="border-t border-surface-100 mt-2 pt-2">
          <p className="text-[9px] font-bold text-surface-500 uppercase tracking-wide mb-1.5">Riesgo</p>
          {[["ALTO", "#DC2626"], ["MEDIO", "#D97706"], ["BAJO", "#2563EB"]].map(([l, c]) => (
            <div key={l} className="flex items-center gap-1.5 mb-1">
              <div className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: c }} />
              <span className="text-[10px] text-surface-600">{l}</span>
            </div>
          ))}
        </div>
        <button onClick={clearKey}
          className="text-[9px] text-surface-400 hover:text-brand-500 mt-2 block w-full text-left">
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
      const txt = await file.text();
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
      const txt = await file.text();
      const r = parseParamsText(txt);
      if (r) store.setAnchuraM(r.longitudM);
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
                  <Row label="Huecos detectados" value={String(voids.length)} />
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
                          <span className="font-semibold">{(a.type === "void" ? "H" : "S") + (i + 1)}</span>
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

Write-Host "  -> src\app\aplicaciones\georadar\page.tsx" -ForegroundColor Gray
$dst = "src\app\aplicaciones\georadar\page.tsx"
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
const MapsPanel = dynamic(() => import("./MapsPanel"), { ssr: false });

export default function GeoradarPage() {
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
      const txt = await file.text();
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
      const txt = await file.text();
      const r = parseParamsText(txt);
      if (r) store.setAnchuraM(r.longitudM);
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
              <h1 className="text-xl font-display font-bold text-surface-900">Georadar</h1>
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
                <MapsPanel showMapa={showMapa} showCalor={showCalor} />
              )}
            </div>
          </div>

          {!store.fullscreen && (
            <div className="space-y-4 overflow-y-auto">
              <div className="card p-4">
                <h2 className="text-xs font-semibold text-surface-400 uppercase tracking-wider mb-3">Resultados</h2>
                <div className="space-y-1.5 text-sm">
                  <Row label="Huecos detectados" value={String(voids.length)} />
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
                          <span className="font-semibold">{(a.type === "void" ? "H" : "S") + (i + 1)}</span>
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
  { name: "Georadar", href: "/aplicaciones/georadar", icon: Radar, screen: "apps_georadar" },
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
$ok1 = Select-String -Path "src\components\layout\Sidebar.tsx" -Pattern '"Georadar V2"' -Quiet
$ok2 = Select-String -Path "src\components\layout\Sidebar.tsx" -Pattern '"Georadar"' -Quiet
$ok3 = !(Select-String -Path "src\components\layout\Sidebar.tsx" -Pattern 'Interpretaci' -Quiet)
$ok4 = !(Select-String -Path "src\components\layout\Sidebar.tsx" -Pattern 'V2.*IA' -Quiet)
$ok5 = Select-String -LiteralPath (Join-Path $RepoPath "src\app\aplicaciones\georadar-v2\MapsPanelV2.tsx") -Pattern "__gmapsV2Ready__" -Quiet
if ($ok1) { Write-Host "    OK: Georadar V2 en Sidebar" -ForegroundColor Green }
if ($ok2) { Write-Host "    OK: Georadar en Sidebar" -ForegroundColor Green }
if ($ok3) { Write-Host "    OK: sin Interpretacion de Georradar" -ForegroundColor Green }
if ($ok4) { Write-Host "    OK: sin V2 + IA" -ForegroundColor Green }
if ($ok5) { Write-Host "    OK: MapsPanelV2 con callback fix" -ForegroundColor Green }
else { Write-Host "    ERROR MapsPanelV2" -ForegroundColor Red }
Write-Host ""
Write-Host '  git add -A'
Write-Host '  git commit -m "fix: Maps race condition, renombrar Georadar y Georadar V2"'
Write-Host '  git push'
Write-Host ""
Write-Host "Menu lateral resultante:" -ForegroundColor Cyan
Write-Host "  Georadar    -> /aplicaciones/georadar"
Write-Host "  Georadar V2 -> /aplicaciones/georadar-v2"
