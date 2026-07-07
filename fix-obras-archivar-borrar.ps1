#Requires -Version 5.1
# fix-obras-archivar-borrar.ps1
# Anade manejo de errores en handleArchive y handleDelete de obras.
# Antes: si el UPDATE/DELETE fallaba silenciosamente, no se veia ningun error.
# Ahora: muestra el error exacto de Supabase en un alert para diagnosticar.
# EJECUTAR TAMBIEN: fix_rls_obras.sql en Supabase para corregir la RLS.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Escribiendo obras/[id]/page.tsx" -ForegroundColor Cyan

$dst = "src\app\obras\[id]\page.tsx"
$content = @'
"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { useParams, useRouter } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import ResourceAvatar from "@/components/shared/ResourceAvatar";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import type { Obra, Asignacion, RecursoHumano, Maquinaria, Tarea, TipoTarea, EstadoObra, Documento, ParteDiario } from "@/lib/types/database";
import {
  Building2, ArrowLeft, MapPin, Users, Wrench, Truck, ClipboardList, FileText,
  Loader2, Plus, Trash2, CheckCircle2, Clock, ListTodo, Upload, History,
  File, Image as ImageIcon, Save, MessageSquare, ExternalLink, Pencil,
  FileSignature, Archive, Eye, AlertTriangle, Download
} from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils/cn";
import ChecklistPanel from "@/components/obras/ChecklistPanel";

type Tab = "general" | "recursos" | "tareas" | "partes" | "documentos" | "checklists" | "logs";

export default function ObraDetallePage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { user } = useAuthStore();
  const isAdmin = user?.role === "admin";
  const supabase = createClient();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [obra, setObra] = useState<Obra | null>(null);
  const [asignaciones, setAsignaciones] = useState<Asignacion[]>([]);
  const [tareas, setTareas] = useState<Tarea[]>([]);
  const [tiposTarea, setTiposTarea] = useState<TipoTarea[]>([]);
  const [estados, setEstados] = useState<EstadoObra[]>([]);
  const [rrhh, setRrhh] = useState<RecursoHumano[]>([]);
  const [maq, setMaq] = useState<Record<string, Maquinaria>>({});
  const [veh, setVeh] = useState<Record<string, any>>({});
  const [documentos, setDocumentos] = useState<Documento[]>([]);
  const [partes, setPartes] = useState<any[]>([]);
  const [tiposObra, setTiposObra] = useState<any[]>([]);
  const [obraTipos, setObraTipos] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<Tab>("general");
  const [logs, setLogs] = useState<any[]>([]);
  const [loadingLogs, setLoadingLogs] = useState(false);
  const [observaciones, setObservaciones] = useState("");
  const [obsSaving, setObsSaving] = useState(false);
  const [obsChanged, setObsChanged] = useState(false);
  const [downloadingPdf, setDownloadingPdf] = useState(false);
  const [taskModal, setTaskModal] = useState(false);
  const [taskForm, setTaskForm] = useState({ descripcion: "", tipo_tarea_id: "", prioridad: "media" as any, fecha_limite: "", asignado_a: "" });
  const [taskSaving, setTaskSaving] = useState(false);
  const [completeModal, setCompleteModal] = useState<Tarea | null>(null);
  const [completeComment, setCompleteComment] = useState("");
  const [editTask, setEditTask] = useState<Tarea | null>(null);
  const [editTaskForm, setEditTaskForm] = useState({ descripcion: "", tipo_tarea_id: "", prioridad: "media" as any, fecha_limite: "", asignado_a: "" });
  const [editTaskSaving, setEditTaskSaving] = useState(false);
  const [uploading, setUploading] = useState(false);

  const fetchLogs = useCallback(async () => {
    if (!id) return;
    setLoadingLogs(true);
    const { data } = await (supabase.from("audit_log") as any)
      .select("id, accion, entidad, modulo, descripcion, user_rol, created_at, valor_anterior, valor_nuevo, user:users(nombre)")
      .eq("obra_id", id)
      .order("created_at", { ascending: false })
      .limit(200);
    setLogs(data || []);
    setLoadingLogs(false);
  }, [id]);

  // Cargar logs al abrir la pestaña (hook antes de cualquier return condicional)
  useEffect(() => { if (tab === "logs") fetchLogs(); }, [tab, fetchLogs]);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [obraRes, asigRes, tareasRes, tiposRes, estadosRes, rrhhRes, maqRes, vehRes, docsRes, partesRes, tiposObraRes, obraTiposRes] = await Promise.all([
      supabase.from("obras").select("*, cliente:clientes(*), estado_custom:estados_obra(*)").eq("id", id).single(),
      supabase.from("asignaciones").select("*").eq("obra_id", id),
      supabase.from("tareas").select("*, tipo_tarea:tipo_tarea(nombre), recurso_asignado:recursos_humanos(nombre, foto_url)").eq("obra_id", id).order("created_at", { ascending: false }),
      supabase.from("tipo_tarea").select("*").eq("activo", true).order("nombre"),
      supabase.from("estados_obra").select("*").eq("activo", true).order("nombre"),
      supabase.from("recursos_humanos").select("*").eq("activo", true),
      supabase.from("maquinaria").select("*").eq("activo", true),
      supabase.from("vehiculos").select("*").eq("activo", true),
      supabase.from("documentos").select("*").eq("obra_id", id).is("parte_id", null).order("created_at", { ascending: false }),
      supabase.from("partes_diarios").select("*, creator:users!partes_diarios_created_by_fkey(nombre)").eq("obra_id", id).order("fecha", { ascending: false }),
      supabase.from("tipos_obra").select("*").eq("activo", true).order("nombre"),
      supabase.from("obra_tipos_obra").select("tipo_obra_id").eq("obra_id", id),
    ]);
    const obraData = obraRes.data as Obra | null;
    setObra(obraData); setObservaciones(obraData?.observaciones || ""); setObsChanged(false);
    setAsignaciones(asigRes.data || []); setTareas((tareasRes.data as any[]) || []);
    setTiposTarea(tiposRes.data || []); setEstados(estadosRes.data || []);
    setRrhh(rrhhRes.data || []); setDocumentos((docsRes.data as Documento[]) || []);
    setPartes(partesRes.data || []); setTiposObra(tiposObraRes.data || []);
    setObraTipos((obraTiposRes.data || []).map((t: any) => t.tipo_obra_id));
    const maqMap: Record<string, any> = {}; (maqRes.data || []).forEach((r: any) => maqMap[r.id] = r); setMaq(maqMap);
    const vehMap: Record<string, any> = {}; (vehRes.data || []).forEach((r: any) => vehMap[r.id] = r); setVeh(vehMap);
    setLoading(false);
  }, [id]);
  useEffect(() => { fetchData(); }, [fetchData]);

  const handleChangeEstado = async (estadoId: string) => { await (supabase.from("obras") as any).update({ estado_obra_id: estadoId || null }).eq("id", id); fetchData(); };
  const handleSaveObservaciones = async () => { setObsSaving(true); await (supabase.from("obras") as any).update({ observaciones }).eq("id", id); setObsSaving(false); setObsChanged(false); };
  const handleArchive = async () => {
    const newArchived = !obra?.archivada;
    const update: any = { archivada: newArchived };
    if (newArchived) { const cerrada = estados.find((e) => e.nombre.toLowerCase().includes("terminada") || e.nombre.toLowerCase().includes("cerrada")); if (cerrada) update.estado_obra_id = cerrada.id; }
    const { error } = await (supabase.from("obras") as any).update(update).eq("id", id);
    if (error) { alert("Error al archivar: " + error.message); return; }
    fetchData();
  };
  const handleDelete = async () => {
    if (!confirm(`¿Seguro que quieres ELIMINAR la obra "${obra?.nombre}"?\n\nSe borrarán todas las asignaciones, tareas, partes y documentos asociados.\n\nEsta acción no se puede deshacer.`)) return;
    const { error } = await (supabase.from("obras") as any).delete().eq("id", id);
    if (error) { alert("Error al eliminar la obra: " + error.message + "\n\nSi persiste, comprueba si hay registros vinculados que bloquean el borrado."); return; }
    router.push("/obras");
  };
  const handleCreateTask = async (e: React.FormEvent) => { e.preventDefault(); setTaskSaving(true); await (supabase.from("tareas") as any).insert({ obra_id: id, descripcion: taskForm.descripcion, tipo_tarea_id: taskForm.tipo_tarea_id || null, prioridad: taskForm.prioridad, fecha_limite: taskForm.fecha_limite || null, asignado_a: taskForm.asignado_a || null, created_by: user?.id }); setTaskSaving(false); setTaskModal(false); setTaskForm({ descripcion: "", tipo_tarea_id: "", prioridad: "media", fecha_limite: "", asignado_a: "" }); fetchData(); };
  const handleCompleteTask = async () => { if (!completeModal) return; await (supabase.from("tareas") as any).update({ estado: "completada", comentario_cierre: completeComment || null, completada_at: new Date().toISOString(), completada_by: user?.id }).eq("id", completeModal.id); setCompleteModal(null); setCompleteComment(""); fetchData(); };
  const handleDeleteTask = async (taskId: string) => { await (supabase.from("tareas") as any).delete().eq("id", taskId); fetchData(); };
  const handleReopenTask = async (taskId: string) => { await (supabase.from("tareas") as any).update({ estado: "pendiente" }).eq("id", taskId); setEditTask(null); fetchData(); };
  const handleOpenEditTask = (t: Tarea) => { setEditTask(t); setEditTaskForm({ descripcion: t.descripcion, tipo_tarea_id: t.tipo_tarea_id || "", prioridad: t.prioridad, fecha_limite: t.fecha_limite || "", asignado_a: t.asignado_a || "" }); };
  const handleSaveEditTask = async (e: React.FormEvent) => { e.preventDefault(); if (!editTask) return; setEditTaskSaving(true); await (supabase.from("tareas") as any).update({ descripcion: editTaskForm.descripcion, tipo_tarea_id: editTaskForm.tipo_tarea_id || null, prioridad: editTaskForm.prioridad, fecha_limite: editTaskForm.fecha_limite || null, asignado_a: editTaskForm.asignado_a || null }).eq("id", editTask.id); setEditTaskSaving(false); setEditTask(null); fetchData(); };
  const handleOpenDoc = async (doc: Documento) => { const { data } = await supabase.storage.from("documentos").createSignedUrl(doc.storage_path, 300); if (data?.signedUrl) window.open(data.signedUrl, "_blank"); };
  const handleDeleteDoc = async (doc: Documento) => { await supabase.storage.from("documentos").remove([doc.storage_path]); await (supabase.from("documentos") as any).delete().eq("id", doc.id); fetchData(); };
  const handleUploadFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    setUploading(true);
    let errors: string[] = [];
    const sanitize = (name: string) => name.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-zA-Z0-9._-]/g, "_");
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const safeName = sanitize(file.name);
      const path = `obras/${id}/${Date.now()}_${safeName}`;
      const { error: uploadErr } = await supabase.storage.from("documentos").upload(path, file);
      if (uploadErr) { errors.push(`${file.name}: ${uploadErr.message}`); continue; }
      const { error: insertErr } = await (supabase.from("documentos") as any).insert({
        obra_id: id, nombre_archivo: file.name,
        tipo: file.type.startsWith("image/") ? "foto" : file.type === "application/pdf" ? "pdf" : "documento",
        categoria: "general", storage_path: path, tamano: file.size, mime_type: file.type, uploaded_by: user?.id,
      });
      if (insertErr) errors.push(`${file.name} (DB): ${insertErr.message}`);
    }
    setUploading(false);
    if (fileInputRef.current) fileInputRef.current.value = "";
    if (errors.length > 0) alert("Errores al subir:\n" + errors.join("\n"));
    fetchData();
  };
  const getTaskDateColor = (f: string | null) => { if (!f) return ""; const d = (new Date(f).getTime() - Date.now()) / 86400000; if (d < 0) return "text-red-600 bg-red-50"; if (d < 3) return "text-amber-600 bg-amber-50"; return "text-surface-600"; };
  const formatBytes = (b: number | null) => { if (!b) return ""; if (b < 1024) return b + " B"; if (b < 1048576) return (b / 1024).toFixed(0) + " KB"; return (b / 1048576).toFixed(1) + " MB"; };

  if (loading) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;
  if (!obra) return <AppLayout><div className="text-center py-20"><p className="text-surface-500">Obra no encontrada</p></div></AppLayout>;


  const tabs: { id: Tab; label: string; icon: typeof Building2; count?: number }[] = [
    { id: "general", label: "General", icon: Building2 },
    { id: "recursos", label: "Recursos", icon: Users, count: asignaciones.length },
    { id: "tareas", label: "Tareas", icon: ListTodo, count: tareas.filter((t) => t.estado === "pendiente").length },
    { id: "partes", label: "Partes", icon: ClipboardList, count: partes.length },
    { id: "documentos", label: "Documentos", icon: FileText, count: documentos.length },
    { id: "checklists", label: "Checklists", icon: CheckCircle2 },
    { id: "logs", label: "Logs", icon: History },
  ];
  const humanos = asignaciones.filter((a) => a.recurso_tipo === "humano");
  const maquinas = asignaciones.filter((a) => a.recurso_tipo === "maquinaria");
  const vehiculos = asignaciones.filter((a) => a.recurso_tipo === "vehiculo");
  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  const prioColors: Record<string, string> = { alta: "bg-red-100 text-red-700", media: "bg-amber-100 text-amber-700", baja: "bg-blue-100 text-blue-700" };
  const estadoBadgeParte: Record<string, { label: string; class: string }> = { pendiente: { label: "Pendiente", class: "bg-amber-100 text-amber-700" }, firmado: { label: "Firmado", class: "bg-emerald-100 text-emerald-700" }, borrador: { label: "Borrador", class: "bg-surface-100 text-surface-600" } };
  const obraTipoNames = obraTipos.map((tid) => tiposObra.find((t: any) => t.id === tid)?.nombre).filter(Boolean);

  return (
    <AppLayout>
      <div className="max-w-5xl mx-auto animate-fade-in">
        {/* Header */}
        <div className="flex items-start gap-4 mb-6">
          <Link href="/obras" className="p-2 mt-1 rounded-lg text-surface-400 hover:bg-surface-100"><ArrowLeft className="w-5 h-5" /></Link>
          <div className="flex-1">
            <div className="flex items-center gap-3">
              <div className="w-3 h-10 rounded-full" style={{ backgroundColor: obra.color || "#DC2626" }} />
              <div>
                <div className="flex items-center gap-2">
                  <h1 className="text-xl font-display font-bold text-surface-900">{obra.nombre}</h1>
                  {obra.archivada && <span className="badge bg-surface-200 text-surface-600 text-[10px]">Archivada</span>}
                </div>
                <div className="flex items-center gap-3 mt-1 text-sm text-surface-500">
                  {obra.direccion && <span className="flex items-center gap-1"><MapPin className="w-3.5 h-3.5" />{obra.direccion}{obra.localidad ? `, ${obra.localidad}` : ""}</span>}
                  {(obra as any).cliente?.nombre && <span>· {(obra as any).cliente.nombre}</span>}
                </div>
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <button onClick={async () => {
              setDownloadingPdf(true);
              try {
                const res = await fetch("/api/obras/pdf", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ obraId: id }) });
                const data = await res.json();
                if (data.pdf) { const link = document.createElement("a"); link.href = `data:application/pdf;base64,${data.pdf}`; link.download = data.filename; link.click(); }
                else alert("Error: " + (data.error || ""));
              } catch (err: any) { alert("Error: " + err.message); }
              setDownloadingPdf(false);
            }} disabled={downloadingPdf} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-violet-700 bg-violet-50 rounded-lg hover:bg-violet-100 disabled:opacity-60">
              {downloadingPdf ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Download className="w-3.5 h-3.5" />} PDF
            </button>
            {isAdmin && (
              <>
                <button onClick={handleArchive} className={cn("flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg", obra.archivada ? "text-blue-700 bg-blue-50 hover:bg-blue-100" : "text-amber-700 bg-amber-50 hover:bg-amber-100")}>
                  {obra.archivada ? <Eye className="w-3.5 h-3.5" /> : <Archive className="w-3.5 h-3.5" />}
                  {obra.archivada ? "Desarchivar" : "Archivar"}
                </button>
                <button onClick={handleDelete} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-red-700 bg-red-50 rounded-lg hover:bg-red-100">
                  <Trash2 className="w-3.5 h-3.5" /> Eliminar
                </button>
                <Link href={`/obras/nueva?edit=${id}`} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">
                  <Pencil className="w-3.5 h-3.5" /> Editar
                </Link>
              </>
            )}
            {isAdmin ? (
              <select value={obra.estado_obra_id || ""} onChange={(e) => handleChangeEstado(e.target.value)}
                className="px-3 py-1.5 rounded-full text-sm font-medium text-white border-0 cursor-pointer focus:outline-none"
                style={{ backgroundColor: (obra as any).estado_custom?.color || "#6B7280" }}>
                <option value="">Sin estado</option>
                {estados.map((es) => <option key={es.id} value={es.id}>{es.nombre}</option>)}
              </select>
            ) : (
              <span className="px-3 py-1.5 rounded-full text-sm font-medium text-white" style={{ backgroundColor: (obra as any).estado_custom?.color || "#6B7280" }}>
                {(obra as any).estado_custom?.nombre || "Sin estado"}
              </span>
            )}
          </div>
        </div>

        {/* Tabs */}
        <div className="flex gap-1 mb-6 border-b border-surface-200 overflow-x-auto">
          {tabs.map((t) => (
            <button key={t.id} onClick={() => setTab(t.id)}
              className={cn("flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 transition-all -mb-px whitespace-nowrap",
                tab === t.id ? "border-brand-500 text-brand-600" : "border-transparent text-surface-500 hover:text-surface-700")}>
              <t.icon className="w-4 h-4" />{t.label}
              {t.count !== undefined && t.count > 0 && <span className="text-[10px] bg-brand-100 text-brand-700 px-1.5 py-0.5 rounded-full">{t.count}</span>}
            </button>
          ))}
        </div>

        {/* GENERAL - all fields */}
        {tab === "general" && (
          <div className="space-y-6">
            <div className="card p-6">
              <h3 className="text-sm font-semibold text-surface-900 mb-4">Datos generales</h3>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Cliente</p><p className="text-sm text-surface-900 mt-1">{(obra as any).cliente?.nombre || "—"}</p></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Tipos de obra</p><div className="flex flex-wrap gap-1 mt-1.5">{obraTipoNames.length > 0 ? obraTipoNames.map((n, i) => <span key={i} className="text-xs px-2 py-0.5 rounded-full bg-brand-50 text-brand-700 border border-brand-200">{n}</span>) : <span className="text-sm text-surface-400">—</span>}</div></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Estado</p><div className="mt-1">{(obra as any).estado_custom ? <span className="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium text-white" style={{ backgroundColor: (obra as any).estado_custom.color }}>{(obra as any).estado_custom.nombre}</span> : <span className="text-sm text-surface-400">Sin estado</span>}</div></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Nº Presupuesto</p><p className="text-sm text-surface-900 mt-1">{(obra as any).num_presupuesto || "—"}</p></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Nº Factura</p><p className="text-sm text-surface-900 mt-1">{(obra as any).num_factura || "—"}</p></div>
              </div>
            </div>

            <div className="card p-6">
              <h3 className="text-sm font-semibold text-surface-900 mb-4">Dirección</h3>
              <div className="grid grid-cols-3 gap-4">
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Dirección</p><p className="text-sm text-surface-900 mt-1">{obra.direccion || "—"}</p></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Localidad</p><p className="text-sm text-surface-900 mt-1">{obra.localidad || "—"}</p></div>
                <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Provincia</p><p className="text-sm text-surface-900 mt-1">{obra.provincia || "—"}</p></div>
              </div>
            </div>

            <div className="card p-6">
              <h3 className="text-sm font-semibold text-surface-900 mb-4">Contacto</h3>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-[10px] font-semibold text-surface-400 uppercase mb-2">Cliente</p>
                  <p className="text-sm text-surface-900">{(obra as any).cliente?.nombre || "—"}</p>
                  <p className="text-xs text-surface-500">{(obra as any).cliente?.telefono || ""} {(obra as any).cliente?.email ? `· ${(obra as any).cliente.email}` : ""}</p>
                </div>
                <div>
                  <p className="text-[10px] font-semibold text-surface-400 uppercase mb-2">Contacto obra</p>
                  <p className="text-sm text-surface-900">{(obra as any).contacto_obra_nombre || "—"}</p>
                  <p className="text-xs text-surface-500">{(obra as any).contacto_obra_telefono || ""} {(obra as any).contacto_obra_email ? `· ${(obra as any).contacto_obra_email}` : ""}</p>
                </div>
              </div>
            </div>

            <div className="card p-6">
              <div className="flex items-center justify-between mb-3">
                <h3 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><MessageSquare className="w-4 h-4 text-surface-400" />Comentarios</h3>
                {isAdmin && obsChanged && <button onClick={handleSaveObservaciones} disabled={obsSaving} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{obsSaving ? <Loader2 className="w-3 h-3 animate-spin" /> : <Save className="w-3 h-3" />}Guardar</button>}
              </div>
              <textarea value={observaciones} onChange={(e) => { setObservaciones(e.target.value); setObsChanged(true); }} rows={4} placeholder="Notas, comentarios..." disabled={!isAdmin} className={ic + " resize-y" + (!isAdmin ? " bg-surface-50 cursor-not-allowed" : "")} />
            </div>
          </div>
        )}

        {/* RECURSOS */}
        {tab === "recursos" && (
          <div className="space-y-4">
            {[{ title: "Personas", icon: Users, tipo: "humano" as const, items: humanos, getName: (rid: string) => rrhh.find((r) => r.id === rid)?.nombre || "?" },
              { title: "Maquinaria", icon: Wrench, tipo: "maquinaria" as const, items: maquinas, getName: (rid: string) => maq[rid]?.nombre || "?" },
              { title: "Vehículos", icon: Truck, tipo: "vehiculo" as const, items: vehiculos, getName: (rid: string) => veh[rid]?.nombre || "?" },
            ].map((g) => {
              // Group by resource, collect date ranges
              const grouped: Record<string, { nombre: string; ranges: { inicio: string; fin: string }[] }> = {};
              g.items.forEach((a) => {
                if (!grouped[a.recurso_id]) grouped[a.recurso_id] = { nombre: g.getName(a.recurso_id), ranges: [] };
                grouped[a.recurso_id].ranges.push({ inicio: a.fecha_inicio, fin: a.fecha_fin });
              });
              // Sort ranges and merge
              Object.values(grouped).forEach((v) => v.ranges.sort((a, b) => a.inicio.localeCompare(b.inicio)));
              const sortedResources = Object.entries(grouped).sort((a, b) => a[1].nombre.localeCompare(b[1].nombre, "es"));

              return (
                <div key={g.title} className="card p-6">
                  <h3 className="flex items-center gap-2 text-sm font-semibold text-surface-900 mb-3"><g.icon className="w-4 h-4 text-surface-400" />{g.title} ({sortedResources.length})</h3>
                  {sortedResources.length === 0 ? <p className="text-sm text-surface-400">Sin asignaciones</p> : (
                    <table className="w-full text-sm">
                      <thead><tr className="border-b border-surface-200">
                        <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2 w-[200px]">Recurso</th>
                        <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-2">Fechas</th>
                        <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-2 w-[80px]">Días</th>
                      </tr></thead>
                      <tbody>{sortedResources.map(([rid, v]) => {
                        const totalDays = v.ranges.reduce((sum, r) => {
                          const s = new Date(r.inicio + "T12:00:00"); const e = new Date(r.fin + "T12:00:00");
                          return sum + Math.round((e.getTime() - s.getTime()) / 86400000) + 1;
                        }, 0);
                        return (
                          <tr key={rid} className="border-b border-surface-50 hover:bg-surface-50/50">
                            <td className="py-2 px-2 font-medium text-surface-900">{v.nombre}</td>
                            <td className="py-2 px-2">
                              <div className="flex flex-wrap gap-1">
                                {v.ranges.map((r, i) => {
                                  const s = new Date(r.inicio + "T12:00:00");
                                  const e = new Date(r.fin + "T12:00:00");
                                  const same = r.inicio === r.fin;
                                  const label = same
                                    ? s.toLocaleDateString("es-ES", { weekday: "short", day: "numeric", month: "short" })
                                    : `${s.toLocaleDateString("es-ES", { day: "numeric", month: "short" })} → ${e.toLocaleDateString("es-ES", { day: "numeric", month: "short" })}`;
                                  return <span key={i} className="text-[10px] px-2 py-0.5 rounded bg-brand-50 text-brand-700">{label}</span>;
                                })}
                              </div>
                            </td>
                            <td className="py-2 px-2 text-right text-surface-600 font-medium">{totalDays}</td>
                          </tr>
                        );
                      })}</tbody>
                    </table>
                  )}
                </div>
              );
            })}
          </div>
        )}

        {/* TAREAS */}
        {tab === "tareas" && (
          <div className="card p-6">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-sm font-semibold text-surface-900">Tareas</h3>
              <button onClick={() => setTaskModal(true)} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-3.5 h-3.5" />Nueva</button>
            </div>
            {tareas.length === 0 ? <p className="text-sm text-surface-500 text-center py-8">Sin tareas</p> : (
              <div className="space-y-2">
                {tareas.map((t) => (
                  <div key={t.id} className={cn("flex items-start gap-3 p-3 rounded-lg border", t.estado === "completada" ? "bg-surface-50 border-surface-100 opacity-60" : "bg-white border-surface-200")}>
                    <button onClick={() => t.estado === "pendiente" ? setCompleteModal(t) : null} className={cn("mt-0.5 shrink-0", t.estado === "completada" ? "text-emerald-500" : "text-surface-300 hover:text-emerald-500")}><CheckCircle2 className="w-5 h-5" /></button>
                    <div className="flex-1 min-w-0 cursor-pointer" onClick={() => handleOpenEditTask(t)}>
                      <p className={cn("text-sm hover:text-brand-600", t.estado === "completada" ? "line-through text-surface-400" : "text-surface-900")}>{t.descripcion}</p>
                      <div className="flex items-center gap-2 mt-1 flex-wrap">
                        <span className={cn("badge text-[10px]", prioColors[t.prioridad])}>{t.prioridad}</span>
                        {(t as any).tipo_tarea?.nombre && <span className="badge bg-surface-100 text-surface-600 text-[10px]">{(t as any).tipo_tarea.nombre}</span>}
                        {(t as any).recurso_asignado?.nombre && <ResourceAvatar nombre={(t as any).recurso_asignado.nombre} foto_url={(t as any).recurso_asignado.foto_url} tipo="humano" size="xs" />}
                        {t.fecha_limite && <span className={cn("text-[10px] px-1.5 py-0.5 rounded", getTaskDateColor(t.fecha_limite))}><Clock className="w-3 h-3 inline mr-0.5" />{new Date(t.fecha_limite).toLocaleDateString("es-ES")}</span>}
                      </div>
                      {t.comentario_cierre && <p className="text-[11px] text-surface-400 mt-1 italic">"{t.comentario_cierre}"</p>}
                    </div>
                    {t.estado === "pendiente" && <button onClick={() => handleDeleteTask(t.id)} className="p-1 rounded text-surface-300 hover:text-red-500"><Trash2 className="w-3.5 h-3.5" /></button>}
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* PARTES */}
        {tab === "partes" && (
          <div className="card p-6">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-sm font-semibold text-surface-900">Partes diarios</h3>
              <button onClick={async () => {
                const toDS = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
                const { data: p } = await (supabase.from("partes_diarios") as any).insert({
                  fecha: toDS(new Date()), created_by: user?.id, estado: "pendiente", obra_id: id,
                  direccion: obra?.direccion || null, localidad: obra?.localidad || null, provincia: obra?.provincia || null,
                  responsable_empresa: user?.nombre || "",
                }).select().single();
                if (p) router.push(`/partes/${p.id}`);
              }} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-3.5 h-3.5" />Nuevo parte</button>
            </div>
            {partes.length === 0 ? <p className="text-sm text-surface-500 text-center py-8">Sin partes</p> : (
              <div className="space-y-2">{partes.map((p) => {
                const est = estadoBadgeParte[p.estado] || estadoBadgeParte.pendiente;
                return (
                  <Link key={p.id} href={`/partes/${p.id}`} className="flex items-center gap-4 p-3 bg-surface-50 rounded-lg border border-surface-100 hover:border-surface-300 group">
                    <div className="text-center shrink-0 w-12"><p className="text-lg font-display font-bold text-surface-900">{new Date(p.fecha + "T12:00:00").getDate()}</p><p className="text-[9px] text-surface-400 uppercase">{new Date(p.fecha + "T12:00:00").toLocaleDateString("es-ES", { month: "short" })}</p></div>
                    <div className="flex-1 min-w-0"><p className="text-sm font-medium text-surface-900 group-hover:text-brand-600">{p.creator?.nombre || "?"}</p><p className="text-xs text-surface-400 truncate">{p.observaciones || ""}</p></div>
                    <div className="flex items-center gap-2 shrink-0">
                      {p.firma_data && <FileSignature className="w-3.5 h-3.5 text-emerald-500" />}
                      {p.firma_cliente && <FileSignature className="w-3.5 h-3.5 text-blue-500" />}
                    </div>
                    <span className={cn("badge text-[10px]", est.class)}>{est.label}</span>
                  </Link>
                );
              })}</div>
            )}
          </div>
        )}

        {/* DOCUMENTOS */}
        {tab === "documentos" && (
          <div className="card p-6">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-sm font-semibold text-surface-900">Documentos</h3>
              {isAdmin && <button onClick={() => fileInputRef.current?.click()} disabled={uploading} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{uploading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Upload className="w-3.5 h-3.5" />}Subir</button>}
            </div>
            <input ref={fileInputRef} type="file" multiple accept="image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt" className="hidden" onChange={handleUploadFile} />
            {documentos.length === 0 ? <div className="text-center py-12 border-2 border-dashed border-surface-200 rounded-xl"><Upload className="w-8 h-8 text-surface-300 mx-auto mb-2" /><p className="text-sm text-surface-500">Sin documentos</p></div> : (
              <div className="space-y-2">{documentos.map((doc) => {
                const isImage = doc.tipo === "foto"; const isPdf = doc.tipo === "pdf";
                return (
                  <div key={doc.id} className="flex items-center gap-3 p-3 bg-surface-50 rounded-lg border border-surface-100 group hover:border-surface-200">
                    <div className={cn("w-10 h-10 rounded-lg flex items-center justify-center shrink-0", isImage ? "bg-violet-100 text-violet-600" : isPdf ? "bg-red-100 text-red-600" : "bg-blue-100 text-blue-600")}>{isImage ? <ImageIcon className="w-5 h-5" /> : isPdf ? <FileText className="w-5 h-5" /> : <File className="w-5 h-5" />}</div>
                    <div className="flex-1 min-w-0 cursor-pointer" onClick={() => handleOpenDoc(doc)}><p className="text-sm font-medium text-surface-900 hover:text-brand-600 truncate">{doc.nombre_archivo}</p><p className="text-[11px] text-surface-400">{formatBytes(doc.tamano)}</p></div>
                    <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100"><button onClick={() => handleOpenDoc(doc)} className="p-1.5 rounded-md text-surface-400 hover:text-brand-600"><ExternalLink className="w-4 h-4" /></button>{isAdmin && <button onClick={() => handleDeleteDoc(doc)} className="p-1.5 rounded-md text-surface-400 hover:text-red-600"><Trash2 className="w-4 h-4" /></button>}</div>
                  </div>
                );
              })}</div>
            )}
          </div>
        )}

        {tab === "logs" && (
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <p className="text-xs text-surface-500">Historial de acciones de esta obra</p>
                    <button onClick={fetchLogs} className="text-xs text-brand-600 hover:underline flex items-center gap-1">
                      <History className="w-3 h-3" />Actualizar
                    </button>
                  </div>
                  {loadingLogs ? (
                    <div className="flex justify-center py-8"><Loader2 className="w-5 h-5 text-brand-500 animate-spin" /></div>
                  ) : logs.length === 0 ? (
                    <div className="text-center py-8 text-sm text-surface-400">Sin registros de actividad para esta obra</div>
                  ) : (
                    <div className="space-y-1.5 max-h-[60vh] overflow-y-auto">
                      {logs.map((log: any) => (
                        <div key={log.id} className="flex items-start gap-3 px-3 py-2.5 rounded-lg bg-surface-50 border border-surface-100 hover:bg-surface-100/60">
                          <div className="shrink-0 mt-0.5">
                            <span className={cn("badge text-[9px]",
                              log.accion === "crear"    ? "bg-emerald-100 text-emerald-700" :
                              log.accion === "eliminar" ? "bg-red-100 text-red-700" :
                              "bg-amber-100 text-amber-700")}>
                              {log.accion}
                            </span>
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className="text-xs text-surface-800 font-medium">
                              {log.descripcion || `${log.accion} en ${log.entidad}`}
                            </p>
                            {/* Mostrar cambios concretos si existen */}
                            {log.valor_anterior && log.valor_nuevo && (() => {
                              const ant = log.valor_anterior as Record<string, any>;
                              const nue = log.valor_nuevo as Record<string, any>;
                              const campos = Object.keys(nue).filter(k =>
                                JSON.stringify(ant[k]) !== JSON.stringify(nue[k]) &&
                                nue[k] !== null && ant[k] !== undefined
                              );
                              if (campos.length === 0) return null;
                              return (
                                <div className="mt-1.5 space-y-0.5">
                                  {campos.map(campo => (
                                    <div key={campo} className="flex items-center gap-1.5 text-[10px]">
                                      <span className="text-surface-400 font-mono">{campo}:</span>
                                      <span className="line-through text-red-400">{String(ant[campo] ?? "—")}</span>
                                      <span className="text-surface-400">→</span>
                                      <span className="text-emerald-600 font-medium">{String(nue[campo] ?? "—")}</span>
                                    </div>
                                  ))}
                                </div>
                              );
                            })()}
                            <p className="text-[10px] text-surface-400 mt-1">
                              {new Date(log.created_at).toLocaleString("es-ES")}
                              {log.user?.nombre && ` · ${log.user.nombre}`}
                              {log.user_rol && ` · ${log.user_rol}`}
                            </p>
                          </div>
                          {log.modulo && (
                            <span className="text-[9px] text-surface-400 shrink-0 font-mono bg-surface-100 px-1.5 py-0.5 rounded">
                              {log.modulo}
                            </span>
                          )}
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}

        {tab === "checklists" && (
          <ChecklistPanel obraId={id} rrhh={rrhh.map((r) => ({ id: r.id, nombre: r.nombre }))} />
        )}
      </div>

      {/* Task modals */}
      <Modal open={taskModal} onClose={() => setTaskModal(false)} title="Nueva tarea">
        <form onSubmit={handleCreateTask} className="space-y-4">
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Descripción *</label><textarea required value={taskForm.descripcion} onChange={(e) => setTaskForm({ ...taskForm, descripcion: e.target.value })} rows={3} placeholder="¿Qué hay que hacer?" className={ic + " resize-none"} /></div>
          <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Tipo</label><select value={taskForm.tipo_tarea_id} onChange={(e) => setTaskForm({ ...taskForm, tipo_tarea_id: e.target.value })} className={ic}><option value="">Sin tipo</option>{tiposTarea.map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}</select></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Prioridad</label><select value={taskForm.prioridad} onChange={(e) => setTaskForm({ ...taskForm, prioridad: e.target.value })} className={ic}><option value="alta">Alta</option><option value="media">Media</option><option value="baja">Baja</option></select></div></div>
          <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Fecha límite</label><input type="date" value={taskForm.fecha_limite} onChange={(e) => setTaskForm({ ...taskForm, fecha_limite: e.target.value })} className={ic} /></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Asignar a</label><select value={taskForm.asignado_a} onChange={(e) => setTaskForm({ ...taskForm, asignado_a: e.target.value })} className={ic}><option value="">Sin asignar</option>{rrhh.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select></div></div>
          <div className="flex justify-end gap-2 pt-2"><button type="button" onClick={() => setTaskModal(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button><button type="submit" disabled={taskSaving || !taskForm.descripcion} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{taskSaving && <Loader2 className="w-4 h-4 animate-spin" />}Crear</button></div>
        </form>
      </Modal>
      <Modal open={!!completeModal} onClose={() => setCompleteModal(null)} title="Completar tarea" size="sm">
        <div className="space-y-4"><p className="text-sm text-surface-700">{completeModal?.descripcion}</p><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Comentario</label><textarea value={completeComment} onChange={(e) => setCompleteComment(e.target.value)} rows={2} placeholder="Opcional" className={ic + " resize-none"} /></div><div className="flex justify-end gap-2"><button onClick={() => setCompleteModal(null)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button><button onClick={handleCompleteTask} className="px-4 py-2.5 text-sm font-medium text-white bg-emerald-500 rounded-lg hover:bg-emerald-600">Completar</button></div></div>
      </Modal>
      <Modal open={!!editTask} onClose={() => setEditTask(null)} title={editTask?.estado === "completada" ? "Tarea completada" : "Editar tarea"}>
        <form onSubmit={handleSaveEditTask} className="space-y-4">
          {editTask?.estado === "completada" && <div className="p-3 bg-emerald-50 border border-emerald-200 rounded-lg"><p className="text-xs font-semibold text-emerald-700 mb-1">Completada el {editTask.completada_at ? new Date(editTask.completada_at).toLocaleDateString("es-ES") : ""}</p>{editTask.comentario_cierre && <p className="text-sm text-emerald-800 italic">"{editTask.comentario_cierre}"</p>}</div>}
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Descripción *</label><textarea required value={editTaskForm.descripcion} onChange={(e) => setEditTaskForm({ ...editTaskForm, descripcion: e.target.value })} rows={3} className={ic + " resize-none"} disabled={editTask?.estado === "completada"} /></div>
          <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Tipo</label><select value={editTaskForm.tipo_tarea_id} onChange={(e) => setEditTaskForm({ ...editTaskForm, tipo_tarea_id: e.target.value })} className={ic} disabled={editTask?.estado === "completada"}><option value="">Sin tipo</option>{tiposTarea.map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}</select></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Prioridad</label><select value={editTaskForm.prioridad} onChange={(e) => setEditTaskForm({ ...editTaskForm, prioridad: e.target.value })} className={ic} disabled={editTask?.estado === "completada"}><option value="alta">Alta</option><option value="media">Media</option><option value="baja">Baja</option></select></div></div>
          <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Fecha límite</label><input type="date" value={editTaskForm.fecha_limite} onChange={(e) => setEditTaskForm({ ...editTaskForm, fecha_limite: e.target.value })} className={ic} disabled={editTask?.estado === "completada"} /></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Asignar a</label><select value={editTaskForm.asignado_a} onChange={(e) => setEditTaskForm({ ...editTaskForm, asignado_a: e.target.value })} className={ic} disabled={editTask?.estado === "completada"}><option value="">Sin asignar</option>{rrhh.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select></div></div>
          <div className="flex items-center justify-between pt-2">
            {editTask?.estado === "completada" ? <button type="button" onClick={() => editTask && handleReopenTask(editTask.id)} className="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium text-amber-700 bg-amber-50 rounded-lg hover:bg-amber-100"><Clock className="w-4 h-4" />Reabrir</button> :
              <button type="button" onClick={() => { setEditTask(null); setCompleteModal(editTask); }} className="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium text-emerald-700 bg-emerald-50 rounded-lg hover:bg-emerald-100"><CheckCircle2 className="w-4 h-4" />Hecha</button>}
            <div className="flex items-center gap-2"><button type="button" onClick={() => setEditTask(null)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cerrar</button>
              {editTask?.estado !== "completada" && <button type="submit" disabled={editTaskSaving || !editTaskForm.descripcion} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{editTaskSaving && <Loader2 className="w-4 h-4 animate-spin" />}Guardar</button>}</div>
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
Write-Host "    Escrito: $dst" -ForegroundColor Green

$ok = Select-String -LiteralPath (Join-Path $RepoPath "src\app\obras\[id]\page.tsx") -Pattern "Error al eliminar la obra" -Quiet
if ($ok) { Write-Host "    OK: manejo de errores anadido" -ForegroundColor Green }
else { Write-Host "    ERROR" -ForegroundColor Red }
Write-Host ""
Write-Host "RECORDATORIO: ejecutar fix_rls_obras.sql en Supabase" -ForegroundColor Yellow
Write-Host ""
Write-Host '  git add -A'
Write-Host '  git commit -m "fix: error handling en archivar y borrar obra"'
Write-Host '  git push'
