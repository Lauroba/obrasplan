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
import { usePermissions } from "@/hooks/usePermissions";

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
const ObraCell = memo(function ObraCell({ obraId, dateStr, assignments, resInfo, onRemove, dw, conflictResources }: {
  obraId: string; dateStr: string; assignments: Asignacion[]; resInfo: Record<string, ResourceInfo>;
  onRemove: (id: string) => void; dw: number; conflictResources: Set<string>;
}) {
  const cid = `cell-${obraId}|${dateStr}`;
  const { setNodeRef, isOver } = useDroppable({ id: cid });
  const personas = assignments.filter((a) => a.recurso_tipo === "humano");
  const otros = assignments.filter((a) => a.recurso_tipo !== "humano");
  return (
    <div ref={setNodeRef} className={cn("h-full border-r border-surface-100 flex flex-col items-center justify-center gap-0.5 p-0.5 transition-colors",
      isOver ? "bg-brand-100 ring-2 ring-brand-400 ring-inset" : "")}
      style={{ width: dw, minWidth: dw }}>
      <div className="flex flex-wrap gap-0.5 justify-center">
        {personas.map((a) => {
          const rkey = `${a.recurso_tipo}|${a.recurso_id}`;
          const info = resInfo[rkey];
          const isConflict = conflictResources.has(`${rkey}|${dateStr}`);
          return info?.foto_url ? (
            <img key={a.id} src={info.foto_url} alt={info.nombre}
              title={`${info.nombre}${isConflict ? " ⚠ Asignado a otra obra este día" : ""}\nClic para quitar`}
              className={cn("rounded-full object-cover cursor-pointer", dw > 60 ? "w-6 h-6" : "w-4 h-4",
                isConflict ? "ring-2 ring-red-500 ring-offset-1" : "hover:ring-2 hover:ring-red-400")}
              onClick={() => onRemove(a.id)} />
          ) : (
            <div key={a.id}
              title={`${info?.nombre || "?"}${isConflict ? " ⚠ Asignado a otra obra este día" : ""}\nClic para quitar`}
              className={cn("rounded-full flex items-center justify-center font-bold cursor-pointer",
                dw > 60 ? "w-6 h-6 text-[8px]" : "w-4 h-4 text-[6px]",
                isConflict
                  ? "bg-red-500 text-white ring-2 ring-red-700 ring-offset-1"
                  : "bg-violet-200 text-violet-800 hover:ring-2 hover:ring-red-400")}
              onClick={() => onRemove(a.id)}>{info?.initials || "?"}</div>
          );
        })}
      </div>
      <div className="flex flex-wrap gap-0.5 justify-center">
        {otros.map((a) => {
          const rkey = `${a.recurso_tipo}|${a.recurso_id}`;
          const info = resInfo[rkey];
          const Icon = TIPO_ICON[a.recurso_tipo];
          const isConflict = conflictResources.has(`${rkey}|${dateStr}`);
          return info?.foto_url ? (
            <img key={a.id} src={info.foto_url} alt={info.nombre}
              title={`${info.nombre}${isConflict ? " ⚠ Asignado a otra obra este día" : ""}\nClic para quitar`}
              className={cn("w-4 h-4 rounded-full object-cover cursor-pointer",
                isConflict ? "ring-2 ring-red-500 ring-offset-1" : "hover:ring-2 hover:ring-red-400")}
              onClick={() => onRemove(a.id)} />
          ) : (
            <div key={a.id}
              title={`${info?.nombre || "?"}${isConflict ? " ⚠ Asignado a otra obra este día" : ""}\nClic para quitar`}
              className={cn("w-4 h-4 rounded-full flex items-center justify-center cursor-pointer",
                isConflict
                  ? "bg-red-500 ring-2 ring-red-700 ring-offset-1"
                  : cn(TIPO_BG[a.recurso_tipo], "hover:ring-2 hover:ring-red-400"))}
              onClick={() => onRemove(a.id)}>
              <Icon className="w-2 h-2 text-white" />
            </div>
          );
        })}
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
function ObraRow({ obra, dateStrs, days, assignGrid, obraRange, resInfo, conflictResources, onRemove, onArchive, onAddManual, onChangeEstado, estados, dw, isWeekend, isToday, notas, onNoteSaved }: {
  obra: Obra; dateStrs: string[]; days: Date[]; assignGrid: Record<string, Asignacion[]>;
  obraRange?: { min: string; max: string }; resInfo: Record<string, ResourceInfo>;
  conflictResources: Set<string>; onRemove: (id: string) => void; onArchive: (id: string, v: boolean) => void;
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
                onRemove={onRemove} dw={dw} conflictResources={conflictResources} />
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
  const { isAdmin: isAdminPlan, canDo: canDoPlan } = usePermissions();
  const puedeAsignar = isAdminPlan || canDoPlan("planificacion", "asignar");

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

  // conflictResources: Set de "recurso_tipo|recurso_id" para los recursos
  // que están asignados a MÁS DE UNA obra en el rango de días visible.
  // Solo estos recursos se muestran en rojo — la celda obra×día NO cambia de color.
  const conflictResources = useMemo(() => {
    const rdm: Record<string, Set<string>> = {};
    asignaciones.forEach((a) => {
      if (!CONFLICT_TYPES.includes(a.recurso_tipo)) return;
      const s = new Date(a.fecha_inicio); const e = new Date(a.fecha_fin);
      for (let d = new Date(s); d <= e; d.setDate(d.getDate() + 1)) {
        const ds = toDS(d);
        const key = `${a.recurso_tipo}|${a.recurso_id}|${ds}`;
        if (!rdm[key]) rdm[key] = new Set();
        rdm[key].add(a.obra_id);
      }
    });
    const resources = new Set<string>();
    Object.entries(rdm).forEach(([key, obraIds]) => {
      if (obraIds.size > 1) {
        // Guardar "tipo|id|fecha" para saber exactamente qué día hay conflicto
        resources.add(key);
      }
    });
    return resources;
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
    setActiveDrag(null);
    if (!e.over) return;
    const aid = String(e.active.id); const oid = String(e.over.id);

    // ---- Vista Obras: drop resource on obra cell ----
    if (aid.startsWith("res-") && oid.startsWith("cell-")) {
      if (!puedeAsignar) return;
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
      if (!puedeAsignar) return;
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
      if (!puedeAsignar) return;
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
            {conflictResources.size > 0 && <span className="flex items-center gap-1 px-2 py-0.5 text-[10px] font-medium text-red-700 bg-red-50 rounded-lg"><AlertTriangle className="w-3 h-3" />{conflictResources.size} conflicto{conflictResources.size > 1 ? "s" : ""}</span>}
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
                      {puedeAsignar && <button onClick={() => setManualModal({ obraId: obra.id, obraName: obra.nombre })} className="flex items-center gap-1 text-[10px] font-medium text-brand-600"><Plus className="w-3 h-3" />Asignar</button>}
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
              {conflictResources.size > 0 && <span className="flex items-center gap-1 px-2 py-1 text-[11px] font-medium text-red-700 bg-red-50 rounded-lg"><AlertTriangle className="w-3 h-3" />{conflictResources.size} conflicto{conflictResources.size > 1 ? "s" : ""}</span>}
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
                            conflictResources={conflictResources} onRemove={handleRemove} onArchive={handleArchive}
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