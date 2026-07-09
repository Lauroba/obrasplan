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