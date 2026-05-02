"use client";

import { useState, useEffect, useRef, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import SignatureCanvas from "@/components/partes/SignatureCanvas";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import type { Obra, TipoTrabajo, RecursoHumano } from "@/lib/types/database";
import { ClipboardList, ArrowLeft, Loader2, Plus, Trash2, Save } from "lucide-react";
import Link from "next/link";

interface LineaForm {
  concepto: string;
  tipo_trabajo_id: string;
  fabricante: string;
  producto: string;
  unidades: string;
  cantidad: string;
}

const emptyLinea: LineaForm = { concepto: "", tipo_trabajo_id: "", fabricante: "", producto: "", unidades: "", cantidad: "" };

function NuevoParteContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const presetObra = searchParams.get("obra");
  const { user } = useAuthStore();
  const supabase = createClient();

  const [obras, setObras] = useState<Obra[]>([]);
  const [tiposTrabajo, setTiposTrabajo] = useState<TipoTrabajo[]>([]);
  const [rrhh, setRrhh] = useState<RecursoHumano[]>([]);
  const [saving, setSaving] = useState(false);

  const [form, setForm] = useState({
    obra_id: presetObra || "", fecha: new Date().toISOString().split("T")[0],
    jefe_obra: "", encargado_obra: "", responsable_empresa: user?.nombre || "",
    direccion: "", localidad: "", provincia: "",
    observaciones: "",
  });
  const [lineas, setLineas] = useState<LineaForm[]>([{ ...emptyLinea }]);
  const [firmaResponsable, setFirmaResponsable] = useState<string | null>(null);
  const [firmaCliente, setFirmaCliente] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([
      supabase.from("obras").select("*, cliente:clientes(nombre)").eq("archivada", false).order("nombre"),
      supabase.from("tipos_trabajo").select("*").eq("activo", true).order("nombre"),
      supabase.from("recursos_humanos").select("*").eq("activo", true).order("nombre"),
    ]).then(([o, t, r]) => {
      setObras((o.data as Obra[]) || []);
      setTiposTrabajo(t.data || []);
      setRrhh(r.data || []);
    });
  }, []);

  // When obra changes, auto-fill address from obra
  useEffect(() => {
    if (form.obra_id) {
      const obra = obras.find((o) => o.id === form.obra_id);
      if (obra) {
        setForm((f) => ({ ...f, direccion: f.direccion || obra.ubicacion || "", }));
      }
    }
  }, [form.obra_id, obras]);

  const addLinea = () => setLineas([...lineas, { ...emptyLinea }]);
  const removeLinea = (idx: number) => setLineas(lineas.filter((_, i) => i !== idx));
  const updateLinea = (idx: number, field: keyof LineaForm, value: string) => {
    setLineas(lineas.map((l, i) => i === idx ? { ...l, [field]: value } : l));
  };

  // When tipo_trabajo changes, auto-fill concepto
  const handleTipoChange = (idx: number, tipoId: string) => {
    const tipo = tiposTrabajo.find((t) => t.id === tipoId);
    updateLinea(idx, "tipo_trabajo_id", tipoId);
    if (tipo && !lineas[idx].concepto) {
      updateLinea(idx, "concepto", tipo.nombre);
    }
  };

  const handleSubmit = async (estado: "pendiente" | "firmado") => {
    if (!form.fecha) return;
    setSaving(true);

    // Determine if firmado
    const finalEstado = (firmaResponsable || firmaCliente) && estado === "firmado" ? "firmado" : "pendiente";

    const { data: parte, error } = await supabase.from("partes_diarios").insert({
      obra_id: form.obra_id || null,
      fecha: form.fecha,
      created_by: user?.id,
      jefe_obra: form.jefe_obra || null,
      encargado_obra: form.encargado_obra || null,
      responsable_empresa: form.responsable_empresa || null,
      direccion: form.direccion || null,
      localidad: form.localidad || null,
      provincia: form.provincia || null,
      observaciones: form.observaciones || null,
      firma_data: firmaResponsable,
      firma_cliente: firmaCliente,
      estado: finalEstado,
    }).select().single();

    if (error || !parte) {
      alert("Error al crear parte: " + (error?.message || ""));
      setSaving(false);
      return;
    }

    // Insert líneas
    const lineasValidas = lineas.filter((l) => l.concepto.trim());
    if (lineasValidas.length > 0) {
      await supabase.from("parte_lineas").insert(
        lineasValidas.map((l, i) => ({
          parte_id: parte.id, orden: i,
          concepto: l.concepto,
          tipo_trabajo_id: l.tipo_trabajo_id || null,
          fabricante: l.fabricante || null,
          producto: l.producto || null,
          unidades: l.unidades || null,
          cantidad: l.cantidad ? parseFloat(l.cantidad) : null,
        }))
      );
    }

    router.push(`/partes/${parte.id}`);
  };

  const ic = "w-full px-3 py-2 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";
  const icSm = "w-full px-2.5 py-1.5 bg-white border border-surface-200 rounded-md text-xs placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition-all";

  return (
    <AppLayout>
      <div className="max-w-4xl mx-auto animate-fade-in">
        {/* Header */}
        <div className="flex items-center gap-3 mb-6">
          <Link href="/partes" className="p-2 rounded-lg text-surface-400 hover:bg-surface-100"><ArrowLeft className="w-5 h-5" /></Link>
          <div className="w-10 h-10 rounded-lg bg-orange-50 flex items-center justify-center"><ClipboardList className="w-5 h-5 text-orange-600" /></div>
          <div><h1 className="text-xl font-display font-bold text-surface-900">Nuevo Parte</h1><p className="text-sm text-surface-500">Parte de trabajos realizados</p></div>
        </div>

        <div className="space-y-6">
          {/* Cabecera del parte */}
          <div className="card p-6">
            <h2 className="text-sm font-semibold text-surface-900 mb-4">Datos del parte</h2>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-medium text-surface-700 mb-1">Fecha *</label>
                <input type="date" value={form.fecha} onChange={(e) => setForm({ ...form, fecha: e.target.value })} required className={ic} />
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-700 mb-1">Obra</label>
                <select value={form.obra_id} onChange={(e) => setForm({ ...form, obra_id: e.target.value })} className={ic}>
                  <option value="">Sin obra</option>
                  {obras.map((o) => <option key={o.id} value={o.id}>{o.nombre}</option>)}
                </select>
              </div>
            </div>
            <div className="grid grid-cols-3 gap-4 mt-4">
              <div><label className="block text-xs font-medium text-surface-700 mb-1">Dirección</label><input type="text" value={form.direccion} onChange={(e) => setForm({ ...form, direccion: e.target.value })} placeholder="Dirección de la obra" className={ic} /></div>
              <div><label className="block text-xs font-medium text-surface-700 mb-1">Localidad</label><input type="text" value={form.localidad} onChange={(e) => setForm({ ...form, localidad: e.target.value })} className={ic} /></div>
              <div><label className="block text-xs font-medium text-surface-700 mb-1">Provincia</label><input type="text" value={form.provincia} onChange={(e) => setForm({ ...form, provincia: e.target.value })} className={ic} /></div>
            </div>
            <div className="grid grid-cols-3 gap-4 mt-4">
              <div><label className="block text-xs font-medium text-surface-700 mb-1">Jefe de obra</label>
                <select value={form.jefe_obra} onChange={(e) => setForm({ ...form, jefe_obra: e.target.value })} className={ic}>
                  <option value="">Seleccionar...</option>{rrhh.map((r) => <option key={r.id} value={r.nombre}>{r.nombre}</option>)}
                </select>
              </div>
              <div><label className="block text-xs font-medium text-surface-700 mb-1">Encargado de obra</label>
                <select value={form.encargado_obra} onChange={(e) => setForm({ ...form, encargado_obra: e.target.value })} className={ic}>
                  <option value="">Seleccionar...</option>{rrhh.map((r) => <option key={r.id} value={r.nombre}>{r.nombre}</option>)}
                </select>
              </div>
              <div><label className="block text-xs font-medium text-surface-700 mb-1">Responsable empresa</label>
                <input type="text" value={form.responsable_empresa} onChange={(e) => setForm({ ...form, responsable_empresa: e.target.value })} className={ic} />
              </div>
            </div>
          </div>

          {/* Relación de trabajos / materiales */}
          <div className="card p-6">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-sm font-semibold text-surface-900">Relación de Trabajos / Materiales</h2>
              <button type="button" onClick={addLinea} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-brand-600 bg-brand-50 rounded-lg hover:bg-brand-100">
                <Plus className="w-3.5 h-3.5" /> Añadir línea
              </button>
            </div>

            {/* Table header */}
            <div className="grid grid-cols-12 gap-2 px-2 mb-2">
              <div className="col-span-2 text-[10px] font-semibold text-surface-400 uppercase">Tipo</div>
              <div className="col-span-3 text-[10px] font-semibold text-surface-400 uppercase">Concepto</div>
              <div className="col-span-2 text-[10px] font-semibold text-surface-400 uppercase">Fabricante</div>
              <div className="col-span-2 text-[10px] font-semibold text-surface-400 uppercase">Producto</div>
              <div className="col-span-1 text-[10px] font-semibold text-surface-400 uppercase">Cant.</div>
              <div className="col-span-1 text-[10px] font-semibold text-surface-400 uppercase">Uds.</div>
              <div className="col-span-1"></div>
            </div>

            {/* Lines */}
            <div className="space-y-2">
              {lineas.map((linea, idx) => (
                <div key={idx} className="grid grid-cols-12 gap-2 items-center bg-surface-50 rounded-lg p-2 border border-surface-100">
                  <div className="col-span-2">
                    <select value={linea.tipo_trabajo_id} onChange={(e) => handleTipoChange(idx, e.target.value)} className={icSm}>
                      <option value="">Tipo...</option>
                      {tiposTrabajo.map((t) => <option key={t.id} value={t.id}>{t.nombre}</option>)}
                    </select>
                  </div>
                  <div className="col-span-3">
                    <input type="text" value={linea.concepto} onChange={(e) => updateLinea(idx, "concepto", e.target.value)} placeholder="Descripción del trabajo" className={icSm} />
                  </div>
                  <div className="col-span-2">
                    <input type="text" value={linea.fabricante} onChange={(e) => updateLinea(idx, "fabricante", e.target.value)} placeholder="Fabricante" className={icSm} />
                  </div>
                  <div className="col-span-2">
                    <input type="text" value={linea.producto} onChange={(e) => updateLinea(idx, "producto", e.target.value)} placeholder="Producto" className={icSm} />
                  </div>
                  <div className="col-span-1">
                    <input type="number" value={linea.cantidad} onChange={(e) => updateLinea(idx, "cantidad", e.target.value)} placeholder="0" step="any" className={icSm} />
                  </div>
                  <div className="col-span-1">
                    <input type="text" value={linea.unidades} onChange={(e) => updateLinea(idx, "unidades", e.target.value)} placeholder="uds" className={icSm} />
                  </div>
                  <div className="col-span-1 flex justify-center">
                    {lineas.length > 1 && (
                      <button type="button" onClick={() => removeLinea(idx)} className="p-1 rounded text-surface-400 hover:text-red-500">
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Observaciones */}
          <div className="card p-6">
            <h2 className="text-sm font-semibold text-surface-900 mb-3">Observaciones</h2>
            <textarea value={form.observaciones} onChange={(e) => setForm({ ...form, observaciones: e.target.value })}
              rows={4} placeholder="Observaciones, incidencias, notas..." className={ic + " resize-y"} />
          </div>

          {/* Firmas */}
          <div className="card p-6">
            <h2 className="text-sm font-semibold text-surface-900 mb-4">Firmas</h2>
            <div className="grid grid-cols-2 gap-6">
              <SignatureCanvas label="Cliente" value={firmaCliente} onChange={setFirmaCliente} />
              <SignatureCanvas label={`Responsable — ${form.responsable_empresa || "Empresa"}`} value={firmaResponsable} onChange={setFirmaResponsable} />
            </div>
          </div>

          {/* Actions */}
          <div className="flex items-center justify-between">
            <Link href="/partes" className="px-4 py-2.5 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</Link>
            <div className="flex items-center gap-3">
              <button onClick={() => handleSubmit("pendiente")} disabled={saving || !form.fecha}
                className="flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-surface-700 bg-surface-200 rounded-lg hover:bg-surface-300 disabled:opacity-60">
                {saving && <Loader2 className="w-4 h-4 animate-spin" />}
                <Save className="w-4 h-4" /> Guardar como pendiente
              </button>
              <button onClick={() => handleSubmit("firmado")} disabled={saving || !form.fecha || (!firmaResponsable && !firmaCliente)}
                className="flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-white bg-emerald-500 rounded-lg hover:bg-emerald-600 disabled:opacity-60">
                {saving && <Loader2 className="w-4 h-4 animate-spin" />}
                Guardar y firmar
              </button>
            </div>
          </div>
        </div>
      </div>
    </AppLayout>
  );
}

export default function NuevoPartePage() {
  return <Suspense><NuevoParteContent /></Suspense>;
}
