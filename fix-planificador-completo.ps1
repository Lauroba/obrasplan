#Requires -Version 5.1
# fix-planificador-completo.ps1
# 1. Planificador: asignaciones filtradas por rango de fechas (sin limite numerico)
# 2. Sidebar: restaura Contactos LEYNA y Etiquetas que desaparecieron
# IMPORTANTE: ejecutar fix_rls_y_paginacion.sql en Supabase PRIMERO

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
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
  CalendarRange, ChevronLeft, ChevronRight, Users, Truck,
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
const SIN_ASIGNAR_ID = "SIN_ASIGNAR"; // ID virtual para la fila especial, nunca existe en BD
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

// ---- Fila SIN ASIGNAR (virtual, siempre primera, no reordenable) ----
function SinAsignarRow({ dateStrs, days, assignGrid, resInfo, onRemove, dw, isWeekend, isToday }: {
  dateStrs: string[]; days: Date[];
  assignGrid: Record<string, Asignacion[]>; resInfo: Record<string, ResourceInfo>;
  onRemove: (id: string) => void; dw: number;
  isWeekend: (d: Date) => boolean; isToday: (d: Date) => boolean;
}) {
  return (
    <div className="flex border-b-2 border-amber-200 bg-amber-50/40">
      <div className="shrink-0 flex items-center gap-2 border-r border-amber-200 px-3"
        style={{ width: LABEL_W, minWidth: LABEL_W }}>
        <div className="w-2 h-2 rounded-full bg-amber-400 shrink-0" />
        <span className="text-[11px] font-bold text-amber-700 uppercase tracking-wide">Sin asignar</span>
      </div>
      {dateStrs.map((ds, i) => {
        const day = days[i];
        const cellAssigns = assignGrid[`${SIN_ASIGNAR_ID}|${ds}`] || [];
        const personas = cellAssigns.filter((a) => a.recurso_tipo === "humano");
        const vehs    = cellAssigns.filter((a) => a.recurso_tipo === "vehiculo");
        return (
          <div key={ds} style={{ width: dw, minWidth: dw }}
            className={cn("border-r border-amber-100 relative",
              isToday(day) ? "bg-brand-50/20" : isWeekend(day) ? "bg-amber-50/60" : "")}>
            <div className="h-full min-h-[44px] flex flex-col items-center justify-center gap-0.5 p-0.5 overflow-hidden">
              {/* RRHH sin asignar ese día */}
              <div className="flex flex-wrap gap-0.5 justify-center">
                {personas.map((a) => {
                  const info = resInfo[`humano|${a.recurso_id}`];
                  return info?.foto_url ? (
                    <img key={a.id} src={info.foto_url} alt={info.nombre}
                      title={`${info.nombre} — sin asignar`}
                      className={cn("rounded-full object-cover ring-1 ring-amber-300", dw > 60 ? "w-6 h-6" : "w-4 h-4")} />
                  ) : (
                    <div key={a.id}
                      title={`${info?.nombre || "?"} — sin asignar`}
                      className={cn("rounded-full bg-violet-100 text-violet-700 flex items-center justify-center font-bold ring-1 ring-amber-300",
                        dw > 60 ? "w-6 h-6 text-[8px]" : "w-4 h-4 text-[6px]")}>
                      {info?.initials || "?"}
                    </div>
                  );
                })}
              </div>
              {/* Vehículos sin asignar ese día */}
              <div className="flex flex-wrap gap-0.5 justify-center">
                {vehs.map((a) => {
                  const info = resInfo[`vehiculo|${a.recurso_id}`];
                  const Icon = TIPO_ICON["vehiculo"] || Users;
                  return info?.foto_url ? (
                    <img key={a.id} src={info.foto_url} alt={info.nombre}
                      title={`${info.nombre} — sin asignar`}
                      className="w-4 h-4 rounded-full object-cover ring-1 ring-amber-300" />
                  ) : (
                    <div key={a.id}
                      title={`${info?.nombre || "?"} — sin asignar`}
                      className="w-4 h-4 rounded-full flex items-center justify-center ring-1 ring-amber-300 bg-teal-100 text-teal-700">
                      <Icon className="w-2 h-2" />
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

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
  const [asignError, setAsignError] = useState<string | null>(null);
  const [manualForm, setManualForm] = useState({ recurso_tipo: "humano" as RecursoTipo, recurso_id: "", fecha_inicio: "", fecha_fin: "" }); // maquinaria y material eliminados del planificador
  const [manualSaving, setManualSaving] = useState(false);
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 8 } }));

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [oR, aR, hR, vR, eR] = await Promise.all([
      supabase.from("obras").select("*, cliente:clientes(*), estado_custom:estados_obra(*)").order("orden_gantt"),
      // Solo cargar asignaciones del rango visible: 4 semanas atras y 8 adelante
      // Escala sin limites numericos arbitrarios
      (() => {
        const rs = new Date(startDate); rs.setDate(rs.getDate() - 28);
        const re = new Date(startDate); re.setDate(re.getDate() + 56);
        const fromDs = `${rs.getFullYear()}-${String(rs.getMonth()+1).padStart(2,"0")}-${String(rs.getDate()).padStart(2,"0")}`;
        const toDs   = `${re.getFullYear()}-${String(re.getMonth()+1).padStart(2,"0")}-${String(re.getDate()).padStart(2,"0")}`;
        return supabase.from("asignaciones").select("*")
          .gte("fecha_fin", fromDs).lte("fecha_inicio", toDs).limit(5000);
      })(),
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

  // Obras reales ordenadas (excluye obras con flags legacy que ya no se usan)
  // Las columnas flag_rrhh_sin_asignar / flag_vehiculo_sin_asignar existen en BD
  // pero se ignoran desde frontend (obsoletas -- la fila SIN ASIGNAR es virtual).
  const conAsig = filteredObras.filter((o) => obrasConAsignacion.has(o.id)).sort(byOrden);
  const aPlanificar = filteredObras.filter((o) => !obrasConAsignacion.has(o.id) && (o as any).estado_custom?.nombre?.toLowerCase().includes("planificar")).sort(byOrden);
  const resto = filteredObras.filter((o) => !obrasConAsignacion.has(o.id) && !(o as any).estado_custom?.nombre?.toLowerCase().includes("planificar")).sort(byOrden);
  const sortedObrasAll = [...conAsig, ...aPlanificar, ...resto];
  const sortedObras = obraSearch ? sortedObrasAll.filter((o) => o.nombre.toLowerCase().includes(obraSearch.toLowerCase())) : sortedObrasAll;
  // obraIds para SortableContext: excluye SIN_ASIGNAR_ID (esa fila es inmune al reorder)
  const obraIds = sortedObras.map((o) => o.id);

  // displayGrid: copia del assignGrid real + asignaciones virtuales de la fila SIN ASIGNAR.
  // La fila SIN ASIGNAR siempre se calcula, independientemente de cualquier flag de obra.
  const displayGrid = useMemo(() => {
    const g: Record<string, Asignacion[]> = {};
    Object.entries(assignGrid).forEach(([k, v]) => { g[k] = [...v]; });

    const weekDays = dateStrs.filter((ds) => { const d = new Date(ds + "T12:00:00"); const day = d.getDay(); return day >= 1 && day <= 5; });

    // RRHH sin asignar ese dia -> aparecen en la fila SIN_ASIGNAR_ID
    rrhh.filter((r) => (r as any).asignable !== false).forEach((person) => {
      weekDays.forEach((ds) => {
        const isAssigned = asignaciones.some((a) => a.recurso_tipo === "humano" && a.recurso_id === person.id && a.fecha_inicio <= ds && a.fecha_fin >= ds);
        if (!isAssigned) {
          const k = `${SIN_ASIGNAR_ID}|${ds}`;
          if (!g[k]) g[k] = [];
          g[k].push({ id: `v-rrhh-${person.id}-${ds}`, obra_id: SIN_ASIGNAR_ID, recurso_tipo: "humano", recurso_id: person.id, fecha_inicio: ds, fecha_fin: ds } as any);
        }
      });
    });

    // Vehiculos sin asignar ese dia -> aparecen en la fila SIN_ASIGNAR_ID
    vehList.filter((r) => (r as any).asignable !== false).forEach((veh) => {
      weekDays.forEach((ds) => {
        const isAssigned = asignaciones.some((a) => a.recurso_tipo === "vehiculo" && a.recurso_id === veh.id && a.fecha_inicio <= ds && a.fecha_fin >= ds);
        if (!isAssigned) {
          const k = `${SIN_ASIGNAR_ID}|${ds}`;
          if (!g[k]) g[k] = [];
          g[k].push({ id: `v-veh-${veh.id}-${ds}`, obra_id: SIN_ASIGNAR_ID, recurso_tipo: "vehiculo", recurso_id: veh.id, fecha_inicio: ds, fecha_fin: ds } as any);
        }
      });
    });

    return g;
  }, [assignGrid, rrhh, vehList, dateStrs, asignaciones]);

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
      // Drop sobre celda SIN_ASIGNAR -> eliminar la asignacion real si existe
      if (obraId === SIN_ASIGNAR_ID) {
        const realAssig = asignaciones.find((a) => a.recurso_tipo === tipo && a.recurso_id === recursoId && a.fecha_inicio <= dateStr && a.fecha_fin >= dateStr);
        if (realAssig) { await supabase.from("asignaciones").delete().eq("id", realAssig.id); fetchData(); }
        return;
      }
      const existing = assignGrid[`${obraId}|${dateStr}`]?.find((a) => a.recurso_tipo === tipo && a.recurso_id === recursoId);
      if (existing) return;
      const { error: insErr } = await supabase.from("asignaciones").insert({ obra_id: obraId, recurso_tipo: tipo as RecursoTipo, recurso_id: recursoId, fecha_inicio: dateStr, fecha_fin: dateStr });
      if (insErr) { setAsignError(`Error al asignar: ${insErr.message} (code: ${insErr.code})`); return; }
      fetchData(); return;
    }

    // ---- Vista RRHH: drop obra on person cell ----
    if (aid.startsWith("panel-obra|") && oid.startsWith("cell-")) {
      const obraId = aid.replace("panel-obra|", "");
      const [recursoId, dateStr] = oid.replace("cell-", "").split("|");
      if (!obraId || !recursoId || !dateStr) return;
      const existing = assignGrid[`${obraId}|${dateStr}`]?.find((a) => a.recurso_tipo === "humano" && a.recurso_id === recursoId);
      if (existing) return;
      const { error: insErr2 } = await supabase.from("asignaciones").insert({ obra_id: obraId, recurso_tipo: "humano", recurso_id: recursoId, fecha_inicio: dateStr, fecha_fin: dateStr });
      if (insErr2) { setAsignError(`Error al asignar: ${insErr2.message} (code: ${insErr2.code})`); return; }
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
      // SIN_ASIGNAR_ID es inmune al reorder
      if (aid === SIN_ASIGNAR_ID || oid === SIN_ASIGNAR_ID) return;
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
      // Saltar fines de semana (0=domingo, 6=sabado)
      if (d.getDay() === 0 || d.getDay() === 6) continue;
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
    if (inserts.length > 0) {
      const { error: insErr3 } = await supabase.from("asignaciones").insert(inserts);
      if (insErr3) { setAsignError(`Error al asignar: ${insErr3.message} (code: ${insErr3.code})`); setManualSaving(false); return; }
    }
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
                    <>
                      {/* Fila SIN ASIGNAR: siempre la primera, virtual, no reordenable */}
                      <SinAsignarRow
                        dateStrs={dateStrs} days={days}
                        assignGrid={displayGrid} resInfo={resInfo}
                        onRemove={handleRemove} dw={dw}
                        isWeekend={isWeekendFn} isToday={isTodayFn}
                      />
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
                    </>
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
                    {([{ id: "all" as ResourceFilter, label: "Todo" }, { id: "humano" as ResourceFilter, icon: Users }, { id: "vehiculo" as ResourceFilter, icon: Truck }]).map((f) => (
                      <button key={f.id} onClick={() => setResourceFilter(f.id)} className={cn("px-1.5 py-0.5 text-[10px] font-medium rounded flex items-center gap-0.5", resourceFilter === f.id ? "bg-brand-50 text-brand-600" : "text-surface-500 hover:bg-surface-100")}>{f.icon && <f.icon className="w-3 h-3" />}{f.label || ""}</button>
                    ))}
                  </div>
                ) : (
                  <div className="flex border-b border-surface-200 px-1 py-1 gap-0.5 flex-wrap">
                    {([{ id: "all" as PanelFilter, label: "Todo" }, { id: "obra" as PanelFilter, icon: Building2 }, { id: "vehiculo" as PanelFilter, icon: Truck }]).map((f) => (
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

        {/* Error de asignación — visible para diagnosticar */}
        {asignError && (
          <div className="fixed bottom-4 left-1/2 -translate-x-1/2 z-50 max-w-lg w-full mx-4">
            <div className="bg-red-50 border border-red-300 rounded-xl px-4 py-3 shadow-xl flex items-start gap-3">
              <div className="flex-1 text-sm text-red-700 font-mono break-all">{asignError}</div>
              <button onClick={() => setAsignError(null)} className="text-red-400 hover:text-red-600 shrink-0 mt-0.5">✕</button>
            </div>
          </div>
        )}
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
                <option value="humano">Persona</option><option value="vehiculo">Vehículo</option>
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
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\planificacion\page.tsx" -ForegroundColor Green

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
  { name: "Tipos de artículo", href: "/almacen/tipos-articulo", icon: Tag, screen: "almacen_tipos_articulo" },
  { name: "Almacenes", href: "/almacen/almacenes", icon: Warehouse, screen: "almacen_almacenes" },
  { name: "Proveedores", href: "/almacen/proveedores", icon: Users2, screen: "almacen_proveedores" },
  { name: "Movimientos", href: "/almacen/movimientos", icon: ArrowLeftRight, screen: "almacen_movimientos" },
  { name: "Etiquetas", href: "/almacen/etiquetas", icon: Tag, screen: "almacen_etiquetas" },
];

const maestros = [
  { name: "Recursos Humanos", href: "/maestros/recursos-humanos", icon: Users, screen: "maestros_rrhh" },
  { name: "Vehículos", href: "/maestros/vehiculos", icon: Truck, screen: "maestros_vehiculos" },
  { name: "Clientes", href: "/maestros/clientes", icon: Contact, screen: "maestros_clientes" },
  { name: "Estados de Obra", href: "/maestros/estados-obra", icon: Tag, screen: "maestros_estados" },
  { name: "Tipos de Trabajo", href: "/maestros/tipos-trabajo", icon: Hammer, screen: "maestros_tipos_trabajo" },
  { name: "Tipos de Obra", href: "/maestros/tipos-obra", icon: Building2, screen: "maestros_tipos_obra" },
  { name: "Contactos LEYNA", href: "/maestros/contactos-leyna", icon: Users2, screen: "maestros_contactos_leyna" },
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
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\components\layout\Sidebar.tsx" -ForegroundColor Green

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
  "/almacen/tipos-articulo": "almacen_tipos_articulo",
  "/almacen/almacenes": "almacen_almacenes",
  "/almacen/proveedores": "almacen_proveedores",
  "/almacen/movimientos": "almacen_movimientos",
  "/almacen/etiquetas": "almacen_etiquetas",
  "/maestros/vehiculos": "maestros_vehiculos",
  "/maestros/clientes": "maestros_clientes",
  "/maestros/estados-obra": "maestros_estados",
  "/maestros/tipos-trabajo": "maestros_tipos_trabajo",
  "/maestros/tipos-obra": "maestros_tipos_obra",
  "/maestros/contactos-leyna": "maestros_contactos_leyna",
  "/almacen/etiquetas": "almacen_etiquetas",
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
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\hooks\useRouteGuard.ts" -ForegroundColor Green

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
  const [isAdminFromRole, setIsAdminFromRole] = useState(false);
  const [loaded, setLoaded] = useState(false);

  // Admin si el campo role = "admin" O si el rol vinculado tiene is_admin = true
  const isAdmin = user?.role === "admin" || isAdminFromRole;

  useEffect(() => {
    if (!user?.id) return;

    const fetchPermisos = async () => {
      // Leer rol_id y role actualizados desde la BD (no solo desde el store cacheado)
      const { data: userData } = await supabase
        .from("users")
        .select("rol_id, role")
        .eq("id", user.id)
        .single();

      if (!userData) { setLoaded(true); return; }

      // Comprobar si el rol vinculado es admin aunque users.role no diga "admin"
      if (userData.rol_id) {
        const { data: rolData } = await supabase
          .from("roles")
          .select("is_admin")
          .eq("id", userData.rol_id)
          .single();
        if (rolData?.is_admin) {
          setIsAdminFromRole(true);
          setLoaded(true);
          return;
        }
        // Si no es admin, cargar permisos granulares
        const { data } = await supabase
          .from("rol_permisos")
          .select("*")
          .eq("rol_id", userData.rol_id);
        setPermisos(data || []);
      }

      // Fallback: users.role = "admin" ya lo cubre isAdmin arriba
      setLoaded(true);
    };

    fetchPermisos();
  }, [user?.id]);

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
      "almacen_articulos", "almacen_tipos_articulo", "almacen_almacenes", "almacen_proveedores", "almacen_movimientos", "almacen_etiquetas",
      "maestros_rrhh", "maestros_vehiculos",
      "maestros_clientes", "maestros_estados", "maestros_tipos_trabajo", "maestros_tipos_obra", "maestros_contactos_leyna", "almacen_etiquetas",
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
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\hooks\usePermissions.ts" -ForegroundColor Green

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
  { id: "almacen_tipos_articulo", label: "Almacén - Tipos de artículo" },
  { id: "almacen_almacenes", label: "Almacén - Almacenes" },
  { id: "almacen_proveedores", label: "Almacén - Proveedores" },
  { id: "almacen_movimientos", label: "Almacén - Movimientos" },
  { id: "almacen_etiquetas", label: "Almacén - Diseñador de etiquetas" },
  { id: "maestros_rrhh", label: "RRHH" },
  { id: "maestros_vehiculos", label: "Vehículos" },
  { id: "maestros_clientes", label: "Clientes" },
  { id: "maestros_estados", label: "Estados obra" },
  { id: "maestros_tipos_trabajo", label: "Tipos trabajo" },
  { id: "maestros_tipos_obra", label: "Tipos de obra" },
  { id: "maestros_contactos_leyna", label: "Contactos LEYNA" },
  { id: "almacen_etiquetas", label: "Almacén - Etiquetas" },
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
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: src\app\configuracion\page.tsx" -ForegroundColor Green

Write-Host ""
Write-Host "==> Verificando" -ForegroundColor Cyan
$ok1 = Select-String -Path "src\components\layout\Sidebar.tsx" -Pattern "contactos-leyna" -Quiet
$ok2 = Select-String -Path "src\app\planificacion\page.tsx" -Pattern "gte.*fecha_fin" -Quiet
if ($ok1) { Write-Host "    OK: Contactos LEYNA en Sidebar" -ForegroundColor Green } else { Write-Host "    ERROR Sidebar" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: filtro de fechas en planificador" -ForegroundColor Green } else { Write-Host "    ERROR planificador" -ForegroundColor Red }
Write-Host ""
Write-Host '  git add -A'
Write-Host '  git commit -m "fix: RLS asignaciones, menu restaurado, planificador por rango fechas"'
Write-Host '  git push'
