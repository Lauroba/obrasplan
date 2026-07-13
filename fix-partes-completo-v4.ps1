#Requires -Version 5.1
# fix-partes-completo-v4.ps1
# TODOS los cambios del parte en un solo script:
#
# page.tsx:
#   - Seccion Trabajos/Materiales eliminada del JSX
#   - Solo firma del CLIENTE (firma responsable eliminada)
#   - Firma del cliente al FINAL (antes de Documentos)
#   - Boton Firmar solo requiere firma cliente
#   - Nombres de archivo normalizados al subir (sin acentos/espacios)
#   - Input file fuera de contenedor flex (fix galeria movil)
#   - Email automatico sin confirm() al firmar
#
# generatePartePdf.ts:
#   - Cabecera: Obra en rojo + Fecha + Creado por
#   - Sin seccion materiales
#   - Solo firma cliente
#   - Fotos 3 por pagina
#
# route.ts:
#   - Solo a lauroba.eneko@gmail.com (FIXED_TO)
#   - Adjuntos reales (bytes, no links)
#   - Asunto: Obra | Fecha | Creador

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Fix partes completo v4" -ForegroundColor Cyan

Write-Host "  -> src\app\partes\[id]\page.tsx" -ForegroundColor Gray
$dst = "src\app\partes\[id]\page.tsx"
$content = @'
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

  // Obras a las que el operario está asignado en la fecha actual del parte
  const obrasDelDia = isAdmin ? obras : obras.filter((o: any) =>
    misAsignaciones.some((a) => a.obra_id === o.id && a.fecha_inicio <= form.fecha && a.fecha_fin >= form.fecha)
  );

  // Si el operario cambia la fecha manualmente, resolver/forzar la obra según su asignación de ese día
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
    // Envío automático al firmar:
    // - Si la obra tiene email de contacto -> se envía a ese email (destinatario principal)
    // - Siempre se añade lauroba.eneko@gmail.com en CC (gestionado en la API route)
    // - Sin confirmación del usuario
    setSendingEmail(true);
    try {
      if (form.obra_id) {
        const { data: obraEmail } = await supabase.from("obras").select("contacto_obra_email").eq("id", form.obra_id).single();
        // Usar email de la obra si existe, si no usar el admin como destinatario principal
        const toEmail = obraEmail?.contacto_obra_email || "lauroba.eneko@gmail.com";
        await fetch("/api/partes/email", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ parteId: id, toEmail }),
        });
      } else {
        // Sin obra asociada: enviar directamente al admin
        await fetch("/api/partes/email", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ parteId: id, toEmail: "lauroba.eneko@gmail.com" }),
        });
      }
    } catch { /* ignorar errores de email para no bloquear el flujo */ }
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

        {/* Observaciones */
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
      {/* Input file fuera de cualquier contenedor flex — garantiza funcionamiento en iOS/Android galería */}
      <input
        ref={fileInputRef}
        type="file"
        multiple
        accept="image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt"
        className="hidden"
        onChange={handleUploadFile}
      />
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
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

Write-Host "  -> src\lib\pdf\generatePartePdf.ts" -ForegroundColor Gray
$dst = "src\lib\pdf\generatePartePdf.ts"
$content = @'
import { createAdminClient } from "@/lib/supabase/admin";
import { LOGO_BASE64 } from "@/lib/logo";
import jsPDF from "jspdf";
import "jspdf-autotable";

declare module "jspdf" {
  interface jsPDF {
    autoTable: (options: any) => jsPDF;
    lastAutoTable: { finalY: number };
  }
}

const PAGE_H  = 297;
const PAGE_W  = 210;
const MARGIN  = 15;
const FOOTER_Y = 290;

// ── Helpers de estilo ─────────────────────────────────────────────────────────
function label(doc: jsPDF) {
  doc.setFontSize(7);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(120, 120, 120);
}
function value(doc: jsPDF) {
  doc.setFontSize(9);
  doc.setFont("helvetica", "normal");
  doc.setTextColor(0, 0, 0);
}
function sectionTitle(doc: jsPDF, text: string, y: number) {
  doc.setFontSize(9);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(220, 38, 38);
  doc.text(text, MARGIN, y);
  doc.setDrawColor(220, 38, 38);
  doc.setLineWidth(0.3);
  doc.line(MARGIN, y + 1.5, PAGE_W - MARGIN, y + 1.5);
  doc.setTextColor(0, 0, 0);
  return y + 6;
}
function addFooters(doc: jsPDF) {
  const total = doc.getNumberOfPages();
  for (let i = 1; i <= total; i++) {
    doc.setPage(i);
    doc.setFontSize(7);
    doc.setFont("helvetica", "normal");
    doc.setTextColor(150, 150, 150);
    doc.text("LOYNEK Soluciones Técnicas — ObrasPlan", MARGIN, FOOTER_Y);
    doc.text(`Página ${i} de ${total}`, PAGE_W - MARGIN, FOOTER_Y, { align: "right" });
  }
}
function checkPage(doc: jsPDF, y: number, need = 20): number {
  if (y + need > FOOTER_Y - 5) {
    doc.addPage();
    return 20;
  }
  return y;
}

// ── Función principal ─────────────────────────────────────────────────────────
export async function generatePartePdf(
  parteId: string
): Promise<{ pdf: string; filename: string }> {
  const supabase = createAdminClient();

  const { data: parte } = await supabase
    .from("partes_diarios")
    .select("*, obra:obras(*), creator:users!partes_diarios_created_by_fkey(nombre)")
    .eq("id", parteId)
    .single();
  if (!parte) throw new Error("Parte not found");

  // Documentos (fotos y otros)
  const { data: docs } = await supabase
    .from("documentos")
    .select("nombre_archivo, storage_path, tipo")
    .eq("parte_id", parteId);

  const fotos = (docs || []).filter(
    (d) => d.tipo === "foto" || /\.(jpg|jpeg|png|webp|gif)$/i.test(d.nombre_archivo)
  );
  const otrosDocs = (docs || []).filter(
    (d) => !fotos.includes(d)
  );

  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
  const w = PAGE_W;
  let y = 15;

  // ── CABECERA ────────────────────────────────────────────────────────────────
  try {
    doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", MARGIN, y, 32, 22);
  } catch {}

  const fecha = parte.fecha
    ? new Date(parte.fecha + "T12:00:00").toLocaleDateString("es-ES", {
        weekday: "long", day: "numeric", month: "long", year: "numeric",
      })
    : "";
  const creador = parte.creator?.nombre || parte.creator?.email || "—";

  doc.setFontSize(16);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(0, 0, 0);
  doc.text("PARTE DE TRABAJO", w / 2, y + 8, { align: "center" });

  // Obra destacada en la cabecera
  doc.setFontSize(11);
  doc.setFont("helvetica", "bold");
  doc.setTextColor(220, 38, 38);
  doc.text(parte.obra?.nombre || "Sin obra", w / 2, y + 15, { align: "center" });

  // Fecha y creador
  doc.setFontSize(9);
  doc.setFont("helvetica", "normal");
  doc.setTextColor(60, 60, 60);
  doc.text(fecha, w / 2, y + 21, { align: "center" });
  doc.setFontSize(8);
  doc.setTextColor(100, 100, 100);
  doc.text(`Creado por: ${creador}`, w / 2, y + 26, { align: "center" });

  // Estado (derecha)
  doc.setFontSize(8);
  doc.setTextColor(150, 150, 150);
  doc.text((parte.estado || "").toUpperCase(), w - MARGIN, y + 8, { align: "right" });
  doc.setTextColor(0, 0, 0);

  y = 44;
  doc.setDrawColor(220, 38, 38);
  doc.setLineWidth(0.8);
  doc.line(MARGIN, y, w - MARGIN, y);
  y += 5;

  // ── DATOS DE LA OBRA ────────────────────────────────────────────────────────
  y = sectionTitle(doc, "DATOS DE LA OBRA", y);

  doc.setFillColor(248, 249, 250);
  doc.roundedRect(MARGIN, y, w - MARGIN * 2, 22, 2, 2, "F");

  // Dirección, localidad y provincia — la obra ya aparece en cabecera
  const midX = w / 2;
  label(doc); doc.text("DIRECCIÓN", MARGIN + 4, y + 5);
  value(doc); doc.text(parte.direccion || "—", MARGIN + 4, y + 11);

  label(doc); doc.text("LOCALIDAD", midX + 4, y + 5);
  value(doc); doc.text(parte.localidad || "—", midX + 4, y + 11);

  label(doc); doc.text("PROVINCIA", MARGIN + 4, y + 16);
  value(doc); doc.text(parte.provincia || "—", MARGIN + 4, y + 21);
  y += 28;

  // ── RESPONSABLES ────────────────────────────────────────────────────────────
  y = checkPage(doc, y, 22);
  y = sectionTitle(doc, "RESPONSABLES", y);

  doc.setFillColor(248, 249, 250);
  doc.roundedRect(MARGIN, y, w - MARGIN * 2, 16, 2, 2, "F");
  const col3 = (w - MARGIN * 2) / 3;

  label(doc); doc.text("JEFE DE OBRA", MARGIN + 4, y + 5);
  value(doc); doc.text(parte.jefe_obra || "—", MARGIN + 4, y + 11);

  label(doc); doc.text("ENCARGADO", MARGIN + col3 + 4, y + 5);
  value(doc); doc.text(parte.encargado_obra || "—", MARGIN + col3 + 4, y + 11);

  label(doc); doc.text("EMPRESA RESPONSABLE", MARGIN + col3 * 2 + 4, y + 5);
  value(doc); doc.text(parte.responsable_empresa || "—", MARGIN + col3 * 2 + 4, y + 11);
  y += 22;

  y += 4; // (creador ya aparece en la cabecera del parte)

  // ── OBSERVACIONES ───────────────────────────────────────────────────────────
  if (parte.observaciones) {
    y = checkPage(doc, y, 30);
    y = sectionTitle(doc, "OBSERVACIONES", y);
    doc.setFontSize(8);
    doc.setFont("helvetica", "normal");
    doc.setTextColor(0, 0, 0);
    const lines = doc.splitTextToSize(parte.observaciones, w - MARGIN * 2);
    doc.text(lines, MARGIN, y);
    y += lines.length * 4 + 8;
  }

  // ── DOCUMENTOS ADJUNTOS (no fotos) ──────────────────────────────────────────
  if (otrosDocs.length > 0) {
    y = checkPage(doc, y, 20);
    y = sectionTitle(doc, "DOCUMENTOS ADJUNTOS", y);
    doc.setFontSize(8);
    doc.setFont("helvetica", "normal");
    for (const d of otrosDocs) {
      y = checkPage(doc, y, 6);
      doc.text(`• ${d.nombre_archivo}`, MARGIN + 2, y);
      y += 5;
    }
    y += 4;
  }

  // ── FIRMA DEL CLIENTE ────────────────────────────────────────────────────────
  y = checkPage(doc, y, 50);
  y = sectionTitle(doc, "FIRMA DEL CLIENTE", y);

  const sigW = 80;
  const sigH = 35;
  doc.setDrawColor(180, 180, 180);
  doc.setLineWidth(0.3);
  doc.roundedRect(MARGIN, y, sigW, sigH, 2, 2);

  if (parte.firma_cliente) {
    try {
      doc.addImage(parte.firma_cliente, "PNG", MARGIN + 2, y + 2, sigW - 4, sigH - 4);
    } catch {}
  }

  doc.setFillColor(240, 240, 240);
  doc.rect(MARGIN, y + sigH, sigW, 6, "F");
  label(doc);
  doc.text("Firma del cliente", MARGIN + sigW / 2, y + sigH + 4, { align: "center" });
  y += sigH + 12;

  // ── FOTOS (3 por página) ──────────────────────────────────────────────────────
  if (fotos.length > 0) {
    doc.addPage();
    y = 20;
    y = sectionTitle(doc, `FOTOGRAFÍAS (${fotos.length})`, y);
    y += 2;

    const imgW  = (w - MARGIN * 2 - 8) / 2; // 2 columnas
    const imgH  = 65;
    const perPage = 3;  // 3 fotos por página (2 arriba, 1 abajo centrada)

    let slot = 0;
    for (let i = 0; i < fotos.length; i++) {
      const foto = fotos[i];

      // Cada 3 fotos: nueva página
      if (i > 0 && i % perPage === 0) {
        doc.addPage();
        y = 20;
        y = sectionTitle(doc, `FOTOGRAFÍAS (cont.)`, y);
        y += 2;
        slot = 0;
      }

      slot = i % perPage;

      // Layout: fila 0 = izquierda, fila 1 = derecha, fila 2 = centrada
      let imgX: number;
      let rowY: number;
      if (slot === 0) {
        imgX = MARGIN;
        rowY = y;
      } else if (slot === 1) {
        imgX = MARGIN + imgW + 8;
        rowY = y;
      } else {
        // 3ª foto: nueva fila, centrada
        rowY = y + imgH + 14;
        imgX = MARGIN + (w - MARGIN * 2 - imgW) / 2;
      }

      // Descargar imagen desde Supabase
      try {
        const { data: signedData } = await supabase.storage
          .from("documentos")
          .createSignedUrl(foto.storage_path, 60);

        if (signedData?.signedUrl) {
          const resp = await fetch(signedData.signedUrl);
          const buf  = await resp.arrayBuffer();
          const b64  = Buffer.from(buf).toString("base64");
          const ext  = foto.nombre_archivo.split(".").pop()?.toLowerCase() || "jpeg";
          const mime = ext === "png" ? "PNG" : "JPEG";
          const dataUri = `data:image/${ext === "png" ? "png" : "jpeg"};base64,${b64}`;

          // Recuadro
          doc.setDrawColor(200, 200, 200);
          doc.setLineWidth(0.3);
          doc.roundedRect(imgX, rowY, imgW, imgH, 2, 2);
          doc.addImage(dataUri, mime, imgX + 1, rowY + 1, imgW - 2, imgH - 8);

          // Nombre del archivo
          doc.setFontSize(6);
          doc.setFont("helvetica", "normal");
          doc.setTextColor(100, 100, 100);
          const shortName = foto.nombre_archivo.length > 28
            ? foto.nombre_archivo.substring(0, 25) + "..."
            : foto.nombre_archivo;
          doc.text(shortName, imgX + imgW / 2, rowY + imgH - 2, { align: "center" });
        }
      } catch { /* si falla una imagen, continuar */ }

      // Avanzar y cuando completamos la fila 2 o es la última
      if (slot === 2 || i === fotos.length - 1) {
        y = (slot === 2 ? y + imgH + 14 : y) + imgH + 14;
      }
    }
  }

  addFooters(doc);

  const pdfBase64 = doc.output("datauristring").split(",")[1];
  const filename = `parte_${parte.fecha}_${
    (parte.obra?.nombre || "sin-obra").replace(/\s+/g, "_")
  }.pdf`;

  return { pdf: pdfBase64, filename };
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

Write-Host "  -> src\app\api\partes\email\route.ts" -ForegroundColor Gray
$dst = "src\app\api\partes\email\route.ts"
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { generatePartePdf } from "@/lib/pdf/generatePartePdf";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(req: NextRequest) {
  try {
    const { parteId } = await req.json();
    if (!parteId) return NextResponse.json({ error: "parteId required" }, { status: 400 });

    const RESEND_API_KEY = process.env.RESEND_API_KEY;
    if (!RESEND_API_KEY) return NextResponse.json({ error: "RESEND_API_KEY not configured" }, { status: 500 });

    const FIXED_TO = "lauroba.eneko@gmail.com";
    const supabase = createAdminClient();

    // ── Configuración de la empresa ──────────────────────────────────────────
    const { data: settings } = await supabase
      .from("app_settings").select("value").eq("key", "partes_email").single();
    const config = settings?.value || {};
    const empresaNombre  = config.empresa_nombre  || "LOYNEK Soluciones Técnicas";
    const footerText     = config.footer_text     || "Email generado automáticamente desde ObrasPlan";
    const colorPrimario  = config.color_primario  || "#DC2626";

    // ── Datos del parte ──────────────────────────────────────────────────────
    const { data: parte } = await supabase
      .from("partes_diarios")
      .select("*, obra:obras(nombre, contacto_obra_nombre), creator:users!partes_diarios_created_by_fkey(nombre)")
      .eq("id", parteId)
      .single();
    if (!parte) return NextResponse.json({ error: "Parte not found" }, { status: 404 });

    const obraName   = parte.obra?.nombre || "Sin obra";
    const creador    = (parte as any).creator?.nombre || "—";
    const fecha      = parte.fecha
      ? new Date(parte.fecha + "T12:00:00").toLocaleDateString("es-ES", {
          day: "numeric", month: "long", year: "numeric",
        })
      : "";

    // ── Generar PDF ──────────────────────────────────────────────────────────
    console.log("[partes/email] Generando PDF para parte", parteId);
    const pdfData = await generatePartePdf(parteId);

    // ── Adjuntos: descargar bytes reales de Supabase ──────────────────────────
    const { data: docs   } = await supabase
      .from("documentos")
      .select("nombre_archivo, storage_path, tipo")
      .eq("parte_id", parteId);
    const { data: audios } = await supabase
      .from("parte_audios")
      .select("nombre_archivo, storage_path")
      .eq("parte_id", parteId);

    // Resend acepta attachments con { filename, content } donde content es base64
    const attachments: { filename: string; content: string }[] = [
      { filename: pdfData.filename, content: pdfData.pdf },
    ];

    // Documentos (fotos, PDFs, etc.)
    for (const d of (docs || [])) {
      try {
        const { data: signed } = await supabase.storage
          .from("documentos")
          .createSignedUrl(d.storage_path, 300);
        if (!signed?.signedUrl) continue;
        const resp = await fetch(signed.signedUrl);
        if (!resp.ok) continue;
        const buf = await resp.arrayBuffer();
        const b64 = Buffer.from(buf).toString("base64");
        attachments.push({ filename: d.nombre_archivo, content: b64 });
      } catch { /* ignorar archivos que fallen */ }
    }

    // Audios
    for (const a of (audios || [])) {
      try {
        const { data: signed } = await supabase.storage
          .from("audios")
          .createSignedUrl(a.storage_path, 300);
        if (!signed?.signedUrl) continue;
        const resp = await fetch(signed.signedUrl);
        if (!resp.ok) continue;
        const buf = await resp.arrayBuffer();
        const b64 = Buffer.from(buf).toString("base64");
        attachments.push({ filename: a.nombre_archivo, content: b64 });
      } catch { /* ignorar audios que fallen */ }
    }

    const nAdj = attachments.length - 1; // sin contar el PDF
    console.log(`[partes/email] ${attachments.length} adjuntos (PDF + ${nAdj} archivos)`);

    // ── Construir email ──────────────────────────────────────────────────────
    const emailPayload = {
      from: `${empresaNombre} <onboarding@resend.dev>`,
      to:   [FIXED_TO],
      subject: `Parte: ${obraName} | ${fecha} | ${creador}`,
      html: `
        <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto">
          <div style="background:${colorPrimario};padding:20px;text-align:center;border-radius:8px 8px 0 0">
            <h1 style="color:white;margin:0;font-size:20px">${empresaNombre} — Parte de Trabajo</h1>
          </div>
          <div style="padding:20px;background:#f9f9f9">
            <p style="color:#333">Parte de trabajo de la obra <strong>${obraName}</strong>, fecha <strong>${fecha}</strong>.</p>
            <p style="color:#333">Creado por: <strong>${creador}</strong></p>
            <p style="color:#333">Se adjuntan el PDF del parte${nAdj > 0 ? ` y ${nAdj} archivo${nAdj > 1 ? "s" : ""} adicional${nAdj > 1 ? "es" : ""}` : ""}.</p>
            <hr style="border:none;border-top:1px solid #ddd;margin:20px 0"/>
            <p style="color:#999;font-size:12px">${footerText}</p>
          </div>
        </div>
      `,
      attachments,
    };

    // ── Enviar via Resend ────────────────────────────────────────────────────
    console.log(`[partes/email] Enviando a ${FIXED_TO} — parte ${parteId}`);
    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify(emailPayload),
    });

    if (!emailRes.ok) {
      const errText = await emailRes.text();
      let errMsg = errText;
      try { errMsg = JSON.parse(errText).message || errText; } catch {}
      console.error("[partes/email] Error Resend:", errMsg);
      return NextResponse.json({ error: `Error Resend: ${errMsg}` }, { status: 400 });
    }

    const emailResult = await emailRes.json();
    console.log("[partes/email] OK — emailId:", emailResult.id);
    return NextResponse.json({ success: true, emailId: emailResult.id });

  } catch (err: any) {
    console.error("[partes/email] Excepción:", err?.message);
    return NextResponse.json({ error: err.message || "Error sending email" }, { status: 500 });
  }
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

$ok1 = !(Select-String -LiteralPath (Join-Path $RepoPath "src\app\partes\[id]\page.tsx") -Pattern "Trabajos / Materiales" -Quiet)
$ok2 = Select-String -LiteralPath (Join-Path $RepoPath "src\app\partes\[id]\page.tsx") -Pattern "Firma del cliente" -Quiet
$ok3 = !(Select-String -LiteralPath (Join-Path $RepoPath "src\app\partes\[id]\page.tsx") -Pattern "firmaResp \|\| !firmaCliente" -Quiet)
$ok4 = Select-String -LiteralPath (Join-Path $RepoPath "src\app\partes\[id]\page.tsx") -Pattern "safeName" -Quiet
$ok5 = !(Select-String -LiteralPath (Join-Path $RepoPath "src\app\partes\[id]\page.tsx") -Pattern "confirm\(" -Quiet)
$ok6 = Select-String -LiteralPath (Join-Path $RepoPath "src\lib\pdf\generatePartePdf.ts") -Pattern "Creado por:" -Quiet
$ok7 = Select-String -LiteralPath (Join-Path $RepoPath "src\app\api\partes\email\route.ts") -Pattern "FIXED_TO" -Quiet
if ($ok1) { Write-Host "    OK: materiales eliminados" -ForegroundColor Green } else { Write-Host "    ERROR: materiales" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: firma cliente al final" -ForegroundColor Green } else { Write-Host "    ERROR: firma" -ForegroundColor Red }
if ($ok3) { Write-Host "    OK: boton firmar solo cliente" -ForegroundColor Green } else { Write-Host "    ERROR: boton" -ForegroundColor Red }
if ($ok4) { Write-Host "    OK: safeName en upload" -ForegroundColor Green } else { Write-Host "    ERROR: safeName" -ForegroundColor Red }
if ($ok5) { Write-Host "    OK: sin confirm()" -ForegroundColor Green } else { Write-Host "    ERROR: queda confirm" -ForegroundColor Red }
if ($ok6) { Write-Host "    OK: cabecera PDF con creador" -ForegroundColor Green } else { Write-Host "    ERROR: PDF" -ForegroundColor Red }
if ($ok7) { Write-Host "    OK: email FIXED_TO" -ForegroundColor Green } else { Write-Host "    ERROR: email" -ForegroundColor Red }
Write-Host ""
Write-Host '  git add "src\app\partes\[id]\page.tsx" src\lib\pdf\generatePartePdf.ts src\app\api\partes\email\route.ts'
Write-Host '  git commit -m "fix: partes completo - sin materiales, firma cliente al final, PDF mejorado, email auto"'
Write-Host '  git push'
