"use client";

import { useAuthStore } from "@/hooks/useAuth";
import { useLayoutStore } from "@/hooks/useLayout";
import { createClient } from "@/lib/supabase/client";
import { useRouter } from "next/navigation";
import { Bell, LogOut, User as UserIcon, Wifi, WifiOff, Menu } from "lucide-react";
import { useState, useEffect } from "react";

export default function Topbar() {
  const { user } = useAuthStore();
  const { setMobileMenu } = useLayoutStore();
  const router = useRouter();
  const [isOnline, setIsOnline] = useState(true);
  const [showUserMenu, setShowUserMenu] = useState(false);

  useEffect(() => {
    setIsOnline(navigator.onLine);
    const on = () => setIsOnline(true);
    const off = () => setIsOnline(false);
    window.addEventListener("online", on);
    window.addEventListener("offline", off);
    return () => { window.removeEventListener("online", on); window.removeEventListener("offline", off); };
  }, []);

  const handleLogout = async () => {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/login");
  };

  const roleLabels: Record<string, string> = { admin: "Administrador", lectura: "Solo lectura", partes: "Partes" };

  return (
    <header className="sticky top-0 z-30 h-14 bg-white/80 backdrop-blur-lg border-b border-surface-200 flex items-center justify-end px-4 lg:px-6 gap-2">
      {/* Mobile menu toggle */}
      <button onClick={() => setMobileMenu(true)} className="mr-auto p-2 rounded-lg text-surface-500 hover:bg-surface-100 lg:hidden">
        <Menu className="w-5 h-5" />
      </button>

      {/* Online status */}
      <div className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-medium">
        {isOnline ? (
          <><Wifi className="w-3.5 h-3.5 text-emerald-500" /><span className="text-emerald-600 hidden sm:inline">Online</span></>
        ) : (
          <><WifiOff className="w-3.5 h-3.5 text-amber-500" /><span className="text-amber-600 hidden sm:inline">Offline</span></>
        )}
      </div>

      {/* Notifications */}
      <button className="relative p-2 rounded-lg text-surface-400 hover:bg-surface-100 hover:text-surface-600 transition-colors">
        <Bell className="w-4.5 h-4.5" />
      </button>

      {/* User menu */}
      <div className="relative">
        <button onClick={() => setShowUserMenu(!showUserMenu)}
          className="flex items-center gap-2.5 pl-3 pr-2 py-1.5 rounded-lg hover:bg-surface-100 transition-colors">
          <div className="text-right hidden sm:block">
            <p className="text-sm font-medium text-surface-900 leading-tight">{user?.nombre || "Usuario"}</p>
            <p className="text-[11px] text-surface-400">{roleLabels[user?.role || "partes"]}</p>
          </div>
          <div className="w-8 h-8 rounded-full bg-brand-500 flex items-center justify-center text-white text-sm font-semibold">
            {user?.nombre?.charAt(0)?.toUpperCase() || "U"}
          </div>
        </button>

        {showUserMenu && (
          <>
            <div className="fixed inset-0 z-40" onClick={() => setShowUserMenu(false)} />
            <div className="absolute right-0 top-full mt-2 w-56 bg-white rounded-xl border border-surface-200 shadow-lg z-50 py-1.5 animate-scale-in">
              <div className="px-4 py-2.5 border-b border-surface-100">
                <p className="text-sm font-medium text-surface-900">{user?.nombre}</p>
                <p className="text-xs text-surface-400">{user?.email}</p>
              </div>
              <button onClick={() => { setShowUserMenu(false); router.push("/configuracion"); }}
                className="w-full flex items-center gap-2.5 px-4 py-2.5 text-sm text-surface-600 hover:bg-surface-50 transition-colors">
                <UserIcon className="w-4 h-4" />Mi perfil
              </button>
              <button onClick={handleLogout}
                className="w-full flex items-center gap-2.5 px-4 py-2.5 text-sm text-red-600 hover:bg-red-50 transition-colors">
                <LogOut className="w-4 h-4" />Cerrar sesión
              </button>
            </div>
          </>
        )}
      </div>
    </header>
  );
}
