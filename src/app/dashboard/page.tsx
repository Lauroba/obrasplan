"use client";

import AppLayout from "@/components/layout/AppLayout";
import { useAuthStore } from "@/hooks/useAuth";
import { createClient } from "@/lib/supabase/client";
import { useEffect, useState } from "react";
import type { RecursoTipo } from "@/lib/types/database";
import {
  CheckCircle2, Clock, AlertTriangle, ArrowRight, ListTodo,
  Building2, ClipboardList, Users, Wrench, Truck, Calendar, FileSignature, Loader2
} from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils/cn";

interface ConflictInfo { recursoName: string; recursoTipo: RecursoTipo; date: string; obras: string[] }
const CONFLICT_TYPES: RecursoTipo[] = ["humano", "maquinaria", "vehiculo"];

export default function DashboardPage() {
  const { user } = useAuthStore();
  const [tareas, setTareas] = useState<any[]>([]);
  const [conflicts, setConflicts] = useState<ConflictInfo[]>([]);
  const [obrasActivas, setObrasActivas] = useState<any[]>([]);
  const [partesSinFirma, setPartesSinFirma] = useState<any[]>([]);
  const [manana, setManana] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [taskFilter, setTaskFilter] = useState<"mine" | "all">("mine");

  useEffect(() => {
    const fetchAll = async () => {
      const supabase = createClient();
      const tomorrow = new Date(); tomorrow.setDate(tomorrow.getDate() + 1);
      const tomorrowStr = tomorrow.toISOString().split("T")[0];

      const [tareasR, obrasR, partesR, asigR, rrhhR, maqR, vehR] = await Promise.all([
        supabase.from("tareas").select("*, obra:obras(nombre, color), tipo_tarea:tipo_tarea(nombre)").eq("estado", "pendiente").order("fecha_limite", { ascending: true, nullsFirst: false }),
        supabase.from("obras").select("*, estado_custom:estados_obra(nombre, color)").eq("archivada", false).order("nombre"),
        supabase.from("partes_diarios").select("*, obra:obras(nombre, color), creator:users!partes_diarios_created_by_fkey(nombre)").eq("estado", "pendiente").order("fecha", { ascending: false }).limit(10),
        supabase.from("asignaciones").select("*"),
        supabase.from("recursos_humanos").select("id, nombre"),
        supabase.from("maquinaria").select("id, nombre"),
        supabase.from("vehiculos").select("id, nombre"),
      ]);

      setTareas((tareasR.data || []) as any[]);
      setObrasActivas((obrasR.data || []) as any[]);
      setPartesSinFirma((partesR.data || []) as any[]);

      // Tomorrow assignments
      const nameMap: Record<string, string> = {};
      (rrhhR.data || []).forEach((r: any) => nameMap[`humano|${r.id}`] = r.nombre);
      const obraNameMap: Record<string, any> = {};
      (obrasR.data || []).forEach((o: any) => obraNameMap[o.id] = o);

      const tomorrowAssigs: { nombre: string; obras: { nombre: string; color: string }[] }[] = [];
      const personObras: Record<string, Set<string>> = {};
      (asigR.data || []).forEach((a: any) => {
        if (a.recurso_tipo !== "humano") return;
        if (a.fecha_inicio <= tomorrowStr && a.fecha_fin >= tomorrowStr) {
          if (!personObras[a.recurso_id]) personObras[a.recurso_id] = new Set();
          personObras[a.recurso_id].add(a.obra_id);
        }
      });
      Object.entries(personObras).forEach(([personId, obraIds]) => {
        const nombre = nameMap[`humano|${personId}`] || "?";
        const obras = Array.from(obraIds).map((oid) => ({ nombre: obraNameMap[oid]?.nombre || "?", color: obraNameMap[oid]?.color || "#999" }));
        tomorrowAssigs.push({ nombre, obras });
      });
      tomorrowAssigs.sort((a, b) => a.nombre.localeCompare(b.nombre));
      setManana(tomorrowAssigs);

      // Conflicts
      const resourceDayMap: Record<string, { obraId: string }[]> = {};
      (asigR.data || []).forEach((a: any) => {
        if (!CONFLICT_TYPES.includes(a.recurso_tipo)) return;
        const s = new Date(a.fecha_inicio); const e = new Date(a.fecha_fin);
        for (let d = new Date(s); d <= e; d.setDate(d.getDate() + 1)) {
          const ds = d.toISOString().split("T")[0];
          const key = `${a.recurso_tipo}|${a.recurso_id}|${ds}`;
          if (!resourceDayMap[key]) resourceDayMap[key] = [];
          resourceDayMap[key].push({ obraId: a.obra_id });
        }
      });
      (maqR.data || []).forEach((r: any) => nameMap[`maquinaria|${r.id}`] = r.nombre);
      (vehR.data || []).forEach((r: any) => nameMap[`vehiculo|${r.id}`] = r.nombre);

      const conflictList: ConflictInfo[] = [];
      const seen = new Set<string>();
      Object.entries(resourceDayMap).forEach(([key, entries]) => {
        const uniqueObras = Array.from(new Set(entries.map((e) => e.obraId)));
        if (uniqueObras.length > 1) {
          const [tipo, recursoId, date] = key.split("|");
          const skey = `${recursoId}|${date}`;
          if (seen.has(skey)) return;
          seen.add(skey);
          conflictList.push({
            recursoName: nameMap[`${tipo}|${recursoId}`] || "?",
            recursoTipo: tipo as RecursoTipo,
            date, obras: uniqueObras.map((id) => obraNameMap[id]?.nombre || "?"),
          });
        }
      });
      setConflicts(conflictList.slice(0, 10));
      setLoading(false);
    };
    fetchAll();
  }, [user]);

  const prioColors: Record<string, string> = { alta: "bg-red-100 text-red-700", media: "bg-amber-100 text-amber-700", baja: "bg-blue-100 text-blue-700" };
  const tipoIcon: Record<RecursoTipo, typeof Users> = { humano: Users, maquinaria: Wrench, vehiculo: Truck, material: ListTodo };
  const getDateColor = (f: string | null) => { if (!f) return ""; const d = (new Date(f).getTime() - Date.now()) / 86400000; if (d < 0) return "text-red-600 bg-red-50"; if (d < 3) return "text-amber-600 bg-amber-50"; return "text-surface-600"; };
  const greeting = () => { const h = new Date().getHours(); if (h < 12) return "Buenos días"; if (h < 20) return "Buenas tardes"; return "Buenas noches"; };

  const filteredTareas = taskFilter === "mine" ? tareas.filter((t) => t.asignado_a === user?.recurso_id) : tareas;

  if (loading) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="mb-6">
          <h1 className="text-2xl font-display font-bold text-surface-900">{greeting()}, {user?.nombre?.split(" ")[0]}</h1>
          <p className="text-surface-500 mt-1">{new Date().toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "long" })}</p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Mis tareas pendientes */}
          <div className="card p-5 flex flex-col max-h-[420px]">
            <div className="flex items-center justify-between mb-3 shrink-0">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><ListTodo className="w-4 h-4 text-brand-600" />Tareas pendientes</h2>
              <div className="flex items-center gap-2">
                <div className="flex bg-surface-100 rounded p-0.5">
                  <button onClick={() => setTaskFilter("mine")} className={cn("px-2 py-0.5 text-[10px] font-medium rounded", taskFilter === "mine" ? "bg-white text-surface-900 shadow-sm" : "text-surface-500")}>Mías</button>
                  <button onClick={() => setTaskFilter("all")} className={cn("px-2 py-0.5 text-[10px] font-medium rounded", taskFilter === "all" ? "bg-white text-surface-900 shadow-sm" : "text-surface-500")}>Todas</button>
                </div>
                <span className="text-xs text-surface-400">{filteredTareas.length}</span>
              </div>
            </div>
            {filteredTareas.length === 0 ? (
              <div className="flex-1 flex flex-col items-center justify-center text-center py-4"><CheckCircle2 className="w-8 h-8 text-emerald-400 mb-2" /><p className="text-sm text-surface-500">Sin tareas pendientes</p></div>
            ) : (
              <div className="space-y-1.5 overflow-y-auto flex-1">
                {filteredTareas.slice(0, 15).map((t) => (
                  <Link key={t.id} href={`/obras/${t.obra_id}`} className="flex items-start gap-2.5 p-2.5 rounded-lg hover:bg-surface-50 border border-surface-100 transition-colors">
                    <div className="w-2 h-2 rounded-full mt-1.5 shrink-0" style={{ backgroundColor: t.obra?.color || "#DC2626" }} />
                    <div className="flex-1 min-w-0">
                      <p className="text-xs font-medium text-surface-900 truncate">{t.descripcion}</p>
                      <div className="flex items-center gap-2 mt-0.5">
                        <span className="text-[10px] text-surface-400">{t.obra?.nombre}</span>
                        <span className={cn("badge text-[9px]", prioColors[t.prioridad])}>{t.prioridad}</span>
                        {t.fecha_limite && <span className={cn("text-[9px] px-1 py-0.5 rounded", getDateColor(t.fecha_limite))}>{new Date(t.fecha_limite).toLocaleDateString("es-ES", { day: "numeric", month: "short" })}</span>}
                      </div>
                    </div>
                  </Link>
                ))}
              </div>
            )}
          </div>

          {/* Conflictos */}
          <div className="card p-5 flex flex-col max-h-[420px]">
            <div className="flex items-center justify-between mb-3 shrink-0">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><AlertTriangle className="w-4 h-4 text-amber-500" />Conflictos</h2>
              {conflicts.length > 0 && <span className="text-xs text-red-500 font-medium">{conflicts.length}</span>}
            </div>
            {conflicts.length === 0 ? (
              <div className="flex-1 flex flex-col items-center justify-center text-center py-4"><CheckCircle2 className="w-8 h-8 text-emerald-400 mb-2" /><p className="text-sm text-surface-500">Sin conflictos</p></div>
            ) : (
              <div className="space-y-1.5 overflow-y-auto flex-1">
                {conflicts.map((c, i) => {
                  const Icon = tipoIcon[c.recursoTipo];
                  return (
                    <div key={i} className="flex items-start gap-2.5 p-2.5 bg-red-50 rounded-lg border border-red-100">
                      <Icon className="w-4 h-4 text-red-500 mt-0.5 shrink-0" />
                      <div className="min-w-0">
                        <p className="text-xs font-medium text-red-800">{c.recursoName}</p>
                        <p className="text-[10px] text-red-600">{new Date(c.date).toLocaleDateString("es-ES", { weekday: "short", day: "numeric", month: "short" })} — {c.obras.join(" y ")}</p>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Obras activas */}
          <div className="card p-5 flex flex-col max-h-[420px]">
            <div className="flex items-center justify-between mb-3 shrink-0">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><Building2 className="w-4 h-4 text-brand-600" />Obras activas</h2>
              <span className="text-xs text-surface-400">{obrasActivas.length}</span>
            </div>
            <div className="space-y-1.5 overflow-y-auto flex-1">
              {obrasActivas.map((o) => (
                <Link key={o.id} href={`/obras/${o.id}`} className="flex items-center gap-3 p-2.5 rounded-lg hover:bg-surface-50 border border-surface-100 transition-colors group">
                  <div className="w-2 h-8 rounded-full shrink-0" style={{ backgroundColor: o.color || "#DC2626" }} />
                  <div className="flex-1 min-w-0">
                    <p className="text-xs font-medium text-surface-900 group-hover:text-brand-600 truncate">{o.nombre}</p>
                    <p className="text-[10px] text-surface-400 truncate">{o.ubicacion || ""}</p>
                  </div>
                  {o.estado_custom && (
                    <span className="text-[9px] px-2 py-0.5 rounded-full text-white shrink-0" style={{ backgroundColor: o.estado_custom.color }}>{o.estado_custom.nombre}</span>
                  )}
                </Link>
              ))}
              {obrasActivas.length === 0 && <p className="text-sm text-surface-400 text-center py-4">Sin obras activas</p>}
            </div>
          </div>

          {/* Partes pendientes de firmar */}
          <div className="card p-5 flex flex-col max-h-[420px]">
            <div className="flex items-center justify-between mb-3 shrink-0">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><ClipboardList className="w-4 h-4 text-orange-500" />Partes sin firmar</h2>
              <span className="text-xs text-surface-400">{partesSinFirma.length}</span>
            </div>
            {partesSinFirma.length === 0 ? (
              <div className="flex-1 flex flex-col items-center justify-center text-center py-4"><CheckCircle2 className="w-8 h-8 text-emerald-400 mb-2" /><p className="text-sm text-surface-500">Todos firmados</p></div>
            ) : (
              <div className="space-y-1.5 overflow-y-auto flex-1">
                {partesSinFirma.map((p) => (
                  <Link key={p.id} href={`/partes/${p.id}`} className="flex items-center gap-3 p-2.5 rounded-lg hover:bg-surface-50 border border-surface-100 transition-colors group">
                    <div className="w-1.5 h-8 rounded-full shrink-0" style={{ backgroundColor: p.obra?.color || "#D4D4D4" }} />
                    <div className="flex-1 min-w-0">
                      <p className="text-xs font-medium text-surface-900 group-hover:text-brand-600">{p.creator?.nombre || "?"} — {p.obra?.nombre || "Sin obra"}</p>
                      <p className="text-[10px] text-surface-400">{new Date(p.fecha).toLocaleDateString("es-ES", { day: "numeric", month: "short" })}</p>
                    </div>
                    <div className="flex gap-1 shrink-0">
                      {!p.firma_data && <span className="text-[9px] text-amber-600 bg-amber-50 px-1.5 py-0.5 rounded">Resp.</span>}
                      {!p.firma_cliente && <span className="text-[9px] text-blue-600 bg-blue-50 px-1.5 py-0.5 rounded">Cliente</span>}
                    </div>
                  </Link>
                ))}
              </div>
            )}
          </div>

          {/* Mañana - Quién trabaja */}
          <div className="card p-5 lg:col-span-2 flex flex-col max-h-[350px]">
            <div className="flex items-center justify-between mb-3 shrink-0">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><Calendar className="w-4 h-4 text-violet-500" />Mañana — {new Date(Date.now() + 86400000).toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "long" })}</h2>
              <span className="text-xs text-surface-400">{manana.length} personas</span>
            </div>
            {manana.length === 0 ? (
              <p className="text-sm text-surface-400 text-center py-6">Sin asignaciones para mañana</p>
            ) : (
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2 overflow-y-auto flex-1">
                {manana.map((m, i) => (
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
            )}
          </div>
        </div>
      </div>
    </AppLayout>
  );
}
