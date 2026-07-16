"use client";
import React from "react";
import { AlertTriangle } from "lucide-react";
import { logAuditErrorClient } from "@/lib/audit/logAuditError";

interface State { error: string | null }

/**
 * Evita que un error de render dentro del Planificador (ej. una fila de
 * Vista Personas u Obras con datos inconsistentes) tumbe toda la página
 * con "Application error: a client-side exception has occurred".
 *
 * A diferencia de un try/catch vacío, esto:
 *  - muestra el error real al usuario (no lo oculta),
 *  - permite reintentar sin recargar toda la app,
 *  - deja constancia en audit_log vía el sistema existente (logAuditErrorClient),
 *    para que quede trazado incluso si el usuario no reporta el fallo.
 */
export class PlanificadorErrorBoundary extends React.Component<
  { children: React.ReactNode; vista: string },
  State
> {
  constructor(props: { children: React.ReactNode; vista: string }) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(err: Error): State {
    return { error: err.message || "Error inesperado en el planificador" };
  }

  componentDidCatch(err: Error) {
    console.error(`[Planificador][${this.props.vista}]`, err);
    logAuditErrorClient({
      modulo: "planificacion",
      entidad: "asignaciones",
      accion: "otro",
      descripcion: `Error de render en Vista ${this.props.vista} del planificador`,
      errorDetalle: `${err.message || err}\n${err.stack || ""}`.slice(0, 2000),
    });
  }

  render() {
    if (this.state.error) {
      return (
        <div className="flex flex-col items-center justify-center h-full bg-red-50 rounded-xl border border-red-200 gap-3 p-6 min-h-[200px]">
          <AlertTriangle className="w-6 h-6 text-red-400" />
          <p className="text-xs font-semibold text-red-700 text-center max-w-sm">
            Ha ocurrido un error al mostrar esta vista: {this.state.error}
          </p>
          <p className="text-[11px] text-red-500 text-center max-w-sm">
            Se ha registrado el incidente. Puedes reintentar o cambiar de vista.
          </p>
          <button
            onClick={() => this.setState({ error: null })}
            className="px-3 py-1.5 text-xs text-red-600 border border-red-300 rounded-lg hover:bg-red-100"
          >
            Reintentar
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
