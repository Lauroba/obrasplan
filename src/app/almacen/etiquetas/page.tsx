"use client";
import { useState, useEffect, useCallback, useRef } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import {
  Tag, Loader2, Plus, Pencil, Trash2, Eye, Printer,
  Copy, Package, RefreshCw, ChevronDown, Check,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import QRCode from "qrcode";

const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

const CAMPOS_DISPONIBLES = [
  { id: "nombre",               label: "Nombre artículo" },
  { id: "codigo_articulo",      label: "Código artículo" },
  { id: "codigo_barras",        label: "Código de barras (texto)" },
  { id: "referencia_proveedor", label: "Ref. proveedor" },
  { id: "proveedor",            label: "Proveedor" },
  { id: "tipo",                 label: "Tipo" },
  { id: "unidad",               label: "Unidad" },
  { id: "stock_minimo",         label: "Stock mínimo" },
  { id: "qr",                   label: "Código QR (imagen)" },
];

const TAMANIOS_PRESET = [
  { label: "Avery L7160 (3×7 = 21/hoja)", ancho: 63.5, alto: 38.1, cols: 3, filas: 7 },
  { label: "Avery L7163 (2×7 = 14/hoja)", ancho: 99.1, alto: 38.1, cols: 2, filas: 7 },
  { label: "Grande (2×4 = 8/hoja)",        ancho: 105,  alto: 74.25, cols: 2, filas: 4 },
  { label: "A6 individual",                ancho: 140,  alto: 97,   cols: 1, filas: 1 },
  { label: "Personalizado",                ancho: 0,    alto: 0,    cols: 0, filas: 0 },
];

const emptyPlantilla = {
  nombre: "", descripcion: "",
  hoja_ancho_mm: 210, hoja_alto_mm: 297,
  etiq_ancho_mm: 63.5, etiq_alto_mm: 38.1,
  etiq_cols: 3, etiq_filas: 7,
  margen_h_mm: 0, margen_v_mm: 0,
  espacio_h_mm: 0, espacio_v_mm: 0,
  campos: ["qr", "nombre", "codigo_articulo", "referencia_proveedor"],
  qr_size_pct: 45, font_size: 7, mostrar_borde: true,
};

// ============================================================
// Componente de previsualización de una etiqueta
// ============================================================
function EtiquetaPreview({ plantilla, articulo, qrDataUrl }: {
  plantilla: typeof emptyPlantilla;
  articulo: any;
  qrDataUrl: string;
}) {
  const mm2px = (mm: number) => mm * 3.7795; // 1mm ≈ 3.7795px a 96dpi
  const w = mm2px(plantilla.etiq_ancho_mm);
  const h = mm2px(plantilla.etiq_alto_mm);
  const qrPx = mm2px(plantilla.etiq_ancho_mm * plantilla.qr_size_pct / 100);

  const textFields = plantilla.campos.filter((c) => c !== "qr");
  const showQr = plantilla.campos.includes("qr") && qrDataUrl;

  const getVal = (field: string) => {
    const map: Record<string, string> = {
      nombre: articulo?.nombre || "Nombre artículo",
      codigo_articulo: articulo?.codigo_articulo || "COD-001",
      codigo_barras: articulo?.codigo_barras || "1234567890",
      referencia_proveedor: articulo?.referencia_proveedor || "REF-001",
      proveedor: articulo?.proveedor?.nombre || "Proveedor",
      tipo: articulo?.tipo || "Material",
      unidad: articulo?.unidad || "ud",
      stock_minimo: `Mín: ${articulo?.stock_minimo ?? 0}`,
    };
    return map[field] || field;
  };

  return (
    <div
      style={{
        width: w, height: h,
        border: plantilla.mostrar_borde ? "1px solid #ccc" : "none",
        borderRadius: 2,
        display: "flex",
        flexDirection: "row",
        alignItems: "stretch",
        overflow: "hidden",
        backgroundColor: "white",
        fontFamily: "Arial, sans-serif",
        fontSize: plantilla.font_size,
      }}>
      {/* QR a la izquierda */}
      {showQr && (
        <div style={{ width: qrPx, display: "flex", alignItems: "center", justifyContent: "center", padding: 3, flexShrink: 0 }}>
          <img src={qrDataUrl} alt="QR" style={{ width: "100%", height: "auto" }} />
        </div>
      )}
      {/* Campos de texto a la derecha */}
      <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", padding: "3px 4px", gap: 1, overflow: "hidden" }}>
        {textFields.map((field) => (
          <div key={field} style={{ fontSize: plantilla.font_size, lineHeight: 1.2, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
            {getVal(field)}
          </div>
        ))}
      </div>
    </div>
  );
}

// ============================================================
// PÁGINA PRINCIPAL
// ============================================================
export default function EtiquetasPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const isAdmin = user?.role === "admin";

  const [plantillas, setPlantillas] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [articulos, setArticulos] = useState<any[]>([]);
  const [articuloSel, setArticuloSel] = useState<any>(null);
  const [qrDataUrl, setQrDataUrl] = useState("");

  // Modal de editor de plantilla
  const [editorOpen, setEditorOpen] = useState(false);
  const [form, setForm] = useState(emptyPlantilla);
  const [editId, setEditId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [presetIdx, setPresetIdx] = useState(0);

  // Modal de impresión
  const [printOpen, setPrintOpen] = useState(false);
  const [printPlantilla, setPrintPlantilla] = useState<any>(null);
  const [printCantidad, setPrintCantidad] = useState(1);
  const printRef = useRef<HTMLDivElement>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [pR, aR] = await Promise.all([
      (supabase.from("etiquetas_plantillas") as any).select("*").eq("activo", true).order("created_at"),
      (supabase.from("articulos") as any).select("id, nombre, codigo_articulo, codigo_barras, referencia_proveedor, tipo, unidad, stock_minimo, proveedor:proveedores(nombre)").eq("activo", true).order("nombre").limit(500),
    ]);
    setPlantillas(pR.data || []);
    setArticulos(aR.data || []);
    if (aR.data?.[0]) setArticuloSel(aR.data[0]);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  // Generar QR cuando cambia el artículo seleccionado
  useEffect(() => {
    const codigo = articuloSel?.codigo_articulo || articuloSel?.codigo_barras || "SIN-CODIGO";
    QRCode.toDataURL(codigo, { width: 200, margin: 1 }).then(setQrDataUrl).catch(console.error);
  }, [articuloSel]);

  const openNew = () => {
    setForm(emptyPlantilla); setEditId(null); setError(null);
    setPresetIdx(0); setEditorOpen(true);
  };

  const openEdit = (p: any) => {
    setForm({
      nombre: p.nombre, descripcion: p.descripcion || "",
      hoja_ancho_mm: p.hoja_ancho_mm, hoja_alto_mm: p.hoja_alto_mm,
      etiq_ancho_mm: p.etiq_ancho_mm, etiq_alto_mm: p.etiq_alto_mm,
      etiq_cols: p.etiq_cols, etiq_filas: p.etiq_filas,
      margen_h_mm: p.margen_h_mm, margen_v_mm: p.margen_v_mm,
      espacio_h_mm: p.espacio_h_mm, espacio_v_mm: p.espacio_v_mm,
      campos: p.campos || [],
      qr_size_pct: p.qr_size_pct, font_size: p.font_size,
      mostrar_borde: p.mostrar_borde,
    });
    setEditId(p.id); setError(null); setPresetIdx(4); setEditorOpen(true);
  };

  const openDuplicate = (p: any) => {
    openEdit({ ...p, id: undefined });
    setEditId(null);
    setForm((f) => ({ ...f, nombre: f.nombre + " (copia)" }));
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.nombre.trim()) { setError("El nombre es obligatorio"); return; }
    setSaving(true); setError(null);
    try {
      const payload = { ...form, created_by: user?.id };
      if (editId) {
        const { error: err } = await (supabase.from("etiquetas_plantillas") as any).update(payload).eq("id", editId);
        if (err) throw err;
      } else {
        const { error: err } = await (supabase.from("etiquetas_plantillas") as any).insert(payload);
        if (err) throw err;
      }
      setEditorOpen(false); fetchData();
    } catch (err: any) { setError(err.message); }
    finally { setSaving(false); }
  };

  const handleDelete = async (p: any) => {
    if (!confirm(`¿Eliminar la plantilla "${p.nombre}"?`)) return;
    await (supabase.from("etiquetas_plantillas") as any).update({ activo: false }).eq("id", p.id);
    fetchData();
  };

  const applyPreset = (idx: number) => {
    setPresetIdx(idx);
    const preset = TAMANIOS_PRESET[idx];
    if (preset.ancho > 0) {
      setForm((f) => ({
        ...f,
        etiq_ancho_mm: preset.ancho, etiq_alto_mm: preset.alto,
        etiq_cols: preset.cols, etiq_filas: preset.filas,
      }));
    }
  };

  const toggleCampo = (campo: string) => {
    setForm((f) => ({
      ...f,
      campos: f.campos.includes(campo)
        ? f.campos.filter((c) => c !== campo)
        : [...f.campos, campo],
    }));
  };

  const handlePrint = (p: any) => {
    setPrintPlantilla(p);
    setPrintCantidad(p.etiq_cols * p.etiq_filas);
    setPrintOpen(true);
  };

  const doPrint = async () => {
    if (!printRef.current || !printPlantilla || !articuloSel) return;

    const mm2px = (mm: number) => mm * 3.7795;
    const plantilla = { ...emptyPlantilla, ...printPlantilla };

    // Generar QR para el artículo seleccionado
    const codigo = articuloSel.codigo_articulo || articuloSel.codigo_barras || "SIN-CODIGO";
    const qr = await QRCode.toDataURL(codigo, { width: 300, margin: 1 });

    // Construir HTML de impresión
    const etiqW = mm2px(plantilla.etiq_ancho_mm);
    const etiqH = mm2px(plantilla.etiq_alto_mm);
    const qrPx  = mm2px(plantilla.etiq_ancho_mm * plantilla.qr_size_pct / 100);
    const showQr = plantilla.campos.includes("qr");
    const textFields = plantilla.campos.filter((c: string) => c !== "qr");

    const getVal = (field: string) => {
      const map: Record<string, string> = {
        nombre: articuloSel.nombre || "",
        codigo_articulo: articuloSel.codigo_articulo || "",
        codigo_barras: articuloSel.codigo_barras || "",
        referencia_proveedor: articuloSel.referencia_proveedor || "",
        proveedor: articuloSel.proveedor?.nombre || "",
        tipo: articuloSel.tipo || "",
        unidad: articuloSel.unidad || "",
        stock_minimo: `Mín: ${articuloSel.stock_minimo ?? 0}`,
      };
      return map[field] || field;
    };

    const etiqHTML = `
      <div style="width:${etiqW}px;height:${etiqH}px;display:flex;flex-direction:row;align-items:stretch;overflow:hidden;border:${plantilla.mostrar_borde ? "1px solid #999" : "none"};box-sizing:border-box;">
        ${showQr ? `<div style="width:${qrPx}px;display:flex;align-items:center;justify-content:center;padding:2px;flex-shrink:0;"><img src="${qr}" style="width:100%;height:auto;" /></div>` : ""}
        <div style="flex:1;display:flex;flex-direction:column;justify-content:center;padding:2px 4px;gap:1px;overflow:hidden;font-family:Arial,sans-serif;font-size:${plantilla.font_size}px;">
          ${textFields.map((f: string) => `<div style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:1.2;">${getVal(f)}</div>`).join("")}
        </div>
      </div>`;

    const marginH = mm2px(plantilla.margen_h_mm);
    const marginV = mm2px(plantilla.margen_v_mm);
    const gapH    = mm2px(plantilla.espacio_h_mm);
    const gapV    = mm2px(plantilla.espacio_v_mm);
    const total   = Math.min(printCantidad, plantilla.etiq_cols * plantilla.etiq_filas);

    let grid = `<div style="display:grid;grid-template-columns:repeat(${plantilla.etiq_cols},${etiqW}px);gap:${gapV}px ${gapH}px;padding:${marginV}px ${marginH}px;width:${mm2px(plantilla.hoja_ancho_mm)}px;">`;
    for (let i = 0; i < total; i++) grid += etiqHTML;
    grid += "</div>";

    const win = window.open("", "_blank", "width=900,height=700");
    if (!win) return;
    win.document.write(`<!DOCTYPE html><html><head><title>Etiquetas</title><style>@page{margin:0}body{margin:0;padding:0}</style></head><body>${grid}</body></html>`);
    win.document.close();
    setTimeout(() => { win.print(); }, 500);
  };

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <Tag className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">Diseñador de etiquetas</h1>
              <p className="text-sm text-surface-500">{plantillas.length} plantillas guardadas</p>
            </div>
          </div>
          {isAdmin && (
            <button onClick={openNew}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
              <Plus className="w-4 h-4" />Nueva plantilla
            </button>
          )}
        </div>

        {/* Selector de artículo para previsualización */}
        <div className="card p-4 mb-4 flex items-center gap-4 flex-wrap">
          <span className="text-sm font-medium text-surface-700 shrink-0">Previsualizar con:</span>
          <select className={cn(ic, "flex-1 min-w-48")}
            value={articuloSel?.id || ""}
            onChange={(e) => setArticuloSel(articulos.find((a) => a.id === e.target.value) || null)}>
            {articulos.map((a) => (
              <option key={a.id} value={a.id}>{a.nombre} — {a.codigo_articulo}</option>
            ))}
          </select>
        </div>

        {/* Lista de plantillas */}
        {loading ? (
          <div className="flex justify-center py-12"><Loader2 className="w-6 h-6 text-brand-500 animate-spin" /></div>
        ) : plantillas.length === 0 ? (
          <div className="card text-center py-12 text-sm text-surface-400">
            <Tag className="w-8 h-8 mx-auto mb-2 opacity-30" />
            Sin plantillas. Crea una nueva para empezar.
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {plantillas.map((p) => (
              <div key={p.id} className="card p-4 flex flex-col gap-3">
                {/* Cabecera */}
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <p className="font-semibold text-surface-900 text-sm">{p.nombre}</p>
                    {p.descripcion && <p className="text-xs text-surface-500 mt-0.5">{p.descripcion}</p>}
                  </div>
                  {isAdmin && (
                    <div className="flex items-center gap-1 shrink-0">
                      <button onClick={() => openEdit(p)} title="Editar"
                        className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100"><Pencil className="w-3.5 h-3.5" /></button>
                      <button onClick={() => openDuplicate(p)} title="Duplicar"
                        className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100"><Copy className="w-3.5 h-3.5" /></button>
                      <button onClick={() => handleDelete(p)} title="Eliminar"
                        className="p-1.5 rounded-lg text-surface-400 hover:bg-red-50 hover:text-red-500"><Trash2 className="w-3.5 h-3.5" /></button>
                    </div>
                  )}
                </div>

                {/* Info tamaño */}
                <div className="text-[11px] text-surface-500 flex flex-wrap gap-2">
                  <span>{p.etiq_ancho_mm}×{p.etiq_alto_mm}mm</span>
                  <span>·</span>
                  <span>{p.etiq_cols}×{p.etiq_filas} = {p.etiq_cols * p.etiq_filas} etiq./hoja</span>
                  <span>·</span>
                  <span>QR {p.qr_size_pct}%</span>
                </div>

                {/* Previsualización */}
                <div className="flex justify-center py-2 bg-surface-50 rounded-lg overflow-hidden">
                  <div style={{ transform: "scale(0.9)", transformOrigin: "center" }}>
                    <EtiquetaPreview
                      plantilla={{ ...emptyPlantilla, ...p }}
                      articulo={articuloSel}
                      qrDataUrl={qrDataUrl}
                    />
                  </div>
                </div>

                {/* Campos incluidos */}
                <div className="flex flex-wrap gap-1">
                  {(p.campos || []).map((c: string) => {
                    const def = CAMPOS_DISPONIBLES.find((d) => d.id === c);
                    return <span key={c} className="badge text-[9px] bg-brand-50 text-brand-600">{def?.label || c}</span>;
                  })}
                </div>

                {/* Botón imprimir */}
                <button onClick={() => handlePrint(p)}
                  className="flex items-center justify-center gap-2 w-full py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
                  <Printer className="w-4 h-4" />Imprimir etiquetas
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* ============================================================
          MODAL EDITOR DE PLANTILLA
      ============================================================ */}
      <Modal open={editorOpen} onClose={() => setEditorOpen(false)}
        title={editId ? "Editar plantilla" : "Nueva plantilla"} size="lg">
        <form onSubmit={handleSave} className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2">
              <label className="block text-xs font-medium text-surface-600 mb-1">Nombre de la plantilla *</label>
              <input required className={ic} value={form.nombre}
                onChange={(e) => setForm({ ...form, nombre: e.target.value })} />
            </div>
            <div className="col-span-2">
              <label className="block text-xs font-medium text-surface-600 mb-1">Descripción</label>
              <input className={ic} value={form.descripcion}
                onChange={(e) => setForm({ ...form, descripcion: e.target.value })} />
            </div>
          </div>

          {/* Tamaño preset */}
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-2">Tamaño de etiqueta</label>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
              {TAMANIOS_PRESET.map((preset, idx) => (
                <button key={idx} type="button" onClick={() => applyPreset(idx)}
                  className={cn("flex items-center gap-2 px-3 py-2 rounded-lg border text-xs text-left transition-colors",
                    presetIdx === idx ? "border-brand-500 bg-brand-50 text-brand-700" : "border-surface-200 text-surface-600 hover:bg-surface-50")}>
                  {presetIdx === idx && <Check className="w-3.5 h-3.5 shrink-0" />}
                  {preset.label}
                </button>
              ))}
            </div>
          </div>

          {/* Dimensiones manuales */}
          <div className="grid grid-cols-4 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Ancho etiq. (mm)</label>
              <input type="number" step="0.1" className={ic} value={form.etiq_ancho_mm}
                onChange={(e) => { setPresetIdx(4); setForm({ ...form, etiq_ancho_mm: parseFloat(e.target.value) || 0 }); }} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Alto etiq. (mm)</label>
              <input type="number" step="0.1" className={ic} value={form.etiq_alto_mm}
                onChange={(e) => { setPresetIdx(4); setForm({ ...form, etiq_alto_mm: parseFloat(e.target.value) || 0 }); }} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Columnas</label>
              <input type="number" min="1" max="10" className={ic} value={form.etiq_cols}
                onChange={(e) => { setPresetIdx(4); setForm({ ...form, etiq_cols: parseInt(e.target.value) || 1 }); }} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Filas</label>
              <input type="number" min="1" max="20" className={ic} value={form.etiq_filas}
                onChange={(e) => { setPresetIdx(4); setForm({ ...form, etiq_filas: parseInt(e.target.value) || 1 }); }} /></div>
          </div>

          {/* Márgenes y espaciados */}
          <div className="grid grid-cols-4 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Margen H (mm)</label>
              <input type="number" step="0.1" className={ic} value={form.margen_h_mm}
                onChange={(e) => setForm({ ...form, margen_h_mm: parseFloat(e.target.value) || 0 })} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Margen V (mm)</label>
              <input type="number" step="0.1" className={ic} value={form.margen_v_mm}
                onChange={(e) => setForm({ ...form, margen_v_mm: parseFloat(e.target.value) || 0 })} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Espacio H (mm)</label>
              <input type="number" step="0.1" className={ic} value={form.espacio_h_mm}
                onChange={(e) => setForm({ ...form, espacio_h_mm: parseFloat(e.target.value) || 0 })} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Espacio V (mm)</label>
              <input type="number" step="0.1" className={ic} value={form.espacio_v_mm}
                onChange={(e) => setForm({ ...form, espacio_v_mm: parseFloat(e.target.value) || 0 })} /></div>
          </div>

          {/* Campos a incluir */}
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-2">Campos a mostrar</label>
            <div className="grid grid-cols-2 gap-1.5">
              {CAMPOS_DISPONIBLES.map((campo) => (
                <label key={campo.id}
                  className={cn("flex items-center gap-2 px-3 py-2 rounded-lg border cursor-pointer text-xs transition-colors",
                    form.campos.includes(campo.id) ? "border-brand-500 bg-brand-50 text-brand-700" : "border-surface-200 text-surface-600 hover:bg-surface-50")}>
                  <input type="checkbox" className="hidden" checked={form.campos.includes(campo.id)}
                    onChange={() => toggleCampo(campo.id)} />
                  {form.campos.includes(campo.id) && <Check className="w-3.5 h-3.5 shrink-0" />}
                  {campo.label}
                </label>
              ))}
            </div>
          </div>

          {/* Opciones visuales */}
          <div className="grid grid-cols-3 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Tamaño QR (%)</label>
              <input type="number" min="20" max="80" className={ic} value={form.qr_size_pct}
                onChange={(e) => setForm({ ...form, qr_size_pct: parseInt(e.target.value) || 40 })} /></div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Tamaño texto (px)</label>
              <input type="number" min="5" max="14" className={ic} value={form.font_size}
                onChange={(e) => setForm({ ...form, font_size: parseInt(e.target.value) || 8 })} /></div>
            <div className="flex items-end pb-1">
              <label className="flex items-center gap-2 cursor-pointer text-xs text-surface-700">
                <input type="checkbox" className="w-4 h-4" checked={form.mostrar_borde}
                  onChange={(e) => setForm({ ...form, mostrar_borde: e.target.checked })} />
                Mostrar borde
              </label>
            </div>
          </div>

          {/* Previsualización en tiempo real */}
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-2">Previsualización</label>
            <div className="flex justify-center py-4 bg-surface-50 rounded-lg">
              <EtiquetaPreview plantilla={form} articulo={articuloSel} qrDataUrl={qrDataUrl} />
            </div>
          </div>

          {error && <p className="text-xs text-red-600">{error}</p>}
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setEditorOpen(false)}
              className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {saving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}Guardar plantilla
            </button>
          </div>
        </form>
      </Modal>

      {/* ============================================================
          MODAL DE IMPRESIÓN
      ============================================================ */}
      <Modal open={printOpen} onClose={() => setPrintOpen(false)} title="Imprimir etiquetas" size="md">
        {printPlantilla && articuloSel && (
          <div className="space-y-4">
            <div>
              <label className="block text-xs font-medium text-surface-600 mb-1">Artículo</label>
              <select className={ic} value={articuloSel.id}
                onChange={(e) => setArticuloSel(articulos.find((a) => a.id === e.target.value))}>
                {articulos.map((a) => <option key={a.id} value={a.id}>{a.nombre} — {a.codigo_articulo}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-600 mb-1">
                Cantidad de etiquetas (máx. {printPlantilla.etiq_cols * printPlantilla.etiq_filas}/hoja)
              </label>
              <input type="number" min="1" max={printPlantilla.etiq_cols * printPlantilla.etiq_filas}
                className={ic} value={printCantidad}
                onChange={(e) => setPrintCantidad(Math.min(parseInt(e.target.value) || 1, printPlantilla.etiq_cols * printPlantilla.etiq_filas))} />
            </div>
            <div className="flex justify-center py-4 bg-surface-50 rounded-lg">
              <EtiquetaPreview plantilla={{ ...emptyPlantilla, ...printPlantilla }} articulo={articuloSel} qrDataUrl={qrDataUrl} />
            </div>
            <div className="flex justify-end gap-2">
              <button onClick={() => setPrintOpen(false)}
                className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
              <button onClick={doPrint}
                className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
                <Printer className="w-4 h-4" />Abrir para imprimir
              </button>
            </div>
          </div>
        )}
      </Modal>
    </AppLayout>
  );
}