"use client";
import React from "react";
import { AlertTriangle } from "lucide-react";

interface State { error: string | null }

export class GeoradarErrorBoundary extends React.Component<
  { children: React.ReactNode },
  State
> {
  constructor(props: { children: React.ReactNode }) {
    super(props);
    this.state = { error: null };
  }
  static getDerivedStateFromError(err: Error): State {
    return { error: err.message || "Error inesperado en el módulo" };
  }
  componentDidCatch(err: Error) {
    console.error("[GeoradarV2 Error]", err);
  }
  render() {
    if (this.state.error) {
      return (
        <div className="flex flex-col items-center justify-center h-full bg-red-50 rounded-xl border border-red-200 gap-3 p-6 min-h-[120px]">
          <AlertTriangle className="w-6 h-6 text-red-400" />
          <p className="text-xs font-semibold text-red-700 text-center max-w-xs">{this.state.error}</p>
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