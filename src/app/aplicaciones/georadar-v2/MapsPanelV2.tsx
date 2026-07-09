"use client";
/**
 * MapsPanelV2.tsx — Google Maps con heatmap para Georadar V2.
 *
 * Fix stack overflow:
 *  - Eliminado HeatOverlay (clase dentro de useEffect creaba closures circulares)
 *  - El heatmap se dibuja solo en el listener "idle" via ref (no closure de estado)
 *  - useRef para anomsRef/gpsRef: el listener siempre ve los datos más recientes
 *    sin necesitar recrearse en cada cambio de store
 *  - mapInst.current inicializado UNA sola vez (guard por ref booleana)
 */

import { useEffect, useRef, useState } from "react";
import { useGeoradarStore } from "@/lib/georadar/useGeoradarStore";
import { Eye, EyeOff, AlertTriangle, Flame, Map } from "lucide-react";
import { cn } from "@/lib/utils/cn";

// ─── Tipos ────────────────────────────────────────────────────────────────────
type AnomalyTypeV2 = "anomaly" | "supply" | "pipe";

const TIPO_V2: Record<AnomalyTypeV2, { label: string; color: string; letra: string }> = {
  anomaly: { label: "Anomalía",   color: "#DC2626", letra: "A" },
  supply:  { label: "Suministro", color: "#2563EB", letra: "S" },
  pipe:    { label: "Tubería",    color: "#D97706", letra: "T" },
};

const LS_KEY   = "georadar_v2_gmaps_key";
const GMAPS_CB = "__gmapsV2Ready__";

// ─── Helpers ──────────────────────────────────────────────────────────────────
function classifyType(a: any): AnomalyTypeV2 {
  if (a.type === "pipe")   return "pipe";
  if (a.type === "supply") return (a.wM ?? 0.5) < 0.15 ? "pipe" : "supply";
  return "anomaly";
}

function markerSVG(tipo: AnomalyTypeV2, label: string): string {
  const { color } = TIPO_V2[tipo];
  return `<svg xmlns="http://www.w3.org/2000/svg" width="34" height="34" viewBox="0 0 34 34">
    <circle cx="17" cy="17" r="15" fill="${color}" stroke="white" stroke-width="2.5"/>
    <text x="17" y="21" text-anchor="middle" fill="white" font-size="10"
      font-weight="700" font-family="monospace,sans-serif">${label}</text>
  </svg>`;
}

function popupHTML(a: any, tipo: AnomalyTypeV2, idx: number): string {
  const { color, label } = TIPO_V2[tipo];
  return `<div style="font-family:system-ui,sans-serif;min-width:190px;padding:2px">
    <b style="color:${color};font-size:13px">${label} ${idx + 1}</b>
    <hr style="margin:6px 0;border-color:${color}30"/>
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

// ─── Heatmap Canvas ───────────────────────────────────────────────────────────
function drawHeatmap(canvas: HTMLCanvasElement, map: any, anoms: any[], radiusPx = 40) {
  // Guard: mapa y proyección deben estar listos
  try {
    if (!map || !map.getProjection || !map.getProjection() || !map.getBounds()) return;
  } catch { return; }

  const W = canvas.width;
  const H = canvas.height;
  if (W < 1 || H < 1) return;

  const ctx = canvas.getContext("2d");
  if (!ctx) return;
  ctx.clearRect(0, 0, W, H);
  if (!anoms.length) return;

  const G = (window as any).google?.maps;
  if (!G) return;

  const pts = anoms
    .filter(a => a.gpt && (a.type === "void" || a.type === "anomaly"))
    .map(a => {
      try {
        const proj   = map.getProjection();
        const bounds = map.getBounds();
        if (!proj || !bounds) return null;
        const ne  = bounds.getNorthEast();
        const sw  = bounds.getSouthWest();
        const neP = proj.fromLatLngToPoint(ne);
        const swP = proj.fromLatLngToPoint(sw);
        const scale   = Math.pow(2, map.getZoom());
        const worldPt = proj.fromLatLngToPoint(new G.LatLng(a.gpt.lat, a.gpt.lon));
        const x = (worldPt.x - swP.x) * scale;
        const y = (worldPt.y - neP.y) * scale;
        return { x, y, w: a.vBruto || 0.01 };
      } catch { return null; }
    })
    .filter((p): p is { x: number; y: number; w: number } =>
      !!p && isFinite(p.x) && isFinite(p.y));

  if (!pts.length) return;

  const maxW  = Math.max(...pts.map(p => p.w), 1e-12);
  const field = new Float32Array(W * H);

  for (const pt of pts) {
    const weight = (pt.w / maxW) + 0.15;
    const x0 = Math.max(0, Math.round(pt.x - radiusPx));
    const x1 = Math.min(W - 1, Math.round(pt.x + radiusPx));
    const y0 = Math.max(0, Math.round(pt.y - radiusPx));
    const y1 = Math.min(H - 1, Math.round(pt.y + radiusPx));
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const d = Math.sqrt((x - pt.x) ** 2 + (y - pt.y) ** 2);
        if (d < radiusPx) field[y * W + x] += weight * (1 - d / radiusPx) ** 2;
      }
    }
  }

  const maxF = Math.max(...Array.from(field));
  if (maxF === 0) return;

  const img = ctx.createImageData(W, H);
  for (let i = 0; i < field.length; i++) {
    const t = field[i] / maxF;
    if (t < 0.01) continue;
    const r = t < 0.5 ? 0 : Math.round((t - 0.5) * 2 * 255);
    const g = t < 0.5 ? Math.round(t * 2 * 255) : Math.round((1 - t) * 2 * 255);
    const b = t < 0.5 ? 255 - Math.round(t * 2 * 255) : 0;
    const idx = i * 4;
    img.data[idx]     = r;
    img.data[idx + 1] = g;
    img.data[idx + 2] = b;
    img.data[idx + 3] = Math.round(t * 0.82 * 255);
  }
  ctx.putImageData(img, 0, 0);
}

// ─── Componente ───────────────────────────────────────────────────────────────
export default function MapsPanelV2() {
  const store = useGeoradarStore();

  const mapDivRef  = useRef<HTMLDivElement>(null);
  const heatCanvas = useRef<HTMLCanvasElement>(null);
  const mapInst    = useRef<any>(null);
  const mapInited  = useRef(false);          // ← evita doble init
  const markers    = useRef<any[]>([]);
  const polyRef    = useRef<any>(null);
  const infoRef    = useRef<any>(null);
  const idleRef    = useRef<any>(null);

  // Refs para datos — el listener idle los lee sin necesitar reconfigurarse
  const anomsRef   = useRef<any[]>([]);
  const viewModeRef = useRef<"map" | "heat" | "both">("map");

  const [apiKey,    setApiKey]    = useState("");
  const [draft,     setDraft]     = useState("");
  const [showKey,   setShowKey]   = useState(false);
  const [mapsReady, setMapsReady] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [viewMode,  setViewMode]  = useState<"map" | "heat" | "both">("map");
  const [filters,   setFilters]   = useState<Record<AnomalyTypeV2, boolean>>(
    { anomaly: true, supply: true, pipe: true }
  );

  // Mantener refs en sync con estado/store
  useEffect(() => { anomsRef.current = store.anoms as any[]; }, [store.anoms]);
  useEffect(() => { viewModeRef.current = viewMode; }, [viewMode]);

  // ── 1. Cargar key ────────────────────────────────────────────────────
  useEffect(() => {
    const k = process.env.NEXT_PUBLIC_GMAPS_KEY || localStorage.getItem(LS_KEY) || "";
    setApiKey(k); setDraft(k);
  }, []);

  // ── 2. Script Google Maps ────────────────────────────────────────────
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
      setLoadError("No se pudo cargar Google Maps. Verifica la API Key.");
      delete (window as any)[GMAPS_CB];
    };
    document.head.appendChild(s);
  }, [apiKey]);

  // ── 3. Inicializar mapa — UNA sola vez ──────────────────────────────
  useEffect(() => {
    if (!mapsReady || !mapDivRef.current || mapInited.current) return;
    mapInited.current = true;                // ← flag: no volver a entrar

    const G = (window as any).google?.maps;
    if (!G) return;

    const gps = store.gps as { lat: number; lon: number; dist?: number }[];
    const center = gps.length > 0
      ? { lat: gps[0].lat, lng: gps[0].lon }
      : { lat: 42.82, lng: -1.64 };

    mapInst.current = new G.Map(mapDivRef.current, {
      center, zoom: 18, mapTypeId: "satellite",
      mapTypeControl: true, fullscreenControl: false, streetViewControl: false,
    });

    // Listener idle: redibuja el heatmap usando ref (no closure de estado)
    idleRef.current = mapInst.current.addListener("idle", () => {
      if (!heatCanvas.current || !mapInst.current) return;
      const vm = viewModeRef.current;
      if (vm === "map") return;              // sin heatmap en modo mapa
      try {
        const W = mapDivRef.current?.clientWidth  || 600;
        const H = mapDivRef.current?.clientHeight || 400;
        if (heatCanvas.current.width  !== W) heatCanvas.current.width  = W;
        if (heatCanvas.current.height !== H) heatCanvas.current.height = H;
        drawHeatmap(heatCanvas.current, mapInst.current, anomsRef.current);
      } catch { /* ignorar */ }
    });
  // Solo depende de mapsReady — nunca se recrea aunque cambie el store
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mapsReady]);

  // ── 4. Actualizar marcadores cuando cambian datos o filtros ──────────
  useEffect(() => {
    if (!mapInst.current) return;
    const G = (window as any).google?.maps;
    if (!G) return;

    // Limpiar
    markers.current.forEach(m => m.setMap(null));
    markers.current = [];
    if (infoRef.current)  { infoRef.current.close(); infoRef.current = null; }
    if (polyRef.current)  { polyRef.current.setMap(null); polyRef.current = null; }

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

    // Marcadores
    (store.anoms as any[]).forEach((a, i) => {
      if (!a.gpt) return;
      const tipo  = classifyType(a);
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
        map: mapInst.current, icon, title: `${cfg.label} ${i + 1}`,
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

    // Heatmap inicial (si ya hay proyección)
    if (heatCanvas.current && viewMode !== "map") {
      try {
        const W = mapDivRef.current?.clientWidth  || 600;
        const H = mapDivRef.current?.clientHeight || 400;
        heatCanvas.current.width  = W;
        heatCanvas.current.height = H;
        drawHeatmap(heatCanvas.current, mapInst.current, store.anoms as any[]);
      } catch { /* proyección no lista aún, se dibujará en idle */ }
    }
  }, [store.anoms, store.gps, filters, viewMode]);

  // ── 5. Mostrar/ocultar canvas y marcadores según modo ───────────────
  useEffect(() => {
    if (heatCanvas.current) {
      heatCanvas.current.style.display = viewMode === "map" ? "none" : "block";
      heatCanvas.current.style.opacity = viewMode === "both" ? "0.75" : "1";
    }
    markers.current.forEach(m => m.setVisible?.(viewMode !== "heat"));
  }, [viewMode]);

  const saveKey = () => {
    const k = draft.trim(); if (!k) return;
    localStorage.setItem(LS_KEY, k);
    // Resetear el mapa para que se cargue con la nueva key
    mapInited.current = false;
    mapInst.current   = null;
    setApiKey(k); setLoadError(""); setMapsReady(false);
    const old = document.getElementById("gmaps-v2");
    if (old) old.remove();
    if ((window as any).google) delete (window as any).google;
  };
  const clearKey = () => {
    localStorage.removeItem(LS_KEY);
    mapInited.current = false;
    mapInst.current   = null;
    setApiKey(""); setDraft(""); setLoadError(""); setMapsReady(false);
    const old = document.getElementById("gmaps-v2");
    if (old) old.remove();
  };

  // ── Sin key ──────────────────────────────────────────────────────────
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
          </a>{" "}activando <em>Maps JavaScript API</em>.
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
      <button onClick={clearKey}
        className="px-4 py-2 text-xs font-semibold text-red-600 border border-red-300 rounded-lg hover:bg-red-100">
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
      <div ref={mapDivRef} className="w-full h-full rounded-xl overflow-hidden" />

      {/* Canvas heatmap superpuesto */}
      <canvas ref={heatCanvas} style={{
        position: "absolute", top: 0, left: 0,
        pointerEvents: "none", borderRadius: "0.75rem",
        display: "none",
      }} />

      {/* Toggle mapa/calor */}
      <div className="absolute top-3 right-3 z-10 flex gap-1 bg-white/90 backdrop-blur-sm border border-surface-200 rounded-xl p-1 shadow-sm">
        {([
          { id: "map",  label: "Mapa",  icon: <Map className="w-3.5 h-3.5" /> },
          { id: "both", label: "Ambos", icon: <><Map className="w-3 h-3" /><Flame className="w-3 h-3" /></> },
          { id: "heat", label: "Calor", icon: <Flame className="w-3.5 h-3.5" /> },
        ] as const).map(({ id, label, icon }) => (
          <button key={id} onClick={() => setViewMode(id)} title={label}
            className={cn("flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs font-semibold transition-all",
              viewMode === id ? "bg-brand-500 text-white shadow-sm" : "text-surface-500 hover:bg-surface-100")}>
            {icon}<span className="hidden sm:inline ml-0.5">{label}</span>
          </button>
        ))}
      </div>

      {/* Filtros */}
      <div className="absolute top-3 left-3 z-10 flex flex-col gap-1.5">
        {(Object.entries(TIPO_V2) as [AnomalyTypeV2, typeof TIPO_V2[AnomalyTypeV2]][]).map(([tipo, cfg]) => (
          <button key={tipo} onClick={() => setFilters(f => ({ ...f, [tipo]: !f[tipo] }))}
            className={cn("flex items-center gap-2 px-2.5 py-1.5 rounded-lg text-xs font-semibold shadow-sm border backdrop-blur-sm transition-all",
              filters[tipo] ? "bg-white/95 text-surface-800 border-surface-200" : "bg-white/60 text-surface-400 border-surface-100")}>
            <span className="w-4 h-4 rounded-full flex items-center justify-center text-white shrink-0"
              style={{ backgroundColor: filters[tipo] ? cfg.color : "#9CA3AF", fontSize: 8, fontWeight: 700 }}>
              {cfg.letra}
            </span>
            <span className={filters[tipo] ? "" : "line-through"}>{cfg.label}</span>
            {filters[tipo] ? <Eye className="w-3 h-3 text-surface-300 ml-auto" /> : <EyeOff className="w-3 h-3 text-surface-300 ml-auto" />}
          </button>
        ))}
      </div>

      {/* Leyenda */}
      <div className="absolute bottom-3 left-3 z-10 bg-white/92 backdrop-blur-sm border border-surface-200 rounded-xl px-3 py-2.5 shadow-sm">
        <p className="text-[9px] font-bold text-surface-500 uppercase tracking-wide mb-2">Leyenda</p>
        <div className="space-y-1.5 mb-2">
          {(Object.entries(TIPO_V2) as [AnomalyTypeV2, typeof TIPO_V2[AnomalyTypeV2]][]).map(([tipo, cfg]) => (
            <div key={tipo} className="flex items-center gap-2">
              <div className="w-5 h-5 rounded-full border-2 border-white shadow-sm flex items-center justify-center text-white font-bold"
                style={{ backgroundColor: cfg.color, fontSize: 8 }}>{cfg.letra}</div>
              <span className="text-[10px] text-surface-700 font-medium">{cfg.label}</span>
            </div>
          ))}
        </div>
        {viewMode !== "map" && (
          <div className="border-t border-surface-100 pt-2 mt-1">
            <p className="text-[9px] font-bold text-surface-500 uppercase tracking-wide mb-1.5">Calor</p>
            <div className="flex items-center gap-1">
              <div className="w-3 h-3 rounded-sm bg-blue-500" />
              <span className="text-[9px] text-surface-500">Bajo</span>
              <div className="w-3 h-3 rounded-sm bg-green-500 ml-1" />
              <div className="w-3 h-3 rounded-sm bg-red-500" />
              <span className="text-[9px] text-surface-500">Alto</span>
            </div>
          </div>
        )}
        <button onClick={clearKey} className="text-[9px] text-surface-400 hover:text-brand-500 mt-2 block">
          ⚙ Cambiar API Key
        </button>
      </div>
    </div>
  );
}