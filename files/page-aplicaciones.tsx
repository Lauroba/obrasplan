"use client";

import Link from "next/link";
import AppLayout from "@/components/layout/AppLayout";
import { LayoutGrid, Radar, ChevronRight } from "lucide-react";

const APPS = [
  {
    key: "georadar_interpretacion",
    nombre: "Interpretación de Georradar",
    descripcion: "Análisis de radargramas Proceq GS8000 Pro: detección de huecos y suministros, cálculo volumétrico Sanders, informe técnico asistido por IA.",
    href: "/aplicaciones/georadar",
    icon: Radar,
    activa: true,
  },
];

export default function AplicacionesPage() {
  return (
    <AppLayout>
      <div className="max-w-5xl mx-auto animate-fade-in">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
            <LayoutGrid className="w-5 h-5 text-brand-600" />
          </div>
          <div>
            <h1 className="text-xl font-display font-bold text-surface-900">Aplicaciones</h1>
            <p className="text-sm text-surface-500">Herramientas internas de ObrasPlan</p>
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {APPS.map((app) => (
            <Link key={app.key} href={app.href} className="card p-5 hover:border-brand-300 hover:shadow-md transition-all group">
              <div className="flex items-start gap-3">
                <div className="w-11 h-11 rounded-lg bg-brand-50 flex items-center justify-center shrink-0 group-hover:bg-brand-100 transition-colors">
                  <app.icon className="w-5 h-5 text-brand-600" />
                </div>
                <div className="flex-1 min-w-0">
                  <h2 className="text-sm font-semibold text-surface-900 mb-1">{app.nombre}</h2>
                  <p className="text-xs text-surface-500 leading-relaxed">{app.descripcion}</p>
                </div>
                <ChevronRight className="w-4 h-4 text-surface-300 group-hover:text-brand-500 transition-colors shrink-0 mt-1" />
              </div>
            </Link>
          ))}
        </div>

        <div className="mt-8 text-center text-xs text-surface-400">Más herramientas internas próximamente.</div>
      </div>
    </AppLayout>
  );
}
