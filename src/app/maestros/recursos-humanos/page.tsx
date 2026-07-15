"use client";

import { useState, useEffect, useCallback, Suspense, useRef } from "react";
import type React from "react";
import { useSearchParams } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import Modal from "@/components/shared/Modal";
import PhotoUpload from "@/components/shared/PhotoUpload";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { RecursoHumano } from "@/lib/types/database";
import { Users, Loader2, ShieldCheck, UserX, UserCheck, Eye, EyeOff, CalendarOff, Pencil } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface RHWithUser extends RecursoHumano { user_role?: string; user_activo?: boolean; user_id?: string; }

const emptyForm = { nombre: "", perfil: "", telefono: "", email: "", password: "", role: "partes", rol_id: "", foto_url: "", asignable: true, fecha_inicio: new Date().toISOString().slice(0, 10), fecha_fin: "" };

// Componente interno que usa useSearchParams — envuelto en Suspense
function EditFromURL({ data, puedeEditar, setForm, setEditingId, setEditingActivo, setError, setModalOpen, emptyFormRef }: {
  data: RHWithUser[]; puedeEditar: boolean;
  setForm: (f: any) => void; setEditingId: (id: string | null) => void;
  setEditingActivo: (v: boolean) => void; setError: (e: string) => void;
  setModalOpen: (v: boolean) => void; emptyFormRef: React.MutableRefObject<typeof emptyForm>;
}) {
  const searchParams = useSearchParams();
  useEffect(() => {
    const editId = searchParams.get("edit");
    if (!editId || !puedeEditar || data.length === 0) return;
    const item = data.find((r) => r.id === editId);
    if (!item) return;
    setForm({ nombre: item.nombre, perfil: item.perfil || "", telefono: item.telefono || "", email: item.email || "", password: "", role: item.user_role || "partes", rol_id: (item as any).user_rol_id || "", foto_url: item.foto_url || "", asignable: (item as any).asignable !== false, fecha_inicio: (item as any).fecha_inicio || new Date().toISOString().slice(0, 10), fecha_fin: (item as any).fecha_fin || "" });
    setEditingId(editId); setEditingActivo(item.user_activo !== false); setError(""); setModalOpen(true);
  }, [searchParams, data, puedeEditar]);
  return null;
}

export default function RecursosHumanosPage() {
  const { user } = useAuthStore();
  const [data, setData] = useState<RHWithUser[]>([]); const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false); const [form, setForm] = useState(emptyForm);
  const [viewRecord, setViewRecord] = useState<RHWithUser | null>(null);
  const [viewTab, setViewTab] = useState<"detalle" | "asignaciones">("detalle");
  const [viewAsignaciones, setViewAsignaciones] = useState<any[]>([]);
  const [loadingAsig, setLoadingAsig] = useState(false);
  const [generandoPdf, setGenerandoPdf] = useState(false);
  const [filtroDesde, setFiltroDesde] = useState("");
  const [filtroHasta, setFiltroHasta] = useState("");
  const [filtroObra, setFiltroObra] = useState("");
  const [filtroEstado, setFiltroEstado] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null); const [saving, setSaving] = useState(false);
  const [error, setError] = useState(""); const [showPassword, setShowPassword] = useState(false);
  const [syncing, setSyncing] = useState(false); const [syncResult, setSyncResult] = useState("");
  const [deleteBlockedMsg, setDeleteBlockedMsg] = useState<string | null>(null);
  const [editingActivo, setEditingActivo] = useState(true);
  const [togglingAccess, setTogglingAccess] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [dbRoles, setDbRoles] = useState<{ id: string; nombre: string; is_admin: boolean }[]>([]);
  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("maestros_rrhh", "crear");
  const puedeEditar   = isAdmin || canDo("maestros_rrhh", "editar");
  const puedeEliminar = isAdmin || canDo("maestros_rrhh", "eliminar");
  const supabase = createClient();
  const emptyFormRef = { current: emptyForm };

  const fetchData = useCallback(async () => {
    setLoading(true);
    const { data: recursos } = await supabase.from("recursos_humanos").select("*").order("nombre");
    const { data: users } = await supabase.from("users").select("id, recurso_id, role, activo, rol_id");
    const { data: rolesData } = await supabase.from("roles").select("id, nombre, is_admin").order("nombre");
    setDbRoles(rolesData || []);
    const userMap: Record<string, { role: string; activo: boolean; id: string; rol_id: string | null }> = {};
    (users || []).forEach((u: any) => { if (u.recurso_id) userMap[u.recurso_id] = { role: u.role, activo: u.activo, id: u.id, rol_id: u.rol_id }; });
    const rolesMap: Record<string, string> = {};
    (rolesData || []).forEach((r: any) => { rolesMap[r.id] = r.nombre; });
    const enriched = (recursos || []).map((r: any) => ({
      ...r,
      user_role: userMap[r.id]?.role, user_activo: userMap[r.id]?.activo ?? r.activo, user_id: userMap[r.id]?.id,
      user_rol_id: userMap[r.id]?.rol_id,
      user_rol_nombre: userMap[r.id]?.rol_id ? rolesMap[userMap[r.id]?.rol_id!] || "Sin rol" : "Sin rol",
    }));
    setData(enriched); setLoading(false);
  }, []);
  useEffect(() => { fetchData(); }, [fetchData]);

  const asignacionesFiltradas = viewAsignaciones.filter((a: any) => {
    if (filtroDesde && a.fecha_inicio < filtroDesde) return false;
    if (filtroHasta && a.fecha_fin > filtroHasta) return false;
    if (filtroObra && !(a.obra?.nombre || "").toLowerCase().includes(filtroObra.toLowerCase())) return false;
    if (filtroEstado && !(a.obra?.estado_custom?.nombre || "").toLowerCase().includes(filtroEstado.toLowerCase())) return false;
    return true;
  });

  const generatePdfAsignaciones = async () => {
    setGenerandoPdf(true);
    try {
      const { default: jsPDF } = await import("jspdf");
      const { default: autoTable } = await import("jspdf-autotable");
      const { LOGO_BASE64 } = await import("@/lib/logo");
      const trabajador = viewRecord!;
      const filas = asignacionesFiltradas;
      const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
      const W = doc.internal.pageSize.getWidth();
      const MARGIN = 15;
      const hoy = new Date();
      const fmt = (iso: string | null) => iso ? iso.split("-").reverse().join("/") : "—";
      const fmtHoy = `${String(hoy.getDate()).padStart(2,"0")}/${String(hoy.getMonth()+1).padStart(2,"0")}/${hoy.getFullYear()}`;
      const addHeader = () => {
        doc.addImage(`data:image/jpeg;base64,${LOGO_BASE64}`, "JPEG", MARGIN, 8, 30, 20);
        doc.setFontSize(7); doc.setTextColor(150);
        doc.text("Loynek Soluciones Técnicas", MARGIN + 32, 14);
        doc.setFontSize(13); doc.setFont("helvetica","bold"); doc.setTextColor(20);
        doc.text("Informe de asignaciones por trabajador", W/2, 14, { align: "center" });
        doc.setFontSize(9); doc.setFont("helvetica","normal"); doc.setTextColor(80);
        doc.text(trabajador.nombre, W/2, 20, { align: "center" });
        if (trabajador.perfil) { doc.setFontSize(8); doc.text(trabajador.perfil, W/2, 25, { align: "center" }); }
        doc.setFontSize(7); doc.setTextColor(130);
        doc.text(`Generado el ${fmtHoy}`, W - MARGIN, 14, { align: "right" });
        if (filtroDesde || filtroHasta) {
          const periodo = `Periodo: ${filtroDesde ? fmt(filtroDesde) : "inicio"} — ${filtroHasta ? fmt(filtroHasta) : "hoy"}`;
          doc.text(periodo, W - MARGIN, 19, { align: "right" });
        }
        doc.setDrawColor(220); doc.setLineWidth(0.3); doc.line(MARGIN, 30, W - MARGIN, 30);
      };
      addHeader();
      const body = filas.length === 0
        ? [["", "Este trabajador no tiene asignaciones registradas para el periodo seleccionado.", "", ""]]
        : filas.map((a: any) => [
            fmt(a.fecha_inicio),
            fmt(a.fecha_fin),
            a.obra?.nombre || "Obra eliminada",
            a.obra?.estado_custom?.nombre || "—",
          ]);
      (autoTable as any)(doc, {
        startY: 34,
        head: [["INICIO", "FIN", "OBRA", "ESTADO"]],
        body,
        margin: { left: MARGIN, right: MARGIN },
        styles: { fontSize: 9, cellPadding: 3, lineColor: [220,220,220], lineWidth: 0.3 },
        headStyles: { fillColor: [220,38,38], textColor: 255, fontStyle: "bold", fontSize: 8 },
        alternateRowStyles: { fillColor: [250,250,250] },
        columnStyles: {
          0: { cellWidth: 28, halign: "center" },
          1: { cellWidth: 28, halign: "center" },
          2: { cellWidth: "auto" },
          3: { cellWidth: 52, halign: "center" },
        },
        didDrawPage: (data: any) => {
          if (data.pageNumber > 1) addHeader();
          const pageCount = (doc as any).internal.getNumberOfPages();
          doc.setFontSize(7); doc.setTextColor(130);
          doc.text(`Página ${data.pageNumber} de ${pageCount}`, W/2, doc.internal.pageSize.getHeight() - 8, { align: "center" });
        },
      });
      const pageCount = (doc as any).internal.getNumberOfPages();
      for (let i = 1; i <= pageCount; i++) {
        doc.setPage(i);
        doc.setFontSize(7); doc.setTextColor(130);
        doc.text(`Página ${i} de ${pageCount}`, W/2, doc.internal.pageSize.getHeight() - 8, { align: "center" });
      }
      const nombreArchivo = `asignaciones_${trabajador.nombre.replace(/\s+/g,"_")}_${fmtHoy.replace(/\//g,"-")}.pdf`;
      doc.save(nombreArchivo);
    } catch (err: any) { alert("Error al generar PDF: " + (err?.message || err)); }
    setGenerandoPdf(false);
  };

  const fetchAsignaciones = async (recursoId: string) => {
    setLoadingAsig(true);
    const { data } = await supabase
      .from("asignaciones")
      .select(`id, fecha_inicio, fecha_fin, observaciones, obra:obras(id, nombre, color, estado_custom:estados_obra(nombre, color))`)
      .eq("recurso_tipo", "humano")
      .eq("recurso_id", recursoId)
      .order("fecha_inicio", { ascending: false });
    setViewAsignaciones(data || []);
    setLoadingAsig(false);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); setError(""); setSaving(true);
    // Update asignable flag directly on recurso
    if (editingId) {
      await (supabase.from("recursos_humanos") as any).update({ asignable: form.asignable, fecha_inicio: form.fecha_inicio || null, fecha_fin: form.fecha_fin || null }).eq("id", editingId);
    }
    try {
      const res = await fetch("/api/users", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: editingId ? "update" : "create", recurso_id: editingId,
          nombre: form.nombre, perfil: form.perfil, telefono: form.telefono, email: form.email,
          password: form.password, role: form.role, rol_id: form.rol_id, foto_url: form.foto_url,
        }),
      });
      const result = await res.json();
      if (!res.ok) { setError(result.error || "Error"); setSaving(false); return; }
    } catch (err: any) { setError(err.message || "Error"); setSaving(false); return; }
    // If creating new, also set asignable
    if (!editingId) {
      // Find the newly created recurso by name+email
      const { data: newR } = await supabase.from("recursos_humanos").select("id").eq("email", form.email).order("created_at", { ascending: false }).limit(1);
      if (newR?.[0]) {
        const updatePayload: any = { fecha_inicio: form.fecha_inicio || new Date().toISOString().slice(0, 10) };
        if (!form.asignable) updatePayload.asignable = false;
        if (form.fecha_fin) updatePayload.fecha_fin = form.fecha_fin;
        await (supabase.from("recursos_humanos") as any).update(updatePayload).eq("id", (newR[0] as any).id);
      }
    }
    setSaving(false); setModalOpen(false); fetchData();
  };

  const handleToggleAccess = async (recursoId: string, currentlyActive: boolean) => {
    const res = await fetch("/api/users", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "toggle_access", recurso_id: recursoId, activo: !currentlyActive }) });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      setDeleteBlockedMsg(json.error || "No se pudo cambiar el acceso");
      return;
    }
    fetchData();
  };

  const handleToggleAccessInModal = async () => {
    if (!editingId) return;
    setTogglingAccess(true);
    setDeleteBlockedMsg(null);
    try {
      const nuevoEstado = !editingActivo;
      const res = await fetch("/api/users", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "toggle_access", recurso_id: editingId, activo: nuevoEstado }),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        setDeleteBlockedMsg(json.error || "No se pudo cambiar el acceso");
        return;
      }
      // Si se desactiva, fijar fecha_fin = hoy en recursos_humanos
      const hoy = new Date().toISOString().slice(0, 10);
      if (!nuevoEstado) {
        await (createClient().from("recursos_humanos") as any)
          .update({ fecha_fin: hoy, activo: false })
          .eq("id", editingId);
        setForm((f: any) => ({ ...f, fecha_fin: hoy }));
      } else {
        await (createClient().from("recursos_humanos") as any)
          .update({ fecha_fin: null, activo: true })
          .eq("id", editingId);
        setForm((f: any) => ({ ...f, fecha_fin: "" }));
      }
      setEditingActivo(nuevoEstado);
      fetchData();
    } catch (err: any) {
      setDeleteBlockedMsg(err.message || "Error al cambiar el acceso");
    } finally { setTogglingAccess(false); }
  };

  const handleDelete = async (item: RHWithUser) => {
    setDeleteBlockedMsg(null);
    setDeleting(true);
    try {
      const res = await fetch("/api/users", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "delete", recurso_id: item.id }),
      });
      const json = await res.json();
      if (!res.ok) {
        setDeleteBlockedMsg(json.error || "No se pudo eliminar el usuario");
        return;
      }
      fetchData();
    } catch (err: any) {
      setDeleteBlockedMsg(err.message || "Error al eliminar");
    } finally { setDeleting(false); }
  };

  const handleSync = async () => {
    setSyncing(true); setSyncResult("");
    try { const res = await fetch("/api/users", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "sync" }) }); const result = await res.json(); setSyncResult(result.message || "Sincronización completada"); fetchData(); }
    catch (err: any) { setSyncResult("Error: " + err.message); }
    setSyncing(false); setTimeout(() => setSyncResult(""), 8000);
  };

  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  const columns: Column<RHWithUser>[] = [
    { key: "nombre", header: "Nombre", render: (item) => (
      <button onClick={() => { setViewRecord(item); setViewTab("detalle"); setViewAsignaciones([]); setFiltroDesde(""); setFiltroHasta(""); setFiltroObra(""); setFiltroEstado(""); }} className="flex items-center gap-3 group text-left w-full">
        {item.foto_url ? <img src={item.foto_url} alt="" className="w-8 h-8 rounded-full object-cover shrink-0" /> :
          <div className="w-8 h-8 rounded-full bg-brand-100 flex items-center justify-center text-brand-700 text-xs font-semibold shrink-0">{item.nombre.split(" ").map(w => w[0]).join("").slice(0, 2).toUpperCase()}</div>}
        <div>
          <span className="font-medium text-surface-900 group-hover:text-brand-600 transition-colors">{item.nombre}</span>
          {!item.user_activo && <span className="ml-2 text-[10px] text-red-500 font-medium">SIN ACCESO</span>}
          {(item as any).asignable === false && <span className="ml-1 text-[10px] text-amber-500 font-medium">NO PLANIF.</span>}
        </div>
      </button>
    )},
    { key: "perfil", header: "Perfil" },
    { key: "email", header: "Email" },
    { key: "user_role", header: "Rol", render: (item) => (
      <span className={cn("badge text-[10px]", (item as any).user_rol_nombre === "Administrador" ? "bg-brand-100 text-brand-700" : "bg-surface-100 text-surface-600")}>{(item as any).user_rol_nombre || "Sin rol"}</span>
    )},
    { key: "user_activo", header: "Acceso", render: (item) => (
      <button onClick={() => isAdmin && handleToggleAccess(item.id, !!item.user_activo)}
        className={cn("flex items-center gap-1 text-[11px] font-medium px-2 py-1 rounded-lg", item.user_activo ? "text-emerald-700 bg-emerald-50 hover:bg-emerald-100" : "text-red-700 bg-red-50 hover:bg-red-100")} disabled={!isAdmin}>
        {item.user_activo ? <UserCheck className="w-3.5 h-3.5" /> : <UserX className="w-3.5 h-3.5" />}{item.user_activo ? "Activo" : "Inactivo"}
      </button>
    )},
  ];

  return (
    <AppLayout><div className="max-w-7xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6">
        <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center"><Users className="w-5 h-5 text-brand-600" /></div>
        <div><h1 className="text-xl font-display font-bold text-surface-900">Recursos Humanos</h1><p className="text-sm text-surface-500">Trabajadores y usuarios de la aplicación</p></div>
        {isAdmin && <button onClick={handleSync} disabled={syncing} className="flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-white bg-violet-500 rounded-lg hover:bg-violet-600 disabled:opacity-60 ml-auto shrink-0">{syncing ? <Loader2 className="w-4 h-4 animate-spin" /> : <UserCheck className="w-4 h-4" />}Sincronizar usuarios</button>}
      </div>
      {syncResult && <div className="mb-4 p-3 bg-violet-50 border border-violet-200 rounded-lg text-sm text-violet-700">{syncResult}</div>}
      {deleteBlockedMsg && (
        <div className="mb-4 p-3 bg-amber-50 border border-amber-200 rounded-lg text-sm text-amber-800 flex items-start justify-between gap-3">
          <span>{deleteBlockedMsg}</span>
          <button onClick={() => setDeleteBlockedMsg(null)} className="text-amber-500 hover:text-amber-700 shrink-0">✕</button>
        </div>
      )}
      <Suspense fallback={null}>
        <EditFromURL data={data} puedeEditar={puedeEditar} setForm={setForm} setEditingId={setEditingId} setEditingActivo={setEditingActivo} setError={setError} setModalOpen={setModalOpen} emptyFormRef={emptyFormRef} />
      </Suspense>
      <DataTable data={data} columns={columns} title="Trabajadores" loading={loading} searchPlaceholder="Buscar por nombre, perfil, email..." searchKeys={["nombre", "perfil", "email", "telefono"]}
        onAdd={isAdmin ? () => { setForm(emptyForm); setEditingId(null); setError(""); setModalOpen(true); } : undefined}
        onEdit={isAdmin ? (item) => { setForm({ nombre: item.nombre, perfil: item.perfil || "", telefono: item.telefono || "", email: item.email || "", password: "", role: item.user_role || "partes", rol_id: (item as any).user_rol_id || "", foto_url: item.foto_url || "", asignable: (item as any).asignable !== false, fecha_inicio: (item as any).fecha_inicio || new Date().toISOString().slice(0, 10), fecha_fin: (item as any).fecha_fin || "" }); setEditingId(item.id); setEditingActivo(item.user_activo !== false); setError(""); setModalOpen(true); } : undefined}
        addLabel="Nuevo trabajador" canAdd={isAdmin} canEdit={isAdmin} canDelete={isAdmin} onDelete={handleDelete} />
      {/* Modal de vista (modo lectura) */}
      <Modal open={!!viewRecord} onClose={() => setViewRecord(null)} title={viewRecord?.nombre || ""} size="xl">
        {viewRecord && (
          <div>
            {/* Botón Editar en cabecera */}
            {puedeEditar && (
              <div className="flex justify-end mb-4 -mt-1">
                <button onClick={() => {
                  const item = viewRecord;
                  setForm({ nombre: item.nombre, perfil: item.perfil || "", telefono: item.telefono || "", email: item.email || "", password: "", role: item.user_role || "partes", rol_id: (item as any).user_rol_id || "", foto_url: item.foto_url || "", asignable: (item as any).asignable !== false, fecha_inicio: (item as any).fecha_inicio || new Date().toISOString().slice(0, 10), fecha_fin: (item as any).fecha_fin || "" });
                  setEditingId(item.id); setEditingActivo(item.user_activo !== false); setError(""); setViewRecord(null); setModalOpen(true);
                }} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
                  <Pencil className="w-3.5 h-3.5" />Editar
                </button>
              </div>
            )}
            {/* Pestañas */}
            <div className="flex border-b border-surface-200 mb-4 gap-1 -mx-1">
              {(["detalle", "asignaciones"] as const).map((t) => (
                <button key={t} onClick={() => { setViewTab(t); if (t === "asignaciones" && viewAsignaciones.length === 0) fetchAsignaciones(viewRecord.id); }}
                  className={cn("px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors", viewTab === t ? "border-brand-500 text-brand-600" : "border-transparent text-surface-500 hover:text-surface-700")}>
                  {t === "detalle" ? "Detalle" : "Asignaciones"}
                </button>
              ))}
            </div>

            {/* PESTAÑA DETALLE */}
            {viewTab === "detalle" && (
              <div className="space-y-4">
                <div className="flex items-start gap-5">
                  {viewRecord.foto_url
                    ? <img src={viewRecord.foto_url} alt="" className="w-16 h-16 rounded-xl object-cover border border-surface-200 shrink-0" />
                    : <div className="w-16 h-16 rounded-xl bg-brand-100 flex items-center justify-center text-brand-700 text-xl font-bold border border-surface-200 shrink-0">{viewRecord.nombre.split(" ").map((w: string) => w[0]).join("").slice(0, 2).toUpperCase()}</div>
                  }
                  <div className="flex-1 grid grid-cols-2 gap-3">
                    <div><p className="text-[10px] font-semibold text-surface-400 uppercase mb-0.5">Nombre</p><p className="text-sm font-medium text-surface-900">{viewRecord.nombre}</p></div>
                    <div><p className="text-[10px] font-semibold text-surface-400 uppercase mb-0.5">Perfil / Puesto</p><p className="text-sm text-surface-700">{viewRecord.perfil || "—"}</p></div>
                    <div><p className="text-[10px] font-semibold text-surface-400 uppercase mb-0.5">Teléfono</p><p className="text-sm text-surface-700">{viewRecord.telefono || "—"}</p></div>
                    <div><p className="text-[10px] font-semibold text-surface-400 uppercase mb-0.5">Email</p><p className="text-sm text-surface-700">{viewRecord.email || "—"}</p></div>
                  </div>
                </div>
                <div className="border-t border-surface-100 pt-3 grid grid-cols-2 gap-3">
                  <div><p className="text-[10px] font-semibold text-surface-400 uppercase mb-0.5">Rol</p>
                    <span className={cn("inline-flex px-2 py-0.5 rounded-full text-xs font-semibold", (viewRecord as any).user_rol_nombre === "Administrador" ? "bg-brand-100 text-brand-700" : "bg-surface-100 text-surface-700")}>{(viewRecord as any).user_rol_nombre || "Sin rol"}</span>
                  </div>
                  <div><p className="text-[10px] font-semibold text-surface-400 uppercase mb-0.5">Acceso</p>
                    <span className={cn("flex items-center gap-1 text-sm", viewRecord.user_activo !== false ? "text-emerald-700" : "text-red-600")}>
                      {viewRecord.user_activo !== false ? <UserCheck className="w-4 h-4" /> : <UserX className="w-4 h-4" />}
                      {viewRecord.user_activo !== false ? "Activo" : "Sin acceso"}
                    </span>
                  </div>
                </div>
                <div className="border-t border-surface-100 pt-3">
                  <p className="text-[10px] font-semibold text-surface-400 uppercase mb-2">Disponibilidad en planificador</p>
                  <div className="grid grid-cols-3 gap-3">
                    <div><p className="text-[10px] text-surface-400 mb-0.5">Fecha inicio</p>
                      <p className="text-sm text-surface-900">{(viewRecord as any).fecha_inicio ? (viewRecord as any).fecha_inicio.split("-").reverse().join("/") : "—"}</p>
                    </div>
                    <div><p className="text-[10px] text-surface-400 mb-0.5">Fecha fin</p>
                      <p className="text-sm text-surface-900">{(viewRecord as any).fecha_fin ? (viewRecord as any).fecha_fin.split("-").reverse().join("/") : "Sin límite"}</p>
                    </div>
                    <div><p className="text-[10px] text-surface-400 mb-0.5">Asignable</p>
                      <span className={cn("text-sm font-medium", (viewRecord as any).asignable !== false ? "text-emerald-700" : "text-red-500")}>
                        {(viewRecord as any).asignable !== false ? "✓ Sí" : "✗ No"}
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* PESTAÑA ASIGNACIONES */}
            {viewTab === "asignaciones" && (
              <div>
                {/* Filtros */}
                <div className="flex flex-wrap gap-2 mb-3">
                  <input type="date" value={filtroDesde} onChange={(e) => setFiltroDesde(e.target.value)}
                    className="px-2 py-1 text-xs bg-surface-50 border border-surface-200 rounded-lg focus:outline-none"
                    placeholder="Desde" title="Desde" />
                  <input type="date" value={filtroHasta} onChange={(e) => setFiltroHasta(e.target.value)}
                    className="px-2 py-1 text-xs bg-surface-50 border border-surface-200 rounded-lg focus:outline-none"
                    placeholder="Hasta" title="Hasta" />
                  <input type="text" value={filtroObra} onChange={(e) => setFiltroObra(e.target.value)}
                    className="px-2 py-1 text-xs bg-surface-50 border border-surface-200 rounded-lg focus:outline-none min-w-[120px]"
                    placeholder="Filtrar obra..." />
                  <input type="text" value={filtroEstado} onChange={(e) => setFiltroEstado(e.target.value)}
                    className="px-2 py-1 text-xs bg-surface-50 border border-surface-200 rounded-lg focus:outline-none min-w-[100px]"
                    placeholder="Filtrar estado..." />
                  {(filtroDesde || filtroHasta || filtroObra || filtroEstado) && (
                    <button onClick={() => { setFiltroDesde(""); setFiltroHasta(""); setFiltroObra(""); setFiltroEstado(""); }}
                      className="px-2 py-1 text-xs text-surface-500 hover:text-surface-700">✕ Limpiar</button>
                  )}
                  <button onClick={generatePdfAsignaciones} disabled={generandoPdf || loadingAsig}
                    className="flex items-center gap-1 px-3 py-1 text-xs font-semibold text-white bg-red-600 rounded-lg hover:bg-red-700 disabled:opacity-60 ml-auto">
                    {generandoPdf ? <Loader2 className="w-3 h-3 animate-spin" /> : null}
                    {generandoPdf ? "Generando..." : "Generar PDF"}
                  </button>
                </div>
              </div>
            )}
            {viewTab === "asignaciones" && (
              loadingAsig ? (
                <div className="flex items-center justify-center py-10"><Loader2 className="w-6 h-6 text-brand-500 animate-spin" /></div>
              ) : viewAsignaciones.length === 0 ? (
                <div className="text-center py-10 text-sm text-surface-400">Este trabajador todavía no tiene asignaciones registradas.</div>
              ) : (
                <div className="overflow-x-auto -mx-1">
                  <table className="w-full text-sm">
                    <thead><tr className="border-b border-surface-200 bg-surface-50">
                      <th className="text-left text-[10px] font-semibold text-surface-400 uppercase px-3 py-2">Inicio</th>
                      <th className="text-left text-[10px] font-semibold text-surface-400 uppercase px-3 py-2">Fin</th>
                      <th className="text-left text-[10px] font-semibold text-surface-400 uppercase px-3 py-2">Obra</th>
                      <th className="text-left text-[10px] font-semibold text-surface-400 uppercase px-3 py-2">Estado</th>
                    </tr></thead>
                    <tbody className="divide-y divide-surface-100">
                      {asignacionesFiltradas.map((a: any) => (
                        <tr key={a.id} className="hover:bg-surface-50">
                          <td className="px-3 py-2 text-surface-600 whitespace-nowrap">{a.fecha_inicio?.split("-").reverse().join("/") || "—"}</td>
                          <td className="px-3 py-2 text-surface-600 whitespace-nowrap">{a.fecha_fin?.split("-").reverse().join("/") || "—"}</td>
                          <td className="px-3 py-2">
                            <span className="flex items-center gap-1.5">
                              <span className="w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: a.obra?.color || "#DC2626" }} />
                              <span className="font-medium text-surface-900">{a.obra?.nombre || "Obra eliminada"}</span>
                            </span>
                          </td>
                          <td className="px-3 py-2 whitespace-nowrap">
                            {a.obra?.estado_custom ? (
                              <span className="inline-flex px-2 py-0.5 rounded-full text-[10px] font-semibold text-white whitespace-nowrap" style={{ backgroundColor: a.obra.estado_custom.color || "#6B7280" }}>{a.obra.estado_custom.nombre}</span>
                            ) : <span className="text-surface-400">—</span>}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  <p className="text-[10px] text-surface-400 px-3 py-2 border-t border-surface-100">{asignacionesFiltradas.length} de {viewAsignaciones.length} asignación{viewAsignaciones.length !== 1 ? "es" : ""}</p>
                </div>
              )
            )}
          </div>
        )}
      </Modal>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Editar trabajador" : "Nuevo trabajador"} size="lg">
        <form onSubmit={handleSubmit} className="space-y-4">
          {error && <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">{error}</div>}
          {deleteBlockedMsg && <div className="p-3 bg-amber-50 border border-amber-200 rounded-lg text-sm text-amber-800">{deleteBlockedMsg}</div>}
          <div className="flex items-start gap-5">
            <PhotoUpload currentUrl={form.foto_url || null} folder="humano" entityId={editingId || undefined} size="lg" onUploaded={(url) => setForm({ ...form, foto_url: url })} onRemoved={() => setForm({ ...form, foto_url: "" })} />
            <div className="flex-1 space-y-4">
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre completo *</label><input type="text" required value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="Ej: Juan García Pérez" className={ic} /></div>
              <div className="grid grid-cols-2 gap-4">
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Perfil / Puesto</label>
                  <select value={form.perfil} onChange={(e) => setForm({ ...form, perfil: e.target.value })} className={ic}><option value="">Seleccionar...</option><option value="Encargado de obra">Encargado de obra</option><option value="Oficial 1ª">Oficial 1ª</option><option value="Oficial 2ª">Oficial 2ª</option><option value="Peón especialista">Peón especialista</option><option value="Peón">Peón</option><option value="Administrativo">Administrativo</option><option value="Técnico">Técnico</option></select>
                </div>
                <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Teléfono</label><input type="tel" value={form.telefono} onChange={(e) => setForm({ ...form, telefono: e.target.value })} placeholder="600 000 000" className={ic} /></div>
              </div>
            </div>
          </div>
          <div className="border-t border-surface-200 pt-4">
            <div className="flex items-center gap-2 mb-3"><ShieldCheck className="w-4 h-4 text-brand-600" /><h3 className="text-sm font-semibold text-surface-900">Acceso a la aplicación</h3></div>
            <div className="grid grid-cols-3 gap-4">
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Email de acceso *</label><input type="email" required value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} placeholder="trabajador@loynek.es" className={ic} /></div>
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">{editingId ? "Nueva contraseña" : "Contraseña *"}</label>
                <div className="relative"><input type={showPassword ? "text" : "password"} value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} placeholder={editingId ? "Dejar vacío para no cambiar" : "Mínimo 6 caracteres"} required={!editingId} minLength={editingId ? 0 : 6} className={ic + " pr-10"} />
                  <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-3 top-1/2 -translate-y-1/2 text-surface-400">{showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}</button>
                </div>
              </div>
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Rol</label>
                <select value={form.rol_id} onChange={(e) => { const rol = dbRoles.find((r) => r.id === e.target.value); setForm({ ...form, rol_id: e.target.value, role: rol?.is_admin ? "admin" : "partes" }); }} className={ic}><option value="">Sin rol</option>{dbRoles.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select>
              </div>
            </div>
          </div>
          {/* Activar/Desactivar acceso (solo al editar) */}
          {editingId && (
            <div className="border-t border-surface-200 pt-4">
              <div className="flex items-center justify-between">
                <div>
                  <span className="text-sm font-medium text-surface-900">Acceso a la aplicación</span>
                  <p className="text-xs text-surface-400">{editingActivo ? "Este usuario puede iniciar sesión." : "Este usuario NO puede iniciar sesión."}</p>
                </div>
                <button type="button" onClick={handleToggleAccessInModal} disabled={togglingAccess}
                  className={cn("flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg disabled:opacity-60",
                    editingActivo ? "text-red-700 bg-red-50 hover:bg-red-100" : "text-emerald-700 bg-emerald-50 hover:bg-emerald-100")}>
                  {togglingAccess && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
                  {!togglingAccess && (editingActivo ? <UserX className="w-3.5 h-3.5" /> : <UserCheck className="w-3.5 h-3.5" />)}
                  {editingActivo ? "Desactivar acceso" : "Activar acceso"}
                </button>
              </div>
            </div>
          )}
          {/* Fechas de disponibilidad */}
          <div className="border-t border-surface-200 pt-4">
            <p className="text-sm font-medium text-surface-900 mb-3">Disponibilidad en planificador</p>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-surface-600 mb-1">Fecha inicio *</label>
                <input type="date" className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none"
                  value={form.fecha_inicio}
                  onChange={(e) => setForm({ ...form, fecha_inicio: e.target.value })} />
                <p className="text-[10px] text-surface-400 mt-1">Desde cuándo aparece en el planificador</p>
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-600 mb-1">Fecha fin</label>
                <input type="date" className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none"
                  value={form.fecha_fin}
                  onChange={(e) => setForm({ ...form, fecha_fin: e.target.value })} />
                <p className="text-[10px] text-surface-400 mt-1">Vacío = disponible indefinidamente</p>
              </div>
            </div>
          </div>
          {/* Asignable flag */}
          <div className="border-t border-surface-200 pt-4">
            <label className="flex items-center gap-3 cursor-pointer">
              <input type="checkbox" checked={form.asignable} onChange={(e) => setForm({ ...form, asignable: e.target.checked })} className="w-4 h-4 rounded border-surface-300 text-brand-600 focus:ring-brand-500" />
              <div>
                <span className="text-sm font-medium text-surface-900">Asignable en planificación</span>
                <p className="text-xs text-surface-400">Si está desactivado, no aparecerá en el panel de recursos del planificador</p>
              </div>
            </label>
          </div>
          <div className="flex items-center justify-end gap-2 pt-2">
            <button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving || !form.nombre || !form.email || (!editingId && !form.password)} className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingId ? "Guardar cambios" : "Crear trabajador"}</button>
          </div>
        </form>
      </Modal>
    </div></AppLayout>
  );
}