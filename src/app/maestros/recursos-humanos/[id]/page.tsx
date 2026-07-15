"use client";

import { useState, useEffect, useCallback } from "react";
import { useParams, useRouter } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import { createClient } from "@/lib/supabase/client";
import { usePermissions } from "@/hooks/usePermissions";
import type { Asignacion } from "@/lib/types/database";
import {
  ArrowLeft, Pencil, Loader2, Users, UserCheck, UserX,
  CalendarDays, CalendarOff, CheckCircle2, XCircle, Building2,
  ExternalLink, Phone, Mail, Briefcase, ShieldCheck,
} from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils/cn";

// ── Tipos locales ─────────────────────────────────────────────────────────────

interface RHDetalle {
  id: string;
  nombre: string;
  perfil: string | null;
  telefono: string | null;
  foto_url: string | null;
  activo: boolean;
  asignable: boolean;
  fecha_inicio: string | null;
  fecha_fin: string | null;
  created_at: string;
  // Enriquecidos desde users
  email?: string;
  user_activo?: boolean;
  user_rol_nombre?: string;
}

interface AsignacionHistorica {
  id: string;
  fecha_inicio: string;
  fecha_fin: string;
  observaciones: string | null;
  obra: {
    id: string;
    nombre: string;
    color: string | null;
    estado_custom?: { nombre: string; color: string } | null;
  } | null;
}

type Tab = "detalle" | "asignaciones";

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmtFecha(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-[11px] font-semibold text-surface-400 uppercase tracking-wider mb-1">{label}</p>
      <div className="text-sm text-surface-900">{children}</div>
    </div>
  );
}

// ── Componente principal ──────────────────────────────────────────────────────

export default function RrhhDetallePage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { isAdmin, canDo, permisosLoaded } = usePermissions();

  const puedeVer    = isAdmin || canDo("maestros_rrhh", "ver");
  const puedeEditar = isAdmin || canDo("maestros_rrhh", "editar");
  const puedeVerObras = isAdmin || canDo("obras", "ver");

  const supabase = createClient();
  const [trabajador, setTrabajador] = useState<RHDetalle | null>(null);
  const [asignaciones, setAsignaciones] = useState<AsignacionHistorica[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingAsig, setLoadingAsig] = useState(false);
  const [error, setError] = useState("");
  const [tab, setTab] = useState<Tab>("detalle");

  // ── Cargar datos del trabajador ─────────────────────────────────────────────
  const fetchTrabajador = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const { data: r, error: e } = await supabase
        .from("recursos_humanos")
        .select("*")
        .eq("id", id)
        .single();
      if (e || !r) { setError("Trabajador no encontrado."); setLoading(false); return; }

      // Enriquecer con datos del usuario (email, rol, activo)
      const { data: u } = await supabase
        .from("users")
        .select("id, email, activo, rol_id")
        .eq("recurso_id", id)
        .maybeSingle();

      let rolNombre = "Sin rol";
      if (u?.rol_id) {
        const { data: rol } = await supabase
          .from("roles").select("nombre").eq("id", u.rol_id).single();
        rolNombre = rol?.nombre || "Sin rol";
      }

      setTrabajador({
        ...r,
        email: u?.email,
        user_activo: u?.activo ?? r.activo,
        user_rol_nombre: rolNombre,
      });
    } catch {
      setError("Error al cargar el trabajador.");
    }
    setLoading(false);
  }, [id]);

  // ── Cargar asignaciones históricas (solo al activar la pestaña) ─────────────
  const fetchAsignaciones = useCallback(async () => {
    setLoadingAsig(true);
    const { data } = await supabase
      .from("asignaciones")
      .select(`
        id,
        fecha_inicio,
        fecha_fin,
        observaciones,
        obra:obras (
          id,
          nombre,
          color,
          estado_custom:estados_obra ( nombre, color )
        )
      `)
      .eq("recurso_tipo", "humano")
      .eq("recurso_id", id)
      .order("fecha_inicio", { ascending: false });

    setAsignaciones((data as any) || []);
    setLoadingAsig(false);
  }, [id]);

  useEffect(() => { fetchTrabajador(); }, [fetchTrabajador]);
  useEffect(() => {
    if (tab === "asignaciones") fetchAsignaciones();
  }, [tab, fetchAsignaciones]);

  // ── Guards ─────────────────────────────────────────────────────────────────
  if (!permisosLoaded || loading) {
    return (
      <AppLayout>
        <div className="flex items-center justify-center h-64">
          <Loader2 className="w-8 h-8 text-brand-500 animate-spin" />
        </div>
      </AppLayout>
    );
  }
  if (!puedeVer) {
    return (
      <AppLayout>
        <div className="text-center py-20">
          <p className="text-surface-500">No tienes permisos para ver esta ficha.</p>
        </div>
      </AppLayout>
    );
  }
  if (error || !trabajador) {
    return (
      <AppLayout>
        <div className="text-center py-20">
          <p className="text-red-500">{error || "Trabajador no encontrado."}</p>
          <Link href="/maestros/recursos-humanos" className="text-brand-600 text-sm mt-3 inline-block hover:underline">
            ← Volver al listado
          </Link>
        </div>
      </AppLayout>
    );
  }

  const initials = trabajador.nombre.split(" ").map((w) => w[0]).join("").slice(0, 2).toUpperCase();

  // Agrupar asignaciones por obra para la tabla (una fila por asignación)
  // Si hay múltiples asignaciones para la misma obra, cada una tiene su fila

  return (
    <AppLayout>
      <div className="max-w-4xl mx-auto animate-fade-in">
        {/* ── Cabecera ───────────────────────────────────────────────────── */}
        <div className="flex items-center gap-3 mb-6">
          <Link
            href="/maestros/recursos-humanos"
            className="p-2 rounded-lg text-surface-400 hover:bg-surface-100 hover:text-surface-700 transition-colors"
          >
            <ArrowLeft className="w-5 h-5" />
          </Link>
          <div className="flex-1 min-w-0">
            <h1 className="text-xl font-display font-bold text-surface-900 truncate">{trabajador.nombre}</h1>
            {trabajador.perfil && (
              <p className="text-sm text-surface-500">{trabajador.perfil}</p>
            )}
          </div>
          {puedeEditar && (
            <Link
              href={`/maestros/recursos-humanos?edit=${id}`}
              className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-500 rounded-lg hover:bg-brand-600 transition-colors"
            >
              <Pencil className="w-4 h-4" />
              Editar
            </Link>
          )}
        </div>

        {/* ── Pestañas ───────────────────────────────────────────────────── */}
        <div className="flex border-b border-surface-200 mb-6 gap-1">
          {(["detalle", "asignaciones"] as Tab[]).map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={cn(
                "px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors capitalize",
                tab === t
                  ? "border-brand-500 text-brand-600"
                  : "border-transparent text-surface-500 hover:text-surface-700"
              )}
            >
              {t === "detalle" ? "Detalle" : "Asignaciones"}
            </button>
          ))}
        </div>

        {/* ════════════════════════════════════════════════════════════════ */}
        {/* PESTAÑA DETALLE                                                  */}
        {/* ════════════════════════════════════════════════════════════════ */}
        {tab === "detalle" && (
          <div className="space-y-6">
            {/* Foto + datos principales */}
            <div className="card p-6">
              <div className="flex items-start gap-6">
                {/* Avatar */}
                <div className="shrink-0">
                  {trabajador.foto_url ? (
                    <img
                      src={trabajador.foto_url}
                      alt={trabajador.nombre}
                      className="w-20 h-20 rounded-2xl object-cover border-2 border-surface-200"
                    />
                  ) : (
                    <div className="w-20 h-20 rounded-2xl bg-brand-100 flex items-center justify-center text-brand-700 text-2xl font-bold border-2 border-surface-200">
                      {initials}
                    </div>
                  )}
                </div>

                {/* Campos principales */}
                <div className="flex-1 grid grid-cols-1 sm:grid-cols-2 gap-5">
                  <Field label="Nombre completo">
                    <span className="font-semibold">{trabajador.nombre}</span>
                  </Field>

                  <Field label="Perfil / Puesto">
                    <span className="flex items-center gap-1.5">
                      <Briefcase className="w-3.5 h-3.5 text-surface-400 shrink-0" />
                      {trabajador.perfil || "—"}
                    </span>
                  </Field>

                  <Field label="Teléfono">
                    <span className="flex items-center gap-1.5">
                      <Phone className="w-3.5 h-3.5 text-surface-400 shrink-0" />
                      {trabajador.telefono || "—"}
                    </span>
                  </Field>

                  <Field label="Email de acceso">
                    <span className="flex items-center gap-1.5">
                      <Mail className="w-3.5 h-3.5 text-surface-400 shrink-0" />
                      {trabajador.email || "—"}
                    </span>
                  </Field>
                </div>
              </div>
            </div>

            {/* Acceso y rol */}
            <div className="card p-6">
              <h2 className="text-sm font-semibold text-surface-900 mb-4 flex items-center gap-2">
                <ShieldCheck className="w-4 h-4 text-brand-500" />
                Acceso a la aplicación
              </h2>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
                <Field label="Rol">
                  <span className={cn(
                    "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-semibold",
                    trabajador.user_rol_nombre === "Administrador"
                      ? "bg-brand-100 text-brand-700"
                      : "bg-surface-100 text-surface-700"
                  )}>
                    {trabajador.user_rol_nombre || "Sin rol"}
                  </span>
                </Field>

                <Field label="Estado del acceso">
                  {trabajador.user_activo !== false ? (
                    <span className="flex items-center gap-1.5 text-emerald-700">
                      <UserCheck className="w-4 h-4" />
                      Activo — puede iniciar sesión
                    </span>
                  ) : (
                    <span className="flex items-center gap-1.5 text-red-600">
                      <UserX className="w-4 h-4" />
                      Sin acceso
                    </span>
                  )}
                </Field>
              </div>
            </div>

            {/* Disponibilidad en planificador */}
            <div className="card p-6">
              <h2 className="text-sm font-semibold text-surface-900 mb-4 flex items-center gap-2">
                <CalendarDays className="w-4 h-4 text-violet-500" />
                Disponibilidad en planificador
              </h2>
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-5">
                <Field label="Fecha inicio">
                  <span className="flex items-center gap-1.5">
                    <CalendarDays className="w-3.5 h-3.5 text-surface-400 shrink-0" />
                    {fmtFecha(trabajador.fecha_inicio)}
                  </span>
                </Field>

                <Field label="Fecha fin">
                  <span className="flex items-center gap-1.5">
                    <CalendarOff className="w-3.5 h-3.5 text-surface-400 shrink-0" />
                    {trabajador.fecha_fin ? fmtFecha(trabajador.fecha_fin) : "Sin límite"}
                  </span>
                </Field>

                <Field label="Asignable en planificación">
                  {trabajador.asignable !== false ? (
                    <span className="flex items-center gap-1.5 text-emerald-700">
                      <CheckCircle2 className="w-4 h-4" />
                      Sí
                    </span>
                  ) : (
                    <span className="flex items-center gap-1.5 text-red-500">
                      <XCircle className="w-4 h-4" />
                      No
                    </span>
                  )}
                </Field>
              </div>
            </div>
          </div>
        )}

        {/* ════════════════════════════════════════════════════════════════ */}
        {/* PESTAÑA ASIGNACIONES                                             */}
        {/* ════════════════════════════════════════════════════════════════ */}
        {tab === "asignaciones" && (
          <div className="card overflow-hidden">
            {loadingAsig ? (
              <div className="flex items-center justify-center py-16">
                <Loader2 className="w-7 h-7 text-brand-500 animate-spin" />
              </div>
            ) : asignaciones.length === 0 ? (
              <div className="text-center py-16">
                <Building2 className="w-10 h-10 text-surface-300 mx-auto mb-3" />
                <p className="text-sm text-surface-500">
                  Este trabajador todavía no tiene asignaciones registradas.
                </p>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-surface-200 bg-surface-50">
                      <th className="text-left text-[11px] font-semibold text-surface-400 uppercase tracking-wider px-4 py-3">
                        Fecha inicio
                      </th>
                      <th className="text-left text-[11px] font-semibold text-surface-400 uppercase tracking-wider px-4 py-3">
                        Fecha fin
                      </th>
                      <th className="text-left text-[11px] font-semibold text-surface-400 uppercase tracking-wider px-4 py-3">
                        Obra
                      </th>
                      <th className="text-left text-[11px] font-semibold text-surface-400 uppercase tracking-wider px-4 py-3">
                        Estado
                      </th>
                      {asignaciones.some((a) => a.observaciones) && (
                        <th className="text-left text-[11px] font-semibold text-surface-400 uppercase tracking-wider px-4 py-3">
                          Notas
                        </th>
                      )}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-surface-100">
                    {asignaciones.map((a) => (
                      <tr key={a.id} className="hover:bg-surface-50 transition-colors">
                        <td className="px-4 py-3 text-surface-700 whitespace-nowrap">
                          {fmtFecha(a.fecha_inicio)}
                        </td>
                        <td className="px-4 py-3 text-surface-700 whitespace-nowrap">
                          {fmtFecha(a.fecha_fin)}
                        </td>
                        <td className="px-4 py-3">
                          {a.obra ? (
                            puedeVerObras ? (
                              <Link
                                href={`/obras/${a.obra.id}`}
                                className="flex items-center gap-2 group"
                              >
                                <span
                                  className="w-2.5 h-2.5 rounded-full shrink-0"
                                  style={{ backgroundColor: a.obra.color || "#DC2626" }}
                                />
                                <span className="font-medium text-surface-900 group-hover:text-brand-600 transition-colors">
                                  {a.obra.nombre}
                                </span>
                                <ExternalLink className="w-3 h-3 text-surface-300 opacity-0 group-hover:opacity-100 transition-opacity shrink-0" />
                              </Link>
                            ) : (
                              <span className="flex items-center gap-2">
                                <span
                                  className="w-2.5 h-2.5 rounded-full shrink-0"
                                  style={{ backgroundColor: a.obra.color || "#DC2626" }}
                                />
                                <span className="font-medium text-surface-900">
                                  {a.obra.nombre}
                                </span>
                              </span>
                            )
                          ) : (
                            <span className="text-surface-400 italic">Obra eliminada</span>
                          )}
                        </td>
                        <td className="px-4 py-3">
                          {a.obra?.estado_custom ? (
                            <span
                              className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold text-white"
                              style={{ backgroundColor: a.obra.estado_custom.color || "#6B7280" }}
                            >
                              {a.obra.estado_custom.nombre}
                            </span>
                          ) : (
                            <span className="text-surface-400">—</span>
                          )}
                        </td>
                        {asignaciones.some((x) => x.observaciones) && (
                          <td className="px-4 py-3 text-surface-500 text-xs max-w-xs truncate">
                            {a.observaciones || "—"}
                          </td>
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>
                <div className="px-4 py-2 border-t border-surface-100 bg-surface-50">
                  <p className="text-[11px] text-surface-400">
                    {asignaciones.length} asignación{asignaciones.length !== 1 ? "es" : ""} en total
                  </p>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </AppLayout>
  );
}
