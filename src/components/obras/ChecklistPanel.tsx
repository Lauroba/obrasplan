"use client";

import { useState, useEffect, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import {
  Plus, Trash2, ChevronDown, ChevronRight, ChevronUp, GripVertical,
  Check, Circle, Loader2, X, User, Flag,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface ChecklistItem {
  id: string;
  checklist_id: string;
  texto: string;
  completado: boolean;
  completado_at: string | null;
  asignado_a: string | null;
  prioridad: "alta" | "media" | "baja";
  orden: number;
}

interface Checklist {
  id: string;
  obra_id: string;
  titulo: string;
  orden: number;
  items: ChecklistItem[];
}

interface Props {
  obraId: string;
  rrhh: { id: string; nombre: string }[];
  readOnly?: boolean;
}

const PRIORIDAD_COLORS: Record<string, { bg: string; text: string; dot: string; label: string }> = {
  alta: { bg: "bg-red-50", text: "text-red-700", dot: "bg-red-500", label: "Alta" },
  media: { bg: "bg-amber-50", text: "text-amber-700", dot: "bg-amber-400", label: "Media" },
  baja: { bg: "bg-emerald-50", text: "text-emerald-700", dot: "bg-emerald-400", label: "Baja" },
};

export default function ChecklistPanel({ obraId, rrhh, readOnly }: Props) {
  const supabase = createClient();
  const { user } = useAuthStore();
  const [checklists, setChecklists] = useState<Checklist[]>([]);
  const [loading, setLoading] = useState(true);
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [newChecklistTitle, setNewChecklistTitle] = useState("");
  const [addingChecklist, setAddingChecklist] = useState(false);
  const [newItemText, setNewItemText] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState<string | null>(null);
  const [editingItemId, setEditingItemId] = useState<string | null>(null);
  const [editingText, setEditingText] = useState("");
  const [editingClTitle, setEditingClTitle] = useState<string | null>(null);
  const [editingTitleText, setEditingTitleText] = useState("");

  const fetchChecklists = useCallback(async () => {
    const { data: cls } = await supabase.from("checklists").select("*").eq("obra_id", obraId).order("orden");
    const { data: items } = await supabase.from("checklist_items").select("*").in("checklist_id", (cls || []).map((c: any) => c.id)).order("orden");

    const result = (cls || []).map((c: any) => ({
      ...c,
      items: (items || []).filter((i: any) => i.checklist_id === c.id),
    }));
    setChecklists(result);
    // Expand all by default
    const exp: Record<string, boolean> = {};
    result.forEach((c: any) => { if (expanded[c.id] === undefined) exp[c.id] = true; else exp[c.id] = expanded[c.id]; });
    setExpanded((prev) => ({ ...exp, ...prev }));
    setLoading(false);
  }, [obraId]);

  useEffect(() => { fetchChecklists(); }, [fetchChecklists]);

  const addChecklist = async () => {
    if (!newChecklistTitle.trim()) return;
    setAddingChecklist(true);
    await (supabase.from("checklists") as any).insert({
      obra_id: obraId, titulo: newChecklistTitle.trim(), orden: checklists.length, created_by: user?.id,
    });
    setNewChecklistTitle("");
    setAddingChecklist(false);
    fetchChecklists();
  };

  const deleteChecklist = async (clId: string) => {
    if (!confirm("¿Eliminar esta checklist y todos sus items?")) return;
    await (supabase.from("checklists") as any).delete().eq("id", clId);
    fetchChecklists();
  };

  const addItem = async (clId: string) => {
    const text = (newItemText[clId] || "").trim();
    if (!text) return;
    const items = checklists.find((c) => c.id === clId)?.items || [];
    await (supabase.from("checklist_items") as any).insert({
      checklist_id: clId, texto: text, orden: items.length,
    });
    setNewItemText((prev) => ({ ...prev, [clId]: "" }));
    fetchChecklists();
  };

  const toggleItem = async (item: ChecklistItem) => {
    setSaving(item.id);
    const now = new Date().toISOString();
    await (supabase.from("checklist_items") as any).update({
      completado: !item.completado,
      completado_at: !item.completado ? now : null,
      completado_por: !item.completado ? user?.id : null,
    }).eq("id", item.id);
    // Update local state immediately
    setChecklists((prev) => prev.map((cl) => ({
      ...cl,
      items: cl.items.map((i) => i.id === item.id ? { ...i, completado: !i.completado, completado_at: !i.completado ? now : null } : i),
    })));
    setSaving(null);
  };

  const deleteItem = async (itemId: string) => {
    await (supabase.from("checklist_items") as any).delete().eq("id", itemId);
    fetchChecklists();
  };

  const moveItem = async (clId: string, itemId: string, direction: "up" | "down") => {
    const cl = checklists.find((c) => c.id === clId);
    if (!cl) return;
    const idx = cl.items.findIndex((i) => i.id === itemId);
    if (idx < 0) return;
    const swapIdx = direction === "up" ? idx - 1 : idx + 1;
    if (swapIdx < 0 || swapIdx >= cl.items.length) return;

    const newItems = [...cl.items];
    [newItems[idx], newItems[swapIdx]] = [newItems[swapIdx], newItems[idx]];

    // Update local state immediately
    setChecklists((prev) => prev.map((c) => c.id === clId ? { ...c, items: newItems } : c));

    // Save new order to DB
    await Promise.all(newItems.map((item, i) =>
      (supabase.from("checklist_items") as any).update({ orden: i }).eq("id", item.id)
    ));
  };

  const updateItemPriority = async (itemId: string, prioridad: string) => {
    await (supabase.from("checklist_items") as any).update({ prioridad }).eq("id", itemId);
    setChecklists((prev) => prev.map((cl) => ({
      ...cl,
      items: cl.items.map((i) => i.id === itemId ? { ...i, prioridad: prioridad as any } : i),
    })));
  };

  const updateItemAssignee = async (itemId: string, asignado_a: string | null) => {
    await (supabase.from("checklist_items") as any).update({ asignado_a: asignado_a || null }).eq("id", itemId);
    setChecklists((prev) => prev.map((cl) => ({
      ...cl,
      items: cl.items.map((i) => i.id === itemId ? { ...i, asignado_a } : i),
    })));
  };

  const saveItemText = async (itemId: string) => {
    const trimmed = editingText.trim();
    if (!trimmed) { setEditingItemId(null); return; }
    await (supabase.from("checklist_items") as any).update({ texto: trimmed }).eq("id", itemId);
    setChecklists((prev) => prev.map((cl) => ({
      ...cl,
      items: cl.items.map((i) => i.id === itemId ? { ...i, texto: trimmed } : i),
    })));
    setEditingItemId(null);
  };

  const saveClTitle = async (clId: string) => {
    const trimmed = editingTitleText.trim();
    if (!trimmed) { setEditingClTitle(null); return; }
    await (supabase.from("checklists") as any).update({ titulo: trimmed }).eq("id", clId);
    setChecklists((prev) => prev.map((cl) => cl.id === clId ? { ...cl, titulo: trimmed } : cl));
    setEditingClTitle(null);
  };

  const getProgress = (items: ChecklistItem[]) => {
    if (items.length === 0) return 0;
    return Math.round((items.filter((i) => i.completado).length / items.length) * 100);
  };

  const getStatus = (progress: number) => {
    if (progress === 0) return { label: "Sin iniciar", class: "text-surface-500 bg-surface-100" };
    if (progress === 100) return { label: "Completada", class: "text-emerald-700 bg-emerald-100" };
    return { label: "En progreso", class: "text-amber-700 bg-amber-100" };
  };

  if (loading) return <div className="flex justify-center py-8"><Loader2 className="w-5 h-5 text-brand-500 animate-spin" /></div>;

  return (
    <div className="space-y-4">
      {checklists.map((cl) => {
        const progress = getProgress(cl.items);
        const status = getStatus(progress);
        const isExpanded = expanded[cl.id] !== false;
        const completed = cl.items.filter((i) => i.completado).length;
        const total = cl.items.length;

        return (
          <div key={cl.id} className="border border-surface-200 rounded-xl overflow-hidden bg-white">
            {/* Header */}
            <div className="flex items-center gap-2 px-4 py-3 bg-surface-50 border-b border-surface-100">
              <button onClick={() => setExpanded((p) => ({ ...p, [cl.id]: !isExpanded }))} className="text-surface-400 hover:text-surface-600">
                {isExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
              </button>
              {!readOnly && editingClTitle === cl.id ? (
                <input type="text" value={editingTitleText} onChange={(e) => setEditingTitleText(e.target.value)}
                  onBlur={() => saveClTitle(cl.id)}
                  onKeyDown={(e) => { if (e.key === "Enter") saveClTitle(cl.id); if (e.key === "Escape") setEditingClTitle(null); }}
                  autoFocus className="flex-1 text-sm font-semibold px-2 py-0.5 bg-white border border-brand-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500/20" />
              ) : (
                <h3 onClick={() => { if (!readOnly) { setEditingClTitle(cl.id); setEditingTitleText(cl.titulo); } }}
                  className={cn("text-sm font-semibold flex-1", readOnly ? "text-surface-900" : "text-surface-900 cursor-pointer hover:text-brand-600")}>{cl.titulo}</h3>
              )}
              <span className={cn("text-[10px] font-medium px-2 py-0.5 rounded-full", status.class)}>{status.label}</span>
              <span className="text-[11px] text-surface-500 font-medium">{completed}/{total}</span>
              {!readOnly && (
                <button onClick={() => deleteChecklist(cl.id)} className="text-surface-300 hover:text-red-500 p-1"><Trash2 className="w-3.5 h-3.5" /></button>
              )}
            </div>

            {/* Progress bar */}
            <div className="px-4 pt-3">
              <div className="flex items-center gap-3">
                <div className="flex-1 h-2 bg-surface-100 rounded-full overflow-hidden">
                  <div className={cn("h-full rounded-full transition-all duration-500",
                    progress === 100 ? "bg-emerald-500" : progress > 0 ? "bg-amber-400" : "bg-surface-200"
                  )} style={{ width: `${progress}%` }} />
                </div>
                <span className={cn("text-xs font-bold min-w-[36px] text-right",
                  progress === 100 ? "text-emerald-600" : progress > 0 ? "text-amber-600" : "text-surface-400"
                )}>{progress}%</span>
              </div>
            </div>

            {/* Items */}
            {isExpanded && (
              <div className="px-4 pb-3 pt-2">
                {cl.items.length === 0 ? (
                  <p className="text-xs text-surface-400 py-3 text-center">Sin items. Añade el primero.</p>
                ) : (
                  <div className="space-y-1">
                    {cl.items.map((item) => {
                      const prio = PRIORIDAD_COLORS[item.prioridad];
                      const assignee = rrhh.find((r) => r.id === item.asignado_a);
                      return (
                        <div key={item.id} className={cn("flex items-start gap-2 py-2 px-2 rounded-lg group transition-colors",
                          item.completado ? "bg-surface-50" : "hover:bg-surface-50")}>
                          {/* Check */}
                          <button onClick={() => !readOnly && toggleItem(item)} disabled={readOnly || saving === item.id}
                            className={cn("mt-0.5 w-5 h-5 rounded-md border-2 flex items-center justify-center shrink-0 transition-all",
                              item.completado ? "bg-emerald-500 border-emerald-500 text-white" : "border-surface-300 hover:border-brand-400")}>
                            {saving === item.id ? <Loader2 className="w-3 h-3 animate-spin" /> : item.completado ? <Check className="w-3 h-3" /> : null}
                          </button>
                          {/* Content */}
                          <div className="flex-1 min-w-0">
                            {!readOnly && editingItemId === item.id ? (
                              <input type="text" value={editingText} onChange={(e) => setEditingText(e.target.value)}
                                onBlur={() => saveItemText(item.id)}
                                onKeyDown={(e) => { if (e.key === "Enter") saveItemText(item.id); if (e.key === "Escape") setEditingItemId(null); }}
                                autoFocus className="w-full text-sm px-2 py-1 bg-white border border-brand-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500/20" />
                            ) : (
                              <p onClick={() => { if (!readOnly) { setEditingItemId(item.id); setEditingText(item.texto); } }}
                                className={cn("text-sm cursor-pointer", item.completado ? "line-through text-surface-400" : "text-surface-900 hover:text-brand-600")}>{item.texto}</p>
                            )}
                            <div className="flex items-center gap-2 mt-1 flex-wrap">
                              {/* Priority */}
                              {!readOnly ? (
                                <select value={item.prioridad} onChange={(e) => updateItemPriority(item.id, e.target.value)}
                                  className={cn("text-[10px] font-medium px-1.5 py-0.5 rounded-md border-0 cursor-pointer", prio.bg, prio.text)}>
                                  <option value="alta">🔴 Alta</option>
                                  <option value="media">🟡 Media</option>
                                  <option value="baja">🟢 Baja</option>
                                </select>
                              ) : (
                                <span className={cn("text-[10px] font-medium px-1.5 py-0.5 rounded-md", prio.bg, prio.text)}>{prio.label}</span>
                              )}
                              {/* Assignee */}
                              {!readOnly ? (
                                <select value={item.asignado_a || ""} onChange={(e) => updateItemAssignee(item.id, e.target.value || null)}
                                  className="text-[10px] text-surface-500 bg-surface-100 px-1.5 py-0.5 rounded-md border-0 cursor-pointer">
                                  <option value="">Sin asignar</option>
                                  {rrhh.map((r) => <option key={r.id} value={r.id}>{r.nombre}</option>)}
                                </select>
                              ) : assignee ? (
                                <span className="text-[10px] text-surface-500 flex items-center gap-0.5"><User className="w-2.5 h-2.5" />{assignee.nombre}</span>
                              ) : null}
                            </div>
                          </div>
                          {/* Actions */}
                          {!readOnly && (
                            <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100">
                              <button onClick={() => moveItem(cl.id, item.id, "up")}
                                disabled={cl.items.indexOf(item) === 0}
                                className="p-1 text-surface-300 hover:text-surface-600 disabled:opacity-30 disabled:cursor-default">
                                <ChevronUp className="w-3.5 h-3.5" />
                              </button>
                              <button onClick={() => moveItem(cl.id, item.id, "down")}
                                disabled={cl.items.indexOf(item) === cl.items.length - 1}
                                className="p-1 text-surface-300 hover:text-surface-600 disabled:opacity-30 disabled:cursor-default">
                                <ChevronDown className="w-3.5 h-3.5" />
                              </button>
                              <button onClick={() => deleteItem(item.id)} className="p-1 text-surface-300 hover:text-red-500">
                                <X className="w-3.5 h-3.5" />
                              </button>
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                )}
                {/* Add item */}
                {!readOnly && (
                  <div className="flex items-center gap-2 mt-2 pt-2 border-t border-surface-100">
                    <input type="text" value={newItemText[cl.id] || ""} onChange={(e) => setNewItemText((p) => ({ ...p, [cl.id]: e.target.value }))}
                      onKeyDown={(e) => { if (e.key === "Enter") addItem(cl.id); }}
                      placeholder="Nuevo item..." className="flex-1 px-3 py-1.5 text-sm bg-surface-50 border border-surface-200 rounded-lg placeholder:text-surface-400 focus:outline-none focus:ring-1 focus:ring-brand-500/30" />
                    <button onClick={() => addItem(cl.id)} className="p-1.5 text-brand-600 hover:bg-brand-50 rounded-lg"><Plus className="w-4 h-4" /></button>
                  </div>
                )}
              </div>
            )}
          </div>
        );
      })}

      {/* Add checklist */}
      {!readOnly && (
        <div className="flex items-center gap-2">
          <input type="text" value={newChecklistTitle} onChange={(e) => setNewChecklistTitle(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter") addChecklist(); }}
            placeholder="Nueva checklist..." className="flex-1 px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-brand-500/20" />
          <button onClick={addChecklist} disabled={addingChecklist || !newChecklistTitle.trim()}
            className="flex items-center gap-1 px-3 py-2 text-sm font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">
            {addingChecklist ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />} Checklist
          </button>
        </div>
      )}

      {checklists.length === 0 && !loading && (
        <div className="text-center py-8 bg-surface-50 rounded-xl border border-surface-100">
          <Check className="w-8 h-8 text-surface-300 mx-auto mb-2" />
          <p className="text-sm text-surface-500">Sin checklists</p>
          <p className="text-xs text-surface-400 mt-1">Añade una checklist para hacer seguimiento del progreso</p>
        </div>
      )}
    </div>
  );
}
