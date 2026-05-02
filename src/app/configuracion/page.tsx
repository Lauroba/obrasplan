"use client";

import { useState, useEffect, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import { Settings, Loader2, Save, ShieldCheck, Check, X } from "lucide-react";
import { cn } from "@/lib/utils/cn";

const PANTALLAS = [
  { id: "planificacion", label: "Planificación", permisos: ["ver", "asignar"] },
  { id: "obras", label: "Obras", permisos: ["ver", "crear", "editar"] },
  { id: "partes", label: "Partes", permisos: ["ver", "crear", "editar", "eliminar"] },
  { id: "maestros", label: "Maestros", permisos: ["ver", "crear", "editar", "eliminar"] },
  { id: "tareas", label: "Tareas", permisos: ["ver", "crear", "editar", "eliminar"] },
  { id: "logs", label: "Logs", permisos: ["ver"] },
  { id: "configuracion", label: "Configuración", permisos: ["ver"] },
];

const PERMISO_LABELS: Record<string, string> = { ver: "Ver", crear: "Crear", editar: "Editar", eliminar: "Eliminar", asignar: "Asignar" };

interface UserPermData {
  userId: string;
  nombre: string;
  email: string;
  role: string;
  permisos: Record<string, Record<string, boolean>>;
}

export default function ConfiguracionPage() {
  const { user } = useAuthStore();
  const supabase = createClient();
  const [users, setUsers] = useState<UserPermData[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [selectedUser, setSelectedUser] = useState<string>("");

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [usersR, permR] = await Promise.all([
      supabase.from("users").select("id, nombre, email, role").order("nombre"),
      supabase.from("user_permisos").select("*"),
    ]);

    const usersData = (usersR.data || []).filter((u: any) => u.role !== "admin");
    const permsData = (permR.data || []) as any[];

    const result: UserPermData[] = usersData.map((u: any) => {
      const permisos: Record<string, Record<string, boolean>> = {};
      PANTALLAS.forEach((p) => {
        const existing = permsData.find((perm: any) => perm.user_id === u.id && perm.pantalla === p.id);
        permisos[p.id] = {
          ver: existing?.ver ?? true,
          crear: existing?.crear ?? true,
          editar: existing?.editar ?? true,
          eliminar: existing?.eliminar ?? true,
          asignar: existing?.asignar ?? true,
        };
      });
      return { userId: u.id, nombre: u.nombre, email: u.email, role: u.role, permisos };
    });

    setUsers(result);
    if (result.length > 0 && !selectedUser) setSelectedUser(result[0].userId);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const togglePerm = (userId: string, pantalla: string, permiso: string) => {
    setUsers((prev) => prev.map((u) => {
      if (u.userId !== userId) return u;
      return {
        ...u,
        permisos: {
          ...u.permisos,
          [pantalla]: { ...u.permisos[pantalla], [permiso]: !u.permisos[pantalla][permiso] },
        },
      };
    }));
    setSaved(false);
  };

  const toggleAllForUser = (userId: string, value: boolean) => {
    setUsers((prev) => prev.map((u) => {
      if (u.userId !== userId) return u;
      const permisos: Record<string, Record<string, boolean>> = {};
      PANTALLAS.forEach((p) => {
        permisos[p.id] = {};
        p.permisos.forEach((perm) => { permisos[p.id][perm] = value; });
      });
      return { ...u, permisos };
    }));
    setSaved(false);
  };

  const handleSave = async () => {
    setSaving(true);
    const currentUser = users.find((u) => u.userId === selectedUser);
    if (!currentUser) { setSaving(false); return; }

    for (const pantalla of PANTALLAS) {
      const perms = currentUser.permisos[pantalla.id];
      await (supabase.from("user_permisos") as any).upsert({
        user_id: currentUser.userId,
        pantalla: pantalla.id,
        ver: perms.ver ?? false,
        crear: perms.crear ?? false,
        editar: perms.editar ?? false,
        eliminar: perms.eliminar ?? false,
        asignar: perms.asignar ?? false,
      }, { onConflict: "user_id,pantalla" });
    }

    setSaving(false);
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  if (user && user.role !== "admin") {
    return <AppLayout><div className="text-center py-20"><ShieldCheck className="w-10 h-10 text-surface-300 mx-auto mb-3" /><p className="text-sm text-surface-500">Solo los administradores pueden acceder a la configuración</p></div></AppLayout>;
  }

  const selectedUserData = users.find((u) => u.userId === selectedUser);

  return (
    <AppLayout>
      <div className="max-w-5xl mx-auto animate-fade-in">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-lg bg-surface-100 flex items-center justify-center"><Settings className="w-5 h-5 text-surface-600" /></div>
          <div><h1 className="text-xl font-display font-bold text-surface-900">Configuración</h1><p className="text-sm text-surface-500">Permisos de acceso por usuario</p></div>
        </div>

        {loading ? (
          <div className="flex justify-center py-20"><Loader2 className="w-8 h-8 text-brand-500 animate-spin" /></div>
        ) : users.length === 0 ? (
          <div className="card p-6 text-center py-12"><ShieldCheck className="w-8 h-8 text-surface-300 mx-auto mb-2" /><p className="text-sm text-surface-500">No hay usuarios estándar. Los administradores tienen acceso completo.</p></div>
        ) : (
          <div className="space-y-4">
            {/* User selector */}
            <div className="card p-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <label className="text-sm font-medium text-surface-700">Usuario:</label>
                  <select value={selectedUser} onChange={(e) => setSelectedUser(e.target.value)}
                    className="px-3 py-2 text-sm bg-surface-50 border border-surface-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/20 min-w-[200px]">
                    {users.map((u) => <option key={u.userId} value={u.userId}>{u.nombre} ({u.email})</option>)}
                  </select>
                </div>
                <div className="flex items-center gap-2">
                  {selectedUserData && (
                    <>
                      <button onClick={() => toggleAllForUser(selectedUser, true)}
                        className="px-3 py-1.5 text-xs font-medium text-emerald-700 bg-emerald-50 rounded-lg hover:bg-emerald-100">
                        Activar todo
                      </button>
                      <button onClick={() => toggleAllForUser(selectedUser, false)}
                        className="px-3 py-1.5 text-xs font-medium text-red-700 bg-red-50 rounded-lg hover:bg-red-100">
                        Desactivar todo
                      </button>
                    </>
                  )}
                  <button onClick={handleSave} disabled={saving}
                    className={cn("flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg transition-all",
                      saved ? "text-emerald-700 bg-emerald-100" : "text-white bg-brand-500 hover:bg-brand-600 disabled:opacity-60")}>
                    {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : saved ? <Check className="w-4 h-4" /> : <Save className="w-4 h-4" />}
                    {saved ? "Guardado" : "Guardar permisos"}
                  </button>
                </div>
              </div>
            </div>

            {/* Permissions table */}
            {selectedUserData && (
              <div className="card overflow-hidden">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="bg-surface-50 border-b border-surface-200">
                      <th className="text-left py-3 px-4 text-[10px] font-semibold text-surface-400 uppercase w-[180px]">Pantalla</th>
                      {["ver", "crear", "editar", "eliminar", "asignar"].map((p) => (
                        <th key={p} className="text-center py-3 px-3 text-[10px] font-semibold text-surface-400 uppercase">{PERMISO_LABELS[p]}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {PANTALLAS.map((pantalla) => (
                      <tr key={pantalla.id} className="border-b border-surface-50 hover:bg-surface-50/50">
                        <td className="py-3 px-4 font-medium text-surface-900">{pantalla.label}</td>
                        {["ver", "crear", "editar", "eliminar", "asignar"].map((perm) => {
                          const available = pantalla.permisos.includes(perm);
                          const checked = selectedUserData.permisos[pantalla.id]?.[perm] ?? false;
                          return (
                            <td key={perm} className="text-center py-3 px-3">
                              {available ? (
                                <button onClick={() => togglePerm(selectedUserData.userId, pantalla.id, perm)}
                                  className={cn("w-8 h-8 rounded-lg flex items-center justify-center mx-auto transition-all",
                                    checked ? "bg-emerald-100 text-emerald-600 hover:bg-emerald-200" : "bg-red-50 text-red-400 hover:bg-red-100")}>
                                  {checked ? <Check className="w-4 h-4" /> : <X className="w-4 h-4" />}
                                </button>
                              ) : (
                                <span className="text-surface-200">—</span>
                              )}
                            </td>
                          );
                        })}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            <p className="text-xs text-surface-400 text-center">Los administradores tienen acceso completo a todas las pantallas y no aparecen en esta lista.</p>
          </div>
        )}
      </div>
    </AppLayout>
  );
}
