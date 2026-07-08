#Requires -Version 5.1
# deploy-georadar-v2.ps1
# Georadar V2: nueva pantalla con interpretacion IA avanzada
# - No modifica ni rompe Georadar V1 (ruta /aplicaciones/georadar)
# - Nueva ruta: /aplicaciones/georadar-v2
# - Nueva entrada en menu lateral: "Georadar V2 + IA"
# - API Key de Anthropic: introducida por el usuario, guardada en localStorage
# - Prompt tecnico mejorado: tuberias por material, mapa prioridades, artefactos

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Creando Georadar V2" -ForegroundColor Cyan

$dst = "src\app\aplicaciones\georadar-v2\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useRef, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import { cn } from "@/lib/utils/cn";
import {
  Radar, Key, Eye, EyeOff, Trash2, Plus, Loader2, Sparkles, AlertTriangle,
  FileText, ChevronDown, ChevronUp, CheckCircle2, XCircle, Info,
} from "lucide-react";
import { buildPromptV2, type ContextoV2, type AnomaliaV2 } from "@/lib/georadar/buildPromptV2";

// ============================================================
// Constantes
// ============================================================
const LS_KEY = "georadar_v2_apikey";
const MODELO = "claude-opus-4-5";

const TIPO_OPCIONES = ["hueco", "tuberia", "artefacto", "humedad", "junta", "otro"];
const RIESGO_OPCIONES = ["alto", "medio", "bajo"] as const;

const emptyAnom = (): AnomaliaV2 => ({
  id: "", tipo: "hueco", distancia: 0, profundidad: 0,
  riesgo: "medio", confianza: 80,
});

const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

// ============================================================
// Componente ApiKey panel
// ============================================================
function ApiKeyPanel({ apiKey, onChange }: { apiKey: string; onChange: (k: string) => void }) {
  const [show, setShow] = useState(false);
  const [draft, setDraft] = useState(apiKey);
  const [saved, setSaved] = useState(false);

  const handleSave = () => {
    localStorage.setItem(LS_KEY, draft.trim());
    onChange(draft.trim());
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };
  const handleDelete = () => {
    localStorage.removeItem(LS_KEY);
    setDraft(""); onChange("");
  };

  return (
    <div className="card p-4 mb-4 border border-amber-200 bg-amber-50/50">
      <div className="flex items-center gap-2 mb-3">
        <Key className="w-4 h-4 text-amber-600" />
        <span className="text-sm font-semibold text-amber-800">API Key de Anthropic</span>
        {apiKey && <span className="ml-auto text-xs text-emerald-600 font-medium flex items-center gap-1"><CheckCircle2 className="w-3 h-3" />Configurada</span>}
        {!apiKey && <span className="ml-auto text-xs text-red-500 font-medium flex items-center gap-1"><XCircle className="w-3 h-3" />No configurada — IA desactivada</span>}
      </div>
      <div className="flex gap-2">
        <div className="relative flex-1">
          <input
            type={show ? "text" : "password"}
            value={draft}
            onChange={e => setDraft(e.target.value)}
            placeholder="sk-ant-..."
            className={cn(ic, "pr-9")}
          />
          <button type="button" onClick={() => setShow(s => !s)}
            className="absolute right-2.5 top-1/2 -translate-y-1/2 text-surface-400 hover:text-surface-600">
            {show ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
          </button>
        </div>
        <button onClick={handleSave} disabled={!draft.trim()}
          className="px-3 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-50">
          {saved ? "✓ Guardada" : "Guardar"}
        </button>
        {apiKey && (
          <button onClick={handleDelete} title="Borrar API Key"
            className="p-2 text-red-400 hover:bg-red-50 rounded-lg">
            <Trash2 className="w-4 h-4" />
          </button>
        )}
      </div>
      <p className="text-xs text-amber-700 mt-2 flex items-start gap-1.5">
        <Info className="w-3.5 h-3.5 shrink-0 mt-0.5" />
        La API Key se guarda solo en este navegador y nunca se envía a servidores de Loynek.
        Se usa exclusivamente para llamar directamente a la API de Anthropic.
      </p>
    </div>
  );
}

// ============================================================
// Componente editor de anomalía
// ============================================================
function AnomaliaEditor({ anom, idx, onChange, onDelete }: {
  anom: AnomaliaV2; idx: number;
  onChange: (a: AnomaliaV2) => void;
  onDelete: () => void;
}) {
  const [expanded, setExpanded] = useState(idx === 0);
  return (
    <div className="border border-surface-200 rounded-xl overflow-hidden">
      <div className="flex items-center gap-2 px-3 py-2.5 bg-surface-50 cursor-pointer"
        onClick={() => setExpanded(e => !e)}>
        <span className={cn("w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold text-white shrink-0",
          anom.riesgo === "alto" ? "bg-red-500" : anom.riesgo === "medio" ? "bg-amber-500" : "bg-blue-500")}>
          {idx + 1}
        </span>
        <span className="text-sm font-medium flex-1">
          {anom.id || `Anomalía ${idx + 1}`} — {anom.tipo} @ {anom.distancia}m / {anom.profundidad}m
        </span>
        <span className="text-xs text-surface-400">{anom.confianza}%</span>
        <button onClick={e => { e.stopPropagation(); onDelete(); }}
          className="p-1 text-surface-300 hover:text-red-500"><Trash2 className="w-3.5 h-3.5" /></button>
        {expanded ? <ChevronUp className="w-4 h-4 text-surface-400" /> : <ChevronDown className="w-4 h-4 text-surface-400" />}
      </div>
      {expanded && (
        <div className="p-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
          <div><label className="block text-xs text-surface-500 mb-1">ID</label>
            <input className={ic} value={anom.id} placeholder="H1, T1, A1..."
              onChange={e => onChange({ ...anom, id: e.target.value })} /></div>
          <div><label className="block text-xs text-surface-500 mb-1">Tipo</label>
            <select className={ic} value={anom.tipo} onChange={e => onChange({ ...anom, tipo: e.target.value })}>
              {TIPO_OPCIONES.map(t => <option key={t} value={t}>{t}</option>)}</select></div>
          <div><label className="block text-xs text-surface-500 mb-1">Riesgo</label>
            <select className={ic} value={anom.riesgo} onChange={e => onChange({ ...anom, riesgo: e.target.value as any })}>
              {RIESGO_OPCIONES.map(r => <option key={r} value={r}>{r}</option>)}</select></div>
          <div><label className="block text-xs text-surface-500 mb-1">Distancia (m)</label>
            <input type="number" step="0.1" className={ic} value={anom.distancia}
              onChange={e => onChange({ ...anom, distancia: parseFloat(e.target.value)||0 })} /></div>
          <div><label className="block text-xs text-surface-500 mb-1">Profundidad (m)</label>
            <input type="number" step="0.01" className={ic} value={anom.profundidad}
              onChange={e => onChange({ ...anom, profundidad: parseFloat(e.target.value)||0 })} /></div>
          <div><label className="block text-xs text-surface-500 mb-1">Confianza (%)</label>
            <input type="number" min="0" max="100" className={ic} value={anom.confianza}
              onChange={e => onChange({ ...anom, confianza: parseInt(e.target.value)||0 })} /></div>
          <div><label className="block text-xs text-surface-500 mb-1">Ancho (m)</label>
            <input type="number" step="0.01" className={ic} value={anom.ancho||""}
              onChange={e => onChange({ ...anom, ancho: parseFloat(e.target.value)||undefined })} /></div>
          <div><label className="block text-xs text-surface-500 mb-1">Alto (m)</label>
            <input type="number" step="0.01" className={ic} value={anom.alto||""}
              onChange={e => onChange({ ...anom, alto: parseFloat(e.target.value)||undefined })} /></div>
          <div><label className="block text-xs text-surface-500 mb-1">Vol. bruto (m³)</label>
            <input type="number" step="0.0001" className={ic} value={anom.volBruto||""}
              onChange={e => onChange({ ...anom, volBruto: parseFloat(e.target.value)||undefined })} /></div>
          <div className="col-span-2 sm:col-span-3">
            <label className="block text-xs text-surface-500 mb-1">Notas / observaciones</label>
            <textarea rows={2} className={cn(ic, "resize-none")} value={anom.notas||""}
              onChange={e => onChange({ ...anom, notas: e.target.value })} /></div>
        </div>
      )}
    </div>
  );
}

// ============================================================
// Página principal Georadar V2
// ============================================================
export default function GeoradarV2Page() {
  const [apiKey, setApiKey] = useState("");
  const [showApiKey, setShowApiKey] = useState(false);

  // Parámetros del perfil
  const [ctx, setCtx] = useState<Omit<ContextoV2, "anomalias">>({
    proyecto: "", operador: "", fecha: new Date().toISOString().slice(0, 10),
    equipo: "Proceq GS8000 Pro", vel: 0.1, er: 9, maxDepth: 2.0,
    perfilM: 10, material: "Arena húmeda", porosidad: 0.35, fSanders: 0.8,
    capas: "", gpsCount: 0,
    lfDt: 45, lfRows: 369, lfCols: 500,
    hfDt: 40, hfRows: 655, hfCols: 500,
  });

  // Anomalías
  const [anomalias, setAnomalias] = useState<AnomaliaV2[]>([]);

  // IA
  const [analizando, setAnalizando] = useState(false);
  const [resultado, setResultado] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [copiado, setCopiado] = useState(false);

  // Cargar API key de localStorage
  useEffect(() => {
    const k = localStorage.getItem(LS_KEY) || "";
    setApiKey(k);
    setShowApiKey(!k); // mostrar panel si no hay key
  }, []);

  const addAnomalia = () => {
    const n = anomalias.length + 1;
    const tipo = "hueco";
    setAnomalias(prev => [...prev, { ...emptyAnom(), id: `H${n}` }]);
  };

  const handleAnalizar = async () => {
    if (!apiKey) { setError("Introduce una API Key de Anthropic para usar la interpretación IA."); return; }
    if (anomalias.length === 0) { setError("Añade al menos una anomalía para analizar."); return; }

    setAnalizando(true); setError(null); setResultado(null);

    const contexto: ContextoV2 = { ...ctx, anomalias };
    const prompt = buildPromptV2(contexto);

    try {
      const resp = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
          "anthropic-dangerous-direct-browser-access": "true",
        },
        body: JSON.stringify({
          model: MODELO,
          max_tokens: 4096,
          messages: [{ role: "user", content: prompt }],
        }),
      });

      if (!resp.ok) {
        const err = await resp.json().catch(() => ({}));
        throw new Error((err as any)?.error?.message || `Error ${resp.status}`);
      }

      const data = await resp.json();
      const text = data.content?.find((b: any) => b.type === "text")?.text || "";
      setResultado(text);
    } catch (e: any) {
      setError("Error al llamar a la IA: " + (e?.message || e));
    } finally {
      setAnalizando(false);
    }
  };

  const handleCopiar = () => {
    if (resultado) {
      navigator.clipboard.writeText(resultado);
      setCopiado(true);
      setTimeout(() => setCopiado(false), 2000);
    }
  };

  const handleDescargar = () => {
    if (!resultado) return;
    const blob = new Blob([resultado], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `georadar-v2-informe-${ctx.fecha}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <AppLayout>
      <div className="max-w-5xl mx-auto animate-fade-in pb-12">
        {/* Cabecera */}
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
            <Radar className="w-5 h-5 text-brand-600" />
          </div>
          <div>
            <h1 className="text-xl font-display font-bold text-surface-900 flex items-center gap-2">
              Georadar V2
              <span className="badge bg-brand-100 text-brand-700 text-[10px]">IA avanzada</span>
            </h1>
            <p className="text-sm text-surface-500">Interpretación GPR con IA — informe técnico profesional</p>
          </div>
          <button onClick={() => setShowApiKey(s => !s)}
            className="ml-auto flex items-center gap-1.5 px-3 py-1.5 text-xs text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">
            <Key className="w-3.5 h-3.5" />{apiKey ? "API Key ✓" : "Configurar API Key"}
          </button>
        </div>

        {/* API Key panel */}
        {showApiKey && <ApiKeyPanel apiKey={apiKey} onChange={k => { setApiKey(k); if (k) setShowApiKey(false); }} />}

        {/* Aviso IA */}
        <div className="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 mb-6 flex items-start gap-3">
          <AlertTriangle className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" />
          <p className="text-xs text-amber-800">
            <strong>Aviso:</strong> La interpretación IA es una ayuda técnica y debe ser validada
            por un técnico competente. No sustituye las comprobaciones en campo.
          </p>
        </div>

        {/* Parámetros del perfil */}
        <div className="card p-5 mb-5">
          <h2 className="text-sm font-semibold text-surface-700 mb-4">Parámetros de la inspección</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {[
              { label: "Proyecto", key: "proyecto", type: "text" },
              { label: "Operador", key: "operador", type: "text" },
              { label: "Fecha", key: "fecha", type: "date" },
              { label: "Equipo GPR", key: "equipo", type: "text" },
              { label: "Material", key: "material", type: "text" },
            ].map(({ label, key, type }) => (
              <div key={key}>
                <label className="block text-xs font-medium text-surface-600 mb-1">{label}</label>
                <input type={type} className={ic} value={(ctx as any)[key]}
                  onChange={e => setCtx(c => ({ ...c, [key]: e.target.value }))} />
              </div>
            ))}
            {[
              { label: "Vel. EM (m/ns)", key: "vel", step: "0.001" },
              { label: "εr (constante diel.)", key: "er", step: "0.1" },
              { label: "Prof. máx. (m)", key: "maxDepth", step: "0.1" },
              { label: "Perfil total (m)", key: "perfilM", step: "0.1" },
              { label: "Porosidad (0-1)", key: "porosidad", step: "0.01" },
              { label: "Factor Sanders", key: "fSanders", step: "0.01" },
              { label: "GPS (nº puntos)", key: "gpsCount", step: "1" },
            ].map(({ label, key, step }) => (
              <div key={key}>
                <label className="block text-xs font-medium text-surface-600 mb-1">{label}</label>
                <input type="number" step={step} className={ic} value={(ctx as any)[key]}
                  onChange={e => setCtx(c => ({ ...c, [key]: parseFloat(e.target.value)||0 }))} />
              </div>
            ))}
            <div className="col-span-full">
              <label className="block text-xs font-medium text-surface-600 mb-1">Capas identificadas</label>
              <input type="text" className={ic} value={ctx.capas} placeholder="Ej: Pavimento a 0.1m; Arena suelta a 0.5m; Gravas a 1.2m"
                onChange={e => setCtx(c => ({ ...c, capas: e.target.value }))} />
            </div>
          </div>
        </div>

        {/* Anomalías */}
        <div className="card p-5 mb-5">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-surface-700">
              Anomalías detectadas <span className="text-surface-400 font-normal">({anomalias.length})</span>
            </h2>
            <button onClick={addAnomalia}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
              <Plus className="w-3.5 h-3.5" />Añadir anomalía
            </button>
          </div>
          {anomalias.length === 0 ? (
            <div className="text-center py-8 text-sm text-surface-400">
              <Radar className="w-8 h-8 mx-auto mb-2 opacity-30" />
              Añade las anomalías detectadas en el radargrama
            </div>
          ) : (
            <div className="space-y-2">
              {anomalias.map((a, i) => (
                <AnomaliaEditor key={i} anom={a} idx={i}
                  onChange={updated => setAnomalias(prev => prev.map((x, j) => j === i ? updated : x))}
                  onDelete={() => setAnomalias(prev => prev.filter((_, j) => j !== i))} />
              ))}
            </div>
          )}
        </div>

        {/* Botón interpretar */}
        <div className="flex gap-3 mb-5">
          <button onClick={handleAnalizar} disabled={analizando || !apiKey}
            className="flex items-center gap-2 px-6 py-3 text-sm font-semibold text-white bg-brand-500 rounded-xl hover:bg-brand-600 disabled:opacity-50 disabled:cursor-not-allowed shadow-sm">
            {analizando ? <Loader2 className="w-4 h-4 animate-spin" /> : <Sparkles className="w-4 h-4" />}
            {analizando ? "Analizando con IA..." : "Interpretar con IA"}
          </button>
          {!apiKey && (
            <p className="text-xs text-red-500 flex items-center gap-1">
              <XCircle className="w-3.5 h-3.5" />Configura la API Key para activar la IA
            </p>
          )}
        </div>

        {/* Error */}
        {error && (
          <div className="bg-red-50 border border-red-200 rounded-xl px-4 py-3 mb-4 text-sm text-red-700 flex items-start gap-2">
            <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />{error}
          </div>
        )}

        {/* Resultado */}
        {resultado && (
          <div className="card p-5">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-sm font-semibold text-surface-700 flex items-center gap-2">
                <FileText className="w-4 h-4 text-brand-500" />Informe técnico GPR — Interpretación IA
              </h2>
              <div className="flex gap-2">
                <button onClick={handleCopiar}
                  className="px-3 py-1.5 text-xs text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">
                  {copiado ? "✓ Copiado" : "Copiar"}
                </button>
                <button onClick={handleDescargar}
                  className="px-3 py-1.5 text-xs font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
                  Descargar .txt
                </button>
              </div>
            </div>
            <div className="bg-surface-50 rounded-xl p-4 max-h-[60vh] overflow-y-auto">
              <pre className="text-xs text-surface-700 whitespace-pre-wrap font-sans leading-relaxed">{resultado}</pre>
            </div>
            <p className="text-xs text-surface-400 mt-3 border-t border-surface-100 pt-3">
              ⚠ La interpretación IA es una ayuda técnica. Validar siempre con técnico competente y comprobaciones en campo.
            </p>
          </div>
        )}
      </div>
    </AppLayout>
  );
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\aplicaciones\georadar-v2\page.tsx" -ForegroundColor Green

$dst = "src\lib\georadar\buildPromptV2.ts"
$content = @'
/**
 * buildPromptV2.ts
 * Prompt mejorado para Georadar V2:
 * - Clasificación de tuberías por material
 * - Mapa de puntos a revisar
 * - Análisis de continuidad lateral
 * - Firmas GPR detalladas
 * - Sección de artefactos
 */

export interface AnomaliaV2 {
  id: string;          // H1, T1, A1...
  tipo: string;        // hueco | tuberia | artefacto | humedad | junta
  distancia: number;   // metros desde inicio
  profundidad: number; // metros
  riesgo: "alto" | "medio" | "bajo";
  confianza: number;   // 0-100
  ancho?: number;
  alto?: number;
  volBruto?: number;
  volNeto?: number;
  gps?: { lat: number; lon: number; elev: number };
  notas?: string;
}

export interface ContextoV2 {
  proyecto: string;
  operador: string;
  fecha: string;
  equipo: string;
  vel: number;        // m/ns
  er: number;         // constante dieléctrica
  maxDepth: number;   // m
  perfilM: number;    // longitud del perfil en m
  material: string;
  porosidad: number;  // 0-1
  fSanders: number;
  capas: string;
  gpsCount: number;
  lfDt?: number; lfRows?: number; lfCols?: number;
  hfDt?: number; hfRows?: number; hfCols?: number;
  anomalias: AnomaliaV2[];
  // Imágenes base64 (opcional — si se envían, Claude puede analizarlas visualmente)
  imagenLF?: string;  // base64 PNG
  imagenHF?: string;  // base64 PNG
}

export function buildPromptV2(ctx: ContextoV2): string {
  const huecos  = ctx.anomalias.filter(a => a.tipo === "hueco");
  const tubos   = ctx.anomalias.filter(a => a.tipo === "tuberia");
  const artefac = ctx.anomalias.filter(a => a.tipo === "artefacto");
  const otros   = ctx.anomalias.filter(a => !["hueco","tuberia","artefacto"].includes(a.tipo));

  const hi = huecos.filter(a => a.riesgo === "alto").length;
  const me = huecos.filter(a => a.riesgo === "medio").length;
  const lo = huecos.filter(a => a.riesgo === "bajo").length;
  const totBruto = huecos.reduce((s,a) => s + (a.volBruto||0), 0);
  const totNeto  = huecos.reduce((s,a) => s + (a.volNeto||0),  0);

  const fmtAnom = (a: AnomaliaV2, i: number) => [
    `--- ${a.tipo.toUpperCase()} ${a.id} ---`,
    `  Distancia  : ${a.distancia.toFixed(1)} m | Profundidad: ${a.profundidad.toFixed(2)} m`,
    `  Riesgo     : ${a.riesgo.toUpperCase()} | Confianza: ${a.confianza}%${a.confianza < 60 ? " ⚠ VERIFICAR" : ""}`,
    a.ancho ? `  Dimensiones: ${a.ancho.toFixed(2)} m ancho x ${a.alto?.toFixed(2)||"?"} m alto` : "",
    a.volBruto ? `  Volumen    : ${a.volBruto.toFixed(4)} m³ bruto / ${(a.volNeto||0).toFixed(4)} m³ neto` : "",
    a.gps ? `  GPS        : ${a.gps.lat.toFixed(6)}N ${a.gps.lon.toFixed(6)}E elev=${a.gps.elev.toFixed(1)}m` : "  GPS        : sin coordenada",
    a.notas ? `  Notas      : ${a.notas}` : "",
  ].filter(Boolean).join("\n");

  return `Eres un GEOTÉCNICO SENIOR EXPERTO en interpretación de radargramas GPR (Ground Penetrating Radar) \
con experiencia contrastada en inspección de subsuelo urbano, detección de infraestructuras enterradas, \
evaluación de riesgos geotécnicos en suelos granulares y generación de informes técnicos profesionales. \
Redacta un INFORME TÉCNICO EXHAUSTIVO, RIGUROSO y en ESPAÑOL.

===================================================================
DATOS DE LA INSPECCIÓN
===================================================================
Proyecto   : ${ctx.proyecto}
Operador   : ${ctx.operador} | Fecha: ${ctx.fecha}
Equipo     : ${ctx.equipo}
Canal LF   : ${ctx.lfDt?.toFixed(2)??"—"} ns | ${ctx.lfRows??"—"} muestras/traza | ${ctx.lfCols??"—"} trazas
Canal HF   : ${ctx.hfDt?.toFixed(2)??"—"} ns | ${ctx.hfRows??"—"} muestras/traza | ${ctx.hfCols??"—"} trazas
Vel. EM    : ${ctx.vel} m/ns | Prof. máx.: ${ctx.maxDepth.toFixed(2)} m | Perfil: ${ctx.perfilM.toFixed(1)} m
Material   : ${ctx.material} | Porosidad: ${(ctx.porosidad*100).toFixed(0)}% | εr=${ctx.er} | f_Sanders=${ctx.fSanders}
Capas      : ${ctx.capas || "No definidas"}
GPS RTK    : ${ctx.gpsCount} puntos

RESUMEN ANOMALÍAS:
  Huecos/cavidades : ${huecos.length} (${hi} ALTO | ${me} MEDIO | ${lo} BAJO)
  Tuberías/sumin.  : ${tubos.length}
  Artefactos ident.: ${artefac.length}
  Otros            : ${otros.length}
  Vol. bruto total : ${totBruto.toFixed(4)} m³ | Neto: ${totNeto.toFixed(4)} m³

===================================================================
ANOMALÍAS DETECTADAS (DATOS PARA ANÁLISIS)
===================================================================
${ctx.anomalias.map(fmtAnom).join("\n\n")}

===================================================================
INSTRUCCIONES DE REDACCIÓN — SIGUE ESTE ORDEN EXACTO
===================================================================

## 1. RESUMEN EJECUTIVO
Párrafo de 6-10 líneas: diagnóstico global, estado de conservación, \
distribución y naturaleza de anomalías, presencia de infraestructuras, zonas críticas, \
valoración del riesgo agregado para las instalaciones superficiales.

## 2. DATOS DE LA INSPECCIÓN
Tabla resumen con los parámetros del equipo y del perfil. Incluir \
frecuencia efectiva de las antenas LF y HF, resolución vertical teórica (λ/4), \
y penetración máxima estimada.

## 3. INTERPRETACIÓN IA DE RADARGRAMAS
Descripción general de la calidad de la señal a lo largo del perfil: \
zonas de buena penetración, zonas de atenuación, presencia de ruido de fondo, \
calidad del acoplamiento antena-suelo, y observaciones generales sobre la \
estratigrafía visible.

## 4. ANÁLISIS DE HUECOS Y CAVIDADES
Para CADA hueco (${huecos.map(h=>h.id).join(", ")||"ninguno"}), un párrafo individual con:
- **Firma GPR**: forma de hipérbola (apertura, amplitud, simetría, limpieza de flancos), \
presencia de FASE INVERTIDA (reflexión de fase contraria → hueco de aire/agua), \
ringing o reverberaciones múltiples, confirmación en canal HF, continuidad lateral
- **Clasificación de material del relleno**: basada en la atenuación posterior a la reflexión \
(hueco seco = alta amplitud + fase invertida limpia; hueco húmedo = amplitud moderada sin fase inv.)
- **Interpretación geológica**: cavidad kárstica, conducto colapsado, zona de sifonamiento, \
vacío antrópico, cámara de servicio, etc. Justificar con profundidad + material + firma GPR
- **Cálculo volumétrico**: volumen bruto y neto, semi-ejes, fiabilidad del cálculo para \
esta anomalía concreta, rango de incertidumbre estimado (±X%)
- **Nivel de riesgo justificado**: factores considerados (profundidad, volumen, carga \
superficial, probabilidad de colapso progresivo, consecuencias)
- **Coordenadas GPS** si disponibles

## 5. ANÁLISIS DE TUBERÍAS E INFRAESTRUCTURAS ENTERRADAS
Para CADA tubería (${tubos.map(t=>t.id).join(", ")||"ninguna"}):
- **Clasificación por material** (analiza la firma GPR y elige):
  • Metal/acero/fundición: reflexión FUERTE + ringing intenso + fase invertida + hipérbola definida
  • PVC/PEAD: reflexión moderada, SIN ringing, hipérbola menos definida, posible cama visible
  • Hormigón/fibrocemento: reflexión difusa, hipérbola amplia
  • Cable eléctrico: hipérbola muy estrecha (pequeño diámetro), reflexión puntual
  • Llena de agua: sin fase invertida; vacía: con fase invertida + ringing
- **Diámetro estimado** (si la resolución lo permite)
- **Orientación** respecto al eje de medida (transversal=hipérbola clásica; paralela=plana continua)
- **Estado aparente**: buen estado / deteriorada / posible fuga (difusión lateral en radargrama)

## 6. PUNTOS A REVISAR EN CAMPO
Tabla OBLIGATORIA con TODAS las anomalías que requieren verificación, ordenada por urgencia:

| Prioridad | ID | Dist. (m) | Prof. (m) | Tipo | Razón de ambigüedad | Acción recomendada |
|-----------|----|-----------|-----------|----- |---------------------|--------------------|
| URGENTE   | H1 | X.X       | X.X       | Hueco ALTO | Hipérbola clara, fase inv., vol >0.1m³ | Perforación Ø50mm |
| PREFERENTE| T1 | X.X       | X.X       | Tubería | Sin GPS, material incierto | Cruce con planos + EM |
| VIGILAR   | H3 | X.X       | X.X       | Hueco BAJO | Confianza <60%, posible artefacto | Repetir perfil |

Rellenar con los datos reales de las anomalías detectadas.

## 7. ARTEFACTOS E INTERFERENCIAS IDENTIFICADAS
Lista de reflexiones identificadas como NO reales, con criterio de discriminación:
- Ringing de superficie (reflexión repetitiva de la antena en la interfaz aire-suelo)
- Coupling aéreo (reflexión de objetos sobre la superficie durante el barrido)
- Hipérbolas de difracción múltiple por objetos próximos
- Zonas de apantallamiento (shadow zones) por conductores superficiales
- Reflexiones laterales (side-returns) por bordillos, paredes, canalizaciones adyacentes
Si no hay artefactos identificados, indicarlo explícitamente.

## 8. ANÁLISIS DE CONTINUIDAD LATERAL
- Distribución de anomalías a lo largo del perfil: ¿zonas de concentración? ¿patrón espacial?
- ¿Alguna anomalía se repite a intervalos regulares? → posible tubería longitudinal o junta
- ¿Hay reflexión horizontal continua? → posible nivel freático, interfaz de capa, solera
- Correlación entre tuberías y zonas de pérdida de finos o huecos adyacentes
- Mecanismo de degradación: puntual vs. sistémico

## 9. ESTIMACIÓN VOLUMÉTRICA
- Consistencia global del método Sanders con el material: ${ctx.material}
- Sensibilidad a la velocidad EM (${ctx.vel} m/ns): impacto de ±0.01 m/ns en profundidad y volumen
- Volumen bruto: ${totBruto.toFixed(4)} m³ | Neto: ${totNeto.toFixed(4)} m³ (f=${ctx.fSanders})
- Huecos con mayor incertidumbre volumétrica y razones técnicas
- Recomendación de ajuste de velocidad si procede (calibración con hipérbola conocida)

## 10. RIESGO GEOTÉCNICO
- Valoración del riesgo por anomalía y global
- Factores agravantes: profundidad <1m, vol >0.1m³, zona de tráfico pesado, \
cercanía a cimentaciones, suelo granular susceptible de sifonamiento
- Escenario de evolución probable sin intervención: estabilidad, colapso progresivo, \
hundimiento súbito

## 11. PLAN DE INTERVENCIÓN PRIORIZADO
Tabla ordenada por urgencia:

| Prioridad | ID/Zona | Dist. (m) | Actuación | Método técnico | Plazo |
|-----------|---------|-----------|-----------|----------------|-------|
| 1 | H_X | X.X | Relleno confirmado | Inyección resina expansiva | Inmediato |
| 2 | T_X | X.X | Identificación tubería | Detección EM + planos | <2 semanas |
| 3 | H_Y | X.X | Monitorización | Extensómetros + GPR 3 meses | Programado |

Métodos disponibles (usar los aplicables): inyección de resina expansiva bicomponente, \
lechada cementosa/microcemento, microsilícex, perforación de confirmación Ø50-100mm, \
excavación manual controlada, extensómetros/inclinómetros, \
repetición GPR con antena mayor frecuencia (900MHz/1.6GHz), tomografía ERT.

## 12. LIMITACIONES DEL MÉTODO GPR
- Incertidumbre en la velocidad EM y su impacto en profundidad y dimensiones
- Resolución vertical teórica (λ/4 a ${ctx.vel} m/ns): indicar para cada frecuencia
- Zonas de apantallamiento o reflexiones múltiples que pueden ocultar anomalías
- Condiciones del pavimento en el momento del ensayo
- Referencias normativas aplicables (UNE-EN ISO 22476, ASTM D6432, etc.)

## 13. CONCLUSIÓN TÉCNICA FINAL
Diagnóstico definitivo, zonas de máxima criticidad, valoración del riesgo global, \
y necesidad o no de actuación inmediata vs. programada.

---
REGLAS DE REDACCIÓN OBLIGATORIAS:
- Informe EXTENSO, TÉCNICO y RIGUROSO. Mínimo 1500 palabras.
- Cada anomalía recibe su propio párrafo numerado.
- Usar terminología geotécnica y GPR precisa.
- Redactar en TERCERA PERSONA IMPERSONAL.
- Si confianza < 60%: marcar con ⚠ "verificación necesaria en campo".
- NUNCA presentar ninguna interpretación como certeza absoluta.
- El apartado 6 (Puntos a revisar) es OBLIGATORIO aunque solo haya una anomalía.
- Si no hay tuberías: apartado 5 debe indicarlo con razón técnica.
- Disclaimer OBLIGATORIO al final del informe:
  "AVISO: La presente interpretación ha sido generada mediante inteligencia artificial \
como ayuda técnica. No sustituye la revisión de un técnico competente titulado ni \
las comprobaciones en campo. Las profundidades, dimensiones y volúmenes son aproximados \
y deben validarse mediante catas, perforaciones o técnicas complementarias. \
El responsable de la obra es el único con capacidad de validar estas conclusiones."`;
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\lib\georadar\buildPromptV2.ts" -ForegroundColor Green

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
  { name: "Georadar V2 ✦ IA", href: "/aplicaciones/georadar-v2", icon: Radar, screen: "apps_georadar_v2" },
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
Write-Host "    Escrito: src\components\layout\Sidebar.tsx" -ForegroundColor Green

$dst = "src\hooks\useRouteGuard.ts"
$content = @'
"use client";

import { useEffect } from "react";
import { useRouter, usePathname } from "next/navigation";
import { usePermissions } from "@/hooks/usePermissions";
import { useAuthStore } from "@/hooks/useAuth";

// Map URL paths to screen names
const PATH_TO_SCREEN: Record<string, string> = {
  "/dashboard": "dashboard",
  "/planificacion": "planificacion",
  "/obras": "obras",
  "/partes": "partes",
  "/aplicaciones/georadar": "apps_georadar",
  "/aplicaciones/georadar-v2": "apps_georadar_v2",
  "/maestros/recursos-humanos": "maestros_rrhh",
  "/almacen/articulos": "almacen_articulos",
  "/almacen/tipos-articulo": "almacen_tipos_articulo",
  "/almacen/almacenes": "almacen_almacenes",
  "/almacen/proveedores": "almacen_proveedores",
  "/almacen/movimientos": "almacen_movimientos",
  "/almacen/etiquetas": "almacen_etiquetas",
  "/maestros/vehiculos": "maestros_vehiculos",
  "/maestros/clientes": "maestros_clientes",
  "/maestros/estados-obra": "maestros_estados",
  "/maestros/tipos-trabajo": "maestros_tipos_trabajo",
  "/maestros/tipos-obra": "maestros_tipos_obra",
  "/maestros/contactos-leyna": "maestros_contactos_leyna",
  "/almacen/etiquetas": "almacen_etiquetas",
  "/logs": "logs",
  "/configuracion": "configuracion",
};

export function useRouteGuard() {
  const router = useRouter();
  const pathname = usePathname();
  const { user } = useAuthStore();
  const { canAccess, loaded } = usePermissions();

  useEffect(() => {
    if (!loaded || !user) return;

    // Find matching screen for current path
    const screen = Object.entries(PATH_TO_SCREEN).find(([path]) => pathname.startsWith(path))?.[1];
    if (!screen) return; // Unknown path, allow

    if (!canAccess(screen)) {
      router.replace("/dashboard");
    }
  }, [pathname, loaded, user, canAccess, router]);
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\hooks\useRouteGuard.ts" -ForegroundColor Green

$dst = "src\hooks\usePermissions.ts"
$content = @'
"use client";

import { useState, useEffect, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";

interface Permisos {
  pantalla: string;
  visible: boolean;
  crear: boolean;
  editar: boolean;
  eliminar: boolean;
  asignar: boolean;
}

// Default permissions per screen for non-configured roles
const DEFAULT_OPERARIO: Record<string, Partial<Permisos>> = {
  dashboard: { visible: true },
  partes: { visible: true, crear: true, editar: true },
  obras: { visible: true },
  planificacion: { visible: true },
};

export function usePermissions() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const [permisos, setPermisos] = useState<Permisos[]>([]);
  const [isAdminFromRole, setIsAdminFromRole] = useState(false);
  const [loaded, setLoaded] = useState(false);

  // Admin si el campo role = "admin" O si el rol vinculado tiene is_admin = true
  const isAdmin = user?.role === "admin" || isAdminFromRole;

  useEffect(() => {
    if (!user?.id) return;

    const fetchPermisos = async () => {
      // Leer rol_id y role actualizados desde la BD (no solo desde el store cacheado)
      const { data: userData } = await supabase
        .from("users")
        .select("rol_id, role")
        .eq("id", user.id)
        .single();

      if (!userData) { setLoaded(true); return; }

      // Comprobar si el rol vinculado es admin aunque users.role no diga "admin"
      if (userData.rol_id) {
        const { data: rolData } = await supabase
          .from("roles")
          .select("is_admin")
          .eq("id", userData.rol_id)
          .single();
        if (rolData?.is_admin) {
          setIsAdminFromRole(true);
          setLoaded(true);
          return;
        }
        // Si no es admin, cargar permisos granulares
        const { data } = await supabase
          .from("rol_permisos")
          .select("*")
          .eq("rol_id", userData.rol_id);
        setPermisos(data || []);
      }

      // Fallback: users.role = "admin" ya lo cubre isAdmin arriba
      setLoaded(true);
    };

    fetchPermisos();
  }, [user?.id]);

  const canAccess = useCallback((pantalla: string): boolean => {
    if (isAdmin) return true;
    const perm = permisos.find((p) => p.pantalla === pantalla);
    if (perm) return perm.visible;
    // Fallback to defaults for operario
    return DEFAULT_OPERARIO[pantalla]?.visible || false;
  }, [isAdmin, permisos]);

  const canDo = useCallback((pantalla: string, action: "crear" | "editar" | "eliminar" | "asignar"): boolean => {
    if (isAdmin) return true;
    const perm = permisos.find((p) => p.pantalla === pantalla);
    if (perm) return !!(perm as any)[action];
    return !!(DEFAULT_OPERARIO[pantalla] as any)?.[action] || false;
  }, [isAdmin, permisos]);

  // Screens that should appear in the sidebar
  const visibleScreens = useCallback((): Set<string> => {
    if (isAdmin) return new Set(["dashboard", "planificacion", "obras", "partes",
      "apps_georadar", "apps_georadar_v2",
      "almacen_articulos", "almacen_tipos_articulo", "almacen_almacenes", "almacen_proveedores", "almacen_movimientos", "almacen_etiquetas",
      "maestros_rrhh", "maestros_vehiculos",
      "maestros_clientes", "maestros_estados", "maestros_tipos_trabajo", "maestros_tipos_obra", "maestros_contactos_leyna", "almacen_etiquetas",
      "logs", "configuracion"]);

    const screens = new Set<string>();
    // From DB permissions
    permisos.forEach((p) => { if (p.visible) screens.add(p.pantalla); });
    // Always add defaults
    Object.entries(DEFAULT_OPERARIO).forEach(([k, v]) => { if (v.visible) screens.add(k); });
    return screens;
  }, [isAdmin, permisos]);

  return { isAdmin, canAccess, canDo, visibleScreens, loaded };
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\hooks\usePermissions.ts" -ForegroundColor Green

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
  { id: "apps_georadar_v2", label: "Georadar V2 (IA)" },
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
Write-Host "    Escrito: src\app\configuracion\page.tsx" -ForegroundColor Green

Write-Host ""
Write-Host "==> Verificando" -ForegroundColor Cyan
$ok1 = Test-Path (Join-Path $RepoPath "src\app\aplicaciones\georadar-v2\page.tsx")
$ok2 = Test-Path (Join-Path $RepoPath "src\lib\georadar\buildPromptV2.ts")
$ok3 = Select-String -Path "src\components\layout\Sidebar.tsx" -Pattern "georadar-v2" -Quiet
if ($ok1) { Write-Host "    OK: pagina Georadar V2 creada" -ForegroundColor Green }
else { Write-Host "    ERROR" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: buildPromptV2.ts creado" -ForegroundColor Green }
else { Write-Host "    ERROR" -ForegroundColor Red }
if ($ok3) { Write-Host "    OK: entrada en Sidebar" -ForegroundColor Green }
else { Write-Host "    ERROR" -ForegroundColor Red }
Write-Host ""
Write-Host '  git add -A'
Write-Host '  git commit -m "feat: Georadar V2 con IA avanzada, prompt mejorado, API Key local"'
Write-Host '  git push'
Write-Host ""
Write-Host "Tras el deploy:" -ForegroundColor Cyan
Write-Host "  1. Ve a /aplicaciones/georadar-v2"
Write-Host "  2. Haz clic en 'Configurar API Key' e introduce tu clave de Anthropic"
Write-Host "  3. Anade anomalias y pulsa 'Interpretar con IA'"
