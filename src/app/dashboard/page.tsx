"use client";

import AppLayout from "@/components/layout/AppLayout";
import { useAuthStore } from "@/hooks/useAuth";
import { createClient } from "@/lib/supabase/client";
import { useEffect, useState } from "react";
import type { Tarea, Asignacion, RecursoTipo } from "@/lib/types/database";
import {
  Building2, Users, Wrench, Truck, ClipboardList, Calendar, CheckCircle2,
  Clock, AlertTriangle, ArrowRight, ListTodo
} from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils/cn";
import ResourceAvatar from "@/components/shared/ResourceAvatar";

interface DashboardStats {
  obrasActivas: number; obrasPlanificadas: number; trabajadores: number;
  maquinas: number; vehiculos: number; partesPendientes: number;
}

interface ConflictInfo {
  recursoName: string; recursoTipo: RecursoTipo; date: string;
  obras: string[];
}

const CONFLICT_TYPES: RecursoTipo[] = ["humano", "maquinaria", "vehiculo"];

export default function DashboardPage() {
  const { user } = useAuthStore();
  const [stats, setStats] = useState<DashboardStats>({ obrasActivas: 0, obrasPlanificadas: 0, trabajadores: 0, maquinas: 0, vehiculos: 0, partesPendientes: 0 });
  const [tareas, setTareas] = useState<any[]>([]);
  const [conflicts, setConflicts] = useState<ConflictInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [taskFilter, setTaskFilter] = useState<"mine" | "all">("mine");

  useEffect(() => {
    const fetchAll = async () => {
      const supabase = createClient();

      const [obras, rrhhC, maqC, vehC, partesC, tareasR, asigR, rrhhR, maqR, vehR, obrasR] = await Promise.all([
        supabase.from("obras").select("estado"),
        supabase.from("recursos_humanos").select("id", { count: "exact", head: true }).eq("activo", true),
        supabase.from("maquinaria").select("id", { count: "exact", head: true }).eq("activo", true),
        supabase.from("vehiculos").select("id", { count: "exact", head: true }).eq("activo", true),
        supabase.from("partes_diarios").select("id", { count: "exact", head: true }).eq("estado", "pendiente"),
        // My pending tasks: join with recurso assigned to me via user's recurso_id
        supabase.from("tareas").select("*, obra:obras(nombre, color), tipo_tarea:tipo_tarea(nombre), recurso_asignado:recursos_humanos(nombre, foto_url)").eq("estado", "pendiente").order("fecha_limite", { ascending: true, nullsFirst: false }),
        supabase.from("asignaciones").select("*"),
        supabase.from("recursos_humanos").select("id, nombre"),
        supabase.from("maquinaria").select("id, nombre"),
        supabase.from("vehiculos").select("id, nombre"),
        supabase.from("obras").select("id, nombre"),
      ]);

      const obrasData = (obras.data || []) as any[];
      setStats({
        obrasActivas: obrasData.filter((o: any) => o.estado === "en_curso").length,
        obrasPlanificadas: obrasData.filter((o: any) => o.estado === "planificada").length,
        trabajadores: rrhhC.count || 0, maquinas: maqC.count || 0, vehiculos: vehC.count || 0,
        partesPendientes: partesC.count || 0,
      });

      // Filter tasks assigned to current user's recurso_id
      const allTareas = (tareasR.data || []) as any[];
      setTareas(allTareas);

      // Compute conflicts
      const nameMap: Record<string, string> = {};
      (rrhhR.data || []).forEach((r: any) => nameMap[`humano|${r.id}`] = r.nombre);
      (maqR.data || []).forEach((r: any) => nameMap[`maquinaria|${r.id}`] = r.nombre);
      (vehR.data || []).forEach((r: any) => nameMap[`vehiculo|${r.id}`] = r.nombre);
      const obraNameMap: Record<string, string> = {};
      (obrasR.data || []).forEach((o: any) => obraNameMap[o.id] = o.nombre);

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

      const conflictList: ConflictInfo[] = [];
      Object.entries(resourceDayMap).forEach(([key, entries]) => {
        const uniqueObras = Array.from(new Set(entries.map((e) => e.obraId)));
        if (uniqueObras.length > 1) {
          const [tipo, recursoId, date] = key.split("|");
          conflictList.push({
            recursoName: nameMap[`${tipo}|${recursoId}`] || "?",
            recursoTipo: tipo as RecursoTipo,
            date, obras: uniqueObras.map((id) => obraNameMap[id] || "?"),
          });
        }
      });
      // Deduplicate by resource+date
      const seen = new Set<string>();
      setConflicts(conflictList.filter((c) => {
        const key = `${c.recursoName}|${c.date}`;
        if (seen.has(key)) return false;
        seen.add(key); return true;
      }).slice(0, 15));

      setLoading(false);
    };
    fetchAll();
  }, [user]);

  const statCards = [
    { label: "Obras activas", value: stats.obrasActivas, icon: Building2, color: "text-brand-600", bg: "bg-brand-50", href: "/obras" },
    { label: "Planificadas", value: stats.obrasPlanificadas, icon: Calendar, color: "text-blue-600", bg: "bg-blue-50", href: "/planificacion" },
    { label: "Trabajadores", value: stats.trabajadores, icon: Users, color: "text-violet-600", bg: "bg-violet-50", href: "/maestros/recursos-humanos" },
    { label: "Maquinaria", value: stats.maquinas, icon: Wrench, color: "text-amber-600", bg: "bg-amber-50", href: "/maestros/maquinaria" },
    { label: "Vehículos", value: stats.vehiculos, icon: Truck, color: "text-teal-600", bg: "bg-teal-50", href: "/maestros/vehiculos" },
    { label: "Partes pend.", value: stats.partesPendientes, icon: ClipboardList, color: "text-orange-600", bg: "bg-orange-50", href: "/partes/aprobar" },
  ];

  const prioColors: Record<string, string> = { alta: "bg-red-100 text-red-700", media: "bg-amber-100 text-amber-700", baja: "bg-blue-100 text-blue-700" };
  const tipoIcon: Record<RecursoTipo, typeof Users> = { humano: Users, maquinaria: Wrench, vehiculo: Truck, material: ListTodo };

  const getDateColor = (fecha: string | null) => {
    if (!fecha) return "";
    const diff = (new Date(fecha).getTime() - Date.now()) / 86400000;
    if (diff < 0) return "text-red-600 bg-red-50";
    if (diff < 3) return "text-amber-600 bg-amber-50";
    return "text-surface-600";
  };

  const greeting = () => { const h = new Date().getHours(); if (h < 12) return "Buenos días"; if (h < 20) return "Buenas tardes"; return "Buenas noches"; };

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="mb-8">
          <h1 className="text-2xl font-display font-bold text-surface-900">{greeting()}, {user?.nombre?.split(" ")[0]}</h1>
          <p className="text-surface-500 mt-1">Aquí tienes el resumen de hoy, {new Date().toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "long" })}</p>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4 mb-8">
          {statCards.map((card) => (
            <Link key={card.label} href={card.href} className="card p-4 hover:shadow-md hover:border-surface-300 transition-all group">
              <div className={`w-9 h-9 rounded-lg ${card.bg} flex items-center justify-center mb-3`}><card.icon className={`w-5 h-5 ${card.color}`} /></div>
              <p className="text-2xl font-display font-bold text-surface-900">{loading ? "—" : card.value}</p>
              <p className="text-xs text-surface-500 mt-0.5">{card.label}</p>
            </Link>
          ))}
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* My pending tasks */}
          <div className="card p-6 flex flex-col max-h-[500px]">
            <div className="flex items-center justify-between mb-4 shrink-0">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><ListTodo className="w-4 h-4 text-brand-600" />Tareas pendientes</h2>
              <div className="flex items-center gap-2">
                <div className="flex bg-surface-100 rounded p-0.5">
                  <button onClick={() => setTaskFilter("mine")} className={cn("px-2 py-0.5 text-[10px] font-medium rounded transition-colors", taskFilter === "mine" ? "bg-white text-surface-900 shadow-sm" : "text-surface-500")}>Mis tareas</button>
                  <button onClick={() => setTaskFilter("all")} className={cn("px-2 py-0.5 text-[10px] font-medium rounded transition-colors", taskFilter === "all" ? "bg-white text-surface-900 shadow-sm" : "text-surface-500")}>Todas</button>
                </div>
                <span className="text-xs text-surface-400">{(taskFilter === "mine" ? tareas.filter((t) => t.asignado_a === user?.recurso_id) : tareas).length}</span>
              </div>
            </div>
            {(() => {
              const filtered = taskFilter === "mine" ? tareas.filter((t) => t.asignado_a === user?.recurso_id) : tareas;
              return filtered.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-8 text-center">
                <CheckCircle2 className="w-10 h-10 text-emerald-400 mb-2" />
                <p className="text-sm font-medium text-surface-700">Sin tareas pendientes</p>
                <p className="text-xs text-surface-400 mt-1">¡Todo al día!</p>
              </div>
            ) : (
              <div className="space-y-2 overflow-y-auto flex-1">
                {filtered.map((t) => (
                  <Link key={t.id} href={`/obras/${t.obra_id}`} className="flex items-start gap-3 p-3 rounded-lg hover:bg-surface-50 transition-colors border border-surface-100">
                    <div className="w-2 h-2 rounded-full mt-2 shrink-0" style={{ backgroundColor: t.obra?.color || "#DC2626" }} />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm text-surface-900 truncate">{t.descripcion}</p>
                      <div className="flex items-center gap-2 mt-1 flex-wrap">
                        <span className="text-[10px] text-surface-400">{t.obra?.nombre}</span>
                        <span className={cn("badge text-[10px]", prioColors[t.prioridad])}>{t.prioridad}</span>
                        {t.recurso_asignado?.nombre && <ResourceAvatar nombre={t.recurso_asignado.nombre} foto_url={t.recurso_asignado.foto_url} tipo="humano" size="xs" className="text-[10px]" />}
                        {t.fecha_limite && <span className={cn("text-[10px] px-1.5 py-0.5 rounded", getDateColor(t.fecha_limite))}><Clock className="w-3 h-3 inline mr-0.5" />{new Date(t.fecha_limite).toLocaleDateString("es-ES")}</span>}
                      </div>
                    </div>
                    <ArrowRight className="w-4 h-4 text-surface-300 mt-1" />
                  </Link>
                ))}
              </div>
            );
            })()}
          </div>

          {/* Conflicts */}
          <div className="card p-6">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-sm font-semibold text-surface-900 flex items-center gap-2"><AlertTriangle className="w-4 h-4 text-amber-500" />Alertas y conflictos</h2>
              {conflicts.length > 0 && <span className="text-xs text-red-500 font-medium">{conflicts.length} conflicto{conflicts.length !== 1 ? "s" : ""}</span>}
            </div>
            {conflicts.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-8 text-center">
                <div className="w-12 h-12 rounded-full bg-emerald-50 flex items-center justify-center mb-3">
                  <CheckCircle2 className="w-6 h-6 text-emerald-500" />
                </div>
                <p className="text-sm font-medium text-surface-700">Sin conflictos detectados</p>
                <p className="text-xs text-surface-400 mt-1">Todos los recursos asignados correctamente</p>
              </div>
            ) : (
              <div className="space-y-2 max-h-[400px] overflow-y-auto">
                {conflicts.map((c, i) => {
                  const Icon = tipoIcon[c.recursoTipo];
                  return (
                    <div key={i} className="flex items-start gap-3 p-3 bg-red-50 rounded-lg border border-red-100">
                      <div className="w-8 h-8 rounded-full bg-red-100 flex items-center justify-center shrink-0"><Icon className="w-4 h-4 text-red-600" /></div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-red-800">{c.recursoName}</p>
                        <p className="text-[11px] text-red-600 mt-0.5">
                          {new Date(c.date).toLocaleDateString("es-ES", { weekday: "short", day: "numeric", month: "short" })} — asignado en: {c.obras.join(" y ")}
                        </p>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      </div>
    </AppLayout>
  );
}
