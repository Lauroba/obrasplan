"use client";
/**
 * MapsPanelV2.tsx
 * Panel de mapa para Georadar V2 usando Google Maps JavaScript API.
 * Cargado con dynamic/ssr:false desde page.tsx igual que MapsPanel original.
 *
 * Diferencias respecto al MapsPanel original (Leaflet + OSM):
 *  - Usa Google Maps satellite como base
 *  - 4 tipos de marcadores: void(hueco), supply(suministro), pipe(tubería), anomaly(anomalía)
 *  - Filtros por tipo activables/desactivables
 *  - Leyenda siempre visible
 *  - API Key configurable via NEXT_PUBLIC_GMAPS_KEY o localStorage
 */

import { useEffect, useRef, useState, useCallback } from "react";
import { useGeoradarStore } from "@/lib/georadar/useGeoradarStore";
import { maxDepthOf } from "@/lib/georadar/renderRadargram";
import { Map, AlertTriangle, Eye, EyeOff } from "lucide-react";
import { cn } from "@/lib/utils/cn";

// ============================================================
// Tipos y configuración visual por tipo de anomalía
// ============================================================
export type AnomalyTypeV2 = "void" | "supply" | "pipe" | "anomaly";

export const TIPO_V2: Record<AnomalyTypeV2, {
  label: string; color: string; letra: string; riskBorder: boolean;
}> = {
  void:    { label: "Hueco",       color: "#DC2626", letra: "H", riskBorder: true  },
  supply:  { label: "Suministro",  color: "#2563EB", letra: "S", riskBorder: false },
  pipe:    { label: "Tubería",     color: "#D97706", letra: "T", riskBorder: false },
  anomaly: { label: "Anomalía",    color: "#7C3AED", letra: "A", riskBorder: true  },
};

const RISK_COLOR: Record<string, string> = {
  high: "#DC2626", med: "#D97706", low: "#2563EB",
};

const GMAPS_LS_KEY = "georadar_v2_gmaps_key";

// ============================================================
// Función para construir el SVG del marcador
// ============================================================
function buildMarkerSVG(tipo: AnomalyTypeV2, label: string, risk: string): string {
  const cfg = TIPO_V2[tipo];
  const riskColor = RISK_COLOR[risk] || "#6B7280";
  const size = 34;
  const r = 14;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
    <circle cx="${size/2}" cy="${size/2}" r="${r}" fill="${cfg.color}" stroke="white" stroke-width="2.5"/>
    ${cfg.riskBorder && risk === "high"
      ? `<circle cx="${size/2}" cy="${size/2}" r="${r}" fill="none" stroke="${riskColor}" stroke-width="1.5" stroke-dasharray="3,2" opacity=".8"/>`
      : ""}
    <text x="${size/2}" y="${size/2 + 4}" text-anchor="middle" fill="white" 
      font-size="10" font-weight="700" font-family="monospace,sans-serif">${label}</text>
  </svg>`;
}

// ============================================================
// Popup HTML para InfoWindow de Google Maps
// ============================================================
function buildPopup(a: any, tipo: AnomalyTypeV2, idx: number): string {
  const cfg = TIPO_V2[tipo];
  const label = `${cfg.letra}${idx + 1}`;
  const riskLabel = a.risk === "high" ? "ALTO" : a.risk === "med" ? "MEDIO" : "BAJO";
  const riskColor = RISK_COLOR[a.risk] || "#6B7280";
  return `
    <div style="font-family:system-ui,-apple-system,sans-serif;min-width:210px;padding:4px 2px">
      <div style="font-size:13px;font-weight:700;color:${cfg.color};margin-bottom:8px;padding-bottom:6px;border-bottom:2px solid ${cfg.color}20">
        ${cfg.label} ${idx + 1}
      </div>
      <table style="width:100%;border-collapse:collapse;font-size:11.5px">
        <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Distancia</td>
            <td style="font-weight:600;color:#111827">${a.distM ?? "—"} m</td></tr>
        <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Profundidad</td>
            <td style="font-weight:600;color:#111827">${a.dM ?? "—"} m</td></tr>
        <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Dimensiones</td>
            <td style="font-weight:600;color:#111827">${a.wM ?? "—"}×${a.hM ?? "—"} m</td></tr>
        ${a.type === "void" || a.type === "anomaly"
          ? `<tr><td style="color:#6B7280;padding:2px 8px 2px 0">Vol. neto</td>
             <td style="font-weight:600;color:#111827">${typeof a.vNet === "number" ? a.vNet.toFixed(4) : "—"} m³</td></tr>` : ""}
        <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Riesgo</td>
            <td style="font-weight:700;color:${riskColor}">${riskLabel}</td></tr>
        <tr><td style="color:#6B7280;padding:2px 8px 2px 0">Confianza</td>
            <td style="font-weight:600;color:#111827">${Math.round((a.conf ?? 0.7) * 100)}%</td></tr>
        ${a.gpt ? `<tr><td style="color:#6B7280;padding:2px 8px 2px 0">GPS</td>
            <td style="font-weight:600;color:#111827;font-size:10px">${a.gpt.lat.toFixed(6)}, ${a.gpt.lon.toFixed(6)}</td></tr>` : ""}
      </table>
    </div>`;
}

// ============================================================
// Componente principal
// ============================================================
export default function MapsPanelV2() {
  const store   = useGeoradarStore();
  const mapRef  = useRef<HTMLDivElement>(null);
  const mapInst = useRef<any>(null);
  const markers = useRef<any[]>([]);
  const polyline = useRef<any>(null);
  const openInfo = useRef<any>(null);

  const [gmapsKey, setGmapsKey] = useState<string>("");
  const [keyDraft, setKeyDraft] = useState<string>("");
  const [showKey,  setShowKey]  = useState(false);
  const [loaded,   setLoaded]   = useState(false);
  const [error,    setError]    = useState<string | null>(null);
  const [filters,  setFilters]  = useState<Record<AnomalyTypeV2, boolean>>({
    void: true, supply: true, pipe: true, anomaly: true,
  });

  // Cargar key: primero env, luego localStorage
  useEffect(() => {
    const envKey = process.env.NEXT_PUBLIC_GMAPS_KEY || "";
    const lsKey  = typeof window !== "undefined" ? localStorage.getItem(GMAPS_LS_KEY) || "" : "";
    const key    = envKey || lsKey;
    setGmapsKey(key);
    setKeyDraft(key);
  }, []);

  // Guardar key en localStorage
  const saveKey = () => {
    if (!keyDraft.trim()) return;
    localStorage.setItem(GMAPS_LS_KEY, keyDraft.trim());
    setGmapsKey(keyDraft.trim());
  };

  // Cargar script de Google Maps
  useEffect(() => {
    if (!gmapsKey) return;
    if ((window as any).google?.maps) { setLoaded(true); return; }
    const existing = document.getElementById("gmaps-script-v2");
    if (existing) {
      existing.addEventListener("load", () => setLoaded(true));
      return;
    }
    const s = document.createElement("script");
    s.id   = "gmaps-script-v2";
    s.src  = `https://maps.googleapis.com/maps/api/js?key=${gmapsKey}`;
    s.async = true;
    s.defer = true;
    s.onload  = () => setLoaded(true);
    s.onerror = () => setError("Error al cargar Google Maps. Verifica que la API Key es válida y que Maps JavaScript API está activada.");
    document.head.appendChild(s);
  }, [gmapsKey]);

  // Inicializar mapa
  useEffect(() => {
    if (!loaded || !mapRef.current || mapInst.current) return;
    const G = (window as any).google.maps;
    const gpsArr = store.gpsPoints;
    const center = gpsArr.length > 0
      ? { lat: gpsArr[0].lat, lng: gpsArr[0].lon }
      : { lat: 42.8, lng: -1.65 };

    mapInst.current = new G.Map(mapRef.current, {
      center, zoom: 18,
      mapTypeId: "satellite",
      mapTypeControl: true,
      fullscreenControl: false,
      streetViewControl: false,
    });
  }, [loaded]);

  // Redibujar marcadores cuando cambian anomalías o filtros
  useEffect(() => {
    if (!loaded || !mapInst.current) return;
    const G   = (window as any).google.maps;
    const anoms = store.anoms;
    const gpsArr = store.gpsPoints;

    // Limpiar marcadores previos
    markers.current.forEach(m => m.setMap(null));
    markers.current = [];
    if (openInfo.current) { openInfo.current.close(); openInfo.current = null; }

    // Traza GPS
    if (polyline.current) polyline.current.setMap(null);
    if (gpsArr.length > 1) {
      polyline.current = new G.Polyline({
        path: gpsArr.map((p: {lat:number;lon:number;dist?:number}) => ({ lat: p.lat, lng: p.lon })),
        strokeColor: "#F59E0B", strokeOpacity: 0.9, strokeWeight: 3, geodesic: true,
      });
      polyline.current.setMap(mapInst.current);

      const bounds = new G.LatLngBounds();
      gpsArr.forEach((p: {lat:number;lon:number;dist?:number}) => bounds.extend({ lat: p.lat, lng: p.lon }));
      mapInst.current.fitBounds(bounds);
    }

    // Clasificar anomalías en 4 tipos
    anoms.forEach((a: any, i: number) => {
      if (!a.gpt) return;

      // Mapeo de tipo original a los 4 tipos V2
      let tipo: AnomalyTypeV2 = "anomaly";
      if (a.type === "void")   tipo = "void";
      else if (a.type === "supply") {
        // supply: si wM < 0.15 (muy estrecho) → tubería, si no → suministro
        tipo = a.wM < 0.15 ? "pipe" : "supply";
      }

      if (!filters[tipo]) return; // filtro activo

      const cfg   = TIPO_V2[tipo];
      const label = `${cfg.letra}${i + 1}`;
      const svgStr = buildMarkerSVG(tipo, label, a.risk);

      const icon = {
        url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(svgStr)}`,
        scaledSize: new G.Size(34, 34),
        anchor:     new G.Point(17, 17),
      };

      const marker = new G.Marker({
        position: { lat: a.gpt.lat, lng: a.gpt.lon },
        map: mapInst.current,
        icon,
        title: `${cfg.label} ${i + 1}`,
        zIndex: a.risk === "high" ? 100 : a.risk === "med" ? 50 : 10,
      });

      const infoWindow = new G.InfoWindow({ content: buildPopup(a, tipo, i) });
      marker.addListener("click", () => {
        if (openInfo.current) openInfo.current.close();
        infoWindow.open(mapInst.current, marker);
        openInfo.current = infoWindow;
      });

      markers.current.push(marker);
    });
  }, [loaded, store.anoms, store.gpsPoints, filters]);

  const toggleFilter = (t: AnomalyTypeV2) =>
    setFilters(f => ({ ...f, [t]: !f[t] }));

  // ── Sin API Key: mostrar configurador ──────────────────────
  if (!gmapsKey) return (
    <div className="flex flex-col items-center justify-center h-full bg-surface-50 rounded-xl border border-surface-200 gap-4 p-6">
      <Map className="w-10 h-10 text-surface-300" />
      <p className="text-sm font-semibold text-surface-700">Configura la Google Maps API Key</p>
      <p className="text-xs text-surface-500 text-center max-w-sm">
        Necesitas una clave de <a href="https://console.cloud.google.com/apis/credentials"
          target="_blank" rel="noopener noreferrer" className="text-brand-600 hover:underline">
          Google Cloud Console</a> con la API <em>Maps JavaScript API</em> activada.
      </p>
      <div className="flex gap-2 w-full max-w-sm">
        <input
          type={showKey ? "text" : "password"}
          value={keyDraft}
          onChange={e => setKeyDraft(e.target.value)}
          placeholder="AIzaSy..."
          className="flex-1 px-3 py-2 text-sm border border-surface-200 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-brand-500/20"
        />
        <button onClick={() => setShowKey(s => !s)}
          className="px-2 text-surface-400 hover:text-surface-600">
          {showKey ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
        </button>
        <button onClick={saveKey} disabled={!keyDraft.trim()}
          className="px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-50">
          Guardar
        </button>
      </div>
      <p className="text-[10px] text-surface-400 text-center">
        La clave se guarda solo en este navegador (localStorage). No se envía a servidores de Loynek.
      </p>
    </div>
  );

  // ── Error de carga ──────────────────────────────────────────
  if (error) return (
    <div className="flex flex-col items-center justify-center h-full bg-red-50 rounded-xl border border-red-200 gap-3 p-6">
      <AlertTriangle className="w-8 h-8 text-red-400" />
      <p className="text-sm text-red-700 text-center max-w-sm">{error}</p>
      <button onClick={() => { setGmapsKey(""); setKeyDraft(""); localStorage.removeItem(GMAPS_LS_KEY); setError(null); }}
        className="px-3 py-1.5 text-xs text-red-600 border border-red-300 rounded-lg hover:bg-red-100">
        Cambiar API Key
      </button>
    </div>
  );

  // ── Mapa ────────────────────────────────────────────────────
  return (
    <div className="relative w-full h-full">
      <div ref={mapRef} className="w-full h-full rounded-xl overflow-hidden" />

      {/* Filtros */}
      <div className="absolute top-3 left-3 z-10 flex flex-col gap-1.5">
        {(Object.entries(TIPO_V2) as [AnomalyTypeV2, typeof TIPO_V2[AnomalyTypeV2]][]).map(([tipo, cfg]) => (
          <button key={tipo} onClick={() => toggleFilter(tipo)}
            className={cn(
              "flex items-center gap-2 px-2.5 py-1.5 rounded-lg text-xs font-semibold shadow-sm transition-all border",
              filters[tipo]
                ? "bg-white text-surface-800 border-surface-200"
                : "bg-surface-100/80 text-surface-400 border-surface-100 line-through"
            )}>
            <span className="w-4 h-4 rounded-full flex items-center justify-center text-white font-bold shrink-0"
              style={{ backgroundColor: filters[tipo] ? cfg.color : "#9CA3AF", fontSize: 8 }}>
              {cfg.letra}
            </span>
            {cfg.label}
            {filters[tipo]
              ? <Eye className="w-3 h-3 text-surface-400 ml-auto" />
              : <EyeOff className="w-3 h-3 text-surface-300 ml-auto" />}
          </button>
        ))}
      </div>

      {/* Leyenda */}
      <div className="absolute bottom-3 left-3 z-10 bg-white/90 backdrop-blur-sm border border-surface-200 rounded-xl px-3 py-2.5 shadow-sm">
        <p className="text-[9px] font-bold text-surface-500 uppercase tracking-wide mb-1.5">Leyenda</p>
        <div className="space-y-1">
          {(Object.entries(TIPO_V2) as [AnomalyTypeV2, typeof TIPO_V2[AnomalyTypeV2]][]).map(([tipo, cfg]) => (
            <div key={tipo} className="flex items-center gap-2">
              <div className="w-5 h-5 rounded-full border-2 border-white shadow-sm flex items-center justify-center text-white font-bold"
                style={{ backgroundColor: cfg.color, fontSize: 8 }}>
                {cfg.letra}
              </div>
              <span className="text-[10px] text-surface-700">{cfg.label}</span>
            </div>
          ))}
        </div>
        <div className="border-t border-surface-100 mt-2 pt-1.5">
          <p className="text-[9px] font-bold text-surface-500 uppercase tracking-wide mb-1">Riesgo</p>
          {[["ALTO", "#DC2626"], ["MEDIO", "#D97706"], ["BAJO", "#2563EB"]].map(([l, c]) => (
            <div key={l} className="flex items-center gap-1.5 mb-0.5">
              <div className="w-2.5 h-2.5 rounded-full border border-white" style={{ backgroundColor: c }} />
              <span className="text-[10px] text-surface-600">{l}</span>
            </div>
          ))}
        </div>
        <button onClick={() => { setGmapsKey(""); setKeyDraft(""); localStorage.removeItem(GMAPS_LS_KEY); }}
          className="text-[9px] text-surface-400 hover:text-brand-500 mt-2 block">
          Cambiar API Key
        </button>
      </div>
    </div>
  );
}