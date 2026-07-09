#Requires -Version 5.1
# deploy-georadar-v2-sin-riesgos.ps1
# 1. Elimina TODOS los riesgos (ALTO/MEDIO/BAJO) de Georadar V2:
#    - Marcadores del mapa sin borde de riesgo
#    - Popup sin fila Riesgo ni Confianza
#    - Panel lateral sin filas Riesgo alto/medio/bajo
#    - Leyenda sin seccion de riesgo
#    - Informe Word sin columna Riesgo
# 2. Panel de API Keys de IA en el lateral:
#    - Campo para Anthropic (Claude) con boton Guardar
#    - Campo para OpenAI (GPT-4o) con boton Guardar
#    - Las keys se guardan en localStorage del navegador
#    - Los botones Claude/GPT-4o muestran "(sin key)" si no estan configurados
# 3. runAnalysis usa las keys del localStorage directamente (sin API route)
# 4. Informe Word mejorado (profesional):
#    - Portada con proyecto, cliente, zona, fecha, operador
#    - Datos de inspeccion en tabla
#    - Metodologia en parrafos
#    - Mapa de localizacion con leyenda A/S/T
#    - Tabla de resultados sin columna Riesgo
#    - Interpretacion IA
#    - Conclusiones y recomendaciones
#    - Limitaciones del metodo

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Aplicando mejoras Georadar V2" -ForegroundColor Cyan

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

function markerSVG(tipo: AnomalyTypeV2, label: string): string {
  const cfg = TIPO_V2[tipo];
  const dot = "";
  return `<svg xmlns="http://www.w3.org/2000/svg" width="34" height="34" viewBox="0 0 34 34">
    <circle cx="17" cy="17" r="15" fill="${cfg.color}" stroke="white" stroke-width="2.5"/>
    ${dot}
    <text x="17" y="21" text-anchor="middle" fill="white" font-size="10"
      font-weight="700" font-family="monospace,sans-serif">${label}</text>
  </svg>`;
}

function popupHTML(a: any, tipo: AnomalyTypeV2, idx: number): string {
  const cfg = TIPO_V2[tipo];
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
        url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(markerSVG(tipo, label))}`,
        scaledSize: new G.Size(34, 34),
        anchor:     new G.Point(17, 17),
      };
      const mk = new G.Marker({
        position: { lat: a.gpt.lat, lng: a.gpt.lon },
        map: mapInst.current, icon,
        title: `${cfg.label} ${i + 1}`,
        zIndex: 50,
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

Write-Host "  -> src\lib\georadar\generateInformeDocx.ts" -ForegroundColor Gray
$dst = "src\lib\georadar\generateInformeDocx.ts"
$content = @'
/**
 * src/lib/georadar/generateInformeDocx.ts
 *
 * Genera el informe Word de una pasada de georradar para Georadar V2.
 * Sin referencias a niveles de riesgo.
 * Incluye sección de mapa de localización.
 */

import {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  HeadingLevel, AlignmentType, BorderStyle, WidthType, ShadingType,
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
const W = 9360; // ancho contenido en twips (A4 - márgenes)

// ── Helpers ──────────────────────────────────────────────────────────────

function headerCell(text: string, width: number, shade = "1F4E79") {
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    shading: { type: ShadingType.SOLID, color: shade },
    borders,
    children: [new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text, bold: true, color: "FFFFFF", size: 18 })],
    })],
  });
}

function dataCell(text: string, width: number, bold = false, color?: string) {
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    borders,
    children: [new Paragraph({
      children: [new TextRun({ text: text ?? "—", bold, color: color || "000000", size: 18 })],
    })],
  });
}

function h1(text: string) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_1,
    spacing: { before: 300, after: 100 },
    children: [new TextRun({ text, bold: true, color: "1F4E79", size: 28 })],
  });
}

function h2(text: string) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_2,
    spacing: { before: 200, after: 80 },
    children: [new TextRun({ text, bold: true, color: "2E74B5", size: 22 })],
  });
}

function p(text: string, opts: { italics?: boolean; size?: number; color?: string } = {}) {
  return new Paragraph({
    spacing: { before: 60, after: 60 },
    children: [new TextRun({
      text,
      italics: opts.italics,
      size: opts.size || 20,
      color: opts.color || "222222",
    })],
  });
}

function separator() {
  return new Paragraph({
    spacing: { before: 120, after: 120 },
    border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: "1F4E79" } },
    children: [],
  });
}

function infoRow(label: string, value: string) {
  return new TableRow({
    children: [
      new TableCell({
        width: { size: 3000, type: WidthType.DXA },
        shading: { type: ShadingType.SOLID, color: "EEF2F7" },
        borders,
        children: [new Paragraph({
          children: [new TextRun({ text: label, bold: true, size: 18, color: "333333" })],
        })],
      }),
      new TableCell({
        width: { size: 6360, type: WidthType.DXA },
        borders,
        children: [new Paragraph({
          children: [new TextRun({ text: value || "—", size: 18 })],
        })],
      }),
    ],
  });
}

// ── Tipo de anomalía legible ───────────────────────────────────────────

function tipoLabel(type: string): string {
  const map: Record<string, string> = {
    void: "Anomalía", anomaly: "Anomalía",
    supply: "Suministro", pipe: "Tubería",
  };
  return map[type] || "Anomalía";
}

function tipoLetra(type: string, idx: number): string {
  const map: Record<string, string> = {
    void: "A", anomaly: "A", supply: "S", pipe: "T",
  };
  return (map[type] || "A") + (idx + 1);
}

// ── Función principal ─────────────────────────────────────────────────

export async function generateInformeDocx(d: InformeData): Promise<Blob> {
  const allAnoms = d.anoms;
  const anomalias = allAnoms.filter(a => a.type === "void" || a.type === "anomaly");
  const suministros = allAnoms.filter(a => a.type === "supply");
  const tuberias = allAnoms.filter(a => a.type === "pipe");
  const maxDepth = d.longitudM > 0 ? (d.velocidadEm * (d.material.er ?? 9) * 1) : 2;
  const colW = [900, 1400, 1400, 1400, 1400, 1800, 1860];

  // ── Portada ─────────────────────────────────────────────────────────
  const portada: Paragraph[] = [
    new Paragraph({ spacing: { before: 1400, after: 200 }, children: [] }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: "INFORME DE PROSPECCIÓN GEORRADAR GPR", bold: true, size: 40, color: "1F4E79" })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 200, after: 600 },
      children: [new TextRun({ text: "Ground Penetrating Radar — Análisis de Subsuelo", size: 24, color: "666666", italics: true })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 100, after: 100 },
      children: [new TextRun({ text: `Proyecto: ${d.proyecto || "—"}`, bold: true, size: 24, color: "222222" })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 60, after: 60 },
      children: [new TextRun({ text: `Cliente: ${d.clienteNombre || "—"}`, size: 22, color: "444444" })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 60, after: 60 },
      children: [new TextRun({ text: `Zona: ${d.zonaNombre || "—"}`, size: 22, color: "444444" })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 60, after: 60 },
      children: [new TextRun({ text: `Fecha: ${d.fecha}`, size: 22, color: "444444" })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 60, after: 600 },
      children: [new TextRun({ text: `Operador: ${d.operador}`, size: 22, color: "444444" })],
    }),
  ];

  // ── 1. Datos de la inspección ────────────────────────────────────────
  const seccionDatos = [
    h2("1. DATOS DE LA INSPECCIÓN"),
    new Table({
      width: { size: W, type: WidthType.DXA },
      rows: [
        infoRow("Proyecto", d.proyecto),
        infoRow("Cliente", d.clienteNombre),
        infoRow("Zona / Perfil", d.zonaNombre),
        infoRow("Fecha", d.fecha),
        infoRow("Operador", d.operador),
        infoRow("Equipo GPR", `Proceq GS8000 (S/N: ${d.dispositivoSn}, FW: ${d.dispositivoFw})`),
        infoRow("Longitud del perfil", `${d.longitudM.toFixed(1)} m`),
        infoRow("Velocidad EM", `${d.velocidadEm} m/ns`),
        infoRow("Material estimado", d.material.n || "—"),
        infoRow("Anomalías detectadas", String(anomalias.length)),
        infoRow("Suministros detectados", String(suministros.length)),
        infoRow("Tuberías detectadas", String(tuberias.length)),
      ],
    }),
  ];

  // ── 2. Metodología ───────────────────────────────────────────────────
  const seccionMetodo = [
    h2("2. METODOLOGÍA"),
    p("La prospección se ha realizado mediante la tecnología GPR (Ground Penetrating Radar) utilizando el sistema Proceq GS8000 de doble antena (canal LF y canal HF). El equipo emite pulsos electromagnéticos de alta frecuencia que penetran en el subsuelo y registran las reflexiones producidas por cambios en las propiedades dieléctricas de los materiales."),
    p("Los datos han sido procesados mediante el algoritmo de detección de anomalías Sanders, que calcula el volumen de cada anomalía a partir de sus dimensiones estimadas y de los parámetros físicos del material encajante. La velocidad de propagación electromagnética utilizada ha sido de " + d.velocidadEm + " m/ns, correspondiente a material tipo " + (d.material.n || "arena húmeda") + "."),
    p("Los resultados deben ser considerados orientativos y complementados con comprobaciones en campo cuando sea necesario.", { italics: true, color: "666666" }),
  ];

  // ── 3. Mapa de localización ──────────────────────────────────────────
  const seccionMapa: (Paragraph | Table)[] = [h2("3. MAPA DE LOCALIZACIÓN DE ELEMENTOS DETECTADOS")];

  seccionMapa.push(
    p("Nota: el mapa de localización se puede visualizar en la aplicación Georadar V2 activando la vista Google Maps con los elementos detectados.", { italics: true, color: "888888" })
  );

  // Leyenda del mapa
  seccionMapa.push(
    new Paragraph({ spacing: { before: 120, after: 60 }, children: [new TextRun({ text: "Leyenda de símbolos:", bold: true, size: 20 })] }),
    new Table({
      width: { size: 5000, type: WidthType.DXA },
      rows: [
        new TableRow({ children: [
          new TableCell({ borders, width: { size: 600, type: WidthType.DXA }, shading: { type: ShadingType.SOLID, color: "DC2626" }, children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: "A", bold: true, color: "FFFFFF", size: 20 })] })] }),
          dataCell("Anomalía (cavidad, discontinuidad, zona alterada)", 4400),
        ]}),
        new TableRow({ children: [
          new TableCell({ borders, width: { size: 600, type: WidthType.DXA }, shading: { type: ShadingType.SOLID, color: "2563EB" }, children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: "S", bold: true, color: "FFFFFF", size: 20 })] })] }),
          dataCell("Suministro (infraestructura enterrada identificada)", 4400),
        ]}),
        new TableRow({ children: [
          new TableCell({ borders, width: { size: 600, type: WidthType.DXA }, shading: { type: ShadingType.SOLID, color: "D97706" }, children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: "T", bold: true, color: "FFFFFF", size: 20 })] })] }),
          dataCell("Tubería (conducción identificada)", 4400),
        ]}),
      ],
    })
  );

  // ── 4. Tabla de resultados ───────────────────────────────────────────
  const seccionTabla: (Paragraph | Table)[] = [
    h2("4. TABLA DE RESULTADOS"),
    p(`Se han detectado un total de ${allAnoms.length} elemento(s) a lo largo del perfil de ${d.longitudM.toFixed(1)} m.`),
  ];

  if (allAnoms.length === 0) {
    seccionTabla.push(p("No se han detectado anomalías significativas en el perfil analizado."));
  } else {
    seccionTabla.push(
      new Table({
        width: { size: W, type: WidthType.DXA },
        rows: [
          new TableRow({
            tableHeader: true,
            children: [
              headerCell("ID", colW[0]),
              headerCell("Tipo", colW[1]),
              headerCell("Distancia (m)", colW[2]),
              headerCell("Profundidad (m)", colW[3]),
              headerCell("Ancho × Alto (m)", colW[4]),
              headerCell("Vol. neto (m³)", colW[5]),
              headerCell("Coordenadas GPS", colW[6]),
            ],
          }),
          ...allAnoms.map((a, i) => new TableRow({
            children: [
              dataCell(tipoLetra(a.type, i), colW[0], true),
              dataCell(tipoLabel(a.type), colW[1]),
              dataCell(String(a.distM), colW[2]),
              dataCell(String(a.dM), colW[3]),
              dataCell(`${a.wM} × ${a.hM}`, colW[4]),
              dataCell(a.type === "void" || a.type === "anomaly" ? a.vNet.toFixed(4) : "—", colW[5]),
              dataCell(a.gpt ? `${a.gpt.lat.toFixed(5)}, ${a.gpt.lon.toFixed(5)}` : "Sin GPS", colW[6]),
            ],
          })),
        ],
      })
    );
  }

  // ── 5. Interpretación IA ─────────────────────────────────────────────
  const seccionIA = [
    h2("5. INTERPRETACIÓN TÉCNICA"),
  ];
  if (d.analisisTexto) {
    seccionIA.push(
      p(`Análisis generado mediante ${d.analisisModelo || "IA"}.`, { italics: true, color: "666666", size: 18 }),
      new Paragraph({
        spacing: { before: 100, after: 100 },
        children: [new TextRun({ text: d.analisisTexto, size: 18, color: "222222" })],
      })
    );
  } else {
    seccionIA.push(p("No se ha realizado análisis IA. Ejecutar el análisis desde la aplicación Georadar V2 antes de generar el informe.", { italics: true, color: "888888" }));
  }

  // ── 6. Conclusiones ──────────────────────────────────────────────────
  const seccionConclusiones = [
    h2("6. CONCLUSIONES Y RECOMENDACIONES"),
    p(`La prospección GPR ha identificado ${allAnoms.length} elemento(s) de interés a lo largo del perfil de ${d.longitudM.toFixed(1)} m, entre los que se encuentran ${anomalias.length} anomalía(s), ${suministros.length} suministro(s) y ${tuberias.length} tubería(s).`),
    p("Se recomienda complementar los resultados con catas o sondeos de comprobación en los puntos de mayor interés, especialmente donde las anomalías presentan mayor volumen estimado o se sitúan a menor profundidad."),
    p("Los resultados de esta prospección tienen carácter orientativo y deben ser interpretados por un técnico competente.", { italics: true, color: "666666" }),
  ];

  // ── 7. Limitaciones ─────────────────────────────────────────────────
  const seccionLimitaciones = [
    h2("7. LIMITACIONES DEL MÉTODO"),
    ...[
      "La profundidad de penetración depende del contenido de agua y las propiedades del suelo.",
      "La velocidad EM asumida introduce incertidumbre en las profundidades y dimensiones estimadas (±10-15%).",
      "Objetos de dimensiones inferiores a λ/4 pueden no ser detectados.",
      "La presencia de materiales conductivos (arcillas saturadas, cables) reduce la penetración.",
      "Este informe ha sido generado con asistencia de herramientas de procesado digital y, en su caso, IA. No sustituye la revisión de un técnico titulado ni las comprobaciones en campo.",
    ].map(t => new Paragraph({
      spacing: { before: 60, after: 60 },
      bullet: { level: 0 },
      children: [new TextRun({ text: t, size: 18, color: "444444" })],
    })),
  ];

  // ── Ensamblar documento ─────────────────────────────────────────────
  const doc = new Document({
    styles: {
      default: {
        document: { run: { font: "Calibri", size: 20, color: "222222" } },
      },
    },
    sections: [{
      properties: { page: { margin: { top: 1134, bottom: 1134, left: 1134, right: 1134 } } },

      children: [
        ...portada,
        separator(),
        h1("INFORME DE PROSPECCIÓN GEORRADAR"),
        ...seccionDatos,
        separator(),
        ...seccionMetodo,
        separator(),
        ...seccionMapa,
        separator(),
        ...seccionTabla,
        separator(),
        ...seccionIA,
        separator(),
        ...seccionConclusiones,
        separator(),
        ...seccionLimitaciones,
      ],
    }],
  });

  return await Packer.toBlob(doc);
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

Write-Host ""
Write-Host "==> Verificando" -ForegroundColor Cyan
$ok1 = !(Select-String -LiteralPath (Join-Path $RepoPath "src\app\aplicaciones\georadar-v2\MapsPanelV2.tsx") -Pattern 'RISK_COLOR' -Quiet)
$ok2 = !(Select-String -LiteralPath (Join-Path $RepoPath "src\app\aplicaciones\georadar-v2\page.tsx") -Pattern 'RISK_LABEL' -Quiet)
$ok3 = Select-String -LiteralPath (Join-Path $RepoPath "src\app\aplicaciones\georadar-v2\page.tsx") -Pattern 'LS_AI_CLAUDE' -Quiet
$ok4 = !(Select-String -LiteralPath (Join-Path $RepoPath "src\lib\georadar\generateInformeDocx.ts") -Pattern 'riskLabel' -Quiet)
if ($ok1) { Write-Host "    OK: RISK_COLOR eliminado de MapsPanelV2" -ForegroundColor Green }
else { Write-Host "    ERROR: queda RISK_COLOR" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: RISK_LABEL eliminado de page.tsx" -ForegroundColor Green }
else { Write-Host "    ERROR: queda RISK_LABEL" -ForegroundColor Red }
if ($ok3) { Write-Host "    OK: LS_AI_CLAUDE en page.tsx" -ForegroundColor Green }
else { Write-Host "    ERROR: falta LS_AI_CLAUDE" -ForegroundColor Red }
if ($ok4) { Write-Host "    OK: riskLabel eliminado del informe Word" -ForegroundColor Green }
else { Write-Host "    ERROR: queda riskLabel en informe" -ForegroundColor Red }
Write-Host ""
Write-Host '  git add -A'
Write-Host '  git commit -m "feat: Georadar V2 - sin riesgos, keys IA locales, informe profesional"'
Write-Host '  git push'
