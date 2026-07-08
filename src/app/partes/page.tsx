"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import type { Obra, RecursoHumano } from "@/lib/types/database";
import { ClipboardList, Plus, Loader2, CheckCircle2, Clock, FileSignature, X, AlertTriangle } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";

const toDS = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

export default function PartesPage() {
  const supabase = createClient();
  const router = useRouter();
  const { user } = useAuthStore();
  const [partes, setPartes] = useState<any[]>([]);
  const [obras, setObras] = useState<Obra[]>([]);
  const [personas, setPersonas] = useState<RecursoHumano[]>([]);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [filterEstado, setFilterEstado] = useState("");
  const [filterObra, setFilterObra] = useState("");
  const [filterFecha, setFilterFecha] = useState("");
  const [filterPersona, setFilterPersona] = useState("");
  // Obra selector modal for multiple assignments
  const [obraSelectModal, setObraSelectModal] = useState(false);
  const [obraOptions, setObraOptions] = useState<{ id: string; nombre: string; color: string; fecha: string }[]>([]);
  const [noObraError, setNoObraError] = useState("");

  const { isAdmin, canDo } = usePermissions();
  const puedeCrear    = isAdmin || canDo("partes", "crear");
  const puedeEditar   = isAdmin || canDo("partes", "editar");
  const puedeEliminar = isAdmin || canDo("partes", "eliminar");

  // Selector de fecha (paso 1 para operario)
  const [dateModal, setDateModal] = useState(false);
  const [selectedFecha, setSelectedFecha] = useState(toDS(new Date()));

  const abrirOCrearParte = async (obraId: string, fecha: string) => {
    setCreating(true);
    setNoObraError("");

    // ¿Ya existe un parte para esta obra+fecha+usuario? Abrirlo, nunca duplicar.
    const { data: existentes } = await supabase.from("partes_diarios").select("id").eq("obra_id", obraId).eq("fecha", fecha).eq("created_by", user?.id);
    if (existentes && existentes.length > 0) {
      router.push(`/partes/${existentes[0].id}`);
      return;
    }

    let direccion = null, localidad = null, provincia = null;
    const { data: obraData } = await supabase.from("obras").select("direccion, localidad, provincia").eq("id", obraId).single();
    if (obraData) { direccion = obraData.direccion; localidad = obraData.localidad; provincia = obraData.provincia; }

    const { data: parte, error } = await (supabase.from("partes_diarios") as any).insert({
      fecha, created_by: user?.id, estado: "pendiente", obra_id: obraId,
      responsable_empresa: user?.nombre || "", direccion, localidad, provincia,
    }).select().single();

    if (parte) {
      router.push(`/partes/${parte.id}`);
    } else if (error?.code === "23505") {
      // Carrera con otra creación simultánea: el parte ya existe, abrirlo
      const { data: ahora } = await supabase.from("partes_diarios").select("id").eq("obra_id", obraId).eq("fecha", fecha).eq("created_by", user?.id);
      if (ahora && ahora.length > 0) { router.push(`/partes/${ahora[0].id}`); return; }
      alert("Ya existe un parte para esa obra y fecha.");
      setCreating(false);
    } else {
      alert("Error al crear parte: " + (error?.message || ""));
      setCreating(false);
    }
  };

  const handleNuevoParte = () => {
    if (isAdmin) { createDraftAdmin(); return; }
    setSelectedFecha(toDS(new Date()));
    setNoObraError("");
    setDateModal(true);
  };

  const handleFechaConfirmada = async () => {
    setDateModal(false);
    setCreating(true);
    setNoObraError("");
    const recursoId = user?.recurso_id;
    if (!recursoId) {
      setNoObraError("Tu usuario no está vinculado a un recurso humano. Contacta con el administrador.");
      setCreating(false);
      return;
    }

    const { data: asigs, error: asigError } = await supabase.from("asignaciones").select("obra_id, fecha_inicio, fecha_fin").eq("recurso_tipo", "humano").eq("recurso_id", recursoId);
    console.log("[parte] recursoId:", recursoId, "selectedFecha:", selectedFecha, "asigs:", asigs, "error:", asigError);
    if (asigError) {
      setNoObraError(`Error consultando asignaciones: ${asigError.message}`);
      setCreating(false);
      return;
    }
    const delDia = (asigs || []).filter((a: any) => a.fecha_inicio <= selectedFecha && a.fecha_fin >= selectedFecha);
    const obraIds = Array.from(new Set(delDia.map((a: any) => a.obra_id)));

    if (obraIds.length === 0) {
      const fechaLabel = new Date(selectedFecha + "T12:00:00").toLocaleDateString("es-ES", { day: "numeric", month: "long" });
      setNoObraError(`No tienes ninguna obra asignada el ${fechaLabel}. (recurso: ${recursoId}, total asignaciones encontradas: ${(asigs || []).length})`);
      setCreating(false);
      return;
    }

    if (obraIds.length === 1) {
      await abrirOCrearParte(obraIds[0], selectedFecha);
      return;
    }

    const { data: obrasData } = await supabase.from("obras").select("id, nombre, color").in("id", obraIds);
    const options = (obrasData || []).map((o: any) => ({ ...o, fecha: selectedFecha })).sort((a: any, b: any) => a.nombre.localeCompare(b.nombre));
    setObraOptions(options);
    setObraSelectModal(true);
    setCreating(false);
  };

  // Admin: crea un parte en blanco directamente (sin pasar por asignaciones)
  const createDraftAdmin = async () => {
    setCreating(true);
    setNoObraError("");
    const { data: parte, error } = await (supabase.from("partes_diarios") as any).insert({
      fecha: toDS(new Date()), created_by: user?.id, estado: "pendiente", obra_id: null,
      responsable_empresa: user?.nombre || "",
    }).select().single();
    if (parte) router.push(`/partes/${parte.id}`);
    else { alert("Error al crear parte: " + (error?.message || "")); setCreating(false); }
  };

  const handleObraSelected = (obraId: string, fecha: string) => {
    setObraSelectModal(false);
    abrirOCrearParte(obraId, fecha);
  };

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [partesR, obrasR, persR] = await Promise.all([
      supabase.from("partes_diarios")
        .select("*, obra:obras(id, nombre, color), creator:users!partes_diarios_created_by_fkey(nombre, recurso_id)")
        .order("fecha", { ascending: false })
        .limit(200),
      supabase.from("obras").select("id, nombre").eq("archivada", false).order("nombre"),
      supabase.from("recursos_humanos").select("id, nombre").eq("activo", true).order("nombre"),
    ]);
    setPartes(partesR.data || []);
    setObras((obrasR.data as Obra[]) || []);
    setPersonas((persR.data as RecursoHumano[]) || []);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const filtered = partes.filter((p) => {
    if (filterEstado && p.estado !== filterEstado) return false;
    if (filterObra && p.obra_id !== filterObra) return false;
    if (filterFecha && p.fecha !== filterFecha) return false;
    if (filterPersona && p.creator?.recurso_id !== filterPersona) return false;
    return true;
  });

  const hasFilters = filterEstado || filterObra || filterFecha || filterPersona;
  const estadoBadge: Record<string, { label: string; class: string; icon: typeof Clock }> = {
    borrador: { label: "Borrador", class: "bg-surface-100 text-surface-600", icon: Clock },
    pendiente: { label: "Pendiente", class: "bg-amber-100 text-amber-700", icon: Clock },
    firmado: { label: "Firmado", class: "bg-emerald-100 text-emerald-700", icon: CheckCircle2 },
  };

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-orange-50 flex items-center justify-center"><ClipboardList className="w-5 h-5 text-orange-600" /></div>
            <div><h1 className="text-xl font-display font-bold text-surface-900">Partes Diarios</h1><p className="text-sm text-surface-500">{filtered.length} partes</p></div>
          </div>
          <button onClick={handleNuevoParte} disabled={creating} className="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
            {creating ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />} Nuevo parte
          </button>
        </div>

        {/* Error message */}
        {noObraError && (
          <div className="mb-4 p-3 bg-amber-50 border border-amber-200 rounded-lg flex items-start gap-2">
            <AlertTriangle className="w-4 h-4 text-amber-600 mt-0.5 shrink-0" />
            <div>
              <p className="text-sm text-amber-800 font-medium">{noObraError}</p>
              <button onClick={() => setNoObraError("")} className="text-xs text-amber-600 hover:underline mt-1">Cerrar</button>
            </div>
          </div>
        )}

        {/* Filters */}
        <div className="card p-3 mb-4">
          <div className="flex items-center gap-3 flex-wrap">
            <select value={filterEstado} onChange={(e) => setFilterEstado(e.target.value)} className="px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20">
              <option value="">Todos los estados</option><option value="pendiente">Pendiente</option><option value="firmado">Firmado</option><option value="borrador">Borrador</option>
            </select>
            <select value={filterObra} onChange={(e) => setFilterObra(e.target.value)} className="px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20">
              <option value="">Todas las obras</option>{obras.map((o) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
            </select>
            <input type="date" value={filterFecha} onChange={(e) => setFilterFecha(e.target.value)} className="px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20" />
            <select value={filterPersona} onChange={(e) => setFilterPersona(e.target.value)} className="px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20">
              <option value="">Todas las personas</option>{personas.map((p) => <option key={p.id} value={p.id}>{p.nombre}</option>)}
            </select>
            {hasFilters && <button onClick={() => { setFilterEstado(""); setFilterObra(""); setFilterFecha(""); setFilterPersona(""); }} className="flex items-center gap-1 px-2.5 py-1.5 text-xs text-red-600 bg-red-50 rounded-lg hover:bg-red-100"><X className="w-3 h-3" />Limpiar</button>}
          </div>
        </div>

        {/* List */}
        {loading ? (
          <div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div>
        ) : filtered.length === 0 ? (
          <div className="card text-center py-16">
            <ClipboardList className="w-10 h-10 text-surface-300 mx-auto mb-3" />
            <p className="text-sm text-surface-500">{hasFilters ? "Sin resultados" : "No hay partes"}</p>
            <button onClick={handleNuevoParte} className="text-sm text-brand-600 hover:underline mt-1">Crear primer parte</button>
          </div>
        ) : (
          <div className="space-y-2">
            {filtered.map((p) => {
              const est = estadoBadge[p.estado] || estadoBadge.pendiente;
              const EstIcon = est.icon;
              return (
                <Link key={p.id} href={`/partes/${p.id}`} className="card flex items-center gap-4 p-4 hover:shadow-md hover:border-surface-300 transition-all group">
                  <div className="w-1.5 h-14 rounded-full shrink-0" style={{ backgroundColor: p.obra?.color || "#D4D4D4" }} />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3 mb-1 flex-wrap">
                      <span className="text-base font-display font-bold text-surface-900 group-hover:text-brand-600">{p.creator?.nombre || "Usuario"}</span>
                      <span className="text-base font-medium text-surface-700">{p.obra?.nombre || "Sin obra"}</span>
                      <span className="text-sm text-surface-500">{new Date(p.fecha + "T12:00:00").toLocaleDateString("es-ES", { weekday: "short", day: "numeric", month: "short", year: "numeric" })}</span>
                    </div>
                    <div className="flex items-center gap-3">
                      {p.direccion && <span className="text-xs text-surface-400">{p.direccion}{p.localidad ? `, ${p.localidad}` : ""}</span>}
                      {p.observaciones && <span className="text-xs text-surface-500 truncate max-w-[300px]">{p.observaciones}</span>}
                    </div>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    {p.firma_data && <span className="text-[10px] text-emerald-600 flex items-center gap-0.5"><FileSignature className="w-3 h-3" />Resp.</span>}
                    {p.firma_cliente && <span className="text-[10px] text-blue-600 flex items-center gap-0.5"><FileSignature className="w-3 h-3" />Cliente</span>}
                  </div>
                  <span className={cn("badge text-[10px] shrink-0 flex items-center gap-1", est.class)}><EstIcon className="w-3 h-3" />{est.label}</span>
                </Link>
              );
            })}
          </div>
        )}
      </div>

      {/* Selector de fecha (paso 1 para operario) */}
      <Modal open={dateModal} onClose={() => setDateModal(false)} title="¿Qué día es el parte?" size="sm">
        <p className="text-sm text-surface-500 mb-4">Indica la fecha del parte. Te asignaremos la obra correspondiente según tu planificación.</p>
        <input type="date" value={selectedFecha} max={toDS(new Date())}
          onChange={(e) => e.target.value && setSelectedFecha(e.target.value)}
          className="w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20 mb-4" />
        <button onClick={handleFechaConfirmada} disabled={creating}
          className="w-full flex items-center justify-center gap-1.5 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
          {creating ? <Loader2 className="w-4 h-4 animate-spin" /> : "Continuar"}
        </button>
      </Modal>

      {/* Obra selector modal (cuando hay 2+ obras asignadas ese día) */}
      <Modal open={obraSelectModal} onClose={() => setObraSelectModal(false)} title="Selecciona la obra" size="sm">
        <p className="text-sm text-surface-500 mb-4">
          Ese día tienes varias obras asignadas{obraOptions[0] ? ` (${new Date(obraOptions[0].fecha + "T12:00:00").toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "short" })})` : ""}. ¿En cuál quieres crear el parte?
        </p>
        <div className="space-y-2">
          {obraOptions.map((o, i) => (
            <button key={`${o.id}-${i}`} onClick={() => handleObraSelected(o.id, o.fecha)}
              className="w-full flex items-center gap-3 p-3 bg-surface-50 rounded-lg border border-surface-200 hover:border-brand-400 hover:bg-brand-50 transition-all text-left">
              <div className="w-3 h-8 rounded-full shrink-0" style={{ backgroundColor: o.color || "#DC2626" }} />
              <span className="text-sm font-medium text-surface-900">{o.nombre}</span>
            </button>
          ))}
        </div>
      </Modal>
    </AppLayout>
  );
}