"use client";
import AppLayout from "@/components/layout/AppLayout";
import Link from "next/link";
import { Warehouse, Package, Building2, Users2, ChevronRight, AlertTriangle, TrendingDown } from "lucide-react";
import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function AlmacenPage() {
  const supabase = createClient();
  const [alertas, setAlertas] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supabase.from("v_alertas_almacen" as any).select("*").limit(5)
      .then(({ data }) => { setAlertas(data || []); setLoading(false); });
  }, []);

  const cards = [
    { href: "/almacen/articulos",   icon: Package,    title: "Artículos",    desc: "Maestro de artículos, lotes y códigos" },
    { href: "/almacen/almacenes",   icon: Warehouse,  title: "Almacenes",    desc: "Gestión de almacenes y ubicaciones" },
    { href: "/almacen/proveedores", icon: Users2,     title: "Proveedores",  desc: "Directorio de proveedores" },
  ];

  return (
    <AppLayout>
      <div className="max-w-5xl mx-auto animate-fade-in">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center">
            <Warehouse className="w-5 h-5 text-brand-600" />
          </div>
          <div>
            <h1 className="text-xl font-display font-bold text-surface-900">Almacén</h1>
            <p className="text-sm text-surface-500">Gestión de stock y artículos</p>
          </div>
        </div>

        {!loading && alertas.length > 0 && (
          <div className="card p-4 mb-6 border-amber-200 bg-amber-50">
            <div className="flex items-center gap-2 mb-3">
              <AlertTriangle className="w-4 h-4 text-amber-600" />
              <span className="text-sm font-semibold text-amber-700">{alertas.length} alertas activas</span>
            </div>
            <div className="space-y-1.5">
              {alertas.map((a: any, i: number) => (
                <div key={i} className="flex items-center gap-2 text-xs text-amber-700">
                  {a.alerta_stock && <TrendingDown className="w-3 h-3" />}
                  <span>{a.nombre} — {a.almacen_nombre}</span>
                  {a.alerta_stock && <span className="badge bg-red-100 text-red-700">Stock bajo ({a.stock_qty})</span>}
                  {a.alerta_caducidad === "caducado" && <span className="badge bg-red-100 text-red-700">Caducado</span>}
                  {a.alerta_caducidad === "caduca_pronto" && <span className="badge bg-amber-100 text-amber-700">Caduca pronto</span>}
                </div>
              ))}
            </div>
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          {cards.map((c) => (
            <Link key={c.href} href={c.href} className="card p-5 hover:border-brand-300 hover:shadow-md transition-all group">
              <div className="flex items-start gap-3">
                <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center shrink-0 group-hover:bg-brand-100 transition-colors">
                  <c.icon className="w-5 h-5 text-brand-600" />
                </div>
                <div className="flex-1 min-w-0">
                  <h2 className="text-sm font-semibold text-surface-900 mb-1">{c.title}</h2>
                  <p className="text-xs text-surface-500">{c.desc}</p>
                </div>
                <ChevronRight className="w-4 h-4 text-surface-300 group-hover:text-brand-500 shrink-0 mt-1" />
              </div>
            </Link>
          ))}
        </div>
      </div>
    </AppLayout>
  );
}