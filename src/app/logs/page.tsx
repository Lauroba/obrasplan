"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import type { AuditLog } from "@/lib/types/database";
import {
  ScrollText, Loader2, ChevronLeft, ChevronRight, Search, X,
  Plus, Pencil, Trash2, LogIn, Eye, ArrowRight, AlertTriangle, CheckCircle2,
  Check, ChevronDown,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";

const PAGE_SIZE = 30;

const ACCION_LABELS: Record<string, { label: string; color: string; icon: typeof Plus }> = {
  crear: { label: "Crear", color: "bg-emerald-100 text-emerald-700", icon: Plus },
  editar: { label: "Editar", color: "bg-blue-100 text-blue-700", icon: Pencil },
  eliminar: { label: "Eliminar", color: "bg-red-100 text-red-700", icon: Trash2 },
  aprobar: { label: "Aprobar", color: "bg-violet-100 text-violet-700", icon: Eye },
  rechazar: { label: "Rechazar", color: "bg-orange-100 text-orange-700", icon: X },
  login: { label: "Login", color: "bg-amber-100 text-amber-700", icon: LogIn },
  logout: { label: "Logout", color: "bg-surface-100 text-surface-700", icon: LogIn },
};

// NOTA: lista ampliada en esta entrega para cubrir entidades que ya
// generaban (o ahora generan, tras la migración 026) entradas de auditoría
// pero no tenían etiqueta legible — aparecían como el nombre crudo de la
// tabla. Ver migración 026_audit_complete_fix.sql para el detalle de qué
// tablas se añadieron al sistema de auditoría en esta entrega.
const ENTIDAD_LABELS: Record<string, string> = {
  obras: "Obra",
  obra_fases: "Fase de obra",
  asignaciones: "Asignación",
  partes_diarios: "Parte diario",
  parte_trabajadores: "Parte · Trabajador",
  parte_maquinaria: "Parte · Maquinaria",
  parte_vehiculos: "Parte · Vehículo",
  parte_materiales: "Parte · Material",
  clientes: "Cliente",
  recursos_humanos: "Recurso humano",
  maquinaria: "Maquinaria",
  vehiculos: "Vehículo",
  materiales: "Material",
  tareas: "Tarea",
  documentos: "Documento",
  parte_lineas: "Línea de parte",
  parte_audios: "Audio de parte",
  tipos_obra: "Tipo de obra",
  tipos_trabajo: "Tipo de trabajo",
  estados_obra: "Estado de obra",
  users: "Usuario",
  configuracion: "Configuración",
  session: "Sesión",
};

const RESULTADO_LABELS: Record<string, { label: string; color: string; icon: typeof CheckCircle2 }> = {
  exito: { label: "Éxito", color: "bg-emerald-100 text-emerald-700", icon: CheckCircle2 },
  error: { label: "Error", color: "bg-red-100 text-red-700", icon: AlertTriangle },
};

export default function LogsPage() {
  const { user } = useAuthStore();
  const supabase = createClient();

  const [logs, setLogs] = useState<any[]>([]);
  const [users, setUsers] = useState<{ id: string; nombre: string }[]>([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(0);
  const [total, setTotal] = useState(0);
  const [selectedLog, setSelectedLog] = useState<any>(null);

  // Filters
  const [filterUser, setFilterUser] = useState("");
  const [filterAccion, setFilterAccion] = useState("");
  const [filterEntidades, setFilterEntidades] = useState<string[]>([]); // multi-selección
  const [filterResultado, setFilterResultado] = useState("");
  const [filterDesde, setFilterDesde] = useState("");
  const [filterHasta, setFilterHasta] = useState("");
  const [entidadesDisponibles, setEntidadesDisponibles] = useState<string[]>([]);
  const [entidadDropOpen, setEntidadDropOpen] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);

    let query = supabase.from("audit_log")
      .select("*, log_user:users!audit_log_user_id_fkey(nombre, email)", { count: "exact" })
      .order("created_at", { ascending: false })
      .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

    if (filterUser) query = query.eq("user_id", filterUser);
    if (filterAccion) query = query.eq("accion", filterAccion);
    if (filterEntidades.length > 0) query = (query as any).in("entidad", filterEntidades);
    if (filterResultado) query = query.eq("resultado", filterResultado);
    if (filterDesde) query = query.gte("created_at", filterDesde + "T00:00:00");
    if (filterHasta) query = query.lte("created_at", filterHasta + "T23:59:59");

    const { data, count } = await query;
    setLogs(data || []);
    setTotal(count || 0);

    setLoading(false);
  }, [page, filterUser, filterAccion, filterEntidades, filterResultado, filterDesde, filterHasta]);

  useEffect(() => { fetchData(); }, [fetchData]);

  // Cargar entidades disponibles y usuarios UNA SOLA VEZ al montar
  useEffect(() => {
    const loadStatic = async () => {
      // Usuarios
      const { data: usersData } = await supabase.from("users").select("id, nombre").order("nombre");
      if (usersData) setUsers(usersData);

      // Entidades: usar RPC get_audit_entidades() para DISTINCT real
      // Si la RPC no existe, fallback a query directa con limit alto
      try {
        const { data: entData, error } = await (supabase.rpc as any)("get_audit_entidades");
        if (!error && entData) {
          setEntidadesDisponibles((entData as any[]).map((r: any) => r.entidad).filter(Boolean));
        } else {
          throw error;
        }
      } catch {
        // Fallback: traer todos los logs y deduplicar en cliente
        const { data: entData2 } = await (supabase.from("audit_log") as any)
          .select("entidad").not("entidad", "is", null).limit(10000);
        if (entData2) {
          const uniq = Array.from(new Set((entData2 as any[]).map((r: any) => r.entidad).filter(Boolean))).sort() as string[];
          setEntidadesDisponibles(uniq);
        }
      }
    };
    loadStatic();
  }, []);

  // Reset page when filters change
  useEffect(() => { setPage(0); }, [filterUser, filterAccion, filterEntidades, filterResultado, filterDesde, filterHasta]);

  const hasFilters = filterUser || filterAccion || filterEntidades.length > 0 || filterResultado || filterDesde || filterHasta;

  // Cerrar el dropdown de entidades al hacer clic fuera
  useEffect(() => {
    if (!entidadDropOpen) return;
    const handler = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      if (!target.closest("[data-entidad-drop]")) setEntidadDropOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [entidadDropOpen]);
  const totalPages = Math.ceil(total / PAGE_SIZE);

  // Get a readable summary of what changed.
  // Prioridad: la `descripcion` ya viene generada desde el backend (trigger
  // de BD o capa de error) a partir de la migración 026 — es más fiable que
  // intentar adivinar el campo "nombre" en el cliente, y funciona igual para
  // cualquier entidad nueva sin tener que tocar este componente cada vez.
  const getChangeSummary = (log: any): string => {
    if (log.descripcion) return log.descripcion;
    if (log.accion === "login") return "Inicio de sesión";
    if (log.accion === "logout") return "Cierre de sesión";
    if (log.accion === "crear" && log.valor_nuevo) {
      const v = log.valor_nuevo;
      return v.nombre || v.descripcion || v.concepto || v.nombre_archivo || "Nuevo registro";
    }
    if (log.accion === "eliminar" && log.valor_anterior) {
      const v = log.valor_anterior;
      return v.nombre || v.descripcion || v.concepto || v.nombre_archivo || "Registro eliminado";
    }
    if (log.accion === "editar" && log.valor_nuevo) {
      const v = log.valor_nuevo;
      return v.nombre || v.descripcion || v.concepto || "Registro modificado";
    }
    return "";
  };

  // Render JSON diff
  const renderDiff = (oldVal: any, newVal: any) => {
    if (!oldVal && !newVal) return null;
    const allKeys = new Set([...Object.keys(oldVal || {}), ...Object.keys(newVal || {})]);
    const ignoredKeys = ["created_at", "updated_at", "id"];
    const changedKeys = Array.from(allKeys).filter((k) => {
      if (ignoredKeys.includes(k)) return false;
      return JSON.stringify(oldVal?.[k]) !== JSON.stringify(newVal?.[k]);
    });

    if (changedKeys.length === 0) return <p className="text-xs text-surface-400 py-2">Sin cambios detectados</p>;

    return (
      <div className="space-y-2">
        {changedKeys.map((key) => (
          <div key={key} className="text-xs border border-surface-100 rounded-lg overflow-hidden">
            <div className="bg-surface-50 px-3 py-1.5 font-semibold text-surface-600 border-b border-surface-100">{key}</div>
            <div className="grid grid-cols-2 divide-x divide-surface-100">
              {oldVal && (
                <div className="px-3 py-2">
                  <p className="text-[10px] text-surface-400 mb-0.5">Anterior</p>
                  <p className="text-red-600 font-mono break-all">{oldVal[key] !== undefined && oldVal[key] !== null ? String(oldVal[key]) : "—"}</p>
                </div>
              )}
              {newVal && (
                <div className="px-3 py-2">
                  <p className="text-[10px] text-surface-400 mb-0.5">Nuevo</p>
                  <p className="text-emerald-600 font-mono break-all">{newVal[key] !== undefined && newVal[key] !== null ? String(newVal[key]) : "—"}</p>
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    );
  };

  // Redirect non-admins
  if (user && user.role !== "admin") {
    return (
      <AppLayout>
        <div className="max-w-7xl mx-auto text-center py-20">
          <ScrollText className="w-10 h-10 text-surface-300 mx-auto mb-3" />
          <p className="text-sm text-surface-500">Solo los administradores pueden ver los logs</p>
        </div>
      </AppLayout>
    );
  }

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        {/* Header */}
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 rounded-lg bg-surface-100 flex items-center justify-center">
            <ScrollText className="w-5 h-5 text-surface-600" />
          </div>
          <div>
            <h1 className="text-xl font-display font-bold text-surface-900">Logs de Auditoría</h1>
            <p className="text-sm text-surface-500">{total} registros</p>
          </div>
        </div>

        {/* Filters */}
        <div className="card p-3 mb-4">
          <div className="flex items-center gap-3 flex-wrap">
            <select value={filterUser} onChange={(e) => setFilterUser(e.target.value)}
              className="px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20">
              <option value="">Todos los usuarios</option>
              {users.map((u) => <option key={u.id} value={u.id}>{u.nombre}</option>)}
            </select>
            <select value={filterAccion} onChange={(e) => setFilterAccion(e.target.value)}
              className="px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20">
              <option value="">Todas las acciones</option>
              {Object.entries(ACCION_LABELS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
            </select>
            {/* Multi-selección de entidades */}
            <div className="relative" data-entidad-drop>
              <button
                onClick={() => setEntidadDropOpen(!entidadDropOpen)}
                className="flex items-center gap-2 px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg hover:bg-surface-100 focus:outline-none"
              >
                {filterEntidades.length === 0
                  ? "Todas las entidades"
                  : filterEntidades.length === 1
                  ? (ENTIDAD_LABELS[filterEntidades[0]] || filterEntidades[0])
                  : `${filterEntidades.length} entidades`}
                <ChevronDown className="w-3.5 h-3.5 text-surface-400" />
              </button>
              {entidadDropOpen && (
                <div className="absolute top-full left-0 mt-1 z-50 bg-white border border-surface-200 rounded-xl shadow-xl min-w-56 max-h-72 overflow-y-auto">
                  <div className="p-2 border-b border-surface-100 flex justify-between items-center">
                    <span className="text-xs font-semibold text-surface-600">Filtrar por entidad</span>
                    <button onClick={() => { setFilterEntidades([]); setEntidadDropOpen(false); }}
                      className="text-[10px] text-brand-600 hover:underline">Limpiar</button>
                  </div>
                  {entidadesDisponibles.map((ent) => (
                    <label key={ent}
                      className="flex items-center gap-2.5 px-3 py-2 hover:bg-surface-50 cursor-pointer"
                      onClick={() => {
                        setFilterEntidades(prev =>
                          prev.includes(ent) ? prev.filter(e => e !== ent) : [...prev, ent]
                        );
                      }}>
                      <div className={cn("w-4 h-4 rounded border-2 flex items-center justify-center shrink-0",
                        filterEntidades.includes(ent) ? "bg-brand-500 border-brand-500" : "border-surface-300")}>
                        {filterEntidades.includes(ent) && <Check className="w-2.5 h-2.5 text-white" />}
                      </div>
                      <span className="text-xs text-surface-700">
                        {ENTIDAD_LABELS[ent] || ent}
                      </span>
                    </label>
                  ))}
                </div>
              )}
            </div>
            <select value={filterResultado} onChange={(e) => setFilterResultado(e.target.value)}
              className="px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20">
              <option value="">Éxito y error</option>
              {Object.entries(RESULTADO_LABELS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
            </select>
            <div className="flex items-center gap-1.5">
              <input type="date" value={filterDesde} onChange={(e) => setFilterDesde(e.target.value)} placeholder="Desde"
                className="px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20" />
              <span className="text-xs text-surface-400">→</span>
              <input type="date" value={filterHasta} onChange={(e) => setFilterHasta(e.target.value)} placeholder="Hasta"
                className="px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20" />
            </div>
            {hasFilters && (
              <button onClick={() => { setFilterUser(""); setFilterAccion(""); setFilterEntidades([]); setFilterResultado(""); setFilterDesde(""); setFilterHasta(""); setEntidadDropOpen(false); }}
                className="flex items-center gap-1 px-2.5 py-1.5 text-xs text-red-600 bg-red-50 rounded-lg hover:bg-red-100">
                <X className="w-3 h-3" /> Limpiar
              </button>
            )}
          </div>
        </div>

        {/* Table */}
        <div className="card overflow-hidden">
          {loading ? (
            <div className="flex justify-center py-16"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div>
          ) : logs.length === 0 ? (
            <div className="text-center py-16"><ScrollText className="w-8 h-8 text-surface-300 mx-auto mb-2" /><p className="text-sm text-surface-500">Sin registros</p></div>
          ) : (
            <>
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-surface-200 bg-surface-50">
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2.5 px-4">Fecha / Hora</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2.5 px-4">Usuario</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2.5 px-4">Acción</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2.5 px-4">Entidad</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2.5 px-4">Detalle</th>
                    <th className="text-left text-[10px] font-semibold text-surface-400 uppercase py-2.5 px-4">Resultado</th>
                    <th className="w-10"></th>
                  </tr>
                </thead>
                <tbody>
                  {logs.map((log) => {
                    const accion = ACCION_LABELS[log.accion] || { label: log.accion, color: "bg-surface-100 text-surface-600", icon: Eye };
                    const AccionIcon = accion.icon;
                    const resultado = RESULTADO_LABELS[log.resultado] || RESULTADO_LABELS.exito;
                    const ResultadoIcon = resultado.icon;
                    return (
                      <tr key={log.id} className="border-b border-surface-50 hover:bg-surface-50/50 cursor-pointer transition-colors" onClick={() => setSelectedLog(log)}>
                        <td className="px-4 py-2.5 text-xs text-surface-600 whitespace-nowrap">
                          {new Date(log.created_at).toLocaleDateString("es-ES", { day: "2-digit", month: "2-digit", year: "numeric" })}
                          <span className="text-surface-400 ml-1">{new Date(log.created_at).toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit", second: "2-digit" })}</span>
                        </td>
                        <td className="px-4 py-2.5">
                          <span className="text-xs font-medium text-surface-900">{log.log_user?.nombre || "Sistema"}</span>
                        </td>
                        <td className="px-4 py-2.5">
                          <span className={cn("badge text-[10px] flex items-center gap-1 w-fit", accion.color)}>
                            <AccionIcon className="w-3 h-3" />{accion.label}
                          </span>
                        </td>
                        <td className="px-4 py-2.5 text-xs text-surface-600">{ENTIDAD_LABELS[log.entidad] || log.entidad}</td>
                        <td className="px-4 py-2.5 text-xs text-surface-500 truncate max-w-[250px]">{getChangeSummary(log)}</td>
                        <td className="px-4 py-2.5">
                          <span className={cn("badge text-[10px] flex items-center gap-1 w-fit", resultado.color)}>
                            <ResultadoIcon className="w-3 h-3" />{resultado.label}
                          </span>
                        </td>
                        <td className="px-4 py-2.5"><ArrowRight className="w-3.5 h-3.5 text-surface-300" /></td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>

              {/* Pagination */}
              {totalPages > 1 && (
                <div className="flex items-center justify-between px-4 py-3 border-t border-surface-100">
                  <p className="text-xs text-surface-400">{page * PAGE_SIZE + 1}–{Math.min((page + 1) * PAGE_SIZE, total)} de {total}</p>
                  <div className="flex items-center gap-1">
                    <button onClick={() => setPage(Math.max(0, page - 1))} disabled={page === 0}
                      className="p-1.5 rounded-md text-surface-400 hover:bg-surface-100 disabled:opacity-30">
                      <ChevronLeft className="w-4 h-4" />
                    </button>
                    <span className="text-xs text-surface-600 px-2">Página {page + 1} de {totalPages}</span>
                    <button onClick={() => setPage(Math.min(totalPages - 1, page + 1))} disabled={page >= totalPages - 1}
                      className="p-1.5 rounded-md text-surface-400 hover:bg-surface-100 disabled:opacity-30">
                      <ChevronRight className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              )}
            </>
          )}
        </div>
      </div>

      {/* Detail modal */}
      <Modal open={!!selectedLog} onClose={() => setSelectedLog(null)} title="Detalle del log" size="lg">
        {selectedLog && (
          <div className="space-y-4">
            {/* Summary */}
            <div className="grid grid-cols-2 gap-4">
              <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Fecha</p>
                <p className="text-sm text-surface-900 mt-0.5">{new Date(selectedLog.created_at).toLocaleString("es-ES")}</p></div>
              <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Usuario</p>
                <p className="text-sm text-surface-900 mt-0.5">{selectedLog.log_user?.nombre || "Sistema"}{selectedLog.user_rol ? ` (${selectedLog.user_rol})` : ""}</p></div>
              <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Acción</p>
                <span className={cn("badge text-xs mt-0.5", (ACCION_LABELS[selectedLog.accion] || {}).color)}>{(ACCION_LABELS[selectedLog.accion] || {}).label || selectedLog.accion}</span></div>
              <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Entidad</p>
                <p className="text-sm text-surface-900 mt-0.5">{ENTIDAD_LABELS[selectedLog.entidad] || selectedLog.entidad}</p></div>
              {selectedLog.modulo && <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Módulo</p><p className="text-sm text-surface-900 mt-0.5 font-mono">{selectedLog.modulo}</p></div>}
              <div><p className="text-[10px] font-semibold text-surface-400 uppercase">Resultado</p>
                <span className={cn("badge text-xs mt-0.5", (RESULTADO_LABELS[selectedLog.resultado] || RESULTADO_LABELS.exito).color)}>
                  {(RESULTADO_LABELS[selectedLog.resultado] || RESULTADO_LABELS.exito).label}
                </span>
              </div>
              {selectedLog.ip_address && <div><p className="text-[10px] font-semibold text-surface-400 uppercase">IP</p><p className="text-sm text-surface-900 mt-0.5 font-mono">{selectedLog.ip_address}</p></div>}
              {selectedLog.user_agent && <div className="col-span-2"><p className="text-[10px] font-semibold text-surface-400 uppercase">Navegador</p><p className="text-xs text-surface-600 mt-0.5 truncate">{selectedLog.user_agent}</p></div>}
            </div>

            {/* Error detail (resultado = error) */}
            {selectedLog.resultado === "error" && selectedLog.error_detalle && (
              <div>
                <h3 className="text-sm font-semibold text-red-700 mb-2 flex items-center gap-1.5"><AlertTriangle className="w-4 h-4" /> Detalle del error</h3>
                <div className="bg-red-50 rounded-lg p-3">
                  <p className="text-xs text-red-700 font-mono whitespace-pre-wrap">{selectedLog.error_detalle}</p>
                </div>
              </div>
            )}

            {/* Diff */}
            {selectedLog.accion === "editar" && (
              <div>
                <h3 className="text-sm font-semibold text-surface-900 mb-2">Cambios realizados</h3>
                {selectedLog.valor_anterior || selectedLog.valor_nuevo
                  ? renderDiff(selectedLog.valor_anterior, selectedLog.valor_nuevo)
                  : (
                    <div className="bg-amber-50 border border-amber-200 rounded-lg p-3">
                      <p className="text-xs text-amber-700">
                        No hay datos de cambio disponibles para este registro.
                        Los logs anteriores a la migración 043b no guardan el detalle de campos modificados.
                        Los nuevos cambios sí quedarán registrados con el valor anterior y nuevo.
                      </p>
                    </div>
                  )
                }
              </div>
            )}

            {selectedLog.accion === "crear" && selectedLog.valor_nuevo && (
              <div>
                <h3 className="text-sm font-semibold text-surface-900 mb-2">Datos creados</h3>
                <div className="bg-surface-50 rounded-lg p-3 max-h-[300px] overflow-y-auto">
                  <pre className="text-xs text-surface-700 font-mono whitespace-pre-wrap">{JSON.stringify(selectedLog.valor_nuevo, null, 2)}</pre>
                </div>
              </div>
            )}

            {selectedLog.accion === "eliminar" && selectedLog.valor_anterior && (
              <div>
                <h3 className="text-sm font-semibold text-surface-900 mb-2">Datos eliminados</h3>
                <div className="bg-red-50 rounded-lg p-3 max-h-[300px] overflow-y-auto">
                  <pre className="text-xs text-red-700 font-mono whitespace-pre-wrap">{JSON.stringify(selectedLog.valor_anterior, null, 2)}</pre>
                </div>
              </div>
            )}

            {selectedLog.accion === "login" && (
              <div className="bg-amber-50 rounded-lg p-3">
                <p className="text-sm text-amber-700">Inicio de sesión registrado</p>
              </div>
            )}
          </div>
        )}
      </Modal>
    </AppLayout>
  );
}