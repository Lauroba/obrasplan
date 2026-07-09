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