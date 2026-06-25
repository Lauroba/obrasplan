#Requires -Version 5.1
# deploy-almacen-fase3.ps1
# Fase 3 del modulo de almacen:
#   - Planificador: elimina maquinaria y material, mantiene RRHH y vehiculos
#   - Dashboard: widget de alertas de stock bajo y caducidad
#   - Movimientos: entrada, salida, ajuste + traslado masivo con scanner
#   - Obras: pestana de stock del almacen de la obra
#   - Configuracion: pestana Almacen (emails alertas, config) + pantallas actualizadas
#   - API: endpoint email de alertas usando Resend
#   - Sidebar/Permisos/Rutas: movimientos anadido, maquinaria/materiales eliminados

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR: repo no encontrado" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Escribiendo archivos" -ForegroundColor Cyan

$dst = "src\app\planificacion\page.tsx"
$content = @'
"use client";

import { useState, useEffect, useCallback, useMemo, memo } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import type { Obra, Asignacion, RecursoHumano, Maquinaria, Vehiculo, Material, RecursoTipo, EstadoObra } from "@/lib/types/database";
import {
  DndContext, useDraggable, useDroppable, DragOverlay,
  PointerSensor, useSensor, useSensors, closestCenter, rectIntersection,
  type DragEndEvent, type DragStartEvent, type CollisionDetection,
} from "@dnd-kit/core";
import { SortableContext, useSortable, verticalListSortingStrategy, arrayMove } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import {
  CalendarRange, ChevronLeft, ChevronRight, Users, Wrench, Truck, Package,
  Plus, Loader2, Archive, Eye, X, GripVertical, AlertTriangle, Building2, Search
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import Link from "next/link";
import CellNote from "@/components/planificacion/CellNote";

type PlanView = "obras" | "rrhh";
type ViewMode = "week" | "month" | "year";
type ResourceFilter = "all" | "humano" | "vehiculo";
type PanelFilter = "all" | "obra" | "vehiculo";
type ResourceInfo = { nombre: string; foto_url: string | null; tipo: RecursoTipo; initials: string };

const TIPO_ICON: Record<string, typeof Users> = { humano: Users, vehiculo: Truck, obra: Building2 };
const TIPO_BG: Record<string, string> = { humano: "bg-violet-100 text-violet-700", vehiculo: "bg-teal-100 text-teal-700", obra: "bg-brand-100 text-brand-700" };
const DAY_WIDTHS: Record<ViewMode, number> = { week: 110, month: 40, year: 18 };
const DAYS_COUNT: Record<ViewMode, number> = { week: 7, month: 31, year: 364 };
const LABEL_W = 210;
const CONFLICT_TYPES: RecursoTipo[] = ["humano", "vehiculo"];
const toDS = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

const customCollision: CollisionDetection = (args) => {
  const aid = String(args.active.id);
  // Resource/panel drag → collide with cells only
  if (aid.startsWith("res-") || aid.startsWith("panel-")) return rectIntersection({ ...args, droppableContainers: args.droppableContainers.filter((c) => String(c.id).startsWith("cell-")) });
  // Person row drag → collide with person rows only
  if (aid.startsWith("prow-")) return closestCenter({ ...args, droppableContainers: args.droppableContainers.filter((c) => String(c.id).startsWith("prow-")) });
  // Obra row drag → collide with obra rows only (exclude cells, res, panel, prow)
  return closestCenter({ ...args, droppableContainers: args.droppableContainers.filter((c) => { const id = String(c.id); return !id.startsWith("cell-") && !id.startsWith("res-") && !id.startsWith("panel-") && !id.startsWith("prow-"); }) });
};

// ---- Draggable Panel Item ----
function PanelItem({ dragId, nombre, foto_url, color, detail, count, iconType }: {
  dragId: string; nombre: string; foto_url?: string | null; color?: string; detail?: string; count: number; iconType: string;
}) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({ id: dragId, data: { nombre, foto_url, color, iconType } });
  const Icon = TIPO_ICON[iconType] || Building2;
  return (
    <div ref={setNodeRef} {...listeners} {...attributes}
      className={cn("flex items-center gap-2 px-2.5 py-1.5 rounded-lg border border-transparent cursor-grab active:cursor-grabbing transition-all select-none",
        isDragging ? "opacity-30 bg-brand-50" : "hover:bg-surface-50 hover:border-surface-200")}>
      {color ? <div className="w-6 h-6 rounded-full shrink-0 flex items-center justify-center" style={{ backgroundColor: color }}><Building2 className="w-3 h-3 text-white" /></div> :
        foto_url ? <img src={foto_url} alt="" className="w-6 h-6 rounded-full object-cover shrink-0" /> :
        <div className={cn("w-6 h-6 rounded-full flex items-center justify-center shrink-0 text-[10px]", TIPO_BG[iconType])}><Icon className="w-3 h-3" /></div>}
      <div className="flex-1 min-w-0"><p className="text-[11px] font-medium text-surface-900 truncate">{nombre}</p>{detail && <p className="text-[10px] text-surface-400 truncate">{detail}</p>}</div>
      {count > 0 && <span className="text-[9px] bg-surface-200 text-surface-600 px-1 py-0.5 rounded-full">{count}</span>}
    </div>
  );
}

// ---- Droppable Cell for Vista Obras ----
const ObraCell = memo(function ObraCell({ obraId, dateStr, assignments, resInfo, onRemove, dw, hasConflict }: {
  obraId: string; dateStr: string; assignments: Asignacion[]; resInfo: Record<string, ResourceInfo>;
  onRemove: (id: string) => void; dw: number; hasConflict: boolean;
}) {
  const cid = `cell-${obraId}|${dateStr}`;
  const { setNodeRef, isOver } = useDroppable({ id: cid });
  const personas = assignments.filter((a) => a.recurso_tipo === "humano");
  const otros = assignments.filter((a) => a.recurso_tipo !== "humano");
  return (
    <div ref={setNodeRef} className={cn("h-full border-r border-surface-100 flex flex-col items-center justify-center gap-0.5 p-0.5 transition-colors",
      isOver ? "bg-brand-100 ring-2 ring-brand-400 ring-inset" : "", hasConflict ? "bg-red-50 ring-1 ring-red-300 ring-inset" : "")}
      style={{ width: dw, minWidth: dw }}>
      <div className="flex flex-wrap gap-0.5 justify-center">
        {personas.map((a) => { const info = resInfo[`${a.recurso_tipo}|${a.recurso_id}`]; return info?.foto_url ? (
          <img key={a.id} src={info.foto_url} alt={info.nombre} title={`${info.nombre}\nClic para quitar`}
            className={cn("rounded-full object-cover cursor-pointer hover:ring-2 hover:ring-red-400", dw > 60 ? "w-6 h-6" : "w-4 h-4")} onClick={() => onRemove(a.id)} />
        ) : (
          <div key={a.id} title={`${info?.nombre || "?"}\nClic para quitar`}
            className={cn("rounded-full bg-violet-200 text-violet-800 flex items-center justify-center font-bold cursor-pointer hover:ring-2 hover:ring-red-400",
              dw > 60 ? "w-6 h-6 text-[8px]" : "w-4 h-4 text-[6px]")} onClick={() => onRemove(a.id)}>{info?.initials || "?"}</div>
        ); })}
      </div>
      <div className="flex flex-wrap gap-0.5 justify-center">
        {otros.map((a) => { const info = resInfo[`${a.recurso_tipo}|${a.recurso_id}`]; const Icon = TIPO_ICON[a.recurso_tipo]; return info?.foto_url ? (
          <img key={a.id} src={info.foto_url} alt={info.nombre} title={`${info.nombre}\nClic para quitar`}
            className="w-4 h-4 rounded-full object-cover cursor-pointer hover:ring-2 hover:ring-red-400" onClick={() => onRemove(a.id)} />
        ) : (
          <div key={a.id} title={`${info?.nombre || "?"}\nClic para quitar`}
            className={cn("w-4 h-4 rounded-full flex items-center justify-center cursor-pointer hover:ring-2 hover:ring-red-400", TIPO_BG[a.recurso_tipo])} onClick={() => onRemove(a.id)}><Icon className="w-2 h-2" /></div>
        ); })}
      </div>
    </div>
  );
});

// ---- Droppable Cell for Vista RRHH ----
const RrhhCell = memo(function RrhhCell({ recursoId, dateStr, personAssignments, obras, onRemove, dw }: {
  recursoId: string; dateStr: string; personAssignments: Asignacion[]; obras: Obra[];
  onRemove: (id: string) => void; dw: number;
}) {
  const cid = `cell-${recursoId}|${dateStr}`;
  const { setNodeRef, isOver } = useDroppable({ id: cid });
  // Deduplicate: one block per unique obra
  const seen = new Set<string>();
  const uniqueAssigs = personAssignments.filter((a) => {
    if (seen.has(a.obra_id)) return false;
    seen.add(a.obra_id); return true;
  });

  return (
    <div ref={setNodeRef} className={cn("h-full border-r border-surface-100 flex flex-col items-center justify-center gap-0.5 p-0.5 transition-colors",
      isOver ? "bg-brand-100 ring-2 ring-brand-400 ring-inset" : "")}
      style={{ width: dw, minWidth: dw }}>
      {uniqueAssigs.map((a) => {
        const obra = obras.find((o) => o.id === a.obra_id);
        return (
          <div key={a.id} title={`${obra?.nombre || "?"}\nClic para quitar`}
            className={cn("rounded cursor-pointer hover:ring-2 hover:ring-red-400 text-white text-center leading-tight",
              dw > 60 ? "text-[8px] px-1 py-0.5 w-full" : "w-full h-3")}
            style={{ backgroundColor: obra?.color || "#DC2626" }}
            onClick={() => onRemove(a.id)}>
            {dw > 60 ? (obra?.nombre || "?").substring(0, 12) : ""}
          </div>
        );
      })}
    </div>
  );
});

// ---- Sortable Row for Vista Obras ----
function ObraRow({ obra, dateStrs, days, assignGrid, obraRange, resInfo, conflictCells, onRemove, onArchive, onAddManual, onChangeEstado, estados, dw, isWeekend, isToday, notas, onNoteSaved }: {
  obra: Obra; dateStrs: string[]; days: Date[]; assignGrid: Record<string, Asignacion[]>;
  obraRange?: { min: string; max: string }; resInfo: Record<string, ResourceInfo>;
  conflictCells: Set<string>; onRemove: (id: string) => void; onArchive: (id: string, v: boolean) => void;
  onAddManual: (obraId: string, obraName: string) => void; onChangeEstado: (obraId: string, estadoId: string) => void;
  estados: EstadoObra[]; dw: number; isWeekend: (d: Date) => boolean; isToday: (d: Date) => boolean;
  notas: Record<string, any>; onNoteSaved: () => void;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: obra.id });
  const style = { transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0.4 : 1 };
  return (
    <div ref={setNodeRef} style={style} className={cn("flex border-b border-surface-100 group bg-white", obra.archivada && "opacity-50")}>
      <div className="shrink-0 flex items-center border-r border-surface-100" style={{ width: LABEL_W, minWidth: LABEL_W }}>
        <div {...attributes} {...listeners} className="px-1 py-3 cursor-grab text-surface-300 hover:text-surface-500"><GripVertical className="w-3.5 h-3.5" /></div>
        <div className="w-2 h-2 rounded-full shrink-0 mr-1.5" style={{ backgroundColor: obra.color || "#DC2626" }} />
        <div className="flex-1 min-w-0 py-1.5 pr-1">
          <Link href={`/obras/${obra.id}`} className="text-[11px] font-medium text-surface-900 hover:text-brand-600 truncate block" onClick={(e) => e.stopPropagation()}>{obra.nombre}</Link>
          <select value={obra.estado_obra_id || ""} onChange={(e) => { e.stopPropagation(); onChangeEstado(obra.id, e.target.value); }}
            className="text-[9px] pl-0.5 pr-3 py-0 border-0 bg-transparent rounded cursor-pointer focus:outline-none appearance-none"
            style={{ color: (obra as any).estado_custom?.color || "#6B7280" }} onClick={(e) => e.stopPropagation()}>
            <option value="">Sin estado</option>{estados.map((es) => <option key={es.id} value={es.id}>{es.nombre}</option>)}
          </select>
        </div>
        <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 pr-1">
          <button onClick={() => onAddManual(obra.id, obra.nombre)} title="Asignar recurso" className="p-0.5 rounded text-brand-500 hover:bg-brand-50"><Plus className="w-3.5 h-3.5" /></button>
          <button onClick={() => onArchive(obra.id, !obra.archivada)} className="p-0.5 rounded text-surface-400 hover:text-amber-600">
            {obra.archivada ? <Eye className="w-3 h-3" /> : <Archive className="w-3 h-3" />}
          </button>
        </div>
      </div>
      {dateStrs.map((ds, i) => {
        const cellAssigns = assignGrid[`${obra.id}|${ds}`] || [];
        const day = days[i]; const inRange = obraRange && ds >= obraRange.min && ds <= obraRange.max;
        return (
          <div key={ds} style={{ width: dw, minWidth: dw }} className={cn("border-r border-surface-100 relative",
            isToday(day) ? "bg-brand-50/30" : isWeekend(day) ? "bg-surface-50/60" : "")}>
            {inRange && <div className="absolute inset-0" style={{ backgroundColor: `${obra.color || "#DC2626"}08` }} />}
            <div className="relative h-full min-h-[44px] group">
              <ObraCell obraId={obra.id} dateStr={ds} assignments={cellAssigns} resInfo={resInfo}
                onRemove={onRemove} dw={dw} hasConflict={conflictCells.has(`${obra.id}|${ds}`)} />
              <div className="absolute top-0 right-0.5 z-10">
                <CellNote obraId={obra.id} fecha={ds} nota={notas[`${obra.id}|${ds}`] || null} onSaved={onNoteSaved} />
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ---- Sortable Person Row for Vista RRHH ----
function SortablePersonRow({ persona, dateStrs, days, assignGrid, obras, onRemove, dw, isWeekend, isToday }: {
  persona: RecursoHumano; dateStrs: string[]; days: Date[]; assignGrid: Record<string, Asignacion[]>;
  obras: Obra[]; onRemove: (id: string) => void; dw: number;
  isWeekend: (d: Date) => boolean; isToday: (d: Date) => boolean;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: `prow-${persona.id}` });
  const style = { transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0.4 : 1 };
  return (
    <div ref={setNodeRef} style={style} className="flex border-b border-surface-100 bg-white">
      <div className="shrink-0 flex items-center border-r border-surface-100" style={{ width: LABEL_W, minWidth: LABEL_W }}>
        <div {...attributes} {...listeners} className="px-1 py-3 cursor-grab text-surface-300 hover:text-surface-500"><GripVertical className="w-3.5 h-3.5" /></div>
        {persona.foto_url ? <img src={persona.foto_url} alt="" className="w-7 h-7 rounded-full object-cover shrink-0" /> :
          <div className="w-7 h-7 rounded-full bg-violet-100 flex items-center justify-center text-violet-700 text-[10px] font-bold shrink-0">
            {persona.nombre.split(" ").map((w) => w[0]).join("").slice(0, 2).toUpperCase()}
          </div>}
        <div className="min-w-0 ml-2"><p className="text-[11px] font-medium text-surface-900 truncate">{persona.nombre}</p>
          <p className="text-[10px] text-surface-400 truncate">{persona.perfil || ""}</p></div>
      </div>
      {dateStrs.map((ds, i) => {
        const day = days[i];
        const personDayAssigs = assignGrid[`person-${persona.id}|${ds}`] || [];
        return (
          <div key={ds} style={{ width: dw, minWidth: dw }}
            className={cn("border-r border-surface-100", isToday(day) ? "bg-brand-50/30" : isWeekend(day) ? "bg-surface-50/60" : "")}>
            <RrhhCell recursoId={persona.id} dateStr={ds} personAssignments={personDayAssigs}
              obras={obras} onRemove={onRemove} dw={dw} />
          </div>
        );
      })}
    </div>
  );
}

// ============================================================================
// MAIN PAGE
// ============================================================================
export default function PlanificacionPage() {
  const supabase = createClient();
  const [obras, setObras] = useState<Obra[]>([]); const [asignaciones, setAsignaciones] = useState<Asignacion[]>([]);
  const [rrhh, setRrhh] = useState<RecursoHumano[]>([]);
  const [vehList, setVehList] = useState<Vehiculo[]>([]);
  const [estados, setEstados] = useState<EstadoObra[]>([]);
  const [loading, setLoading] = useState(true);
  const [planView, setPlanView] = useState<PlanView>("obras");
  const [viewMode, setViewMode] = useState<ViewMode>("week");
  const [showArchived, setShowArchived] = useState(false);
  const [estadoFilter, setEstadoFilter] = useState("");
  const [resourceFilter, setResourceFilter] = useState<ResourceFilter>("all");
  const [panelFilter, setPanelFilter] = useState<PanelFilter>("all");
  const [panelOpen, setPanelOpen] = useState(true);
  const [resourceSearch, setResourceSearch] = useState("");
  const [obraSearch, setObraSearch] = useState("");
  const [notas, setNotas] = useState<Record<string, any>>({});
  const [isMobile, setIsMobile] = useState(false);
  const [mobileDay, setMobileDay] = useState(() => new Date());

  useEffect(() => {
    const check = () => setIsMobile(window.innerWidth < 1024);
    check(); window.addEventListener("resize", check);
    return () => window.removeEventListener("resize", check);
  }, []);
  const [activeDrag, setActiveDrag] = useState<{ nombre: string; foto_url?: string | null; color?: string; iconType: string } | null>(null);
  const [startDate, setStartDate] = useState(() => { const d = new Date(); d.setDate(d.getDate() - d.getDay() + 1); return new Date(d.getFullYear(), d.getMonth(), d.getDate()); });
  const [manualModal, setManualModal] = useState<{ obraId: string; obraName: string } | null>(null);
  const [manualForm, setManualForm] = useState({ recurso_tipo: "humano" as RecursoTipo, recurso_id: "", fecha_inicio: "", fecha_fin: "" }); // maquinaria y material eliminados del planificador
  const [manualSaving, setManualSaving] = useState(false);
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 8 } }));

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [oR, aR, hR, vR, eR] = await Promise.all([
      supabase.from("obras").select("*, cliente:clientes(*), estado_custom:estados_obra(*)").order("orden_gantt"),
      supabase.from("asignaciones").select("*"),
      supabase.from("recursos_humanos").select("*").eq("activo", true).order("orden_planificacion" as any, { ascending: true }).order("nombre"),
      supabase.from("vehiculos").select("*").eq("activo", true).order("nombre"),
      supabase.from("estados_obra").select("*").eq("activo", true).order("nombre"),
    ]);
    setObras((oR.data as Obra[]) || []); setAsignaciones(aR.data || []);
    setRrhh(hR.data || []); setVehList(vR.data || []);
    setEstados(eR.data || []); setLoading(false);
    // Fetch notas (resilient - table might not exist yet)
    try {
      const { data: notasData } = await supabase.from("planificador_notas").select("*");
      const notasMap: Record<string, any> = {};
      (notasData || []).forEach((n: any) => { notasMap[`${n.obra_id}|${n.fecha}`] = n; });
      setNotas(notasMap);
    } catch { /* table might not exist */ }
  }, []);
  useEffect(() => { fetchData(); }, [fetchData]);

  const resInfo = useMemo(() => {
    const m: Record<string, ResourceInfo> = {};
    rrhh.forEach((r) => m[`humano|${r.id}`] = { nombre: r.nombre, foto_url: r.foto_url, tipo: "humano", initials: r.nombre.split(" ").map((w) => w[0]).join("").slice(0, 2).toUpperCase() });
    vehList.forEach((r) => m[`vehiculo|${r.id}`] = { nombre: r.nombre, foto_url: r.foto_url, tipo: "vehiculo", initials: r.nombre.slice(0, 2).toUpperCase() });
    return m;
  }, [rrhh, vehList]);

  const dw = DAY_WIDTHS[viewMode]; const daysN = DAYS_COUNT[viewMode];
  const days = useMemo(() => { const a: Date[] = []; for (let i = 0; i < daysN; i++) { const d = new Date(startDate); d.setDate(d.getDate() + i); a.push(d); } return a; }, [startDate, daysN]);
  const dateStrs = useMemo(() => days.map((d) => toDS(d)), [days]);

  const assignGrid = useMemo(() => {
    const g: Record<string, Asignacion[]> = {};
    asignaciones.forEach((a) => {
      const s = new Date(a.fecha_inicio + "T12:00:00"); const e = new Date(a.fecha_fin + "T12:00:00");
      for (let d = new Date(s); d <= e; d.setDate(d.getDate() + 1)) {
        const ds = toDS(d);
        const k1 = `${a.obra_id}|${ds}`; if (!g[k1]) g[k1] = []; g[k1].push(a);
        if (a.recurso_tipo === "humano") {
          const k2 = `person-${a.recurso_id}|${ds}`; if (!g[k2]) g[k2] = []; g[k2].push(a);
        }
      }
    }); return g;
  }, [asignaciones]);

  const conflictCells = useMemo(() => {
    const rdm: Record<string, { obraId: string }[]> = {};
    asignaciones.forEach((a) => {
      if (!CONFLICT_TYPES.includes(a.recurso_tipo)) return;
      const s = new Date(a.fecha_inicio); const e = new Date(a.fecha_fin);
      for (let d = new Date(s); d <= e; d.setDate(d.getDate() + 1)) {
        const ds = toDS(d);
        const key = `${a.recurso_tipo}|${a.recurso_id}|${ds}`;
        if (!rdm[key]) rdm[key] = []; rdm[key].push({ obraId: a.obra_id });
      }
    });
    const cells = new Set<string>();
    Object.entries(rdm).forEach(([key, entries]) => {
      if (Array.from(new Set(entries.map((e) => e.obraId))).length > 1) {
        const ds = key.split("|")[2];
        entries.forEach((e) => cells.add(`${e.obraId}|${ds}`));
      }
    }); return cells;
  }, [asignaciones]);

  const obraRanges = useMemo(() => {
    const r: Record<string, { min: string; max: string }> = {};
    asignaciones.forEach((a) => {
      if (!r[a.obra_id]) r[a.obra_id] = { min: a.fecha_inicio, max: a.fecha_fin };
      else { if (a.fecha_inicio < r[a.obra_id].min) r[a.obra_id].min = a.fecha_inicio; if (a.fecha_fin > r[a.obra_id].max) r[a.obra_id].max = a.fecha_fin; }
    }); return r;
  }, [asignaciones]);

  // Sort obras: 1) assigned this week (alpha), 2) "a planificar" (alpha), 3) rest (alpha)
  const obrasConAsignacion = new Set<string>();
  asignaciones.forEach((a) => {
    const inicio = String(a.fecha_inicio).substring(0, 10);
    const fin = String(a.fecha_fin).substring(0, 10);
    for (const ds of dateStrs) {
      if (inicio <= ds && fin >= ds) { obrasConAsignacion.add(a.obra_id); break; }
    }
  });
  const filteredObras = obras.filter((o) => (!o.archivada || showArchived) && (!estadoFilter || o.estado_obra_id === estadoFilter));
  const byOrden = (a: any, b: any) => {
    const oa = a.orden_gantt ?? 9999; const ob = b.orden_gantt ?? 9999;
    return oa !== ob ? oa - ob : a.nombre.localeCompare(b.nombre, "es");
  };

  // Find flag obras and merge into one
  const rrhhFlagObra = filteredObras.find((o) => (o as any).flag_rrhh_sin_asignar);
  const vehFlagObra = filteredObras.find((o) => (o as any).flag_vehiculo_sin_asignar);
  const primaryFlagObra = rrhhFlagObra || vehFlagObra; // Use RRHH obra as the merged line, or vehicle if no RRHH
  const flagIds = new Set<string>();
  if (rrhhFlagObra) flagIds.add(rrhhFlagObra.id);
  if (vehFlagObra) flagIds.add(vehFlagObra.id);
  const mergedFlagObras = primaryFlagObra ? [primaryFlagObra] : [];

  const conAsig = filteredObras.filter((o) => !flagIds.has(o.id) && obrasConAsignacion.has(o.id)).sort(byOrden);
  const aPlanificar = filteredObras.filter((o) => !flagIds.has(o.id) && !obrasConAsignacion.has(o.id) && (o as any).estado_custom?.nombre?.toLowerCase().includes("planificar")).sort(byOrden);
  const resto = filteredObras.filter((o) => !flagIds.has(o.id) && !obrasConAsignacion.has(o.id) && !(o as any).estado_custom?.nombre?.toLowerCase().includes("planificar")).sort(byOrden);
  const sortedObrasAll = [...mergedFlagObras, ...conAsig, ...aPlanificar, ...resto];
  const sortedObras = obraSearch ? sortedObrasAll.filter((o) => o.nombre.toLowerCase().includes(obraSearch.toLowerCase())) : sortedObrasAll;
  const obraIds = sortedObras.map((o) => o.id);

  const primaryFlagObraId = primaryFlagObra?.id || null;

  // Virtual assignments for merged "sin asignar" line (visual only)
  const displayGrid = useMemo(() => {
    const g: Record<string, Asignacion[]> = {};
    Object.entries(assignGrid).forEach(([k, v]) => { g[k] = [...v]; });

    if (!primaryFlagObraId) return g;
    const targetObraId = primaryFlagObraId;

    const weekDays = dateStrs.filter((ds) => { const d = new Date(ds + "T12:00:00"); const day = d.getDay(); return day >= 1 && day <= 5; });

    // Add unassigned RRHH
    rrhh.filter((r) => (r as any).asignable !== false).forEach((person) => {
      weekDays.forEach((ds) => {
        const isAssigned = asignaciones.some((a) => a.recurso_tipo === "humano" && a.recurso_id === person.id && a.fecha_inicio <= ds && a.fecha_fin >= ds);
        if (!isAssigned) {
          const k = `${targetObraId}|${ds}`;
          if (!g[k]) g[k] = [];
          g[k].push({ id: `v-rrhh-${person.id}-${ds}`, obra_id: targetObraId, recurso_tipo: "humano", recurso_id: person.id, fecha_inicio: ds, fecha_fin: ds } as any);
        }
      });
    });

    // Add unassigned vehicles (same target obra)
    vehList.filter((r) => (r as any).asignable !== false).forEach((veh) => {
      weekDays.forEach((ds) => {
        const isAssigned = asignaciones.some((a) => a.recurso_tipo === "vehiculo" && a.recurso_id === veh.id && a.fecha_inicio <= ds && a.fecha_fin >= ds);
        if (!isAssigned) {
          const k = `${targetObraId}|${ds}`;
          if (!g[k]) g[k] = [];
          g[k].push({ id: `v-veh-${veh.id}-${ds}`, obra_id: targetObraId, recurso_tipo: "vehiculo", recurso_id: veh.id, fecha_inicio: ds, fecha_fin: ds } as any);
        }
      });
    });

    return g;
  }, [assignGrid, primaryFlagObraId, rrhh, vehList, dateStrs, asignaciones]);
  // obraIds computed above with sortedObras

  const navigate = (dir: number) => { const d = new Date(startDate); d.setDate(d.getDate() + dir * (viewMode === "week" ? 7 : viewMode === "month" ? 31 : 90)); setStartDate(d); };
  const goToday = () => { const d = new Date(); d.setDate(d.getDate() - d.getDay() + 1); setStartDate(new Date(d.getFullYear(), d.getMonth(), d.getDate())); };
  const isTodayFn = (d: Date) => { const t = new Date(); return d.getDate() === t.getDate() && d.getMonth() === t.getMonth() && d.getFullYear() === t.getFullYear(); };
  const isWeekendFn = (d: Date) => d.getDay() === 0 || d.getDay() === 6;

  const handleDragStart = (e: DragStartEvent) => { const d = e.active.data.current; if (d) setActiveDrag({ nombre: d.nombre, foto_url: d.foto_url, color: d.color, iconType: d.iconType }); };

  const handleDragEnd = async (e: DragEndEvent) => {
    setActiveDrag(null); if (!e.over) return;
    const aid = String(e.active.id); const oid = String(e.over.id);

    // ---- Vista Obras: drop resource on obra cell ----
    if (aid.startsWith("res-") && oid.startsWith("cell-")) {
      const [tipo, recursoId] = aid.replace("res-", "").split("|");
      const [obraId, dateStr] = oid.replace("cell-", "").split("|");
      if (!tipo || !recursoId || !obraId || !dateStr) return;
      const existing = assignGrid[`${obraId}|${dateStr}`]?.find((a) => a.recurso_tipo === tipo && a.recurso_id === recursoId);
      if (existing) return;
      await supabase.from("asignaciones").insert({ obra_id: obraId, recurso_tipo: tipo as RecursoTipo, recurso_id: recursoId, fecha_inicio: dateStr, fecha_fin: dateStr });
      fetchData(); return;
    }

    // ---- Vista RRHH: drop obra on person cell ----
    if (aid.startsWith("panel-obra|") && oid.startsWith("cell-")) {
      const obraId = aid.replace("panel-obra|", "");
      const [recursoId, dateStr] = oid.replace("cell-", "").split("|");
      if (!obraId || !recursoId || !dateStr) return;
      const existing = assignGrid[`${obraId}|${dateStr}`]?.find((a) => a.recurso_tipo === "humano" && a.recurso_id === recursoId);
      if (existing) return;
      await supabase.from("asignaciones").insert({ obra_id: obraId, recurso_tipo: "humano", recurso_id: recursoId, fecha_inicio: dateStr, fecha_fin: dateStr });
      fetchData(); return;
    }

    // ---- Vista RRHH: drop maq/veh/mat on person cell (assign to person's obra that day) ----
    if (aid.startsWith("panel-vehiculo|") && oid.startsWith("cell-")) {
      const parts = aid.replace("panel-", "").split("|");
      const tipo = parts[0] as RecursoTipo; const recursoId = parts[1];
      const [personId, dateStr] = oid.replace("cell-", "").split("|");
      // Find which obra this person is assigned to on this day
      const personAssigs = assignGrid[`person-${personId}|${dateStr}`] || [];
      if (personAssigs.length === 0) return; // Person not assigned to any obra that day
      const obraId = personAssigs[0].obra_id;
      const existing = assignGrid[`${obraId}|${dateStr}`]?.find((a) => a.recurso_tipo === tipo && a.recurso_id === recursoId);
      if (existing) return;
      await supabase.from("asignaciones").insert({ obra_id: obraId, recurso_tipo: tipo, recurso_id: recursoId, fecha_inicio: dateStr, fecha_fin: dateStr });
      fetchData(); return;
    }

    // ---- Row reorder (Vista Obras) ----
    if (!aid.startsWith("res-") && !aid.startsWith("cell-") && !aid.startsWith("panel-") && !aid.startsWith("prow-") &&
        !oid.startsWith("cell-") && !oid.startsWith("res-") && !oid.startsWith("panel-") && !oid.startsWith("prow-")) {
      if (aid === oid) return;
      const oldIdx = obraIds.indexOf(aid); const newIdx = obraIds.indexOf(oid);
      if (oldIdx === -1 || newIdx === -1) return;
      const newOrder = arrayMove(obraIds, oldIdx, newIdx);
      await Promise.all(newOrder.map((id, i) => supabase.from("obras").update({ orden_gantt: i } as any).eq("id", id)));
      fetchData();
      return;
    }

    // ---- Row reorder (Vista RRHH) ----
    if (aid.startsWith("prow-") && oid.startsWith("prow-")) {
      if (aid === oid) return;
      const sortedRrhh = [...rrhh].sort((a, b) => ((a as any).orden_planificacion || 0) - ((b as any).orden_planificacion || 0));
      const ids = sortedRrhh.map((p) => `prow-${p.id}`);
      const oldIdx = ids.indexOf(aid); const newIdx = ids.indexOf(oid);
      if (oldIdx === -1 || newIdx === -1) return;
      const newOrder = arrayMove(ids, oldIdx, newIdx);
      await Promise.all(newOrder.map((prefixedId, i) => {
        const personId = prefixedId.replace("prow-", "");
        return supabase.from("recursos_humanos").update({ orden_planificacion: i } as any).eq("id", personId);
      }));
      fetchData();
    }
  };

  const handleRemove = async (id: string) => { await supabase.from("asignaciones").delete().eq("id", id); fetchData(); };
  const handleArchive = async (id: string, v: boolean) => {
    const update: any = { archivada: v };
    // When archiving, set estado to "Terminada/Cerrada"
    if (v) {
      const cerrada = estados.find((e) => e.nombre.toLowerCase().includes("terminada") || e.nombre.toLowerCase().includes("cerrada"));
      if (cerrada) update.estado_obra_id = cerrada.id;
    }
    await supabase.from("obras").update(update as any).eq("id", id);
    fetchData();
  };

  const handleManualAssign = async () => {
    if (!manualModal || !manualForm.recurso_id || !manualForm.fecha_inicio || !manualForm.fecha_fin) return;
    setManualSaving(true);
    const s = new Date(manualForm.fecha_inicio); const e = new Date(manualForm.fecha_fin);
    const inserts: any[] = [];
    for (let d = new Date(s); d <= e; d.setDate(d.getDate() + 1)) {
      const ds = toDS(d);
      // Check if already assigned this resource to this obra on this day
      const alreadyExists = asignaciones.some((a) =>
        a.obra_id === manualModal.obraId && a.recurso_tipo === manualForm.recurso_tipo &&
        a.recurso_id === manualForm.recurso_id && a.fecha_inicio <= ds && a.fecha_fin >= ds
      );
      if (!alreadyExists) {
        inserts.push({ obra_id: manualModal.obraId, recurso_tipo: manualForm.recurso_tipo, recurso_id: manualForm.recurso_id, fecha_inicio: ds, fecha_fin: ds });
      }
    }
    if (inserts.length > 0) await supabase.from("asignaciones").insert(inserts);
    setManualSaving(false); setManualModal(null); fetchData();
  };

  const getResourceList = (tipo: RecursoTipo) => {
    if (tipo === "humano") return rrhh.filter((r) => (r as any).asignable !== false).map((r) => ({ id: r.id, nombre: r.nombre }));
    if (tipo === "vehiculo") return vehList.filter((r) => (r as any).asignable !== false).map((r) => ({ id: r.id, nombre: r.nombre }));
    return [];
  };

  // Panel items for Vista Obras (filter asignable + search)
  const obrasPanelItems = useMemo(() => {
    const all: { dragId: string; nombre: string; foto_url?: string | null; detail?: string; count: number; iconType: string }[] = [];
    const search = resourceSearch.toLowerCase();
    if (resourceFilter === "all" || resourceFilter === "humano") rrhh.filter((r) => (r as any).asignable !== false).forEach((r) => all.push({ dragId: `res-humano|${r.id}`, nombre: r.nombre, foto_url: r.foto_url, detail: r.perfil || undefined, count: asignaciones.filter((a) => a.recurso_tipo === "humano" && a.recurso_id === r.id).length, iconType: "humano" }));
    if (resourceFilter === "all" || resourceFilter === "vehiculo") vehList.filter((r) => (r as any).asignable !== false).forEach((r) => all.push({ dragId: `res-vehiculo|${r.id}`, nombre: r.nombre, foto_url: r.foto_url, detail: r.matricula || undefined, count: asignaciones.filter((a) => a.recurso_tipo === "vehiculo" && a.recurso_id === r.id).length, iconType: "vehiculo" }));
    return all.filter((r) => !search || r.nombre.toLowerCase().includes(search) || (r.detail || "").toLowerCase().includes(search)).sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
  }, [resourceFilter, rrhh, vehList, asignaciones, resourceSearch]);

  // Panel items for Vista RRHH (filter asignable + search)
  const rrhhPanelItems = useMemo(() => {
    const all: { dragId: string; nombre: string; foto_url?: string | null; color?: string; detail?: string; count: number; iconType: string }[] = [];
    const search = resourceSearch.toLowerCase();
    if (panelFilter === "all" || panelFilter === "obra") sortedObras.forEach((o) => all.push({ dragId: `panel-obra|${o.id}`, nombre: o.nombre, color: o.color || "#DC2626", detail: (o as any).cliente?.nombre, count: asignaciones.filter((a) => a.obra_id === o.id && a.recurso_tipo === "humano").length, iconType: "obra" }));
    if (panelFilter === "all" || panelFilter === "vehiculo") vehList.filter((r) => (r as any).asignable !== false).forEach((r) => all.push({ dragId: `panel-vehiculo|${r.id}`, nombre: r.nombre, foto_url: r.foto_url, detail: r.matricula || undefined, count: 0, iconType: "vehiculo" }));
    return all.filter((r) => !search || r.nombre.toLowerCase().includes(search) || (r.detail || "").toLowerCase().includes(search)).sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
  }, [panelFilter, sortedObras, vehList, asignaciones, resourceSearch]);

  const dayLabel = (d: Date, i: number) => {
    if (viewMode === "week") return d.toLocaleDateString("es-ES", { weekday: "short", day: "numeric", month: "short" });
    if (viewMode === "month") return d.toLocaleDateString("es-ES", { day: "numeric", month: "short" });
    return i % 7 === 0 ? `S${Math.ceil((i + 1) / 7)}` : "";
  };

  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  // Mobile helper
  const mobileDateStr = toDS(mobileDay);
  const mobileWeekDays = useMemo(() => {
    const d = new Date(mobileDay);
    const day = d.getDay(); const diff = d.getDate() - day + (day === 0 ? -6 : 1);
    const mon = new Date(d); mon.setDate(diff);
    return Array.from({ length: 7 }, (_, i) => { const dd = new Date(mon); dd.setDate(mon.getDate() + i); return dd; });
  }, [mobileDay]);

  if (loading) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;

  if (isMobile) {
    const DAY_SHORT = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"];
    const mobileObras = (() => {
      const result: { obra: any; recursos: any[] }[] = [];
      sortedObras.forEach((obra) => {
        const items = displayGrid[`${obra.id}|${mobileDateStr}`] || [];
        if (items.length > 0) result.push({ obra, recursos: items.map((a) => ({ ...a, nombre: resInfo[`${a.recurso_tipo}|${a.recurso_id}`]?.nombre || "?", tipo: a.recurso_tipo })) });
      });
      return result;
    })();
    const assignedPeople = new Set<string>();
    asignaciones.forEach((a) => { if (a.recurso_tipo === "humano" && a.fecha_inicio <= mobileDateStr && a.fecha_fin >= mobileDateStr) assignedPeople.add(a.recurso_id); });
    const unassigned = rrhh.filter((r) => (r as any).asignable !== false && !assignedPeople.has(r.id));
    const isWeekday = mobileDay.getDay() >= 1 && mobileDay.getDay() <= 5;

    return (
      <AppLayout>
        <div className="animate-fade-in pb-4">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2"><CalendarRange className="w-4 h-4 text-brand-600" /><h1 className="text-base font-display font-bold text-surface-900">Planificación</h1></div>
            {conflictCells.size > 0 && <span className="flex items-center gap-1 px-2 py-0.5 text-[10px] font-medium text-red-700 bg-red-50 rounded-lg"><AlertTriangle className="w-3 h-3" />{conflictCells.size}</span>}
          </div>
          {/* Week strip */}
          <div className="flex gap-1 mb-3">
            {mobileWeekDays.map((d) => {
              const ds = toDS(d); const isSelected = ds === mobileDateStr; const isToday = ds === toDS(new Date());
              const hasData = sortedObras.some((o) => (displayGrid[`${o.id}|${ds}`] || []).length > 0);
              return (
                <button key={ds} onClick={() => setMobileDay(d)}
                  className={cn("flex-1 flex flex-col items-center py-2 rounded-xl transition-all",
                    isSelected ? "bg-brand-500 text-white shadow-md" : isToday ? "bg-brand-50 text-brand-700" : "bg-surface-100 text-surface-600")}>
                  <span className="text-[9px] font-semibold uppercase">{DAY_SHORT[d.getDay()]}</span>
                  <span className={cn("text-lg font-bold leading-tight", isSelected ? "text-white" : "")}>{d.getDate()}</span>
                  {hasData && !isSelected && <div className="w-1 h-1 rounded-full bg-brand-400 mt-0.5" />}
                </button>
              );
            })}
          </div>
          {/* Week nav */}
          <div className="flex items-center justify-between mb-3">
            <button onClick={() => { const d = new Date(mobileDay); d.setDate(d.getDate() - 7); setMobileDay(d); }} className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100"><ChevronLeft className="w-4 h-4" /></button>
            <button onClick={() => setMobileDay(new Date())} className="px-3 py-1 text-xs font-medium text-brand-600 bg-brand-50 rounded-lg">Hoy</button>
            <button onClick={() => { const d = new Date(mobileDay); d.setDate(d.getDate() + 7); setMobileDay(d); }} className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100"><ChevronRight className="w-4 h-4" /></button>
          </div>
          <p className="text-sm font-semibold text-surface-900 mb-3">{mobileDay.toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "long" })}</p>
          {/* Obras */}
          {mobileObras.length === 0 ? (
            <div className="text-center py-12 bg-surface-50 rounded-xl border border-surface-100"><CalendarRange className="w-8 h-8 text-surface-300 mx-auto mb-2" /><p className="text-sm text-surface-500">Sin asignaciones</p></div>
          ) : (
            <div className="space-y-3">
              {mobileObras.map(({ obra, recursos }) => {
                const personas = recursos.filter((r) => r.tipo === "humano"); const otros = recursos.filter((r) => r.tipo !== "humano");
                return (
                  <div key={obra.id} className="bg-white rounded-xl border border-surface-200 overflow-hidden shadow-sm">
                    <div className="flex items-center gap-3 px-4 py-3 border-b border-surface-100" style={{ borderLeftWidth: 4, borderLeftColor: obra.color || "#DC2626" }}>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-semibold text-surface-900 truncate">{obra.nombre}</p>
                        {(obra as any).estado_custom && <span className="text-[9px] text-white px-1.5 py-0.5 rounded-full inline-block mt-0.5" style={{ backgroundColor: (obra as any).estado_custom?.color }}>{(obra as any).estado_custom?.nombre}</span>}
                      </div>
                      <span className="text-[10px] text-surface-400 font-medium">{recursos.length}</span>
                    </div>
                    <div className="px-4 py-2.5 space-y-1.5">
                      {personas.length > 0 && <div><p className="text-[9px] font-semibold text-surface-400 uppercase mb-1">Personas</p><div className="flex flex-wrap gap-1.5">{personas.map((r) => <span key={r.id} className="flex items-center gap-1 px-2 py-1 bg-violet-50 text-violet-700 rounded-lg text-[11px] font-medium"><span className="w-5 h-5 rounded-full bg-violet-200 flex items-center justify-center text-[8px] font-bold">{r.nombre.split(" ").map((w: string) => w[0]).join("").slice(0, 2)}</span>{r.nombre.split(" ")[0]}</span>)}</div></div>}
                      {otros.length > 0 && <div><p className="text-[9px] font-semibold text-surface-400 uppercase mb-1 mt-1">Recursos</p><div className="flex flex-wrap gap-1.5">{otros.map((r) => { const c: Record<string, string> = { maquinaria: "bg-amber-50 text-amber-700", vehiculo: "bg-teal-50 text-teal-700", material: "bg-emerald-50 text-emerald-700" }; return <span key={r.id} className={cn("px-2 py-1 rounded-lg text-[11px] font-medium", c[r.tipo] || "bg-surface-100")}>{r.nombre}</span>; })}</div></div>}
                    </div>
                    <div className="px-4 py-2 bg-surface-50 border-t border-surface-100 flex justify-end">
                      <button onClick={() => setManualModal({ obraId: obra.id, obraName: obra.nombre })} className="flex items-center gap-1 text-[10px] font-medium text-brand-600"><Plus className="w-3 h-3" />Asignar</button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
          {/* Unassigned */}
          {isWeekday && unassigned.length > 0 && (
            <div className="mt-4 bg-amber-50 rounded-xl border border-amber-200 p-4">
              <p className="text-[10px] font-semibold text-amber-700 uppercase mb-2">Sin asignar ({unassigned.length})</p>
              <div className="flex flex-wrap gap-1.5">{unassigned.map((r) => <span key={r.id} className="px-2 py-1 bg-white text-amber-800 rounded-lg text-[11px] font-medium border border-amber-200">{r.nombre.split(" ")[0]}</span>)}</div>
            </div>
          )}
        </div>
        <Modal open={!!manualModal} onClose={() => setManualModal(null)} title={`Asignar: ${manualModal?.obraName || ""}`}>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Tipo</label><select value={manualForm.recurso_tipo} onChange={(e) => setManualForm({ ...manualForm, recurso_tipo: e.target.value as RecursoTipo, recurso_id: "" })} className={ic}><option value="humano">Persona</option><option value="vehiculo">Vehículo</option></select></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Recurso</label><select value={manualForm.recurso_id} onChange={(e) => setManualForm({ ...manualForm, recurso_id: e.target.value })} className={ic}><option value="">Seleccionar...</option>{getResourceList(manualForm.recurso_tipo).map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}</select></div></div>
            <div className="grid grid-cols-2 gap-4"><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Desde</label><input type="date" value={manualForm.fecha_inicio || mobileDateStr} onChange={(e) => setManualForm({ ...manualForm, fecha_inicio: e.target.value })} className={ic} /></div><div><label className="block text-sm font-medium text-surface-700 mb-1.5">Hasta</label><input type="date" value={manualForm.fecha_fin || mobileDateStr} onChange={(e) => setManualForm({ ...manualForm, fecha_fin: e.target.value })} className={ic} /></div></div>
            <button onClick={handleManualAssign} disabled={manualSaving || !manualForm.recurso_id || !manualForm.fecha_inicio || !manualForm.fecha_fin} className="w-full flex items-center justify-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{manualSaving && <Loader2 className="w-4 h-4 animate-spin" />}Asignar</button>
          </div>
        </Modal>
      </AppLayout>
    );
  }

  // Desktop view
  return (
    <AppLayout>
      <DndContext sensors={sensors} collisionDetection={customCollision} onDragStart={handleDragStart} onDragEnd={handleDragEnd}>
        <div className="animate-fade-in h-[calc(100vh-7rem)] flex flex-col">
          {/* Header */}
          <div className="flex items-center justify-between mb-2 shrink-0">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-lg bg-brand-50 flex items-center justify-center"><CalendarRange className="w-4 h-4 text-brand-600" /></div>
              <h1 className="text-base font-display font-bold text-surface-900">Planificación</h1>
              {/* View toggle */}
              <div className="flex bg-surface-100 rounded-lg p-0.5 ml-2">
                <button onClick={() => setPlanView("obras")} className={cn("flex items-center gap-1 px-3 py-1 text-[11px] font-medium rounded-md transition-colors", planView === "obras" ? "bg-white text-surface-900 shadow-sm" : "text-surface-500")}>
                  <Building2 className="w-3.5 h-3.5" />Vista Obras
                </button>
                <button onClick={() => setPlanView("rrhh")} className={cn("flex items-center gap-1 px-3 py-1 text-[11px] font-medium rounded-md transition-colors", planView === "rrhh" ? "bg-white text-surface-900 shadow-sm" : "text-surface-500")}>
                  <Users className="w-3.5 h-3.5" />Vista Personas
                </button>
              </div>
            </div>
            <div className="flex items-center gap-2">
              {conflictCells.size > 0 && <span className="flex items-center gap-1 px-2 py-1 text-[11px] font-medium text-red-700 bg-red-50 rounded-lg"><AlertTriangle className="w-3 h-3" />{conflictCells.size}</span>}
              <div className="relative">
                <input type="text" value={obraSearch} onChange={(e) => setObraSearch(e.target.value)} placeholder="Filtrar obra..." className="w-32 px-2 py-1 pl-7 text-[11px] bg-surface-100 border-0 rounded-lg text-surface-600 placeholder:text-surface-400 focus:outline-none focus:ring-1 focus:ring-brand-500/30 focus:w-44 transition-all" />
                <Search className="w-3 h-3 text-surface-400 absolute left-2 top-1/2 -translate-y-1/2" />
                {obraSearch && <button onClick={() => setObraSearch("")} className="absolute right-1.5 top-1/2 -translate-y-1/2 text-surface-400 hover:text-surface-600"><X className="w-3 h-3" /></button>}
              </div>
              <select value={estadoFilter} onChange={(e) => setEstadoFilter(e.target.value)} className="px-2 py-1 text-[11px] bg-surface-100 border-0 rounded-lg text-surface-600 focus:outline-none">
                <option value="">Todos estados</option>{estados.map((es) => <option key={es.id} value={es.id}>{es.nombre}</option>)}
              </select>
              <button onClick={() => setShowArchived(!showArchived)} className={cn("flex items-center gap-1 px-2 py-1 text-[11px] font-medium rounded-lg", showArchived ? "bg-surface-200 text-surface-700" : "bg-surface-100 text-surface-500")}><Archive className="w-3 h-3" /></button>
              <Link href="/obras/nueva" className="flex items-center gap-1 px-2.5 py-1 text-[11px] font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-3 h-3" />Obra</Link>
            </div>
          </div>
          {/* Nav */}
          <div className="flex items-center justify-between mb-1.5 shrink-0">
            <div className="flex items-center gap-1">
              <button onClick={() => navigate(-1)} className="p-1 rounded text-surface-400 hover:bg-surface-100"><ChevronLeft className="w-4 h-4" /></button>
              <button onClick={goToday} className="px-2 py-0.5 text-[10px] font-medium text-brand-600 bg-brand-50 rounded hover:bg-brand-100">Hoy</button>
              <button onClick={() => navigate(1)} className="p-1 rounded text-surface-400 hover:bg-surface-100"><ChevronRight className="w-4 h-4" /></button>
              <span className="text-[11px] font-medium text-surface-600 ml-1">{days[0].toLocaleDateString("es-ES", { day: "numeric", month: "long" })} — {days[days.length - 1].toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" })}</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="flex bg-surface-100 rounded p-0.5">{(["week", "month", "year"] as ViewMode[]).map((v) => (
                <button key={v} onClick={() => setViewMode(v)} className={cn("px-2 py-0.5 text-[10px] font-medium rounded transition-colors", viewMode === v ? "bg-white text-surface-900 shadow-sm" : "text-surface-500")}>
                  {v === "week" ? "Semana" : v === "month" ? "Mes" : "Año"}</button>))}</div>
              <button onClick={() => setPanelOpen(!panelOpen)} className={cn("px-2 py-1 text-[10px] font-medium rounded-lg", panelOpen ? "bg-brand-50 text-brand-600" : "bg-surface-100 text-surface-500")}>{panelOpen ? "Ocultar" : "Panel"}</button>
              
            </div>
          </div>

          {/* Grid */}
          <div className="flex gap-0 flex-1 min-h-0">
            <div className="flex-1 card overflow-hidden flex flex-col min-w-0">
              <div className="flex-1 overflow-auto">
                <div style={{ minWidth: LABEL_W + daysN * dw }}>
                  {/* Day header */}
                  <div className="flex sticky top-0 z-20 bg-white border-b border-surface-200">
                    <div className="shrink-0 px-2 py-1.5 bg-surface-50 border-r border-surface-200 text-[10px] font-semibold text-surface-400 uppercase flex items-center" style={{ width: LABEL_W, minWidth: LABEL_W }}>
                      {planView === "obras" ? <><GripVertical className="w-3 h-3 mr-1 opacity-0" />Obra</> : <><Users className="w-3 h-3 mr-1" />Persona</>}
                    </div>
                    {days.map((d, i) => (
                      <div key={i} className={cn("text-center py-1.5 border-r border-surface-100 text-[10px] shrink-0 leading-tight",
                        isTodayFn(d) ? "bg-brand-50 font-bold text-brand-700" : isWeekendFn(d) ? "bg-surface-50 text-surface-400" : "text-surface-600")}
                        style={{ width: dw, minWidth: dw }}>{dayLabel(d, i)}</div>
                    ))}
                  </div>

                  {/* ===== VISTA OBRAS ===== */}
                  {planView === "obras" && (
                    <SortableContext key={obraIds.join(",")} items={obraIds} strategy={verticalListSortingStrategy}>
                      {sortedObras.map((obra) => (
                        <ObraRow key={obra.id} obra={obra} dateStrs={dateStrs} days={days}
                          assignGrid={displayGrid} obraRange={obraRanges[obra.id]} resInfo={resInfo}
                          conflictCells={conflictCells} onRemove={handleRemove} onArchive={handleArchive}
                          onAddManual={(id, name) => { setManualModal({ obraId: id, obraName: name }); setManualForm({ recurso_tipo: "humano", recurso_id: "", fecha_inicio: "", fecha_fin: "" }); }}
                          onChangeEstado={async (oId, eId) => { await supabase.from("obras").update({ estado_obra_id: eId || null } as any).eq("id", oId); fetchData(); }}
                          estados={estados} dw={dw} isWeekend={isWeekendFn} isToday={isTodayFn}
                          notas={notas} onNoteSaved={fetchData} />
                      ))}
                    </SortableContext>
                  )}

                  {/* ===== VISTA RRHH ===== */}
                  {planView === "rrhh" && (() => {
                    const assignableRrhh = rrhh.filter((r) => (r as any).asignable !== false);
                    const rrhhWithAssignments = new Set<string>();
                    asignaciones.forEach((a) => { if (a.recurso_tipo === "humano") dateStrs.forEach((ds) => { if (a.fecha_inicio <= ds && a.fecha_fin >= ds) rrhhWithAssignments.add(a.recurso_id); }); });
                    const sortedRrhh = [...assignableRrhh].sort((a, b) => {
                      const aHas = rrhhWithAssignments.has(a.id);
                      const bHas = rrhhWithAssignments.has(b.id);
                      if (aHas && !bHas) return -1;
                      if (!aHas && bHas) return 1;
                      return a.nombre.localeCompare(b.nombre, "es");
                    });
                    const rrhhIds = sortedRrhh.map((p) => `prow-${p.id}`);
                    return (
                      <SortableContext key={rrhhIds.join(",")} items={rrhhIds} strategy={verticalListSortingStrategy}>
                        {sortedRrhh.map((persona) => (
                          <SortablePersonRow key={persona.id} persona={persona} dateStrs={dateStrs} days={days}
                            assignGrid={displayGrid} obras={obras} onRemove={handleRemove} dw={dw}
                            isWeekend={isWeekendFn} isToday={isTodayFn} />
                        ))}
                      </SortableContext>
                    );
                  })()}

                  {((planView === "obras" && sortedObras.length === 0) || (planView === "rrhh" && rrhh.length === 0)) && (
                    <div className="py-16 text-center"><p className="text-sm text-surface-500">No hay datos</p></div>
                  )}
                </div>
              </div>
            </div>

            {/* Panel */}
            {panelOpen && (
              <div className="w-[240px] shrink-0 ml-2 card flex flex-col overflow-hidden">
                <div className="px-3 py-2 border-b border-surface-200 bg-surface-50 flex items-center justify-between">
                  <div><p className="text-[11px] font-semibold text-surface-900">{planView === "obras" ? "Recursos" : "Obras y recursos"}</p><p className="text-[9px] text-surface-400">Arrastra al calendario</p></div>
                  <button onClick={() => setPanelOpen(false)} className="p-1 rounded text-surface-400 hover:bg-surface-200"><X className="w-3 h-3" /></button>
                </div>

                {/* Filters */}
                {planView === "obras" ? (
                  <div className="flex border-b border-surface-200 px-1 py-1 gap-0.5 flex-wrap">
                    {([{ id: "all" as ResourceFilter, label: "Todo" }, { id: "humano" as ResourceFilter, icon: Users }, { id: "maquinaria" as ResourceFilter, icon: Wrench }, { id: "vehiculo" as ResourceFilter, icon: Truck }, { id: "material" as ResourceFilter, icon: Package }]).map((f) => (
                      <button key={f.id} onClick={() => setResourceFilter(f.id)} className={cn("px-1.5 py-0.5 text-[10px] font-medium rounded flex items-center gap-0.5", resourceFilter === f.id ? "bg-brand-50 text-brand-600" : "text-surface-500 hover:bg-surface-100")}>{f.icon && <f.icon className="w-3 h-3" />}{f.label || ""}</button>
                    ))}
                  </div>
                ) : (
                  <div className="flex border-b border-surface-200 px-1 py-1 gap-0.5 flex-wrap">
                    {([{ id: "all" as PanelFilter, label: "Todo" }, { id: "obra" as PanelFilter, icon: Building2 }, { id: "maquinaria" as PanelFilter, icon: Wrench }, { id: "vehiculo" as PanelFilter, icon: Truck }, { id: "material" as PanelFilter, icon: Package }]).map((f) => (
                      <button key={f.id} onClick={() => setPanelFilter(f.id)} className={cn("px-1.5 py-0.5 text-[10px] font-medium rounded flex items-center gap-0.5", panelFilter === f.id ? "bg-brand-50 text-brand-600" : "text-surface-500 hover:bg-surface-100")}>{f.icon && <f.icon className="w-3 h-3" />}{f.label || ""}</button>
                    ))}
                  </div>
                )}

                <div className="flex-1 overflow-y-auto p-1 space-y-0.5">
                  {/* Search box */}
                  <div className="px-1 pb-1">
                    <input type="text" value={resourceSearch} onChange={(e) => setResourceSearch(e.target.value)} placeholder="Buscar recurso..."
                      className="w-full px-2.5 py-1.5 bg-surface-50 border border-surface-200 rounded-md text-[11px] placeholder:text-surface-400 focus:outline-none focus:ring-1 focus:ring-brand-500/30 focus:border-brand-400" />
                  </div>
                  {planView === "obras" ? obrasPanelItems.map((r) => <PanelItem key={r.dragId} {...r} />) :
                    rrhhPanelItems.map((r) => <PanelItem key={r.dragId} {...r} />)}
                </div>
              </div>
            )}
          </div>
        </div>

        <DragOverlay dropAnimation={null}>{activeDrag && (
          <div className="flex items-center gap-2 px-3 py-2 rounded-lg shadow-xl border text-xs font-medium bg-white border-surface-300">
            {activeDrag.color ? <div className="w-5 h-5 rounded-full" style={{ backgroundColor: activeDrag.color }}><Building2 className="w-3 h-3 text-white m-1" /></div> :
              activeDrag.foto_url ? <img src={activeDrag.foto_url} className="w-5 h-5 rounded-full object-cover" alt="" /> :
              (() => { const I = TIPO_ICON[activeDrag.iconType] || Building2; return <I className="w-4 h-4" />; })()}
            {activeDrag.nombre}
          </div>
        )}</DragOverlay>
      </DndContext>

      {/* Manual assignment modal */}
      <Modal open={!!manualModal} onClose={() => setManualModal(null)} title={`Asignar: ${manualModal?.obraName || ""}`}>
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Tipo</label>
              <select value={manualForm.recurso_tipo} onChange={(e) => setManualForm({ ...manualForm, recurso_tipo: e.target.value as RecursoTipo, recurso_id: "" })} className={ic}>
                <option value="humano">Persona</option><option value="maquinaria">Maquinaria</option><option value="vehiculo">Vehículo</option><option value="material">Material</option>
              </select></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Recurso *</label>
              <select value={manualForm.recurso_id} onChange={(e) => setManualForm({ ...manualForm, recurso_id: e.target.value })} className={ic}>
                <option value="">Seleccionar...</option>{getResourceList(manualForm.recurso_tipo).map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}
              </select></div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Fecha inicio *</label><input type="date" value={manualForm.fecha_inicio} onChange={(e) => setManualForm({ ...manualForm, fecha_inicio: e.target.value })} className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Fecha fin *</label><input type="date" value={manualForm.fecha_fin} onChange={(e) => setManualForm({ ...manualForm, fecha_fin: e.target.value })} min={manualForm.fecha_inicio} className={ic} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <button onClick={() => setManualModal(null)} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button onClick={handleManualAssign} disabled={manualSaving || !manualForm.recurso_id || !manualForm.fecha_inicio || !manualForm.fecha_fin}
              className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {manualSaving && <Loader2 className="w-4 h-4 animate-spin" />}Asignar</button>
          </div>
        </div>
      </Modal>
    </AppLayout>
  );
}
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\planificacion\page.tsx" -ForegroundColor Green

$dst = "src\app\dashboard\page.tsx"
$content = @'
"use client";

import AppLayout from "@/components/layout/AppLayout";
import { useAuthStore } from "@/hooks/useAuth";
import { createClient } from "@/lib/supabase/client";
import { useEffect, useState, useCallback } from "react";
import type { RecursoTipo } from "@/lib/types/database";
import {
  CheckCircle2, Clock, AlertTriangle, ListTodo,
  Building2, ClipboardList, Users, Truck, Calendar,
  Loader2, ChevronLeft, ChevronRight, Warehouse, TrendingDown
} from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils/cn";
import { filtrarObrasVisiblesOperario } from "@/lib/utils/obrasVisiblesOperario";

interface ConflictInfo { recursoId: string; recursoName: string; recursoTipo: RecursoTipo; date: string; obras: string[] }
type AssigView = "dia" | "semana";

const CONFLICT_TYPES: RecursoTipo[] = ["humano", "maquinaria", "vehiculo"];
const DAY_NAMES = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"];
const toDS = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const parseDS = (ds: string) => { const [y, m, d] = ds.split("-").map(Number); return new Date(y, m - 1, d); };

export default function DashboardPage() {
  const { user } = useAuthStore();
  const [tareas, setTareas] = useState<any[]>([]);
  const [conflicts, setConflicts] = useState<ConflictInfo[]>([]);
  const [obrasActivas, setObrasActivas] = useState<any[]>([]);
  const [obraSearch, setObraSearch] = useState("");
  const [obraEstadoFilter, setObraEstadoFilter] = useState("");
  const [partesSinFirma, setPartesSinFirma] = useState<any[]>([]);
  const [checklistItems, setChecklistItems] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [taskFilter, setTaskFilter] = useState<"mine" | "all">("mine");
  const [alertasAlmacen, setAlertasAlmacen] = useState<any[]>([]);

  // Assignments panel state
  const [assigView, setAssigView] = useState<AssigView>("dia");
  const [assigDate, setAssigDate] = useState(() => { const d = new Date(); return new Date(d.getFullYear(), d.getMonth(), d.getDate()); });
  const [assigData, setAssigData] = useState<Record<string, { nombre: string; obras: { nombre: string; color: string }[] }[]>>({});
  const [assigLoading, setAssigLoading] = useState(false);
  const [allAsignaciones, setAllAsignaciones] = useState<any[]>([]);
  const [rrhhNames, setRrhhNames] = useState<Record<string, string>>({});
  const [obraMap, setObraMap] = useState<Record<string, any>>({});

  // Fetch main data once
  useEffect(() => {
    const fetchAll = async () => {
      const supabase = createClient();
      const [tareasR, obrasR, partesR, asigR, rrhhR, maqR, vehR, revisadosR, misPartesR] = await Promise.all([
        supabase.from("tareas").select("*, obra:obras(nombre, color), tipo_tarea:tipo_tarea(nombre), recurso_asignado:recursos_humanos(nombre)").eq("estado", "pendiente").order("fecha_limite", { ascending: true, nullsFirst: false }),
        supabase.from("obras").select("*, estado_custom:estados_obra(*), cliente:clientes(nombre)").eq("archivada", false).order("nombre"),
        supabase.from("partes_diarios").select("*, obra:obras(nombre, color), creator:users!partes_diarios_created_by_fkey(nombre)").eq("estado", "pendiente").order("fecha", { ascending: false }).limit(10),
        supabase.from("asignaciones").select("*"),
        supabase.from("recursos_humanos").select("id, nombre").eq("activo", true),
        Promise.resolve({ data: [] }),  // maquinaria eliminada del planificador
        supabase.from("vehiculos").select("id, nombre"),
        supabase.from("conflictos_revisados").select("recurso_tipo, recurso_id, fecha"),
        user?.id ? supabase.from("partes_diarios").select("obra_id, fecha, estado").eq("created_by", user.id) : Promise.resolve({ data: [] as any[] }),
      ]);

      let obrasVisibles = (obrasR.data || []) as any[];
      if (user?.role !== "admin" && user?.recurso_id) {
        const misAsig = (asigR.data || []).filter((a: any) => a.recurso_tipo === "humano" && a.recurso_id === user.recurso_id);
        obrasVisibles = filtrarObrasVisiblesOperario(obrasVisibles, misAsig as any, (misPartesR.data || []) as any);
      }

      setTareas((tareasR.data || []) as any[]);
      setObrasActivas(obrasVisibles);
      setPartesSinFirma((partesR.data || []) as any[]);

      // Fetch checklist items assigned to current user
      if (user?.recurso_id) {
        const { data: clItems } = await supabase.from("checklist_items")
          .select("*, checklist:checklists(titulo, obra_id, obra:obras(nombre, color))")
          .eq("asignado_a", user.recurso_id)
          .eq("completado", false)
          .order("prioridad")
          .limit(20);
        setChecklistItems(clItems || []);
      }

      setAllAsignaciones(asigR.data || []);

      const names: Record<string, string> = {};
      (rrhhR.data || []).forEach((r: any) => names[r.id] = r.nombre);
      setRrhhNames(names);

      const om: Record<string, any> = {};
      (obrasR.data || []).forEach((o: any) => om[o.id] = o);
      setObraMap(om);

      // Conflicts
      const nameMap: Record<string, string> = {};
      (rrhhR.data || []).forEach((r: any) => nameMap[`humano|${r.id}`] = r.nombre);
      // maquinaria eliminada del planificador
      (vehR.data || []).forEach((r: any) => nameMap[`vehiculo|${r.id}`] = r.nombre);

      const rdm: Record<string, { obraId: string }[]> = {};
      (asigR.data || []).forEach((a: any) => {
        if (!CONFLICT_TYPES.includes(a.recurso_tipo)) return;
        const s = new Date(a.fecha_inicio); const e = new Date(a.fecha_fin);
        for (let d = new Date(s); d <= e; d.setDate(d.getDate() + 1)) {
          const ds = toDS(d);
          const key = `${a.recurso_tipo}|${a.recurso_id}|${ds}`;
          if (!rdm[key]) rdm[key] = []; rdm[key].push({ obraId: a.obra_id });
        }
      });
      if (revisadosR.error) console.error("No se pudo leer conflictos_revisados (¿falta ejecutar la migracion 021?):", revisadosR.error);
      const revisedSet = new Set((revisadosR.data || []).map((r: any) => `${r.recurso_tipo}|${r.recurso_id}|${r.fecha}`));
      const cList: ConflictInfo[] = []; const seen = new Set<string>();
      Object.entries(rdm).forEach(([key, entries]) => {
        const uObras = Array.from(new Set(entries.map((e) => e.obraId)));
        if (uObras.length > 1) {
          const [tipo, rid, date] = key.split("|");
          const sk = `${rid}|${date}`; if (seen.has(sk)) return; seen.add(sk);
          if (revisedSet.has(`${tipo}|${rid}|${date}`)) return;
          cList.push({ recursoId: rid, recursoName: nameMap[`${tipo}|${rid}`] || "?", recursoTipo: tipo as RecursoTipo, date, obras: uObras.map((id) => om[id]?.nombre || "?") });
        }
      });
      setConflicts(cList.slice(0, 10));
      // Alertas almacen
      try {
        const { data: alertasData } = await supabase.from("v_alertas_almacen" as any).select("*").limit(8);
        setAlertasAlmacen(alertasData || []);
      } catch { /* tabla puede no existir si no se ejecuto la migracion 030 */ }
      setLoading(false);
    };
    fetchAll();
  }, [user]);

  const marcarRevisado = async (c: ConflictInfo) => {
    const supabase = createClient();
    setConflicts((prev) => prev.filter((x) => !(x.recursoId === c.recursoId && x.recursoTipo === c.recursoTipo && x.date === c.date)));
    const { error } = await supabase.from("conflictos_revisados").insert({
      recurso_tipo: c.recursoTipo, recurso_id: c.recursoId, fecha: c.date, revisado_por: user?.id,
    } as any);
    if (error) {
      console.error("Error guardando conflicto revisado:", error);
      alert("No se pudo guardar como revisado: " + error.message + "\n(¿se ejecutó la migración 021_conflictos_revisados.sql en Supabase?)");
      setConflicts((prev) => [...prev, c]);
    }
  };

  // Compute assignments for selected date(s)
  const computeAssignments = useCallback(() => {
    const dates: string[] = [];
    if (assigView === "dia") {
      dates.push(toDS(assigDate));
    } else {
      // Week: Mon to Sun
      const d = new Date(assigDate);
      const day = d.getDay(); const diff = d.getDate() - day + (day === 0 ? -6 : 1);
      const monday = new Date(d); monday.setDate(diff);
      for (let i = 0; i < 7; i++) {
        const dd = new Date(monday); dd.setDate(monday.getDate() + i);
        dates.push(toDS(dd));
      }
    }

    const result: Record<string, { nombre: string; obras: { nombre: string; color: string }[] }[]> = {};
    dates.forEach((ds) => {
      const personObras: Record<string, Set<string>> = {};
      allAsignaciones.forEach((a: any) => {
        if (a.recurso_tipo !== "humano") return;
        if (a.fecha_inicio <= ds && a.fecha_fin >= ds) {
          if (!personObras[a.recurso_id]) personObras[a.recurso_id] = new Set();
          personObras[a.recurso_id].add(a.obra_id);
        }
      });
      const list: { nombre: string; obras: { nombre: string; color: string }[] }[] = [];
      Object.entries(personObras).forEach(([pid, oids]) => {
        list.push({
          nombre: rrhhNames[pid] || "?",
          obras: Array.from(oids).map((oid) => ({ nombre: obraMap[oid]?.nombre || "?", color: obraMap[oid]?.color || "#999" })),
        });
      });
      list.sort((a, b) => a.nombre.localeCompare(b.nombre));
      result[ds] = list;
    });
    setAssigData(result);
  }, [assigDate, assigView, allAsignaciones, rrhhNames, obraMap]);

  useEffect(() => { if (!loading) computeAssignments(); }, [computeAssignments, loading]);

  const navigateDate = (dir: number) => {
    const d = new Date(assigDate);
    d.setDate(d.getDate() + (assigView === "dia" ? dir : dir * 7));
    setAssigDate(d);
  };
  const goToday = () => setAssigDate(new Date(new Date().getFullYear(), new Date().getMonth(), new Date().getDate()));

  const prioColors: Record<string, string> = { alta: "bg-red-100 text-red-700", media: "bg-amber-100 text-amber-700", baja: "bg-blue-100 text-blue-700" };
  const tipoIcon: Record<string, typeof Users> = { humano: Users, vehiculo: Truck };
  const getDateColor = (f: string | null) => { if (!f) return ""; const d = (new Date(f).getTime() - Date.now()) / 86400000; if (d < 0) return "text-red-600 bg-red-50"; if (d < 3) return "text-amber-600 bg-amber-50"; return "text-surface-600"; };
  const greeting = () => { const h = new Date().getHours(); if (h < 12) return "Buenos días"; if (h < 20) return "Buenas tardes"; return "Buenas noches"; };

  const filteredTareas = taskFilter === "mine" ? tareas.filter((t) => t.asignado_a === user?.recurso_id) : tareas;
  const obraEstadosDisponibles = Array.from(new Map(obrasActivas.filter((o) => o.estado_custom).map((o) => [o.estado_custom.id, o.estado_custom])).values());
  const obrasFiltradas = obrasActivas.filter((o) => {
    if (obraEstadoFilter && o.estado_obra_id !== obraEstadoFilter) return false;
    if (obraSearch.trim()) {
      const q = obraSearch.trim().toLowerCase();
      const hay = [o.nombre, o.cliente?.nombre, o.direccion, o.localidad, o.num_presupuesto, o.ubicacion].filter(Boolean).join(" ").toLowerCase();
      if (!hay.includes(q)) return false;
    }
    return true;
  });
  const assigDates = Object.keys(assigData).sort();
  const totalPersons = assigView === "dia" ? (assigData[assigDates[0]] || []).length : Object.values(assigData).reduce((acc, v) => Math.max(acc, v.length), 0);

  if (loading) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="mb-6">
          <h1 className="text-xl lg:text-2xl font-display font-bold text-surface-900">{greeting()}, {user?.nombre?.split(" ")[0]}</h1>
          <p className="text-surface-500 text-sm mt-1">{new Date().toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "long" })}</p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 lg:gap-6">
          {/* Asignaciones - navegable por día/semana */}
          <div className="card p-4 lg:p-5 lg:col-span-2 flex flex-col">
            <div className="flex items-center justify-between mb-3 shrink-0 flex-wrap gap-2">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2">
                <Calendar className="w-4 h-4 text-violet-500" />
                {assigView === "dia"
                  ? assigDate.toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "long" })
                  : `Semana del ${assigDates[0] ? parseDS(assigDates[0]).toLocaleDateString("es-ES", { day: "numeric", month: "long" }) : ""}`
                }
              </h2>
              <div className="flex items-center gap-2">
                {/* View toggle */}
                <div className="flex bg-surface-100 rounded p-0.5">
                  <button onClick={() => setAssigView("dia")} className={cn("px-2 py-0.5 text-[10px] font-medium rounded", assigView === "dia" ? "bg-white text-surface-900 shadow-sm" : "text-surface-500")}>Día</button>
                  <button onClick={() => setAssigView("semana")} className={cn("px-2 py-0.5 text-[10px] font-medium rounded", assigView === "semana" ? "bg-white text-surface-900 shadow-sm" : "text-surface-500")}>Semana</button>
                </div>
                {/* Date navigation */}
                <div className="flex items-center gap-1">
                  <button onClick={() => navigateDate(-1)} className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100"><ChevronLeft className="w-4 h-4" /></button>
                  <button onClick={goToday} className="px-2.5 py-1 text-[11px] font-medium text-brand-600 bg-brand-50 rounded-lg hover:bg-brand-100">Hoy</button>
                  <button onClick={() => navigateDate(1)} className="p-1.5 rounded-lg text-surface-400 hover:bg-surface-100"><ChevronRight className="w-4 h-4" /></button>
                </div>
                {/* Date picker */}
                <input type="date" value={toDS(assigDate)}
                  onChange={(e) => { if (e.target.value) setAssigDate(parseDS(e.target.value)); }}
                  className="px-2 py-1 text-xs bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20" />
                <span className="text-xs text-surface-400">{totalPersons} pers.</span>
              </div>
            </div>

            {/* Day view */}
            {assigView === "dia" && (() => {
              const ds = toDS(assigDate);
              const people = assigData[ds] || [];
              return people.length === 0 ? (
                <p className="text-sm text-surface-400 text-center py-8">Sin asignaciones para este día</p>
              ) : (
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2 ">
                  {people.map((m, i) => (
                    <div key={i} className="flex items-center gap-2.5 p-2.5 bg-surface-50 rounded-lg border border-surface-100">
                      <div className="w-7 h-7 rounded-full bg-violet-100 flex items-center justify-center text-violet-700 text-[9px] font-bold shrink-0">
                        {m.nombre.split(" ").map((w: string) => w[0]).join("").slice(0, 2).toUpperCase()}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-xs font-medium text-surface-900 truncate">{m.nombre}</p>
                        <div className="flex gap-1 mt-0.5 flex-wrap">
                          {m.obras.map((o: any, j: number) => (
                            <span key={j} className="text-[9px] text-white px-1.5 py-0.5 rounded" style={{ backgroundColor: o.color }}>{o.nombre}</span>
                          ))}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              );
            })()}

            {/* Week view */}
            {assigView === "semana" && (
              <div className="overflow-x-auto">
                <div className="min-w-[700px]">
                  {/* Day headers */}
                  <div className="grid grid-cols-8 gap-1 mb-2">
                    <div className="text-[10px] font-semibold text-surface-400 uppercase px-2 py-1">Persona</div>
                    {assigDates.map((ds) => {
                      const d = parseDS(ds);
                      const isToday = ds === toDS(new Date());
                      return (
                        <div key={ds} className={cn("text-[10px] font-semibold text-center px-1 py-1 rounded", isToday ? "bg-brand-50 text-brand-700" : "text-surface-400 uppercase")}>
                          {DAY_NAMES[d.getDay()]} {d.getDate()}
                        </div>
                      );
                    })}
                  </div>
                  {/* People rows */}
                  {(() => {
                    // Get all unique people across the week
                    const allPeople = new Set<string>();
                    assigDates.forEach((ds) => (assigData[ds] || []).forEach((p) => allPeople.add(p.nombre)));
                    const sortedPeople = Array.from(allPeople).sort();

                    if (sortedPeople.length === 0) return <p className="text-sm text-surface-400 text-center py-6">Sin asignaciones esta semana</p>;

                    return (
                      <div className="space-y-1 ">
                        {sortedPeople.map((nombre) => (
                          <div key={nombre} className="grid grid-cols-8 gap-1 items-center">
                            <div className="flex items-center gap-1.5 px-2 py-1.5">
                              <div className="w-5 h-5 rounded-full bg-violet-100 flex items-center justify-center text-violet-700 text-[7px] font-bold shrink-0">
                                {nombre.split(" ").map((w: string) => w[0]).join("").slice(0, 2).toUpperCase()}
                              </div>
                              <span className="text-[10px] font-medium text-surface-900 truncate">{nombre}</span>
                            </div>
                            {assigDates.map((ds) => {
                              const dayPeople = assigData[ds] || [];
                              const person = dayPeople.find((p) => p.nombre === nombre);
                              const isToday = ds === toDS(new Date());
                              return (
                                <div key={ds} className={cn("min-h-[32px] rounded px-1 py-0.5 flex flex-wrap gap-0.5 items-center", isToday ? "bg-brand-50/50" : "bg-surface-50")}>
                                  {person?.obras.map((o, j) => (
                                    <span key={j} className="text-[8px] text-white px-1 py-0.5 rounded leading-tight" style={{ backgroundColor: o.color }}>
                                      {o.nombre.length > 10 ? o.nombre.substring(0, 10) + "…" : o.nombre}
                                    </span>
                                  ))}
                                </div>
                              );
                            })}
                          </div>
                        ))}
                      </div>
                    );
                  })()}
                </div>
              </div>
            )}
          </div>
          {/* Tareas */}
          <div className="card p-4 lg:p-5 flex flex-col max-h-[380px]">
            <div className="flex items-center justify-between mb-3 shrink-0">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><ListTodo className="w-4 h-4 text-brand-600" />Tareas</h2>
              <div className="flex items-center gap-2">
                <div className="flex bg-surface-100 rounded p-0.5">
                  <button onClick={() => setTaskFilter("mine")} className={cn("px-2 py-0.5 text-[10px] font-medium rounded", taskFilter === "mine" ? "bg-white text-surface-900 shadow-sm" : "text-surface-500")}>Mías</button>
                  <button onClick={() => setTaskFilter("all")} className={cn("px-2 py-0.5 text-[10px] font-medium rounded", taskFilter === "all" ? "bg-white text-surface-900 shadow-sm" : "text-surface-500")}>Todas</button>
                </div>
                <span className="text-xs text-surface-400">{filteredTareas.length}</span>
              </div>
            </div>
            {filteredTareas.length === 0 ? (
              <div className="flex-1 flex flex-col items-center justify-center py-4"><CheckCircle2 className="w-8 h-8 text-emerald-400 mb-2" /><p className="text-sm text-surface-500">Sin tareas</p></div>
            ) : (
              <div className="space-y-1.5 overflow-y-auto flex-1">
                {filteredTareas.slice(0, 15).map((t) => (
                  <Link key={t.id} href={`/obras/${t.obra_id}`} className="flex items-start gap-2.5 p-2 rounded-lg hover:bg-surface-50 border border-surface-100">
                    <div className="w-2 h-2 rounded-full mt-1.5 shrink-0" style={{ backgroundColor: t.obra?.color || "#DC2626" }} />
                    <div className="flex-1 min-w-0">
                      <p className="text-xs font-medium text-surface-900 truncate">{t.descripcion}</p>
                      <div className="flex items-center gap-2 mt-0.5">
                        <span className="text-[10px] text-surface-400">{t.obra?.nombre}</span>
                        {t.recurso_asignado?.nombre && <span className="text-[10px] text-violet-500">→ {t.recurso_asignado.nombre}</span>}
                        <span className={cn("badge text-[9px]", prioColors[t.prioridad])}>{t.prioridad}</span>
                        {t.fecha_limite && <span className={cn("text-[9px] px-1 py-0.5 rounded", getDateColor(t.fecha_limite))}>{new Date(t.fecha_limite).toLocaleDateString("es-ES", { day: "numeric", month: "short" })}</span>}
                      </div>
                    </div>
                  </Link>
                ))}
              </div>
            )}
          </div>

          {/* Checklist items pendientes */}
          {checklistItems.length > 0 && (
          <div className="card overflow-hidden">
            <div className="flex items-center justify-between p-4 border-b border-surface-100">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><CheckCircle2 className="w-4 h-4 text-violet-500" />Mis items de checklist</h2>
              <span className="text-xs text-surface-400">{checklistItems.length} pendientes</span>
            </div>
            <div className="divide-y divide-surface-100 max-h-60 overflow-y-auto">
              {checklistItems.map((item) => {
                const pColors: Record<string, string> = { alta: "bg-red-100 text-red-700", media: "bg-amber-100 text-amber-700", baja: "bg-emerald-100 text-emerald-700" };
                return (
                  <div key={item.id} className="flex items-start gap-2.5 p-3 hover:bg-surface-50">
                    <button onClick={async () => {
                      const supabase = createClient();
                      await (supabase.from("checklist_items") as any).update({ completado: true, completado_at: new Date().toISOString(), completado_por: user?.id }).eq("id", item.id);
                      setChecklistItems((prev) => prev.filter((i) => i.id !== item.id));
                    }} className="mt-0.5 w-4 h-4 rounded border-2 border-surface-300 hover:border-emerald-400 shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="text-xs font-medium text-surface-900">{item.texto}</p>
                      <div className="flex items-center gap-2 mt-0.5">
                        <span className="text-[10px] text-surface-400">{item.checklist?.obra?.nombre || "—"}</span>
                        <span className="text-[10px] text-violet-500">{item.checklist?.titulo || ""}</span>
                        <span className={cn("badge text-[9px]", pColors[item.prioridad])}>{item.prioridad}</span>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
          )}

          {/* Conflictos */}
          <div className="card p-4 lg:p-5 flex flex-col max-h-[380px]">
            <div className="flex items-center justify-between mb-3 shrink-0">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><AlertTriangle className="w-4 h-4 text-amber-500" />Conflictos</h2>
              {conflicts.length > 0 && <span className="text-xs text-red-500 font-medium">{conflicts.length}</span>}
            </div>
            {conflicts.length === 0 ? (
              <div className="flex-1 flex flex-col items-center justify-center py-4"><CheckCircle2 className="w-8 h-8 text-emerald-400 mb-2" /><p className="text-sm text-surface-500">Sin conflictos</p></div>
            ) : (
              <div className="space-y-1.5 overflow-y-auto flex-1">
                {conflicts.map((c, i) => {
                  const Icon = tipoIcon[c.recursoTipo];
                  return (
                    <div key={i} className="flex items-start gap-2.5 p-2 bg-red-50 rounded-lg border border-red-100">
                      <Icon className="w-4 h-4 text-red-500 mt-0.5 shrink-0" />
                      <div className="min-w-0 flex-1"><p className="text-xs font-medium text-red-800">{c.recursoName}</p><p className="text-[10px] text-red-600">{new Date(c.date).toLocaleDateString("es-ES", { weekday: "short", day: "numeric", month: "short" })} — {c.obras.join(" y ")}</p></div>
                      <button onClick={() => marcarRevisado(c)} className="flex items-center gap-1 text-[10px] font-medium text-emerald-700 bg-emerald-50 hover:bg-emerald-100 px-2 py-1 rounded-lg shrink-0">
                        <CheckCircle2 className="w-3 h-3" /> Revisado
                      </button>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Obras activas */}
          <div className="card p-4 lg:p-5 flex flex-col max-h-[380px]">
            <div className="flex items-center justify-between mb-2 shrink-0">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><Building2 className="w-4 h-4 text-brand-600" />Obras activas</h2>
              <span className="text-xs text-surface-400">{obrasFiltradas.length}</span>
            </div>
            <div className="flex items-center gap-1.5 mb-2 shrink-0">
              <input type="text" value={obraSearch} onChange={(e) => setObraSearch(e.target.value)}
                placeholder="Buscar obra, cliente, dirección..."
                className="flex-1 min-w-0 px-2 py-1.5 text-xs bg-surface-50 border-0 rounded-lg placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20" />
              <select value={obraEstadoFilter} onChange={(e) => setObraEstadoFilter(e.target.value)}
                className="px-1.5 py-1.5 text-xs bg-surface-50 border-0 rounded-lg text-surface-600 focus:outline-none focus:ring-2 focus:ring-brand-500/20 max-w-[100px]">
                <option value="">Estado</option>
                {obraEstadosDisponibles.map((e: any) => <option key={e.id} value={e.id}>{e.nombre}</option>)}
              </select>
            </div>
            <div className="space-y-1.5 overflow-y-auto flex-1">
              {obrasFiltradas.map((o) => (
                <Link key={o.id} href={`/obras/${o.id}`} className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-50 border border-surface-100 group">
                  <div className="w-2 h-8 rounded-full shrink-0" style={{ backgroundColor: o.color || "#DC2626" }} />
                  <div className="flex-1 min-w-0"><p className="text-xs font-medium text-surface-900 group-hover:text-brand-600 truncate">{o.nombre}</p><p className="text-[10px] text-surface-400 truncate">{o.ubicacion || ""}</p></div>
                  {o.estado_custom && <span className="text-[9px] px-2 py-0.5 rounded-full text-white shrink-0" style={{ backgroundColor: o.estado_custom.color }}>{o.estado_custom.nombre}</span>}
                </Link>
              ))}
              {obrasFiltradas.length === 0 && <p className="text-sm text-surface-400 text-center py-4">Sin obras</p>}
            </div>
          </div>

          {/* Alertas de almacen */}
          {alertasAlmacen.length > 0 && (
            <div className="card p-4 lg:p-5 flex flex-col max-h-[320px]">
              <div className="flex items-center justify-between mb-3 shrink-0">
                <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2">
                  <Warehouse className="w-4 h-4 text-amber-500" />Alertas de almacen
                </h2>
                <span className="text-xs text-surface-400">{alertasAlmacen.length}</span>
              </div>
              <div className="space-y-1.5 overflow-y-auto flex-1">
                {alertasAlmacen.map((a: any, i: number) => (
                  <div key={i} className="flex items-center gap-2 px-2.5 py-1.5 rounded-lg bg-amber-50 border border-amber-100">
                    <TrendingDown className="w-3.5 h-3.5 text-amber-600 shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="text-xs font-medium text-surface-900 truncate">{a.nombre}</p>
                      <p className="text-[10px] text-surface-500">{a.almacen_nombre}</p>
                    </div>
                    <div className="flex flex-col items-end gap-0.5">
                      {a.alerta_stock && <span className="badge text-[9px] bg-red-100 text-red-700">Stock: {Number(a.stock_qty).toFixed(1)} / min {Number(a.stock_minimo_def).toFixed(1)}</span>}
                      {a.alerta_caducidad === "caducado" && <span className="badge text-[9px] bg-red-100 text-red-700">Caducado</span>}
                      {a.alerta_caducidad === "caduca_pronto" && <span className="badge text-[9px] bg-amber-100 text-amber-700">Caduca pronto</span>}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Partes sin firmar */}
          <div className="card p-4 lg:p-5 flex flex-col max-h-[380px]">
            <div className="flex items-center justify-between mb-3 shrink-0">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><ClipboardList className="w-4 h-4 text-orange-500" />Partes sin firmar</h2>
              <span className="text-xs text-surface-400">{partesSinFirma.length}</span>
            </div>
            {partesSinFirma.length === 0 ? (
              <div className="flex-1 flex flex-col items-center justify-center py-4"><CheckCircle2 className="w-8 h-8 text-emerald-400 mb-2" /><p className="text-sm text-surface-500">Todos firmados</p></div>
            ) : (
              <div className="space-y-1.5 overflow-y-auto flex-1">
                {partesSinFirma.map((p) => (
                  <Link key={p.id} href={`/partes/${p.id}`} className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-50 border border-surface-100 group">
                    <div className="w-1.5 h-8 rounded-full shrink-0" style={{ backgroundColor: p.obra?.color || "#D4D4D4" }} />
                    <div className="flex-1 min-w-0"><p className="text-xs font-medium text-surface-900 group-hover:text-brand-600">{p.creator?.nombre || "?"} — {p.obra?.nombre || "Sin obra"}</p><p className="text-[10px] text-surface-400">{new Date(p.fecha).toLocaleDateString("es-ES", { day: "numeric", month: "short" })}</p></div>
                    <div className="flex gap-1 shrink-0">
                      {!p.firma_data && <span className="text-[9px] text-amber-600 bg-amber-50 px-1.5 py-0.5 rounded">Resp.</span>}
                      {!p.firma_cliente && <span className="text-[9px] text-blue-600 bg-blue-50 px-1.5 py-0.5 rounded">Cliente</span>}
                    </div>
                  </Link>
                ))}
              </div>
            )}
          </div>

        </div>
      </div>
    </AppLayout>
  );
}
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\dashboard\page.tsx" -ForegroundColor Green

$dst = "src\app\almacen\movimientos\page.tsx"
$content = @'
"use client";
import { useState, useEffect, useCallback, useRef } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import {
  ArrowDownToLine, ArrowUpFromLine, ArrowLeftRight, SlidersHorizontal,
  Plus, Loader2, Search, Scan, CheckCircle2, X, Package
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";

type TipoMov = "entrada" | "salida" | "ajuste";
const ic = "w-full px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20";

const TIPO_CONFIG = {
  entrada:  { label: "Entrada",  icon: ArrowDownToLine,  color: "bg-emerald-100 text-emerald-700" },
  salida:   { label: "Salida",   icon: ArrowUpFromLine,  color: "bg-red-100 text-red-700" },
  ajuste:   { label: "Ajuste",   icon: SlidersHorizontal,color: "bg-amber-100 text-amber-700" },
  traslado_salida:  { label: "Traslado salida",  icon: ArrowLeftRight, color: "bg-blue-100 text-blue-700" },
  traslado_entrada: { label: "Traslado entrada", icon: ArrowLeftRight, color: "bg-blue-100 text-blue-700" },
};

interface ScanItem { articulo: any; cantidad: number; codigoBarras: string; }

export default function MovimientosPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const scanRef = useRef<HTMLInputElement>(null);

  const [movimientos, setMovimientos] = useState<any[]>([]);
  const [articulos, setArticulos] = useState<any[]>([]);
  const [almacenes, setAlmacenes] = useState<any[]>([]);
  const [obras, setObras] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");

  // Modal movimiento individual
  const [modalOpen, setModalOpen] = useState(false);
  const [tipo, setTipo] = useState<TipoMov>("entrada");
  const [form, setForm] = useState({ articulo_id: "", almacen_origen_id: "", almacen_destino_id: "", cantidad: "1", obra_id: "", observaciones: "" });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Modal traslado masivo (scan)
  const [trasladoOpen, setTrasladoOpen] = useState(false);
  const [scanInput, setScanInput] = useState("");
  const [scanItems, setScanItems] = useState<ScanItem[]>([]);
  const [trasladoForm, setTrasladoForm] = useState({ almacen_origen_id: "", almacen_destino_id: "", obra_id: "" });
  const [trasladoSaving, setTrasladoSaving] = useState(false);
  const [scanNotFound, setScanNotFound] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [mR, aR, alR, oR] = await Promise.all([
      (supabase.from("movimientos_almacen") as any)
        .select("*, articulo:articulos(nombre,codigo_articulo), almacen_origen:almacenes!almacen_origen_id(nombre), almacen_destino:almacenes!almacen_destino_id(nombre), obra:obras(nombre), user:users(nombre)")
        .order("created_at", { ascending: false }).limit(200),
      (supabase.from("articulos") as any).select("id,nombre,codigo_articulo,codigo_barras").eq("activo", true).order("nombre"),
      (supabase.from("almacenes") as any).select("id,nombre,codigo_almacen").eq("activo", true).order("nombre"),
      (supabase.from("obras") as any).select("id,nombre").order("nombre"),
    ]);
    setMovimientos(mR.data || []);
    setArticulos(aR.data || []);
    setAlmacenes(alR.data || []);
    setObras(oR.data || []);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  // Guardar movimiento individual
  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true); setError(null);
    try {
      const payload: any = {
        tipo: tipo === "entrada" ? "entrada" : tipo === "salida" ? "salida" : "ajuste",
        articulo_id: form.articulo_id,
        cantidad: parseFloat(form.cantidad) || 1,
        obra_id: form.obra_id || null,
        observaciones: form.observaciones || null,
        created_by: user?.id,
      };
      if (tipo === "salida" || tipo === "ajuste") payload.almacen_origen_id = form.almacen_origen_id || null;
      if (tipo === "entrada") payload.almacen_destino_id = form.almacen_destino_id || null;

      const { error: err } = await (supabase.from("movimientos_almacen") as any).insert(payload);
      if (err) throw err;
      setModalOpen(false); fetchData();
    } catch (err: any) {
      setError(err.message);
      await logAuditErrorClient({ modulo: "almacen.movimientos", entidad: "movimientos_almacen", accion: "crear", descripcion: "Error al registrar movimiento", errorDetalle: err.message });
    } finally { setSaving(false); }
  };

  // Scan: buscar artículo por código de barras
  const handleScan = (e: React.FormEvent) => {
    e.preventDefault();
    if (!scanInput.trim()) return;
    setScanNotFound(false);
    const found = articulos.find((a) =>
      a.codigo_barras === scanInput.trim() ||
      a.codigo_articulo === scanInput.trim()
    );
    if (!found) { setScanNotFound(true); setScanInput(""); return; }
    setScanItems((prev) => {
      const existing = prev.find((i) => i.articulo.id === found.id);
      if (existing) return prev.map((i) => i.articulo.id === found.id ? { ...i, cantidad: i.cantidad + 1 } : i);
      return [...prev, { articulo: found, cantidad: 1, codigoBarras: scanInput.trim() }];
    });
    setScanInput("");
    setTimeout(() => scanRef.current?.focus(), 50);
  };

  // Confirmar traslado masivo
  const handleTraslado = async () => {
    if (!trasladoForm.almacen_origen_id || !trasladoForm.almacen_destino_id || scanItems.length === 0) return;
    setTrasladoSaving(true);
    try {
      for (const item of scanItems) {
        await (supabase.rpc as any)("registrar_traslado", {
          p_articulo_id: item.articulo.id,
          p_almacen_origen_id: trasladoForm.almacen_origen_id,
          p_almacen_destino_id: trasladoForm.almacen_destino_id,
          p_cantidad: item.cantidad,
          p_obra_id: trasladoForm.obra_id || null,
        });
      }
      setTrasladoOpen(false);
      setScanItems([]);
      setTrasladoForm({ almacen_origen_id: "", almacen_destino_id: "", obra_id: "" });
      fetchData();
    } catch (err: any) {
      setError(err.message);
    } finally { setTrasladoSaving(false); }
  };

  const filtered = movimientos.filter((m) =>
    !search ||
    m.articulo?.nombre?.toLowerCase().includes(search.toLowerCase()) ||
    m.articulo?.codigo_articulo?.toLowerCase().includes(search.toLowerCase()) ||
    m.tipo?.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="flex items-center justify-between mb-6 flex-wrap gap-3">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <ArrowLeftRight className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">Movimientos</h1>
              <p className="text-sm text-surface-500">Entradas, salidas, ajustes y traslados</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <button onClick={() => { setTrasladoOpen(true); setScanItems([]); setScanInput(""); }}
              className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200">
              <Scan className="w-4 h-4" />Traslado masivo
            </button>
            <button onClick={() => { setModalOpen(true); setTipo("entrada"); setForm({ articulo_id: "", almacen_origen_id: "", almacen_destino_id: "", cantidad: "1", obra_id: "", observaciones: "" }); setError(null); }}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">
              <Plus className="w-4 h-4" />Nuevo movimiento
            </button>
          </div>
        </div>

        <div className="card overflow-hidden">
          <div className="p-3 border-b border-surface-100">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
              <input className="w-full pl-9 pr-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg" placeholder="Buscar por artículo, tipo..." value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
          </div>
          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="w-6 h-6 text-brand-500 animate-spin" /></div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-surface-100 bg-surface-50">
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Fecha</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Tipo</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Artículo</th>
                    <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Cantidad</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden md:table-cell">Almacén</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Obra</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4 hidden lg:table-cell">Usuario</th>
                  </tr>
                </thead>
                <tbody>
                  {filtered.map((m) => {
                    const cfg = TIPO_CONFIG[m.tipo as keyof typeof TIPO_CONFIG];
                    const almacen = m.almacen_destino?.nombre || m.almacen_origen?.nombre || "—";
                    return (
                      <tr key={m.id} className="border-b border-surface-50 hover:bg-surface-50/50">
                        <td className="px-4 py-2.5 text-xs text-surface-500 font-mono whitespace-nowrap">
                          {new Date(m.fecha).toLocaleDateString("es-ES")}
                        </td>
                        <td className="px-4 py-2.5">
                          {cfg && <span className={cn("badge text-[10px]", cfg.color)}>{cfg.label}</span>}
                        </td>
                        <td className="px-4 py-2.5">
                          <div className="font-medium text-surface-900 text-xs">{m.articulo?.nombre || "—"}</div>
                          <div className="text-surface-400 text-[10px] font-mono">{m.articulo?.codigo_articulo}</div>
                        </td>
                        <td className="px-4 py-2.5 text-right font-mono text-sm">{m.cantidad}</td>
                        <td className="px-4 py-2.5 text-xs text-surface-600 hidden md:table-cell">{almacen}</td>
                        <td className="px-4 py-2.5 text-xs text-surface-600 hidden lg:table-cell">{m.obra?.nombre || "—"}</td>
                        <td className="px-4 py-2.5 text-xs text-surface-500 hidden lg:table-cell">{m.user?.nombre || "—"}</td>
                      </tr>
                    );
                  })}
                  {filtered.length === 0 && <tr><td colSpan={7} className="text-center py-12 text-sm text-surface-400">Sin movimientos</td></tr>}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {/* Modal: movimiento individual */}
      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title="Nuevo movimiento" size="md">
        <form onSubmit={handleSave} className="space-y-3">
          <div>
            <label className="block text-xs font-medium text-surface-600 mb-1">Tipo de movimiento</label>
            <div className="flex gap-2">
              {(["entrada","salida","ajuste"] as TipoMov[]).map((t) => {
                const cfg = TIPO_CONFIG[t];
                return (
                  <button key={t} type="button"
                    onClick={() => setTipo(t)}
                    className={cn("flex-1 flex items-center justify-center gap-1.5 py-2 text-xs font-semibold rounded-lg border transition-colors",
                      tipo === t ? "border-brand-500 bg-brand-50 text-brand-700" : "border-surface-200 text-surface-600 hover:bg-surface-50")}>
                    <cfg.icon className="w-3.5 h-3.5" />{cfg.label}
                  </button>
                );
              })}
            </div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Artículo *</label>
            <select required className={ic} value={form.articulo_id} onChange={(e) => setForm({ ...form, articulo_id: e.target.value })}>
              <option value="">Seleccionar artículo...</option>
              {articulos.map((a) => <option key={a.id} value={a.id}>{a.nombre} — {a.codigo_articulo}</option>)}
            </select>
          </div>
          {(tipo === "salida" || tipo === "ajuste") && (
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Almacén origen</label>
              <select className={ic} value={form.almacen_origen_id} onChange={(e) => setForm({ ...form, almacen_origen_id: e.target.value })}>
                <option value="">Sin especificar</option>
                {almacenes.map((a) => <option key={a.id} value={a.id}>{a.nombre}</option>)}
              </select>
            </div>
          )}
          {tipo === "entrada" && (
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Almacén destino</label>
              <select className={ic} value={form.almacen_destino_id} onChange={(e) => setForm({ ...form, almacen_destino_id: e.target.value })}>
                <option value="">Sin especificar</option>
                {almacenes.map((a) => <option key={a.id} value={a.id}>{a.nombre}</option>)}
              </select>
            </div>
          )}
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Cantidad *</label>
              <input required type="number" min="0.001" step="0.001" className={ic} value={form.cantidad} onChange={(e) => setForm({ ...form, cantidad: e.target.value })} />
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Obra (opcional)</label>
              <select className={ic} value={form.obra_id} onChange={(e) => setForm({ ...form, obra_id: e.target.value })}>
                <option value="">Sin obra</option>
                {obras.map((o) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
              </select>
            </div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Observaciones</label>
            <input className={ic} value={form.observaciones} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} />
          </div>
          {error && <p className="text-xs text-red-600">{error}</p>}
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving} className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}Registrar</button>
          </div>
        </form>
      </Modal>

      {/* Modal: traslado masivo con scan */}
      <Modal open={trasladoOpen} onClose={() => setTrasladoOpen(false)} title="Traslado masivo" size="lg">
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Almacén origen *</label>
              <select className={ic} value={trasladoForm.almacen_origen_id} onChange={(e) => setTrasladoForm({ ...trasladoForm, almacen_origen_id: e.target.value })}>
                <option value="">Seleccionar...</option>
                {almacenes.map((a) => <option key={a.id} value={a.id}>{a.nombre}</option>)}
              </select>
            </div>
            <div><label className="block text-xs font-medium text-surface-600 mb-1">Almacén destino *</label>
              <select className={ic} value={trasladoForm.almacen_destino_id} onChange={(e) => setTrasladoForm({ ...trasladoForm, almacen_destino_id: e.target.value })}>
                <option value="">Seleccionar...</option>
                {almacenes.map((a) => <option key={a.id} value={a.id}>{a.nombre}</option>)}
              </select>
            </div>
          </div>
          <div><label className="block text-xs font-medium text-surface-600 mb-1">Obra (opcional)</label>
            <select className={ic} value={trasladoForm.obra_id} onChange={(e) => setTrasladoForm({ ...trasladoForm, obra_id: e.target.value })}>
              <option value="">Sin obra</option>
              {obras.map((o) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
            </select>
          </div>

          <div className="border-t border-surface-100 pt-4">
            <p className="text-xs font-semibold text-surface-600 mb-2">Escanear artículos — apunta la pistola y escanea</p>
            <form onSubmit={handleScan} className="flex gap-2">
              <div className="relative flex-1">
                <Scan className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-400" />
                <input
                  ref={scanRef}
                  autoFocus
                  className={cn(ic, "pl-9", scanNotFound && "border-red-400 bg-red-50")}
                  placeholder="Código de barras..."
                  value={scanInput}
                  onChange={(e) => { setScanInput(e.target.value); setScanNotFound(false); }}
                />
              </div>
              <button type="submit" className="px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600">Añadir</button>
            </form>
            {scanNotFound && <p className="text-xs text-red-600 mt-1">Artículo no encontrado</p>}
          </div>

          {scanItems.length > 0 && (
            <div className="border border-surface-200 rounded-lg overflow-hidden">
              <div className="bg-surface-50 px-3 py-2 text-xs font-semibold text-surface-600">{scanItems.length} artículos en la lista</div>
              <div className="max-h-48 overflow-y-auto">
                {scanItems.map((item, i) => (
                  <div key={i} className="flex items-center gap-3 px-3 py-2 border-b border-surface-50 last:border-0">
                    <Package className="w-4 h-4 text-surface-400 shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="text-xs font-medium text-surface-900 truncate">{item.articulo.nombre}</p>
                      <p className="text-[10px] text-surface-400 font-mono">{item.articulo.codigo_articulo}</p>
                    </div>
                    <div className="flex items-center gap-1">
                      <button onClick={() => setScanItems((prev) => prev.map((s, j) => j === i ? { ...s, cantidad: Math.max(1, s.cantidad - 1) } : s))} className="w-6 h-6 rounded flex items-center justify-center bg-surface-100 hover:bg-surface-200 text-xs font-bold">−</button>
                      <span className="w-8 text-center text-sm font-mono">{item.cantidad}</span>
                      <button onClick={() => setScanItems((prev) => prev.map((s, j) => j === i ? { ...s, cantidad: s.cantidad + 1 } : s))} className="w-6 h-6 rounded flex items-center justify-center bg-surface-100 hover:bg-surface-200 text-xs font-bold">+</button>
                    </div>
                    <button onClick={() => setScanItems((prev) => prev.filter((_, j) => j !== i))} className="p-1 text-surface-300 hover:text-red-500"><X className="w-3.5 h-3.5" /></button>
                  </div>
                ))}
              </div>
            </div>
          )}

          <div className="flex justify-end gap-2">
            <button onClick={() => setTrasladoOpen(false)} className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button
              onClick={handleTraslado}
              disabled={trasladoSaving || scanItems.length === 0 || !trasladoForm.almacen_origen_id || !trasladoForm.almacen_destino_id}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
              {trasladoSaving ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <CheckCircle2 className="w-3.5 h-3.5" />}
              Confirmar traslado ({scanItems.reduce((s, i) => s + i.cantidad, 0)} uds)
            </button>
          </div>
        </div>
      </Modal>
    </AppLayout>
  );
}
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\almacen\movimientos\page.tsx" -ForegroundColor Green

$dst = "src\app\obras\[id]\obra-detail.tsx"
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
  Loader2, Plus, Trash2, CheckCircle2, Clock, ListTodo, Upload,
  File, Image as ImageIcon, Save, MessageSquare, ExternalLink, Pencil,
  FileSignature, Archive, Eye, AlertTriangle, Download
, Package2 } from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils/cn";
import ChecklistPanel from "@/components/obras/ChecklistPanel";

type Tab = "general" | "recursos" | "tareas" | "partes" | "documentos" | "checklists" | "almacen";

export default function ObraDetallePage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { user } = useAuthStore();
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
  const [stockObra, setStockObra] = useState<any[]>([]);
  const [tiposObra, setTiposObra] = useState<any[]>([]);
  const [obraTipos, setObraTipos] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<Tab>("general");
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
    // Stock del almacen de la obra
    try {
      const { data: almacenObraR } = await (supabase.from("almacenes") as any).select("id").eq("obra_id", id).eq("activo", true).maybeSingle();
      if (almacenObraR?.id) {
        const { data: stockR } = await (supabase.from("v_stock_actual") as any).select("*").eq("almacen_id", almacenObraR.id);
        setStockObra(stockR || []);
      }
    } catch { /* tabla almacen puede no existir aun */ }
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
    await (supabase.from("obras") as any).update(update).eq("id", id); fetchData();
  };
  const handleDelete = async () => {
    if (!confirm(`¿Seguro que quieres ELIMINAR la obra "${obra?.nombre}"?\n\nSe borrarán todas las asignaciones, tareas, partes y documentos asociados.\n\nEsta acción no se puede deshacer.`)) return;
    await (supabase.from("obras") as any).delete().eq("id", id);
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
  const handleUploadFile = async (e: React.ChangeEvent<HTMLInputElement>) => { const files = e.target.files; if (!files) return; setUploading(true); for (let i = 0; i < files.length; i++) { const file = files[i]; const path = `obras/${id}/${Date.now()}_${file.name}`; const { error } = await supabase.storage.from("documentos").upload(path, file); if (error) continue; await (supabase.from("documentos") as any).insert({ obra_id: id, nombre_archivo: file.name, tipo: file.type.startsWith("image/") ? "foto" : file.type === "application/pdf" ? "pdf" : "documento", categoria: "general", storage_path: path, tamano: file.size, mime_type: file.type, uploaded_by: user?.id }); } setUploading(false); if (fileInputRef.current) fileInputRef.current.value = ""; fetchData(); };
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
    { id: "almacen", label: "Almacén", icon: Package2, count: stockObra.length },
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
            <select value={obra.estado_obra_id || ""} onChange={(e) => handleChangeEstado(e.target.value)}
              className="px-3 py-1.5 rounded-full text-sm font-medium text-white border-0 cursor-pointer focus:outline-none"
              style={{ backgroundColor: (obra as any).estado_custom?.color || "#6B7280" }}>
              <option value="">Sin estado</option>
              {estados.map((es) => <option key={es.id} value={es.id}>{es.nombre}</option>)}
            </select>
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
                {obsChanged && <button onClick={handleSaveObservaciones} disabled={obsSaving} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{obsSaving ? <Loader2 className="w-3 h-3 animate-spin" /> : <Save className="w-3 h-3" />}Guardar</button>}
              </div>
              <textarea value={observaciones} onChange={(e) => { setObservaciones(e.target.value); setObsChanged(true); }} rows={4} placeholder="Notas, comentarios..." className={ic + " resize-y"} />
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
              <button onClick={() => fileInputRef.current?.click()} disabled={uploading} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{uploading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Upload className="w-3.5 h-3.5" />}Subir</button>
              <input ref={fileInputRef} type="file" multiple accept="image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt" className="hidden" onChange={handleUploadFile} />
            </div>
            {documentos.length === 0 ? <div className="text-center py-12 border-2 border-dashed border-surface-200 rounded-xl"><Upload className="w-8 h-8 text-surface-300 mx-auto mb-2" /><p className="text-sm text-surface-500">Sin documentos</p></div> : (
              <div className="space-y-2">{documentos.map((doc) => {
                const isImage = doc.tipo === "foto"; const isPdf = doc.tipo === "pdf";
                return (
                  <div key={doc.id} className="flex items-center gap-3 p-3 bg-surface-50 rounded-lg border border-surface-100 group hover:border-surface-200">
                    <div className={cn("w-10 h-10 rounded-lg flex items-center justify-center shrink-0", isImage ? "bg-violet-100 text-violet-600" : isPdf ? "bg-red-100 text-red-600" : "bg-blue-100 text-blue-600")}>{isImage ? <ImageIcon className="w-5 h-5" /> : isPdf ? <FileText className="w-5 h-5" /> : <File className="w-5 h-5" />}</div>
                    <div className="flex-1 min-w-0 cursor-pointer" onClick={() => handleOpenDoc(doc)}><p className="text-sm font-medium text-surface-900 hover:text-brand-600 truncate">{doc.nombre_archivo}</p><p className="text-[11px] text-surface-400">{formatBytes(doc.tamano)}</p></div>
                    <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100"><button onClick={() => handleOpenDoc(doc)} className="p-1.5 rounded-md text-surface-400 hover:text-brand-600"><ExternalLink className="w-4 h-4" /></button><button onClick={() => handleDeleteDoc(doc)} className="p-1.5 rounded-md text-surface-400 hover:text-red-600"><Trash2 className="w-4 h-4" /></button></div>
                  </div>
                );
              })}</div>
            )}
          </div>
        )}

        {tab === "checklists" && (
          <ChecklistPanel obraId={id} rrhh={rrhh.map((r) => ({ id: r.id, nombre: r.nombre }))} />
        )}

        {tab === "almacen" && (
          <div className="space-y-4">
            {stockObra.length === 0 ? (
              <div className="card p-8 text-center text-sm text-surface-400">
                <p>Esta obra no tiene un almacen asociado o no tiene stock registrado.</p>
                <p className="text-xs mt-2">Ve a Almacen → Almacenes y crea un almacen con esta obra para empezar a registrar stock.</p>
              </div>
            ) : (
              <div className="card overflow-hidden">
                <div className="px-4 py-3 border-b border-surface-100 bg-surface-50">
                  <h3 className="text-sm font-semibold text-surface-700">Stock del almacen de la obra</h3>
                </div>
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-surface-100">
                      <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Articulo</th>
                      <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Cod. articulo</th>
                      <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Tipo</th>
                      <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Stock</th>
                      <th className="text-right text-[10px] font-semibold text-surface-400 uppercase py-2 px-4">Min.</th>
                    </tr>
                  </thead>
                  <tbody>
                    {stockObra.map((s: any, i: number) => (
                      <tr key={i} className={cn("border-b border-surface-50", s.bajo_minimo ? "bg-red-50/50" : "hover:bg-surface-50/50")}>
                        <td className="px-4 py-2.5 font-medium text-surface-900">{s.nombre}</td>
                        <td className="px-4 py-2.5 font-mono text-xs text-surface-500">{s.codigo_articulo}</td>
                        <td className="px-4 py-2.5 text-xs text-surface-500">{s.tipo}</td>
                        <td className={cn("px-4 py-2.5 text-right font-mono text-sm font-semibold", s.bajo_minimo ? "text-red-600" : "text-surface-900")}>
                          {Number(s.stock_qty).toFixed(2)} {s.unidad}
                        </td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs text-surface-400">{Number(s.stock_minimo_def).toFixed(2)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
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
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\obras\[id]\obra-detail.tsx" -ForegroundColor Green

$dst = "src\app\api\almacen\alertas-email\route.ts"
$content = @'
/**
 * src/app/api/almacen/alertas-email/route.ts
 *
 * Envía email de alertas de stock bajo y caducidad usando Resend,
 * siguiendo el mismo patrón que /api/partes/email.
 * Se llama desde el cron nocturno o manualmente desde Configuracion.
 */
import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(req: NextRequest) {
  const RESEND_API_KEY = process.env.RESEND_API_KEY;
  if (!RESEND_API_KEY) return NextResponse.json({ error: "RESEND_API_KEY no configurada" }, { status: 500 });

  try {
    const admin = createAdminClient();

    // Leer configuracion de alertas
    const { data: settingsRow } = await admin.from("app_settings").select("value").eq("key", "almacen_alertas").single();
    const config = (settingsRow?.value as any) || {};
    const emails: string[] = config.emails || [];
    const asunto: string = config.asunto || "Alertas de almacen - ObrasPlan";
    const diasAviso: number = config.dias_aviso_caducidad || 30;

    if (!emails.length) return NextResponse.json({ sent: false, reason: "Sin emails configurados" });

    // Obtener alertas
    const { data: alertas } = await admin.from("v_alertas_almacen" as any).select("*");
    if (!alertas || alertas.length === 0) return NextResponse.json({ sent: false, reason: "Sin alertas activas" });

    const stockBajo = alertas.filter((a: any) => a.alerta_stock);
    const caducados = alertas.filter((a: any) => a.alerta_caducidad === "caducado");
    const caducaProto = alertas.filter((a: any) => a.alerta_caducidad === "caduca_pronto");

    const rowHTML = (a: any) => `
      <tr>
        <td style="padding:6px 12px;border-bottom:1px solid #f0f0f0">${a.nombre}</td>
        <td style="padding:6px 12px;border-bottom:1px solid #f0f0f0">${a.almacen_nombre}</td>
        <td style="padding:6px 12px;border-bottom:1px solid #f0f0f0;text-align:right">${Number(a.stock_qty ?? 0).toFixed(2)}</td>
        <td style="padding:6px 12px;border-bottom:1px solid #f0f0f0;text-align:right">${Number(a.stock_minimo_def ?? 0).toFixed(2)}</td>
        <td style="padding:6px 12px;border-bottom:1px solid #f0f0f0">${a.caducidad ? new Date(a.caducidad).toLocaleDateString("es-ES") : "—"}</td>
      </tr>`;

    const section = (title: string, rows: any[], headerColor: string) => rows.length === 0 ? "" : `
      <h3 style="color:${headerColor};margin:24px 0 8px">${title} (${rows.length})</h3>
      <table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-size:13px">
        <thead><tr style="background:#f8f8f8">
          <th style="padding:6px 12px;text-align:left;color:#666">Artículo</th>
          <th style="padding:6px 12px;text-align:left;color:#666">Almacén</th>
          <th style="padding:6px 12px;text-align:right;color:#666">Stock actual</th>
          <th style="padding:6px 12px;text-align:right;color:#666">Stock mínimo</th>
          <th style="padding:6px 12px;text-align:left;color:#666">Caducidad</th>
        </tr></thead>
        <tbody>${rows.map(rowHTML).join("")}</tbody>
      </table>`;

    const html = `
      <div style="font-family:Arial,sans-serif;max-width:700px;margin:0 auto;color:#333">
        <div style="background:#DC2626;padding:20px 24px;border-radius:8px 8px 0 0">
          <h1 style="color:#fff;margin:0;font-size:20px">Alertas de almacén</h1>
          <p style="color:rgba(255,255,255,.8);margin:4px 0 0;font-size:13px">${new Date().toLocaleDateString("es-ES", { weekday: "long", year: "numeric", month: "long", day: "numeric" })}</p>
        </div>
        <div style="padding:24px;background:#fff;border:1px solid #eee;border-top:none;border-radius:0 0 8px 8px">
          ${section("🔴 Stock por debajo del mínimo", stockBajo, "#DC2626")}
          ${section("⚫ Artículos caducados", caducados, "#7c3aed")}
          ${section("🟡 Artículos que caducan en ${diasAviso} días", caducaProto, "#d97706")}
          <p style="margin-top:24px;font-size:12px;color:#999">Generado automáticamente por ObrasPlan</p>
        </div>
      </div>`;

    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${RESEND_API_KEY}` },
      body: JSON.stringify({ from: "ObrasPlan Almacén <onboarding@resend.dev>", to: emails, subject: asunto, html }),
    });

    if (!emailRes.ok) {
      const err = await emailRes.text();
      return NextResponse.json({ error: "Error Resend: " + err }, { status: 400 });
    }

    // Registrar en audit
    await admin.from("audit_log").insert({
      accion: "crear", entidad: "almacen_alertas", modulo: "almacen",
      descripcion: `Email de alertas enviado a ${emails.length} destinatarios (${alertas.length} alertas)`,
      resultado: "exito", origen: "api_route",
    } as any);

    return NextResponse.json({ sent: true, alertas: alertas.length, destinatarios: emails.length });
  } catch (err: any) {
    return NextResponse.json({ error: err.message }, { status: 500 });
  }
}
'@
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\api\almacen\alertas-email\route.ts" -ForegroundColor Green

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
  { id: "almacen_almacenes", label: "Almacén - Almacenes" },
  { id: "almacen_proveedores", label: "Almacén - Proveedores" },
  { id: "almacen_movimientos", label: "Almacén - Movimientos" },
  { id: "maestros_rrhh", label: "RRHH" },
  { id: "maestros_vehiculos", label: "Vehículos" },
  { id: "maestros_clientes", label: "Clientes" },
  { id: "maestros_estados", label: "Estados obra" },
  { id: "maestros_tipos_trabajo", label: "Tipos trabajo" },
  { id: "maestros_tipos_obra", label: "Tipos de obra" },
  { id: "apps_georadar", label: "Georadar" },
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
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\configuracion\page.tsx" -ForegroundColor Green

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
];

const almacen = [
  { name: "Artículos", href: "/almacen/articulos", icon: Package, screen: "almacen_articulos" },
  { name: "Almacenes", href: "/almacen/almacenes", icon: Warehouse, screen: "almacen_almacenes" },
  { name: "Proveedores", href: "/almacen/proveedores", icon: Users2, screen: "almacen_proveedores" },
  { name: "Movimientos", href: "/almacen/movimientos", icon: ArrowLeftRight, screen: "almacen_movimientos" },
];

const maestros = [
  { name: "Recursos Humanos", href: "/maestros/recursos-humanos", icon: Users, screen: "maestros_rrhh" },
  { name: "Vehículos", href: "/maestros/vehiculos", icon: Truck, screen: "maestros_vehiculos" },
  { name: "Clientes", href: "/maestros/clientes", icon: Contact, screen: "maestros_clientes" },
  { name: "Estados de Obra", href: "/maestros/estados-obra", icon: Tag, screen: "maestros_estados" },
  { name: "Tipos de Trabajo", href: "/maestros/tipos-trabajo", icon: Hammer, screen: "maestros_tipos_trabajo" },
  { name: "Tipos de Obra", href: "/maestros/tipos-obra", icon: Building2, screen: "maestros_tipos_obra" },
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
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\components\layout\Sidebar.tsx" -ForegroundColor Green

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
  const [loaded, setLoaded] = useState(false);

  const isAdmin = user?.role === "admin";

  useEffect(() => {
    if (!user?.id) return;
    if (isAdmin) { setLoaded(true); return; }

    // Fetch permissions for user's role
    const fetchPermisos = async () => {
      // Get user's rol_id
      const { data: userData } = await supabase.from("users").select("rol_id").eq("id", user.id).single();
      if (userData?.rol_id) {
        const { data } = await supabase.from("rol_permisos").select("*").eq("rol_id", userData.rol_id);
        setPermisos(data || []);
      }
      setLoaded(true);
    };

    fetchPermisos();
  }, [user?.id, isAdmin]);

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
      "apps_georadar",
      "almacen_articulos", "almacen_almacenes", "almacen_proveedores", "almacen_movimientos",
      "maestros_rrhh", "maestros_vehiculos",
      "maestros_clientes", "maestros_estados", "maestros_tipos_trabajo", "maestros_tipos_obra",
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
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\hooks\usePermissions.ts" -ForegroundColor Green

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
  "/maestros/recursos-humanos": "maestros_rrhh",
  "/almacen/articulos": "almacen_articulos",
  "/almacen/almacenes": "almacen_almacenes",
  "/almacen/proveedores": "almacen_proveedores",
  "/almacen/movimientos": "almacen_movimientos",
  "/maestros/vehiculos": "maestros_vehiculos",
  "/maestros/clientes": "maestros_clientes",
  "/maestros/estados-obra": "maestros_estados",
  "/maestros/tipos-trabajo": "maestros_tipos_trabajo",
  "/maestros/tipos-obra": "maestros_tipos_obra",
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
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\hooks\useRouteGuard.ts" -ForegroundColor Green

Write-Host ""
Write-Host "==> Verificacion" -ForegroundColor Cyan
$checks = @(
    "src\app\almacen\movimientos\page.tsx",
    "src\app\api\almacen\alertas-email\route.ts"
)
$allOk = $true
foreach ($f in $checks) {
    if (Test-Path $f) { Write-Host ("    OK: " + $f) -ForegroundColor Green }
    else { Write-Host ("    FALTA: " + $f) -ForegroundColor Red; $allOk = $false }
}
$sidebarOk = Select-String -Path "src\components\layout\Sidebar.tsx" -Pattern "almacen_movimientos" -Quiet
if ($sidebarOk) { Write-Host "    OK: Sidebar tiene almacen_movimientos" -ForegroundColor Green }
else { Write-Host "    ERROR: Sidebar sin almacen_movimientos" -ForegroundColor Red; $allOk = $false }
$planOk = Select-String -Path "src\app\planificacion\page.tsx" -Pattern "maquinaria" -Quiet
if (-not $planOk) { Write-Host "    OK: Planificador sin maquinaria" -ForegroundColor Green }
else { Write-Host "    AVISO: Planificador aun menciona maquinaria (revisar)" -ForegroundColor Yellow }

Write-Host ""
if ($allOk) {
    Write-Host "Todo correcto. Ejecutar tambien:" -ForegroundColor Green
    Write-Host "  031_almacen_fase3.sql en Supabase SQL Editor"
    Write-Host ""
    Write-Host '  git add -A'
    Write-Host '  git commit -m "feat: almacen fase 3 - movimientos, dashboard alertas, stock por obra, config email"'
    Write-Host '  git push'
} else { Write-Host "Algo fallo." -ForegroundColor Red }
