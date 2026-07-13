"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { useParams } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import SignatureCanvas from "@/components/partes/SignatureCanvas";
import AudioRecorder from "@/components/partes/AudioRecorder";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { ParteDiario, ParteLinea, Documento, ParteAudio, TipoTrabajo, RecursoHumano } from "@/lib/types/database";
import {
  ClipboardList, ArrowLeft, Loader2, Upload, Trash2, FileText,
  Image as ImageIcon, File, CheckCircle2, Clock, Save, ExternalLink,
  Plus, Mail, Download
} from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils/cn";

interface LineaForm { id?: string; concepto: string; tipo_trabajo_id: string; fabricante: string; producto: string; unidades: string; cantidad: string }
const emptyLinea: LineaForm = { concepto: "", tipo_trabajo_id: "", fabricante: "", producto: "", unidades: "", cantidad: "" };

export default function ParteDetallePage() {
  const { id } = useParams<{ id: string }>();
  const { user } = useAuthStore();
  const supabase = createClient();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [parte, setParte] = useState<ParteDiario | null>(null);
  const [documentos, setDocumentos] = useState<Documento[]>([]);
  const [audios, setAudios] = useState<ParteAudio[]>([]);
  const [tiposTrabajo, setTiposTrabajo] = useState<TipoTrabajo[]>([]);
  const [rrhh, setRrhh] = useState<RecursoHumano[]>([]);
  const [obras, setObras] = useState<any[]>([]);
  const [allUsers, setAllUsers] = useState<any[]>([]);
  const [createdBy, setCreatedBy] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [misAsignaciones, setMisAsignaciones] = useState<{ obra_id: string; fecha_inicio: string; fecha_fin: string }[]>([]);
  const fechaChangedManually = useRef(false);

  // Editable form state
  const [form, setForm] = useState({ fecha: "", obra_id: "", jefe_obra: "", encargado_obra: "", responsable_empresa: "", direccion: "", localidad: "", provincia: "", observaciones: "" });
  const [lineas, setLineas] = useState<LineaForm[]>([]);
  const [firmaResp, setFirmaResp] = useState<string | null>(null);
  const [firmaCliente, setFirmaCliente] = useState<string | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const isAdminUser = isAdmin;
    const [parteR, lineasR, docsR, audiosR, tiposR, rrhhR, obrasR, usersR, misAsigR] = await Promise.all([
      supabase.from("partes_diarios").select("*, obra:obras(*), creator:users!partes_diarios_created_by_fkey(nombre)").eq("id", id).single(),
      supabase.from("parte_lineas").select("*, tipo_trabajo:tipos_trabajo(nombre)").eq("parte_id", id).order("orden"),
      supabase.from("documentos").select("*").eq("parte_id", id).order("created_at", { ascending: false }),
      supabase.from("parte_audios").select("*").eq("parte_id", id).order("created_at", { ascending: false }),
      supabase.from("tipos_trabajo").select("*").eq("activo", true).order("nombre"),
      supabase.from("recursos_humanos").select("*").eq("activo", true).order("nombre"),
      supabase.from("obras").select("*").eq("archivada", false).order("nombre"),
      supabase.from("users").select("id, nombre").order("nombre"),
      !isAdminUser && user?.recurso_id
        ? supabase.from("asignaciones").select("obra_id, fecha_inicio, fecha_fin").eq("recurso_tipo", "humano").eq("recurso_id", user.recurso_id)
        : Promise.resolve({ data: [] as any[] }),
    ]);
    const p = parteR.data as ParteDiario | null;
    setParte(p);
    setCreatedBy(p?.created_by || "");
    setForm({
      fecha: p?.fecha || "", obra_id: p?.obra_id || "",
      jefe_obra: p?.jefe_obra || "", encargado_obra: p?.encargado_obra || "",
      responsable_empresa: p?.responsable_empresa || "",
      direccion: p?.direccion || "", localidad: p?.localidad || "", provincia: p?.provincia || "",
      observaciones: p?.observaciones || "",
    });
    setLineas((lineasR.data || []).map((l: any) => ({
      id: l.id, concepto: l.concepto || "", tipo_trabajo_id: l.tipo_trabajo_id || "",
      fabricante: l.fabricante || "", producto: l.producto || "",
      unidades: l.unidades || "", cantidad: l.cantidad?.toString() || "",
    })));
    setFirmaResp(p?.firma_data || null);
    setFirmaCliente(p?.firma_cliente || null);
    setDocumentos((docsR.data as Documento[]) || []);
    setAudios((audiosR.data as ParteAudio[]) || []);
    setTiposTrabajo(tiposR.data || []);
    setRrhh(rrhhR.data || []);
    setObras(obrasR.data || []);
    setAllUsers(usersR.data || []);
    setMisAsignaciones((misAsigR.data || []) as any);
    setLoading(false);
  }, [id, user]);
  useEffect(() => { fetchData(); }, [fetchData]);

  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("partes", "crear");
  const puedeEditar   = isAdmin || canDo("partes", "editar");
  const puedeEliminar = isAdmin || canDo("partes", "eliminar");
  const isEditable = parte?.estado === "pendiente" || parte?.estado === "borrador";
  const hasObra = !!form.obra_id;

  const handleObraChange = (obraId: string) => {
    const obra = obras.find((o: any) => o.id === obraId);
    setForm((f) => ({ ...f, obra_id: obraId, direccion: obra?.direccion || "", localidad: obra?.localidad || "", provincia: obra?.provincia || "" }));
  };

  // Obras a las que el operario esta asignado en la fecha actual del parte
  const obrasDelDia = isAdmin ? obras : obras.filter((o: any) =>
    misAsignaciones.some((a) => a.obra_id === o.id && a.fecha_inicio <= form.fecha && a.fecha_fin >= form.fecha)
  );

  // Si el operario cambia la fecha manualmente, resolver la obra segun su asignacion de ese dia
  useEffect(() => {
    if (isAdmin || !fechaChangedManually.current) return;
    if (obrasDelDia.length === 1) {
      handleObraChange(obrasDelDia[0].id);
    } else if (!obrasDelDia.some((o: any) => o.id === form.obra_id)) {
      setForm((f) => ({ ...f, obra_id: "", direccion: "", localidad: "", provincia: "" }));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [form.fecha, misAsignaciones]);

  const addLinea = () => setLineas([...lineas, { ...emptyLinea }]);
  const removeLinea = (idx: number) => setLineas(lineas.filter((_, i) => i !== idx));
  const updateLinea = (idx: number, field: keyof LineaForm, value: string) => setLineas(lineas.map((l, i) => i === idx ? { ...l, [field]: value } : l));

  const handleSave = async () => {
    setSaving(true);
    await (supabase.from("partes_diarios") as any).update({
      fecha: form.fecha, obra_id: form.obra_id || null,
      jefe_obra: form.jefe_obra || null, encargado_obra: form.encargado_obra || null,
      responsable_empresa: form.responsable_empresa || null,
      direccion: form.direccion || null, localidad: form.localidad || null, provincia: form.provincia || null,
      observaciones: form.observaciones || null,
      firma_data: firmaResp, firma_cliente: firmaCliente,
      created_by: createdBy || undefined,
    }).eq("id", id);

    // Delete old lines and insert new ones
    await (supabase.from("parte_lineas") as any).delete().eq("parte_id", id);
    const valid = lineas.filter((l) => l.concepto.trim());
    if (valid.length > 0) {
      await (supabase.from("parte_lineas") as any).insert(valid.map((l, i) => ({
        parte_id: id, orden: i, concepto: l.concepto, tipo_trabajo_id: l.tipo_trabajo_id || null,
        fabricante: l.fabricante || null, producto: l.producto || null,
        unidades: l.unidades || null, cantidad: l.cantidad ? parseFloat(l.cantidad) : null,
      })));
    }
    setSaving(false); fetchData();
  };

  const handleFirmar = async () => {
    setSaving(true);
    await (supabase.from("partes_diarios") as any).update({
      firma_data: firmaResp, firma_cliente: firmaCliente, estado: "firmado",
      fecha: form.fecha, obra_id: form.obra_id || null,
      jefe_obra: form.jefe_obra || null, encargado_obra: form.encargado_obra || null,
      responsable_empresa: form.responsable_empresa || null,
      direccion: form.direccion || null, localidad: form.localidad || null, provincia: form.provincia || null,
      observaciones: form.observaciones || null,
    }).eq("id", id);
    await (supabase.from("parte_lineas") as any).delete().eq("parte_id", id);
    const valid = lineas.filter((l) => l.concepto.trim());
    if (valid.length > 0) {
      await (supabase.from("parte_lineas") as any).insert(valid.map((l, i) => ({
        parte_id: id, orden: i, concepto: l.concepto, tipo_trabajo_id: l.tipo_trabajo_id || null,
        fabricante: l.fabricante || null, producto: l.producto || null,
        unidades: l.unidades || null, cantidad: l.cantidad ? parseFloat(l.cantidad) : null,
      })));
    }
    setSaving(false);
    await fetchData();
    // Envio automatico - siempre a lauroba.eneko@gmail.com (sin confirm)
    setSendingEmail(true);
    try {
      await fetch("/api/partes/email", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ parteId: id }),
      });
    } catch (e) { console.error("[firma] error email:", e); }
    setSendingEmail(false);
  };

  const handleTranscription = async (label: string, text: string) => {
    const newObs = form.observaciones ? `${form.observaciones}\n\n[${label}]: ${text}` : `[${label}]: ${text}`;
    setForm((f) => ({ ...f, observaciones: newObs }));
    await (supabase.from("partes_diarios") as any).update({ observaciones: newObs }).eq("id", id);
  };

  const [sendingEmail, setSendingEmail] = useState(false);
  const [downloadingPdf, setDownloadingPdf] = useState(false);

  const handleDownloadPdf = async () => {
    setDownloadingPdf(true);
    try {
      const res = await fetch("/api/partes/pdf", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ parteId: id }) });
      const data = await res.json();
      if (data.pdf) {
        const link = document.createElement("a");
        link.href = `data:application/pdf;base64,${data.pdf}`;
        link.download = data.filename;
        link.click();
      } else { alert("Error: " + (data.error || "No PDF")); }
    } catch (err: any) { alert("Error: " + err.message); }
    setDownloadingPdf(false);
  };

  const handleSendEmail = async () => {
    const obraData = parte as any;
    const contactEmail = obraData?.obra?.contacto_obra_email || "";
    const email = prompt("Enviar parte por email a:", contactEmail);
    if (!email) return;

    setSendingEmail(true);
    try {
      const res = await fetch("/api/partes/email", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ parteId: id, toEmail: email }),
      });
      const data = await res.json();
      if (data.success) alert("Email enviado correctamente a " + email);
      else alert("Error: " + (data.error || "Error desconocido"));
    } catch (err: any) { alert("Error: " + err.message); }
    setSendingEmail(false);
  };

  const handleUploadFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    // Save form first if obra changed
    if (form.obra_id && form.obra_id !== parte?.obra_id) {
      await (supabase.from("partes_diarios") as any).update({
        obra_id: form.obra_id || null, fecha: form.fecha,
        jefe_obra: form.jefe_obra || null, encargado_obra: form.encargado_obra || null,
        responsable_empresa: form.responsable_empresa || null,
        direccion: form.direccion || null, localidad: form.localidad || null, provincia: form.provincia || null,
        observaciones: form.observaciones || null,
      }).eq("id", id);
    }
    setUploading(true);
    let errors: string[] = [];
    let success = 0;
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      // Normalizar nombre: quitar acentos, espacios y caracteres especiales
      // Supabase Storage rechaza nombres con estos caracteres
      const safeName = file.name
        .normalize("NFD").replace(/[\u0300-\u036f]/g, "") // quitar acentos
        .replace(/[^a-zA-Z0-9._-]/g, "_");               // reemplazar especiales
      const path = `partes/${id}/${Date.now()}_${safeName}`;
      const { error: uploadErr } = await supabase.storage.from("documentos").upload(path, file);
      if (uploadErr) { errors.push(`${file.name}: ${uploadErr.message}`); continue; }
      const insertData: any = {
        parte_id: id, nombre_archivo: file.name, // nombre original para mostrar
        tipo: file.type.startsWith("image/") ? "foto" : file.type === "application/pdf" ? "pdf" : "documento",
        categoria: "general", storage_path: path, tamano: file.size, mime_type: file.type, uploaded_by: user?.id,
      };
      if (form.obra_id) insertData.obra_id = form.obra_id;
      const { error: insertErr } = await (supabase.from("documentos") as any).insert(insertData);
      if (insertErr) errors.push(`${file.name} (DB): ${insertErr.message}`);
      else success++;
    }
    setUploading(false);
    if (fileInputRef.current) fileInputRef.current.value = "";
    if (errors.length > 0) alert("Errores al subir:\n" + errors.join("\n"));
    fetchData();
  };
  const handleOpenDoc = async (doc: Documento) => { const { data } = await supabase.storage.from("documentos").createSignedUrl(doc.storage_path, 300); if (data?.signedUrl) window.open(data.signedUrl, "_blank"); };
  const handleDeleteDoc = async (doc: Documento) => { await supabase.storage.from("documentos").remove([doc.storage_path]); await (supabase.from("documentos") as any).delete().eq("id", doc.id); fetchData(); };
  const formatBytes = (b: number | null) => { if (!b) return ""; if (b < 1024) return b + " B"; if (b < 1048576) return (b / 1024).toFixed(0) + " KB"; return (b / 1048576).toFixed(1) + " MB"; };

  if (loading) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;
  if (!parte) return <AppLayout><div className="text-center py-20"><p className="text-surface-500">Parte no encontrado</p></div></AppLayout>;

  const estBadge: Record<string, { label: string; class: string }> = { borrador: { label: "Borrador", class: "bg-surface-200 text-surface-700" }, pendiente: { label: "Pendiente", class: "bg-amber-100 text-amber-700" }, firmado: { label: "Firmado", class: "bg-emerald-100 text-emerald-700" } };
  const est = estBadge[parte.estado] || estBadge.pendiente;
  const ic = "w-full px-3 py-2 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  const icLocked = ic + " bg-surface-100 text-surface-500 cursor-not-allowed";
  const icDisabled = ic + " bg-surface-100 text-surface-500 cursor-not-allowed";
  const icSm = "w-full px-2.5 py-1.5 bg-white border border-surface-200 rounded-md text-xs placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  return (
    <AppLayout><div className="max-w-4xl mx-auto animate-fade-in">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <Link href="/partes" className="p-2 rounded-lg text-surface-400 hover:bg-surface-100"><ArrowLeft className="w-5 h-5" /></Link>
          <div className="w-10 h-10 rounded-lg bg-orange-50 flex items-center justify-center"><ClipboardList className="w-5 h-5 text-orange-600" /></div>
          <div>
            <h1 className="text-xl font-display font-bold text-surface-900">Parte — {new Date(parte.fecha + "T12:00:00").toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" })}</h1>
            <p className="text-sm text-surface-500">{(parte as any).obra?.nombre || "Sin obra"} · {(parte as any).creator?.nombre}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {parte.estado === "firmado" && (
            <>
              <button onClick={handleDownloadPdf} disabled={downloadingPdf}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200 disabled:opacity-60">
                {downloadingPdf ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Download className="w-3.5 h-3.5" />} PDF
              </button>
              <button onClick={handleSendEmail} disabled={sendingEmail}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-blue-700 bg-blue-50 rounded-lg hover:bg-blue-100 disabled:opacity-60">
                {sendingEmail ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Mail className="w-3.5 h-3.5" />} Enviar
              </button>
            </>
          )}
          <span className={cn("badge text-sm", est.class)}>{est.label}</span>
        </div>
      </div>

      <div className="space-y-6">
        {/* Cabecera */}
        <div className="card p-6">
          <h2 className="text-sm font-semibold text-surface-900 mb-4">Datos del parte</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Fecha</label><input type="date" value={form.fecha} onChange={(e) => { fechaChangedManually.current = true; setForm({ ...form, fecha: e.target.value }); }} disabled={!isEditable} className={isEditable ? ic : icDisabled} /></div>
            <div>
              <label className="block text-xs font-medium text-surface-700 mb-1">Obra</label>
              {!isAdmin && obrasDelDia.length <= 1 ? (
                <select value={form.obra_id} disabled className={icDisabled}>
                  {obrasDelDia.length === 1
                    ? <option value={obrasDelDia[0].id}>{obrasDelDia[0].nombre}</option>
                    : <option value="">Sin obra asignada ese día</option>}
                </select>
              ) : (
                <select value={form.obra_id} onChange={(e) => handleObraChange(e.target.value)} disabled={!isEditable} className={isEditable ? ic : icDisabled}>
                  <option value="">{isAdmin ? "Sin obra" : "Selecciona la obra"}</option>
                  {(isAdmin ? obras : obrasDelDia).map((o: any) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
                </select>
              )}
            </div>
          </div>
          <div className="grid grid-cols-3 gap-4 mt-4">
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Dirección <span className="text-[10px] text-surface-400">(de la obra)</span></label><input type="text" value={form.direccion} readOnly className={icLocked} /></div>
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Localidad</label><input type="text" value={form.localidad} readOnly className={icLocked} /></div>
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Provincia</label><input type="text" value={form.provincia} readOnly className={icLocked} /></div>
          </div>
          <div className="grid grid-cols-3 gap-4 mt-4">
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Jefe de obra</label><select value={form.jefe_obra} onChange={(e) => setForm({ ...form, jefe_obra: e.target.value })} disabled={!isEditable} className={isEditable ? ic : icDisabled}><option value="">Seleccionar...</option>{rrhh.map((r) => <option key={r.id} value={r.nombre}>{r.nombre}</option>)}</select></div>
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Encargado</label><select value={form.encargado_obra} onChange={(e) => setForm({ ...form, encargado_obra: e.target.value })} disabled={!isEditable} className={isEditable ? ic : icDisabled}><option value="">Seleccionar...</option>{rrhh.map((r) => <option key={r.id} value={r.nombre}>{r.nombre}</option>)}</select></div>
            <div><label className="block text-xs font-medium text-surface-700 mb-1">Responsable</label><input type="text" value={form.responsable_empresa} onChange={(e) => setForm({ ...form, responsable_empresa: e.target.value })} disabled={!isEditable} className={isEditable ? ic : icDisabled} /></div>
          </div>
          <div className="mt-4">
            <label className="block text-xs font-medium text-surface-700 mb-1">Creado por</label>
            {isAdmin && isEditable ? (
              <select value={createdBy} onChange={(e) => setCreatedBy(e.target.value)} className={ic}>
                {allUsers.map((u: any) => <option key={u.id} value={u.id}>{u.nombre}</option>)}
              </select>
            ) : (
              <p className="text-sm text-surface-600 py-2">{(parte as any).creator?.nombre || "—"}</p>
            )}
          </div>
        </div>

        {/* Observaciones */}
        <div className="card p-6">
          <h2 className="text-sm font-semibold text-surface-900 mb-3">Observaciones</h2>
          <textarea value={form.observaciones} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} disabled={!isEditable}
            rows={5} placeholder="Observaciones, transcripciones de audio..." className={(isEditable ? ic : icDisabled) + " resize-y font-mono text-xs"} />
        </div>



        {/* Firma del cliente */}
        <div className="card p-6">
          <h2 className="text-sm font-semibold text-surface-900 mb-4">Firma del cliente</h2>
          <SignatureCanvas label="Cliente" value={firmaCliente} onChange={setFirmaCliente} disabled={!isEditable} />
        </div>

        {/* Documentos */}
        <div className="card p-6">

          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-surface-900">Documentos</h2>
            <button onClick={() => { console.log("Click subir"); fileInputRef.current?.click(); }} disabled={uploading} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {uploading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Upload className="w-3.5 h-3.5" />}Subir
            </button>
          </div>
          {documentos.length === 0 ? <p className="text-xs text-surface-400 text-center py-4">Sin documentos</p> : (
            <div className="space-y-1.5">{documentos.map((doc) => {
              const isImage = doc.tipo === "foto"; const isPdf = doc.tipo === "pdf";
              return (
                <div key={doc.id} className="flex items-center gap-3 p-2.5 bg-surface-50 rounded-lg border border-surface-100 group">
                  <div className={cn("w-8 h-8 rounded-lg flex items-center justify-center shrink-0", isImage ? "bg-violet-100 text-violet-600" : isPdf ? "bg-red-100 text-red-600" : "bg-blue-100 text-blue-600")}>
                    {isImage ? <ImageIcon className="w-4 h-4" /> : isPdf ? <FileText className="w-4 h-4" /> : <File className="w-4 h-4" />}
                  </div>
                  <div className="flex-1 min-w-0 cursor-pointer" onClick={() => handleOpenDoc(doc)}>
                    <p className="text-xs font-medium text-surface-900 hover:text-brand-600 truncate">{doc.nombre_archivo}</p>
                    <p className="text-[10px] text-surface-400">{formatBytes(doc.tamano)}</p>
                  </div>
                  <div className="flex gap-1 opacity-0 group-hover:opacity-100">
                    <button onClick={() => handleOpenDoc(doc)} className="p-1 rounded text-surface-400 hover:text-brand-600"><ExternalLink className="w-3.5 h-3.5" /></button>
                    <button onClick={() => handleDeleteDoc(doc)} className="p-1 rounded text-surface-400 hover:text-red-600"><Trash2 className="w-3.5 h-3.5" /></button>
                  </div>
                </div>
              );
            })}</div>
          )}
        </div>

        {/* Audios */}
        <div className="card p-6">
          <AudioRecorder parteId={id} audios={audios} onChanged={fetchData} onTranscription={handleTranscription} disabled={false} />
        </div>

        {/* Actions */}
        {isEditable && (
          <div className="flex items-center justify-between pb-6">
            {(!firmaCliente) && (
              <p className="text-xs text-amber-600 flex items-center gap-1">
                ⚠ Se necesita la firma del cliente
              </p>
            )}
            {firmaCliente && <div />}
            <div className="flex items-center gap-3 ml-auto">
            <button onClick={handleSave} disabled={saving} className="flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-surface-700 bg-surface-200 rounded-lg hover:bg-surface-300 disabled:opacity-60">
              {saving && <Loader2 className="w-4 h-4 animate-spin" />}<Save className="w-4 h-4" />Guardar
            </button>
            <button onClick={handleFirmar} disabled={saving || !firmaCliente} title={!firmaCliente ? "Se necesita la firma del cliente" : ""} className="flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-white bg-emerald-500 rounded-lg hover:bg-emerald-600 disabled:opacity-60">
              {saving && <Loader2 className="w-4 h-4 animate-spin" />}<CheckCircle2 className="w-4 h-4" />Firmar
            </button>
            </div>
          </div>
        )}
      </div>
      {/* Input file fuera de contenedor flex — garantiza galería en iOS/Android */}
      <input
        ref={fileInputRef}
        type="file"
        multiple
        accept="image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt"
        className="hidden"
        onChange={handleUploadFile}
      />
    </div></AppLayout>
  );
}
