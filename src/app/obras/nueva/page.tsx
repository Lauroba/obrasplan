"use client";
import { useState, useEffect, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import type { Cliente, EstadoObra } from "@/lib/types/database";
import { Building2, Loader2, ArrowLeft, X } from "lucide-react";
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
  const [tiposObra, setTiposObra] = useState<any[]>([]);
  const [rrhhList, setRrhhList] = useState<any[]>([]);
  const [tiposSeleccionados, setTiposSeleccionados] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [loadingEdit, setLoadingEdit] = useState(!!editId);
  const [form, setForm] = useState({
    nombre: "", cliente_id: "", estado_obra_id: "",
    direccion: "", localidad: "", provincia: "",
    num_presupuesto: "", num_factura: "",
    contacto_obra_nombre: "", contacto_obra_telefono: "", contacto_obra_email: "",
    responsable_obra_id: "",

    observaciones: "", color: COLORS[Math.floor(Math.random() * COLORS.length)]
  });

  useEffect(() => {
    Promise.all([
      supabase.from("clientes").select("*").eq("activo", true).order("nombre"),
      supabase.from("estados_obra").select("*").eq("activo", true).order("nombre"),
      supabase.from("tipos_obra").select("*").eq("activo", true).order("nombre").then(r => r).catch(() => ({ data: [] })),
      supabase.from("recursos_humanos").select("id, nombre").eq("activo", true).order("nombre"),
    ]).then(([c, e, t, r]) => {
      setClientes(c.data || []);
      setEstados(e.data || []);
      setTiposObra(t.data || []);
      setRrhhList(r.data || []);
      if (!editId) {
        const pendiente = (e.data || []).find((es: EstadoObra) => es.nombre.toLowerCase().includes("pendiente"));
        if (pendiente) setForm((f) => ({ ...f, estado_obra_id: pendiente.id }));
      }
    });
    if (editId) {
      supabase.from("obras").select("*, cliente:clientes(*)").eq("id", editId).single().then(async ({ data }) => {
        if (data) {
          setForm({
            nombre: data.nombre, cliente_id: data.cliente_id || "", estado_obra_id: data.estado_obra_id || "",
            direccion: data.direccion || "", localidad: data.localidad || "", provincia: data.provincia || "",
            num_presupuesto: data.num_presupuesto || "", num_factura: data.num_factura || "",
            contacto_obra_nombre: data.contacto_obra_nombre || "", contacto_obra_telefono: data.contacto_obra_telefono || "",
            contacto_obra_email: data.contacto_obra_email || "",
            responsable_obra_id: data.responsable_obra_id || "",

            observaciones: data.observaciones || "", color: data.color || COLORS[0],
          });
          const { data: tipos } = await supabase.from("obra_tipos_obra").select("tipo_obra_id").eq("obra_id", editId);
          if (tipos) setTiposSeleccionados(tipos.map((t: any) => t.tipo_obra_id));
        }
        setLoadingEdit(false);
      });
    }
  }, [editId]);

  const handleClienteChange = (clienteId: string) => {
    const cliente = clientes.find((c) => c.id === clienteId);
    setForm((f) => ({
      ...f, cliente_id: clienteId,
      contacto_obra_nombre: f.contacto_obra_nombre || cliente?.contacto || "",
      contacto_obra_telefono: f.contacto_obra_telefono || cliente?.telefono || "",
      contacto_obra_email: f.contacto_obra_email || (cliente as any)?.email || "",
    }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); if (!form.nombre) return; setSaving(true);
    try {
      const payload: any = {
        nombre: form.nombre, cliente_id: form.cliente_id || null,
        ubicacion: form.direccion || null, estado_obra_id: form.estado_obra_id || null,
        observaciones: form.observaciones || null, color: form.color,
        responsable_obra_id: form.responsable_obra_id || null,

      };
      if (form.direccion) payload.direccion = form.direccion;
      if (form.localidad) payload.localidad = form.localidad;
      if (form.provincia) payload.provincia = form.provincia;
      if (form.num_presupuesto) payload.num_presupuesto = form.num_presupuesto;
      if (form.num_factura) payload.num_factura = form.num_factura;
      if (form.contacto_obra_nombre) payload.contacto_obra_nombre = form.contacto_obra_nombre;
      if (form.contacto_obra_telefono) payload.contacto_obra_telefono = form.contacto_obra_telefono;
      if (form.contacto_obra_email) payload.contacto_obra_email = form.contacto_obra_email;

      let obraId = editId;
      if (editId) {
        const { error } = await (supabase.from("obras") as any).update(payload).eq("id", editId);
        if (error) throw error;
      } else {
        const { data: obra, error } = await (supabase.from("obras") as any)
          .insert({ ...payload, created_by: user?.id, estado: "planificada", orden_gantt: 9999 })
          .select().single();
        if (error) throw error;
        obraId = obra.id;
      }

      if (obraId) {
        await (supabase.from("obra_tipos_obra") as any).delete().eq("obra_id", obraId);
        if (tiposSeleccionados.length > 0) {
          await (supabase.from("obra_tipos_obra") as any).insert(
            tiposSeleccionados.map((tipoId) => ({ obra_id: obraId, tipo_obra_id: tipoId }))
          );
        }
      }
      router.push(`/obras/${obraId}`);
    } catch (err: any) {
      alert("Error al guardar: " + (err?.message || err));
      setSaving(false);
    }
  };

  const ic = "w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  if (loadingEdit) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;

  const selectedCliente = clientes.find((c) => c.id === form.cliente_id);

  return (
    <AppLayout><div className="max-w-3xl mx-auto animate-fade-in">
      <div className="flex items-center gap-3 mb-6">
        <Link href={editId ? `/obras/${editId}` : "/obras"} className="p-2 rounded-lg text-surface-400 hover:bg-surface-100"><ArrowLeft className="w-5 h-5" /></Link>
        <div className="w-10 h-10 rounded-lg bg-brand-50 flex items-center justify-center"><Building2 className="w-5 h-5 text-brand-600" /></div>
        <h1 className="text-xl font-display font-bold text-surface-900">{editId ? "Editar Obra" : "Nueva Obra"}</h1>
      </div>
      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="card p-6 space-y-4">
          <h2 className="text-sm font-semibold text-surface-900">Datos generales</h2>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nombre *</label><input type="text" required value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} placeholder="Ej: Reforma Local" className={ic} /></div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Cliente</label><select value={form.cliente_id} onChange={(e) => handleClienteChange(e.target.value)} className={ic}><option value="">Sin cliente</option>{clientes.map((c) => <option key={c.id} value={c.id}>{c.nombre}</option>)}</select></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Estado</label><select value={form.estado_obra_id} onChange={(e) => setForm({ ...form, estado_obra_id: e.target.value })} className={ic}><option value="">Sin estado</option>{estados.map((e) => <option key={e.id} value={e.id}>{e.nombre}</option>)}</select></div>
          </div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Responsable de obra</label>
            <select value={form.responsable_obra_id} onChange={(e) => setForm({ ...form, responsable_obra_id: e.target.value })} className={ic}>
              <option value="">Sin responsable</option>
              {rrhhList.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-surface-700 mb-1.5">Tipos de obra</label>
            <div className="flex flex-wrap gap-1.5">
              {tiposObra.map((t) => {
                const selected = tiposSeleccionados.includes(t.id);
                return (
                  <button key={t.id} type="button" onClick={() => setTiposSeleccionados(selected ? tiposSeleccionados.filter((x: string) => x !== t.id) : [...tiposSeleccionados, t.id])}
                    className={`flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-medium transition-all border ${selected ? "bg-brand-500 text-white border-brand-500" : "bg-white text-surface-600 border-surface-200 hover:border-brand-300"}`}>
                    {t.nombre}
                    {selected && <X className="w-3 h-3" />}
                  </button>
                );
              })}
              {tiposObra.length === 0 && <p className="text-xs text-surface-400">Créalos en Maestros → Tipos de Obra</p>}
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nº Presupuesto</label><input type="text" value={form.num_presupuesto} onChange={(e) => setForm({ ...form, num_presupuesto: e.target.value })} placeholder="P-2026-001" className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Nº Factura</label><input type="text" value={form.num_factura} onChange={(e) => setForm({ ...form, num_factura: e.target.value })} placeholder="F-2026-001" className={ic} /></div>
          </div>
        </div>

        <div className="card p-6 space-y-4">
          <h2 className="text-sm font-semibold text-surface-900">Dirección de la obra</h2>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Dirección</label><input type="text" value={form.direccion} onChange={(e) => setForm({ ...form, direccion: e.target.value })} placeholder="Calle, número..." className={ic} /></div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Localidad</label><input type="text" value={form.localidad} onChange={(e) => setForm({ ...form, localidad: e.target.value })} placeholder="Ciudad" className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Provincia</label><input type="text" value={form.provincia} onChange={(e) => setForm({ ...form, provincia: e.target.value })} placeholder="Provincia" className={ic} /></div>
          </div>
        </div>

        <div className="card p-6 space-y-4">
          <h2 className="text-sm font-semibold text-surface-900">Contacto</h2>
          {selectedCliente && (
            <div className="p-3 bg-surface-50 rounded-lg border border-surface-100">
              <p className="text-[10px] font-semibold text-surface-400 uppercase mb-1">Datos del cliente (del maestro)</p>
              <p className="text-sm text-surface-700">{selectedCliente.nombre} · {selectedCliente.telefono || "—"} · {(selectedCliente as any).email || "—"}</p>
            </div>
          )}
          <p className="text-xs text-surface-400">El contacto de obra se copia del cliente pero se puede cambiar:</p>
          <div className="grid grid-cols-3 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Contacto obra</label><input type="text" value={form.contacto_obra_nombre} onChange={(e) => setForm({ ...form, contacto_obra_nombre: e.target.value })} placeholder="Nombre" className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Teléfono</label><input type="tel" value={form.contacto_obra_telefono} onChange={(e) => setForm({ ...form, contacto_obra_telefono: e.target.value })} placeholder="Teléfono" className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Email</label><input type="email" value={form.contacto_obra_email} onChange={(e) => setForm({ ...form, contacto_obra_email: e.target.value })} placeholder="email@..." className={ic} /></div>
          </div>
        </div>

        {/* Flags especiales */}
        

        <div className="card p-6 space-y-4">
          <h2 className="text-sm font-semibold text-surface-900">Apariencia</h2>
          <div>
            <label className="block text-sm font-medium text-surface-700 mb-1.5">Color en el Gantt</label>
            <div className="flex items-center gap-1.5 flex-wrap">{COLORS.map((c) => (<button key={c} type="button" onClick={() => setForm({ ...form, color: c })} className="w-7 h-7 rounded-full border-2 transition-all hover:scale-110" style={{ backgroundColor: c, borderColor: form.color === c ? c : "transparent", transform: form.color === c ? "scale(1.25)" : "", boxShadow: form.color === c ? `0 0 0 3px ${c}30` : "none" }} />))}</div>
          </div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1.5">Observaciones</label><textarea value={form.observaciones} onChange={(e) => setForm({ ...form, observaciones: e.target.value })} rows={3} placeholder="Notas..." className={ic + " resize-none"} /></div>
        </div>

        <div className="flex items-center justify-end gap-3">
          <Link href={editId ? `/obras/${editId}` : "/obras"} className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</Link>
          <button type="submit" disabled={saving || !form.nombre} className="flex items-center gap-2 px-6 py-2.5 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editId ? "Guardar" : "Crear obra"}</button>
        </div>
      </form>
    </div></AppLayout>
  );
}

export default function NuevaObraPage() {
  return <Suspense><NuevaObraContent /></Suspense>;
}