"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { Obra, EstadoObra } from "@/lib/types/database";
import { Building2, Plus, Archive, ArchiveRestore, Loader2, FileDown, ChevronDown, X, Check } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import Link from "next/link";
import { filtrarObrasVisiblesOperario } from "@/lib/utils/obrasVisiblesOperario";

// Ordenación natural para num_presupuesto: "P-100" > "P-20" correctamente
function naturalSort(a: string, b: string): number {
  const re = /(\d+)/g;
  const aParts = a.split(re); const bParts = b.split(re);
  for (let i = 0; i < Math.max(aParts.length, bParts.length); i++) {
    const ai = aParts[i] || ""; const bi = bParts[i] || "";
    const an = parseInt(ai); const bn = parseInt(bi);
    if (!isNaN(an) && !isNaN(bn)) { if (an !== bn) return an - bn; }
    else { const c = ai.localeCompare(bi, "es"); if (c !== 0) return c; }
  }
  return 0;
}

function sortObras(list: Obra[]): Obra[] {
  return [...list].sort((a, b) => {
    const pa = (a as any).num_presupuesto || "";
    const pb = (b as any).num_presupuesto || "";
    if (!pa && pb) return 1;   // sin presupuesto al final
    if (pa && !pb) return -1;
    if (!pa && !pb) return (a.nombre || "").localeCompare(b.nombre || "", "es");
    const nc = naturalSort(pa, pb);
    if (nc !== 0) return nc;
    return (a.nombre || "").localeCompare(b.nombre || "", "es");
  });
}

export default function ObrasPage() {
  const { user } = useAuthStore();
  const { isAdmin, canDo, loaded: permisosLoaded } = usePermissions();
  const puedeCrear    = isAdmin || canDo("obras", "crear");
  const puedeEditar   = isAdmin || canDo("obras", "editar");
  const puedeEliminar = isAdmin || canDo("obras", "eliminar");
  const esSoloOperario = permisosLoaded && !isAdmin && !canDo("obras", "crear") && !canDo("obras", "editar");

  const supabase = createClient();
  const [archivando, setArchivando]         = useState<string | null>(null);
  const [confirmArchive, setConfirmArchive] = useState<string | null>(null);
  const [data, setData]                     = useState<Obra[]>([]);
  const [estados, setEstados]               = useState<EstadoObra[]>([]);
  const [estadosFilter, setEstadosFilter]   = useState<Set<string>>(new Set()); // multi
  const [archivedFilter, setArchivedFilter] = useState<"activas" | "archivadas" | "todas">("activas");
  const [loading, setLoading]               = useState(true);
  const [generandoPdf, setGenerandoPdf]     = useState(false);
  const [searchQuery, setSearchQuery]       = useState("");
  const [dropdownOpen, setDropdownOpen]     = useState(false);
  const [cambiandoEstado, setCambiandoEstado] = useState<string | null>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Cerrar dropdown al hacer clic fuera
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node))
        setDropdownOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const { data: rows } = await supabase
      .from("obras")
      .select("*, cliente:clientes(*), estado_custom:estados_obra(*)")
      .order("num_presupuesto", { ascending: true });

    let visibleRows = (rows as Obra[]) || [];
    if (esSoloOperario && user?.recurso_id) {
      const [asigR, partesR] = await Promise.all([
        supabase.from("asignaciones").select("obra_id, fecha_inicio, fecha_fin").eq("recurso_tipo", "humano").eq("recurso_id", user.recurso_id),
        supabase.from("partes_diarios").select("obra_id, fecha, estado").eq("created_by", user.id),
      ]);
      visibleRows = filtrarObrasVisiblesOperario(visibleRows, (asigR.data || []) as any, (partesR.data || []) as any);
    }

    setData(sortObras(visibleRows));
    const { data: est } = await supabase.from("estados_obra").select("*").eq("activo", true).order("nombre");
    setEstados(est || []);
    setLoading(false);
  }, [user, esSoloOperario]);

  useEffect(() => { if (permisosLoaded) fetchData(); }, [fetchData, permisosLoaded]);

  // ── Cambio de estado inline ────────────────────────────────────────
  const handleChangeEstado = async (obra: Obra, nuevoEstadoId: string) => {
    const estadoAnteriorId = obra.estado_obra_id;
    if (estadoAnteriorId === nuevoEstadoId) return;
    setCambiandoEstado(obra.id);
    // Optimistic update
    setData((prev) => prev.map((o) => o.id === obra.id
      ? { ...o, estado_obra_id: nuevoEstadoId || null,
          estado_custom: nuevoEstadoId ? estados.find((e) => e.id === nuevoEstadoId) || null : null } as Obra
      : o
    ));
    const { error } = await (supabase.from("obras") as any)
      .update({ estado_obra_id: nuevoEstadoId || null })
      .eq("id", obra.id);
    if (error) {
      // Revertir en caso de error
      setData((prev) => prev.map((o) => o.id === obra.id
        ? { ...o, estado_obra_id: estadoAnteriorId,
            estado_custom: estadoAnteriorId ? estados.find((e) => e.id === estadoAnteriorId) || null : null } as Obra
        : o
      ));
      alert("Error al cambiar estado: " + error.message);
    }
    // audit_log lo registra el trigger audit_obras de Supabase (INSERT/UPDATE/DELETE)
    setCambiandoEstado(null);
  };

  // ── Filtrado ───────────────────────────────────────────────────────
  const filteredData = data.filter((o) => {
    if (archivedFilter === "activas"    && (o as any).archivada) return false;
    if (archivedFilter === "archivadas" && !(o as any).archivada) return false;
    if (estadosFilter.size > 0 && !estadosFilter.has(o.estado_obra_id || "")) return false;
    return true;
  });

  // ── Columnas ───────────────────────────────────────────────────────
  const columns: Column<Obra>[] = [
    {
      key: "num_presupuesto" as any, header: "N.º Presupuesto",
      render: (item) => (
        <span className="text-xs font-mono text-surface-700 whitespace-nowrap">
          {(item as any).num_presupuesto || <span className="text-surface-300">—</span>}
        </span>
      ),
    },
    {
      key: "nombre", header: "Obra",
      render: (item) => (
        <Link href={`/obras/${item.id}`} className="group">
          <div className="flex items-center gap-2">
            <div className="w-1.5 h-7 rounded-full shrink-0" style={{ backgroundColor: item.color || "#DC2626" }} />
            <div>
              <span className="font-medium text-surface-900 group-hover:text-brand-600 transition-colors text-sm">{item.nombre}</span>
              {(item as any).cliente?.nombre && (
                <p className="text-xs text-surface-400">{(item as any).cliente.nombre}</p>
              )}
            </div>
          </div>
        </Link>
      ),
    },
    {
      key: "cliente_id", header: "Cliente",
      render: (item) => <span className="text-sm text-surface-700">{(item as any).cliente?.nombre || "—"}</span>,
    },
    {
      key: "estado_obra_id", header: "Estado",
      render: (item) => {
        const est = (item as any).estado_custom as EstadoObra | null;
        if (!puedeEditar) {
          return est
            ? <span className="inline-flex px-2 py-0.5 rounded-full text-xs font-medium text-white whitespace-nowrap" style={{ backgroundColor: est.color }}>{est.nombre}</span>
            : <span className="text-xs text-surface-400">Sin estado</span>;
        }
        return (
          <div className="relative flex items-center gap-1.5">
            {cambiandoEstado === item.id && <Loader2 className="w-3 h-3 animate-spin text-surface-400 shrink-0" />}
            <select
              value={item.estado_obra_id || ""}
              onChange={(e) => { e.stopPropagation(); handleChangeEstado(item, e.target.value); }}
              onClick={(e) => e.stopPropagation()}
              disabled={cambiandoEstado === item.id}
              className="text-xs font-medium text-white border-0 rounded-full px-2 py-0.5 cursor-pointer focus:outline-none appearance-none pr-4 disabled:opacity-60"
              style={{ backgroundColor: est?.color || "#9CA3AF", backgroundImage: "none" }}
            >
              <option value="" style={{ backgroundColor: "#fff", color: "#374151" }}>Sin estado</option>
              {estados.map((e) => (
                <option key={e.id} value={e.id} style={{ backgroundColor: e.color, color: "#fff" }}>{e.nombre}</option>
              ))}
            </select>
          </div>
        );
      },
    },
    {
      key: "archivada" as any, header: "",
      render: (item) => {
        if (!puedeEditar && !puedeEliminar) return null;
        const estaArchivada = !!(item as any).archivada;
        const isConfirming = confirmArchive === item.id;
        const isLoading = archivando === item.id;
        return (
          <div className="flex items-center justify-end gap-1">
            {isConfirming && <span className="text-xs text-amber-600 font-medium mr-1">¿Confirmar?</span>}
            <button
              onClick={(e) => { e.preventDefault(); e.stopPropagation(); handleArchivar(item); }}
              disabled={isLoading}
              title={estaArchivada ? "Restaurar obra" : "Archivar obra"}
              className={cn("p-1.5 rounded-lg transition-colors disabled:opacity-50",
                isConfirming ? "bg-amber-100 text-amber-700" :
                estaArchivada ? "text-surface-400 hover:bg-emerald-50 hover:text-emerald-600" :
                "text-surface-400 hover:bg-amber-50 hover:text-amber-600"
              )}
            >
              {isLoading ? <Loader2 className="w-4 h-4 animate-spin" /> :
               estaArchivada ? <ArchiveRestore className="w-4 h-4" /> : <Archive className="w-4 h-4" />}
            </button>
          </div>
        );
      },
    },
  ];

  const handleArchivar = async (obra: Obra) => {
    if (confirmArchive !== obra.id) { setConfirmArchive(obra.id); return; }
    setArchivando(obra.id); setConfirmArchive(null);
    const { error } = await (supabase.from("obras") as any)
      .update({ archivada: !(obra as any).archivada }).eq("id", obra.id);
    if (error) alert("Error al archivar: " + error.message);
    else fetchData();
    setArchivando(null);
  };

  const handleGenerarPdf = async () => {
    const q = searchQuery.toLowerCase().trim();
    const obrasFiltradas = (q
      ? filteredData.filter((o) =>
          [o.nombre, (o as any).ubicacion, (o as any).cliente?.nombre,
           (o as any).direccion, (o as any).localidad, (o as any).num_presupuesto]
            .some((v) => v && String(v).toLowerCase().includes(q))
        )
      : filteredData);

    if (obrasFiltradas.length === 0) {
      alert("No hay obras con los filtros actuales."); return;
    }
    setGenerandoPdf(true);
    try {
      const estadosSeleccionados = estados
        .filter((e) => estadosFilter.has(e.id))
        .map((e) => e.nombre);

      const res = await fetch("/api/informes/obras", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          obras: obrasFiltradas,
          archivedFilter,
          estadosFilterLabels: estadosSeleccionados,
          searchQuery: q,
        }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: "Error" }));
        alert("Error al generar PDF: " + err.error); setGenerandoPdf(false); return;
      }
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      const hoy = new Date();
      const fecha = `${hoy.getFullYear()}${String(hoy.getMonth()+1).padStart(2,"0")}${String(hoy.getDate()).padStart(2,"0")}`;
      a.href = url; a.download = `obras_${archivedFilter}_${fecha}.pdf`;
      document.body.appendChild(a); a.click();
      setTimeout(() => { URL.revokeObjectURL(url); document.body.removeChild(a); }, 1000);
    } catch (err: any) { alert("Error: " + (err?.message || err)); }
    setGenerandoPdf(false);
  };

  // Label para el multi-selector
  const estadosFilterLabel = estadosFilter.size === 0
    ? "Todos los estados"
    : estadosFilter.size === 1
    ? (estados.find((e) => estadosFilter.has(e.id))?.nombre || "1 estado")
    : `${estadosFilter.size} estados`;

  const tableTitle = archivedFilter === "activas" ? "Obras activas"
    : archivedFilter === "archivadas" ? "Obras archivadas" : "Todas las obras";

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="flex items-center justify-between mb-6 flex-wrap gap-3">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <Building2 className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">Obras</h1>
              <p className="text-sm text-surface-500">Listado de todas las obras</p>
            </div>
          </div>

          <div className="flex items-center gap-2 flex-wrap">
            {/* Activas / Archivadas / Todas */}
            <div className="flex bg-surface-100 rounded-lg p-0.5 gap-0.5">
              {(["activas", "archivadas", "todas"] as const).map((v) => (
                <button key={v} onClick={() => setArchivedFilter(v)}
                  className={cn("px-3 py-1.5 text-xs font-medium rounded-md transition-colors",
                    archivedFilter === v ? "bg-white text-surface-900 shadow-sm" : "text-surface-500 hover:text-surface-700")}>
                  {v === "activas" ? "Activas" : v === "archivadas" ? "Archivadas" : "Todas"}
                </button>
              ))}
            </div>

            {/* Multi-selector de estados */}
            <div className="relative" ref={dropdownRef}>
              <button
                onClick={() => setDropdownOpen((v) => !v)}
                className={cn(
                  "flex items-center gap-1.5 px-3 py-2 text-sm rounded-lg border transition-colors",
                  estadosFilter.size > 0
                    ? "bg-brand-50 border-brand-200 text-brand-700 font-medium"
                    : "bg-surface-100 border-transparent text-surface-600 hover:bg-surface-200"
                )}
              >
                <span className="max-w-[160px] truncate">{estadosFilterLabel}</span>
                {estadosFilter.size > 0
                  ? <button onClick={(e) => { e.stopPropagation(); setEstadosFilter(new Set()); }}
                      className="ml-1 text-brand-400 hover:text-brand-700"><X className="w-3 h-3" /></button>
                  : <ChevronDown className={cn("w-3.5 h-3.5 transition-transform", dropdownOpen && "rotate-180")} />}
              </button>

              {dropdownOpen && (
                <div className="absolute right-0 top-full mt-1 z-30 bg-white rounded-xl shadow-lg border border-surface-200 py-1 min-w-[200px] max-h-64 overflow-y-auto">
                  <div className="px-3 py-1.5 border-b border-surface-100 flex items-center justify-between">
                    <span className="text-[11px] font-semibold text-surface-400 uppercase">Filtrar por estado</span>
                    {estadosFilter.size > 0 && (
                      <button onClick={() => setEstadosFilter(new Set())}
                        className="text-[10px] text-brand-600 hover:text-brand-800 font-medium">Limpiar</button>
                    )}
                  </div>
                  {estados.map((e) => {
                    const sel = estadosFilter.has(e.id);
                    return (
                      <button key={e.id}
                        onClick={() => {
                          const next = new Set(estadosFilter);
                          if (sel) next.delete(e.id); else next.add(e.id);
                          setEstadosFilter(next);
                        }}
                        className={cn(
                          "w-full flex items-center gap-2.5 px-3 py-2 text-sm text-left hover:bg-surface-50 transition-colors",
                          sel && "bg-brand-50"
                        )}
                      >
                        <span className="w-3 h-3 rounded-full shrink-0" style={{ backgroundColor: e.color }} />
                        <span className="flex-1 text-surface-800">{e.nombre}</span>
                        {sel && <Check className="w-3.5 h-3.5 text-brand-600 shrink-0" />}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>

            {/* Informe PDF */}
            <button onClick={handleGenerarPdf} disabled={generandoPdf || loading}
              className="flex items-center gap-1.5 px-3 py-2 text-sm font-medium text-surface-700 bg-surface-100 rounded-lg hover:bg-surface-200 disabled:opacity-60 transition-colors">
              {generandoPdf ? <Loader2 className="w-4 h-4 animate-spin" /> : <FileDown className="w-4 h-4" />}
              {generandoPdf ? "Generando..." : "Informe PDF"}
            </button>

            {puedeCrear && (
              <Link href="/obras/nueva"
                className="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 transition-colors">
                <Plus className="w-4 h-4" /> Nueva obra
              </Link>
            )}
          </div>
        </div>

        <div onClick={() => { if (confirmArchive) setConfirmArchive(null); if (dropdownOpen) setDropdownOpen(false); }}>
          <DataTable
            data={filteredData}
            columns={columns}
            title={tableTitle}
            loading={loading}
            searchPlaceholder="Buscar por nombre, cliente, presupuesto, dirección..."
            searchKeys={["nombre", "ubicacion", "estado",
              (o: any) => o.cliente?.nombre || "",
              (o: any) => o.direccion || "",
              (o: any) => o.localidad || "",
              (o: any) => o.num_presupuesto || ""]}
            onSearch={(q) => setSearchQuery(q)}
            canAdd={false} canEdit={false} canDelete={false}
          />
        </div>
      </div>
    </AppLayout>
  );
}
