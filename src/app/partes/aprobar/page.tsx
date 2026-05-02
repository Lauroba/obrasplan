"use client";

import AppLayout from "@/components/layout/AppLayout";
import { Construction } from "lucide-react";

export default function Page() {
  const pageName = "partes/aprobar".split("/").map(s => s.replace("[", "").replace("]", "")).join(" > ");
  return (
    <AppLayout>
      <div className="max-w-7xl mx-auto animate-fade-in">
        <div className="card flex flex-col items-center justify-center py-20">
          <div className="w-16 h-16 rounded-2xl bg-surface-100 flex items-center justify-center mb-4">
            <Construction className="w-8 h-8 text-surface-400" />
          </div>
          <h2 className="text-lg font-display font-bold text-surface-900">
            Página en desarrollo
          </h2>
          <p className="text-sm text-surface-500 mt-1 capitalize">{pageName}</p>
        </div>
      </div>
    </AppLayout>
  );
}
