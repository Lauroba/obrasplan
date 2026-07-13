#Requires -Version 5.1
# fix-partes-email-v2.ps1
# El email no llegaba por 3 razones:
#
# 1. DOMINIO onboarding@resend.dev: Resend en modo sandbox solo entrega
#    a destinatarios verificados en la cuenta. Usando CC el admin podia
#    ser bloqueado. FIX: lauroba.eneko@gmail.com va en "to[]" directamente.
#
# 2. toEmail NULO: si la obra no tenia contacto_obra_email, el campo
#    devuelve null -> la API recibia null como toEmail -> fallo silencioso.
#    FIX: siempre se asigna lauroba.eneko@gmail.com como fallback en page.tsx
#    antes de llamar a la API.
#
# 3. ERRORES SILENCIADOS: catch{} vacio ocultaba cualquier error de Resend.
#    FIX: logs en consola del servidor (Vercel Functions logs) y en el cliente.
#    Para ver los logs: Vercel Dashboard -> proyecto -> Functions -> Logs.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Fix email partes v2" -ForegroundColor Cyan

Write-Host "  -> src\app\api\partes\email\route.ts" -ForegroundColor Gray
$dst = "src\app\api\partes\email\route.ts"
$content = @'
import { NextRequest, NextResponse } from "next/server";
import { generatePartePdf } from "@/lib/pdf/generatePartePdf";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(req: NextRequest) {
  try {
    const { parteId, toEmail } = await req.json();
    if (!parteId || !toEmail) return NextResponse.json({ error: "parteId and toEmail required" }, { status: 400 });

    const RESEND_API_KEY = process.env.RESEND_API_KEY;
    if (!RESEND_API_KEY) return NextResponse.json({ error: "RESEND_API_KEY not configured" }, { status: 500 });

    const supabase = createAdminClient();

    // Fetch settings for CC and design
    const { data: settings } = await supabase.from("app_settings").select("value").eq("key", "partes_email").single();
    const config = settings?.value || {};
    const ccEmails: string[] = config.cc_emails || [];
    const empresaNombre = config.empresa_nombre || "LOYNEK Soluciones Técnicas";
    const footerText = config.footer_text || "Este email ha sido enviado automáticamente desde ObrasPlan";
    const colorPrimario = config.color_primario || "#DC2626";

    // Fetch parte info for email body
    const { data: parte } = await supabase.from("partes_diarios").select("*, obra:obras(nombre, contacto_obra_nombre)").eq("id", parteId).single();
    if (!parte) return NextResponse.json({ error: "Parte not found" }, { status: 404 });

    const obraName = parte.obra?.nombre || "Sin obra";
    const contactName = parte.obra?.contacto_obra_nombre || "";
    const fecha = parte.fecha ? new Date(parte.fecha + "T12:00:00").toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" }) : "";

    // Generate PDF
    const pdfData = await generatePartePdf(parteId);

    // Get download links for documents and audios
    const { data: docs } = await supabase.from("documentos").select("nombre_archivo, storage_path, tipo").eq("parte_id", parteId);
    const { data: audios } = await supabase.from("parte_audios").select("nombre_archivo, storage_path").eq("parte_id", parteId);

    const attachmentLinks: { name: string; url: string; type: string }[] = [];

    for (const doc of (docs || [])) {
      const { data: signed } = await supabase.storage.from("documentos").createSignedUrl(doc.storage_path, 604800); // 7 days
      if (signed?.signedUrl) attachmentLinks.push({ name: doc.nombre_archivo, url: signed.signedUrl, type: doc.tipo || "documento" });
    }
    for (const audio of (audios || [])) {
      const { data: signed } = await supabase.storage.from("audios").createSignedUrl(audio.storage_path, 604800);
      if (signed?.signedUrl) attachmentLinks.push({ name: audio.nombre_archivo, url: signed.signedUrl, type: "audio" });
    }

    // Build attachments HTML
    let attachmentsHtml = "";
    if (attachmentLinks.length > 0) {
      attachmentsHtml = `
        <div style="margin-top: 20px; padding: 15px; background: #f0f0f0; border-radius: 8px;">
          <p style="color: #333; font-weight: bold; margin: 0 0 10px 0; font-size: 14px;">Documentos adjuntos:</p>
          ${attachmentLinks.map((a) => `<p style="margin: 5px 0;"><a href="${a.url}" style="color: ${colorPrimario}; text-decoration: none;">📎 ${a.name}</a> <span style="color: #999; font-size: 12px;">(${a.type})</span></p>`).join("")}
        </div>
      `;
    }

    // Build email
    // ADMIN siempre en "to" para garantizar entrega independiente del dominio
    const ADMIN_EMAIL = "lauroba.eneko@gmail.com";
    const toList = toEmail && toEmail !== ADMIN_EMAIL
      ? [toEmail, ADMIN_EMAIL]   // cliente + admin
      : [ADMIN_EMAIL];            // solo admin si no hay email de obra
    console.log("[partes/email] Enviando a:", toList, "| parteId:", parteId);
    const emailPayload: any = {
      from: `${empresaNombre} <onboarding@resend.dev>`,
      to: toList,
      subject: `Parte de trabajo — ${obraName} — ${fecha}`,
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
          <div style="background: ${colorPrimario}; padding: 20px; text-align: center; border-radius: 8px 8px 0 0;">
            <h1 style="color: white; margin: 0; font-size: 20px;">${empresaNombre} — Parte de Trabajo</h1>
          </div>
          <div style="padding: 20px; background: #f9f9f9;">
            <p style="color: #333;">Estimado/a ${contactName || ""},</p>
            <p style="color: #333;">Adjunto el parte de trabajo correspondiente a la obra <strong>${obraName}</strong> del <strong>${fecha}</strong>.</p>
            <p style="color: #333;">Encontrará el parte en formato PDF adjunto a este email.</p>
            ${attachmentsHtml}
            <hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;" />
            <p style="color: #999; font-size: 12px;">${footerText}</p>
          </div>
        </div>
      `,
      attachments: [{ filename: pdfData.filename, content: pdfData.pdf }],
    };

    // CC adicional desde configuración (opcional)
    if (ccEmails.length > 0) {
      emailPayload.cc = ccEmails;
    }

    // Send via Resend
    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${RESEND_API_KEY}` },
      body: JSON.stringify(emailPayload),
    });

    if (!emailRes.ok) {
      const errText = await emailRes.text();
      let errMsg = errText;
      try { errMsg = JSON.parse(errText).message || errText; } catch {}
      console.error("[partes/email] Error Resend:", errMsg, "| to:", toList);
      return NextResponse.json({ error: `Error Resend: ${errMsg}` }, { status: 400 });
    }

    const emailResult = await emailRes.json();
    console.log("[partes/email] Email enviado OK. ID:", emailResult.id, "| to:", toList);
    return NextResponse.json({ success: true, emailId: emailResult.id });
  } catch (err: any) {
    return NextResponse.json({ error: err.message || "Error sending email" }, { status: 500 });
  }
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

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
    // Envío automático al firmar — sin confirmación del usuario.
    // lauroba.eneko@gmail.com siempre recibe el email (gestionado en la API route).
    setSendingEmail(true);
    try {
      // toEmail puede ser null si la obra no tiene email — la route lo maneja
      let toEmail = "lauroba.eneko@gmail.com";
      if (form.obra_id) {
        const { data: obraEmail } = await supabase
          .from("obras").select("contacto_obra_email").eq("id", form.obra_id).single();
        if (obraEmail?.contacto_obra_email) {
          toEmail = obraEmail.contacto_obra_email;
        }
      }
      const res = await fetch("/api/partes/email", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ parteId: id, toEmail }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        console.error("[firma] Error email:", (err as any).error);
      }
    } catch (e) {
      console.error("[firma] Error inesperado al enviar email:", e);
    }
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
      const path = `partes/${id}/${Date.now()}_${file.name}`;
      const { error: uploadErr } = await supabase.storage.from("documentos").upload(path, file);
      if (uploadErr) { errors.push(`${file.name}: ${uploadErr.message}`); continue; }
      const insertData: any = {
        parte_id: id, nombre_archivo: file.name,
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

        {/* Líneas */}
        <div className="card p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-surface-900">Trabajos / Materiales</h2>
            {isEditable && <button type="button" onClick={addLinea} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-brand-600 bg-brand-50 rounded-lg hover:bg-brand-100"><Plus className="w-3.5 h-3.5" />Línea</button>}
          </div>
          {lineas.length === 0 ? <p className="text-sm text-surface-400 text-center py-4">Sin líneas</p> : isEditable ? (
            <div className="space-y-2">
              <div className="grid grid-cols-12 gap-2 px-2">
                <div className="col-span-2 text-[10px] font-semibold text-surface-400 uppercase">Tipo</div>
                <div className="col-span-3 text-[10px] font-semibold text-surface-400 uppercase">Concepto</div>
                <div className="col-span-2 text-[10px] font-semibold text-surface-400 uppercase">Fabricante</div>
                <div className="col-span-2 text-[10px] font-semibold text-surface-400 uppercase">Producto</div>
                <div className="col-span-1 text-[10px] font-semibold text-surface-400 uppercase">Cant.</div>
                <div className="col-span-1 text-[10px] font-semibold text-surface-400 uppercase">Uds.</div>
                <div className="col-span-1"></div>
              </div>
              {lineas.map((l, idx) => (
                <div key={idx} className="grid grid-cols-12 gap-2 items-center bg-surface-50 rounded-lg p-2 border border-surface-100">
                  <div className="col-span-2"><select value={l.tipo_trabajo_id} onChange={(e) => { updateLinea(idx, "tipo_trabajo_id", e.target.value); const t = tiposTrabajo.find((tt) => tt.id === e.target.value); if (t && !l.concepto) updateLinea(idx, "concepto", t.nombre); }} className={icSm}><option value="">Tipo...</option>{tiposTrabajo.map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}</select></div>
                  <div className="col-span-3"><input type="text" value={l.concepto} onChange={(e) => updateLinea(idx, "concepto", e.target.value)} placeholder="Descripción" className={icSm} /></div>
                  <div className="col-span-2"><input type="text" value={l.fabricante} onChange={(e) => updateLinea(idx, "fabricante", e.target.value)} placeholder="Fabricante" className={icSm} /></div>
                  <div className="col-span-2"><input type="text" value={l.producto} onChange={(e) => updateLinea(idx, "producto", e.target.value)} placeholder="Producto" className={icSm} /></div>
                  <div className="col-span-1"><input type="number" value={l.cantidad} onChange={(e) => updateLinea(idx, "cantidad", e.target.value)} step="any" className={icSm} /></div>
                  <div className="col-span-1"><input type="text" value={l.unidades} onChange={(e) => updateLinea(idx, "unidades", e.target.value)} placeholder="uds" className={icSm} /></div>
                  <div className="col-span-1 flex justify-center"><button type="button" onClick={() => removeLinea(idx)} className="p-1 rounded text-surface-400 hover:text-red-500"><Trash2 className="w-3.5 h-3.5" /></button></div>
                </div>
              ))}
            </div>
          ) : (
            <table className="w-full text-sm">
              <thead><tr className="border-b border-surface-200">
                <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Concepto</th>
                <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Tipo</th>
                <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Fabricante</th>
                <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Producto</th>
                <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Cant.</th>
                <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Uds.</th>
              </tr></thead>
              <tbody>{lineas.map((l, i) => {
                const tipo = tiposTrabajo.find((t) => t.id === l.tipo_trabajo_id);
                return (
                  <tr key={i} className="border-b border-surface-50">
                    <td className="py-2 px-2 font-medium text-surface-900">{l.concepto}</td>
                    <td className="py-2 px-2 text-surface-600">{tipo?.nombre || "—"}</td>
                    <td className="py-2 px-2 text-surface-600">{l.fabricante || "—"}</td>
                    <td className="py-2 px-2 text-surface-600">{l.producto || "—"}</td>
                    <td className="py-2 px-2 text-right text-surface-900 font-medium">{l.cantidad || "—"}</td>
                    <td className="py-2 px-2 text-surface-600">{l.unidades || "—"}</td>
                  </tr>
                );
              })}</tbody>
            </table>
          )}
        </div>

        {/* Observaciones */}
        <div className="card p-6">
          <h2 className="text-sm font-semibold text-surface-900 mb-3">Observaciones</h2>
          <textarea value={form.observaciones} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} disabled={!isEditable}
            rows={5} placeholder="Observaciones, transcripciones de audio..." className={(isEditable ? ic : icDisabled) + " resize-y font-mono text-xs"} />
        </div>

        {/* Firmas */}
        <div className="card p-6">
          <h2 className="text-sm font-semibold text-surface-900 mb-4">Firmas</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <SignatureCanvas label="Cliente" value={firmaCliente} onChange={setFirmaCliente} disabled={!isEditable} />
            <SignatureCanvas label={`Responsable — ${form.responsable_empresa || "Empresa"}`} value={firmaResp} onChange={setFirmaResp} disabled={!isEditable} />
          </div>
        </div>

        {/* Documentos */}
        <div className="card p-6">
          <input ref={fileInputRef} type="file" multiple accept="image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt" className="hidden" onChange={handleUploadFile} />
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
            {(!firmaResp || !firmaCliente) && (
              <p className="text-xs text-amber-600 flex items-center gap-1">
                ⚠ Para firmar se necesitan ambas firmas{!firmaResp ? " (falta responsable)" : ""}{!firmaCliente ? " (falta cliente)" : ""}
              </p>
            )}
            {firmaResp && firmaCliente && <div />}
            <div className="flex items-center gap-3 ml-auto">
            <button onClick={handleSave} disabled={saving} className="flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-surface-700 bg-surface-200 rounded-lg hover:bg-surface-300 disabled:opacity-60">
              {saving && <Loader2 className="w-4 h-4 animate-spin" />}<Save className="w-4 h-4" />Guardar
            </button>
            <button onClick={handleFirmar} disabled={saving || !firmaResp || !firmaCliente} title={!firmaResp || !firmaCliente ? "Ambas firmas son obligatorias" : ""} className="flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-white bg-emerald-500 rounded-lg hover:bg-emerald-600 disabled:opacity-60">
              {saving && <Loader2 className="w-4 h-4 animate-spin" />}<CheckCircle2 className="w-4 h-4" />Firmar
            </button>
            </div>
          </div>
        )}
      </div>
    </div></AppLayout>
  );
}
'@
$dir = Split-Path -Parent (Join-Path $RepoPath $dst)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)

$ok1 = Select-String -LiteralPath (Join-Path $RepoPath "src\app\api\partes\email\route.ts") -Pattern "toList" -Quiet
$ok2 = Select-String -LiteralPath (Join-Path $RepoPath "src\app\api\partes\email\route.ts") -Pattern "console.log" -Quiet
$ok3 = Select-String -LiteralPath (Join-Path $RepoPath "src\app\partes\[id]\page.tsx") -Pattern "contacto_obra_email" -Quiet
if ($ok1) { Write-Host "    OK: admin en to[] directamente" -ForegroundColor Green }
else { Write-Host "    ERROR: falta toList" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: logs en route.ts" -ForegroundColor Green }
else { Write-Host "    ERROR: faltan logs" -ForegroundColor Red }
if ($ok3) { Write-Host "    OK: toEmail seguro en page.tsx" -ForegroundColor Green }
else { Write-Host "    ERROR" -ForegroundColor Red }
Write-Host ""
Write-Host "VERIFICAR ENTREGA:" -ForegroundColor Cyan
Write-Host "  1. Firma un parte"
Write-Host "  2. Ve a Vercel Dashboard -> tu proyecto -> Deployments"
Write-Host "     -> Functions -> ver logs de /api/partes/email"
Write-Host "  3. Busca lineas '[partes/email] Enviando a:' y '[partes/email] Email enviado OK'"
Write-Host "  4. Si ves error de Resend -> revisar dominio en resend.com/domains"
Write-Host ""
Write-Host '  git add src\app\api\partes\email\route.ts "src\app\partes\[id]\page.tsx"'
Write-Host '  git commit -m "fix: email partes - admin en to[], logs, toEmail seguro"'
Write-Host '  git push'
