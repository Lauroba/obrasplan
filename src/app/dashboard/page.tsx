"use client";

import AppLayout from "@/components/layout/AppLayout";
import { useAuthStore } from "@/hooks/useAuth";
import { createClient } from "@/lib/supabase/client";
import { useEffect, useState, useCallback } from "react";
import type { RecursoTipo } from "@/lib/types/database";
import {
  CheckCircle2, Clock, AlertTriangle, ListTodo,
  Building2, ClipboardList, Users, Wrench, Truck, Calendar,
  Loader2, ChevronLeft, ChevronRight
} from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils/cn";

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
  const [partesSinFirma, setPartesSinFirma] = useState<any[]>([]);
  const [checklistItems, setChecklistItems] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [taskFilter, setTaskFilter] = useState<"mine" | "all">("mine");

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
      const [tareasR, obrasR, partesR, asigR, rrhhR, maqR, vehR, revisadosR] = await Promise.all([
        supabase.from("tareas").select("*, obra:obras(nombre, color), tipo_tarea:tipo_tarea(nombre), recurso_asignado:recursos_humanos(nombre)").eq("estado", "pendiente").order("fecha_limite", { ascending: true, nullsFirst: false }),
        supabase.from("obras").select("*, estado_custom:estados_obra(*)").eq("archivada", false).order("nombre"),
        supabase.from("partes_diarios").select("*, obra:obras(nombre, color), creator:users!partes_diarios_created_by_fkey(nombre)").eq("estado", "pendiente").order("fecha", { ascending: false }).limit(10),
        supabase.from("asignaciones").select("*"),
        supabase.from("recursos_humanos").select("id, nombre").eq("activo", true),
        supabase.from("maquinaria").select("id, nombre"),
        supabase.from("vehiculos").select("id, nombre"),
        supabase.from("conflictos_revisados").select("recurso_tipo, recurso_id, fecha"),
      ]);

      setTareas((tareasR.data || []) as any[]);
      setObrasActivas((obrasR.data || []) as any[]);
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
      (maqR.data || []).forEach((r: any) => nameMap[`maquinaria|${r.id}`] = r.nombre);
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
      setLoading(false);
    };
    fetchAll();
  }, [user]);

  const marcarRevisado = async (c: ConflictInfo) => {
    const supabase = createClient();
    setConflicts((prev) => prev.filter((x) => !(x.recursoId === c.recursoId && x.recursoTipo === c.recursoTipo && x.date === c.date)));
    await supabase.from("conflictos_revisados").insert({
      recurso_tipo: c.recursoTipo, recurso_id: c.recursoId, fecha: c.date, revisado_por: user?.id,
    } as any);
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
  const tipoIcon: Record<RecursoTipo, typeof Users> = { humano: Users, maquinaria: Wrench, vehiculo: Truck, material: ListTodo };
  const getDateColor = (f: string | null) => { if (!f) return ""; const d = (new Date(f).getTime() - Date.now()) / 86400000; if (d < 0) return "text-red-600 bg-red-50"; if (d < 3) return "text-amber-600 bg-amber-50"; return "text-surface-600"; };
  const greeting = () => { const h = new Date().getHours(); if (h < 12) return "Buenos días"; if (h < 20) return "Buenas tardes"; return "Buenas noches"; };

  const filteredTareas = taskFilter === "mine" ? tareas.filter((t) => t.asignado_a === user?.recurso_id) : tareas;
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
            <div className="flex items-center justify-between mb-3 shrink-0">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><Building2 className="w-4 h-4 text-brand-600" />Obras activas</h2>
              <span className="text-xs text-surface-400">{obrasActivas.length}</span>
            </div>
            <div className="space-y-1.5 overflow-y-auto flex-1">
              {obrasActivas.map((o) => (
                <Link key={o.id} href={`/obras/${o.id}`} className="flex items-center gap-3 p-2 rounded-lg hover:bg-surface-50 border border-surface-100 group">
                  <div className="w-2 h-8 rounded-full shrink-0" style={{ backgroundColor: o.color || "#DC2626" }} />
                  <div className="flex-1 min-w-0"><p className="text-xs font-medium text-surface-900 group-hover:text-brand-600 truncate">{o.nombre}</p><p className="text-[10px] text-surface-400 truncate">{o.ubicacion || ""}</p></div>
                  {o.estado_custom && <span className="text-[9px] px-2 py-0.5 rounded-full text-white shrink-0" style={{ backgroundColor: o.estado_custom.color }}>{o.estado_custom.nombre}</span>}
                </Link>
              ))}
              {obrasActivas.length === 0 && <p className="text-sm text-surface-400 text-center py-4">Sin obras</p>}
            </div>
          </div>

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
