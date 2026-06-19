#Requires -Version 5.1
# fix-georadar-fullscreen-mapas.ps1
# Anade pantalla completa, selector de vista (7 modos) y panel de mapas
# (OSM sincronizado + mapa de calor) a la app de Interpretacion de
# Georradar. Contenido incrustado directamente, sin depender de ningun
# zip externo.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"

if (-not (Test-Path $RepoPath)) {
    Write-Host "ERROR: no se encuentra el repo en $RepoPath" -ForegroundColor Red
    exit 1
}
Set-Location $RepoPath

Write-Host ""
Write-Host "==> Escribiendo archivos del modulo georadar" -ForegroundColor Cyan

$dst = "src\lib\georadar\useGeoradarStore.ts"
$content = @'
/**
 * src/lib/georadar/useGeoradarStore.ts
 *
 * Estado del modulo de interpretacion de georradar. Reemplaza las
 * variables globales mutables S / ZONES de la app HTML original por un
 * store de Zustand, siguiendo el mismo patron que el resto de ObrasPlan
 * (ver src/hooks/useLayout.ts).
 */

import { create } from "zustand";
import type { SegyData } from "./parseSegy";
import type { AnomalyResult, LayerResult, GpsPoint, MaterialKey } from "./detectAnomalies";

export interface ZoomState {
  lf: number;
  hf: number;
}

// Modos de vista del panel de visualizacion, equivalentes a LAYOUTS del
// HTML original: all=4 paneles, lf/hf=radar individual, mapa/calor=mapas
// individuales, radares=LF+HF, mapas=mapa+calor.
export type LayoutMode = "all" | "lf" | "hf" | "mapa" | "calor" | "radares" | "mapas";

interface GeoradarState {
  rdLF: SegyData | null;
  rdHF: SegyData | null;
  gps: GpsPoint[];

  anoms: AnomalyResult[];
  layers: LayerResult[];
  selectedIndex: number;

  clienteNombre: string;
  proyecto: string;
  zonaNombre: string;
  velocidadEm: number;
  anchuraM: number;
  longitudSeccionM: number;
  material: MaterialKey;
  longitudPerfilM: number;

  zoomLevel: ZoomState;
  zoomStart: ZoomState;

  analisisTexto: string | null;
  analisisModelo: string | null;
  analizando: boolean;

  layoutMode: LayoutMode;
  fullscreen: boolean;
  heatmapMinFrac: number;
  heatmapMaxFrac: number;
  heatmapRadiusPx: number;

  setRdLF: (rd: SegyData | null) => void;
  setRdHF: (rd: SegyData | null) => void;
  setGps: (gps: GpsPoint[]) => void;
  setAnoms: (anoms: AnomalyResult[], layers: LayerResult[]) => void;
  setSelectedIndex: (i: number) => void;
  setClienteNombre: (v: string) => void;
  setProyecto: (v: string) => void;
  setZonaNombre: (v: string) => void;
  setVelocidadEm: (v: number) => void;
  setAnchuraM: (v: number) => void;
  setLongitudSeccionM: (v: number) => void;
  setMaterial: (v: MaterialKey) => void;
  setLongitudPerfilM: (v: number) => void;
  setZoom: (ch: "lf" | "hf", level: number, start: number) => void;
  setAnalisis: (texto: string | null, modelo: string | null) => void;
  setAnalizando: (v: boolean) => void;
  setLayoutMode: (m: LayoutMode) => void;
  setFullscreen: (v: boolean) => void;
  toggleFullscreen: () => void;
  setHeatmapParams: (min: number, max: number, radius: number) => void;
  reset: () => void;
}

const initialState = {
  rdLF: null,
  rdHF: null,
  gps: [] as GpsPoint[],
  anoms: [] as AnomalyResult[],
  layers: [] as LayerResult[],
  selectedIndex: -1,
  clienteNombre: "",
  proyecto: "",
  zonaNombre: "ZONA 1",
  velocidadEm: 0.09,
  anchuraM: 0,
  longitudSeccionM: 1.5,
  material: "gr" as MaterialKey,
  longitudPerfilM: 884.2,
  zoomLevel: { lf: 1, hf: 1 },
  zoomStart: { lf: 0, hf: 0 },
  analisisTexto: null,
  analisisModelo: null,
  analizando: false,
  layoutMode: "all" as LayoutMode,
  fullscreen: false,
  heatmapMinFrac: 0,
  heatmapMaxFrac: 1,
  heatmapRadiusPx: 30,
};

export const useGeoradarStore = create<GeoradarState>((set) => ({
  ...initialState,
  setRdLF: (rd) => set({ rdLF: rd }),
  setRdHF: (rd) => set({ rdHF: rd }),
  setGps: (gps) => set({ gps }),
  setAnoms: (anoms, layers) => set({ anoms, layers }),
  setSelectedIndex: (i) => set({ selectedIndex: i }),
  setClienteNombre: (v) => set({ clienteNombre: v }),
  setProyecto: (v) => set({ proyecto: v }),
  setZonaNombre: (v) => set({ zonaNombre: v }),
  setVelocidadEm: (v) => set({ velocidadEm: v }),
  setAnchuraM: (v) => set({ anchuraM: v }),
  setLongitudSeccionM: (v) => set({ longitudSeccionM: v }),
  setMaterial: (v) => set({ material: v }),
  setLongitudPerfilM: (v) => set({ longitudPerfilM: v }),
  setZoom: (ch, level, start) =>
    set((s) => ({ zoomLevel: { ...s.zoomLevel, [ch]: level }, zoomStart: { ...s.zoomStart, [ch]: start } })),
  setAnalisis: (texto, modelo) => set({ analisisTexto: texto, analisisModelo: modelo }),
  setAnalizando: (v) => set({ analizando: v }),
  setLayoutMode: (m) => set({ layoutMode: m }),
  setFullscreen: (v) => set({ fullscreen: v }),
  toggleFullscreen: () => set((s) => ({ fullscreen: !s.fullscreen })),
  setHeatmapParams: (min, max, radius) => set({ heatmapMinFrac: min, heatmapMaxFrac: max, heatmapRadiusPx: radius }),
  reset: () => set(initialState),
}));
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Set-Content -Path $dst -Value $content -NoNewline -Encoding UTF8
Write-Host "    Escrito: $dst" -ForegroundColor Green

$dst = "src\lib\georadar\mapLayers.ts"
$content = @'
/**
 * src/lib/georadar/mapLayers.ts
 *
 * Logica de los dos mapas Leaflet (OSM sincronizado + mapa de calor de
 * anomalias), portada de la app HTML original (initMaps, updateMaps,
 * renderHeat). Adaptada para usarse desde refs de React en vez de
 * document.getElementById, y con la paleta de colores de ObrasPlan
 * (decision confirmada: estilo claro, no el tema oscuro original).
 */

import L from "leaflet";
import type { AnomalyResult, GpsPoint } from "./detectAnomalies";

export interface MapPair {
  m1: L.Map;
  m2: L.Map;
  layers1: L.Layer[];
  layers2: L.Layer[];
}

const DEFAULT_CENTER: L.LatLngTuple = [43.3585, -3.0518];

export function initMaps(container1: HTMLElement, container2: HTMLElement, onMove: () => void): MapPair {
  const m1 = L.map(container1, { center: DEFAULT_CENTER, zoom: 16, zoomControl: true, preferCanvas: true });
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    maxZoom: 20,
    minZoom: 1,
    crossOrigin: true,
  }).addTo(m1);

  const m2 = L.map(container2, { center: DEFAULT_CENTER, zoom: 16, zoomControl: false, attributionControl: false, preferCanvas: true });
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 20, minZoom: 1, crossOrigin: true }).addTo(m2);

  let syncing = false;
  m1.on("move zoom", () => {
    if (syncing) return;
    syncing = true;
    m2.setView(m1.getCenter(), m1.getZoom(), { animate: false });
    syncing = false;
    onMove();
  });
  m2.on("move zoom", () => {
    if (syncing) return;
    syncing = true;
    m1.setView(m2.getCenter(), m2.getZoom(), { animate: false });
    syncing = false;
    onMove();
  });

  return { m1, m2, layers1: [], layers2: [] };
}

function clearLayers(pair: MapPair) {
  pair.layers1.forEach((l) => {
    try { l.remove(); } catch { /* capa ya eliminada */ }
  });
  pair.layers2.forEach((l) => {
    try { l.remove(); } catch { /* capa ya eliminada */ }
  });
  pair.layers1 = [];
  pair.layers2 = [];
}

function addToBoth(pair: MapPair, layer1: L.Layer, layer2: L.Layer) {
  layer1.addTo(pair.m1);
  layer2.addTo(pair.m2);
  pair.layers1.push(layer1);
  pair.layers2.push(layer2);
}

const TRACK_COLOR = "#dc2626";
const RISK_COLOR: Record<string, string> = { high: "#dc2626", med: "#d97706", low: "#2563eb" };

export function updateMapLayers(
  pair: MapPair,
  gps: GpsPoint[],
  anoms: AnomalyResult[],
  longitudPerfilM: number,
  onSelectAnom: (i: number) => void
) {
  clearLayers(pair);
  if (!gps.length) return;

  const lls: L.LatLngTuple[] = gps.map((p) => [p.lat, p.lon]);

  const track1 = L.polyline(lls, { color: TRACK_COLOR, weight: 3, opacity: 0.85, smoothFactor: 1 });
  const track2 = L.polyline(lls, { color: TRACK_COLOR, weight: 3, opacity: 0.85, smoothFactor: 1 });
  addToBoth(pair, track1, track2);

  const glow1 = L.polyline(lls, { color: TRACK_COLOR, weight: 8, opacity: 0.12, smoothFactor: 1 });
  const glow2 = L.polyline(lls, { color: TRACK_COLOR, weight: 8, opacity: 0.12, smoothFactor: 1 });
  addToBoth(pair, glow1, glow2);

  const bounds = track1.getBounds();
  pair.m1.fitBounds(bounds, { padding: [50, 50], maxZoom: 17, animate: false });
  pair.m2.fitBounds(bounds, { padding: [50, 50], maxZoom: 17, animate: false });

  const mkStyle = { radius: 7, fillOpacity: 0.9, weight: 2, color: "#ffffff" };
  const start = gps[0];
  const end = gps[gps.length - 1];
  addToBoth(
    pair,
    L.circleMarker([start.lat, start.lon], { ...mkStyle, fillColor: "#16a34a" }).bindTooltip("Inicio - 0m"),
    L.circleMarker([start.lat, start.lon], { ...mkStyle, fillColor: "#16a34a" })
  );
  addToBoth(
    pair,
    L.circleMarker([end.lat, end.lon], { ...mkStyle, fillColor: TRACK_COLOR }).bindTooltip("Fin - " + longitudPerfilM.toFixed(1) + "m"),
    L.circleMarker([end.lat, end.lon], { ...mkStyle, fillColor: TRACK_COLOR })
  );

  anoms.forEach((a, i) => {
    if (!a.gpt) return;
    const isVoid = a.type === "void";
    const col = isVoid ? "#dc2626" : "#d97706";
    const svg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28">' +
      (a.risk === "high" ? '<circle cx="14" cy="14" r="13" fill="none" stroke="' + col + '" stroke-width="2" stroke-dasharray="3,2" opacity=".6"/>' : "") +
      '<circle cx="14" cy="14" r="10" fill="' + col + '" fill-opacity=".95" stroke="#ffffff" stroke-width="2"/>' +
      '<text x="14" y="17" text-anchor="middle" fill="#ffffff" font-size="7" font-weight="bold" font-family="monospace">' + (isVoid ? "H" : "S") + (i + 1) + "</text></svg>";
    const icon = L.divIcon({ html: svg, className: "", iconSize: [28, 28], iconAnchor: [14, 14] });
    const riskColor = a.risk ? RISK_COLOR[a.risk] : "#6b7280";
    const popupHtml =
      '<div style="font-family:system-ui,sans-serif;font-size:12px;min-width:160px">' +
      '<div style="font-weight:700;color:' + col + ';margin-bottom:4px">' + (isVoid ? "Hueco " : "Suministro ") + (i + 1) + "</div>" +
      '<div style="display:flex;justify-content:space-between;padding:2px 0"><span style="color:#6b7280">Distancia</span><span>' + a.distM + " m</span></div>" +
      '<div style="display:flex;justify-content:space-between;padding:2px 0"><span style="color:#6b7280">Profundidad</span><span>' + a.dM + " m</span></div>" +
      '<div style="display:flex;justify-content:space-between;padding:2px 0"><span style="color:#6b7280">Dimensiones</span><span>' + a.wM + "x" + a.hM + " m</span></div>" +
      (isVoid
        ? '<div style="display:flex;justify-content:space-between;padding:2px 0"><span style="color:#6b7280">Vol. bruto</span><span>' + a.vBruto.toFixed(4) + " m3</span></div>" +
          '<div style="display:flex;justify-content:space-between;padding:2px 0"><span style="color:#6b7280">Riesgo</span><span style="color:' + riskColor + ';font-weight:700">' + (a.risk?.toUpperCase() || "-") + "</span></div>"
        : "") +
      "</div>";
    const mk1 = L.marker([a.gpt.lat, a.gpt.lon], { icon }).bindPopup(popupHtml);
    const mk2 = L.marker([a.gpt.lat, a.gpt.lon], { icon }).bindPopup(popupHtml);
    mk1.on("click", () => onSelectAnom(i));
    mk2.on("click", () => onSelectAnom(i));
    addToBoth(pair, mk1, mk2);
  });
}

export interface HeatmapParams {
  minDepthFrac: number;
  maxDepthFrac: number;
  radiusPx: number;
}

export function renderHeatmap(
  canvas: HTMLCanvasElement,
  map2: L.Map,
  anoms: AnomalyResult[],
  maxDepthM: number,
  params: HeatmapParams
): { voidsInRange: number } {
  const wrap = canvas.parentElement;
  const W = wrap?.clientWidth || 2;
  const H = wrap?.clientHeight || 2;
  canvas.width = W;
  canvas.height = H;
  canvas.style.width = W + "px";
  canvas.style.height = H + "px";
  const ctx = canvas.getContext("2d");
  if (!ctx) return { voidsInRange: 0 };
  ctx.clearRect(0, 0, W, H);

  if (!anoms.length) return { voidsInRange: 0 };

  const minDepth = params.minDepthFrac * maxDepthM;
  const maxDepth = params.maxDepthFrac * maxDepthM;
  const voids = anoms.filter(
    (a) => a.type === "void" && a.gpt && a.dM >= minDepth && (params.maxDepthFrac >= 1 || a.dM <= maxDepth)
  );
  if (!voids.length) return { voidsInRange: 0 };

  const pts = voids
    .map((a) => {
      try {
        const pt = map2.latLngToContainerPoint([a.gpt!.lat, a.gpt!.lon]);
        return { x: pt.x, y: pt.y, vol: a.vBruto, risk: a.risk };
      } catch {
        return null;
      }
    })
    .filter((p): p is { x: number; y: number; vol: number; risk: AnomalyResult["risk"] } => !!p && isFinite(p.x) && isFinite(p.y));

  if (!pts.length) return { voidsInRange: voids.length };

  const rad = params.radiusPx;
  const maxV = Math.max(...pts.map((p) => p.vol), 1e-12);
  const field = new Float32Array(W * H);
  pts.forEach((pt) => {
    const w = pt.vol / maxV + 0.15;
    const x0 = Math.max(0, Math.round(pt.x - rad));
    const x1 = Math.min(W - 1, Math.round(pt.x + rad));
    const y0 = Math.max(0, Math.round(pt.y - rad));
    const y1 = Math.min(H - 1, Math.round(pt.y + rad));
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const d = Math.sqrt((x - pt.x) ** 2 + (y - pt.y) ** 2);
        if (d < rad) field[y * W + x] += w * (1 - d / rad) ** 2;
      }
    }
  });

  let fmax = 0;
  for (let i = 0; i < field.length; i++) if (field[i] > fmax) fmax = field[i];
  if (!fmax) return { voidsInRange: voids.length };

  const img = ctx.createImageData(W, H);
  for (let i = 0; i < W * H; i++) {
    const t = field[i] / fmax;
    if (t < 0.04) continue;
    let r: number, g: number, b: number;
    if (t < 0.25) {
      r = 0; g = Math.round(t * 4 * 180); b = Math.round(80 + t * 4 * 175);
    } else if (t < 0.5) {
      const s = (t - 0.25) / 0.25; r = 0; g = Math.round(180 + s * 75); b = Math.round(255 - s * 255);
    } else if (t < 0.75) {
      const s = (t - 0.5) / 0.25; r = Math.round(s * 255); g = 255; b = 0;
    } else {
      const s = (t - 0.75) / 0.25; r = 255; g = Math.round(255 - s * 230); b = 0;
    }
    const idx = i * 4;
    img.data[idx] = r; img.data[idx + 1] = g; img.data[idx + 2] = b;
    img.data[idx + 3] = Math.round(Math.min(t * 1.5, 1) * 180);
  }
  ctx.putImageData(img, 0, 0);

  pts.forEach((pt) => {
    if (pt.x < 0 || pt.x > W || pt.y < 0 || pt.y > H) return;
    const rc = pt.risk === "high" ? "#dc2626" : pt.risk === "med" ? "#d97706" : "#2563eb";
    ctx.beginPath();
    ctx.arc(pt.x, pt.y, 6, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(255,255,255,0.92)";
    ctx.fill();
    ctx.strokeStyle = rc;
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.fillStyle = "#111827";
    ctx.font = "bold 8px monospace";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText((pt.vol * 1e4).toFixed(0), pt.x, pt.y);
    ctx.textAlign = "left";
    ctx.textBaseline = "alphabetic";
  });

  const lx = 8;
  const ly = H - 46;
  const gg = ctx.createLinearGradient(lx, ly, lx + 90, ly);
  gg.addColorStop(0, "rgba(0,80,200,.9)");
  gg.addColorStop(0.33, "rgba(0,220,255,.9)");
  gg.addColorStop(0.55, "rgba(0,255,50,.9)");
  gg.addColorStop(0.75, "rgba(255,230,0,.9)");
  gg.addColorStop(1, "rgba(255,20,0,.9)");
  ctx.fillStyle = gg;
  ctx.fillRect(lx, ly, 90, 8);
  ctx.strokeStyle = "rgba(0,0,0,.2)";
  ctx.lineWidth = 0.5;
  ctx.strokeRect(lx, ly, 90, 8);
  ctx.fillStyle = "rgba(255,255,255,.95)";
  ctx.font = "7px monospace";
  ctx.shadowColor = "rgba(0,0,0,0.6)";
  ctx.shadowBlur = 2;
  ctx.fillText("Bajo", lx, ly + 17);
  ctx.fillText("Alto", lx + 62, ly + 17);
  ctx.fillText("Vol. x10-4 m3", lx, ly + 26);
  ctx.shadowBlur = 0;

  return { voidsInRange: voids.length };
}
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Set-Content -Path $dst -Value $content -NoNewline -Encoding UTF8
Write-Host "    Escrito: $dst" -ForegroundColor Green

$dst = "src\app\aplicaciones\georadar\MapsPanel.tsx"
$content = @'
"use client";

import { useEffect, useRef, useState } from "react";
import "leaflet/dist/leaflet.css";
import L from "leaflet";
import { initMaps, updateMapLayers, renderHeatmap, type MapPair } from "@/lib/georadar/mapLayers";
import { useGeoradarStore } from "@/lib/georadar/useGeoradarStore";
import { maxDepthOf } from "@/lib/georadar/renderRadargram";

/**
 * Panel de mapas (OSM sincronizado + mapa de calor de anomalias).
 * Componente separado y cargado con next/dynamic (ssr:false) desde la
 * pagina principal, porque Leaflet accede a `window` en el momento de
 * importarse y rompe el render de servidor de Next.js si no se aisla asi.
 *
 * Los iconos por defecto de Leaflet (marker-icon.png) se referencian via
 * URL relativa al paquete y fallan en bundlers como Webpack/Next si no se
 * reconfiguran; aqui no se usan marcadores por defecto (todos los
 * marcadores de mapLayers.ts usan L.divIcon con SVG inline), asi que no
 * hace falta el workaround habitual de Leaflet+webpack.
 */
export default function MapsPanel({ showMapa, showCalor }: { showMapa: boolean; showCalor: boolean }) {
  const store = useGeoradarStore();
  const mapContainer1 = useRef<HTMLDivElement>(null);
  const mapContainer2 = useRef<HTMLDivElement>(null);
  const heatCanvas = useRef<HTMLCanvasElement>(null);
  const pairRef = useRef<MapPair | null>(null);
  const [voidsInRange, setVoidsInRange] = useState(0);

  const refreshHeat = () => {
    if (!heatCanvas.current || !pairRef.current) return;
    const rd = store.rdLF || store.rdHF;
    const md = rd ? maxDepthOf(rd, store.velocidadEm) : 3;
    const { voidsInRange: n } = renderHeatmap(heatCanvas.current, pairRef.current.m2, store.anoms, md, {
      minDepthFrac: store.heatmapMinFrac,
      maxDepthFrac: store.heatmapMaxFrac,
      radiusPx: store.heatmapRadiusPx,
    });
    setVoidsInRange(n);
  };

  // Inicializa los mapas una sola vez, cuando ambos contenedores existen.
  useEffect(() => {
    if (!mapContainer1.current || !mapContainer2.current || pairRef.current) return;
    const pair = initMaps(mapContainer1.current, mapContainer2.current, refreshHeat);
    pairRef.current = pair;
    return () => {
      pair.m1.remove();
      pair.m2.remove();
      pairRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Redibuja las capas (track GPS + anomalias) cuando cambian los datos.
  useEffect(() => {
    if (!pairRef.current) return;
    updateMapLayers(pairRef.current, store.gps, store.anoms, store.longitudPerfilM, store.setSelectedIndex);
    setTimeout(() => {
      pairRef.current?.m1.invalidateSize(false);
      pairRef.current?.m2.invalidateSize(false);
      refreshHeat();
    }, 250);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [store.gps, store.anoms, store.longitudPerfilM]);

  // Redibuja el heatmap cuando cambian sus parametros o la visibilidad cambia
  useEffect(() => {
    const t = setTimeout(refreshHeat, 100);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [store.heatmapMinFrac, store.heatmapMaxFrac, store.heatmapRadiusPx, showMapa, showCalor]);

  // Recalcular tamano de los mapas al cambiar de layout (el contenedor
  // puede pasar de oculto a visible y Leaflet necesita invalidateSize).
  useEffect(() => {
    const t = setTimeout(() => {
      pairRef.current?.m1.invalidateSize(false);
      pairRef.current?.m2.invalidateSize(false);
      refreshHeat();
    }, 80);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showMapa, showCalor]);

  const md = (store.rdLF || store.rdHF) ? maxDepthOf((store.rdLF || store.rdHF)!, store.velocidadEm) : 3;

  return (
    <>
      {showMapa && (
        <div className="bg-white flex flex-col min-h-0">
          <div className="flex items-center gap-2 px-2 py-1 border-b border-surface-100 text-[10px]">
            <span className="font-semibold text-surface-700">Mapa</span>
            <span className="text-surface-400 font-mono">
              {store.gps.length} pts RTK · {store.anoms.length} anomalías
            </span>
          </div>
          <div ref={mapContainer1} className="relative flex-1 min-h-[200px]">
            {store.gps.length === 0 && (
              <div className="absolute inset-0 z-[1000] flex items-center justify-center bg-white/90 text-surface-400 text-[11px] px-6 text-center pointer-events-none">
                Carga un GNSS CSV o pulsa &quot;Probar con datos demo&quot;
              </div>
            )}
          </div>
        </div>
      )}

      {showCalor && (
        <div className="bg-white flex flex-col min-h-0">
          <div className="flex items-center gap-2 px-2 py-1 border-b border-surface-100 text-[10px] flex-wrap">
            <span className="font-semibold text-surface-700">Mapa de calor</span>
            <span className="text-surface-400 font-mono">{voidsInRange} huecos en rango</span>
            <div className="ml-auto flex items-center gap-1.5 text-surface-500">
              <span className="font-mono">Prof:</span>
              <input
                type="range" min={0} max={100}
                value={store.heatmapMinFrac * 100}
                onChange={(e) => store.setHeatmapParams(parseInt(e.target.value) / 100, store.heatmapMaxFrac, store.heatmapRadiusPx)}
                className="w-12"
              />
              <span className="font-mono text-[9px]">{(store.heatmapMinFrac * md).toFixed(1)}m</span>
              <input
                type="range" min={0} max={100}
                value={store.heatmapMaxFrac * 100}
                onChange={(e) => store.setHeatmapParams(store.heatmapMinFrac, parseInt(e.target.value) / 100, store.heatmapRadiusPx)}
                className="w-12"
              />
              <span className="font-mono text-[9px]">{store.heatmapMaxFrac >= 1 ? "∞" : (store.heatmapMaxFrac * md).toFixed(1) + "m"}</span>
              <span className="font-mono">R:</span>
              <input
                type="range" min={10} max={120}
                value={store.heatmapRadiusPx}
                onChange={(e) => store.setHeatmapParams(store.heatmapMinFrac, store.heatmapMaxFrac, parseInt(e.target.value))}
                className="w-10"
              />
            </div>
          </div>
          <div className="relative flex-1 min-h-[200px]">
            <div ref={mapContainer2} className="absolute inset-0" />
            <canvas ref={heatCanvas} className="absolute inset-0 pointer-events-none" />
            {store.gps.length === 0 && (
              <div className="absolute inset-0 z-[1000] flex items-center justify-center bg-white/90 text-surface-400 text-[11px] px-6 text-center pointer-events-none">
                Carga un GNSS CSV o pulsa &quot;Probar con datos demo&quot;
              </div>
            )}
          </div>
        </div>
      )}
    </>
  );
}
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Set-Content -Path $dst -Value $content -NoNewline -Encoding UTF8
Write-Host "    Escrito: $dst" -ForegroundColor Green

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
      <div ref={containerRef} className={cn(store.fullscreen ? "bg-white p-4 h-screen flex flex-col" : "max-w-[1600px] mx-auto animate-fade-in")}>
        {!store.fullscreen && (
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <Radar className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">Interpretación de Georradar</h1>
              <p className="text-sm text-surface-500">Análisis de radargramas Proceq GS8000 Pro</p>
            </div>
          </div>
        )}

        <div className={cn("grid gap-4", store.fullscreen ? "grid-cols-1 lg:grid-cols-[260px_1fr_280px] flex-1 min-h-0" : "grid-cols-1 lg:grid-cols-[260px_1fr_280px]")}>
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

          <div className={cn("card overflow-hidden flex flex-col", store.fullscreen ? "min-h-0" : "")} style={store.fullscreen ? undefined : { minHeight: 560 }}>
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
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Set-Content -Path $dst -Value $content -NoNewline -Encoding UTF8
Write-Host "    Escrito: $dst" -ForegroundColor Green

Write-Host ""
Write-Host "==> Anadiendo leaflet y @types/leaflet a package.json" -ForegroundColor Cyan

$pkgPath = "package.json"
$pkgContent = Get-Content -Path $pkgPath -Raw
$normalizedPkg = $pkgContent -replace "`r`n", "`n"

if ($normalizedPkg -match '"leaflet":') {
    Write-Host "    Ya estaba: leaflet en package.json" -ForegroundColor Yellow
} else {
    $oldDep = @'
    "jspdf": "^2.5.2",
'@
    $newDep = @'
    "jspdf": "^2.5.2",
    "leaflet": "^1.9.4",
'@
    $oldOld = ($oldDep -replace "`r`n", "`n")
    $newNew = ($newDep -replace "`r`n", "`n")
    if ($normalizedPkg.Contains($oldOld)) {
        $normalizedPkg = $normalizedPkg.Replace($oldOld, $newNew)
        Write-Host "    Anadido: leaflet" -ForegroundColor Green
    } else {
        Write-Host "    AVISO: no se encontro el punto de insercion para leaflet, anadelo a mano" -ForegroundColor Yellow
    }
}

if ($normalizedPkg -match '"@types/leaflet":') {
    Write-Host "    Ya estaba: @types/leaflet en package.json" -ForegroundColor Yellow
} else {
    $oldDev = @'
    "@types/node": "^22.10.0",
'@
    $newDev = @'
    "@types/leaflet": "^1.9.21",
    "@types/node": "^22.10.0",
'@
    $oldOld2 = ($oldDev -replace "`r`n", "`n")
    $newNew2 = ($newDev -replace "`r`n", "`n")
    if ($normalizedPkg.Contains($oldOld2)) {
        $normalizedPkg = $normalizedPkg.Replace($oldOld2, $newNew2)
        Write-Host "    Anadido: @types/leaflet" -ForegroundColor Green
    } else {
        Write-Host "    AVISO: no se encontro el punto de insercion para @types/leaflet, anadelo a mano" -ForegroundColor Yellow
    }
}

$finalPkg = $normalizedPkg -replace "`n", "`r`n"
Set-Content -Path $pkgPath -Value $finalPkg -NoNewline -Encoding UTF8

Write-Host ""
Write-Host "==> Verificando resultado" -ForegroundColor Cyan
$checks = @(
    "src\lib\georadar\useGeoradarStore.ts",
    "src\lib\georadar\mapLayers.ts",
    "src\app\aplicaciones\georadar\MapsPanel.tsx",
    "src\app\aplicaciones\georadar\page.tsx"
)
$allOk = $true
foreach ($f in $checks) {
    if (Test-Path $f) {
        $hasMarker = Select-String -Path $f -Pattern "layoutMode|fullscreen|Leaflet|MapsPanel" -Quiet -ErrorAction SilentlyContinue
        if ($hasMarker) {
            Write-Host ("    OK: " + $f) -ForegroundColor Green
        } else {
            Write-Host ("    FALTA CONTENIDO: " + $f) -ForegroundColor Red
            $allOk = $false
        }
    } else {
        Write-Host ("    NO EXISTE: " + $f) -ForegroundColor Red
        $allOk = $false
    }
}

Write-Host ""
if ($allOk) {
    Write-Host "Todo correcto. Siguiente paso:" -ForegroundColor Green
    Write-Host "  npm install"
    Write-Host "  git add -A"
    Write-Host '  git commit -m "feat: pantalla completa, selector de vista y mapas en Georradar"'
    Write-Host "  git push"
} else {
    Write-Host "Algo fallo, revisa los mensajes en rojo antes de hacer commit." -ForegroundColor Red
}
