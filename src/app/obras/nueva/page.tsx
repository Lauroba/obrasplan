"use client";
import { useState, useEffect, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import type { Cliente, EstadoObra, Obra } from "@/lib/types/database";
import { Building2, Loader2, ArrowLeft } from "lucide-react";
import Link from "next/link";

const COLORS = [
  "#DC2626","#EF4444","#F97316","#F59E0B","#EAB308","#84CC16","#22C55E","#16A34A",
  "#10B981","#14B8A6","#06B6D4","#0EA5E9","#3B82F6","#2563EB","#6366F1","#4F46E5",
  "#8B5CF6","#7C3AED","#A855F7","#9333EA","#C026D3","#D946EF","#EC4899","#E11D48",
  "#B45309","#92400E","#78716C","#57534E","#374151","#1F2937","#0F172A","#065F46",
];

function NuevaObraContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const editId = searchParams.get("edit");
  const { user } = useAuthStore();
  const supabase = createClient();
  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [estados, setEstados] = useState<EstadoObra[]>([]);
  const [saving, setSaving] = useState(false);
  const [loadingEdit, setLoadingEdit] = useState(!!editId);
  const [form, setForm] = useState({ nombre: "", cliente_id: "", ubicacion: "", estado_obra_id: "", observaciones: "", color: COLORS[Math.floor(Math.random() * COLORS.length)] });

  useEffect(() => {
    Promise.all([
      supabase.from("clientes").select("*").eq("activo", true).order("nombre"),
      supabase.from("estados_obra").select("*").eq("activo", true).order("nombre"),
    ]).then(([c, e]) => {
      setClientes(c.data || []);
      setEstados(e.data || []);
      if (!editId) {
        const pendiente = (e.data || []).find((es: EstadoObra) => es.nombre.toLowerCase().includes("pendiente"));
        if (pendiente) setForm((f) => ({ ...f, estado_obra_id: pendiente.id }));
      }
    });

    // Load obra data if editing
    if (editId) {
      supabase.from("obras").select("*").eq("id", editId).single().then(({ data }) => {
        if (data) {
          setForm({
            nombre: data.nombre, cliente_id: data.cliente_id || "", ubicacion: data.ubicacion || "",
            estado_obra_id: data.estado_obra_id || "", observaciones: data.observaciones || "",
            color: data.color || COLORS[0],
          });
        }
        setLoadingEdit(false);
      });
    }
  }, [editId]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.nombre) return;
    setSaving(true);
    const payload = {
      nombre: form.nombre, cliente_id: form.cliente_id || null, ubicacion: form.ubicacion || null,
      estado_obra_id: form.estado_obra_id || null, observaciones: form.observaciones || null, color: form.color,
    };

    if (editId) {
      await supabase.from("obras").update(payload).eq("id", editId);
      router.push(`/obras/${editId}`);
    } else {
      const { data: obra } = await supabase.from("obras").insert({
        ...payload, created_by: user?.id, estado: "planificada", orden_gantt: 9999,
      }).select().single();
      if (obra) router.push(`/obras/${obra.id}`);
      else { alert("Error al crear obra"); setSaving(false); }
    }
  };

  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  if (loadingEdit) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;

  return (
    <AppLayout><div className="max-w-3xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6">
        <Link href={editId ? `/obras/${editId}` : "/obras"} className="p-2 rounded-lg text-surface-400 hover:bg-surface-100"><ArrowLeft className="w-5 h-5" /></Link>
        <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center"><Building2 className="w-5 h-5 text-brand-600" /></div>
        <div><h1 className="text-xl font-display font-bold text-surface-900">{editId ? "Editar Obra" : "Nueva Obra"}</h1></div>
      </div>
      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="card p-6">
          <h2 className="text-sm font-semibold text-surface-900 mb-4">Datos generales</h2>
          <div className="space-y-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre de la obra *</label><input type="text" required value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="Ej: Reforma Local Comercial" className={ic} /></div>
            <div className="grid grid-cols-2 gap-4">
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Cliente</label><select value={form.cliente_id} onChange={(e) => setForm({ ...form, cliente_id: e.target.value })} className={ic}><option value="">Sin cliente</option>{clientes.map((c) => <option key={c.id} value={c.id}>{c.nombre}</option>)}</select></div>
              <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Estado</label><select value={form.estado_obra_id} onChange={(e) => setForm({ ...form, estado_obra_id: e.target.value })} className={ic}><option value="">Sin estado</option>{estados.map((e) => <option key={e.id} value={e.id}>{e.nombre}</option>)}</select></div>
            </div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Ubicación</label><input type="text" value={form.ubicacion} onChange={(e) => setForm({ ...form, ubicacion: e.target.value })} placeholder="Dirección de la obra" className={ic} /></div>
            <div>
              <label className="block text-sm font-medium text-surface-700 mb-1.5">Color en el Gantt</label>
              <div className="flex items-center gap-1.5 flex-wrap">
                {COLORS.map((c) => (<button key={c} type="button" onClick={() => setForm({ ...form, color: c })}
                  className="w-7 h-7 rounded-full border-2 transition-all hover:scale-110"
                  style={{ backgroundColor: c, borderColor: form.color === c ? c : "transparent", transform: form.color === c ? "scale(1.25)" : "", boxShadow: form.color === c ? `0 0 0 3px ${c}30` : "none" }} />))}
              </div>
            </div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Observaciones</label><textarea value={form.observaciones} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} rows={3} placeholder="Notas adicionales..." className={ic + " resize-none"} /></div>
          </div>
        </div>
        <div className="flex items-center justify-end gap-3">
          <Link href={editId ? `/obras/${editId}` : "/obras"} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</Link>
          <button type="submit" disabled={saving || !form.nombre} className="flex items-center gap-2 px-6 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editId ? "Guardar cambios" : "Crear obra"}</button>
        </div>
      </form>
    </div></AppLayout>
  );
}

export default function NuevaObraPage() {
  return <Suspense><NuevaObraContent /></Suspense>;
}
