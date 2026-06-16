"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Modal from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { Contact, Plus, Loader2, Pencil, Trash2, Users, Phone, Mail, Globe, Building2, ChevronDown, ChevronRight, FileText, Download } from "lucide-react";
import { cn } from "@/lib/utils/cn";

const TIPOS_CLIENTE = ["Empresa", "Comunidad", "Administración", "Constructora", "Particular", "Otro"];
const emptyCliente = { nombre: "", tipo_cliente: "", nif: "", telefono: "", email: "", direccion: "", web: "" };
const emptyContacto = { nombre: "", email: "", telefono: "", cargo: "", notas: "" };

export default function ClientesPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const isAdmin = user?.role === "admin";
  const [clientes, setClientes] = useState<any[]>([]);
  const [contactos, setContactos] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  // Modals
  const [clienteModal, setClienteModal] = useState(false);
  const [clienteForm, setClienteForm] = useState(emptyCliente);
  const [editingClienteId, setEditingClienteId] = useState<string | null>(null);
  const [contactoModal, setContactoModal] = useState(false);
  const [contactoForm, setContactoForm] = useState(emptyContacto);
  const [editingContactoId, setEditingContactoId] = useState<string | null>(null);
  const [contactoClienteId, setContactoClienteId] = useState<string>("");
  const [saving, setSaving] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [cR, ctR] = await Promise.all([
      supabase.from("clientes").select("*").eq("activo", true).order("nombre"),
      supabase.from("contactos").select("*").order("nombre"),
    ]);
    setClientes(cR.data || []);
    setContactos(ctR.data || []);
    setLoading(false);
  }, []);
  useEffect(() => { fetchData(); }, [fetchData]);

  const clienteContactos = (clienteId: string) => contactos.filter((c) => c.cliente_id === clienteId);

  const handleSaveCliente = async (e: React.FormEvent) => {
    e.preventDefault(); setSaving(true);
    const payload = { ...clienteForm };
    Object.keys(payload).forEach((k) => { if (!(payload as any)[k]) (payload as any)[k] = null; });
    if (editingClienteId) await (supabase.from("clientes") as any).update(payload).eq("id", editingClienteId);
    else await (supabase.from("clientes") as any).insert({ ...payload, activo: true });
    setSaving(false); setClienteModal(false); fetchData();
  };

  const handleSaveContacto = async (e: React.FormEvent) => {
    e.preventDefault(); setSaving(true);
    const payload = { ...contactoForm, cliente_id: contactoClienteId };
    Object.keys(payload).forEach((k) => { if (!(payload as any)[k]) (payload as any)[k] = null; });
    (payload as any).cliente_id = contactoClienteId; // ensure not null
    if (editingContactoId) await (supabase.from("contactos") as any).update(payload).eq("id", editingContactoId);
    else await (supabase.from("contactos") as any).insert({ ...payload, activo: true });
    setSaving(false); setContactoModal(false); fetchData();
  };

  const handleDeleteCliente = async (id: string) => {
    if (!confirm("¿Desactivar este cliente?")) return;
    await (supabase.from("clientes") as any).update({ activo: false }).eq("id", id);
    fetchData();
  };

  const handleToggleContacto = async (id: string, activo: boolean) => {
    await (supabase.from("contactos") as any).update({ activo: !activo }).eq("id", id);
    fetchData();
  };

  const filtered = clientes.filter((c) => !search || c.nombre?.toLowerCase().includes(search.toLowerCase()) || c.nif?.toLowerCase().includes(search.toLowerCase()));

  const ic = "w-full px-3 py-2 bg-surface-50 border border-surface-200 rounded-lg text-sm placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500";

  if (loading) return <AppLayout><div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div></AppLayout>;

  return (
    <AppLayout>
      <div className="max-w-5xl mx-auto animate-fade-in">
        {/* Header */}
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-blue-50 flex items-center justify-center"><Contact className="w-5 h-5 text-blue-600" /></div>
            <div><h1 className="text-xl font-display font-bold text-surface-900">Clientes</h1><p className="text-sm text-surface-500">{filtered.length} clientes · {contactos.length} contactos</p></div>
          </div>
          <div className="flex gap-2">
            <a href="/api/informes/clientes?format=pdf" target="_blank" className="flex items-center gap-1 px-3 py-2 text-xs font-medium text-violet-700 bg-violet-50 rounded-lg hover:bg-violet-100"><Download className="w-3.5 h-3.5" />PDF</a>
            {isAdmin && <button onClick={() => { setClienteForm(emptyCliente); setEditingClienteId(null); setClienteModal(true); }} className="flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600"><Plus className="w-4 h-4" />Nuevo cliente</button>}
          </div>
        </div>

        {/* Search */}
        <div className="mb-4"><input type="text" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Buscar cliente por nombre o CIF/NIF..." className={ic} /></div>

        {/* Client list with expandable contacts */}
        <div className="space-y-2">
          {filtered.map((cliente) => {
            const cts = clienteContactos(cliente.id);
            const isExpanded = expanded[cliente.id];
            return (
              <div key={cliente.id} className="card overflow-hidden">
                {/* Client row */}
                <div className="flex items-center gap-3 p-4 cursor-pointer hover:bg-surface-50" onClick={() => setExpanded((p) => ({ ...p, [cliente.id]: !isExpanded }))}>
                  <button className="text-surface-400">{isExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}</button>
                  <div className="w-9 h-9 rounded-lg bg-blue-100 flex items-center justify-center shrink-0"><Building2 className="w-4 h-4 text-blue-600" /></div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-surface-900">{cliente.nombre}</span>
                      {cliente.tipo_cliente && <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-surface-100 text-surface-500">{cliente.tipo_cliente}</span>}
                      {cliente.nif && <span className="text-[10px] font-mono text-surface-400">{cliente.nif}</span>}
                    </div>
                    <div className="flex items-center gap-3 text-xs text-surface-500 mt-0.5">
                      {cliente.telefono && <span className="flex items-center gap-0.5"><Phone className="w-3 h-3" />{cliente.telefono}</span>}
                      {cliente.email && <span className="flex items-center gap-0.5"><Mail className="w-3 h-3" />{cliente.email}</span>}
                      {cliente.web && <span className="flex items-center gap-0.5"><Globe className="w-3 h-3" />{cliente.web}</span>}
                    </div>
                  </div>
                  <span className="text-xs text-surface-400">{cts.length} contacto{cts.length !== 1 ? "s" : ""}</span>
                  {isAdmin && (
                    <div className="flex gap-1" onClick={(e) => e.stopPropagation()}>
                      <button onClick={() => { setClienteForm({ nombre: cliente.nombre, tipo_cliente: cliente.tipo_cliente || "", nif: cliente.nif || "", telefono: cliente.telefono || "", email: cliente.email || "", direccion: cliente.direccion || "", web: cliente.web || "" }); setEditingClienteId(cliente.id); setClienteModal(true); }} className="p-1.5 text-surface-400 hover:text-brand-600 rounded-lg hover:bg-surface-100"><Pencil className="w-3.5 h-3.5" /></button>
                      <button onClick={() => handleDeleteCliente(cliente.id)} className="p-1.5 text-surface-400 hover:text-red-600 rounded-lg hover:bg-red-50"><Trash2 className="w-3.5 h-3.5" /></button>
                    </div>
                  )}
                </div>

                {/* Contacts section */}
                {isExpanded && (
                  <div className="border-t border-surface-100 bg-surface-50/50 px-4 py-3">
                    <div className="flex items-center justify-between mb-2">
                      <p className="text-[10px] font-semibold text-surface-400 uppercase">Contactos</p>
                      {isAdmin && <button onClick={() => { setContactoForm(emptyContacto); setEditingContactoId(null); setContactoClienteId(cliente.id); setContactoModal(true); }} className="flex items-center gap-0.5 text-[10px] font-medium text-brand-600 hover:underline"><Plus className="w-3 h-3" />Añadir</button>}
                    </div>
                    {cts.length === 0 ? (
                      <p className="text-xs text-surface-400 py-2">Sin contactos</p>
                    ) : (
                      <div className="space-y-1.5">
                        {cts.map((ct) => (
                          <div key={ct.id} className={cn("flex items-center gap-3 p-2.5 bg-white rounded-lg border border-surface-100 group", !ct.activo && "opacity-50")}>
                            <div className="w-7 h-7 rounded-full bg-violet-100 flex items-center justify-center text-[10px] font-bold text-violet-700 shrink-0">{ct.nombre?.charAt(0)?.toUpperCase()}</div>
                            <div className="flex-1 min-w-0">
                              <span className={cn("text-sm font-medium", ct.activo ? "text-surface-900" : "text-surface-400 line-through")}>{ct.nombre}</span>
                              {ct.cargo && <span className="ml-2 text-[10px] text-surface-400">{ct.cargo}</span>}
                              <div className="flex items-center gap-3 text-[11px] text-surface-500 mt-0.5">
                                {ct.telefono && <span>{ct.telefono}</span>}
                                {ct.email && <span>{ct.email}</span>}
                              </div>
                              {ct.notas && <p className="text-[10px] text-surface-400 mt-0.5 italic">{ct.notas}</p>}
                            </div>
                            {isAdmin && (
                              <div className="flex gap-1 opacity-0 group-hover:opacity-100">
                                <button onClick={() => { setContactoForm({ nombre: ct.nombre, email: ct.email || "", telefono: ct.telefono || "", cargo: ct.cargo || "", notas: ct.notas || "" }); setEditingContactoId(ct.id); setContactoClienteId(ct.cliente_id); setContactoModal(true); }} className="p-1 text-surface-400 hover:text-brand-600"><Pencil className="w-3 h-3" /></button>
                                <button onClick={() => handleToggleContacto(ct.id, ct.activo)} className={cn("p-1", ct.activo ? "text-surface-400 hover:text-red-500" : "text-emerald-400 hover:text-emerald-600")}>{ct.activo ? <Trash2 className="w-3 h-3" /> : <Plus className="w-3 h-3" />}</button>
                              </div>
                            )}
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* Cliente Modal */}
      <Modal open={clienteModal} onClose={() => setClienteModal(false)} title={editingClienteId ? "Editar cliente" : "Nuevo cliente"}>
        <form onSubmit={handleSaveCliente} className="space-y-4">
          <div><label className="block text-sm font-medium text-surface-700 mb-1">Nombre *</label><input required value={clienteForm.nombre} onChange={(e) => setClienteForm({ ...clienteForm, nombre: e.target.value })} className={ic} /></div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Tipo</label><select value={clienteForm.tipo_cliente} onChange={(e) => setClienteForm({ ...clienteForm, tipo_cliente: e.target.value })} className={ic}><option value="">Sin tipo</option>{TIPOS_CLIENTE.map((t) => <option key={t} value={t}>{t}</option>)}</select></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1">CIF/NIF</label><input value={clienteForm.nif} onChange={(e) => setClienteForm({ ...clienteForm, nif: e.target.value })} placeholder="B12345678" className={ic} /></div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Teléfono</label><input value={clienteForm.telefono} onChange={(e) => setClienteForm({ ...clienteForm, telefono: e.target.value })} className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Email</label><input type="email" value={clienteForm.email} onChange={(e) => setClienteForm({ ...clienteForm, email: e.target.value })} className={ic} /></div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Dirección</label><input value={clienteForm.direccion} onChange={(e) => setClienteForm({ ...clienteForm, direccion: e.target.value })} className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Web</label><input value={clienteForm.web} onChange={(e) => setClienteForm({ ...clienteForm, web: e.target.value })} placeholder="www.ejemplo.com" className={ic} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <button type="button" onClick={() => setClienteModal(false)} className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving || !clienteForm.nombre} className="flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingClienteId ? "Guardar" : "Crear"}</button>
          </div>
        </form>
      </Modal>

      {/* Contacto Modal */}
      <Modal open={contactoModal} onClose={() => setContactoModal(false)} title={editingContactoId ? "Editar contacto" : "Nuevo contacto"}>
        <form onSubmit={handleSaveContacto} className="space-y-4">
          <div><label className="block text-sm font-medium text-surface-700 mb-1">Nombre *</label><input required value={contactoForm.nombre} onChange={(e) => setContactoForm({ ...contactoForm, nombre: e.target.value })} className={ic} /></div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Email</label><input type="email" value={contactoForm.email} onChange={(e) => setContactoForm({ ...contactoForm, email: e.target.value })} className={ic} /></div>
            <div><label className="block text-sm font-medium text-surface-700 mb-1">Teléfono</label><input value={contactoForm.telefono} onChange={(e) => setContactoForm({ ...contactoForm, telefono: e.target.value })} className={ic} /></div>
          </div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1">Cargo</label><input value={contactoForm.cargo} onChange={(e) => setContactoForm({ ...contactoForm, cargo: e.target.value })} placeholder="Director técnico, Administrador..." className={ic} /></div>
          <div><label className="block text-sm font-medium text-surface-700 mb-1">Notas</label><textarea value={contactoForm.notas} onChange={(e) => setContactoForm({ ...contactoForm, notas: e.target.value })} rows={2} className={ic + " resize-none"} /></div>
          <div className="flex justify-end gap-2 pt-2">
            <button type="button" onClick={() => setContactoModal(false)} className="px-4 py-2 text-sm text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200">Cancelar</button>
            <button type="submit" disabled={saving || !contactoForm.nombre} className="flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">{saving && <Loader2 className="w-4 h-4 animate-spin" />}{editingContactoId ? "Guardar" : "Crear"}</button>
          </div>
        </form>
      </Modal>
    </AppLayout>
  );
}
