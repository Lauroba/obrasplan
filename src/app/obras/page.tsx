"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import DataTable, { Column } from "@/components/shared/DataTable";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { usePermissions } from "@/hooks/usePermissions";
import type { Obra, EstadoObra } from "@/lib/types/database";
import { Building2, Plus, Archive, ArchiveRestore, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import Link from "next/link";
import { filtrarObrasVisiblesOperario } from "@/lib/utils/obrasVisiblesOperario";

export default function ObrasPage() {
  const { user } = useAuthStore();
  const { isAdmin, canDo, loaded: permisosLoaded } = usePermissions();
  // Solo filtrar por asignaciones si es operario puro (sin permisos crear/editar obras)
  // Guard: mientras cargan los permisos, no filtrar (evita race condition)
  const esSoloOperario = permisosLoaded && !isAdmin && !canDo("obras", "crear") && !canDo("obras", "editar");
  const [archivando, setArchivando] = useState<string | null>(null);
  const [confirmArchive, setConfirmArchive] = useState<string | null>(null);
  const [data, setData] = useState<Obra[]>([]);
  const [estados, setEstados] = useState<EstadoObra[]>([]);
  const [estadoFilter, setEstadoFilter] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const supabase = createClient();

  const fetchData = useCallback(async () => {
    setLoading(true);
    const { data: rows } = await supabase
      .from("obras")
      .select("*, cliente:clientes(*), estado_custom:estados_obra(*)")
      .order("fecha_inicio", { ascending: false });

    let visibleRows = (rows as Obra[]) || [];
    // Solo filtrar si es operario puro Y los permisos ya cargaron
    if (esSoloOperario && user?.recurso_id) {
      const [asigR, partesR] = await Promise.all([
        supabase.from("asignaciones").select("obra_id, fecha_inicio, fecha_fin").eq("recurso_tipo", "humano").eq("recurso_id", user.recurso_id),
        supabase.from("partes_diarios").select("obra_id, fecha, estado").eq("created_by", user.id),
      ]);
      visibleRows = filtrarObrasVisiblesOperario(visibleRows, (asigR.data || []) as any, (partesR.data || []) as any);
    }

    setData(visibleRows);
    const { data: est } = await supabase.from("estados_obra").select("*").eq("activo", true).order("nombre");
    setEstados(est || []);
    setLoading(false);
  }, [user, esSoloOperario]);

  // Esperar a que los permisos carguen antes de hacer el fetch inicial
  useEffect(() => {
    if (permisosLoaded) fetchData();
  }, [fetchData, permisosLoaded]);

  const columns: Column<Obra>[] = [
    {
      key: "nombre", header: "Obra",
      render: (item) => (
        <Link href={`/obras/${item.id}`} className="group">
          <div className="flex items-center gap-3">
            <div className="w-2 h-8 rounded-full" style={{ backgroundColor: item.color || "#DC2626" }} />
            <div>
              <span className="font-medium text-surface-900 group-hover:text-brand-600 transition-colors">{item.nombre}</span>
              <p className="text-xs text-surface-400">{item.ubicacion || "Sin ubicación"}</p>
            </div>
          </div>
        </Link>
      ),
    },
    { key: "cliente_id", header: "Cliente", render: (item) => (item as any).cliente?.nombre || "—" },
    {
      key: "archivada" as any, header: "",
      render: (item) => {
        if (user?.role !== "admin") return null;
        const estaArchivada = !!(item as any).archivada;
        const isConfirming = confirmArchive === item.id;
        const isLoading = archivando === item.id;
        return (
          <div className="flex items-center justify-end gap-1">
            {isConfirming && (
              <span className="text-xs text-amber-600 font-medium mr-1">¿Confirmar?</span>
            )}
            <button
              onClick={(e) => { e.preventDefault(); e.stopPropagation(); handleArchivar(item); }}
              disabled={isLoading}
              title={estaArchivada ? "Restaurar obra" : "Archivar obra"}
              className={cn(
                "p-1.5 rounded-lg transition-colors disabled:opacity-50",
                isConfirming
                  ? "bg-amber-100 text-amber-700 hover:bg-amber-200"
                  : estaArchivada
                  ? "text-surface-400 hover:bg-emerald-50 hover:text-emerald-600"
                  : "text-surface-400 hover:bg-amber-50 hover:text-amber-600"
              )}
            >
              {isLoading
                ? <Loader2 className="w-4 h-4 animate-spin" />
                : estaArchivada
                ? <ArchiveRestore className="w-4 h-4" />
                : <Archive className="w-4 h-4" />
              }
            </button>
          </div>
        );
      },
    },
    {
      key: "estado_obra_id", header: "Estado",
      render: (item) => {
        const est = (item as any).estado_custom;
        return est ? (
          <span className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-medium text-white" style={{ backgroundColor: est.color }}>{est.nombre}</span>
        ) : <span className="text-xs text-surface-400">Sin estado</span>;
      },
    },
  ];

  const handleArchivar = async (obra: Obra) => {
    if (confirmArchive !== obra.id) { setConfirmArchive(obra.id); return; }
    setArchivando(obra.id); setConfirmArchive(null);
    const { error } = await (supabase.from("obras") as any)
      .update({ archivada: !(obra as any).archivada })
      .eq("id", obra.id);
    if (error) alert("Error al archivar: " + error.message);
    else fetchData();
    setArchivando(null);
  };

  const filteredData = estadoFilter ? data.filter((o) => o.estado_obra_id === estadoFilter) : data;

  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
              <Building2 className="w-5 h-5 text-brand-600" />
            </div>
            <div>
              <h1 className="text-xl font-display font-bold text-surface-900">Obras</h1>
              <p className="text-sm text-surface-500">Listado de todas las obras</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <select value={estadoFilter} onChange={(e) => setEstadoFilter(e.target.value)} className="px-3 py-2 text-sm bg-surface-100 border-0 rounded-lg text-surface-600 focus:outline-none focus:ring-2 focus:ring-brand-500/20">
              <option value="">Todos los estados</option>
              {estados.map((e) => <option key={e.id} value={e.id}>{e.nombre}</option>)}
            </select>
            {user?.role === "admin" && (
              <Link href="/obras/nueva" className="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 transition-colors">
                <Plus className="w-4 h-4" /> Nueva obra
              </Link>
            )}
          </div>
        </div>
        <div onClick={() => { if (confirmArchive) setConfirmArchive(null); }}>
        <DataTable data={filteredData} columns={columns} title="Todas las obras" loading={loading}
          searchPlaceholder="Buscar por nombre, cliente, dirección, localidad, presupuesto..."
          searchKeys={["nombre", "ubicacion", "estado", (o: any) => o.cliente?.nombre || "", (o: any) => o.direccion || "", (o: any) => o.localidad || "", (o: any) => o.num_presupuesto || ""]}
          canAdd={false} canEdit={false} canDelete={false} />
        </div>
      </div>
    </AppLayout>
  );
}