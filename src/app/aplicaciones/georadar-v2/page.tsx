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