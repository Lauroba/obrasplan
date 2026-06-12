"use client";

import { useState, useRef, useEffect } from "react";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { FileText, Plus, Save, X, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface Nota {
  id: string;
  obra_id: string;
  fecha: string;
  texto: string;
  created_by: string;
  created_at: string;
  updated_by: string;
  updated_at: string;
  creator_nombre?: string;
}

interface Props {
  obraId: string;
  fecha: string;
  nota: Nota | null;
  onSaved: () => void;
}

export default function CellNote({ obraId, fecha, nota, onSaved }: Props) {
  const { user } = useAuthStore();
  const supabase = createClient();
  const [hovered, setHovered] = useState(false);
  const [pinned, setPinned] = useState(false);
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(nota?.texto || "");
  const [saving, setSaving] = useState(false);
  const popupRef = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  // Close pinned popup on outside click
  useEffect(() => {
    if (!pinned) return;
    const handler = (e: MouseEvent) => {
      if (popupRef.current && !popupRef.current.contains(e.target as Node) &&
          containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setPinned(false);
        setEditing(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [pinned]);

  const handleSave = async () => {
    if (!text.trim()) return;
    setSaving(true);
    if (nota) {
      await (supabase.from("planificador_notas") as any).update({
        texto: text.trim(), updated_by: user?.id, updated_at: new Date().toISOString(),
      }).eq("id", nota.id);
    } else {
      await (supabase.from("planificador_notas") as any).insert({
        obra_id: obraId, fecha, texto: text.trim(), created_by: user?.id, updated_by: user?.id,
      });
    }
    setSaving(false);
    setEditing(false);
    onSaved();
  };

  const handleDelete = async () => {
    if (!nota) return;
    await (supabase.from("planificador_notas") as any).delete().eq("id", nota.id);
    setText("");
    setEditing(false);
    setPinned(false);
    onSaved();
  };

  const showPopup = hovered || pinned;
  const formatDate = (d: string) => new Date(d).toLocaleString("es-ES", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

  return (
    <div ref={containerRef} className="relative inline-flex"
      onMouseEnter={() => setHovered(true)} onMouseLeave={() => setHovered(false)}>
      {/* Trigger icon */}
      {nota ? (
        <button onClick={(e) => { e.stopPropagation(); setPinned(!pinned); }}
          className="p-0.5 text-amber-500 hover:text-amber-600 transition-colors">
          <FileText className="w-3 h-3" />
        </button>
      ) : (
        <button onClick={(e) => { e.stopPropagation(); setPinned(true); setEditing(true); setText(""); }}
          className="p-0.5 text-surface-300 hover:text-surface-500 opacity-0 group-hover:opacity-100 transition-all">
          <Plus className="w-2.5 h-2.5" />
        </button>
      )}

      {/* Popup */}
      {showPopup && (nota || editing) && (
        <div ref={popupRef} onClick={(e) => e.stopPropagation()}
          className="absolute z-50 bottom-full left-0 mb-1 w-56 bg-white rounded-lg shadow-lg border border-surface-200 overflow-hidden animate-scale-in">
          {editing ? (
            <div className="p-2 space-y-1.5">
              <textarea value={text} onChange={(e) => setText(e.target.value)} autoFocus rows={2} maxLength={200}
                placeholder="Nota..."
                className="w-full text-xs px-2 py-1.5 bg-surface-50 border border-surface-200 rounded-md resize-none focus:outline-none focus:ring-1 focus:ring-brand-500/30" />
              <div className="flex items-center justify-between">
                <span className="text-[9px] text-surface-400">{text.length}/200</span>
                <div className="flex gap-1">
                  {nota && <button onClick={handleDelete} className="px-1.5 py-0.5 text-[10px] text-red-600 hover:bg-red-50 rounded">Eliminar</button>}
                  <button onClick={() => { setEditing(false); setPinned(false); }} className="px-1.5 py-0.5 text-[10px] text-surface-500 hover:bg-surface-100 rounded">Cancelar</button>
                  <button onClick={handleSave} disabled={saving || !text.trim()}
                    className="flex items-center gap-0.5 px-2 py-0.5 text-[10px] font-medium text-white bg-brand-500 rounded hover:bg-brand-600 disabled:opacity-60">
                    {saving ? <Loader2 className="w-2.5 h-2.5 animate-spin" /> : <Save className="w-2.5 h-2.5" />}
                  </button>
                </div>
              </div>
            </div>
          ) : nota ? (
            <div className="p-2">
              <p className="text-xs text-surface-900 leading-relaxed">{nota.texto}</p>
              <div className="flex items-center justify-between mt-1.5 pt-1.5 border-t border-surface-100">
                <span className="text-[9px] text-surface-400">{nota.creator_nombre || "—"} · {formatDate(nota.updated_at)}</span>
                {pinned && (
                  <button onClick={() => { setEditing(true); setText(nota.texto); }}
                    className="text-[10px] text-brand-600 hover:underline">Editar</button>
                )}
              </div>
            </div>
          ) : null}
        </div>
      )}
    </div>
  );
}
