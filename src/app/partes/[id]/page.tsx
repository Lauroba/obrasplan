"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { useParams } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import SignatureCanvas from "@/components/partes/SignatureCanvas";
import AudioRecorder from "@/components/partes/AudioRecorder";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import type { ParteDiario, ParteLinea, Documento, ParteAudio } from "@/lib/types/database";
import {
  ClipboardList, ArrowLeft, Loader2, Download, Upload, Trash2, FileText,
  Image as ImageIcon, File, CheckCircle2, Clock, Save, ExternalLink
} from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils/cn";

export default function ParteDetallePage() {
  const { id } = useParams<{ id: string }>();
  const { user } = useAuthStore();
  const supabase = createClient();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [parte, setParte] = useState<ParteDiario | null>(null);
  const [lineas, setLineas] = useState<ParteLinea[]>([]);
  const [documentos, setDocumentos] = useState<Documento[]>([]);
  const [audios, setAudios] = useState<ParteAudio[]>([]);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [observaciones, setObservaciones] = useState("");
  const [obsChanged, setObsChanged] = useState(false);
  const [obsSaving, setObsSaving] = useState(false);
  const [firmaResp, setFirmaResp] = useState<string | null>(null);
  const [firmaCliente, setFirmaCliente] = useState<string | null>(null);
  const [firmaSaving, setFirmaSaving] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [parteR, lineasR, docsR, audiosR] = await Promise.all([
      supabase.from("partes_diarios").select("*, obra:obras(nombre, color, ubicacion), creator:users!partes_diarios_created_by_fkey(nombre)").eq("id", id).single(),
      supabase.from("parte_lineas").select("*, tipo_trabajo:tipos_trabajo(nombre)").eq("parte_id", id).order("orden"),
      supabase.from("documentos").select("*").eq("parte_id", id).order("created_at", { ascending: false }),
      supabase.from("parte_audios").select("*").eq("parte_id", id).order("created_at", { ascending: false }),
    ]);
    const p = parteR.data as ParteDiario | null;
    setParte(p);
    setObservaciones(p?.observaciones || "");
    setObsChanged(false);
    setFirmaResp(p?.firma_data || null);
    setFirmaCliente(p?.firma_cliente || null);
    setLineas((lineasR.data as ParteLinea[]) || []);
    setDocumentos((docsR.data as Documento[]) || []);
    setAudios((audiosR.data as ParteAudio[]) || []);
    setLoading(false);
  }, [id]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const isPendiente = parte?.estado === "pendiente" || parte?.estado === "borrador";

  // Handle audio transcription — append to observaciones
  const handleTranscription = async (audioLabel: string, text: string) => {
    const newObs = observaciones
      ? `${observaciones}\n\n[${audioLabel}]: ${text}`
      : `[${audioLabel}]: ${text}`;
    setObservaciones(newObs);
    // Auto-save transcription
    await supabase.from("partes_diarios").update({ observaciones: newObs } as any).eq("id", id);
  };

  const handleSaveObservaciones = async () => {
    setObsSaving(true);
    await supabase.from("partes_diarios").update({ observaciones } as any).eq("id", id);
    setObsSaving(false);
    setObsChanged(false);
  };

  const handleSaveFirmas = async () => {
    setFirmaSaving(true);
    const update: Record<string, any> = { firma_data: firmaResp, firma_cliente: firmaCliente };
    if (firmaResp || firmaCliente) update.estado = "firmado";
    await supabase.from("partes_diarios").update(update as any).eq("id", id);
    setFirmaSaving(false);
    fetchData();
  };

  const handleUploadFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    setUploading(true);
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const path = `partes/${id}/${Date.now()}_${file.name}`;
      const isImage = file.type.startsWith("image/");
      const isPdf = file.type === "application/pdf";
      const { error } = await supabase.storage.from("documentos").upload(path, file);
      if (error) continue;
      await supabase.from("documentos").insert({
        obra_id: parte?.obra_id || null, parte_id: id,
        nombre_archivo: file.name, tipo: isImage ? "foto" : isPdf ? "pdf" : "documento",
        categoria: "general", storage_path: path, tamano: file.size, mime_type: file.type, uploaded_by: user?.id,
      });
    }
    setUploading(false);
    if (fileInputRef.current) fileInputRef.current.value = "";
    fetchData();
  };

  const handleOpenDoc = async (doc: Documento) => {
    const { data } = await supabase.storage.from("documentos").createSignedUrl(doc.storage_path, 300);
    if (data?.signedUrl) window.open(data.signedUrl, "_blank");
  };

  const handleDeleteDoc = async (doc: Documento) => {
    await supabase.storage.from("documentos").remove([doc.storage_path]);
    await supabase.from("documentos").delete().eq("id", doc.id);
    fetchData();
  };

  const formatBytes = (b: number | null) => { if (!b) return ""; if (b < 1024) return b + " B"; if (b < 1048576) return (b / 1024).toFixed(0) + " KB"; return (b / 1048576).toFixed(1) + " MB"; };

  if (loading) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;
  if (!parte) return <AppLayout><div className="text-center py-20"><p className="text-surface-500">Parte no encontrado</p></div></AppLayout>;

  const estadoBadge: Record<string, { label: string; class: string }> = {
    borrador: { label: "Borrador", class: "bg-surface-200 text-surface-700" },
    pendiente: { label: "Pendiente", class: "bg-amber-100 text-amber-700" },
    firmado: { label: "Firmado", class: "bg-emerald-100 text-emerald-700" },
  };
  const est = estadoBadge[parte.estado] || estadoBadge.pendiente;
  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  return (
    <AppLayout>
      <div className="max-w-4xl mx-auto animate-fade-in">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <Link href="/partes" className="p-2 rounded-lg text-surface-400 hover:bg-surface-100"><ArrowLeft className="w-5 h-5" /></Link>
            <div className="w-10 h-10 rounded-lg bg-orange-50 flex items-center justify-center"><ClipboardList className="w-5 h-5 text-orange-600" /></div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">
                Parte — {new Date(parte.fecha).toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" })}
              </h1>
              <p className="text-sm text-surface-500">{(parte as any).obra?.nombre || "Sin obra"} · {(parte as any).creator?.nombre}</p>
            </div>
          </div>
          <span className={cn("badge text-sm", est.class)}>{est.label}</span>
        </div>

        <div className="space-y-6">
          {/* Cabecera */}
          <div className="card p-6">
            <h2 className="text-sm font-semibold text-surface-900 mb-4">Datos del parte</h2>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
              {[
                { label: "Fecha", value: new Date(parte.fecha).toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "long", year: "numeric" }) },
                { label: "Obra", value: (parte as any).obra?.nombre || "Sin obra" },
                { label: "Dirección", value: parte.direccion },
                { label: "Localidad", value: parte.localidad },
                { label: "Provincia", value: parte.provincia },
                { label: "Jefe de obra", value: parte.jefe_obra },
                { label: "Encargado", value: parte.encargado_obra },
                { label: "Responsable", value: parte.responsable_empresa },
                { label: "Creado por", value: (parte as any).creator?.nombre },
              ].map((f) => (
                <div key={f.label}><p className="text-[10px] font-semibold text-surface-400 uppercase">{f.label}</p><p className="text-sm text-surface-900 mt-0.5">{f.value || "—"}</p></div>
              ))}
            </div>
          </div>

          {/* Relación de trabajos */}
          <div className="card p-6">
            <h2 className="text-sm font-semibold text-surface-900 mb-4">Relación de Trabajos / Materiales</h2>
            {lineas.length === 0 ? (
              <p className="text-sm text-surface-400 text-center py-4">Sin líneas de trabajo</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead><tr className="border-b border-surface-200">
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Concepto</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Tipo</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Fabricante</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Producto</th>
                    <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Cant.</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Uds.</th>
                  </tr></thead>
                  <tbody>{lineas.map((l) => (
                    <tr key={l.id} className="border-b border-surface-50">
                      <td className="py-2 px-2 font-medium text-surface-900">{l.concepto}</td>
                      <td className="py-2 px-2 text-surface-600">{(l as any).tipo_trabajo?.nombre || "—"}</td>
                      <td className="py-2 px-2 text-surface-600">{l.fabricante || "—"}</td>
                      <td className="py-2 px-2 text-surface-600">{l.producto || "—"}</td>
                      <td className="py-2 px-2 text-right text-surface-900 font-medium">{l.cantidad || "—"}</td>
                      <td className="py-2 px-2 text-surface-600">{l.unidades || "—"}</td>
                    </tr>
                  ))}</tbody>
                </table>
              </div>
            )}
          </div>

          {/* Observaciones — editable */}
          <div className="card p-6">
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-sm font-semibold text-surface-900">Observaciones</h2>
              {obsChanged && (
                <button onClick={handleSaveObservaciones} disabled={obsSaving}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
                  {obsSaving ? <Loader2 className="w-3 h-3 animate-spin" /> : <Save className="w-3 h-3" />} Guardar
                </button>
              )}
            </div>
            <textarea value={observaciones}
              onChange={(e) => { setObservaciones(e.target.value); setObsChanged(true); }}
              rows={5} placeholder="Observaciones, incidencias, transcripciones de audio..."
              className={ic + " resize-y font-mono text-xs"} />
          </div>

          {/* Firmas */}
          <div className="card p-6">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-sm font-semibold text-surface-900">Firmas</h2>
              {isPendiente && (firmaResp !== parte.firma_data || firmaCliente !== parte.firma_cliente) && (
                <button onClick={handleSaveFirmas} disabled={firmaSaving}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-white bg-emerald-500 rounded-lg hover:bg-emerald-600 disabled:opacity-60">
                  {firmaSaving ? <Loader2 className="w-3 h-3 animate-spin" /> : <Save className="w-3 h-3" />}
                  Guardar y firmar
                </button>
              )}
            </div>
            <div className="grid grid-cols-2 gap-6">
              <SignatureCanvas label="Cliente" value={firmaCliente} onChange={setFirmaCliente} disabled={!isPendiente} />
              <SignatureCanvas label={`Responsable — ${parte.responsable_empresa || "Empresa"}`} value={firmaResp} onChange={setFirmaResp} disabled={!isPendiente} />
            </div>
          </div>

          {/* Documentos */}
          <div className="card p-6">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-sm font-semibold text-surface-900">Documentos y fotos</h2>
              <button onClick={() => fileInputRef.current?.click()} disabled={uploading}
                className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
                {uploading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Upload className="w-3.5 h-3.5" />} Subir
              </button>
              <input ref={fileInputRef} type="file" multiple accept="image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt" className="hidden" onChange={handleUploadFile} />
            </div>
            {documentos.length === 0 ? (
              <p className="text-xs text-surface-400 text-center py-4">Sin documentos adjuntos</p>
            ) : (
              <div className="space-y-1.5">
                {documentos.map((doc) => {
                  const isImage = doc.tipo === "foto"; const isPdf = doc.tipo === "pdf";
                  return (
                    <div key={doc.id} className="flex items-center gap-3 p-2.5 bg-surface-50 rounded-lg border border-surface-100 group">
                      <div className={cn("w-8 h-8 rounded-lg flex items-center justify-center shrink-0",
                        isImage ? "bg-violet-100 text-violet-600" : isPdf ? "bg-red-100 text-red-600" : "bg-blue-100 text-blue-600")}>
                        {isImage ? <ImageIcon className="w-4 h-4" /> : isPdf ? <FileText className="w-4 h-4" /> : <File className="w-4 h-4" />}
                      </div>
                      <div className="flex-1 min-w-0 cursor-pointer" onClick={() => handleOpenDoc(doc)}>
                        <p className="text-xs font-medium text-surface-900 hover:text-brand-600 truncate">{doc.nombre_archivo}</p>
                        <p className="text-[10px] text-surface-400">{formatBytes(doc.tamano)}</p>
                      </div>
                      <div className="flex gap-1 opacity-0 group-hover:opacity-100">
                        <button onClick={() => handleOpenDoc(doc)} title="Abrir" className="p-1 rounded text-surface-400 hover:text-brand-600"><ExternalLink className="w-3.5 h-3.5" /></button>
                        <button onClick={() => handleDeleteDoc(doc)} title="Eliminar" className="p-1 rounded text-surface-400 hover:text-red-600"><Trash2 className="w-3.5 h-3.5" /></button>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Audios */}
          <div className="card p-6">
            <AudioRecorder parteId={id} audios={audios} onChanged={fetchData} onTranscription={handleTranscription} disabled={false} />
          </div>
        </div>
      </div>
    </AppLayout>
  );
}
